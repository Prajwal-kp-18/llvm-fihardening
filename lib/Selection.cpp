//===- Selection.cpp - Which functions and instructions to harden ---------===//

#include "FIHarden.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/LineIterator.h"
#include "llvm/Support/MemoryBuffer.h"

using namespace llvm;

#define DEBUG_TYPE "fi-harden"

static cl::opt<std::string> AllowlistFile(
    "fi-harden-allowlist",
    cl::desc("File of functions to harden, one IR name (mangled for C++) per "
             "line; '#' starts a comment line"),
    cl::value_desc("file"));

// The runtime's trap handler: a check inside it would trap into itself.
static constexpr StringLiteral TrapHandler = "fi_trap";

// Functions marked __attribute__((annotate("fi_harden"))). Clang lists them in
// llvm.global.annotations as {function, annotation string, file, line, args}.
static void addAnnotated(Module &M, SmallPtrSetImpl<Function *> &Out) {
  GlobalVariable *GV = M.getNamedGlobal("llvm.global.annotations");
  if (!GV || !GV->hasInitializer())
    return;
  auto *Entries = dyn_cast<ConstantArray>(GV->getInitializer());
  if (!Entries)
    return;
  for (Value *E : Entries->operands()) {
    auto *Entry = dyn_cast<ConstantStruct>(E);
    if (!Entry || Entry->getNumOperands() < 2)
      continue;
    auto *F = dyn_cast<Function>(Entry->getOperand(0)->stripPointerCasts());
    auto *Str =
        dyn_cast<GlobalVariable>(Entry->getOperand(1)->stripPointerCasts());
    if (!F || !Str || !Str->hasInitializer())
      continue;
    auto *Text = dyn_cast<ConstantDataArray>(Str->getInitializer());
    if (Text && Text->isCString() && Text->getAsCString() == "fi_harden")
      Out.insert(F);
  }
}

// Names absent from this module are fine: one list serves every source file.
static void addAllowlisted(Module &M, SmallPtrSetImpl<Function *> &Out) {
  if (AllowlistFile.empty())
    return;
  auto Buf = MemoryBuffer::getFile(AllowlistFile.getValue(), /*IsText=*/true);
  if (!Buf)
    reportFatalUsageError(Twine("fi-harden: cannot read allowlist '") +
                          AllowlistFile.getValue() +
                          "': " + Buf.getError().message());
  for (line_iterator L(**Buf, /*SkipBlanks=*/true, '#'); !L.is_at_eof(); ++L)
    if (Function *F = M.getFunction(L->trim()))
      Out.insert(F);
}

SmallVector<Function *> fiharden::selectFunctions(Module &M, bool All) {
  SmallPtrSet<Function *, 8> Marked;
  if (!All) {
    addAnnotated(M, Marked);
    addAllowlisted(M, Marked);
  }
  SmallVector<Function *> Selected;
  for (Function &F : M)
    if (!F.isDeclaration() && F.getName() != TrapHandler &&
        (All || Marked.contains(&F)))
      Selected.push_back(&F);
  return Selected;
}

// Why countermeasures may not duplicate or re-evaluate I; empty if they may.
// The first six are absolute. A documented exception to the last two (say,
// for ordinary loads) belongs between them and the six.
static StringRef skipReason(const Instruction &I) {
  if (I.isEHPad())
    return "EH pad";
  if (isa<InvokeInst>(I))
    return "invoke";
  if (isa<CallBrInst>(I))
    return "callbr";
  if (isa<VAArgInst>(I))
    return "va_arg";
  if (I.isAtomic())
    return "atomic";
  if (I.isVolatile())
    return "volatile";
  if (I.mayHaveSideEffects())
    return "side effects";
  if (I.mayReadOrWriteMemory())
    return "reads or writes memory";
  return "";
}

bool fiharden::skipInstruction(Instruction &I, OptimizationRemarkEmitter &ORE) {
  StringRef Why = skipReason(I);
  if (Why.empty())
    return false;
  ORE.emit([&] {
    return OptimizationRemarkMissed(DEBUG_TYPE, "Skipped", &I)
           << I.getOpcodeName() << " left alone: " << Why;
  });
  return true;
}

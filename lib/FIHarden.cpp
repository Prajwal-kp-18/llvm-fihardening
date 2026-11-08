//===- FIHarden.cpp - Fault-injection hardening plugin entry point --------===//
//
// Registers fi-harden, a module pass because function selection reads the
// module-level llvm.global.annotations, and three inspection passes:
// fi-harden-skips reports every instruction countermeasures must leave alone,
// fi-harden-copies runs every compare on opaque copies of its operands, and
// fi-harden-checks turns hand-written fi.check calls into checks. Under clang
// it also keeps marked functions out of line, before the inliner.
//
// opt:   -load-pass-plugin=FIHarden.so -passes='fi-harden<all;branches;compares>'
// clang: -fpass-plugin=FIHarden.so [-mllvm -fi-harden=all,branches,compares]
//
//===----------------------------------------------------------------------===//

#include "FIHarden.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Plugins/PassPlugin.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

#define DEBUG_TYPE "fi-harden"

STATISTIC(NumFunctions, "Functions selected for hardening");

static cl::list<std::string> ClangParams(
    "fi-harden", cl::CommaSeparated,
    cl::desc("fi-harden parameters under clang -fpass-plugin, as in "
             "fi-harden<...>: all, allowlist=<file>, trap=call, branches, "
             "compares"));

namespace {

struct FIHardenOptions {
  bool All = false;      // every defined function, not just the marked ones
  std::string Allowlist; // file naming more functions to harden
  bool TrapCall = false; // a failed check calls fi_trap before trapping
  bool Branches = false;
  bool Compares = false;

  // The countermeasures, not All.
  void print(raw_ostream &OS, StringRef Sep = ", ") const {
    ListSeparator LS(Sep);
    if (Branches)
      OS << LS << "branches";
    if (Compares)
      OS << LS << "compares";
  }
};

// Parses the text between the <> of fi-harden<all;branches;compares>. Naming
// no countermeasure means every countermeasure. The allowlist is a parameter,
// not a cl::opt, because opt in LLVM 24 parses its options before it loads
// plugins.
Expected<FIHardenOptions> parseOptions(StringRef Params) {
  FIHardenOptions Opts;
  if (!Params.empty())
    for (StringRef P : split(Params, ';')) {
      StringRef File = P;
      if (P == "all")
        Opts.All = true;
      else if (P == "branches")
        Opts.Branches = true;
      else if (P == "compares")
        Opts.Compares = true;
      else if (P == "trap=call")
        Opts.TrapCall = true;
      else if (File.consume_front("allowlist=") && !File.empty())
        Opts.Allowlist = File.str();
      else
        return createStringError(
            "invalid fi-harden parameter '" + P +
            "'; expected all, allowlist=<file>, trap=call, branches or "
            "compares");
    }
  if (!Opts.Branches && !Opts.Compares)
    Opts.Branches = Opts.Compares = true;
  return Opts;
}

// The parameters given under clang, as -mllvm -fi-harden=a,b.
FIHardenOptions clangOptions() {
  auto Opts = parseOptions(join(ClangParams, ";"));
  if (!Opts)
    reportFatalUsageError(Opts.takeError());
  return *Opts;
}

// Required: hardening must also run on optnone functions and at -O0.
class FIHardenPass : public RequiredPassInfoMixin<FIHardenPass> {
  FIHardenOptions Opts;
  bool PreLink; // the compile step of -flto, which link-time IR passes follow

public:
  explicit FIHardenPass(FIHardenOptions Opts, bool PreLink = false)
      : Opts(Opts), PreLink(PreLink) {}

  PreservedAnalyses run(Module &M, ModuleAnalysisManager &MAM) {
    FunctionAnalysisManager &FAM =
        MAM.getResult<FunctionAnalysisManagerModuleProxy>(M).getManager();
    auto Selected = fiharden::selectFunctions(M, Opts.All, Opts.Allowlist);
    // Link-time GVN rewrites a re-check's copies from the edge's equality,
    // so the true edge compares a with itself (branches.ll shows the same
    // with -O2 after hardening).
    if (PreLink && !Selected.empty())
      reportFatalUsageError("fi-harden doesn't support -flto: link-time "
                            "optimisation would weaken the checks");
    bool Changed = false;
    for (Function *F : Selected) {
      ++NumFunctions;
      std::string Msg;
      raw_string_ostream OS(Msg);
      Opts.print(OS);
      LLVM_DEBUG(dbgs() << DEBUG_TYPE << ": " << F->getName() << ": " << Msg
                        << "\n");
      auto &ORE = FAM.getResult<OptimizationRemarkEmitterAnalysis>(*F);
      ORE.emit([&] {
        return OptimizationRemark(DEBUG_TYPE, "Selected", F)
               << "hardening " << F->getName() << ": " << Msg;
      });
      fiharden::Checker C(*F, Opts.TrapCall);
      if (Opts.Branches)
        Changed |= fiharden::hardenBranches(*F, C, ORE);
      if (Opts.Compares)
        Changed |= fiharden::hardenCompares(*F, C, ORE);
    }
    return Changed ? PreservedAnalyses::none() : PreservedAnalyses::all();
  }

  // Prints as fi-harden<...>, so -print-pipeline-passes output can be fed
  // back to opt.
  void printPipeline(raw_ostream &OS, function_ref<StringRef(StringRef)>) {
    OS << "fi-harden<" << (Opts.All ? "all;" : "");
    if (!Opts.Allowlist.empty())
      OS << "allowlist=" << Opts.Allowlist << ';';
    if (Opts.TrapCall)
      OS << "trap=call;";
    Opts.print(OS, ";");
    OS << '>';
  }
};

// Keeps the marked and allowlisted functions out of line. Hardening runs at
// OptimizerLast, after the inliner: a marked function inlined into an
// unmarked caller would leave its decision there, unhardened. With all, every
// caller is hardened too, so inlining is fine.
struct KeepOutOfLinePass : RequiredPassInfoMixin<KeepOutOfLinePass> {
  FIHardenOptions Opts;

  PreservedAnalyses run(Module &M, ModuleAnalysisManager &) {
    if (Opts.All)
      return PreservedAnalyses::all();
    auto Selected = fiharden::selectFunctions(M, false, Opts.Allowlist);
    for (Function *F : Selected) {
      if (F->hasFnAttribute(Attribute::AlwaysInline))
        reportFatalUsageError("fi-harden: '" + F->getName() +
                              "' is always_inline, but a hardened function "
                              "must stay out of line");
      F->addFnAttr(Attribute::NoInline);
    }
    return Selected.empty() ? PreservedAnalyses::all()
                            : PreservedAnalyses::none();
  }
};

// Emits a missed remark for every instruction countermeasures must leave
// alone, so the skip rules can be tested and inspected on their own.
struct SkipReportPass : RequiredPassInfoMixin<SkipReportPass> {
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &FAM) {
    auto &ORE = FAM.getResult<OptimizationRemarkEmitterAnalysis>(F);
    for (Instruction &I : instructions(F))
      fiharden::skipInstruction(I, ORE);
    return PreservedAnalyses::all();
  }
};

// Feeds every compare opaque copies of its operands, so the barrier can be
// tested on its own: icmp eq %a, %a then survives opt -O2 and llc -O2.
struct CopyComparesPass : RequiredPassInfoMixin<CopyComparesPass> {
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &FAM) {
    auto &ORE = FAM.getResult<OptimizationRemarkEmitterAnalysis>(F);
    for (Instruction &I : instructions(F))
      if (isa<CmpInst>(I) && !fiharden::skipInstruction(I, ORE)) {
        IRBuilder<> B(&I);
        for (Use &Op : I.operands())
          Op.set(fiharden::opaqueCopy(B, Op));
      }
    return PreservedAnalyses::none();
  }
};

// Turns each call fi.check(i1 %cond, i1 %expected) into a check that traps
// unless %cond is %expected, so the trap path can be tested on its own.
struct HandWrittenChecksPass : RequiredPassInfoMixin<HandWrittenChecksPass> {
  FIHardenOptions Opts;

  PreservedAnalyses run(Function &F, FunctionAnalysisManager &) {
    SmallVector<CallInst *> Marks;
    for (Instruction &I : instructions(F))
      if (auto *CI = dyn_cast<CallInst>(&I))
        if (Function *Callee = CI->getCalledFunction();
            Callee && Callee->getName() == "fi.check")
          Marks.push_back(CI);
    fiharden::Checker C(F, Opts.TrapCall);
    for (CallInst *CI : Marks) {
      C.trapUnless(CI->getArgOperand(0),
                   cast<ConstantInt>(CI->getArgOperand(1))->isOne(), CI);
      CI->eraseFromParent();
    }
    return Marks.empty() ? PreservedAnalyses::all() : PreservedAnalyses::none();
  }
};

} // namespace

extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "FIHarden", LLVM_VERSION_STRING,
          [](PassBuilder &PB) {
            PB.registerPipelineParsingCallback(
                [](StringRef Name, ModulePassManager &MPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (!PassBuilder::checkParametrizedPassName(Name,
                                                              "fi-harden"))
                    return false;
                  auto Opts = PassBuilder::parsePassParameters(
                      parseOptions, Name, "fi-harden");
                  if (!Opts)
                    reportFatalUsageError(Opts.takeError());
                  MPM.addPass(FIHardenPass(*Opts));
                  return true;
                });
            PB.registerPipelineParsingCallback(
                [](StringRef Name, FunctionPassManager &FPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name == "fi-harden-skips")
                    FPM.addPass(SkipReportPass());
                  else if (Name == "fi-harden-copies")
                    FPM.addPass(CopyComparesPass());
                  else if (PassBuilder::checkParametrizedPassName(
                               Name, "fi-harden-checks")) {
                    auto Opts = PassBuilder::parsePassParameters(
                        parseOptions, Name, "fi-harden-checks");
                    if (!Opts)
                      reportFatalUsageError(Opts.takeError());
                    FPM.addPass(HandWrittenChecksPass{{}, *Opts});
                  } else
                    return false;
                  return true;
                });
            // Before the inliner, at -O0 too (always_inline).
            PB.registerPipelineStartEPCallback(
                [](ModulePassManager &MPM, OptimizationLevel) {
                  MPM.addPass(KeepOutOfLinePass{{}, clangOptions()});
                });
            // After all IR optimisation, so no IR pass can merge or fold
            // the redundancy away. The backend still runs after this. The
            // ThinLTO link step's OptimizerLast is after all of it too.
            // ponytail: -flto is refused; harden in the link step (full LTO
            // has no OptimizerLast there) to support it.
            PB.registerOptimizerLastEPCallback(
                [](ModulePassManager &MPM, OptimizationLevel,
                   ThinOrFullLTOPhase Phase) {
                  MPM.addPass(FIHardenPass(
                      clangOptions(),
                      Phase == ThinOrFullLTOPhase::ThinLTOPreLink ||
                          Phase == ThinOrFullLTOPhase::FullLTOPreLink));
                });
          }};
}

//===- Check.cpp - Inline checks and the trap block -----------------------===//
//
// A check is a compare and a branch to the function's trap block: no call on
// the check path, so skipping one instruction can't disable it. The trap
// block is call @llvm.trap + unreachable, legal because llvm.trap doesn't
// return; the old error blocks put unreachable after a call that did, so the
// optimizer deleted the checks as dead.
//
// One trap block per function, because merging trap blocks is harmless: with
// one block, one per check, or tail merging off, llc -O2 keeps every compare
// and every branch on AArch64 and Thumb-2, and it tail-merges separate trap
// blocks into one anyway. The one way merging hurts is Thumb-2 if-conversion:
// when a check falls through into another and both are just cmp + bne to the
// same trap, they become cmp; it eq; cmpeq; bne, one branch a single skip
// disables. A block holding opaque copies can't be predicated, so a check's
// copies go in its block. llc's own SimplifyCFG still hoists copies that every
// successor starts with, as both edges of a re-checked branch do; that's
// harmless there, since each of those checks continues to a successor of the
// original branch, never into another check.
//
//===----------------------------------------------------------------------===//

#include "FIHarden.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/IR/Module.h"

using namespace llvm;

void fiharden::Checker::trapUnless(Value *Cond, bool Expected,
                                   Instruction *Before) {
  if (!Trap) {
    Trap = BasicBlock::Create(F.getContext(), "fi.trap", &F);
    IRBuilder<> B(Trap);
    Module &M = *F.getParent();
    // Skipping the call, or a handler that returns, still traps.
    if (CallHandler)
      B.CreateCall(M.getOrInsertFunction("fi_trap", B.getVoidTy()))
          ->setDoesNotThrow();
    B.CreateCall(Intrinsic::getOrInsertDeclaration(&M, Intrinsic::trap));
    B.CreateUnreachable();
  }
  BasicBlock *Head = Before->getParent();
  DebugLoc Loc = Before->getDebugLoc();
  // Before a br X, there's nothing to split off: branch to X or the trap.
  auto *Br = dyn_cast<UncondBrInst>(Before);
  BasicBlock *Ok =
      Br ? Br->getSuccessor() : Head->splitBasicBlock(Before, "fi.ok");
  Head->getTerminator()->eraseFromParent();
  CondBrInst::Create(Cond, Expected ? Ok : Trap, Expected ? Trap : Ok, Head)
      ->setDebugLoc(Loc);
}

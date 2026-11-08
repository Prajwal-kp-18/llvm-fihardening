//===- BranchHardening.cpp - Countermeasure A: re-check both edges --------===//
//
// After br %c, T, F, each edge gets a block that recomputes %c from opaque
// copies and traps unless it matches the edge: true on the way to T, false on
// the way to F. It's GCC's -fharden-conditional-branches. It catches a skipped
// or inverted branch and a corrupted flag, and favours neither edge.
//
// A compare is re-emitted with the same predicate, so NaN needs no special
// case; constant operands stay immediates. Any other condition (a load, call,
// argument, or an and of compares) is checked through an opaque copy of the i1
// itself, which still catches a skipped or inverted branch but not a fault in
// computing the i1. switch is left alone, as GCC does: each case edge would
// need its own compare and the default edge one per case. select conditions
// are countermeasure B's.
//
// llc tail-merges identical check blocks: an unrolled loop's false edges can
// share one. Each branch still reaches a re-check of the registers it
// compared, but counting check blocks in the binary undercounts.
//
// At -O2, a && b && c reaches here as one and of compares, so it gets the
// weaker copied-i1 check. Each compare in the and is countermeasure B's,
// which checks it against its inverse.
// ponytail: with branches but not compares, a fault inside the condition (an
// AArch64 ccmp chain) goes unchecked. Recompute each compare of the and/or
// tree here if branches alone must cover it.
//
//===----------------------------------------------------------------------===//

#include "FIHarden.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"

using namespace llvm;

#define DEBUG_TYPE "fi-harden"

STATISTIC(NumBranches, "Branches re-checked on both edges");

// The condition, recomputed from opaque copies at the end of Edge. Cmp is the
// compare to re-emit, or null to copy Cond itself.
static Value *recompute(Value *Cond, CmpInst *Cmp, BasicBlock *Edge) {
  IRBuilder<> B(Edge->getTerminator());
  if (!Cmp)
    return fiharden::opaqueCopy(B, Cond);
  Instruction *Again = Cmp->clone();
  for (Use &Op : Again->operands())
    if (!isa<Constant>(Op))
      Op.set(fiharden::opaqueCopy(B, Op));
  return B.Insert(Again, Cmp->getName() + ".again");
}

bool fiharden::hardenBranches(Function &F, Checker &C,
                              OptimizationRemarkEmitter &ORE) {
  SmallVector<CondBrInst *> Branches;
  for (BasicBlock &BB : F) {
    Instruction *T = BB.getTerminator();
    if (auto *Br = dyn_cast<CondBrInst>(T)) {
      // A constant condition has nothing to check; a branch with one target
      // nothing to protect.
      if (!isa<Constant>(Br->getCondition()) &&
          Br->getSuccessor(0) != Br->getSuccessor(1))
        Branches.push_back(Br);
    } else if (isa<SwitchInst>(T)) {
      ORE.emit([&] {
        return OptimizationRemarkMissed(DEBUG_TYPE, "Switch", T)
               << "switch left alone: only conditional branches are "
                  "re-checked";
      });
    }
  }

  for (CondBrInst *Br : Branches) {
    Value *Cond = Br->getCondition();
    auto *Cmp = dyn_cast<CmpInst>(Cond);
    if (Cmp && skipInstruction(*Cmp, ORE))
      Cmp = nullptr;
    BasicBlock *From = Br->getParent();
    for (unsigned Succ : {0u, 1u}) { // successor 0 is taken when Cond is true
      BasicBlock *Edge =
          SplitEdge(From, Br->getSuccessor(Succ), nullptr, nullptr, nullptr,
                    Succ ? "fi.false" : "fi.true");
      C.trapUnless(recompute(Cond, Cmp, Edge), /*Expected=*/Succ == 0,
                   Edge->getTerminator());
    }
    ++NumBranches;
    ORE.emit([&] {
      return OptimizationRemark(DEBUG_TYPE, "Branch", Br)
             << "branch re-checked on both edges: "
             << (Cmp ? std::string(Cmp->getOpcodeName()) +
                           " recomputed from copies"
                     : std::string("condition copied"));
    });
  }
  return !Branches.empty();
}

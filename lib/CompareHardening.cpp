//===- CompareHardening.cpp - Countermeasure B: check against the inverse -===//
//
// After %c = icmp P a, b, whose result is used as a value (returned, stored,
// a select condition, an operand of an and), the inverse predicate is computed
// from opaque copies of a and b, and the code traps unless %c equals the
// negated inverse. It's GCC's -fharden-compares. getInversePredicate gets NaN
// right: olt's inverse is uge, so a NaN gives false, then true. The inverse
// keeps the compare's flags (nnan, samesign), so both lower the same way.
//
// Those uses then read an opaque copy of %c, the value the check compared.
// Otherwise CodeGenPrepare sinks a fresh compare next to each user in another
// block: on AArch64, return a == b re-ran cmp + cset after the check, and
// skipping that cset went unchecked. Branch uses keep %c: they're
// countermeasure A's, so A and B never check the same use. Compares used only
// by branches are left to A, and run before B, so A's re-checks aren't checked
// again.
//
// The check is "equal to the negated inverse", not "differs from the
// inverse": the same for i1s, but the backend compares whole registers, often
// the very register returned, and only the first catches one left holding
// junk. With "differs", skipping the and w0, w8, #1 that puts the boolean in
// the return register let a wrong PIN through on AArch64 and Thumb-2. The
// inverse is negated through an opaque copy: otherwise the backend folds the
// negation into it and recomputes the original predicate, and a fault that
// zeroes both results would pass.
//
// ponytail: the check protects computing the boolean and the register it's
// checked in, not moving it after the check (into another register or to
// memory). Data-flow duplication (C) covers that.
//
//===----------------------------------------------------------------------===//

#include "FIHarden.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Instructions.h"

using namespace llvm;

#define DEBUG_TYPE "fi-harden"

STATISTIC(NumCompares, "Compares checked against their inverse");

bool fiharden::hardenCompares(Function &F, Checker &C,
                              OptimizationRemarkEmitter &ORE) {
  SmallVector<std::pair<CmpInst *, SmallVector<Use *>>> Compares;
  for (Instruction &I : instructions(F))
    if (auto *Cmp = dyn_cast<CmpInst>(&I)) {
      SmallVector<Use *> Uses;
      for (Use &U : Cmp->uses())
        if (!isa<CondBrInst>(U.getUser()))
          Uses.push_back(&U);
      if (!Uses.empty() && !skipInstruction(*Cmp, ORE))
        Compares.emplace_back(Cmp, std::move(Uses));
    }

  // Last first: splitting after a compare then moves only up to the next
  // check, not the rest of the block, so a block of n compares isn't O(n^2).
  for (auto &Site : reverse(Compares)) {
    CmpInst *Cmp = Site.first;
    IRBuilder<> B(Cmp->getNextNode());
    Value *Copy = opaqueCopy(B, Cmp);
    for (Use *U : Site.second)
      U->set(Copy);
    auto *Inv = cast<CmpInst>(Cmp->clone());
    Inv->setPredicate(Cmp->getInversePredicate());
    for (Use &Op : Inv->operands())
      if (!isa<Constant>(Op))
        Op.set(opaqueCopy(B, Op));
    B.Insert(Inv, Cmp->getName() + ".inv");
    Value *Negated = B.CreateNot(opaqueCopy(B, Inv));
    C.trapUnless(B.CreateICmpEQ(Copy, Negated), /*Expected=*/true,
                 &*B.GetInsertPoint());
  }
  for (auto &Site : Compares) {
    ++NumCompares;
    ORE.emit([&] {
      return OptimizationRemark(DEBUG_TYPE, "Compare", Site.first)
             << Site.first->getOpcodeName() << " checked against its inverse";
    });
  }
  return !Compares.empty();
}

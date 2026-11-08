//===- CompareHardening.cpp - Countermeasure B: check against the inverse -===//
//
// After %c = icmp P a, b, whose result is used as a value (returned, stored,
// a select condition, an operand of an and), the inverse predicate is computed
// from opaque copies of a and b, and the code traps unless the two results
// differ. It's GCC's -fharden-compares. getInversePredicate gets NaN right:
// olt's inverse is uge, so a NaN gives false, then true. The inverse keeps the
// compare's flags (nnan, samesign), so both lower the same way.
//
// Those uses then read an opaque copy of %c, the value the check compared.
// Otherwise CodeGenPrepare sinks a fresh compare next to each user in another
// block: on AArch64, return a == b re-ran cmp + cset after the check, and
// skipping that cset went unchecked. Branch uses keep %c: they're
// countermeasure A's, so A and B never check the same use. Compares used only
// by branches are left to A, and run before B, so A's re-checks aren't checked
// again.
//
// ponytail: the check compares i1s, so it protects computing the boolean, not
// moving it afterwards. A skipped and w0, w8, #1 leaves the return register
// holding whatever it held. Data-flow duplication (C) or a multi-bit encoding
// of the result covers that.
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

  for (auto &Site : Compares) {
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
    C.trapUnless(B.CreateICmpNE(Copy, Inv), /*Expected=*/true,
                 &*B.GetInsertPoint());
    ++NumCompares;
    ORE.emit([&] {
      return OptimizationRemark(DEBUG_TYPE, "Compare", Cmp)
             << Cmp->getOpcodeName() << " checked against its inverse";
    });
  }
  return !Compares.empty();
}

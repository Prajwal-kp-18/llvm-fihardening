//===- OpaqueCopy.cpp - Values the optimizer can't see through ------------===//
//
// An opaque copy is an empty asm sideeffect "", "=r,0" that hands its input
// back: GCC's detach_value() and OpenTitan's launder32(). No pass can prove
// two copies equal, so a check that compares copies isn't folded or merged.
//
// It hides the output, not the input. A pass that runs after the copy is
// inserted may still rewrite its input: on the true edge of br (a == b), GVN
// turns copy(b) into copy(a), and the re-check then compares a with itself.
// That's why fi-harden runs at OptimizerLast, after every IR optimisation.
//
// sideeffect, as in OpenTitan: they saw a plain asm barrier merged during
// register allocation. Every barrier decision is in this file, so changing
// the strategy (say, to an intrinsic) touches nothing else.
//
//===----------------------------------------------------------------------===//

#include "FIHarden.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/InlineAsm.h"
#include "llvm/Support/MathExtras.h"

using namespace llvm;

// The type the asm operand takes for a T: pointers as they are, integers and
// floating point as an integer of a power-of-two width, at least 8 bits (x86
// can't allocate a register for i17). Null for vectors and anything wider than
// 64 bits: wider asm operands span several registers, and AArch64 didn't keep
// all of an i128.
// ponytail: no copies over 64 bits; split them into i64 pieces if 128-bit
// compares (long double on AArch64) need hardening.
static Type *carrier(Type *T) {
  if (T->isPointerTy())
    return T;
  if (!T->isIntegerTy() && !T->isFloatingPointTy())
    return nullptr;
  uint64_t Bits = T->getPrimitiveSizeInBits().getFixedValue();
  if (Bits > 64)
    return nullptr;
  return IntegerType::get(T->getContext(),
                          std::max<uint64_t>(8, PowerOf2Ceil(Bits)));
}

bool fiharden::hasOpaqueCopy(Type *T) { return carrier(T); }

Value *fiharden::opaqueCopy(IRBuilderBase &B, Value *V) {
  Type *T = V->getType();
  Type *C = carrier(T);
  assert(C && "no opaque copy of this type; check hasOpaqueCopy first");
  // Floating point is 16, 32 or 64 bits, so its carrier has the same width.
  Value *In =
      T->isFloatingPointTy() ? B.CreateBitCast(V, C) : B.CreateZExt(V, C);
  auto *Asm = InlineAsm::get(FunctionType::get(C, {C}, false), "", "=r,0",
                             /*hasSideEffects=*/true);
  CallInst *Copy = B.CreateCall(Asm, In);
  Copy->setDoesNotThrow(); // as clang emits it
  if (V->hasName())
    Copy->setName(V->getName() + ".copy");
  return T->isFloatingPointTy() ? B.CreateBitCast(Copy, T)
                                : B.CreateTrunc(Copy, T);
}

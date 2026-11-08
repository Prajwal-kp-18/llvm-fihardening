//===- FIHarden.h - Shared declarations for the fi-harden plugin ----------===//

#ifndef FIHARDEN_H
#define FIHARDEN_H

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

namespace llvm {
class BasicBlock;
class Function;
class IRBuilderBase;
class Instruction;
class Module;
class OptimizationRemarkEmitter;
class Type;
class Value;
} // namespace llvm

namespace fiharden {

/// The defined functions to harden, in module order: those marked
/// __attribute__((annotate("fi_harden"))) or named in the Allowlist file, or
/// every defined function if All. Never the trap handler.
llvm::SmallVector<llvm::Function *>
selectFunctions(llvm::Module &M, bool All, llvm::StringRef Allowlist);

/// True if countermeasures must not duplicate or re-evaluate I. Emits a missed
/// remark with the reason, so no countermeasure can skip silently.
bool skipInstruction(llvm::Instruction &I,
                     llvm::OptimizationRemarkEmitter &ORE);

/// True if opaqueCopy takes values of type T.
bool hasOpaqueCopy(llvm::Type *T);

/// A copy of V, inserted at B, that no optimisation can prove equal to V or
/// to another copy of V. See OpaqueCopy.cpp for what it doesn't hide.
llvm::Value *opaqueCopy(llvm::IRBuilderBase &B, llvm::Value *V);

/// Inserts checks into one function. They share one trap block, made on first
/// use: llvm.trap, after a call to fi_trap if CallHandler.
class Checker {
  llvm::Function &F;
  bool CallHandler;
  llvm::BasicBlock *Trap = nullptr;

public:
  Checker(llvm::Function &F, bool CallHandler)
      : F(F), CallHandler(CallHandler) {}

  /// Splits Before's block at Before: execution continues there if Cond is
  /// Expected and traps otherwise. Cond and the opaque copies it compares must
  /// be in Before's block (see Check.cpp).
  void trapUnless(llvm::Value *Cond, bool Expected, llvm::Instruction *Before);
};

} // namespace fiharden

#endif

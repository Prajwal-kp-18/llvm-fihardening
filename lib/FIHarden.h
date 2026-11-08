//===- FIHarden.h - Shared declarations for the fi-harden plugin ----------===//

#ifndef FIHARDEN_H
#define FIHARDEN_H

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

namespace llvm {
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

} // namespace fiharden

#endif

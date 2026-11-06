//===- FIHarden.h - Shared declarations for the fi-harden plugin ----------===//

#ifndef FIHARDEN_H
#define FIHARDEN_H

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

namespace llvm {
class Function;
class Instruction;
class Module;
class OptimizationRemarkEmitter;
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

} // namespace fiharden

#endif

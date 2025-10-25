#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/InstrTypes.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/IR/InstIterator.h"

using namespace llvm;

namespace {

class FIHardeningPass : public PassInfoMixin<FIHardeningPass> {
public:
  PreservedAnalyses run(Module &M, ModuleAnalysisManager &MAM) {
    for (Function &F : M) {
      if (F.isDeclaration())
        continue;

      unsigned VulnerableCount = 0;
      
      for (BasicBlock &BB : F) {
        bool hasEqualityComparison = false;
        bool hasFunctionCall = false;
        
        // First pass: detect if BB has equality comparison or function call
        for (Instruction &I : BB) {
          if (auto *Cmp = dyn_cast<ICmpInst>(&I)) {
            if (Cmp->isEquality()) {
              hasEqualityComparison = true;
            }
          }
          if (isa<CallInst>(&I) || isa<InvokeInst>(&I)) {
            hasFunctionCall = true;
          }
        }
        
        // Second pass: check for vulnerabilities
        for (Instruction &I : BB) {
          // Check conditional branches
          if (auto *Br = dyn_cast<BranchInst>(&I)) {
            if (Br->isConditional() && !hasEqualityComparison) {
              errs() << "Warning: Conditional branch in function '" << F.getName()
                     << "' lacks redundant condition check (no equality comparison in BB)\n";
              VulnerableCount++;
            }
          }
          
          // Check load/store instructions
          if (isa<LoadInst>(&I) || isa<StoreInst>(&I)) {
            if (!hasFunctionCall) {
              errs() << "Warning: " 
                     << (isa<LoadInst>(&I) ? "Load" : "Store")
                     << " instruction in function '" << F.getName()
                     << "' lacks verification call in BB\n";
              VulnerableCount++;
            }
          }
        }
      }
      
      if (VulnerableCount > 0) {
        errs() << "Function '" << F.getName() 
               << "' has " << VulnerableCount 
               << " potentially vulnerable instruction(s)\n";
      }
    }
    
    // This pass does not modify the IR
    return PreservedAnalyses::all();
  }
  
  static bool isRequired() { return true; }
};

} // anonymous namespace

// Pass registration
extern "C" LLVM_ATTRIBUTE_WEAK ::llvm::PassPluginLibraryInfo
llvmGetPassPluginInfo() {
  return {
    LLVM_PLUGIN_API_VERSION, "FIHardeningPass", LLVM_VERSION_STRING,
    [](PassBuilder &PB) {
      PB.registerPipelineParsingCallback(
        [](StringRef Name, ModulePassManager &MPM,
           ArrayRef<PassBuilder::PipelineElement>) {
          if (Name == "fi-harden") {
            MPM.addPass(FIHardeningPass());
            return true;
          }
          return false;
        }
      );
    }
  };
}

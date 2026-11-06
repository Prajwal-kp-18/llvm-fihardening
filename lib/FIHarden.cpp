//===- FIHarden.cpp - Fault-injection hardening plugin entry point --------===//
//
// Registers one module pass, fi-harden. It's a module pass because function
// selection reads the module-level llvm.global.annotations.
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/Statistic.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Plugins/PassPlugin.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

#define DEBUG_TYPE "fi-harden"

STATISTIC(NumFunctions, "Functions visited");

namespace {

struct FIHardenOptions {
  bool Branches = true;
  bool Compares = true;
};

raw_ostream &operator<<(raw_ostream &OS, const FIHardenOptions &Opts) {
  ListSeparator LS;
  if (Opts.Branches)
    OS << LS << "branches";
  if (Opts.Compares)
    OS << LS << "compares";
  return OS;
}

class FIHardenPass : public PassInfoMixin<FIHardenPass> {
  FIHardenOptions Opts;

public:
  explicit FIHardenPass(FIHardenOptions Opts) : Opts(Opts) {}

  PreservedAnalyses run(Module &M, ModuleAnalysisManager &MAM) {
    FunctionAnalysisManager &FAM =
        MAM.getResult<FunctionAnalysisManagerModuleProxy>(M).getManager();
    for (Function &F : M) {
      if (F.isDeclaration())
        continue;
      ++NumFunctions;
      LLVM_DEBUG(dbgs() << DEBUG_TYPE << ": " << F.getName() << ": " << Opts
                        << "\n");
      FAM.getResult<OptimizationRemarkEmitterAnalysis>(F).emit([&] {
        std::string Msg;
        raw_string_ostream(Msg) << Opts;
        return OptimizationRemark(DEBUG_TYPE, "Countermeasures", &F)
               << "countermeasures: " << Msg;
      });
    }
    return PreservedAnalyses::all();
  }

  // Hardening must also run on optnone functions and at -O0.
  static bool isRequired() { return true; }
};

} // namespace

extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "FIHarden", LLVM_VERSION_STRING,
          [](PassBuilder &PB) {
            PB.registerPipelineParsingCallback(
                [](StringRef Name, ModulePassManager &MPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name != "fi-harden")
                    return false;
                  MPM.addPass(FIHardenPass(FIHardenOptions()));
                  return true;
                });
          }};
}

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
  bool Branches = false;
  bool Compares = false;
};

// Parses the text between the <> of fi-harden<branches;compares>. No
// parameters means every countermeasure.
Expected<FIHardenOptions> parseOptions(StringRef Params) {
  if (Params.empty())
    return FIHardenOptions{true, true};
  FIHardenOptions Opts;
  for (StringRef P : split(Params, ';')) {
    if (P == "branches")
      Opts.Branches = true;
    else if (P == "compares")
      Opts.Compares = true;
    else
      return createStringError("invalid fi-harden parameter '" + P +
                               "'; expected branches or compares");
  }
  return Opts;
}

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
                  if (!PassBuilder::checkParametrizedPassName(Name,
                                                              "fi-harden"))
                    return false;
                  auto Opts = PassBuilder::parsePassParameters(
                      parseOptions, Name, "fi-harden");
                  if (!Opts)
                    reportFatalUsageError(Opts.takeError());
                  MPM.addPass(FIHardenPass(*Opts));
                  return true;
                });
          }};
}

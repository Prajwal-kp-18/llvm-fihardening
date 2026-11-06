//===- FIHarden.cpp - Fault-injection hardening plugin entry point --------===//
//
// Registers one module pass, fi-harden. It's a module pass because function
// selection reads the module-level llvm.global.annotations.
//
// opt:   -load-pass-plugin=FIHarden.so -passes='fi-harden<branches;compares>'
// clang: -fpass-plugin=FIHarden.so [-mllvm -fi-harden-countermeasures=...]
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/Statistic.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Plugins/PassPlugin.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

#define DEBUG_TYPE "fi-harden"

STATISTIC(NumFunctions, "Functions visited");

static cl::list<std::string> ClangCountermeasures(
    "fi-harden-countermeasures", cl::CommaSeparated,
    cl::desc("Countermeasures fi-harden applies under clang -fpass-plugin: "
             "branches, compares (default: all)"));

namespace {

struct FIHardenOptions {
  bool Branches = false;
  bool Compares = false;

  void print(raw_ostream &OS, StringRef Sep = ", ") const {
    ListSeparator LS(Sep);
    if (Branches)
      OS << LS << "branches";
    if (Compares)
      OS << LS << "compares";
  }
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
      LLVM_DEBUG({
        dbgs() << DEBUG_TYPE << ": " << F.getName() << ": ";
        Opts.print(dbgs());
        dbgs() << "\n";
      });
      FAM.getResult<OptimizationRemarkEmitterAnalysis>(F).emit([&] {
        std::string Msg;
        raw_string_ostream OS(Msg);
        Opts.print(OS);
        return OptimizationRemark(DEBUG_TYPE, "Countermeasures", &F)
               << "countermeasures: " << Msg;
      });
    }
    return PreservedAnalyses::all();
  }

  // Prints as fi-harden<branches;compares>, so -print-pipeline-passes output
  // can be fed back to opt.
  void printPipeline(raw_ostream &OS, function_ref<StringRef(StringRef)>) {
    OS << "fi-harden<";
    Opts.print(OS, ";");
    OS << '>';
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
            // After all IR optimisation, so no IR pass can merge or fold
            // the redundancy away. The backend still runs after this.
            // ponytail: LTO runs this in both pre-link and post-link
            // pipelines; decide which one hardens when LTO is supported.
            PB.registerOptimizerLastEPCallback(
                [](ModulePassManager &MPM, OptimizationLevel,
                   ThinOrFullLTOPhase) {
                  auto Opts = parseOptions(join(ClangCountermeasures, ";"));
                  if (!Opts)
                    reportFatalUsageError(Opts.takeError());
                  MPM.addPass(FIHardenPass(*Opts));
                });
          }};
}

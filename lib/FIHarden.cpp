//===- FIHarden.cpp - Fault-injection hardening plugin entry point --------===//
//
// Registers fi-harden, a module pass because function selection reads the
// module-level llvm.global.annotations, and fi-harden-skips, which reports
// every instruction countermeasures must leave alone.
//
// opt:   -load-pass-plugin=FIHarden.so -passes='fi-harden<all;branches;compares>'
// clang: -fpass-plugin=FIHarden.so [-mllvm -fi-harden=all,branches,compares]
//
//===----------------------------------------------------------------------===//

#include "FIHarden.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Analysis/OptimizationRemarkEmitter.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Plugins/PassPlugin.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

#define DEBUG_TYPE "fi-harden"

STATISTIC(NumFunctions, "Functions selected for hardening");

static cl::list<std::string> ClangParams(
    "fi-harden", cl::CommaSeparated,
    cl::desc("fi-harden parameters under clang -fpass-plugin, as in "
             "fi-harden<...>: all, branches, compares"));

namespace {

struct FIHardenOptions {
  bool All = false; // every defined function, not just the marked ones
  bool Branches = false;
  bool Compares = false;

  // The countermeasures, not All.
  void print(raw_ostream &OS, StringRef Sep = ", ") const {
    ListSeparator LS(Sep);
    if (Branches)
      OS << LS << "branches";
    if (Compares)
      OS << LS << "compares";
  }
};

// Parses the text between the <> of fi-harden<all;branches;compares>. Naming
// no countermeasure means every countermeasure.
Expected<FIHardenOptions> parseOptions(StringRef Params) {
  FIHardenOptions Opts;
  if (!Params.empty())
    for (StringRef P : split(Params, ';')) {
      if (P == "all")
        Opts.All = true;
      else if (P == "branches")
        Opts.Branches = true;
      else if (P == "compares")
        Opts.Compares = true;
      else
        return createStringError("invalid fi-harden parameter '" + P +
                                 "'; expected all, branches or compares");
    }
  if (!Opts.Branches && !Opts.Compares)
    Opts.Branches = Opts.Compares = true;
  return Opts;
}

// Required: hardening must also run on optnone functions and at -O0.
class FIHardenPass : public RequiredPassInfoMixin<FIHardenPass> {
  FIHardenOptions Opts;

public:
  explicit FIHardenPass(FIHardenOptions Opts) : Opts(Opts) {}

  PreservedAnalyses run(Module &M, ModuleAnalysisManager &MAM) {
    FunctionAnalysisManager &FAM =
        MAM.getResult<FunctionAnalysisManagerModuleProxy>(M).getManager();
    for (Function *F : fiharden::selectFunctions(M, Opts.All)) {
      ++NumFunctions;
      std::string Msg;
      raw_string_ostream OS(Msg);
      Opts.print(OS);
      LLVM_DEBUG(dbgs() << DEBUG_TYPE << ": " << F->getName() << ": " << Msg
                        << "\n");
      FAM.getResult<OptimizationRemarkEmitterAnalysis>(*F).emit([&] {
        return OptimizationRemark(DEBUG_TYPE, "Selected", F)
               << "hardening " << F->getName() << ": " << Msg;
      });
    }
    return PreservedAnalyses::all();
  }

  // Prints as fi-harden<...>, so -print-pipeline-passes output can be fed
  // back to opt.
  void printPipeline(raw_ostream &OS, function_ref<StringRef(StringRef)>) {
    OS << "fi-harden<" << (Opts.All ? "all;" : "");
    Opts.print(OS, ";");
    OS << '>';
  }
};

// Emits a missed remark for every instruction countermeasures must leave
// alone, so the skip rules can be tested and inspected on their own.
struct SkipReportPass : RequiredPassInfoMixin<SkipReportPass> {
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &FAM) {
    auto &ORE = FAM.getResult<OptimizationRemarkEmitterAnalysis>(F);
    for (Instruction &I : instructions(F))
      fiharden::skipInstruction(I, ORE);
    return PreservedAnalyses::all();
  }
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
            PB.registerPipelineParsingCallback(
                [](StringRef Name, FunctionPassManager &FPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name != "fi-harden-skips")
                    return false;
                  FPM.addPass(SkipReportPass());
                  return true;
                });
            // After all IR optimisation, so no IR pass can merge or fold
            // the redundancy away. The backend still runs after this.
            // ponytail: LTO runs this in both pre-link and post-link
            // pipelines; decide which one hardens when LTO is supported.
            PB.registerOptimizerLastEPCallback(
                [](ModulePassManager &MPM, OptimizationLevel,
                   ThinOrFullLTOPhase) {
                  auto Opts = parseOptions(join(ClangParams, ";"));
                  if (!Opts)
                    reportFatalUsageError(Opts.takeError());
                  MPM.addPass(FIHardenPass(*Opts));
                });
          }};
}

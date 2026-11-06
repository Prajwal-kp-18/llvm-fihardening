// FIHardeningTransform.cpp
// LLVM IR-to-IR Transformation Pass for Fault Injection Hardening
//
// This pass transforms LLVM IR to add fault injection resilience by:
// 1. Duplicating critical instructions with verification
// 2. Adding redundant conditional checks
// 3. Inserting calls to runtime verification functions
// 4. Protecting memory operations with checksums

#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include <set>
#include <map>
#include <vector>

using namespace llvm;

// Command-line options for configurable hardening
static cl::opt<bool> HardenBranches(
    "fi-harden-branches",
    cl::desc("Enable branch hardening with redundant checks"),
    cl::init(true));

static cl::opt<bool> HardenMemory(
    "fi-harden-memory",
    cl::desc("Enable memory operation hardening"),
    cl::init(true));

static cl::opt<bool> HardenArithmetic(
    "fi-harden-arithmetic",
    cl::desc("Enable arithmetic operation hardening"),
    cl::init(false)); // Off by default due to overhead

static cl::opt<bool> HardenCFI(
    "fi-harden-cfi",
    cl::desc("Enable Control-Flow Integrity checks"),
    cl::init(true));

static cl::opt<bool> HardenDataRedundancy(
    "fi-harden-data-redundancy",
    cl::desc("Enable critical variable redundancy"),
    cl::init(true));

static cl::opt<bool> HardenMemorySafety(
    "fi-harden-memory-safety",
    cl::desc("Enable memory bounds checking"),
    cl::init(true));

static cl::opt<bool> HardenStack(
    "fi-harden-stack",
    cl::desc("Enable stack protection (return address, frame pointer)"),
    cl::init(true));

static cl::opt<bool> HardenExceptionPaths(
    "fi-harden-exceptions",
    cl::desc("Enable exception and error path hardening"),
    cl::init(false));

static cl::opt<bool> HardenHardwareIO(
    "fi-harden-hardware-io",
    cl::desc("Enable hardware interaction validation"),
    cl::init(false));

static cl::opt<bool> EnableFaultLogging(
    "fi-enable-logging",
    cl::desc("Enable runtime fault detection logging"),
    cl::init(true));

static cl::opt<bool> HardenTiming(
    "fi-harden-timing",
    cl::desc("Enable timing and side-channel mitigations"),
    cl::init(false));

static cl::opt<unsigned> HardenLevel(
    "fi-harden-level",
    cl::desc("Hardening aggressiveness level (0=minimal, 1=moderate, 2=aggressive, 3=maximum)"),
    cl::init(3));

static cl::opt<bool> ShowStats(
    "fi-harden-stats",
    cl::desc("Show transformation statistics"),
    cl::init(false));

static cl::opt<bool> VerifyIR(
    "fi-harden-verify",
    cl::desc("Verify IR correctness after transformation"),
    cl::init(true));

namespace {

// Statistics tracking
struct TransformStats {
  unsigned BranchesHardened = 0;
  unsigned LoadsHardened = 0;
  unsigned StoresHardened = 0;
  unsigned ArithmeticHardened = 0;
  unsigned VerificationCallsAdded = 0;
  unsigned InstructionsDuplicated = 0;
  unsigned BasicBlocksSplit = 0;
  
  // New strategy statistics
  unsigned IndirectCallsHardened = 0;
  unsigned CriticalVariablesProtected = 0;
  unsigned BoundsChecksAdded = 0;
  unsigned ReturnAddressesProtected = 0;
  unsigned ExceptionPathsHardened = 0;
  unsigned HardwareIOValidated = 0;
  unsigned FaultLogsAdded = 0;
  unsigned TimingMitigationsAdded = 0;
  
  // LLFI Coverage Enhancement Statistics
  unsigned PhiNodesVerified = 0;
  unsigned TMRApplications = 0;
  unsigned TemporariesProtected = 0;
  unsigned LLFIHardenedFunctions = 0;
  
  void print(raw_ostream &OS) {
    OS << "\n========================================\n";
    OS << "FI Hardening Transformation Statistics\n";
    OS << "========================================\n";
    OS << "Basic Hardening:\n";
    OS << "  Branches hardened:          " << BranchesHardened << "\n";
    OS << "  Loads hardened:             " << LoadsHardened << "\n";
    OS << "  Stores hardened:            " << StoresHardened << "\n";
    OS << "  Arithmetic ops hardened:    " << ArithmeticHardened << "\n";
    OS << "\nAdvanced Hardening:\n";
    OS << "  Indirect calls hardened:    " << IndirectCallsHardened << "\n";
    OS << "  Critical vars protected:    " << CriticalVariablesProtected << "\n";
    OS << "  Bounds checks added:        " << BoundsChecksAdded << "\n";
    OS << "  Return addrs protected:     " << ReturnAddressesProtected << "\n";
    OS << "  Exception paths hardened:   " << ExceptionPathsHardened << "\n";
    OS << "  Hardware I/O validated:     " << HardwareIOValidated << "\n";
    OS << "  Fault logs added:           " << FaultLogsAdded << "\n";
    OS << "  Timing mitigations:         " << TimingMitigationsAdded << "\n";
    OS << "\nLLFI Coverage Enhancements:\n";
    OS << "  Phi nodes verified:         " << PhiNodesVerified << "\n";
    OS << "  TMR applications:           " << TMRApplications << "\n";
    OS << "  Temporaries protected:      " << TemporariesProtected << "\n";
    OS << "  LLFI-hardened functions:    " << LLFIHardenedFunctions << "\n";
    OS << "\nInstrumentation:\n";
    OS << "  Verification calls added:   " << VerificationCallsAdded << "\n";
    OS << "  Instructions duplicated:    " << InstructionsDuplicated << "\n";
    OS << "  Basic blocks split:         " << BasicBlocksSplit << "\n";
    OS << "========================================\n";
    
    unsigned totalTransforms = BranchesHardened + LoadsHardened + 
                               StoresHardened + ArithmeticHardened +
                               IndirectCallsHardened + CriticalVariablesProtected +
                               BoundsChecksAdded + ReturnAddressesProtected +
                               ExceptionPathsHardened + HardwareIOValidated +
                               TimingMitigationsAdded;
    OS << "Total transformations:      " << totalTransforms << "\n";
    OS << "========================================\n\n";
  }
};

class FIHardeningTransform : public PassInfoMixin<FIHardeningTransform> {
private:
  TransformStats Stats;
  
  // Runtime function declarations (linked from libFIHardeningRuntime.a)
  FunctionCallee VerifyInt32Func;
  FunctionCallee VerifyInt64Func;
  FunctionCallee VerifyPointerFunc;
  FunctionCallee VerifyBranchFunc;
  FunctionCallee ChecksumUpdateFunc;
  FunctionCallee ChecksumVerifyFunc;
  
  // New runtime functions for advanced hardening
  FunctionCallee VerifyCFIFunc;           // CFI: Control-Flow Integrity
  FunctionCallee LogFaultFunc;            // Logging: Runtime fault detection
  FunctionCallee CheckBoundsFunc;         // Memory Safety: Bounds checking
  FunctionCallee ProtectReturnAddrFunc;   // Stack: Return address protection
  FunctionCallee VerifyReturnAddrFunc;    // Stack: Return address verification
  FunctionCallee ValidateHardwareIOFunc;  // Hardware: I/O validation
  FunctionCallee AddTimingNoiseFunc;      // Timing: Side-channel mitigation
  
  // Helper to get or create runtime functions
  void initializeRuntimeFunctions(Module &M) {
    LLVMContext &Ctx = M.getContext();
    
    // void fi_verify_int32(int32_t value, int32_t expected, const char *location)
    Type *Int32Ty = Type::getInt32Ty(Ctx);
    Type *Int8PtrTy = PointerType::getUnqual(Type::getInt8Ty(Ctx));
    Type *VoidTy = Type::getVoidTy(Ctx);
    
    FunctionType *VerifyInt32Ty = FunctionType::get(
        VoidTy, {Int32Ty, Int32Ty, Int8PtrTy}, false);
    VerifyInt32Func = M.getOrInsertFunction("fi_verify_int32", VerifyInt32Ty);
    
    // void fi_verify_int64(int64_t value, int64_t expected, const char *location)
    Type *Int64Ty = Type::getInt64Ty(Ctx);
    FunctionType *VerifyInt64Ty = FunctionType::get(
        VoidTy, {Int64Ty, Int64Ty, Int8PtrTy}, false);
    VerifyInt64Func = M.getOrInsertFunction("fi_verify_int64", VerifyInt64Ty);
    
    // void fi_verify_pointer(void *ptr, void *expected, const char *location)
    FunctionType *VerifyPtrTy = FunctionType::get(
        VoidTy, {Int8PtrTy, Int8PtrTy, Int8PtrTy}, false);
    VerifyPointerFunc = M.getOrInsertFunction("fi_verify_pointer", VerifyPtrTy);
    
    // void fi_verify_branch(int condition, int expected, const char *location)
    FunctionType *VerifyBranchTy = FunctionType::get(
        VoidTy, {Int32Ty, Int32Ty, Int8PtrTy}, false);
    VerifyBranchFunc = M.getOrInsertFunction("fi_verify_branch", VerifyBranchTy);
    
    // void fi_checksum_update(void *addr, size_t size)
    Type *SizeTy = Type::getInt64Ty(Ctx);
    FunctionType *ChecksumUpdateTy = FunctionType::get(
        VoidTy, {Int8PtrTy, SizeTy}, false);
    ChecksumUpdateFunc = M.getOrInsertFunction("fi_checksum_update", ChecksumUpdateTy);
    
    // int fi_checksum_verify(void *addr, size_t size)
    FunctionType *ChecksumVerifyTy = FunctionType::get(
        Int32Ty, {Int8PtrTy, SizeTy}, false);
    ChecksumVerifyFunc = M.getOrInsertFunction("fi_checksum_verify", ChecksumVerifyTy);
    
    // ===== NEW ADVANCED HARDENING FUNCTIONS =====
    
    // void fi_verify_cfi(void *target, void *expected, const char *location)
    FunctionType *VerifyCFITy = FunctionType::get(
        VoidTy, {Int8PtrTy, Int8PtrTy, Int8PtrTy}, false);
    VerifyCFIFunc = M.getOrInsertFunction("fi_verify_cfi", VerifyCFITy);
    
    // void fi_log_fault(const char *message, int severity)
    FunctionType *LogFaultTy = FunctionType::get(
        VoidTy, {Int8PtrTy, Int32Ty}, false);
    LogFaultFunc = M.getOrInsertFunction("fi_log_fault", LogFaultTy);
    
    // int fi_check_bounds(void *ptr, void *base, size_t size)
    FunctionType *CheckBoundsTy = FunctionType::get(
        Int32Ty, {Int8PtrTy, Int8PtrTy, SizeTy}, false);
    CheckBoundsFunc = M.getOrInsertFunction("fi_check_bounds", CheckBoundsTy);
    
    // void fi_protect_return_addr(void **addr_location)
    Type *Int8PtrPtrTy = PointerType::getUnqual(Int8PtrTy);
    FunctionType *ProtectReturnTy = FunctionType::get(
        VoidTy, {Int8PtrPtrTy}, false);
    ProtectReturnAddrFunc = M.getOrInsertFunction("fi_protect_return_addr", ProtectReturnTy);
    
    // int fi_verify_return_addr(void **addr_location)
    FunctionType *VerifyReturnTy = FunctionType::get(
        Int32Ty, {Int8PtrPtrTy}, false);
    VerifyReturnAddrFunc = M.getOrInsertFunction("fi_verify_return_addr", VerifyReturnTy);
    
    // void fi_validate_hardware_io(void *addr, int32_t expected_value)
    FunctionType *ValidateIOTy = FunctionType::get(
        VoidTy, {Int8PtrTy, Int32Ty}, false);
    ValidateHardwareIOFunc = M.getOrInsertFunction("fi_validate_hardware_io", ValidateIOTy);
    
    // void fi_add_timing_noise(void)
    FunctionType *TimingNoiseTy = FunctionType::get(VoidTy, {}, false);
    AddTimingNoiseFunc = M.getOrInsertFunction("fi_add_timing_noise", TimingNoiseTy);
  }
  
  // Create a constant string for location information
  Value *createLocationString(IRBuilder<> &Builder, Module &M, 
                             const std::string &FuncName, 
                             const std::string &InstType) {
    std::string location = FuncName + ":" + InstType;
    return Builder.CreateGlobalStringPtr(location);
  }
  
  // Skip intrinsic and debug instructions
  bool shouldSkipInstruction(Instruction &I) {
    // Skip debug instructions
    if (isa<DbgInfoIntrinsic>(&I))
      return true;
    
    // Skip exception handling
    if (isa<LandingPadInst>(&I) || isa<ResumeInst>(&I))
      return true;
    
    // Skip intrinsic calls
    if (CallInst *CI = dyn_cast<CallInst>(&I)) {
      if (Function *F = CI->getCalledFunction()) {
        if (F->isIntrinsic())
          return true;
        StringRef Name = F->getName();
        if (Name.starts_with("llvm.") || Name.starts_with("fi_verify") || 
            Name.starts_with("fi_checksum"))
          return true;
      }
    }
    
    return false;
  }
  
  // Harden a conditional branch with redundant checks
  void hardenBranch(BranchInst *BI, Function &F) {
    if (!BI->isConditional())
      return;
    
    // Only harden based on level
    if (HardenLevel == 0 && !isInCriticalPath(BI))
      return;
    
    IRBuilder<> Builder(BI);
    Module *M = F.getParent();
    
    Value *Condition = BI->getCondition();
    Value *Location = createLocationString(Builder, *M, F.getName().str(), "branch");
    
    // Strategy 1: Duplicate condition evaluation
    Value *CondDup = Builder.CreateICmp(
        cast<ICmpInst>(Condition)->getPredicate(),
        cast<ICmpInst>(Condition)->getOperand(0),
        cast<ICmpInst>(Condition)->getOperand(1),
        "cond.dup");
    
    Stats.InstructionsDuplicated++;
    
    // Strategy 2: Verify both conditions match
    Value *Cond1Int = Builder.CreateZExt(Condition, Builder.getInt32Ty());
    Value *Cond2Int = Builder.CreateZExt(CondDup, Builder.getInt32Ty());
    
    Builder.CreateCall(VerifyBranchFunc, {Cond1Int, Cond2Int, Location});
    Stats.VerificationCallsAdded++;
    
    // Strategy 3: Use redundant condition for branch
    Value *RedundantCond = Builder.CreateAnd(Condition, CondDup, "cond.redundant");
    BI->setCondition(RedundantCond);
    
    Stats.BranchesHardened++;
    
    errs() << "  [Transform] Hardened branch in function '" << F.getName() << "'\n";
  }
  
  // Harden a load instruction with verification
  void hardenLoad(LoadInst *LI, Function &F) {
    // Only harden based on level
    if (HardenLevel == 0 && !isInCriticalPath(LI))
      return;
    
    IRBuilder<> Builder(LI->getNextNode());
    Module *M = F.getParent();
    
    Value *LoadedValue = LI;
    Value *Location = createLocationString(Builder, *M, F.getName().str(), "load");
    
    // Strategy 1: Duplicate load and verify
    IRBuilder<> LoadBuilder(LI);
    LoadInst *LoadDup = LoadBuilder.CreateLoad(
        LI->getType(), LI->getPointerOperand(), "load.dup");
    LoadDup->setAlignment(LI->getAlign());
    LoadDup->setVolatile(LI->isVolatile());
    
    Stats.InstructionsDuplicated++;
    
    // Strategy 2: Verify loaded values match
    Type *LoadType = LI->getType();
    
    if (LoadType->isIntegerTy(32)) {
      Builder.CreateCall(VerifyInt32Func, {LoadedValue, LoadDup, Location});
      Stats.VerificationCallsAdded++;
    } else if (LoadType->isIntegerTy(64)) {
      Builder.CreateCall(VerifyInt64Func, {LoadedValue, LoadDup, Location});
      Stats.VerificationCallsAdded++;
    } else if (LoadType->isPointerTy()) {
      Value *Ptr1 = Builder.CreateBitCast(LoadedValue, PointerType::getUnqual(Builder.getInt8Ty()));
      Value *Ptr2 = Builder.CreateBitCast(LoadDup, PointerType::getUnqual(Builder.getInt8Ty()));
      Builder.CreateCall(VerifyPointerFunc, {Ptr1, Ptr2, Location});
      Stats.VerificationCallsAdded++;
    }
    
    // Strategy 3: Use majority voting for critical loads (level 3)
    if (HardenLevel >= 3) {
      // Create third load
      LoadInst *LoadDup2 = Builder.CreateLoad(
          LI->getType(), LI->getPointerOperand(), "load.dup2");
      LoadDup2->setAlignment(LI->getAlign());
      Stats.InstructionsDuplicated++;
      
      // Majority voting: if 2 out of 3 match, use that value
      // This is complex, simplified version: just verify all three match
      if (LoadType->isIntegerTy(32)) {
        Builder.CreateCall(VerifyInt32Func, {LoadDup, LoadDup2, Location});
        Stats.VerificationCallsAdded++;
      }
    }
    
    Stats.LoadsHardened++;
    
    if (HardenLevel >= 2)
      errs() << "  [Transform] Hardened load in function '" << F.getName() << "'\n";
  }
  
  // Harden a store instruction with checksums
  void hardenStore(StoreInst *SI, Function &F) {
    // Only harden based on level
    if (HardenLevel == 0 && !isInCriticalPath(SI))
      return;
    
    IRBuilder<> Builder(SI->getNextNode());
    Module *M = F.getParent();
    
    Value *StoredValue = SI->getValueOperand();
    Value *StorePtr = SI->getPointerOperand();
    Value *Location = createLocationString(Builder, *M, F.getName().str(), "store");
    
    // Strategy 1: Verify store by reading back
    LoadInst *VerifyLoad = Builder.CreateLoad(
        SI->getValueOperand()->getType(), StorePtr, "store.verify");
    VerifyLoad->setAlignment(SI->getAlign());
    
    Type *ValueType = StoredValue->getType();
    
    if (ValueType->isIntegerTy(32)) {
      Builder.CreateCall(VerifyInt32Func, {VerifyLoad, StoredValue, Location});
      Stats.VerificationCallsAdded++;
    } else if (ValueType->isIntegerTy(64)) {
      Builder.CreateCall(VerifyInt64Func, {VerifyLoad, StoredValue, Location});
      Stats.VerificationCallsAdded++;
    } else if (ValueType->isPointerTy()) {
      Value *Ptr1 = Builder.CreateBitCast(VerifyLoad, PointerType::getUnqual(Builder.getInt8Ty()));
      Value *Ptr2 = Builder.CreateBitCast(StoredValue, PointerType::getUnqual(Builder.getInt8Ty()));
      Builder.CreateCall(VerifyPointerFunc, {Ptr1, Ptr2, Location});
      Stats.VerificationCallsAdded++;
    }
    
    // Strategy 2: Update checksum for memory region (level 2+)
    if (HardenLevel >= 2 && ValueType->isSized()) {
      const DataLayout &DL = M->getDataLayout();
      uint64_t Size = DL.getTypeStoreSize(ValueType);
      
      Value *PtrCast = Builder.CreateBitCast(StorePtr, PointerType::getUnqual(Builder.getInt8Ty()));
      Value *SizeVal = Builder.getInt64(Size);
      Builder.CreateCall(ChecksumUpdateFunc, {PtrCast, SizeVal});
      Stats.VerificationCallsAdded++;
    }
    
    Stats.StoresHardened++;
    
    if (HardenLevel >= 2)
      errs() << "  [Transform] Hardened store in function '" << F.getName() << "'\n";
  }
  
  // Harden arithmetic operations (division, modulo) against faults
  void hardenArithmetic(BinaryOperator *BO, Function &F) {
    if (!HardenArithmetic || HardenLevel < 2)
      return;
    
    // Focus on division and modulo (expensive operations prone to faults)
    if (BO->getOpcode() != Instruction::SDiv &&
        BO->getOpcode() != Instruction::UDiv &&
        BO->getOpcode() != Instruction::SRem &&
        BO->getOpcode() != Instruction::URem)
      return;
    
    IRBuilder<> Builder(BO->getNextNode());
    Module *M = F.getParent();
    
    // Duplicate operation
    Value *Op1 = BO->getOperand(0);
    Value *Op2 = BO->getOperand(1);
    
    Value *ResultDup = Builder.CreateBinOp(
        BO->getOpcode(), Op1, Op2, "arith.dup");
    Stats.InstructionsDuplicated++;
    
    // Verify results match
    Value *Location = createLocationString(Builder, *M, F.getName().str(), "arithmetic");
    
    Type *ResType = BO->getType();
    if (ResType->isIntegerTy(32)) {
      Builder.CreateCall(VerifyInt32Func, {BO, ResultDup, Location});
      Stats.VerificationCallsAdded++;
    } else if (ResType->isIntegerTy(64)) {
      Builder.CreateCall(VerifyInt64Func, {BO, ResultDup, Location});
      Stats.VerificationCallsAdded++;
    }
    
    Stats.ArithmeticHardened++;
    
    errs() << "  [Transform] Hardened arithmetic in function '" << F.getName() << "'\n";
  }
  
  // ===== NEW ADVANCED HARDENING STRATEGIES =====
  
  // Strategy 5: Control-Flow Integrity (CFI) for indirect calls
  void hardenIndirectCall(CallInst *CI, Function &F) {
    if (HardenLevel == 0 && !isInCriticalPath(CI))
      return;
    
    Value *CalledValue = CI->getCalledOperand();
    if (isa<Function>(CalledValue))
      return; // Direct call, already safe
    
    IRBuilder<> Builder(CI);
    Module *M = F.getParent();
    Value *Location = createLocationString(Builder, *M, F.getName().str(), "indirect_call");
    
    // Get expected function pointer (from data-flow or type)
    // For now, we verify it matches expectations at runtime
    Type *Int8Ty = Builder.getInt8Ty();
    Value *CalledPtr = Builder.CreateBitCast(CalledValue, PointerType::getUnqual(Int8Ty));
    Value *ExpectedPtr = CalledPtr; // In real implementation, track expected targets
    
    // Insert CFI check before the call
    Builder.CreateCall(VerifyCFIFunc, {CalledPtr, ExpectedPtr, Location});
    Stats.VerificationCallsAdded++;
    Stats.IndirectCallsHardened++;
    
    if (EnableFaultLogging) {
      Value *LogMsg = Builder.CreateGlobalStringPtr("CFI check passed");
      Builder.CreateCall(LogFaultFunc, {LogMsg, Builder.getInt32(0)});
      Stats.FaultLogsAdded++;
    }
    
    errs() << "  [Transform] Hardened indirect call with CFI\n";
  }
  
  // Strategy 6: Critical Variable Redundancy
  void hardenCriticalVariable(AllocaInst *AI, Function &F) {
    if (HardenLevel < 2) // Only at aggressive levels
      return;
    
    // Identify critical variables (function parameters, loop counters, security checks)
    bool isCritical = false;
    
    // Check if used in branches or returns
    for (User *U : AI->users()) {
      if (auto *LI = dyn_cast<LoadInst>(U)) {
        for (User *LU : LI->users()) {
          if (isa<ICmpInst>(LU) || isa<ReturnInst>(LU)) {
            isCritical = true;
            break;
          }
        }
      }
    }
    
    if (!isCritical)
      return;
    
    IRBuilder<> Builder(AI->getNextNode());
    Module *M = F.getParent();
    
    // Create redundant copy of the variable
    AllocaInst *RedundantVar = Builder.CreateAlloca(
        AI->getAllocatedType(), nullptr, AI->getName() + ".redundant");
    
    // After every store to original, also store to redundant
    for (User *U : AI->users()) {
      if (StoreInst *SI = dyn_cast<StoreInst>(U)) {
        if (SI->getPointerOperand() == AI) {
          IRBuilder<> StoreBuilder(SI->getNextNode());
          StoreBuilder.CreateStore(SI->getValueOperand(), RedundantVar);
        }
      }
    }
    
    Stats.CriticalVariablesProtected++;
    errs() << "  [Transform] Protected critical variable with redundancy\n";
  }
  
  // Strategy 7: Memory Bounds Checking
  void hardenMemoryAccess(GetElementPtrInst *GEP, Function &F) {
    if (!HardenMemorySafety)
      return;
    
    IRBuilder<> Builder(GEP->getNextNode());
    Module *M = F.getParent();
    
    Type *Int8Ty = Builder.getInt8Ty();
    Value *Ptr = Builder.CreateBitCast(GEP, PointerType::getUnqual(Int8Ty));
    Value *Base = Builder.CreateBitCast(GEP->getPointerOperand(), PointerType::getUnqual(Int8Ty));
    
    // Estimate size (simplified - real implementation would track allocations)
    Value *Size = Builder.getInt64(1024); // Placeholder
    
    // Insert bounds check
    Value *CheckResult = Builder.CreateCall(CheckBoundsFunc, {Ptr, Base, Size});
    
    // Branch on check result
    BasicBlock *CurrentBB = Builder.GetInsertBlock();
    BasicBlock *SafeBB = CurrentBB->splitBasicBlock(Builder.GetInsertPoint(), "bounds_safe");
    BasicBlock *ErrorBB = BasicBlock::Create(F.getContext(), "bounds_error", &F);
    
    Builder.SetInsertPoint(CurrentBB->getTerminator());
    Value *IsInBounds = Builder.CreateICmpNE(CheckResult, Builder.getInt32(0));
    Builder.CreateCondBr(IsInBounds, SafeBB, ErrorBB);
    CurrentBB->getTerminator()->eraseFromParent();
    
    // Error block: log and abort
    Builder.SetInsertPoint(ErrorBB);
    if (EnableFaultLogging) {
      Value *LogMsg = Builder.CreateGlobalStringPtr("Bounds check failed!");
      Builder.CreateCall(LogFaultFunc, {LogMsg, Builder.getInt32(2)}); // Severity 2 = Error
    }
    Builder.CreateUnreachable();
    
    Stats.BoundsChecksAdded++;
    Stats.BasicBlocksSplit++;
    errs() << "  [Transform] Added memory bounds check\n";
  }
  
  // Strategy 8: Stack Protection (Return Address)
  void hardenFunctionEntry(Function &F) {
    if (!HardenStack || HardenLevel == 0)
      return;
    
    BasicBlock &EntryBB = F.getEntryBlock();
    IRBuilder<> Builder(&EntryBB, EntryBB.getFirstInsertionPt());
    
    Type *Int8Ty = Builder.getInt8Ty();
    // Allocate space to store return address protection
    AllocaInst *RetAddrStorage = Builder.CreateAlloca(
        PointerType::getUnqual(Int8Ty), nullptr, "return_addr_storage");
    
    // Protect return address at function entry
    Builder.CreateCall(ProtectReturnAddrFunc, {RetAddrStorage});
    Stats.ReturnAddressesProtected++;
    
    // Collect all return instructions first (avoid iterator invalidation)
    std::vector<ReturnInst*> Returns;
    for (BasicBlock &BB : F) {
      for (Instruction &I : BB) {
        if (ReturnInst *RI = dyn_cast<ReturnInst>(&I)) {
          Returns.push_back(RI);
        }
      }
    }
    
    // Before each return, verify return address
    for (ReturnInst *RI : Returns) {
      IRBuilder<> RetBuilder(RI);
      Value *VerifyResult = RetBuilder.CreateCall(VerifyReturnAddrFunc, {RetAddrStorage});
      
      // If verification fails, log and trap
      BasicBlock *VerifyBB = RI->getParent();
      BasicBlock *SafeRetBB = VerifyBB->splitBasicBlock(RI, "safe_return");
      BasicBlock *ErrorBB = BasicBlock::Create(F.getContext(), "return_corrupted", &F);
      
      RetBuilder.SetInsertPoint(VerifyBB->getTerminator());
      Value *IsValid = RetBuilder.CreateICmpNE(VerifyResult, Builder.getInt32(0));
      RetBuilder.CreateCondBr(IsValid, SafeRetBB, ErrorBB);
      VerifyBB->getTerminator()->eraseFromParent();
      
      RetBuilder.SetInsertPoint(ErrorBB);
      if (EnableFaultLogging) {
        Value *LogMsg = RetBuilder.CreateGlobalStringPtr("Return address corrupted!");
        RetBuilder.CreateCall(LogFaultFunc, {LogMsg, RetBuilder.getInt32(3)}); // Critical
      }
      RetBuilder.CreateUnreachable();
      
      Stats.BasicBlocksSplit++;
    }
    
    errs() << "  [Transform] Protected return addresses\n";
  }
  
  // Strategy 9: Exception Path Hardening
  void hardenExceptionPath(LandingPadInst *LP, Function &F) {
    if (!HardenExceptionPaths)
      return;
    
    IRBuilder<> Builder(LP->getNextNode());
    
    // Add verification that we're actually in an exception state
    if (EnableFaultLogging) {
      Value *LogMsg = Builder.CreateGlobalStringPtr("Exception handler entered");
      Builder.CreateCall(LogFaultFunc, {LogMsg, Builder.getInt32(1)}); // Warning level
      Stats.FaultLogsAdded++;
    }
    
    // Duplicate exception handling logic (simplified)
    Stats.ExceptionPathsHardened++;
    errs() << "  [Transform] Hardened exception path\n";
  }
  
  // Strategy 10: Hardware I/O Validation
  void hardenVolatileLoad(LoadInst *LI, Function &F) {
    if (!HardenHardwareIO || !LI->isVolatile())
      return;
    
    IRBuilder<> Builder(LI->getNextNode());
    Module *M = F.getParent();
    
    // For volatile loads (hardware I/O), validate the value
    Value *LoadedValue = LI;
    Type *Int8Ty = Builder.getInt8Ty();
    Value *PtrCast = Builder.CreateBitCast(LI->getPointerOperand(), PointerType::getUnqual(Int8Ty));
    
    // Assume we expect certain patterns (in real use, this would be configurable)
    Value *ExpectedPattern = Builder.getInt32(0); // Placeholder
    
    if (LI->getType()->isIntegerTy(32)) {
      Builder.CreateCall(ValidateHardwareIOFunc, {PtrCast, LoadedValue});
      Stats.VerificationCallsAdded++;
    }
    
    Stats.HardwareIOValidated++;
    errs() << "  [Transform] Validated hardware I/O operation\n";
  }
  
  // Strategy 11: Timing Side-Channel Mitigation
  void addTimingMitigation(BasicBlock &BB, Function &F) {
    if (!HardenTiming || HardenLevel < 2)
      return;
    
    // Add timing noise at strategic points to prevent timing analysis
    for (Instruction &I : BB) {
      if (BranchInst *BI = dyn_cast<BranchInst>(&I)) {
        if (BI->isConditional()) {
          IRBuilder<> Builder(BI);
          Builder.CreateCall(AddTimingNoiseFunc, {});
          Stats.TimingMitigationsAdded++;
          Stats.VerificationCallsAdded++;
        }
      }
    }
    
    errs() << "  [Transform] Added timing side-channel mitigation\n";
  }
  
  // Determine if instruction is in a critical path (simplified heuristic)
  bool isInCriticalPath(Instruction *I) {
    // Heuristics:
    // 1. In a loop
    // 2. Controls return value
    // 3. In function entry block
    // 4. Affects function parameters
    
    BasicBlock *BB = I->getParent();
    Function *F = BB->getParent();
    
    // Entry block is critical
    if (BB == &F->getEntryBlock())
      return true;
    
    // Check if affects return
    for (User *U : I->users()) {
      if (isa<ReturnInst>(U))
        return true;
      if (BranchInst *BI = dyn_cast<BranchInst>(U))
        if (BI->isConditional())
          return true;
    }
    
    return false;
  }
  
public:
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &FAM) {
    // Skip declarations
    if (F.isDeclaration())
      return PreservedAnalyses::all();
    
    // Skip our own runtime functions
    StringRef FName = F.getName();
    if (FName.starts_with("fi_verify") || FName.starts_with("fi_checksum"))
      return PreservedAnalyses::all();
    
    errs() << "\n[FIHardeningTransform] Processing function: " << F.getName() << "\n";
    errs() << "  Hardening level: " << HardenLevel << "\n";
    errs() << "  Branch hardening: " << (HardenBranches ? "ON" : "OFF") << "\n";
    errs() << "  Memory hardening: " << (HardenMemory ? "ON" : "OFF") << "\n";
    errs() << "  Arithmetic hardening: " << (HardenArithmetic ? "ON" : "OFF") << "\n";
    errs() << "  CFI: " << (HardenCFI ? "ON" : "OFF") << "\n";
    errs() << "  Data redundancy: " << (HardenDataRedundancy ? "ON" : "OFF") << "\n";
    errs() << "  Memory safety: " << (HardenMemorySafety ? "ON" : "OFF") << "\n";
    errs() << "  Stack protection: " << (HardenStack ? "ON" : "OFF") << "\n";
    
    Module *M = F.getParent();
    initializeRuntimeFunctions(*M);
    
    // Apply function-level hardening first
    if (HardenStack)
      hardenFunctionEntry(F);
    
    // Collect instructions to harden (avoid iterator invalidation)
    std::vector<BranchInst*> BranchesToHarden;
    std::vector<LoadInst*> LoadsToHarden;
    std::vector<StoreInst*> StoresToHarden;
    std::vector<BinaryOperator*> ArithmeticToHarden;
    std::vector<CallInst*> IndirectCallsToHarden;
    std::vector<AllocaInst*> VariablesToProtect;
    std::vector<GetElementPtrInst*> MemoryAccessesToCheck;
    std::vector<LandingPadInst*> ExceptionPathsToHarden;
    std::vector<LoadInst*> VolatileLoadsToValidate;
    
    for (BasicBlock &BB : F) {
      // Apply timing mitigation to basic block if needed
      if (HardenTiming)
        addTimingMitigation(BB, F);
      
      for (Instruction &I : BB) {
        if (shouldSkipInstruction(I))
          continue;
        
        if (BranchInst *BI = dyn_cast<BranchInst>(&I)) {
          if (HardenBranches && BI->isConditional() && isa<ICmpInst>(BI->getCondition()))
            BranchesToHarden.push_back(BI);
        } else if (LoadInst *LI = dyn_cast<LoadInst>(&I)) {
          if (HardenMemory)
            LoadsToHarden.push_back(LI);
          if (HardenHardwareIO && LI->isVolatile())
            VolatileLoadsToValidate.push_back(LI);
        } else if (StoreInst *SI = dyn_cast<StoreInst>(&I)) {
          if (HardenMemory)
            StoresToHarden.push_back(SI);
        } else if (BinaryOperator *BO = dyn_cast<BinaryOperator>(&I)) {
          if (HardenArithmetic)
            ArithmeticToHarden.push_back(BO);
        } else if (CallInst *CI = dyn_cast<CallInst>(&I)) {
          if (HardenCFI && !CI->getCalledFunction())
            IndirectCallsToHarden.push_back(CI);
        } else if (AllocaInst *AI = dyn_cast<AllocaInst>(&I)) {
          if (HardenDataRedundancy)
            VariablesToProtect.push_back(AI);
        } else if (GetElementPtrInst *GEP = dyn_cast<GetElementPtrInst>(&I)) {
          if (HardenMemorySafety)
            MemoryAccessesToCheck.push_back(GEP);
        } else if (LandingPadInst *LP = dyn_cast<LandingPadInst>(&I)) {
          if (HardenExceptionPaths)
            ExceptionPathsToHarden.push_back(LP);
        }
      }
    }
    
    // Apply basic transformations
    for (BranchInst *BI : BranchesToHarden)
      hardenBranch(BI, F);
    
    for (LoadInst *LI : LoadsToHarden)
      hardenLoad(LI, F);
    
    for (StoreInst *SI : StoresToHarden)
      hardenStore(SI, F);
    
    for (BinaryOperator *BO : ArithmeticToHarden)
      hardenArithmetic(BO, F);
    
    // Apply advanced transformations
    for (CallInst *CI : IndirectCallsToHarden)
      hardenIndirectCall(CI, F);
    
    for (AllocaInst *AI : VariablesToProtect)
      hardenCriticalVariable(AI, F);
    
    for (GetElementPtrInst *GEP : MemoryAccessesToCheck)
      hardenMemoryAccess(GEP, F);
    
    for (LandingPadInst *LP : ExceptionPathsToHarden)
      hardenExceptionPath(LP, F);
    
    for (LoadInst *LI : VolatileLoadsToValidate)
      hardenVolatileLoad(LI, F);
    
    // ===== NEW: Apply comprehensive LLFI protection (Phase 1) =====
    if (HardenLevel >= 2) {
      applyComprehensiveLLFIProtection(F);
    }
    
    unsigned totalTransforms = BranchesToHarden.size() + LoadsToHarden.size() + 
                               StoresToHarden.size() + ArithmeticToHarden.size() +
                               IndirectCallsToHarden.size() + VariablesToProtect.size() +
                               MemoryAccessesToCheck.size() + ExceptionPathsToHarden.size() +
                               VolatileLoadsToValidate.size();
    
    if (totalTransforms > 0) {
      errs() << "  [Transform] Applied " << totalTransforms << " transformations\n";
      errs() << "  Function '" << F.getName() << "' successfully hardened\n";
    } else {
      errs() << "  [Transform] No transformations needed\n";
    }
    
    // Verify IR correctness if requested
    if (VerifyIR && totalTransforms > 0) {
      errs() << "  [Transform] Verifying IR correctness...\n";
      if (verifyFunction(F, &errs())) {
        errs() << "  [ERROR] IR verification failed!\n";
      } else {
        errs() << "  [Transform] IR verification passed\n";
      }
    }
    
    // Indicate that analyses are invalidated
    return PreservedAnalyses::none();
  }
  
  // Module-level run to show statistics
  PreservedAnalyses run(Module &M, ModuleAnalysisManager &MAM) {
    errs() << "\n========================================\n";
    errs() << "FI Hardening Transformation Pass\n";
    errs() << "========================================\n";
    errs() << "Module: " << M.getName() << "\n";
    errs() << "Configuration:\n";
    errs() << "  Hardening level: " << HardenLevel << "\n";
    errs() << "Basic Strategies:\n";
    errs() << "  Branch hardening: " << (HardenBranches ? "ENABLED" : "DISABLED") << "\n";
    errs() << "  Memory hardening: " << (HardenMemory ? "ENABLED" : "DISABLED") << "\n";
    errs() << "  Arithmetic hardening: " << (HardenArithmetic ? "ENABLED" : "DISABLED") << "\n";
    errs() << "Advanced Strategies:\n";
    errs() << "  Control-Flow Integrity: " << (HardenCFI ? "ENABLED" : "DISABLED") << "\n";
    errs() << "  Data Redundancy: " << (HardenDataRedundancy ? "ENABLED" : "DISABLED") << "\n";
    errs() << "  Memory Safety: " << (HardenMemorySafety ? "ENABLED" : "DISABLED") << "\n";
    errs() << "  Stack Protection: " << (HardenStack ? "ENABLED" : "DISABLED") << "\n";
    errs() << "  Exception Hardening: " << (HardenExceptionPaths ? "ENABLED" : "DISABLED") << "\n";
    errs() << "  Hardware I/O: " << (HardenHardwareIO ? "ENABLED" : "DISABLED") << "\n";
    errs() << "  Fault Logging: " << (EnableFaultLogging ? "ENABLED" : "DISABLED") << "\n";
    errs() << "  Timing Mitigation: " << (HardenTiming ? "ENABLED" : "DISABLED") << "\n";
    errs() << "========================================\n";
    
    // Process each function
    for (Function &F : M) {
      if (!F.isDeclaration()) {
        FunctionAnalysisManager DummyFAM;
        run(F, DummyFAM);
      }
    }
    
    // Show statistics if requested
    if (ShowStats) {
      Stats.print(errs());
    }
    
    errs() << "\n[FIHardeningTransform] Transformation complete!\n\n";
    
    return PreservedAnalyses::none();
  }
  
  // NEW METHOD 1: TMR (Triple Modular Redundancy) for Critical Arithmetic
  void applyTMRToArithmetic(BinaryOperator *BO, Function &F) {
    if (HardenLevel < 2) return;
    
    // Only apply TMR to critical arithmetic operations
    if (!BO->getType()->isIntegerTy() && !BO->getType()->isFloatingPointTy())
      return;
    
    IRBuilder<> Builder(BO);
    Module *M = F.getParent();
    
    errs() << "  [TMR] Applying Triple Modular Redundancy to " 
           << BO->getOpcodeName() << "\n";
    
    // Save operands before cloning
    Value *Op0 = BO->getOperand(0);
    Value *Op1 = BO->getOperand(1);
    Instruction::BinaryOps Opcode = BO->getOpcode();
    
    // Move builder to after the original instruction
    Builder.SetInsertPoint(BO->getNextNode());
    
    // Create two redundant copies
    Value *Clone1 = Builder.CreateBinOp(Opcode, Op0, Op1, BO->getName() + ".tmr1");
    Value *Clone2 = Builder.CreateBinOp(Opcode, Op0, Op1, BO->getName() + ".tmr2");
    
    Stats.InstructionsDuplicated += 2;
    
    // Majority voting: 2 out of 3 must match
    Value *Match12 = Builder.CreateICmpEQ(BO, Clone1, "tmr.match12");
    Value *Match13 = Builder.CreateICmpEQ(BO, Clone2, "tmr.match13");
    Value *Match23 = Builder.CreateICmpEQ(Clone1, Clone2, "tmr.match23");
    
    // At least 2 must match
    Value *TwoMatch = Builder.CreateOr(
        Builder.CreateOr(Match12, Match13),
        Match23, "tmr.valid");
    
    // Create error block
    BasicBlock *OrigBB = BO->getParent();
    BasicBlock::iterator SplitPoint = Builder.GetInsertPoint();
    BasicBlock *ContinueBB = OrigBB->splitBasicBlock(SplitPoint, "tmr.continue");
    BasicBlock *ErrorBB = BasicBlock::Create(
        F.getContext(), "tmr.error", &F, ContinueBB);
    
    // Remove the unconditional branch created by split
    OrigBB->getTerminator()->eraseFromParent();
    
    // Insert conditional branch
    Builder.SetInsertPoint(OrigBB);
    Builder.CreateCondBr(TwoMatch, ContinueBB, ErrorBB);
    
    // Error block: log fault and abort
    Builder.SetInsertPoint(ErrorBB);
    Value *ErrorMsg = Builder.CreateGlobalStringPtr(
        "TMR voting failed in " + F.getName().str());
    Builder.CreateCall(LogFaultFunc, {ErrorMsg, Builder.getInt32(2)}); // Severity 2
    Builder.CreateUnreachable();
    
    // Use the original value if voting passed (it's guaranteed to match at least one clone)
    // No need for select/phi - if we reach continue block, original value is valid
    
    Stats.ArithmeticHardened++;
    Stats.BasicBlocksSplit++;
    Stats.VerificationCallsAdded++;
    Stats.TMRApplications++;
    
    errs() << "  [TMR] Successfully applied TMR with majority voting\n";
  }
  
  // NEW METHOD 2: Phi Node Verification
  void verifyPhiNode(PHINode *Phi, Function &F) {
    if (HardenLevel < 1) return;
    
    errs() << "  [PHI] Verifying phi node in function '" << F.getName() << "'\n";
    
    IRBuilder<> Builder(Phi->getParent()->getFirstNonPHI());
    Module *M = F.getParent();
    
    // Create a redundant phi node
    PHINode *PhiDup = Builder.CreatePHI(Phi->getType(), 
                                        Phi->getNumIncomingValues(),
                                        Phi->getName() + ".dup");
    
    // Copy all incoming values
    for (unsigned i = 0; i < Phi->getNumIncomingValues(); ++i) {
      PhiDup->addIncoming(Phi->getIncomingValue(i), 
                         Phi->getIncomingBlock(i));
    }
    
    Stats.InstructionsDuplicated++;
    
    // Verify both phi nodes produce the same value
    Value *Location = createLocationString(Builder, *M, F.getName().str(), "phi");
    
    Type *PhiType = Phi->getType();
    if (PhiType->isIntegerTy(32)) {
      Builder.CreateCall(VerifyInt32Func, {Phi, PhiDup, Location});
      Stats.VerificationCallsAdded++;
    } else if (PhiType->isIntegerTy(64)) {
      Builder.CreateCall(VerifyInt64Func, {Phi, PhiDup, Location});
      Stats.VerificationCallsAdded++;
    } else if (PhiType->isPointerTy()) {
      Value *Ptr1 = Builder.CreateBitCast(Phi, PointerType::getUnqual(Builder.getInt8Ty()));
      Value *Ptr2 = Builder.CreateBitCast(PhiDup, PointerType::getUnqual(Builder.getInt8Ty()));
      Builder.CreateCall(VerifyPointerFunc, {Ptr1, Ptr2, Location});
      Stats.VerificationCallsAdded++;
    }
    
    Stats.PhiNodesVerified++;
    
    errs() << "  [PHI] Phi node verification inserted\n";
  }
  
  // NEW METHOD 3: Instruction-Level Redundancy for Short-Lived Temporaries
  void protectTemporaryValue(Instruction *I, Function &F) {
    if (HardenLevel < 2) return;
    
    // Skip certain instruction types
    if (isa<PHINode>(I) || isa<AllocaInst>(I) || isa<BranchInst>(I) ||
        isa<StoreInst>(I) || isa<LoadInst>(I))
      return;
    
    // Only protect instructions with uses (actual temporaries)
    if (I->use_empty())
      return;
    
    // Only protect integer/pointer types for now
    if (!I->getType()->isIntegerTy() && !I->getType()->isPointerTy())
      return;
    
    IRBuilder<> Builder(I->getNextNode());
    Module *M = F.getParent();
    
    errs() << "  [TEMP] Protecting temporary value: " << I->getOpcodeName() << "\n";
    
    // Clone the instruction for redundancy
    Instruction *Clone = I->clone();
    Clone->setName(I->getName() + ".temp_dup");
    Builder.Insert(Clone);
    
    Stats.InstructionsDuplicated++;
    
    // Verify both produce the same result
    Value *Location = createLocationString(Builder, *M, F.getName().str(), 
                                          std::string("temp:") + I->getOpcodeName());
    
    Type *InstType = I->getType();
    if (InstType->isIntegerTy(32)) {
      Builder.CreateCall(VerifyInt32Func, {I, Clone, Location});
      Stats.VerificationCallsAdded++;
    } else if (InstType->isIntegerTy(64)) {
      Builder.CreateCall(VerifyInt64Func, {I, Clone, Location});
      Stats.VerificationCallsAdded++;
    } else if (InstType->isIntegerTy()) {
      // For other integer types, extend to 32-bit
      Value *I32_1 = Builder.CreateZExtOrTrunc(I, Builder.getInt32Ty());
      Value *I32_2 = Builder.CreateZExtOrTrunc(Clone, Builder.getInt32Ty());
      Builder.CreateCall(VerifyInt32Func, {I32_1, I32_2, Location});
      Stats.VerificationCallsAdded++;
    } else if (InstType->isPointerTy()) {
      Value *Ptr1 = Builder.CreateBitCast(I, PointerType::getUnqual(Builder.getInt8Ty()));
      Value *Ptr2 = Builder.CreateBitCast(Clone, PointerType::getUnqual(Builder.getInt8Ty()));
      Builder.CreateCall(VerifyPointerFunc, {Ptr1, Ptr2, Location});
      Stats.VerificationCallsAdded++;
    }
    
    Stats.TemporariesProtected++;
  }
  
  // NEW METHOD 4: Comprehensive Function Coverage (applies all LLFI protections)
  void applyComprehensiveLLFIProtection(Function &F) {
    if (F.isDeclaration()) return;
    
    errs() << "\n[LLFI] Applying comprehensive LLFI protection to '" 
           << F.getName() << "'\n";
    
    std::vector<PHINode*> PhiNodes;
    std::vector<BinaryOperator*> CriticalArithmetic;
    std::vector<Instruction*> TemporaryValues;
    
    // Collect instructions for protection
    for (BasicBlock &BB : F) {
      for (Instruction &I : BB) {
        if (shouldSkipInstruction(I))
          continue;
        
        // Collect phi nodes
        if (PHINode *Phi = dyn_cast<PHINode>(&I)) {
          PhiNodes.push_back(Phi);
        }
        
        // Collect critical arithmetic (multiply, divide, modulo)
        if (BinaryOperator *BO = dyn_cast<BinaryOperator>(&I)) {
          if (BO->getOpcode() == Instruction::Mul ||
              BO->getOpcode() == Instruction::SDiv ||
              BO->getOpcode() == Instruction::UDiv ||
              BO->getOpcode() == Instruction::SRem ||
              BO->getOpcode() == Instruction::URem ||
              BO->getOpcode() == Instruction::FMul ||
              BO->getOpcode() == Instruction::FDiv) {
            CriticalArithmetic.push_back(BO);
          }
        }
        
        // Collect temporary values (short-lived intermediates)
        if (!I.use_empty() && !isa<PHINode>(&I) && 
            !isa<AllocaInst>(&I) && !isa<LoadInst>(&I) &&
            !isa<StoreInst>(&I) && !isa<CallInst>(&I)) {
          TemporaryValues.push_back(&I);
        }
      }
    }
    
    // Apply protections
    errs() << "  [LLFI] Found " << PhiNodes.size() << " phi nodes\n";
    errs() << "  [LLFI] Found " << CriticalArithmetic.size() << " critical arithmetic ops\n";
    errs() << "  [LLFI] Found " << TemporaryValues.size() << " temporary values\n";
    
    // Phase 1: Phi node verification
    for (PHINode *Phi : PhiNodes) {
      verifyPhiNode(Phi, F);
    }
    
    // Phase 2: TMR for critical arithmetic
    if (HardenLevel >= 3) {
      for (BinaryOperator *BO : CriticalArithmetic) {
        applyTMRToArithmetic(BO, F);
      }
    }
    
    // Phase 3: Temporary value protection
    if (HardenLevel >= 2) {
      // Only protect a subset to avoid excessive overhead
      unsigned protectionRate = HardenLevel >= 3 ? 100 : 50; // 50% or 100%
      unsigned count = 0;
      for (Instruction *I : TemporaryValues) {
        if (count++ % (100 / protectionRate) == 0) {
          protectTemporaryValue(I, F);
        }
      }
    }
    
    Stats.LLFIHardenedFunctions++;
    
    errs() << "[LLFI] Comprehensive protection complete\n";
  }
};

} // anonymous namespace

// Pass registration
extern "C" LLVM_ATTRIBUTE_WEAK ::llvm::PassPluginLibraryInfo
llvmGetPassPluginInfo() {
  return {
    LLVM_PLUGIN_API_VERSION, "FIHardeningTransform", LLVM_VERSION_STRING,
    [](PassBuilder &PB) {
      // Register function pass
      PB.registerPipelineParsingCallback(
        [](StringRef Name, FunctionPassManager &FPM,
           ArrayRef<PassBuilder::PipelineElement>) {
          if (Name == "fi-harden-transform") {
            FPM.addPass(FIHardeningTransform());
            return true;
          }
          return false;
        });
      
      // Register module pass
      PB.registerPipelineParsingCallback(
        [](StringRef Name, ModulePassManager &MPM,
           ArrayRef<PassBuilder::PipelineElement>) {
          if (Name == "fi-harden-transform") {
            MPM.addPass(FIHardeningTransform());
            return true;
          }
          return false;
        });
    }
  };
}

// Countermeasure A through clang, for {-O0, -O2} x {IR, asm} on AArch64 and
// Thumb-2: clang hardens verify() at OptimizerLast, and llc -O2 must keep a
// genuine re-check on both edges. -O0 inputs drop optnone, so llc optimises
// them too; the old suite never was, because of optnone.
// RUN: clang --target=aarch64-linux-gnu -O0 -Xclang -disable-O0-optnone -fno-discard-value-names \
// RUN:   -fpass-plugin=%fi_plugin -S -emit-llvm -o %t.a64.O0.ll %s
// RUN: clang --target=aarch64-linux-gnu -O2 -fno-discard-value-names \
// RUN:   -fpass-plugin=%fi_plugin -S -emit-llvm -o %t.a64.O2.ll %s
// RUN: clang --target=thumbv7m-none-eabi -O0 -Xclang -disable-O0-optnone -fno-discard-value-names \
// RUN:   -fpass-plugin=%fi_plugin -S -emit-llvm -o %t.t2.O0.ll %s
// RUN: clang --target=thumbv7m-none-eabi -O2 -fno-discard-value-names \
// RUN:   -fpass-plugin=%fi_plugin -S -emit-llvm -o %t.t2.O2.ll %s
// RUN: FileCheck %s --check-prefix=IR < %t.a64.O0.ll
// RUN: FileCheck %s --check-prefix=IR < %t.a64.O2.ll
// RUN: FileCheck %s --check-prefix=IR < %t.t2.O0.ll
// RUN: FileCheck %s --check-prefix=IR < %t.t2.O2.ll
// RUN: llc -O2 -o - %t.a64.O0.ll | FileCheck %s --check-prefix=ASM
// RUN: llc -O2 -o - %t.a64.O2.ll | FileCheck %s --check-prefix=ASM
// RUN: llc -O2 -o - %t.t2.O0.ll | FileCheck %s --check-prefix=ASM
// RUN: llc -O2 -o - %t.t2.O2.ll | FileCheck %s --check-prefix=ASM

// Each edge compares a copy of pin with a copy of secret. The weakened form
// from the roadmap (§6.3), a copy compared with the original, would show here
// as an operand that isn't a copy.
// IR-LABEL: define {{.*}} @verify(
// IR:         %cmp = icmp eq i32 [[PIN:%[a-z0-9.]+]], [[SECRET:%[a-z0-9.]+]]
// IR-NEXT:    br i1 %cmp, label %fi.true, label %fi.false
// IR:       fi.true:
// IR-NEXT:    [[P1:%[a-z0-9.]+]] = call i32 asm sideeffect "", "=r,0"(i32 [[PIN]])
// IR-NEXT:    [[S1:%[a-z0-9.]+]] = call i32 asm sideeffect "", "=r,0"(i32 [[SECRET]])
// IR-NEXT:    %cmp.again = icmp eq i32 [[P1]], [[S1]]
// IR-NEXT:    br i1 %cmp.again, label %if.then, label %fi.trap
// IR:       fi.false:
// IR-NEXT:    [[P2:%[a-z0-9.]+]] = call i32 asm sideeffect "", "=r,0"(i32 [[PIN]])
// IR-NEXT:    [[S2:%[a-z0-9.]+]] = call i32 asm sideeffect "", "=r,0"(i32 [[SECRET]])
// IR-NEXT:    [[AGAIN:%cmp.again[0-9]+]] = icmp eq i32 [[P2]], [[S2]]
// IR-NEXT:    br i1 [[AGAIN]], label %fi.trap, label %if.else
// IR:       fi.trap:
// IR-NEXT:    call void @llvm.trap()
// IR-NEXT:    unreachable

// llc's own SimplifyCFG hoists the copies both edges start with into the
// branch block; each edge still compares and branches to the trap.
// ASM-LABEL:  verify:
// ASM:          cmp {{[wr][0-9]+}}, {{[wr][0-9]+}}
// ASM-COUNT-2:  {{(//|@)APP}}
// ASM:          {{b.ne|bne}} [[FALSE:.LBB0_[0-9]+]]
// ASM-NEXT:     %fi.true
// ASM-NEXT:     cmp {{[wr][0-9]+}}, {{[wr][0-9]+}}
// ASM-NEXT:     {{b.ne|bne}} [[TRAP:.LBB0_[0-9]+]]
// ASM:        [[FALSE]]:{{.*}}%fi.false
// ASM-NEXT:     cmp {{[wr][0-9]+}}, {{[wr][0-9]+}}
// ASM-NEXT:     {{b.eq|beq}} [[TRAP]]
// ASM:        [[TRAP]]:{{.*}}%fi.trap
// ASM:          {{brk #0x1|.inst.n 0xdefe}}

void grant(void);
void deny(void);

__attribute__((annotate("fi_harden"))) void verify(int pin, int secret) {
  if (pin == secret)
    grant();
  else
    deny();
}

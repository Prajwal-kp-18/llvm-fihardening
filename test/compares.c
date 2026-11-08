// Countermeasure B through clang, for {-O0, -O2} x {IR, asm} on AArch64 and
// Thumb-2: a VerifyPIN-style return pin_ok, and a compare that's stored,
// branched on and returned, so A and B both apply to it. -O0 inputs drop
// optnone, so llc optimises them too.
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
// RUN: llc -O2 -o - %t.a64.O0.ll | FileCheck %s --check-prefixes=ASM,A64
// RUN: llc -O2 -o - %t.a64.O2.ll | FileCheck %s --check-prefixes=ASM,A64
// RUN: llc -O2 -o - %t.t2.O0.ll | FileCheck %s --check-prefixes=ASM,T2
// RUN: llc -O2 -o - %t.t2.O2.ll | FileCheck %s --check-prefixes=ASM,T2

// The inverse compares a copy of pin with a copy of secret, and pin_ok is
// stored (-O0) or returned (-O2) from the copy the check compared.
// IR-LABEL: define {{.*}} @verify(
// IR:         %cmp = icmp eq i32 [[PIN:%[a-z0-9.]+]], [[SECRET:%[a-z0-9.]+]]
// IR-NEXT:    [[Z:%[0-9]+]] = zext i1 %cmp to i8
// IR-NEXT:    %cmp.copy = call i8 asm sideeffect "", "=r,0"(i8 [[Z]])
// IR-NEXT:    [[C:%[0-9]+]] = trunc i8 %cmp.copy to i1
// IR-NEXT:    [[P:%[a-z0-9.]+]] = call i32 asm sideeffect "", "=r,0"(i32 [[PIN]])
// IR-NEXT:    [[S:%[a-z0-9.]+]] = call i32 asm sideeffect "", "=r,0"(i32 [[SECRET]])
// IR-NEXT:    %cmp.inv = icmp ne i32 [[P]], [[S]]
// IR-NEXT:    [[IZ:%[0-9]+]] = zext i1 %cmp.inv to i8
// IR-NEXT:    %cmp.inv.copy = call i8 asm sideeffect "", "=r,0"(i8 [[IZ]])
// IR-NEXT:    [[I:%[0-9]+]] = trunc i8 %cmp.inv.copy to i1
// IR-NEXT:    [[NOT:%[0-9]+]] = xor i1 [[I]], true
// IR-NEXT:    [[OK:%[0-9]+]] = icmp eq i1 [[C]], [[NOT]]
// IR-NEXT:    br i1 [[OK]], label %fi.ok, label %fi.trap
// IR:       fi.ok:
// IR-NEXT:    %conv = zext i1 [[C]] to i32
// IR:       fi.trap:
// IR-NEXT:    call void @llvm.trap()
// IR-NEXT:    unreachable

// B checks the compare; the stored flag reads the copy and the branch doesn't:
// it's A's, which re-checks both edges. One trap block.
// IR-LABEL: define {{.*}} @both(
// IR:         %cmp.inv = icmp ne i32
// IR:         br i1 {{%[0-9]+}}, label %fi.ok, label %fi.trap
// IR:       fi.ok:
// IR-NEXT:    %conv = zext i1 {{%[0-9]+}} to i32
// IR:         br i1 {{%cmp|%tobool}}, label %fi.true, label %fi.false
// IR:       fi.false:
// IR:         br i1 {{%[a-z.]+again[0-9]+}}, label %fi.trap, label %if.end
// IR:       fi.true:
// IR:         br i1 {{%[a-z.]+again}}, label %if.then, label %fi.trap
// IR:       fi.trap:{{.*}}preds = %entry, %fi.false, %fi.true

// The inverse keeps the reversed predicate (cset ne, movne). The check
// compares the register that's returned (w0) or stored and returned (r0) with
// the negated inverse (bic) and traps unless they're equal, so a skipped and
// that leaves junk there traps too. On Thumb-2 the trap is the fall-through of
// a predicated return: skipping bxeq reaches it.
// A64-LABEL:  verify:
// A64:          cmp w0, w1
// A64:          cset [[C:w[0-9]+]], eq
// A64-COUNT-3:  //APP
// A64:          cmp w0, w1
// A64-NEXT:     and w0, [[C]], #0x1
// A64-NEXT:     cset [[INV:w[0-9]+]], ne
// A64-NEXT:     //APP
// A64:          bic [[EXP:w[0-9]+]], {{w[0-9]+}}, [[INV]]
// A64-NEXT:     cmp w0, [[EXP]]
// A64-NEXT:     b.ne [[TRAP:.LBB0_[0-9]+]]
// A64:        [[TRAP]]:{{.*}}%fi.trap
// A64:          brk #0x1
// T2-LABEL:   verify:
// T2:           subs [[C:r[0-9]+]], r0, r1
// T2-NEXT:      clz [[C]], [[C]]
// T2-NEXT:      lsrs [[C]], [[C]], #5
// T2-COUNT-3:   @APP
// T2:           subs [[INV:r[0-9]+]], {{r[0-9]+}}, {{r[0-9]+}}
// T2-NEXT:      it ne
// T2-NEXT:      movne [[INV]], #1
// T2-NEXT:      @APP
// T2:           and r0, [[C]], #1
// T2-NEXT:      bic.w [[EXP:r[0-9]+]], {{r[0-9]+}}, [[INV]]
// T2-NEXT:      cmp r0, [[EXP]]
// T2-NEXT:      {{itt?}} eq
// T2:           bxeq lr
// T2-NEXT:    {{.*}}%fi.trap
// T2-NEXT:      .inst.n 0xdefe

// B's check traps unless equal; A's true edge traps if false, its false edge
// if true; all three go to one trap.
// ASM-LABEL:  both:
// ASM-COUNT-4:  {{(//|@)APP}}
// ASM:          {{b.ne|bne}} [[TRAP:.LBB1_[0-9]+]]
// ASM:          %fi.true
// ASM:          {{b.ne|bne|cbz}} {{.*}}[[TRAP]]
// ASM:          %fi.false
// ASM:          {{b.eq|beq|cbnz}} {{.*}}[[TRAP]]
// ASM:        [[TRAP]]:{{.*}}%fi.trap
// ASM:          {{brk #0x1|.inst.n 0xdefe}}

void grant(void);
int g_ok;

__attribute__((annotate("fi_harden"))) int verify(int pin, int secret) {
  int pin_ok = pin == secret;
  return pin_ok;
}

__attribute__((annotate("fi_harden"))) int both(int pin, int secret) {
  int ok = pin == secret;
  g_ok = ok;
  if (ok)
    grant();
  return ok;
}

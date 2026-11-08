; fi-harden-copies runs every compare on opaque copies of its operands, so the
; barrier (lib/OpaqueCopy.cpp) is tested before any countermeasure uses it.
; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-copies,verify -S %s | FileCheck %s

; Two copies of one value stay two. Without them opt -O2 folds icmp eq %a, %a
; to true and deletes the trap. The copies hide their output, not their input,
; which is why fi-harden runs after all IR optimisation (see OpaqueCopy.cpp).
; RUN: opt -load-pass-plugin=%fi_plugin -passes='function(fi-harden-copies),default<O2>' -S %s \
; RUN:   | FileCheck %s --check-prefix=O2
; RUN: opt -load-pass-plugin=%fi_plugin -passes='function(fi-harden-copies),default<O2>' %s \
; RUN:   | llc -O2 -mtriple=aarch64-linux-gnu -o - | FileCheck %s --check-prefix=A64
; RUN: opt -load-pass-plugin=%fi_plugin -passes='function(fi-harden-copies),default<O2>' %s \
; RUN:   | llc -O2 -mtriple=thumbv7m-none-eabi -o - | FileCheck %s --check-prefix=T2
; x86 can't allocate a register for an i17 operand; the i32 carrier compiles.
; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-copies %s \
; RUN:   | llc -O2 -mtriple=x86_64-linux-gnu -o /dev/null

; Vectors and anything over 64 bits get no copy, so their compares are skipped.
; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-copies -pass-remarks-missed=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=SKIP
; SKIP:      icmp left alone: operands have no opaque copy
; SKIP-NEXT: icmp left alone: operands have no opaque copy
; SKIP-NEXT: fcmp left alone: operands have no opaque copy

; CHECK-LABEL: @same(
; CHECK-NEXT:    %a.copy = call i32 asm sideeffect "", "=r,0"(i32 %a) #[[NOUNWIND:[0-9]+]]
; CHECK-NEXT:    %a.copy1 = call i32 asm sideeffect "", "=r,0"(i32 %a) #[[NOUNWIND]]
; CHECK-NEXT:    %c = icmp eq i32 %a.copy, %a.copy1
; O2-LABEL:    @same(
; O2-NEXT:       %a.copy = tail call i32 asm sideeffect "", "=r,0"(i32 %a)
; O2-NEXT:       %a.copy1 = tail call i32 asm sideeffect "", "=r,0"(i32 %a)
; O2-NEXT:       %c = icmp eq i32 %a.copy, %a.copy1
; O2-NEXT:       br i1 %c
; A64-LABEL:   same:
; A64-COUNT-2:   //APP
; A64:           cmp {{w[0-9]+}}, {{w[0-9]+}}
; A64-NEXT:      b.ne
; A64:           brk
; T2-LABEL:    same:
; T2-COUNT-2:    @APP
; T2:            cmp {{r[0-9]+}}, {{r[0-9]+}}
; T2:            .inst.n 0xdefe
define void @same(i32 %a) {
  %c = icmp eq i32 %a, %a
  br i1 %c, label %ok, label %trap
ok:
  ret void
trap:
  call void @llvm.trap()
  unreachable
}

; i1 goes through i8, as clang passes a bool to asm.
; CHECK-LABEL: @bool(
; CHECK-NEXT:    [[X:%.*]] = zext i1 %x to i8
; CHECK-NEXT:    [[XC:%.*]] = call i8 asm sideeffect "", "=r,0"(i8 [[X]])
; CHECK-NEXT:    [[X1:%.*]] = trunc i8 [[XC]] to i1
define i1 @bool(i1 %x, i1 %y) {
  %c = icmp eq i1 %x, %y
  ret i1 %c
}

; CHECK-LABEL: @odd(
; CHECK-NEXT:    [[N:%.*]] = zext i17 %n to i32
; CHECK-NEXT:    [[NC:%.*]] = call i32 asm sideeffect "", "=r,0"(i32 [[N]])
; CHECK-NEXT:    [[N1:%.*]] = trunc i32 [[NC]] to i17
define i1 @odd(i17 %n, i17 %m) {
  %c = icmp ult i17 %n, %m
  ret i1 %c
}

; Pointers go in as they are; constants are copied too.
; CHECK-LABEL: @ptr(
; CHECK-NEXT:    %p.copy = call ptr asm sideeffect "", "=r,0"(ptr %p)
; CHECK-NEXT:    [[NULL:%.*]] = call ptr asm sideeffect "", "=r,0"(ptr null)
; CHECK-NEXT:    %c = icmp eq ptr %p.copy, [[NULL]]
define i1 @ptr(ptr %p) {
  %c = icmp eq ptr %p, null
  ret i1 %c
}

; Floating point goes through an integer of its width.
; CHECK-LABEL: @float(
; CHECK-NEXT:    [[F:%.*]] = bitcast float %f to i32
; CHECK-NEXT:    [[FC:%.*]] = call i32 asm sideeffect "", "=r,0"(i32 [[F]])
; CHECK-NEXT:    [[F1:%.*]] = bitcast i32 [[FC]] to float
define i1 @float(float %f, float %g) {
  %c = fcmp olt float %f, %g
  ret i1 %c
}

; CHECK-LABEL: @double(
; CHECK-NEXT:    [[D:%.*]] = bitcast double %d to i64
; CHECK-NEXT:    [[DC:%.*]] = call i64 asm sideeffect "", "=r,0"(i64 [[D]])
define i1 @double(double %d) {
  %c = fcmp une double %d, 0.0
  ret i1 %c
}

; CHECK-LABEL: @skipped(
; CHECK-NOT:     asm
; CHECK:         ret
define <2 x i1> @skipped(<2 x i32> %v, <2 x i32> %w, i128 %x, i128 %y, fp128 %f, fp128 %g) {
  %c1 = icmp eq <2 x i32> %v, %w
  %c2 = icmp eq i128 %x, %y
  %c3 = fcmp oeq fp128 %f, %g
  %r1 = select i1 %c2, <2 x i1> %c1, <2 x i1> zeroinitializer
  %r2 = select i1 %c3, <2 x i1> %r1, <2 x i1> zeroinitializer
  ret <2 x i1> %r2
}

; CHECK: attributes #[[NOUNWIND]] = { nounwind }

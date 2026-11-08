; Countermeasure B: a compare whose result is used as a value is checked
; against its inverse, recomputed from opaque copies, and its users read a copy
; of the checked result.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;compares>,verify' -S %s | FileCheck %s
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;compares>' -pass-remarks=fi-harden \
; RUN:   -pass-remarks-missed=fi-harden -disable-output %s 2>&1 | FileCheck %s --check-prefix=REMARK
; Every kind lowers on both targets, with A on too.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>' %s \
; RUN:   | llc -O2 -mtriple=aarch64-linux-gnu -o /dev/null
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>' %s \
; RUN:   | llc -O2 -mtriple=thumbv7m-none-eabi -o /dev/null

; Without compares, compares are left alone.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;branches>' -S %s \
; RUN:   | FileCheck %s --check-prefix=OFF
; OFF-NOT: .inv =

; With both, A re-checks the branch use and B the value use, and they share
; the trap.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;branches;compares>,verify' -S %s \
; RUN:   | FileCheck %s --check-prefix=BOTH

; REMARK: hardening ret:
; REMARK: icmp checked against its inverse
; REMARK: hardening nan:
; REMARK: fcmp checked against its inverse
; REMARK: hardening branch_only:
; REMARK-NOT: checked against its inverse
; REMARK: hardening wide:
; REMARK: icmp left alone: operands have no opaque copy
; REMARK: hardening vec:
; REMARK: icmp left alone: operands have no opaque copy

; Trap unless the copy of %c equals the negated copy of the inverse; the return
; reads the copy.
; CHECK-LABEL: @ret(
; CHECK:         %c = icmp eq i32 %a, %b
; CHECK-NEXT:    [[Z:%.*]] = zext i1 %c to i8
; CHECK-NEXT:    %c.copy = call i8 asm sideeffect "", "=r,0"(i8 [[Z]])
; CHECK-NEXT:    [[C:%.*]] = trunc i8 %c.copy to i1
; CHECK-NEXT:    %a.copy = call i32 asm sideeffect "", "=r,0"(i32 %a)
; CHECK-NEXT:    %b.copy = call i32 asm sideeffect "", "=r,0"(i32 %b)
; CHECK-NEXT:    %c.inv = icmp ne i32 %a.copy, %b.copy
; CHECK-NEXT:    [[IZ:%.*]] = zext i1 %c.inv to i8
; CHECK-NEXT:    %c.inv.copy = call i8 asm sideeffect "", "=r,0"(i8 [[IZ]])
; CHECK-NEXT:    [[I:%.*]] = trunc i8 %c.inv.copy to i1
; CHECK-NEXT:    [[NOT:%.*]] = xor i1 [[I]], true
; CHECK-NEXT:    [[OK:%.*]] = icmp eq i1 [[C]], [[NOT]]
; CHECK-NEXT:    br i1 [[OK]], label %fi.ok, label %fi.trap
; CHECK:       fi.ok:
; CHECK-NEXT:    %r = zext i1 [[C]] to i32
; CHECK-NEXT:    ret i32 %r
; CHECK:       fi.trap:
; CHECK-NEXT:    call void @llvm.trap()
; CHECK-NEXT:    unreachable
define i32 @ret(i32 %a, i32 %b) {
  %c = icmp eq i32 %a, %b
  %r = zext i1 %c to i32
  ret i32 %r
}

; The inverse of olt is uge: a NaN gives false, then true.
; CHECK-LABEL: @nan(
; CHECK:         %c.inv = fcmp uge double {{%[0-9]+}}, {{%[0-9]+}}
define i1 @nan(double %x, double %y) {
  %c = fcmp olt double %x, %y
  ret i1 %c
}

; The inverse keeps the flags, so both compares lower alike.
; CHECK-LABEL: @fast(
; CHECK:         %c.inv = fcmp nnan ugt float {{%[0-9]+}}, {{%[0-9]+}}
define i1 @fast(float %x, float %y) {
  %c = fcmp nnan ole float %x, %y
  ret i1 %c
}

; A select condition; the constant stays an immediate.
; CHECK-LABEL: @sel(
; CHECK:         %x.copy = call i32 asm sideeffect "", "=r,0"(i32 %x)
; CHECK-NEXT:    %c.inv = icmp uge i32 %x.copy, 42
; CHECK:       fi.ok:
; CHECK-NEXT:    %r = select i1 [[C:%[0-9]+]], i32 %t, i32 %f
define i32 @sel(i32 %x, i32 %t, i32 %f) {
  %c = icmp ult i32 %x, 42
  %r = select i1 %c, i32 %t, i32 %f
  ret i32 %r
}

; A stored flag; a pointer compare with null.
; CHECK-LABEL: @store(
; CHECK:         %c.inv = icmp ne ptr %p.copy, null
; CHECK:       fi.ok:
; CHECK-NEXT:    store i1 {{%[0-9]+}}, ptr %q
define void @store(ptr %p, ptr %q) {
  %c = icmp eq ptr %p, null
  store i1 %c, ptr %q
  ret void
}

; The branch keeps %c: it's A's. The return reads the copy.
; CHECK-LABEL: @both(
; CHECK:         [[C:%[0-9]+]] = trunc i8 %c.copy to i1
; CHECK:         br i1 {{%[0-9]+}}, label %fi.ok, label %fi.trap
; CHECK:       fi.ok:
; CHECK-NEXT:    br i1 %c, label %t, label %f
; CHECK:       f:
; CHECK-NEXT:    %r = zext i1 [[C]] to i32
; BOTH-LABEL: @both(
; BOTH:         %c.inv = icmp ne i32
; BOTH:         br i1 {{%[0-9]+}}, label %fi.ok, label %fi.trap
; BOTH:       fi.ok:
; BOTH-NEXT:    br i1 %c, label %fi.true, label %fi.false
; BOTH:       fi.false:
; BOTH:         %c.again{{[0-9]+}} = icmp eq i32
; BOTH-NEXT:    br i1 %c.again{{[0-9]+}}, label %fi.trap, label %f
; BOTH:       fi.true:
; BOTH:         %c.again = icmp eq i32
; BOTH-NEXT:    br i1 %c.again, label %t, label %fi.trap
; BOTH-NOT:   .inv =
; BOTH:       fi.trap:{{.*}}preds = %0, %fi.false, %fi.true
define i32 @both(i32 %a, i32 %b) {
  %c = icmp eq i32 %a, %b
  br i1 %c, label %t, label %f
t:
  call void @grant()
  br label %f
f:
  %r = zext i1 %c to i32
  ret i32 %r
}

; The phi reads the copy, from the block the split leaves the branch in.
; CHECK-LABEL: @phi(
; CHECK:         %c.inv = icmp sle i32 %a.copy, %b.copy
; CHECK:       j:
; CHECK-NEXT:    %r = phi i1 [ {{%[0-9]+}}, %fi.ok ], [ false, %e ]
define i1 @phi(i32 %a, i32 %b, i1 %d) {
entry:
  %c = icmp sgt i32 %a, %b
  br i1 %d, label %j, label %e
e:
  br label %j
j:
  %r = phi i1 [ %c, %entry ], [ false, %e ]
  ret i1 %r
}

; Left alone: a compare used only by a branch (A's), and compares with no
; opaque copy of their operands.
; CHECK-LABEL: @branch_only(
; CHECK-NEXT:    %c = icmp eq i32 %a, %b
; CHECK-NEXT:    br i1 %c, label %t, label %f
; CHECK-NOT:   fi.
; CHECK-LABEL: @wide(
; CHECK-NEXT:    %c = icmp eq i128 %x, %y
; CHECK-NEXT:    ret i1 %c
; CHECK-LABEL: @vec(
; CHECK-NEXT:    %c = icmp eq <2 x i32> %x, %y
; CHECK-NEXT:    ret <2 x i1> %c
define i32 @branch_only(i32 %a, i32 %b) {
  %c = icmp eq i32 %a, %b
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

define i1 @wide(i128 %x, i128 %y) {
  %c = icmp eq i128 %x, %y
  ret i1 %c
}

define <2 x i1> @vec(<2 x i32> %x, <2 x i32> %y) {
  %c = icmp eq <2 x i32> %x, %y
  ret <2 x i1> %c
}

declare void @grant()

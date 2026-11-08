; Countermeasure A: each edge of a conditional branch recomputes the condition
; from opaque copies and traps unless it matches the edge taken.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;branches>,verify' -S %s | FileCheck %s
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;branches>' -pass-remarks=fi-harden \
; RUN:   -pass-remarks-missed=fi-harden -disable-output %s 2>&1 | FileCheck %s --check-prefix=REMARK
; Every kind lowers on both targets.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;branches>' %s \
; RUN:   | llc -O2 -mtriple=aarch64-linux-gnu -o /dev/null
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;branches>' %s \
; RUN:   | llc -O2 -mtriple=thumbv7m-none-eabi -o /dev/null

; Without branches, branches are left alone.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;compares>' -S %s \
; RUN:   | FileCheck %s --check-prefix=OFF
; OFF-NOT: fi.true

; trap=call reaches the handler from these checks too.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;trap=call>' -S %s \
; RUN:   | FileCheck %s --check-prefix=CALL
; CALL:      fi.trap:
; CALL-NEXT:   call void @fi_trap()
; CALL-NEXT:   call void @llvm.trap()

; REMARK: hardening cmp:
; REMARK: branch re-checked on both edges: icmp recomputed from copies
; REMARK: hardening nan:
; REMARK: branch re-checked on both edges: fcmp recomputed from copies
; REMARK: hardening flag:
; REMARK: branch re-checked on both edges: condition copied
; REMARK: hardening wide:
; REMARK: icmp left alone: operands have no opaque copy
; REMARK: branch re-checked on both edges: condition copied
; REMARK: hardening sw:
; REMARK: switch left alone: only conditional branches are re-checked

; True edge: trap unless the recomputed compare is true. False edge: unless
; it's false.
; CHECK-LABEL: @cmp(
; CHECK:         %c = icmp eq i32 %a, %b
; CHECK-NEXT:    br i1 %c, label %fi.true, label %fi.false
; CHECK:       fi.true:
; CHECK-NEXT:    %a.copy = call i32 asm sideeffect "", "=r,0"(i32 %a)
; CHECK-NEXT:    %b.copy = call i32 asm sideeffect "", "=r,0"(i32 %b)
; CHECK-NEXT:    %c.again = icmp eq i32 %a.copy, %b.copy
; CHECK-NEXT:    br i1 %c.again, label %t, label %fi.trap
; CHECK:       fi.false:
; CHECK-NEXT:    %a.copy1 = call i32 asm sideeffect "", "=r,0"(i32 %a)
; CHECK-NEXT:    %b.copy2 = call i32 asm sideeffect "", "=r,0"(i32 %b)
; CHECK-NEXT:    %c.again3 = icmp eq i32 %a.copy1, %b.copy2
; CHECK-NEXT:    br i1 %c.again3, label %fi.trap, label %f
; CHECK:       fi.trap:
; CHECK-NEXT:    call void @llvm.trap()
; CHECK-NEXT:    unreachable
define i32 @cmp(i32 %a, i32 %b) {
  %c = icmp eq i32 %a, %b
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

; The same predicate on bitwise copies gives the same answer for NaN.
; CHECK-LABEL: @nan(
; CHECK:       fi.true:
; CHECK:         %c.again = fcmp une double {{%[0-9]+}}, {{%[0-9]+}}
; CHECK-NEXT:    br i1 %c.again, label %t, label %fi.trap
; CHECK:       fi.false:
; CHECK:         %c.again3 = fcmp une double {{%[0-9]+}}, {{%[0-9]+}}
; CHECK-NEXT:    br i1 %c.again3, label %fi.trap, label %f
define i32 @nan(double %x, double %y) {
  %c = fcmp une double %x, %y
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

; A condition that isn't a compare is checked through a copy of the i1.
; CHECK-LABEL: @flag(
; CHECK:       fi.true:
; CHECK-NEXT:    [[X:%.*]] = zext i1 %on to i8
; CHECK-NEXT:    [[XC:%.*]] = call i8 asm sideeffect "", "=r,0"(i8 [[X]])
; CHECK-NEXT:    [[ON:%.*]] = trunc i8 [[XC]] to i1
; CHECK-NEXT:    br i1 [[ON]], label %t, label %fi.trap
; CHECK:       fi.false:
; CHECK:         br i1 {{%[0-9]+}}, label %fi.trap, label %f
define i32 @flag(i1 %on) {
  br i1 %on, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

; Constants stay immediates.
; CHECK-LABEL: @imm(
; CHECK:       fi.true:
; CHECK-NEXT:    %x.copy = call i32 asm sideeffect "", "=r,0"(i32 %x)
; CHECK-NEXT:    %c.again = icmp ult i32 %x.copy, 42
define i32 @imm(i32 %x) {
  %c = icmp ult i32 %x, 42
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

; The back edge goes through its check block, and the phi follows it.
; CHECK-LABEL: @loop(
; CHECK:       head:
; CHECK-NEXT:    %i = phi i32 [ 0, %entry ], [ %i.next, %fi.true ]
; CHECK:         br i1 %c, label %fi.true, label %fi.false
; CHECK:       fi.true:
; CHECK:         br i1 %c.again, label %head, label %fi.trap
define i32 @loop(i32 %n) {
entry:
  br label %head
head:
  %i = phi i32 [ 0, %entry ], [ %i.next, %head ]
  %i.next = add i32 %i, 1
  %c = icmp slt i32 %i.next, %n
  br i1 %c, label %head, label %exit
exit:
  ret i32 %i.next
}

; No opaque copy of an i128: the compare can't be redone, so the i1 is copied.
; CHECK-LABEL: @wide(
; CHECK:       fi.true:
; CHECK-NEXT:    zext i1 %c to i8
define i32 @wide(i128 %x, i128 %y) {
  %c = icmp eq i128 %x, %y
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

; Left alone: switch, a constant condition, a branch with one target.
; CHECK-LABEL: @sw(
; CHECK-NEXT:    switch i32 %x, label %d [
; CHECK-NOT:   fi.
; CHECK-LABEL: @constant(
; CHECK-NEXT:    br i1 true, label %t, label %f
; CHECK-NOT:   fi.
; CHECK-LABEL: @one_target(
; CHECK-NEXT:    br i1 %c, label %t, label %t
; CHECK-NOT:   fi.
define i32 @sw(i32 %x) {
  switch i32 %x, label %d [ i32 1, label %t ]
t:
  ret i32 1
d:
  ret i32 0
}

define i32 @constant() {
  br i1 true, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

define i32 @one_target(i1 %c) {
  br i1 %c, label %t, label %t
t:
  ret i32 1
}

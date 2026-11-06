; Old defect 3: atomicrmw, va_arg and callbr were duplicated, so
; atomic_fetch_add incremented twice and va_arg advanced the list twice. Each
; must stay exactly once.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>,verify' -S %s | FileCheck %s
; CHECK-LABEL: @rmw(
; CHECK:       atomicrmw
; CHECK-NOT:   atomicrmw
; CHECK-LABEL: @va(
; CHECK:       va_arg
; CHECK-NOT:   va_arg
; CHECK-LABEL: @cbr(
; CHECK:       callbr
; CHECK-NOT:   callbr

; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-skips -pass-remarks-missed=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=SKIP
; SKIP: atomicrmw left alone: atomic
; SKIP: va_arg left alone: va_arg
; SKIP: callbr left alone: callbr

define i1 @rmw(ptr %p) {
  %old = atomicrmw add ptr %p, i32 1 seq_cst
  %c = icmp eq i32 %old, 0
  ret i1 %c
}

define i1 @va(ptr %ap) {
  %v = va_arg ptr %ap, i32
  %c = icmp eq i32 %v, 0
  ret i1 %c
}

define i32 @cbr(i32 %x) {
entry:
  callbr void asm "", "r,!i"(i32 %x) to label %normal [label %indirect]
normal:
  ret i32 0
indirect:
  ret i32 1
}

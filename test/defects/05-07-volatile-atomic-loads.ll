; Old defects 5 and 7: volatile (MMIO) loads were duplicated, re-reading a
; device register, and duplicated atomic loads lost their ordering. A check on a
; loaded value must copy the value, never load it again.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>,verify' -S %s | FileCheck %s
; CHECK-LABEL: @mmio(
; CHECK:       load volatile i32
; CHECK-NOT:   load
; CHECK-LABEL: @flag(
; CHECK:       load atomic i32
; CHECK-NOT:   load

; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-skips -pass-remarks-missed=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=SKIP
; SKIP: load left alone: volatile
; SKIP: load left alone: atomic

define i32 @mmio(ptr %reg) {
entry:
  %v = load volatile i32, ptr %reg, align 4
  %c = icmp eq i32 %v, 0
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 %v
}

define i1 @flag(ptr %p) {
  %v = load atomic i32, ptr %p acquire, align 4
  %c = icmp ne i32 %v, 0
  ret i1 %c
}

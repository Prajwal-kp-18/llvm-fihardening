; The plugin loads, fi-harden runs and the module still verifies.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>,verify' -disable-output %s

; With all, one remark per defined function; declarations are never touched.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>' -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --implicit-check-not=remark
; CHECK: remark: {{.*}}hardening f: branches, compares

define i32 @f(i32 %a, i32 %b) {
  %c = icmp eq i32 %a, %b
  %r = zext i1 %c to i32
  ret i32 %r
}

declare void @g()

; Old defect 11: error blocks ended in unreachable after a call that returns.
; Reaching them was UB, so the optimizer could delete the checks. Every
; unreachable in hardened code must directly follow call void @llvm.trap(),
; which is noreturn. @already_trapping keeps grep from finding nothing.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>,verify' -S %s -o %t.ll
; RUN: grep -B1 '^ *unreachable$' %t.ll | not grep -v -e '^ *unreachable$' -e '@llvm.trap()' -e '^--$'

declare void @llvm.trap() cold noreturn nounwind

define void @already_trapping() {
  call void @llvm.trap()
  unreachable
}

define i32 @check(i32 %a, i32 %b) {
  %c = icmp eq i32 %a, %b
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

define i1 @flag(i32 %a, i32 %b) {
  %c = icmp ult i32 %a, %b
  ret i1 %c
}

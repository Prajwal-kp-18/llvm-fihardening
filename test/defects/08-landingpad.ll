; Old defect 8: a check was inserted before a landingpad, which must be the
; first non-PHI instruction of its block. The compare and branch inside this
; landing pad are hardening sites; the landingpad has to stay first.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>,verify' -S %s | FileCheck %s
; CHECK:      lpad:
; CHECK-NEXT:   landingpad

; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-skips -pass-remarks-missed=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=SKIP
; SKIP: landingpad left alone: EH pad

declare i32 @__gxx_personality_v0(...)
declare void @may_throw(i32)
declare void @handle(i32)

define void @f(i32 %x) personality ptr @__gxx_personality_v0 {
entry:
  invoke void @may_throw(i32 %x) to label %done unwind label %lpad
done:
  ret void
lpad:
  %lp = landingpad { ptr, i32 } cleanup
  %sel = extractvalue { ptr, i32 } %lp, 1
  %c = icmp eq i32 %sel, 1
  br i1 %c, label %one, label %other
one:
  call void @handle(i32 1)
  resume { ptr, i32 } %lp
other:
  resume { ptr, i32 } %lp
}

; Old defect 2: C++ invoke was treated as an ordinary value and duplicated, and
; inserting after it (a terminator) segfaulted. invoke and landingpad are left
; alone; the compare after the invoke may still be hardened.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>,verify' -S %s | FileCheck %s
; CHECK:     invoke i32 @may_throw
; CHECK-NOT: invoke
; CHECK:     landingpad
; CHECK-NOT: landingpad

; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-skips -pass-remarks-missed=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=SKIP
; SKIP: invoke left alone: invoke
; SKIP: landingpad left alone: EH pad

declare i32 @__gxx_personality_v0(...)
declare i32 @may_throw(i32)
declare ptr @__cxa_begin_catch(ptr)
declare void @__cxa_end_catch()

define i32 @f(i32 %x) personality ptr @__gxx_personality_v0 {
entry:
  %r = invoke i32 @may_throw(i32 %x) to label %ok unwind label %lpad
ok:
  %c = icmp eq i32 %r, 0
  br i1 %c, label %zero, label %nonzero
zero:
  ret i32 0
nonzero:
  ret i32 %r
lpad:
  %lp = landingpad { ptr, i32 } catch ptr null
  %e = extractvalue { ptr, i32 } %lp, 0
  %p = call ptr @__cxa_begin_catch(ptr %e)
  call void @__cxa_end_catch()
  ret i32 -1
}

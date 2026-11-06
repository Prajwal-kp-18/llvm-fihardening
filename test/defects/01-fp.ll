; Old defect 1: hardening a floating-point multiply emitted icmp on double, and
; opt aborted. An FP compare must be re-evaluated with fcmp, or skipped.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>,verify' -S %s | FileCheck %s
; CHECK-NOT: icmp {{.*}}double
; CHECK:     fcmp olt double
; CHECK-NOT: icmp {{.*}}double
; CHECK:     fcmp oeq double
; CHECK-NOT: icmp {{.*}}double

; FP arithmetic and compares are pure, so countermeasures may re-evaluate them.
; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-skips -pass-remarks-missed=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=SKIP --allow-empty
; SKIP-NOT: remark

define i1 @mul_branch(double %a, double %b) {
entry:
  %m = fmul double %a, %b
  %c = fcmp olt double %m, 1.0
  br i1 %c, label %t, label %f
t:
  ret i1 true
f:
  ret i1 false
}

define i1 @div_return(double %a, double %b) {
  %d = fdiv double %a, %b
  %c = fcmp oeq double %d, %b
  ret i1 %c
}

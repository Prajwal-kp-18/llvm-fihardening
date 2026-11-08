; Test inputs don't carry optnone unless the test says why: llc doesn't
; optimise an optnone function, so a check that survives in a test could
; still be optimised away in a real -O2 build. The old suite never noticed,
; because clang -O0 marks every function optnone.
; Hand-written IR: none at all.
; RUN: not grep -nE '^(attributes|define) .*optnone' %S/*.ll %S/defects/*.ll
; clang -O0 adds optnone unless -disable-O0-optnone. Only clang.c keeps it, to
; show fi-harden still runs on optnone functions.
; RUN: grep -E 'RUN: +clang .*-O0 ' %S/*.c | grep -v disable-O0-optnone | FileCheck %s
; CHECK-NOT: RUN{{:}}
; CHECK:     clang.c:// RUN{{:}} clang -O0 -fpass-plugin
; CHECK-NOT: RUN{{:}}

; fi-harden<...> selects countermeasures; no parameters means all of them.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<branches>' -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=BRANCHES
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<compares>' -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=COMPARES
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<compares;branches>' -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=BOTH
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden' -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=BOTH

; BRANCHES: countermeasures: branches{{$}}
; COMPARES: countermeasures: compares{{$}}
; BOTH: countermeasures: branches, compares{{$}}

; RUN: not opt -load-pass-plugin=%fi_plugin -passes='fi-harden<bogus>' -disable-output %s 2>&1 \
; RUN:   | FileCheck %s --check-prefix=BAD
; RUN: not opt -load-pass-plugin=%fi_plugin -passes='fi-harden<branches;>' -disable-output %s 2>&1 \
; RUN:   | FileCheck %s --check-prefix=EMPTY
; BAD: invalid fi-harden parameter 'bogus'; expected branches or compares
; EMPTY: invalid fi-harden parameter ''

define void @f() {
  ret void
}

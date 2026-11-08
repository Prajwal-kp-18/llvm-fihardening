; fi-harden<...> selects countermeasures; naming none means all of them. all
; hardens every defined function instead of only the marked ones.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;branches>' -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=BRANCHES
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<compares;all>' -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=COMPARES
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all;compares;branches>' -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=BOTH
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>' -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=BOTH

; BRANCHES: hardening f: branches{{$}}
; COMPARES: hardening f: compares{{$}}
; BOTH: hardening f: branches, compares{{$}}

; The parsed parameters print back in pipeline syntax.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<compares;branches>' -print-pipeline-passes \
; RUN:   -disable-output %s | FileCheck %s --check-prefix=PRINT
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<branches;all>' -print-pipeline-passes \
; RUN:   -disable-output %s | FileCheck %s --check-prefix=PRINT-ALL
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<compares;allowlist=list.txt>' \
; RUN:   -print-pipeline-passes -disable-output %s | FileCheck %s --check-prefix=PRINT-LIST
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<branches;trap=call>' -print-pipeline-passes \
; RUN:   -disable-output %s | FileCheck %s --check-prefix=PRINT-TRAP
; PRINT: fi-harden<branches;compares>
; PRINT-ALL: fi-harden<all;branches>
; PRINT-LIST: fi-harden<allowlist=list.txt;compares>
; PRINT-TRAP: fi-harden<trap=call;branches>

; RUN: not opt -load-pass-plugin=%fi_plugin -passes='fi-harden<bogus>' -disable-output %s 2>&1 \
; RUN:   | FileCheck %s --check-prefix=BAD
; RUN: not opt -load-pass-plugin=%fi_plugin -passes='fi-harden<branches;>' -disable-output %s 2>&1 \
; RUN:   | FileCheck %s --check-prefix=EMPTY
; RUN: not opt -load-pass-plugin=%fi_plugin -passes='fi-harden<allowlist=>' -disable-output %s 2>&1 \
; RUN:   | FileCheck %s --check-prefix=NO-FILE
; BAD: invalid fi-harden parameter 'bogus'; expected all, allowlist=<file>, trap=call, branches or compares
; EMPTY: invalid fi-harden parameter ''
; NO-FILE: invalid fi-harden parameter 'allowlist='

define void @f() {
  ret void
}

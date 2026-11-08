// clang -fpass-plugin runs fi-harden at OptimizerLast, at -O0 and -O2, on the
// functions marked annotate("fi_harden") only.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -Rpass=fi-harden -S -o /dev/null %s 2>&1 \
// RUN:   | FileCheck %s --implicit-check-not='remark: hardening'
// RUN: clang -O0 -fpass-plugin=%fi_plugin -Rpass=fi-harden -S -o /dev/null %s 2>&1 \
// RUN:   | FileCheck %s --implicit-check-not='remark: hardening'
// CHECK: remark: hardening check_pin: branches, compares

// It's the last pass that changes function bodies: after it come only
// module cleanups and remarks. An optimisation after it can undo a check:
// branches.ll shows GVN turning a re-check into a compare of a with itself.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -mllvm -print-pipeline-passes -S -o /dev/null %s \
// RUN:   | FileCheck %s --check-prefix=PIPELINE
// RUN: clang -O0 -Xclang -disable-O0-optnone -fpass-plugin=%fi_plugin -mllvm -print-pipeline-passes \
// RUN:   -S -o /dev/null %s | FileCheck %s --check-prefix=PIPELINE-O0
// PIPELINE: ,fi-harden<branches;compares>,globaldce,constmerge,cg-profile,rel-lookup-table-converter,lower-comment-string,function(annotation-remarks){{$}}
// PIPELINE-O0: ,fi-harden<branches;compares>,lower-comment-string,function(annotation-remarks){{$}}

// -mllvm -fi-harden takes the same parameters as fi-harden<...>.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden=all,branches \
// RUN:   -Rpass=fi-harden -S -o /dev/null %s 2>&1 | FileCheck %s --check-prefix=ALL
// RUN: clang -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden=allowlist=%S/Inputs/allowlist.txt \
// RUN:   -Rpass=fi-harden -S -o /dev/null %s 2>&1 | FileCheck %s --check-prefix=LIST --implicit-check-not='remark: hardening'
// RUN: not clang -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden=bogus \
// RUN:   -S -o /dev/null %s 2>&1 | FileCheck %s --check-prefix=BAD
// ALL: remark: hardening check_pin: branches{{ }}
// ALL: remark: hardening helper: branches{{ }}
// ALL: remark: hardening listed: branches{{ }}
// LIST: remark: hardening check_pin: branches, compares
// LIST: remark: hardening listed: branches, compares
// BAD: invalid fi-harden parameter 'bogus'

__attribute__((annotate("fi_harden"))) int check_pin(int a, int b) {
  return a == b;
}

int helper(int x) { return x + 1; }

int listed(int x) { return x - 1; }

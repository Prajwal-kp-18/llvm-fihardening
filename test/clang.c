// clang -fpass-plugin runs fi-harden at OptimizerLast, at -O0 and -O2, on the
// functions marked annotate("fi_harden") only.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -Rpass=fi-harden -S -o /dev/null %s 2>&1 \
// RUN:   | FileCheck %s --implicit-check-not=remark
// RUN: clang -O0 -fpass-plugin=%fi_plugin -Rpass=fi-harden -S -o /dev/null %s 2>&1 \
// RUN:   | FileCheck %s --implicit-check-not=remark
// CHECK: remark: hardening check_pin: branches, compares

// It sits in the -O2 pipeline under its own name.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -mllvm -print-pipeline-passes -S -o /dev/null %s \
// RUN:   | FileCheck %s --check-prefix=PIPELINE
// PIPELINE: ,fi-harden<branches;compares>,

// -mllvm -fi-harden takes the same parameters as fi-harden<...>.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden=all,branches \
// RUN:   -Rpass=fi-harden -S -o /dev/null %s 2>&1 | FileCheck %s --check-prefix=ALL
// RUN: not clang -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden=bogus \
// RUN:   -S -o /dev/null %s 2>&1 | FileCheck %s --check-prefix=BAD
// ALL: remark: hardening check_pin: branches{{ }}
// ALL: remark: hardening helper: branches{{ }}
// BAD: invalid fi-harden parameter 'bogus'

__attribute__((annotate("fi_harden"))) int check_pin(int a, int b) {
  return a == b;
}

int helper(int x) { return x + 1; }

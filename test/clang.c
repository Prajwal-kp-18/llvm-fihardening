// clang -fpass-plugin runs fi-harden at OptimizerLast, at -O0 and -O2.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -Rpass=fi-harden -S -o /dev/null %s 2>&1 | FileCheck %s
// RUN: clang -O0 -fpass-plugin=%fi_plugin -Rpass=fi-harden -S -o /dev/null %s 2>&1 | FileCheck %s
// CHECK: remark: countermeasures: branches, compares

// It sits in the -O2 pipeline under its own name.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -mllvm -print-pipeline-passes -S -o /dev/null %s \
// RUN:   | FileCheck %s --check-prefix=PIPELINE
// PIPELINE: ,fi-harden<branches;compares>,

// -mllvm -fi-harden-countermeasures picks countermeasures from clang.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden-countermeasures=branches \
// RUN:   -Rpass=fi-harden -S -o /dev/null %s 2>&1 | FileCheck %s --check-prefix=BRANCHES
// RUN: not clang -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden-countermeasures=bogus \
// RUN:   -S -o /dev/null %s 2>&1 | FileCheck %s --check-prefix=BAD
// BRANCHES: remark: countermeasures: branches{{ }}
// BAD: invalid fi-harden parameter 'bogus'

int f(int a, int b) { return a == b; }

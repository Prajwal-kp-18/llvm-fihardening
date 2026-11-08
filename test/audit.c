// End to end: clang compiles these programs straight to objects for AArch64
// and Thumb-2, through the whole backend after OptimizerLast (SelectionDAG
// CSE, DAGCombine, MachineCSE, branch folding, tail merging), and
// eval/audit.py checks that every check the remarks promise is still there.
// RUN: clang --target=aarch64-linux-gnu -O0 -Xclang -disable-O0-optnone -fpass-plugin=%fi_plugin \
// RUN:   -c -o %t.a64.O0.o %s -fsave-optimization-record -foptimization-record-file=%t.a64.O0.yaml
// RUN: clang --target=aarch64-linux-gnu -O2 -fpass-plugin=%fi_plugin \
// RUN:   -c -o %t.a64.O2.o %s -fsave-optimization-record -foptimization-record-file=%t.a64.O2.yaml
// RUN: clang --target=thumbv7m-none-eabi -O0 -Xclang -disable-O0-optnone -fpass-plugin=%fi_plugin \
// RUN:   -c -o %t.t2.O0.o %s -fsave-optimization-record -foptimization-record-file=%t.t2.O0.yaml
// RUN: clang --target=thumbv7m-none-eabi -O2 -fpass-plugin=%fi_plugin \
// RUN:   -c -o %t.t2.O2.o %s -fsave-optimization-record -foptimization-record-file=%t.t2.O2.yaml
// RUN: %audit %t.a64.O0.o %t.a64.O0.yaml | FileCheck %s --implicit-check-not=FAIL
// RUN: %audit %t.a64.O2.o %t.a64.O2.yaml | FileCheck %s --implicit-check-not=FAIL
// RUN: %audit %t.t2.O0.o %t.t2.O0.yaml | FileCheck %s --implicit-check-not=FAIL
// RUN: %audit %t.t2.O2.o %t.t2.O2.yaml | FileCheck %s --implicit-check-not=FAIL

// With trap=call, the trap block gets its own prologue and a call to fi_trap.
// RUN: clang --target=aarch64-linux-gnu -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden=trap=call \
// RUN:   -c -o %t.a64.call.o %s -fsave-optimization-record -foptimization-record-file=%t.a64.call.yaml
// RUN: clang --target=thumbv7m-none-eabi -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden=trap=call \
// RUN:   -c -o %t.t2.call.o %s -fsave-optimization-record -foptimization-record-file=%t.t2.call.yaml
// RUN: %audit %t.a64.call.o %t.a64.call.yaml | FileCheck %s --implicit-check-not=FAIL
// RUN: %audit %t.t2.call.o %t.t2.call.yaml | FileCheck %s --implicit-check-not=FAIL

// sig_ok's unrolled loop shares tail-merged check blocks between branches;
// each branch still counts both edges.
// CHECK: ok and3:
// CHECK: ok boot:
// CHECK: ok both:
// CHECK: ok counter:
// CHECK: ok fp:
// CHECK: ok in_range:
// CHECK: ok sig_ok:
// CHECK: ok sw:
// CHECK: ok verify_pin:

// The audit fails when checks are missing: an unhardened object, or one built
// with branches only, against the full build's remarks. Remarks without
// fi-harden are an error, not a pass.
// RUN: clang --target=thumbv7m-none-eabi -O2 -c -o %t.plain.o %s \
// RUN:   -fsave-optimization-record -foptimization-record-file=%t.plain.yaml
// RUN: not %audit %t.plain.o %t.t2.O2.yaml | FileCheck %s --check-prefix=LOST
// RUN: clang --target=thumbv7m-none-eabi -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden=branches \
// RUN:   -c -o %t.branches.o %s
// RUN: not %audit %t.branches.o %t.t2.O2.yaml | FileCheck %s --check-prefix=NOCMP
// RUN: not %audit %t.plain.o %t.plain.yaml 2>&1 | FileCheck %s --check-prefix=NONE
// LOST: FAIL and3: 3 promised, 0 found
// LOST: FAIL verify_pin: {{[0-9]+}} promised, 0 found
// NOCMP: FAIL and3: 3 promised, 0 found
// NOCMP: ok boot: 2 promised, 2 found
// NONE: no fi-harden remarks in

#define H __attribute__((annotate("fi_harden")))
void grant(void);
void a(void);
void b(void);
void c(void);
int g_ok;

// VerifyPIN, FISSC-style: a byte loop that clears a flag.
H int verify_pin(const unsigned char *pin, const unsigned char *ref) {
  int ok = 1;
  for (int i = 0; i < 4; i++)
    if (pin[i] != ref[i])
      ok = 0;
  return ok;
}

// An early-exit compare loop, as in a signature check.
H int sig_ok(const unsigned char *x, const unsigned char *y, int n) {
  for (int i = 0; i < n; i++)
    if (x[i] != y[i])
      return 0;
  return 1;
}

H int and3(int a, int b, int c, int d, int e, int f) {
  if (a == b && c == d && e == f)
    return 1;
  return 0;
}

H int in_range(unsigned x, unsigned lo, unsigned hi) {
  return x >= lo && x <= hi;
}

H void boot(int sig, int expected) {
  if (sig == expected)
    grant();
}

// Stored, branched on and returned: both countermeasures apply.
H int both(int pin, int secret) {
  int ok = pin == secret;
  g_ok = ok;
  if (ok)
    grant();
  return ok;
}

H int counter(const int *v, int n) {
  int s = 0;
  for (int i = 0; i < n; i++)
    s += v[i];
  return s;
}

H double fp(double x, double y) { return x < y ? x : y; }

// A switch is left alone; the branches it lowers to aren't checks.
H void sw(int x) {
  switch (x) {
  case 1:
    a();
    break;
  case 2:
    b();
    break;
  case 7:
    c();
    break;
  }
}

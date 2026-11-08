// fi-harden runs at OptimizerLast, after the inliner, so a marked function
// inlined into an unmarked caller would leave its decision there, unhardened.
// Marked functions stay out of line instead, static ones too.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -S -emit-llvm -o - %s | FileCheck %s
// CHECK-LABEL: define {{.*}} @verify(
// CHECK:         call void @llvm.trap()
// CHECK-LABEL: define {{.*}} @caller(
// CHECK:         call {{.*}} @verify(
// CHECK:         call {{.*}} @verify_static(
// CHECK-LABEL: define {{.*}} @verify_static(
// CHECK:         call void @llvm.trap()

// With all, every caller is hardened too, so inlining stays allowed.
// RUN: clang -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden=all -S -emit-llvm -o - %s \
// RUN:   | FileCheck %s --check-prefix=ALL
// ALL-LABEL: define {{.*}} @caller(
// ALL-NOT:     call {{.*}} @verify
// ALL:         call void @llvm.trap()

// always_inline asks for the opposite.
// RUN: not clang -O2 -fpass-plugin=%fi_plugin -DALWAYS -c -o /dev/null %s 2>&1 \
// RUN:   | FileCheck %s --check-prefix=ALWAYS
// ALWAYS: fi-harden: 'forced' is always_inline, but a hardened function must stay out of line

void grant(void);

__attribute__((annotate("fi_harden"))) int verify(int pin, int secret) {
  return pin == secret;
}

static __attribute__((annotate("fi_harden"))) int verify_static(int pin,
                                                                int secret) {
  return pin == secret;
}

void caller(int pin) {
  if (verify(pin, 1234))
    grant();
  if (verify_static(pin, 4321))
    grant();
}

#ifdef ALWAYS
__attribute__((annotate("fi_harden"), always_inline)) inline int forced(int a) {
  return a == 7;
}
int use(int a) { return forced(a); }
#endif

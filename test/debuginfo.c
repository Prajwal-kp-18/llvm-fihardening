// With -g, an fi_trap defined in the same module (a unity build, or the
// runtime linked in) has debug info, so trap=call's call to it needs a
// location or the module doesn't verify. The trap block gets line 0 in the
// hardened function's scope.
// RUN: clang -g -O2 -fpass-plugin=%fi_plugin -mllvm -fi-harden=trap=call -S -emit-llvm -o %t.ll %s
// RUN: opt -passes=verify -disable-output %t.ll 2>&1 | count 0
// RUN: FileCheck %s < %t.ll
// CHECK:     call void @fi_trap(){{.*}}, !dbg [[LOC:![0-9]+]]
// CHECK-DAG: [[LOC]] = !DILocation(line: 0, scope: [[SP:![0-9]+]])
// CHECK-DAG: [[SP]] = distinct !DISubprogram(name: "verify"

void fi_trap(void) {
  for (;;) {
  }
}

__attribute__((annotate("fi_harden"))) int verify(int pin, int secret) {
  return pin == secret;
}

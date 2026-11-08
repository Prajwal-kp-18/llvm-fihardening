// Reference handler for fi-harden<trap=call>: a failed check calls fi_trap,
// then traps, so skipping the call or returning from it still traps. Replace
// the body with your response (count the fault, wipe keys, reset the device)
// and keep it short, without stdio or abort(): each instruction in it is one
// more place to inject a fault. fi-harden never hardens fi_trap.
//
// This one spins until a reset (a watchdog, a debugger). One fault can't get
// it out: breaking the first loop lands in the second.
void fi_trap(void) {
  static volatile int Spin = 1;
  while (Spin) {
  }
  while (Spin) {
  }
}

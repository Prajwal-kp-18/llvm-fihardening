// Bare-metal Cortex-M startup for eval/fisim.py: vector table, reset handler,
// and the addresses the simulator stops at. No libc. The program provides
// int main(void); its return value lands in fi_result.
extern unsigned _sidata[], _sdata[], _edata[], _sbss[], _ebss[], _estack[];
int main(void);

volatile int fi_result;

// The simulator stops when it reaches one of these. noinline + the asm keep
// each a distinct address.
__attribute__((noinline, noreturn)) void fi_done(void) { for (;;) __asm__ volatile(""); }
__attribute__((noinline, noreturn)) void fi_fault(void) { for (;;) __asm__ volatile(""); }
// trap=call's handler: reaching it means a check fired.
__attribute__((noinline, noreturn)) void fi_trap(void) { for (;;) __asm__ volatile(""); }
// A program calls this on a bad outcome, for simulators that stop at an
// address (ARMORY's halting points). It returns, so fisim.py doesn't notice.
__attribute__((noinline)) void fi_bad(void) { __asm__ volatile(""); }

__attribute__((noreturn)) void Reset_Handler(void) {
  // volatile, so the compiler can't turn the loops into memcpy/memset calls.
  for (volatile unsigned *s = _sidata, *d = _sdata; d < _edata;)
    *d++ = *s++;
  for (volatile unsigned *d = _sbss; d < _ebss;)
    *d++ = 0;
  fi_result = main();
  fi_done();
}

// Initial SP, reset, then every fault and interrupt: fi_fault.
__attribute__((section(".vectors"), used)) void (*const fi_vectors[16])(void) = {
    (void (*)(void))_estack, Reset_Handler, fi_fault, fi_fault, fi_fault, fi_fault,
    fi_fault, 0, 0, 0, 0, fi_fault, fi_fault, 0, fi_fault, fi_fault};

// eval/fisim.py on a bare-metal Cortex-M3 PIN check, wrong in its last digit:
// unhardened, one skipped instruction gets the PIN accepted (main returns 1);
// with fi-harden none does, and the checks fire. Faulting only check() also
// means the window is found, and .data is copied (the PIN is there).
// REQUIRES: fisim
// RUN: clang --target=thumbv7m-none-eabi -mcpu=cortex-m3 -O2 -ffreestanding -nostdlib \
// RUN:   -fuse-ld=lld -T %S/../eval/cm/cm.ld %S/../eval/cm/start.c %s -o %t.plain.elf
// RUN: clang --target=thumbv7m-none-eabi -mcpu=cortex-m3 -O2 -ffreestanding -nostdlib \
// RUN:   -fuse-ld=lld -T %S/../eval/cm/cm.ld %S/../eval/cm/start.c %s -o %t.hard.elf \
// RUN:   -fpass-plugin=%fi_plugin
// RUN: %python %S/../eval/fisim.py %t.plain.elf check | FileCheck --check-prefix=PLAIN %s
// RUN: %python %S/../eval/fisim.py %t.hard.elf check | FileCheck --check-prefix=HARD %s

// PLAIN: golden: ret=0,
// PLAIN: skip: {{.*}} ret=1 {{[1-9]}}
// HARD: golden: ret=0,
// Outcomes print sorted (crash, ret=0, ret=1, ..., timeout, trap): no ret=1.
// HARD: skip: {{[0-9]+ faults, (crash [0-9]+, )?ret=0 [0-9]+, (timeout [0-9]+, )?trap [1-9]}}

unsigned char pin[4] = {1, 2, 3, 0};
static const unsigned char ref[4] = {1, 2, 3, 4};

__attribute__((annotate("fi_harden"), noinline)) int check(void) {
  for (int i = 0; i < 4; i++)
    if (pin[i] != ref[i])
      return 0;
  return 1;
}

int main(void) { return check(); }

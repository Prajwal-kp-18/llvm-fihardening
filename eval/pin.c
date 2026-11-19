// A PIN check under attack: the attacker enters a wrong PIN and faults one
// instruction of the marked functions; "GRANTED" means the attack worked.
#include <stdio.h>
#include <stdlib.h>
#define H __attribute__((annotate("fi_harden"), noinline))

// trap=call handler for the experiment: says it caught the fault.
void fi_trap(void) {
  puts("TRAPPED");
  _Exit(77);
}

// FISSC VerifyPIN style: a byte loop that clears a flag (countermeasure B).
H int verify_pin(const unsigned char *pin, const unsigned char *ref) {
  int ok = 1;
  for (int i = 0; i < 4; i++)
    if (pin[i] != ref[i])
      ok = 0;
  return ok;
}

// The decision itself: early exit, then a branch to grant (countermeasure A).
H int auth(const unsigned char *pin, const unsigned char *ref) {
  for (int i = 0; i < 4; i++)
    if (pin[i] != ref[i])
      return 0;
  return 1;
}

int main(int argc, char **argv) {
  static const unsigned char ref[4] = {1, 2, 3, 4};
  unsigned char pin[4] = {1, 2, 3, 4};
  pin[3] = (unsigned char)atoi(argv[2]);       // wrong unless argv[2] is 4
  int ok = argv[1][0] == 'v' ? verify_pin(pin, ref) : auth(pin, ref);
  puts(ok ? "GRANTED" : "DENIED");
  return 0;
}

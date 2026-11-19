// main for FISSC's VerifyPIN on eval/cm, replacing its main.c (which prints).
// The user PIN is wrong: 0000 against 1234 (FISSC's), or with -DLAST_DIGIT
// only its last digit is (1230). Returns what FISSC's oracles say: 1 the wrong
// PIN was accepted, 2 the try counter wasn't decremented, 4 VerifyPIN's own
// countermeasure fired; 0 nothing bad.
typedef unsigned char BOOL;
void initialize(void);
BOOL verifyPIN(void);
BOOL oracle_auth(void);
BOOL oracle_ptc(void);
extern unsigned char g_countermeasure, g_userPin[];
void fi_bad(void);

int main(void) {
  initialize();
#ifdef LAST_DIGIT
  for (int i = 0; i < 3; i++)
    g_userPin[i] = i + 1;
#endif
  verifyPIN();
  if (g_countermeasure == 1)
    return 4;
  int r = oracle_auth() | oracle_ptc() << 1;
  if (r & 1)
    fi_bad(); // for eval/armory.sh: the wrong PIN was accepted
  return r;
}

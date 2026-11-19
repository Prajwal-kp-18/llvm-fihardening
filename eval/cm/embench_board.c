// Embench's board hooks on eval/cm. eval/overhead.py counts the instructions
// executed between the two triggers, that is, in benchmark().
__attribute__((noinline)) void initialise_board(void) {}
__attribute__((noinline)) void start_trigger(void) { __asm__ volatile(""); }
__attribute__((noinline)) void stop_trigger(void) { __asm__ volatile(""); }

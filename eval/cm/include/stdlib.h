// The libc the Embench kernels use on eval/cm; ../libc.c implements it.
#include <stddef.h>
void exit(int) __attribute__((noreturn));
void abort(void) __attribute__((noreturn));

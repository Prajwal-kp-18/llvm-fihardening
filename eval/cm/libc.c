// The libc the Embench kernels need on eval/cm. Build it with -fno-builtin, or
// the loops become calls to the functions they implement.
#include <stdlib.h>
#include <string.h>

extern volatile int fi_result;
void fi_done(void) __attribute__((noreturn));

void *memcpy(void *d, const void *s, size_t n) {
  char *p = d;
  const char *q = s;
  while (n--)
    *p++ = *q++;
  return d;
}

void *memset(void *d, int c, size_t n) {
  char *p = d;
  while (n--)
    *p++ = c;
  return d;
}

int memcmp(const void *a, const void *b, size_t n) {
  const unsigned char *p = a, *q = b;
  for (; n; n--, p++, q++)
    if (*p != *q)
      return *p - *q;
  return 0;
}

// The Arm run-time ABI's versions, which clang calls for struct copies. The
// 4 and 8 variants only promise alignment.
void __aeabi_memcpy(void *d, const void *s, size_t n) { memcpy(d, s, n); }
void __aeabi_memcpy4(void *, const void *, size_t) __attribute__((alias("__aeabi_memcpy")));
void __aeabi_memcpy8(void *, const void *, size_t) __attribute__((alias("__aeabi_memcpy")));
void __aeabi_memset(void *d, size_t n, int c) { memset(d, c, n); }
void __aeabi_memset4(void *, size_t, int) __attribute__((alias("__aeabi_memset")));
void __aeabi_memset8(void *, size_t, int) __attribute__((alias("__aeabi_memset")));
void __aeabi_memclr(void *d, size_t n) { memset(d, 0, n); }
void __aeabi_memclr4(void *, size_t) __attribute__((alias("__aeabi_memclr")));
void __aeabi_memclr8(void *, size_t) __attribute__((alias("__aeabi_memclr")));

void exit(int status) {
  fi_result = status;
  fi_done();
}

void abort(void) { exit(1); }

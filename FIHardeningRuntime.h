// FIHardeningRuntime.h
// Runtime verification library for fault injection hardening
//
// This header defines the API for runtime verification functions
// called by the transformed IR code.

#ifndef FI_HARDENING_RUNTIME_H
#define FI_HARDENING_RUNTIME_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Verification functions for different data types
void fi_verify_int32(int32_t value, int32_t expected, const char *location);
void fi_verify_int64(int64_t value, int64_t expected, const char *location);
void fi_verify_pointer(void *ptr, void *expected, const char *location);
void fi_verify_branch(int condition, int expected, const char *location);

// Checksum-based memory protection
void fi_checksum_update(void *addr, size_t size);
int fi_checksum_verify(void *addr, size_t size);

// Advanced hardening functions
void fi_verify_cfi(void *target, void *expected, const char *location);
void fi_log_fault(const char *message, int severity);
int fi_check_bounds(void *ptr, void *base, size_t size);
void fi_protect_return_addr(void **addr_location);
int fi_verify_return_addr(void **addr_location);
void fi_validate_hardware_io(void *addr, int32_t expected_value);
void fi_add_timing_noise(void);

// Configuration and statistics
void fi_runtime_init(void);
void fi_runtime_shutdown(void);
void fi_runtime_print_stats(void);

// Error handling modes
typedef enum {
  FI_ERROR_ABORT,     // Abort on mismatch (default)
  FI_ERROR_LOG,       // Log but continue
  FI_ERROR_CORRECT    // Attempt correction
} fi_error_mode_t;

void fi_set_error_mode(fi_error_mode_t mode);
fi_error_mode_t fi_get_error_mode(void);

// Statistics
typedef struct {
  uint64_t verifications_performed;
  uint64_t mismatches_detected;
  uint64_t int32_verifications;
  uint64_t int64_verifications;
  uint64_t pointer_verifications;
  uint64_t branch_verifications;
  uint64_t checksum_verifications;
  uint64_t checksum_failures;
} fi_runtime_stats_t;

const fi_runtime_stats_t *fi_get_stats(void);

#ifdef __cplusplus
}
#endif

#endif // FI_HARDENING_RUNTIME_H

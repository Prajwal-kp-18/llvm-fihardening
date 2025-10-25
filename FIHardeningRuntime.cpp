// FIHardeningRuntime.cpp
// Runtime verification library implementation

#include "FIHardeningRuntime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>

// Global statistics
static fi_runtime_stats_t g_stats = {0};

// Error handling mode
static fi_error_mode_t g_error_mode = FI_ERROR_ABORT;

// Checksum table for memory regions
#define MAX_CHECKSUM_ENTRIES 1024
typedef struct {
  void *addr;
  size_t size;
  uint32_t checksum;
} checksum_entry_t;

static checksum_entry_t g_checksum_table[MAX_CHECKSUM_ENTRIES];
static size_t g_checksum_count = 0;

// Simple checksum calculation (can be replaced with CRC32 for production)
static uint32_t calculate_checksum(void *addr, size_t size) {
  uint32_t sum = 0;
  uint8_t *bytes = (uint8_t *)addr;
  for (size_t i = 0; i < size; i++) {
    sum = (sum << 1) ^ bytes[i];
  }
  return sum;
}

// Find checksum entry
static checksum_entry_t *find_checksum_entry(void *addr, size_t size) {
  for (size_t i = 0; i < g_checksum_count; i++) {
    if (g_checksum_table[i].addr == addr && g_checksum_table[i].size == size) {
      return &g_checksum_table[i];
    }
  }
  return NULL;
}

// Initialization and shutdown
void fi_runtime_init(void) {
  memset(&g_stats, 0, sizeof(g_stats));
  g_checksum_count = 0;
  g_error_mode = FI_ERROR_ABORT;
  
  // Optionally register atexit handler
  atexit(fi_runtime_shutdown);
}

void fi_runtime_shutdown(void) {
  // Print statistics if any verifications were performed
  if (g_stats.verifications_performed > 0) {
    fi_runtime_print_stats();
  }
}

void fi_runtime_print_stats(void) {
  fprintf(stderr, "\n");
  fprintf(stderr, "========================================\n");
  fprintf(stderr, "FI Hardening Runtime Statistics\n");
  fprintf(stderr, "========================================\n");
  fprintf(stderr, "Total verifications:     %lu\n", g_stats.verifications_performed);
  fprintf(stderr, "Mismatches detected:     %lu\n", g_stats.mismatches_detected);
  fprintf(stderr, "  Int32 verifications:   %lu\n", g_stats.int32_verifications);
  fprintf(stderr, "  Int64 verifications:   %lu\n", g_stats.int64_verifications);
  fprintf(stderr, "  Pointer verifications: %lu\n", g_stats.pointer_verifications);
  fprintf(stderr, "  Branch verifications:  %lu\n", g_stats.branch_verifications);
  fprintf(stderr, "  Checksum verifications:%lu\n", g_stats.checksum_verifications);
  fprintf(stderr, "  Checksum failures:     %lu\n", g_stats.checksum_failures);
  
  if (g_stats.verifications_performed > 0) {
    double mismatch_rate = (double)g_stats.mismatches_detected / 
                          g_stats.verifications_performed * 100.0;
    fprintf(stderr, "Mismatch rate:           %.4f%%\n", mismatch_rate);
  }
  
  fprintf(stderr, "========================================\n");
  fprintf(stderr, "\n");
}

const fi_runtime_stats_t *fi_get_stats(void) {
  return &g_stats;
}

void fi_set_error_mode(fi_error_mode_t mode) {
  g_error_mode = mode;
}

fi_error_mode_t fi_get_error_mode(void) {
  return g_error_mode;
}

// Handle verification failure
static void handle_mismatch(const char *type, const char *location, 
                           const char *details) {
  g_stats.mismatches_detected++;
  
  fprintf(stderr, "\n[FI MISMATCH DETECTED]\n");
  fprintf(stderr, "Type:     %s\n", type);
  fprintf(stderr, "Location: %s\n", location ? location : "unknown");
  fprintf(stderr, "Details:  %s\n", details);
  fprintf(stderr, "\n");
  
  switch (g_error_mode) {
    case FI_ERROR_ABORT:
      fprintf(stderr, "Aborting due to fault injection detection!\n");
      abort();
      break;
      
    case FI_ERROR_LOG:
      fprintf(stderr, "Continuing execution (log mode)\n");
      break;
      
    case FI_ERROR_CORRECT:
      fprintf(stderr, "Attempting correction (not fully implemented)\n");
      break;
  }
}

// Verification implementations
void fi_verify_int32(int32_t value, int32_t expected, const char *location) {
  g_stats.verifications_performed++;
  g_stats.int32_verifications++;
  
  if (value != expected) {
    char details[256];
    snprintf(details, sizeof(details), 
             "int32 mismatch: got %d, expected %d", value, expected);
    handle_mismatch("int32", location, details);
  }
}

void fi_verify_int64(int64_t value, int64_t expected, const char *location) {
  g_stats.verifications_performed++;
  g_stats.int64_verifications++;
  
  if (value != expected) {
    char details[256];
    snprintf(details, sizeof(details), 
             "int64 mismatch: got %ld, expected %ld", value, expected);
    handle_mismatch("int64", location, details);
  }
}

void fi_verify_pointer(void *ptr, void *expected, const char *location) {
  g_stats.verifications_performed++;
  g_stats.pointer_verifications++;
  
  if (ptr != expected) {
    char details[256];
    snprintf(details, sizeof(details), 
             "pointer mismatch: got %p, expected %p", ptr, expected);
    handle_mismatch("pointer", location, details);
  }
}

void fi_verify_branch(int condition, int expected, const char *location) {
  g_stats.verifications_performed++;
  g_stats.branch_verifications++;
  
  if (condition != expected) {
    char details[256];
    snprintf(details, sizeof(details), 
             "branch condition mismatch: got %d, expected %d", 
             condition, expected);
    handle_mismatch("branch", location, details);
  }
}

void fi_checksum_update(void *addr, size_t size) {
  // Find or create entry
  checksum_entry_t *entry = find_checksum_entry(addr, size);
  
  if (!entry) {
    // Add new entry
    if (g_checksum_count >= MAX_CHECKSUM_ENTRIES) {
      fprintf(stderr, "Warning: Checksum table full, ignoring update\n");
      return;
    }
    entry = &g_checksum_table[g_checksum_count++];
    entry->addr = addr;
    entry->size = size;
  }
  
  // Calculate and store checksum
  entry->checksum = calculate_checksum(addr, size);
}

int fi_checksum_verify(void *addr, size_t size) {
  g_stats.verifications_performed++;
  g_stats.checksum_verifications++;
  
  checksum_entry_t *entry = find_checksum_entry(addr, size);
  
  if (!entry) {
    fprintf(stderr, "Warning: No checksum entry found for %p (size %zu)\n", 
            addr, size);
    return 1; // Assume OK if no entry
  }
  
  uint32_t current_checksum = calculate_checksum(addr, size);
  
  if (current_checksum != entry->checksum) {
    g_stats.checksum_failures++;
    char details[256];
    snprintf(details, sizeof(details), 
             "memory corruption at %p: checksum %08x, expected %08x",
             addr, current_checksum, entry->checksum);
    handle_mismatch("checksum", "memory_region", details);
    return 0; // Mismatch
  }
  
  return 1; // OK
}

// ===== ADVANCED HARDENING RUNTIME FUNCTIONS =====

// Control-Flow Integrity verification
void fi_verify_cfi(void *target, void *expected, const char *location) {
  g_stats.verifications_performed++;
  
  if (target != expected) {
    char details[256];
    snprintf(details, sizeof(details), 
             "CFI violation: target %p, expected %p at %s",
             target, expected, location);
    handle_mismatch("cfi", "indirect_call", details);
  }
}

// Fault logging
void fi_log_fault(const char *message, int severity) {
  const char *severity_str[] = {"INFO", "WARNING", "ERROR", "CRITICAL"};
  if (severity < 0 || severity > 3) severity = 1;
  
  fprintf(stderr, "[FI-Runtime] [%s] %s\n", severity_str[severity], message);
  
  if (severity >= 2) {
    g_stats.mismatches_detected++;
  }
}

// Memory bounds checking
int fi_check_bounds(void *ptr, void *base, size_t size) {
  g_stats.verifications_performed++;
  
  uintptr_t ptr_addr = (uintptr_t)ptr;
  uintptr_t base_addr = (uintptr_t)base;
  uintptr_t end_addr = base_addr + size;
  
  if (ptr_addr < base_addr || ptr_addr >= end_addr) {
    char details[256];
    snprintf(details, sizeof(details),
             "Bounds check failed: ptr %p outside [%p, %p)",
             ptr, base, (void*)end_addr);
    handle_mismatch("bounds", "memory_access", details);
    return 0; // Out of bounds
  }
  
  return 1; // In bounds
}

// Stack protection: save return address
static uintptr_t g_saved_return_addrs[1024];
static size_t g_return_addr_count = 0;

void fi_protect_return_addr(void **addr_location) {
  if (g_return_addr_count >= 1024) {
    fprintf(stderr, "Warning: Return address protection table full\n");
    return;
  }
  
  // Save the return address
  g_saved_return_addrs[g_return_addr_count++] = (uintptr_t)(*addr_location);
}

int fi_verify_return_addr(void **addr_location) {
  g_stats.verifications_performed++;
  
  if (g_return_addr_count == 0) {
    fprintf(stderr, "Warning: No saved return address to verify\n");
    return 1; // Assume OK
  }
  
  uintptr_t current_addr = (uintptr_t)(*addr_location);
  uintptr_t saved_addr = g_saved_return_addrs[--g_return_addr_count];
  
  if (current_addr != saved_addr) {
    char details[256];
    snprintf(details, sizeof(details),
             "Return address corrupted: current %p, expected %p",
             (void*)current_addr, (void*)saved_addr);
    handle_mismatch("return_addr", "stack", details);
    return 0; // Corrupted
  }
  
  return 1; // OK
}

// Hardware I/O validation
void fi_validate_hardware_io(void *addr, int32_t expected_value) {
  g_stats.verifications_performed++;
  
  // Read actual value from hardware register
  int32_t actual_value = *(volatile int32_t *)addr;
  
  // Simple validation: check if value is reasonable
  // In production, this would have more sophisticated checks
  if (actual_value != expected_value && expected_value != 0) {
    char details[256];
    snprintf(details, sizeof(details),
             "Hardware I/O unexpected: addr %p, value %d, expected %d",
             addr, actual_value, expected_value);
    // Don't abort on I/O mismatches, just log
    fi_log_fault(details, 1); // Warning level
  }
}

// Timing side-channel mitigation
void fi_add_timing_noise(void) {
  // Add random delays to prevent timing analysis
  // In production, use proper random delays
  volatile int dummy = 0;
  for (int i = 0; i < (rand() % 10); i++) {
    dummy += i;
  }
}

// Constructor to initialize runtime (GCC/Clang attribute)
__attribute__((constructor))
static void fi_runtime_constructor(void) {
  fi_runtime_init();
}

// Destructor to print stats (GCC/Clang attribute)
__attribute__((destructor))
static void fi_runtime_destructor(void) {
  // Stats already printed in shutdown, but ensure it happens
}

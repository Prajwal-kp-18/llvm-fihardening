# FIHardeningTransform Benchmarking Guide

## Overview

The `benchmark.sh` script provides comprehensive performance analysis for the FIHardeningTransform pass, measuring:

- **IR Code Bloat**: Lines of code increase
- **Binary Size Overhead**: Executable size increase
- **Pass Compilation Time**: Time to apply transformations
- **Runtime Performance**: Execution time overhead
- **Memory Usage**: Runtime memory consumption

## Usage

### Basic Usage

```bash
./scripts/benchmark.sh
```

This will:
1. Find all `.c` files in `./tests/`
2. Apply transformations and measure metrics
3. Generate results in `./benchmark_results/`

### Directory Structure

```
benchmark_results/
├── benchmark_summary.csv          # Combined results for all tests
├── test_advanced_hardening/       # Per-test directory
│   ├── input.ll                   # Original LLVM IR
│   ├── output_hardened.ll         # Transformed IR
│   ├── test_orig                  # Baseline binary
│   ├── test_hardened              # Hardened binary (if runtime available)
│   ├── metrics.txt                # Human-readable metrics
│   ├── metrics.csv                # CSV format metrics
│   ├── pass_time.txt              # Pass compilation timing
│   ├── runtime_orig.txt           # Baseline runtime stats
│   ├── runtime_hardened.txt       # Hardened runtime stats
│   ├── memory_orig.txt            # Baseline memory stats
│   └── memory_hardened.txt        # Hardened memory stats
└── test_transform/                # Another test
    └── ...
```

## Metrics Explained

### 1. IR Size (lines)
- **Baseline**: Original IR line count
- **Hardened**: Transformed IR line count
- **Overhead**: Percentage increase in code size

### 2. Binary Size (bytes)
- **Baseline**: Original executable size
- **Hardened**: Hardened executable size
- **Overhead**: Percentage increase in binary size

### 3. Pass Compilation Time (seconds)
- Time taken by opt to apply FIHardeningTransform
- Measured using `/usr/bin/time -p`

### 4. Runtime Performance (seconds)
- **Real**: Wall-clock time
- **User**: CPU time in user mode
- **Sys**: CPU time in kernel mode
- **Overhead**: Percentage slowdown

### 5. Memory Usage (KB)
- **Max RSS**: Maximum Resident Set Size
- **Overhead**: Percentage increase in peak memory

## Viewing Results

### Summary Table (All Tests)

```bash
column -t -s',' benchmark_results/benchmark_summary.csv
```

Example output:
```
Test                     Metric      Baseline  Hardened  Overhead_%  Unit
test_advanced_hardening  IR_Size     446       1048      134.00      lines
test_advanced_hardening  Binary_Size 16488     23456     42.25       bytes
test_transform           IR_Size     321       687       114.02      lines
```

### Individual Test Metrics

```bash
cat benchmark_results/test_advanced_hardening/metrics.txt
```

### CSV Format (for spreadsheets)

```bash
cat benchmark_results/test_advanced_hardening/metrics.csv
```

## Requirements

### Essential
- `clang` - LLVM compiler
- `opt` - LLVM optimizer
- FIHardeningTransform.so plugin built

### Optional (for full metrics)
- `/usr/bin/time` - For detailed timing/memory stats
  ```bash
  sudo apt install time
  ```
- `runtime/fi_runtime.c` - Runtime library for hardened binary linking
  (Without this, binary/runtime/memory benchmarks are skipped)

## Runtime Library Support

The hardened IR requires runtime functions for fault injection verification:
- `fi_verify_int32()`, `fi_verify_branch()`, `fi_protect_return_addr()`, etc.

### Option 1: Create Runtime Library

Create `runtime/fi_runtime.c` with stub implementations:

```c
#include <stdio.h>

void fi_verify_int32(int val1, int val2, void* loc) {
    if (val1 != val2) {
        fprintf(stderr, "FI detected at %p\n", loc);
    }
}

void fi_verify_branch(int c1, int c2, void* loc) {
    if (c1 != c2) {
        fprintf(stderr, "Branch FI at %p\n", loc);
    }
}

void fi_protect_return_addr(void* addr) {
    // Stack protection logic
}

void fi_verify_return_addr(void* addr) {
    // Return address verification
}

void fi_log_fault(void* loc) {
    fprintf(stderr, "Fault logged at %p\n", loc);
}

// Add other stubs as needed...
```

### Option 2: Skip Binary Benchmarks

If runtime library is unavailable, the script will:
- ✅ Still measure IR size and pass compilation time
- ⊘ Skip binary size, runtime performance, and memory benchmarks

## Customization

### Change Test Directory

Edit `benchmark.sh`:
```bash
TEST_DIR="./your_test_dir"
```

### Change Output Directory

```bash
BENCHMARK_DIR="./your_results_dir"
```

### Run on Specific Files

```bash
# Edit the script to benchmark specific files
benchmark_test "./path/to/your_test.c"
```

## Interpreting Results

### Good Metrics
- **IR Size**: 100-200% overhead is typical for comprehensive hardening
- **Binary Size**: 20-50% increase is reasonable
- **Runtime**: <30% slowdown for production use
- **Memory**: <20% increase is acceptable

### High Overhead Indicators
- IR Size >300%: Very aggressive hardening
- Runtime >50%: May impact user experience
- Memory >40%: Could cause issues on constrained systems

### Optimization Tips
If overhead is too high:
1. Reduce hardening level in transformation pass
2. Disable specific strategies (e.g., data redundancy)
3. Use profile-guided optimization
4. Apply hardening selectively to critical functions

## Example Workflow

```bash
# 1. Build the plugin
mkdir build && cd build
cmake .. && make
cd ..

# 2. Run benchmarks
./scripts/benchmark.sh

# 3. View summary
column -t -s',' benchmark_results/benchmark_summary.csv

# 4. Inspect specific test
cat benchmark_results/test_advanced_hardening/metrics.txt

# 5. Compare IR
diff -u benchmark_results/test_advanced_hardening/input.ll \
        benchmark_results/test_advanced_hardening/output_hardened.ll | less
```

## Troubleshooting

### "Plugin not found"
```bash
# Build the plugin first
mkdir build && cd build && cmake .. && make
```

### "No .c test files found"
```bash
# Add test files to ./tests/ or change TEST_DIR in benchmark.sh
```

### "Hardened binary skipped"
```bash
# Create runtime library at ./runtime/fi_runtime.c
# See "Runtime Library Support" section above
```

### "GNU time not available"
```bash
# Install time utility
sudo apt install time
```

## Output Files Summary

| File | Content |
|------|---------|
| `benchmark_summary.csv` | All tests, all metrics |
| `<test>/metrics.txt` | Human-readable summary |
| `<test>/metrics.csv` | Machine-readable data |
| `<test>/input.ll` | Original IR |
| `<test>/output_hardened.ll` | Transformed IR |
| `<test>/test_orig` | Baseline executable |
| `<test>/test_hardened` | Hardened executable |
| `<test>/pass_time.txt` | Transformation timing |
| `<test>/runtime_*.txt` | Execution timing |
| `<test>/memory_*.txt` | Memory usage stats |

## Notes

- Benchmark results vary by test complexity and hardware
- Run multiple iterations for statistical significance
- Clean `benchmark_results/` between runs for fresh data
- Binary benchmarks require runtime library implementation
- All timing uses `/usr/bin/time` for precision

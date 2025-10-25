#!/usr/bin/env bash

# Benchmarking script for FIHardeningTransform
# Measures performance overhead, code bloat, and memory usage

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PLUGIN_PATH="./build/FIHardeningTransform.so"
RUNTIME_SOURCE="./FIHardeningRuntime.cpp"
TEST_DIR="./tests"
BENCHMARK_DIR="./benchmark_results"
PASS_NAME="fi-harden-transform"

# CSV header
CSV_HEADER="Test,Metric,Baseline,Hardened,Overhead_%,Unit"

echo "========================================"
echo "FIHardeningTransform Benchmarking Suite"
echo "========================================"
echo ""

# Check if plugin exists
if [ ! -f "$PLUGIN_PATH" ]; then
    echo -e "${RED}Error: Plugin not found at $PLUGIN_PATH${NC}"
    echo "Please build the plugin first with:"
    echo "  mkdir build && cd build && cmake .. && make"
    exit 1
fi

# Note: Runtime will be compiled after benchmark directory is created
RUNTIME_AVAILABLE=false
RUNTIME_OBJ=""

# Check if /usr/bin/time exists (for detailed metrics)
if [ ! -f "/usr/bin/time" ]; then
    echo -e "${YELLOW}Warning: /usr/bin/time not found. Install with: sudo apt install time${NC}"
    echo "Falling back to basic timing..."
    USE_GNU_TIME=false
else
    USE_GNU_TIME=true
fi

# Create benchmark directory
mkdir -p "$BENCHMARK_DIR"

# Compile runtime library if available
if [ -f "$RUNTIME_SOURCE" ]; then
    echo -e "${BLUE}Compiling FI Hardening Runtime Library...${NC}"
    RUNTIME_OBJ="$BENCHMARK_DIR/FIHardeningRuntime.o"
    if clang++ -c -O2 "$RUNTIME_SOURCE" -o "$RUNTIME_OBJ" 2>&1; then
        echo -e "${GREEN}✓ Runtime library compiled: $RUNTIME_OBJ${NC}"
        RUNTIME_AVAILABLE=true
    else
        echo -e "${YELLOW}⚠ Failed to compile runtime library${NC}"
        echo -e "${YELLOW}  Binary benchmarks will be skipped${NC}"
        RUNTIME_AVAILABLE=false
    fi
else
    echo -e "${YELLOW}⚠ Runtime source not found: $RUNTIME_SOURCE${NC}"
    echo -e "${YELLOW}  Binary benchmarks will be skipped${NC}"
fi
echo ""

echo "Benchmark output directory: $BENCHMARK_DIR"
SUMMARY_CSV="$BENCHMARK_DIR/benchmark_summary.csv"
echo "$CSV_HEADER" > "$SUMMARY_CSV"

# Function to calculate percentage overhead
calc_overhead() {
    local baseline=$1
    local hardened=$2
    
    if [ "$baseline" = "0" ] || [ -z "$baseline" ]; then
        echo "N/A"
    else
        echo "scale=2; (($hardened - $baseline) / $baseline) * 100" | bc
    fi
}

# Function to benchmark a single test
benchmark_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .c)
    local test_bench_dir="$BENCHMARK_DIR/$test_name"
    
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}Benchmarking: $test_name${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    # Create test-specific directory
    mkdir -p "$test_bench_dir"
    
    # Paths
    local orig_ir="$test_bench_dir/input.ll"
    local hardened_ir="$test_bench_dir/output_hardened.ll"
    local orig_binary="$test_bench_dir/test_orig"
    local hardened_binary="$test_bench_dir/test_hardened"
    local metrics_file="$test_bench_dir/metrics.txt"
    local csv_file="$test_bench_dir/metrics.csv"
    local pass_time_file="$test_bench_dir/pass_time.txt"
    
    # Initialize metrics files
    echo "Benchmark Metrics for $test_name" > "$metrics_file"
    echo "Generated: $(date)" >> "$metrics_file"
    echo "========================================" >> "$metrics_file"
    echo "" >> "$metrics_file"
    
    echo "$CSV_HEADER" > "$csv_file"
    
    # Step 1: Compile to IR
    echo -e "${YELLOW}[1/7] Compiling C to LLVM IR...${NC}"
    if clang -S -emit-llvm -O0 -o "$orig_ir" "$test_file" 2>/dev/null; then
        echo -e "${GREEN}✓ IR generation complete${NC}"
    else
        echo -e "${RED}✗ Failed to compile $test_file${NC}"
        return 1
    fi
    
    # Step 2: Apply FIHardeningTransform pass and measure time
    echo -e "${YELLOW}[2/7] Applying FIHardeningTransform pass...${NC}"
    if [ "$USE_GNU_TIME" = true ]; then
        /usr/bin/time -p -o "$pass_time_file" \
            opt -load-pass-plugin="$PLUGIN_PATH" \
            -passes="$PASS_NAME" \
            "$orig_ir" -S -o "$hardened_ir" 2>&1 | grep -E "Transform|Applied|successfully" || true
    else
        opt -load-pass-plugin="$PLUGIN_PATH" \
            -passes="$PASS_NAME" \
            "$orig_ir" -S -o "$hardened_ir" 2>&1 | grep -E "Transform|Applied|successfully" || true
    fi
    
    if [ -f "$hardened_ir" ]; then
        echo -e "${GREEN}✓ Transformation complete${NC}"
    else
        echo -e "${RED}✗ Transformation failed${NC}"
        return 1
    fi
    
    # Measure pass compilation time
    if [ -f "$pass_time_file" ]; then
        pass_real_time=$(grep "real" "$pass_time_file" | awk '{print $2}')
        pass_user_time=$(grep "user" "$pass_time_file" | awk '{print $2}')
        pass_sys_time=$(grep "sys" "$pass_time_file" | awk '{print $2}')
        echo "Pass Compilation Time:" >> "$metrics_file"
        echo "  Real: ${pass_real_time}s" >> "$metrics_file"
        echo "  User: ${pass_user_time}s" >> "$metrics_file"
        echo "  Sys:  ${pass_sys_time}s" >> "$metrics_file"
        echo "" >> "$metrics_file"
        
        echo "$test_name,Pass_Real_Time,N/A,$pass_real_time,N/A,seconds" >> "$csv_file"
    fi
    
    # Step 3: Measure IR sizes
    echo -e "${YELLOW}[3/7] Measuring IR sizes...${NC}"
    orig_ir_lines=$(wc -l < "$orig_ir")
    hardened_ir_lines=$(wc -l < "$hardened_ir")
    ir_overhead=$(calc_overhead "$orig_ir_lines" "$hardened_ir_lines")
    
    echo "IR Size (lines):" >> "$metrics_file"
    echo "  Baseline:  $orig_ir_lines" >> "$metrics_file"
    echo "  Hardened:  $hardened_ir_lines" >> "$metrics_file"
    echo "  Overhead:  ${ir_overhead}%" >> "$metrics_file"
    echo "" >> "$metrics_file"
    
    echo "$test_name,IR_Size,$orig_ir_lines,$hardened_ir_lines,$ir_overhead,lines" >> "$csv_file"
    echo "$test_name,IR_Size,$orig_ir_lines,$hardened_ir_lines,$ir_overhead,lines" >> "$SUMMARY_CSV"
    
    echo -e "${GREEN}✓ IR: $orig_ir_lines → $hardened_ir_lines lines (+${ir_overhead}%)${NC}"
    
    # Step 4: Compile to binaries
    echo -e "${YELLOW}[4/7] Compiling binaries...${NC}"
    if clang "$orig_ir" -o "$orig_binary" 2>/dev/null; then
        echo -e "${GREEN}✓ Baseline binary compiled${NC}"
    else
        echo -e "${RED}✗ Failed to compile baseline binary${NC}"
        return 1
    fi
    
    # Compile hardened binary with runtime library
    if [ "$RUNTIME_AVAILABLE" = true ]; then
        if clang++ "$hardened_ir" "$RUNTIME_OBJ" -o "$hardened_binary" 2>/dev/null; then
            echo -e "${GREEN}✓ Hardened binary compiled (with FI runtime)${NC}"
            BINARY_COMPILED=true
        else
            echo -e "${YELLOW}⊘ Hardened binary compilation failed${NC}"
            BINARY_COMPILED=false
        fi
    else
        echo -e "${YELLOW}⊘ Hardened binary skipped (runtime library not available)${NC}"
        echo -e "${YELLOW}  Compile FIHardeningRuntime.cpp to enable binary benchmarks${NC}"
        BINARY_COMPILED=false
    fi
    
    # Step 5: Measure binary sizes
    echo -e "${YELLOW}[5/7] Measuring binary sizes...${NC}"
    
    if [ "$BINARY_COMPILED" = true ]; then
        orig_binary_size=$(stat -c%s "$orig_binary" 2>/dev/null || stat -f%z "$orig_binary")
        hardened_binary_size=$(stat -c%s "$hardened_binary" 2>/dev/null || stat -f%z "$hardened_binary")
        binary_overhead=$(calc_overhead "$orig_binary_size" "$hardened_binary_size")
        
        # Human-readable sizes
        orig_binary_size_h=$(ls -lh "$orig_binary" | awk '{print $5}')
        hardened_binary_size_h=$(ls -lh "$hardened_binary" | awk '{print $5}')
        
        echo "Binary Size:" >> "$metrics_file"
        echo "  Baseline:  $orig_binary_size bytes ($orig_binary_size_h)" >> "$metrics_file"
        echo "  Hardened:  $hardened_binary_size bytes ($hardened_binary_size_h)" >> "$metrics_file"
        echo "  Overhead:  ${binary_overhead}%" >> "$metrics_file"
        echo "" >> "$metrics_file"
        
        echo "$test_name,Binary_Size,$orig_binary_size,$hardened_binary_size,$binary_overhead,bytes" >> "$csv_file"
        echo "$test_name,Binary_Size,$orig_binary_size,$hardened_binary_size,$binary_overhead,bytes" >> "$SUMMARY_CSV"
        
        echo -e "${GREEN}✓ Binary: $orig_binary_size_h → $hardened_binary_size_h (+${binary_overhead}%)${NC}"
    else
        echo "Binary Size: Skipped (hardened binary not compiled)" >> "$metrics_file"
        echo "" >> "$metrics_file"
        echo -e "${YELLOW}⊘ Binary size measurement skipped${NC}"
    fi
    
    # Step 6: Measure runtime execution times
    echo -e "${YELLOW}[6/7] Measuring runtime performance...${NC}"
    
    # Check if binaries are executable (have main function) and hardened binary was compiled
    if [ "$BINARY_COMPILED" = true ] && nm "$orig_binary" 2>/dev/null | grep -q " T main"; then
        local orig_time_file="$test_bench_dir/runtime_orig.txt"
        local hardened_time_file="$test_bench_dir/runtime_hardened.txt"
        
        # Run baseline
        if [ "$USE_GNU_TIME" = true ]; then
            /usr/bin/time -p -o "$orig_time_file" "$orig_binary" >/dev/null 2>&1 || true
            orig_real_time=$(grep "real" "$orig_time_file" 2>/dev/null | awk '{print $2}' || echo "0")
            orig_user_time=$(grep "user" "$orig_time_file" 2>/dev/null | awk '{print $2}' || echo "0")
            orig_sys_time=$(grep "sys" "$orig_time_file" 2>/dev/null | awk '{print $2}' || echo "0")
        else
            orig_real_time="N/A"
            orig_user_time="N/A"
            orig_sys_time="N/A"
        fi
        
        # Run hardened
        if [ "$USE_GNU_TIME" = true ]; then
            /usr/bin/time -p -o "$hardened_time_file" "$hardened_binary" >/dev/null 2>&1 || true
            hardened_real_time=$(grep "real" "$hardened_time_file" 2>/dev/null | awk '{print $2}' || echo "0")
            hardened_user_time=$(grep "user" "$hardened_time_file" 2>/dev/null | awk '{print $2}' || echo "0")
            hardened_sys_time=$(grep "sys" "$hardened_time_file" 2>/dev/null | awk '{print $2}' || echo "0")
        else
            hardened_real_time="N/A"
            hardened_user_time="N/A"
            hardened_sys_time="N/A"
        fi
        
        if [ "$orig_real_time" != "N/A" ]; then
            runtime_overhead=$(calc_overhead "$orig_real_time" "$hardened_real_time")
            
            echo "Runtime Performance:" >> "$metrics_file"
            echo "  Baseline Real Time:  ${orig_real_time}s" >> "$metrics_file"
            echo "  Hardened Real Time:  ${hardened_real_time}s" >> "$metrics_file"
            echo "  Overhead:            ${runtime_overhead}%" >> "$metrics_file"
            echo "  Baseline User Time:  ${orig_user_time}s" >> "$metrics_file"
            echo "  Hardened User Time:  ${hardened_user_time}s" >> "$metrics_file"
            echo "" >> "$metrics_file"
            
            echo "$test_name,Runtime_Real,$orig_real_time,$hardened_real_time,$runtime_overhead,seconds" >> "$csv_file"
            echo "$test_name,Runtime_User,$orig_user_time,$hardened_user_time,N/A,seconds" >> "$csv_file"
            echo "$test_name,Runtime_Real,$orig_real_time,$hardened_real_time,$runtime_overhead,seconds" >> "$SUMMARY_CSV"
            
            echo -e "${GREEN}✓ Runtime: ${orig_real_time}s → ${hardened_real_time}s (+${runtime_overhead}%)${NC}"
        else
            echo "Runtime Performance: Skipped (GNU time not available)" >> "$metrics_file"
            echo "" >> "$metrics_file"
            echo -e "${YELLOW}⊘ Runtime measurement skipped${NC}"
        fi
    else
        echo "Runtime Performance: Skipped (no main function)" >> "$metrics_file"
        echo "" >> "$metrics_file"
        echo -e "${YELLOW}⊘ Runtime measurement skipped (no executable)${NC}"
    fi
    
    # Step 7: Measure memory usage
    echo -e "${YELLOW}[7/7] Measuring memory usage...${NC}"
    
    if [ "$BINARY_COMPILED" = true ] && [ "$USE_GNU_TIME" = true ] && nm "$orig_binary" 2>/dev/null | grep -q " T main"; then
        local orig_mem_file="$test_bench_dir/memory_orig.txt"
        local hardened_mem_file="$test_bench_dir/memory_hardened.txt"
        
        # Run with -v for detailed memory stats
        /usr/bin/time -v "$orig_binary" >/dev/null 2>"$orig_mem_file" || true
        /usr/bin/time -v "$hardened_binary" >/dev/null 2>"$hardened_mem_file" || true
        
        # Extract max resident set size
        orig_mem=$(grep "Maximum resident set size" "$orig_mem_file" 2>/dev/null | awk '{print $6}' || echo "0")
        hardened_mem=$(grep "Maximum resident set size" "$hardened_mem_file" 2>/dev/null | awk '{print $6}' || echo "0")
        
        if [ "$orig_mem" != "0" ]; then
            mem_overhead=$(calc_overhead "$orig_mem" "$hardened_mem")
            
            echo "Memory Usage (Max RSS):" >> "$metrics_file"
            echo "  Baseline:  ${orig_mem} KB" >> "$metrics_file"
            echo "  Hardened:  ${hardened_mem} KB" >> "$metrics_file"
            echo "  Overhead:  ${mem_overhead}%" >> "$metrics_file"
            echo "" >> "$metrics_file"
            
            echo "$test_name,Memory_RSS,$orig_mem,$hardened_mem,$mem_overhead,KB" >> "$csv_file"
            echo "$test_name,Memory_RSS,$orig_mem,$hardened_mem,$mem_overhead,KB" >> "$SUMMARY_CSV"
            
            echo -e "${GREEN}✓ Memory: ${orig_mem}KB → ${hardened_mem}KB (+${mem_overhead}%)${NC}"
        else
            echo "Memory Usage: Could not measure" >> "$metrics_file"
            echo "" >> "$metrics_file"
            echo -e "${YELLOW}⊘ Memory measurement unavailable${NC}"
        fi
    else
        echo "Memory Usage: Skipped (GNU time not available or no main)" >> "$metrics_file"
        echo "" >> "$metrics_file"
        echo -e "${YELLOW}⊘ Memory measurement skipped${NC}"
    fi
    
    # Generate summary table for this test
    echo "" >> "$metrics_file"
    echo "========================================" >> "$metrics_file"
    echo "Summary Table" >> "$metrics_file"
    echo "========================================" >> "$metrics_file"
    column -t -s',' "$csv_file" >> "$metrics_file"
    
    echo -e "${GREEN}✓ Benchmark complete for $test_name${NC}"
    echo -e "${BLUE}Results saved to: $test_bench_dir/${NC}"
    
    return 0
}

# Main execution
echo -e "${BLUE}Benchmark output directory: $BENCHMARK_DIR${NC}"
echo ""

# Collect test files
shopt -s nullglob
c_files=("$TEST_DIR"/*.c)
shopt -u nullglob

if [ ${#c_files[@]} -eq 0 ]; then
    echo -e "${YELLOW}No .c test files found in $TEST_DIR${NC}"
    echo "Please add test files or specify a different TEST_DIR"
    exit 1
fi

echo -e "${BLUE}Found ${#c_files[@]} test file(s) to benchmark${NC}"

# Benchmark each test
successful=0
failed=0

for test_file in "${c_files[@]}"; do
    if benchmark_test "$test_file"; then
        ((successful++))
    else
        ((failed++))
    fi
done

# Final summary
echo ""
echo "========================================"
echo "Benchmark Summary"
echo "========================================"
echo -e "${GREEN}Successful: $successful${NC}"
if [ $failed -gt 0 ]; then
    echo -e "${RED}Failed: $failed${NC}"
fi
echo ""
echo "Results saved in: $BENCHMARK_DIR/"
echo ""
echo "Summary CSV: $SUMMARY_CSV"
echo ""
echo -e "${CYAN}Per-test results:${NC}"
for test_file in "${c_files[@]}"; do
    test_name=$(basename "$test_file" .c)
    echo "  - $BENCHMARK_DIR/$test_name/"
done
echo ""
echo -e "${BLUE}To view summary table:${NC}"
echo "  column -t -s',' $SUMMARY_CSV"
echo ""
echo -e "${BLUE}To view individual test metrics:${NC}"
echo "  cat $BENCHMARK_DIR/<test_name>/metrics.txt"
echo ""

# Display summary table
if [ -f "$SUMMARY_CSV" ] && [ $(wc -l < "$SUMMARY_CSV") -gt 1 ]; then
    echo "========================================"
    echo "Overhead Summary (All Tests)"
    echo "========================================"
    column -t -s',' "$SUMMARY_CSV"
    echo ""
fi

echo -e "${GREEN}Benchmarking complete!${NC}"

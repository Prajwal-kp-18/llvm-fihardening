
#!/usr/bin/env bash

# Test runner script for FIHardeningPass
# Usage: 
#   ./run_tests.sh                    - Run all tests in tests/ directory
#   ./run_tests.sh file.c             - Run test on specific file
#   ./run_tests.sh file1.c file2.c    - Run tests on multiple files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PLUGIN_PATH="./FIHardeningTransform.so"
TEST_DIR="./tests"
OUTPUT_DIR="./test_results"

# Spinner configuration
SPINNER_PID=""
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

echo "========================================"
echo "FIHardeningPass Test Suite Runner"
echo "========================================"

# Check if plugin exists
if [ ! -f "$PLUGIN_PATH" ]; then
    echo -e "${RED}Error: Plugin not found at $PLUGIN_PATH${NC}"
    echo "Please build the plugin first with:"
    echo "  mkdir build && cd build && cmake .. && make"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Spinner function
start_spinner() {
    local message="$1"
    local delay=0.1
    
    # Hide cursor
    tput civis 2>/dev/null || true
    
    (
        i=0
        while true; do
            printf "\r${CYAN}${SPINNER_FRAMES[$i]} $message${NC}"
            i=$(( (i + 1) % ${#SPINNER_FRAMES[@]} ))
            sleep $delay
        done
    ) &
    
    SPINNER_PID=$!
}

stop_spinner() {
    local exit_code=${1:-0}
    local success_msg="$2"
    local error_msg="$3"
    
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    
    # Clear the spinner line
    printf "\r\033[K"
    
    # Show cursor
    tput cnorm 2>/dev/null || true
    
    # Print result
    if [ "$exit_code" -eq 0 ]; then
        [ -n "$success_msg" ] && echo -e "${GREEN}✓ $success_msg${NC}"
    else
        [ -n "$error_msg" ] && echo -e "${RED}✗ $error_msg${NC}"
    fi
}

# Cleanup function for trapped signals
cleanup() {
    stop_spinner 1
    exit 1
}

# Trap signals to ensure spinner cleanup
trap cleanup SIGINT SIGTERM

# Function to check if graphviz is available
check_graphviz() {
    if ! command -v dot >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Function to generate CFG for a single IR file
generate_cfg_for_ir() {
    local ir_file="$1"
    local output_prefix="$2"
    local working_dir="$3"
    
    local dot_files=()
    local png_count=0
    local failed_conversions=0
    
    # Change to working directory
    pushd "$working_dir" >/dev/null 2>&1 || return 1
    
    # Clean up any old .dot files
    rm -f cfg.*.dot .*.dot 2>/dev/null || true
    
    # Generate .dot files
    if ! opt -passes='dot-cfg' -disable-output "$(basename "$ir_file")" 2>/dev/null; then
        popd >/dev/null 2>&1 || true
        return 1
    fi
    
    # Collect all generated .dot files
    for dotf in cfg.*.dot .*.dot; do
        [ -f "$dotf" ] && dot_files+=("$dotf")
    done
    
    # Convert each .dot file to PNG
    for dotf in "${dot_files[@]}"; do
        func=$(echo "$dotf" | sed -E 's/^(cfg\\.|\\.)//' | sed 's/\\.dot$//')
        outpng="${output_prefix}_${func}.png"
        
        if dot -Tpng "$dotf" -o "$outpng" 2>/dev/null; then
            ((png_count++))
        else
            ((failed_conversions++))
        fi
        
        rm -f "$dotf"
    done
    
    popd >/dev/null 2>&1 || true
    
    # Return the count (0 if none generated)
    echo "$png_count"
    return 0
}

# Function to run a single test
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .c)
    
    echo ""
    echo -e "${YELLOW}Running test: $test_name${NC}"
    echo "----------------------------------------"
    
    # Generate LLVM IR
    start_spinner "Compiling $test_name to LLVM IR..."
    if clang -S -emit-llvm -o "$OUTPUT_DIR/$test_name.ll" "$test_file" 2>/dev/null; then
        stop_spinner 0 "Compiled $test_name to LLVM IR"
    else
        stop_spinner 1 "" "Failed to compile $test_file"
        return 1
    fi
    
    # Run the pass and write hardened IR + capture output
    hardened_ir="$OUTPUT_DIR/${test_name}_hardened.ll"
    
    start_spinner "Running FIHardeningPass on $test_name..."
    if opt -load-pass-plugin="$PLUGIN_PATH" \
        -passes="fi-harden-transform" \
        -fi-harden-level=3 \
        -fi-harden-stats \
        "$OUTPUT_DIR/$test_name.ll" -S -o "$hardened_ir" \
        2> "$OUTPUT_DIR/$test_name.output"; then
        stop_spinner 0 "FIHardeningPass completed"
    else
        stop_spinner 1 "" "FIHardeningPass failed"
        return 1
    fi

    # Display pass output
    if [ -s "$OUTPUT_DIR/$test_name.output" ]; then
        echo -e "${BLUE}Pass output:${NC}"
        cat "$OUTPUT_DIR/$test_name.output"
    else
        echo "No warnings detected (clean code)"
    fi

    # Apply O3 optimization
    o3_ir="$OUTPUT_DIR/${test_name}_hardened_O3.ll"
    
    start_spinner "Applying -O3 optimization to hardened IR..."
    if opt -O3 "$hardened_ir" -S -o "$o3_ir" 2>/dev/null; then
        stop_spinner 0 "O3 optimization completed"
    else
        stop_spinner 1 "" "Failed to optimize IR with -O3"
        return 1
    fi

    # Check O3 preservation
    diff_file="$OUTPUT_DIR/${test_name}_O3_diff.txt"
    diff -u "$hardened_ir" "$o3_ir" > "$diff_file" 2>/dev/null || true

    if [ ! -s "$diff_file" ]; then
        echo -e "${GREEN}✓ O3 preserved all FIHardening transformations${NC}"
        rm -f "$diff_file"
    else
        echo -e "${YELLOW}⚠ O3 modified hardened IR (diff saved)${NC}"
    fi

    # CFG Visualization generation
    if ! check_graphviz; then
        echo -e "${YELLOW}⚠ Graphviz 'dot' not found. Skipping CFG generation${NC}"
        echo -e "  Install with: ${CYAN}sudo apt install graphviz${NC}"
    else
        echo -e "${YELLOW}Note: Generating CFGs may take time for large code size.${NC}"
        # Generate CFGs for hardened IR
        start_spinner "Generating CFG visualizations for hardened IR..."
        
        hardened_count=$(generate_cfg_for_ir "$hardened_ir" "${test_name}_cfg" "$OUTPUT_DIR" 2>/dev/null || echo "0")
        
        if [ "$hardened_count" -gt 0 ]; then
            stop_spinner 0 "Generated $hardened_count CFG(s) for hardened IR"
        else
            stop_spinner 1 "" "Failed to generate CFGs for hardened IR"
        fi
        
        # Generate CFGs for O3 IR
        start_spinner "Generating CFG visualizations for O3-optimized IR..."
        
        o3_count=$(generate_cfg_for_ir "$o3_ir" "${test_name}_cfg_O3" "$OUTPUT_DIR" 2>/dev/null || echo "0")
        
        if [ "$o3_count" -gt 0 ]; then
            stop_spinner 0 "Generated $o3_count CFG(s) for O3-optimized IR"
        else
            stop_spinner 1 "" "Failed to generate CFGs for O3-optimized IR"
        fi
        
        # Summary of CFG generation
        total_cfgs=$((hardened_count + o3_count))
        if [ "$total_cfgs" -gt 0 ]; then
            echo -e "${GREEN}✓ Total CFG images generated: $total_cfgs${NC}"
        else
            echo -e "${YELLOW}⚠ No CFG images were generated${NC}"
        fi
    fi

    # Summary of artifacts for this test
    echo ""
    echo -e "${GREEN}Artifacts for $test_name:${NC}"
    echo "  - Original IR: $OUTPUT_DIR/$test_name.ll"
    echo "  - Hardened IR: $hardened_ir"
    echo "  - O3 Hardened IR: $o3_ir"
    if [ -f "$diff_file" ]; then
        echo "  - O3 Diff: $diff_file"
    fi
    
    # Count and display CFG files
    cfg_files=("$OUTPUT_DIR/${test_name}_cfg_"*.png)
    if [ -f "${cfg_files[0]}" ]; then
        echo "  - CFG images: $OUTPUT_DIR/${test_name}_cfg_*.png (${#cfg_files[@]} files)"
    fi

    return 0
}

# Test counter
TEST_COUNT=0
PASS_COUNT=0

# Check if arguments provided
if [ $# -gt 0 ]; then
    # Run tests on specified files
    echo -e "${BLUE}Running tests on specified files...${NC}"
    for test_file in "$@"; do
        if [ ! -f "$test_file" ]; then
            echo -e "${RED}Error: File not found: $test_file${NC}"
            continue
        fi
        TEST_COUNT=$((TEST_COUNT + 1))
        run_test "$test_file" && PASS_COUNT=$((PASS_COUNT + 1)) || true
    done
else
    # No arguments, run all tests
    echo -e "${BLUE}Running all tests...${NC}"
    
    # Test from examples directory
    if [ -f "examples/test_suite.c" ]; then
        TEST_COUNT=$((TEST_COUNT + 1))
        run_test "examples/test_suite.c" && PASS_COUNT=$((PASS_COUNT + 1)) || true
    fi

    # Test from tests directory
    if [ -d "$TEST_DIR" ]; then
        shopt -s nullglob
        c_files=("$TEST_DIR"/*.c)
        if [ ${#c_files[@]} -eq 0 ]; then
            echo -e "${YELLOW}No .c test files found in $TEST_DIR${NC}"
        else
            for test_file in "${c_files[@]}"; do
                TEST_COUNT=$((TEST_COUNT + 1))
                run_test "$test_file" && PASS_COUNT=$((PASS_COUNT + 1)) || true
            done
        fi
        shopt -u nullglob
    fi
fi

# Final summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
if [ "$TEST_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No tests were run${NC}"
elif [ "$PASS_COUNT" -eq "$TEST_COUNT" ]; then
    echo -e "${GREEN}✓ All tests passed: $PASS_COUNT / $TEST_COUNT${NC}"
else
    echo -e "${YELLOW}Passed: $PASS_COUNT / $TEST_COUNT tests${NC}"
fi
echo "Results saved in: $OUTPUT_DIR/"
echo ""
echo "To view individual test results:"
echo "  cat $OUTPUT_DIR/*.output"
echo "  ls $OUTPUT_DIR/*.png  # View CFG images"
echo "  open $OUTPUT_DIR/*.png  # Open CFG images (macOS)"
echo "  xdg-open $OUTPUT_DIR/*.png  # Open CFG images (Linux)"
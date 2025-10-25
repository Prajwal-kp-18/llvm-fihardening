#!/usr/bin/env bash

# Test runner script for FIHardeningPass
# Optimized for LLVM 18 with New Pass Manager

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PLUGIN_PATH="./FIHardeningTransform.so"
TEST_DIR="./tests"
OUTPUT_DIR="./test_results"

# Detect LLVM version
LLVM_VERSION=$(opt --version 2>/dev/null | grep -oP 'LLVM version \K\d+' | head -1 || echo "0")

echo "========================================"
echo "FIHardeningPass Test Suite Runner"
echo "========================================"
echo -e "${BLUE}LLVM Version: $LLVM_VERSION${NC}"
echo -e "${BLUE}Pass Manager: New PM (default)${NC}"
echo ""

# Check if plugin exists
if [ ! -f "$PLUGIN_PATH" ]; then
    echo -e "${RED}Error: Plugin not found at $PLUGIN_PATH${NC}"
    echo "Please build the plugin first with:"
    echo "  mkdir build && cd build && cmake .. && make"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to run a single test
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .c)
    
    echo ""
    echo -e "${YELLOW}Running test: $test_name${NC}"
    echo "----------------------------------------"
    
    # Generate LLVM IR
    echo "→ Generating LLVM IR..."
    clang -S -emit-llvm -o "$OUTPUT_DIR/$test_name.ll" "$test_file" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to compile $test_file${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✓ IR generated${NC}"
    
    # Run the pass with new pass manager
    hardened_ir="$OUTPUT_DIR/${test_name}_hardened.ll"
    echo "→ Running FIHardening pass..."
    
    # New pass manager syntax for LLVM 18
    opt -load-pass-plugin="$PLUGIN_PATH" \
        -passes="fi-harden-transform" \
        "$OUTPUT_DIR/$test_name.ll" -S -o "$hardened_ir" \
        2> "$OUTPUT_DIR/$test_name.output"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Pass execution failed${NC}"
        cat "$OUTPUT_DIR/$test_name.output"
        return 1
    fi

    # Display pass output
    if [ -s "$OUTPUT_DIR/$test_name.output" ]; then
        cat "$OUTPUT_DIR/$test_name.output"
    fi
    echo -e "${GREEN}  ✓ Hardening complete${NC}"

    # Apply O3 optimization
    o3_ir="$OUTPUT_DIR/${test_name}_hardened_O3.ll"
    echo "→ Applying -O3 optimization..."
    if ! opt -O3 "$hardened_ir" -S -o "$o3_ir" 2>/dev/null; then
        echo -e "${RED}✗ Failed to optimize IR with -O3${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✓ O3 optimization complete${NC}"

    # Check O3 diff
    diff_file="$OUTPUT_DIR/${test_name}_O3_diff.txt"
    diff -u "$hardened_ir" "$o3_ir" > "$diff_file" 2>/dev/null || true

    if [ -s "$diff_file" ]; then
        lines=$(wc -l < "$diff_file")
        echo -e "${YELLOW}  ⚠ O3 modified instrumentation ($lines lines changed)${NC}"
        echo "    See: $diff_file"
    else
        echo -e "${GREEN}  ✓ O3 preserved all transformations${NC}"
        rm -f "$diff_file"
    fi

    # CFG Visualization generation
    echo "→ Generating CFG visualizations..."
    if ! command -v dot >/dev/null 2>&1; then
        echo -e "${RED}  ✗ Graphviz not found. Install: sudo apt install graphviz${NC}"
        echo -e "${YELLOW}  Skipping CFG generation.${NC}"
    else
        pushd "$OUTPUT_DIR" >/dev/null || true

        # Clean up old .dot files
        rm -f cfg.*.dot .*.dot 2>/dev/null || true

        # Generate CFGs for hardened IR
        opt -passes='dot-cfg' -disable-output "$(basename "$hardened_ir")" 2>/dev/null || true
        
        for dotf in cfg.*.dot .*.dot; do
            [ -f "$dotf" ] || continue
            func=$(echo "$dotf" | sed -E 's/^(cfg\.|\.)//' | sed 's/\.dot$//')
            outpng="${test_name}_cfg_${func}.png"
            dot -Tpng "$dotf" -o "$outpng" 2>/dev/null && rm -f "$dotf"
        done

        # Generate CFGs for O3 IR
        opt -passes='dot-cfg' -disable-output "$(basename "$o3_ir")" 2>/dev/null || true
        
        for dotf in cfg.*.dot .*.dot; do
            [ -f "$dotf" ] || continue
            func=$(echo "$dotf" | sed -E 's/^(cfg\.|\.)//' | sed 's/\.dot$//')
            outpng="${test_name}_cfg_O3_${func}.png"
            dot -Tpng "$dotf" -o "$outpng" 2>/dev/null && rm -f "$dotf"
        done

        popd >/dev/null || true
        
        png_count=$(find "$OUTPUT_DIR" -name "${test_name}_cfg_*.png" 2>/dev/null | wc -l)
        if [ "$png_count" -gt 0 ]; then
            echo -e "${GREEN}  ✓ Generated $png_count CFG images${NC}"
        else
            echo -e "${YELLOW}  ⚠ No CFG images generated${NC}"
        fi
    fi

    # Summary
    echo ""
    echo -e "${GREEN}Artifacts for $test_name:${NC}"
    echo "  Original IR:    $OUTPUT_DIR/$test_name.ll"
    echo "  Hardened IR:    $hardened_ir"
    echo "  O3 Hardened:    $o3_ir"
    [ -f "$diff_file" ] && echo "  O3 Diff:        $diff_file"
    echo "  CFG Images:     $OUTPUT_DIR/${test_name}_cfg_*.png"

    return 0
}

# Run tests
TEST_COUNT=0
PASS_COUNT=0

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

# Final summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
if [ "$PASS_COUNT" -eq "$TEST_COUNT" ]; then
    echo -e "${GREEN}✓ All tests passed: $PASS_COUNT / $TEST_COUNT${NC}"
else
    echo -e "${YELLOW}Passed: $PASS_COUNT / $TEST_COUNT tests${NC}"
fi
echo "Results saved in: $OUTPUT_DIR/"
echo ""
echo "View results with:"
echo "  ls -lh $OUTPUT_DIR/"
echo "  ls $OUTPUT_DIR/*.png  # View CFG images"

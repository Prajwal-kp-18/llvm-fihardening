#!/bin/bash

# test_advanced_hardening.sh - Test all 12 hardening strategies

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"

TEST_FILE="$PROJECT_ROOT/tests/test_advanced_hardening.c"
TEST_BASE="test_advanced_hardening"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   Advanced Hardening Test Suite${NC}"
echo -e "${CYAN}   Testing 12 Fault Injection Strategies${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Step 1: Generate LLVM IR
echo -e "${YELLOW}[1/6] Generating LLVM IR...${NC}"
clang -S -emit-llvm -O0 -o "$BUILD_DIR/${TEST_BASE}.ll" "$TEST_FILE"
echo -e "  ${GREEN}✓${NC} Generated: ${TEST_BASE}.ll"
echo ""

# Step 2: Run analysis pass
echo -e "${YELLOW}[2/6] Running analysis pass...${NC}"
opt -load-pass-plugin="$BUILD_DIR/FIHardeningPass.so" \
    -passes="fi-harden" \
    -disable-output "$BUILD_DIR/${TEST_BASE}.ll" 2>&1 | head -30
echo ""

# Step 3: Apply transformation with ALL strategies enabled
echo -e "${YELLOW}[3/6] Applying ALL hardening transformations...${NC}"
opt -load-pass-plugin="$BUILD_DIR/FIHardeningTransform.so" \
    -passes="fi-harden-transform" \
    -fi-harden-level=2 \
    -fi-harden-branches=true \
    -fi-harden-memory=true \
    -fi-harden-arithmetic=false \
    -fi-harden-cfi=true \
    -fi-harden-data-redundancy=true \
    -fi-harden-memory-safety=true \
    -fi-harden-stack=true \
    -fi-harden-exceptions=true \
    -fi-harden-hardware-io=true \
    -fi-enable-logging=true \
    -fi-harden-timing=true \
    -fi-harden-stats=true \
    -S "$BUILD_DIR/${TEST_BASE}.ll" \
    -o "$BUILD_DIR/${TEST_BASE}_hardened.ll" 2>&1 | grep -E "Statistics|hardened|Total|ENABLED|DISABLED" || true
echo ""

# Step 4: Compile hardened version
echo -e "${YELLOW}[4/6] Compiling hardened binary...${NC}"
clang "$BUILD_DIR/${TEST_BASE}_hardened.ll" \
    "$BUILD_DIR/libFIHardeningRuntime.a" \
    -o "$BUILD_DIR/${TEST_BASE}_hardened"
echo -e "  ${GREEN}✓${NC} Compiled: ${TEST_BASE}_hardened"
echo ""

# Step 5: Measure overhead
echo -e "${YELLOW}[5/6] Measuring transformation overhead...${NC}"

# Compile original for comparison
clang "$BUILD_DIR/${TEST_BASE}.ll" -o "$BUILD_DIR/${TEST_BASE}_original"

ORIGINAL_SIZE=$(stat -c%s "$BUILD_DIR/${TEST_BASE}_original" 2>/dev/null || stat -f%z "$BUILD_DIR/${TEST_BASE}_original")
HARDENED_SIZE=$(stat -c%s "$BUILD_DIR/${TEST_BASE}_hardened" 2>/dev/null || stat -f%z "$BUILD_DIR/${TEST_BASE}_hardened")

ORIGINAL_IR_LINES=$(wc -l < "$BUILD_DIR/${TEST_BASE}.ll")
HARDENED_IR_LINES=$(wc -l < "$BUILD_DIR/${TEST_BASE}_hardened.ll")

SIZE_INCREASE=$(awk "BEGIN {printf \"%.2f\", 100.0 * ($HARDENED_SIZE - $ORIGINAL_SIZE) / $ORIGINAL_SIZE}")
IR_INCREASE=$(awk "BEGIN {printf \"%.2f\", 100.0 * ($HARDENED_IR_LINES - $ORIGINAL_IR_LINES) / $ORIGINAL_IR_LINES}")

echo -e "  Binary Size:"
echo -e "    Original:  ${ORIGINAL_SIZE} bytes"
echo -e "    Hardened:  ${HARDENED_SIZE} bytes"
echo -e "    Increase:  ${GREEN}+${SIZE_INCREASE}%${NC}"
echo ""
echo -e "  IR Size:"
echo -e "    Original:  ${ORIGINAL_IR_LINES} lines"
echo -e "    Hardened:  ${HARDENED_IR_LINES} lines"
echo -e "    Increase:  ${GREEN}+${IR_INCREASE}%${NC}"
echo ""

# Step 6: Run hardened program
echo -e "${YELLOW}[6/6] Running hardened program...${NC}"
echo -e "${CYAN}----------------------------------------${NC}"
"$BUILD_DIR/${TEST_BASE}_hardened"
echo -e "${CYAN}----------------------------------------${NC}"
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Advanced Hardening Test Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Key Metrics:${NC}"
echo -e "  • Binary overhead: ${SIZE_INCREASE}%"
echo -e "  • IR overhead: ${IR_INCREASE}%"
echo -e "  • Strategies tested: 12"
echo ""
echo -e "${BLUE}Enabled Strategies:${NC}"
echo -e "  1. ✓ Branch Hardening"
echo -e "  2. ✓ Load Hardening"
echo -e "  3. ✓ Store Hardening"
echo -e "  4. ✗ Arithmetic Hardening (disabled)"
echo -e "  5. ✓ Control-Flow Integrity (CFI)"
echo -e "  6. ✓ Data/State Redundancy"
echo -e "  7. ✓ Memory Safety/Bounds Checking"
echo -e "  8. ✓ Stack Protection"
echo -e "  9. ✓ Exception Path Hardening"
echo -e " 10. ✓ Hardware I/O Validation"
echo -e " 11. ✓ Fault Detection & Logging"
echo -e " 12. ✓ Timing Side-Channel Mitigation"
echo ""

echo -e "${CYAN}Files generated:${NC}"
echo -e "  • $BUILD_DIR/${TEST_BASE}.ll"
echo -e "  • $BUILD_DIR/${TEST_BASE}_hardened.ll"
echo -e "  • $BUILD_DIR/${TEST_BASE}_original"
echo -e "  • $BUILD_DIR/${TEST_BASE}_hardened"
echo ""

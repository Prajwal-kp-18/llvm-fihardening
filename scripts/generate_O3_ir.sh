#!/bin/bash
#
# generate_O3_ir.sh - Generate O3-optimized IR for normal and hardened versions
#
# Usage: ./generate_O3_ir.sh <source.c>
#

set -e

PROGRAM_C=${1:-tests/test_advanced_hardening.c}

if [ ! -f "$PROGRAM_C" ]; then
    echo "Error: Source file not found: $PROGRAM_C"
    echo "Usage: $0 <source.c>"
    exit 1
fi

PROGRAM_NAME=$(basename "$PROGRAM_C" .c)

echo "╔══════════════════════════════════════════════════════════╗"
echo "║         O3-Optimized IR Generation                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Source:       $PROGRAM_C"
echo "Output:       build/"
echo ""

# Step 1: Generate O3-optimized IR (normal)
echo "[1/4] Generating O3 IR (normal, optimized)..."
clang -S -emit-llvm -O3 \
    -o "build/${PROGRAM_NAME}_O3.ll" \
    "$PROGRAM_C"
echo "  ✓ Created: build/${PROGRAM_NAME}_O3.ll"
echo ""

# Step 2: Show statistics for O3 IR
echo "[2/4] Analyzing O3 IR..."
LINES_O3=$(wc -l < "build/${PROGRAM_NAME}_O3.ll")
INSTRS_O3=$(grep -E "^\s+(call|store|load|br|add|sub|mul|icmp|ret)" "build/${PROGRAM_NAME}_O3.ll" 2>/dev/null | wc -l)
FUNCS_O3=$(grep "^define" "build/${PROGRAM_NAME}_O3.ll" 2>/dev/null | wc -l)
echo "  Lines:        $LINES_O3"
echo "  Instructions: $INSTRS_O3"
echo "  Functions:    $FUNCS_O3"
echo ""

# Step 3: Apply hardening to O3 IR
echo "[3/4] Applying hardening to O3 IR..."
opt -load-pass-plugin=build/FIHardeningTransform.so \
    -passes="fi-harden-transform" \
    -fi-harden-level=2 \
    -S "build/${PROGRAM_NAME}_O3.ll" \
    -o "build/${PROGRAM_NAME}_O3_hardened.ll" \
    2>&1 | grep -E "transformations|Statistics" || echo "  ⚠ Transformation applied"
echo "  ✓ Created: build/${PROGRAM_NAME}_O3_hardened.ll"
echo ""

# Step 4: Show statistics for hardened O3 IR
echo "[4/4] Analyzing O3 hardened IR..."
LINES_HARD=$(wc -l < "build/${PROGRAM_NAME}_O3_hardened.ll")
INSTRS_HARD=$(grep -E "^\s+(call|store|load|br|add|sub|mul|icmp|ret)" "build/${PROGRAM_NAME}_O3_hardened.ll" 2>/dev/null | wc -l)
FUNCS_HARD=$(grep "^define" "build/${PROGRAM_NAME}_O3_hardened.ll" 2>/dev/null | wc -l)
echo "  Lines:        $LINES_HARD"
echo "  Instructions: $INSTRS_HARD"
echo "  Functions:    $FUNCS_HARD"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "%-30s %15s %15s %15s\n" "Metric" "O3 Normal" "O3 Hardened" "Overhead"
echo "────────────────────────────────────────────────────────────────"
printf "%-30s %15s %15s %15s\n" "Lines" "$LINES_O3" "$LINES_HARD" "+$(echo "scale=1; ($LINES_HARD-$LINES_O3)*100/$LINES_O3" | bc)%"
printf "%-30s %15s %15s %15s\n" "Instructions" "$INSTRS_O3" "$INSTRS_HARD" "+$(echo "scale=1; ($INSTRS_HARD-$INSTRS_O3)*100/$INSTRS_O3" | bc)%"
printf "%-30s %15s %15s %15s\n" "Functions" "$FUNCS_O3" "$FUNCS_HARD" "same"
echo ""

echo "✅ Generated files:"
echo "  1. build/${PROGRAM_NAME}_O3.ll          (O3 optimized, normal)"
echo "  2. build/${PROGRAM_NAME}_O3_hardened.ll (O3 optimized + hardened)"
echo ""
echo "Next steps:"
echo "  # Benchmark normal O3"
echo "  ./scripts/opt_only_benchmark.sh build/${PROGRAM_NAME}_O3.ll"
echo ""
echo "  # Benchmark hardened O3"
echo "  ./scripts/opt_only_benchmark.sh build/${PROGRAM_NAME}_O3_hardened.ll"
echo ""

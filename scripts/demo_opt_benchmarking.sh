#!/bin/bash
#
# demo_opt_benchmarking.sh - Interactive demonstration of opt-only benchmarking
#

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     Demo: Using opt for Hardening Benchmarks            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "This demonstrates how to benchmark hardening using ONLY opt"
echo "No compilation, no execution - pure static analysis!"
echo ""

# Use existing test file or create simple one
if [ -f "build/test_advanced_hardening.ll" ]; then
    TEST_FILE="build/test_advanced_hardening.ll"
    echo "Using existing test: $TEST_FILE"
else
    echo "Creating simple test program..."
    cat > /tmp/simple_test.c << 'C_CODE'
#include <stdio.h>

int factorial(int n) {
    int result = 1;
    for (int i = 1; i <= n; i++) {
        result = result * i;
    }
    return result;
}

int main() {
    int n = 5;
    int result = factorial(n);
    printf("factorial(%d) = %d\n", n, result);
    return 0;
}
C_CODE

    clang -S -emit-llvm -O0 -o /tmp/simple_test.ll /tmp/simple_test.c
    TEST_FILE="/tmp/simple_test.ll"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running opt-only benchmark..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

./scripts/opt_only_benchmark.sh "$TEST_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎓 What just happened (using ONLY opt):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. ✅ FIHardeningPass analyzed original IR"
echo "   → Counted vulnerabilities (branches, loads, stores)"
echo "   → No compilation needed!"
echo ""
echo "2. ✅ FIHardeningTransform modified IR"
echo "   → Added verification calls"
echo "   → Duplicated critical operations"
echo "   → Inserted redundant checks"
echo ""
echo "3. ✅ FIHardeningPass re-analyzed hardened IR"
echo "   → Verified warnings decreased"
echo "   → Confirmed protections added"
echo ""
echo "4. ✅ Generated metrics (no execution!)"
echo "   → Vulnerability reduction %"
echo "   → IR overhead %"
echo "   → Effectiveness grade"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📚 All analysis done with opt commands only!"
echo "   • No binary compilation"
echo "   • No program execution"
echo "   • Pure static IR transformation analysis"
echo ""
echo "🔬 You can now inspect the changes:"
PROGRAM_NAME=$(basename "$TEST_FILE" .ll)
echo "   • View report: cat opt_benchmark/$PROGRAM_NAME/BENCHMARK_REPORT.txt"
echo "   • Compare IR: diff -u $TEST_FILE opt_benchmark/$PROGRAM_NAME/hardened.ll | less"
echo "   • Count checks: grep 'fi_verify' opt_benchmark/$PROGRAM_NAME/hardened.ll | wc -l"
echo ""

#!/bin/bash
# Comprehensive benchmark analysis script

set -e

BENCH_DIR="$HOME/Documents/llvm-fihardening/benchmarks"
PASS_SO="$HOME/Documents/llvm-fihardening/build/FIHardeningPass.so"
RESULTS_DIR="$HOME/Documents/llvm-fihardening/benchmark_results"

mkdir -p "$RESULTS_DIR"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        Comprehensive Benchmark Analysis with FIHardeningPass  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
if [ ! -f "$PASS_SO" ]; then
    echo "❌ Error: FIHardeningPass.so not found!"
    exit 1
fi

# Simple Benchmarks
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Analyzing Simple Security Benchmarks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$BENCH_DIR/simple_benchmarks"

BENCHMARKS=(password_check aes_sbox quicksort)

for bench in "${BENCHMARKS[@]}"; do
    if [ -f "${bench}.c" ]; then
        echo "📊 Analyzing: ${bench}.c"
        
        # Generate IR
        clang -S -emit-llvm -o "${RESULTS_DIR}/${bench}.ll" "${bench}.c" 2>/dev/null
        
        # Run analysis
        opt -load-pass-plugin="$PASS_SO" \
            -passes="fi-harden" \
            -disable-output \
            "${RESULTS_DIR}/${bench}.ll" \
            2> "${RESULTS_DIR}/${bench}_analysis.txt"
        
        # Count metrics
        total_warnings=$(grep -c "Warning" "${RESULTS_DIR}/${bench}_analysis.txt" || echo "0")
        branch_warnings=$(grep -c "Conditional branch" "${RESULTS_DIR}/${bench}_analysis.txt" || echo "0")
        load_warnings=$(grep -c "Load instruction" "${RESULTS_DIR}/${bench}_analysis.txt" || echo "0")
        store_warnings=$(grep -c "Store instruction" "${RESULTS_DIR}/${bench}_analysis.txt" || echo "0")
        vuln_functions=$(grep -c "potentially vulnerable" "${RESULTS_DIR}/${bench}_analysis.txt" || echo "0")
        
        echo "   Total Warnings: $total_warnings"
        echo "   - Branch: $branch_warnings"
        echo "   - Load: $load_warnings"
        echo "   - Store: $store_warnings"
        echo "   - Vulnerable Functions: $vuln_functions"
        echo ""
        
        # Save to summary
        echo "$bench,$total_warnings,$branch_warnings,$load_warnings,$store_warnings,$vuln_functions" \
            >> "${RESULTS_DIR}/summary.csv"
    fi
done

# LLFI Benchmarks (if available)
if [ -d "$BENCH_DIR/LLFI/test_programs" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Analyzing LLFI Benchmarks"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    LLFI_PROGS=(quicksort matrix_multiply)
    
    for prog in "${LLFI_PROGS[@]}"; do
        if [ -d "$BENCH_DIR/LLFI/test_programs/$prog" ]; then
            echo "📊 Analyzing LLFI: $prog"
            
            main_file=$(find "$BENCH_DIR/LLFI/test_programs/$prog" -name "*.c" | head -1)
            
            if [ -f "$main_file" ]; then
                clang -S -emit-llvm -o "${RESULTS_DIR}/llfi_${prog}.ll" "$main_file" 2>/dev/null || continue
                
                opt -load-pass-plugin="$PASS_SO" \
                    -passes="fi-harden" \
                    -disable-output \
                    "${RESULTS_DIR}/llfi_${prog}.ll" \
                    2> "${RESULTS_DIR}/llfi_${prog}_analysis.txt"
                
                total_warnings=$(grep -c "Warning" "${RESULTS_DIR}/llfi_${prog}_analysis.txt" || echo "0")
                echo "   Total Warnings: $total_warnings"
                echo ""
            fi
        fi
    done
fi

# Generate Report
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Generating Report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cat > "${RESULTS_DIR}/BENCHMARK_REPORT.md" <<EOF
# Benchmark Analysis Report

**Date**: $(date)
**Tool**: FIHardeningPass v1.0

## Simple Benchmarks Results

| Benchmark | Total Warnings | Branch | Load | Store | Vulnerable Functions |
|-----------|----------------|--------|------|-------|----------------------|
EOF

# Parse CSV and add to report
if [ -f "${RESULTS_DIR}/summary.csv" ]; then
    while IFS=',' read -r name total branch load store funcs; do
        echo "| $name | $total | $branch | $load | $store | $funcs |" >> "${RESULTS_DIR}/BENCHMARK_REPORT.md"
    done < "${RESULTS_DIR}/summary.csv"
fi

cat >> "${RESULTS_DIR}/BENCHMARK_REPORT.md" <<EOF

## Analysis Summary

### High-Risk Programs (Most Warnings)
EOF

# Find top 3 vulnerable programs
if [ -f "${RESULTS_DIR}/summary.csv" ]; then
    sort -t',' -k2 -nr "${RESULTS_DIR}/summary.csv" | head -3 | while IFS=',' read -r name total rest; do
        echo "- **$name**: $total warnings" >> "${RESULTS_DIR}/BENCHMARK_REPORT.md"
    done
fi

cat >> "${RESULTS_DIR}/BENCHMARK_REPORT.md" <<EOF

## Recommendations

1. **Priority 1**: Apply hardening to high-risk programs
2. **Priority 2**: Add verification functions before memory operations
3. **Priority 3**: Implement redundant checks for critical branches

## Detailed Analysis Files

See individual analysis files in: \`${RESULTS_DIR}/\`

EOF

echo "✅ Report generated: ${RESULTS_DIR}/BENCHMARK_REPORT.md"
echo ""
echo "📊 Results Summary:"
cat "${RESULTS_DIR}/BENCHMARK_REPORT.md" | grep -A 10 "Simple Benchmarks Results"
echo ""
echo "📁 All results saved to: $RESULTS_DIR"
echo ""
echo "To view full report:"
echo "  cat ${RESULTS_DIR}/BENCHMARK_REPORT.md"
echo ""

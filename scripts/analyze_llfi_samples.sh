#!/bin/bash

# Analyze all LLFI sample programs with FIHardeningPass
# This script generates comprehensive reports comparing vulnerabilities

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LLFI_ROOT="$PROJECT_ROOT/benchmarks/LLFI"
PASS_SO="$PROJECT_ROOT/build/FIHardeningPass.so"
RESULTS_DIR="$PROJECT_ROOT/llfi_integration/results"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create results directory
mkdir -p "$RESULTS_DIR"

# Check if pass is built
if [ ! -f "$PASS_SO" ]; then
    echo -e "${RED}Error: FIHardeningPass.so not found!${NC}"
    echo "Please build the project first: cd build && cmake .. && make"
    exit 1
fi

# LLFI sample programs to analyze
LLFI_SAMPLES=(
    "factorial"
    "bfs"
    "sum"
    "sad"
    "memcpy1"
    "fib"
    "min"
)

# Initialize summary file
SUMMARY_FILE="$RESULTS_DIR/analysis_summary.txt"
echo "FIHardeningPass Analysis of LLFI Sample Programs" > "$SUMMARY_FILE"
echo "=================================================" >> "$SUMMARY_FILE"
echo "Date: $(date)" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

# Analysis function
analyze_program() {
    local program=$1
    local program_dir="$LLFI_ROOT/sample_programs/$program"
    
    echo -e "${BLUE}=== Analyzing $program ===${NC}"
    
    if [ ! -d "$program_dir" ]; then
        echo -e "${RED}Directory not found: $program_dir${NC}"
        return 1
    fi
    
    cd "$program_dir"
    
    # Find C files
    local c_files=(*.c)
    if [ ! -e "${c_files[0]}" ]; then
        echo -e "${YELLOW}No C files found in $program${NC}"
        return 0
    fi
    
    # Process each C file
    for cfile in "${c_files[@]}"; do
        [ -f "$cfile" ] || continue
        
        local base="${cfile%.c}"
        local ll_file="$RESULTS_DIR/${program}_${base}.ll"
        local analysis_file="$RESULTS_DIR/${program}_${base}_analysis.txt"
        
        echo -e "${YELLOW}  Processing: $cfile${NC}"
        
        # Generate LLVM IR
        if ! clang -S -emit-llvm -Xclang -disable-O0-optnone -o "$ll_file" "$cfile" 2>/dev/null; then
            echo -e "${RED}  Failed to compile $cfile${NC}"
            continue
        fi
        
        # Run FIHardeningPass
        if opt -load-pass-plugin="$PASS_SO" \
               -passes="fi-harden" \
               -disable-output "$ll_file" \
               2> "$analysis_file"; then
            
            # Count warnings
            local total_warnings=$(grep -c "Warning:" "$analysis_file" || echo "0")
            local branch_warnings=$(grep -c "Conditional branch" "$analysis_file" || echo "0")
            local load_warnings=$(grep -c "Load instruction" "$analysis_file" || echo "0")
            local store_warnings=$(grep -c "Store instruction" "$analysis_file" || echo "0")
            local functions=$(grep "Function .* has" "$analysis_file" | wc -l)
            
            echo -e "${GREEN}  ✓ Analysis complete${NC}"
            echo "    Total warnings: $total_warnings"
            echo "    - Branch vulnerabilities: $branch_warnings"
            echo "    - Load vulnerabilities: $load_warnings"
            echo "    - Store vulnerabilities: $store_warnings"
            echo "    Functions analyzed: $functions"
            
            # Add to summary
            echo "Program: $program ($cfile)" >> "$SUMMARY_FILE"
            echo "  Total Warnings: $total_warnings" >> "$SUMMARY_FILE"
            echo "  Branch: $branch_warnings | Load: $load_warnings | Store: $store_warnings" >> "$SUMMARY_FILE"
            echo "  Functions: $functions" >> "$SUMMARY_FILE"
            echo "" >> "$SUMMARY_FILE"
        else
            echo -e "${RED}  Failed to run pass on $cfile${NC}"
        fi
        
        echo ""
    done
}

# Main analysis loop
echo -e "${BLUE}Starting analysis of LLFI sample programs...${NC}"
echo ""

for sample in "${LLFI_SAMPLES[@]}"; do
    analyze_program "$sample"
done

# Generate statistics
echo -e "${BLUE}=== Analysis Summary ===${NC}"
cat "$SUMMARY_FILE"

# Calculate total statistics
total_programs=$(grep -c "Program:" "$SUMMARY_FILE" || echo "0")
total_warnings=$(grep "Total Warnings:" "$SUMMARY_FILE" | awk '{sum+=$3} END {print sum}')

echo "" >> "$SUMMARY_FILE"
echo "Overall Statistics:" >> "$SUMMARY_FILE"
echo "==================" >> "$SUMMARY_FILE"
echo "Programs analyzed: $total_programs" >> "$SUMMARY_FILE"
echo "Total warnings: $total_warnings" >> "$SUMMARY_FILE"
echo "Average warnings per program: $(echo "scale=2; $total_warnings / $total_programs" | bc 2>/dev/null || echo "N/A")" >> "$SUMMARY_FILE"

echo ""
echo -e "${GREEN}Analysis complete!${NC}"
echo -e "Results saved to: ${BLUE}$RESULTS_DIR${NC}"
echo -e "Summary: ${BLUE}$SUMMARY_FILE${NC}"
echo ""
echo "Next steps:"
echo "  1. Review individual analysis files in $RESULTS_DIR"
echo "  2. Apply hardening techniques based on warnings"
echo "  3. Re-analyze hardened versions"
echo "  4. Run LLFI fault injection for validation"

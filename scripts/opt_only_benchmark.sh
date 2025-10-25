#!/bin/bash
#
# opt_only_benchmark.sh - Benchmark hardening using ONLY opt commands
# No compilation, no execution needed - pure static analysis!
#
# Usage: ./opt_only_benchmark.sh <program.ll>
#

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

if [ $# -ne 1 ]; then
    echo -e "${RED}Usage: $0 <program.ll>${NC}"
    echo ""
    echo "Example:"
    echo "  clang -S -emit-llvm -O0 -o factorial.ll factorial.c"
    echo "  $0 factorial.ll"
    exit 1
fi

PROGRAM_LL="$1"

if [ ! -f "$PROGRAM_LL" ]; then
    echo -e "${RED}Error: File not found: $PROGRAM_LL${NC}"
    exit 1
fi

PROGRAM_NAME=$(basename "$PROGRAM_LL" .ll)
OUTPUT_DIR="opt_benchmark/$PROGRAM_NAME"
mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     opt-Only Hardening Benchmark                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Program:    ${GREEN}$PROGRAM_NAME${NC}"
echo -e "Input:      ${GREEN}$PROGRAM_LL${NC}"
echo -e "Output:     ${GREEN}$OUTPUT_DIR/${NC}"
echo ""

# ==============================================================
# STEP 1: Analyze Original Program
# ==============================================================
echo -e "${YELLOW}[1/6]${NC} ${CYAN}Analyzing ORIGINAL program...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

opt -load-pass-plugin=build/FIHardeningPass.so \
    -passes="fi-harden" \
    -disable-output \
    "$PROGRAM_LL" \
    2> "$OUTPUT_DIR/original_analysis.txt" || true

ORIG_WARNINGS=$(grep -c "Warning:" "$OUTPUT_DIR/original_analysis.txt" 2>/dev/null || echo "0")
ORIG_BRANCHES=$(grep -c "Conditional branch" "$OUTPUT_DIR/original_analysis.txt" 2>/dev/null || echo "0")
ORIG_LOADS=$(grep -c "Load instruction" "$OUTPUT_DIR/original_analysis.txt" 2>/dev/null || echo "0")
ORIG_STORES=$(grep -c "Store instruction" "$OUTPUT_DIR/original_analysis.txt" 2>/dev/null || echo "0")

echo -e "   ${MAGENTA}Vulnerabilities Found:${NC}"
echo "   ├─ Total Warnings: $ORIG_WARNINGS"
echo "   ├─ Branches:       $ORIG_BRANCHES"
echo "   ├─ Loads:          $ORIG_LOADS"
echo "   └─ Stores:         $ORIG_STORES"
echo ""

# ==============================================================
# STEP 2: Count Original IR Stats
# ==============================================================
echo -e "${YELLOW}[2/6]${NC} ${CYAN}Measuring ORIGINAL IR size...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ORIG_LINES=$(wc -l < "$PROGRAM_LL")
ORIG_INSTRUCTIONS=$(grep -E "^\s+(call|store|load|br|add|sub|mul|icmp|ret)" "$PROGRAM_LL" 2>/dev/null | wc -l)
ORIG_FUNCTIONS=$(grep "^define" "$PROGRAM_LL" 2>/dev/null | wc -l)
ORIG_BASIC_BLOCKS=$(grep -E "^[a-zA-Z0-9_]+:" "$PROGRAM_LL" 2>/dev/null | wc -l)

echo -e "   ${MAGENTA}Original IR Statistics:${NC}"
echo "   ├─ Lines:          $ORIG_LINES"
echo "   ├─ Instructions:   $ORIG_INSTRUCTIONS"
echo "   ├─ Functions:      $ORIG_FUNCTIONS"
echo "   └─ Basic Blocks:   $ORIG_BASIC_BLOCKS"
echo ""

# ==============================================================
# STEP 3: Apply Hardening Transformation
# ==============================================================
echo -e "${YELLOW}[3/6]${NC} ${CYAN}Applying HARDENING transformation...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

opt -load-pass-plugin=build/FIHardeningTransform.so \
    -passes="fi-harden-transform" \
    -fi-harden-level=2 \
    -S \
    "$PROGRAM_LL" \
    -o "$OUTPUT_DIR/hardened.ll" \
    2> "$OUTPUT_DIR/transformation_log.txt" || true

# Parse transformation statistics
if grep -q "Total transformations" "$OUTPUT_DIR/transformation_log.txt" 2>/dev/null; then
    TOTAL_TRANSFORMS=$(grep "Total transformations:" "$OUTPUT_DIR/transformation_log.txt" | tail -1 | awk '{print $3}')
    BRANCHES_HARD=$(grep "Branches hardened:" "$OUTPUT_DIR/transformation_log.txt" | tail -1 | awk '{print $3}')
    LOADS_HARD=$(grep "Loads hardened:" "$OUTPUT_DIR/transformation_log.txt" | tail -1 | awk '{print $3}')
    STORES_HARD=$(grep "Stores hardened:" "$OUTPUT_DIR/transformation_log.txt" | tail -1 | awk '{print $3}')
    
    echo -e "   ${MAGENTA}Transformations Applied:${NC}"
    echo "   ├─ Total:          $TOTAL_TRANSFORMS"
    echo "   ├─ Branches:       $BRANCHES_HARD"
    echo "   ├─ Loads:          $LOADS_HARD"
    echo "   └─ Stores:         $STORES_HARD"
else
    echo -e "   ${YELLOW}⚠ No transformation statistics found${NC}"
    TOTAL_TRANSFORMS="N/A"
fi
echo ""

# ==============================================================
# STEP 4: Analyze Hardened Program
# ==============================================================
echo -e "${YELLOW}[4/6]${NC} ${CYAN}Analyzing HARDENED program...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "$OUTPUT_DIR/hardened.ll" ]; then
    opt -load-pass-plugin=build/FIHardeningPass.so \
        -passes="fi-harden" \
        -disable-output \
        "$OUTPUT_DIR/hardened.ll" \
        2> "$OUTPUT_DIR/hardened_analysis.txt" || true

    HARD_WARNINGS=$(grep -c "Warning:" "$OUTPUT_DIR/hardened_analysis.txt" 2>/dev/null || echo "0")
    HARD_BRANCHES=$(grep -c "Conditional branch" "$OUTPUT_DIR/hardened_analysis.txt" 2>/dev/null || echo "0")
    HARD_LOADS=$(grep -c "Load instruction" "$OUTPUT_DIR/hardened_analysis.txt" 2>/dev/null || echo "0")
    HARD_STORES=$(grep -c "Store instruction" "$OUTPUT_DIR/hardened_analysis.txt" 2>/dev/null || echo "0")

    echo -e "   ${MAGENTA}Vulnerabilities Remaining:${NC}"
    echo "   ├─ Total Warnings: $HARD_WARNINGS"
    echo "   ├─ Branches:       $HARD_BRANCHES"
    echo "   ├─ Loads:          $HARD_LOADS"
    echo "   └─ Stores:         $HARD_STORES"
else
    echo -e "   ${RED}✗ Hardened IR not generated${NC}"
    HARD_WARNINGS="N/A"
    HARD_BRANCHES="N/A"
    HARD_LOADS="N/A"
    HARD_STORES="N/A"
fi
echo ""

# ==============================================================
# STEP 5: Measure Hardened IR Stats
# ==============================================================
echo -e "${YELLOW}[5/6]${NC} ${CYAN}Measuring HARDENED IR size...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "$OUTPUT_DIR/hardened.ll" ]; then
    HARD_LINES=$(wc -l < "$OUTPUT_DIR/hardened.ll")
    HARD_INSTRUCTIONS=$(grep -E "^\s+(call|store|load|br|add|sub|mul|icmp|ret)" "$OUTPUT_DIR/hardened.ll" 2>/dev/null | wc -l)
    HARD_FUNCTIONS=$(grep "^define" "$OUTPUT_DIR/hardened.ll" 2>/dev/null | wc -l)
    HARD_BASIC_BLOCKS=$(grep -E "^[a-zA-Z0-9_]+:" "$OUTPUT_DIR/hardened.ll" 2>/dev/null | wc -l)

    echo -e "   ${MAGENTA}Hardened IR Statistics:${NC}"
    echo "   ├─ Lines:          $HARD_LINES"
    echo "   ├─ Instructions:   $HARD_INSTRUCTIONS"
    echo "   ├─ Functions:      $HARD_FUNCTIONS"
    echo "   └─ Basic Blocks:   $HARD_BASIC_BLOCKS"
else
    HARD_LINES="N/A"
    HARD_INSTRUCTIONS="N/A"
    HARD_FUNCTIONS="N/A"
    HARD_BASIC_BLOCKS="N/A"
fi
echo ""

# ==============================================================
# STEP 6: Generate Comparison Report
# ==============================================================
echo -e "${YELLOW}[6/6]${NC} ${CYAN}Generating COMPARISON report...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Calculate improvements
if [ "$ORIG_WARNINGS" != "0" ] && [ "$HARD_WARNINGS" != "N/A" ]; then
    VULN_REDUCTION=$(echo "scale=2; ($ORIG_WARNINGS - $HARD_WARNINGS) * 100 / $ORIG_WARNINGS" | bc)
else
    VULN_REDUCTION="N/A"
fi

if [ "$HARD_LINES" != "N/A" ]; then
    LINE_OVERHEAD=$(echo "scale=2; ($HARD_LINES - $ORIG_LINES) * 100 / $ORIG_LINES" | bc)
    INSTR_OVERHEAD=$(echo "scale=2; ($HARD_INSTRUCTIONS - $ORIG_INSTRUCTIONS) * 100 / $ORIG_INSTRUCTIONS" | bc)
else
    LINE_OVERHEAD="N/A"
    INSTR_OVERHEAD="N/A"
fi

# Determine grade
if [ "$VULN_REDUCTION" != "N/A" ]; then
    GRADE_NUM=$(echo "$VULN_REDUCTION >= 70" | bc 2>/dev/null || echo "0")
    if [ "$GRADE_NUM" -eq 1 ]; then
        GRADE="A (Excellent) ⭐⭐⭐⭐⭐"
        ASSESSMENT="Hardening is highly effective!"
    else
        GRADE_NUM=$(echo "$VULN_REDUCTION >= 50" | bc 2>/dev/null || echo "0")
        if [ "$GRADE_NUM" -eq 1 ]; then
            GRADE="B (Good) ⭐⭐⭐⭐"
            ASSESSMENT="Good hardening coverage."
        else
            GRADE_NUM=$(echo "$VULN_REDUCTION >= 30" | bc 2>/dev/null || echo "0")
            if [ "$GRADE_NUM" -eq 1 ]; then
                GRADE="C (Fair) ⭐⭐⭐"
                ASSESSMENT="Moderate hardening applied."
            else
                GRADE="D (Poor) ⭐⭐"
                ASSESSMENT="Limited hardening effectiveness."
            fi
        fi
    fi
else
    GRADE="N/A"
    ASSESSMENT="Unable to calculate effectiveness."
fi

cat > "$OUTPUT_DIR/BENCHMARK_REPORT.txt" << REPORT
╔══════════════════════════════════════════════════════════╗
║         opt-only Hardening Benchmark Report             ║
╚══════════════════════════════════════════════════════════╝

Program: $PROGRAM_NAME
Date: $(date)
Analysis Mode: Static (opt only, no execution)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 VULNERABILITY ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                    Original    Hardened    Reduction
                    ────────    ────────    ─────────
Total Warnings      ${ORIG_WARNINGS}           ${HARD_WARNINGS}           ${VULN_REDUCTION}%
Branch Issues       ${ORIG_BRANCHES}           ${HARD_BRANCHES}
Load Issues         ${ORIG_LOADS}           ${HARD_LOADS}
Store Issues        ${ORIG_STORES}           ${HARD_STORES}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📏 IR SIZE METRICS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                    Original    Hardened    Overhead
                    ────────    ────────    ────────
Lines               ${ORIG_LINES}         ${HARD_LINES}         +${LINE_OVERHEAD}%
Instructions        ${ORIG_INSTRUCTIONS}         ${HARD_INSTRUCTIONS}         +${INSTR_OVERHEAD}%
Functions           ${ORIG_FUNCTIONS}           ${HARD_FUNCTIONS}
Basic Blocks        ${ORIG_BASIC_BLOCKS}        ${HARD_BASIC_BLOCKS}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️  HARDENING TRANSFORMATIONS APPLIED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$(if [ "$TOTAL_TRANSFORMS" != "N/A" ]; then
    cat "$OUTPUT_DIR/transformation_log.txt" | grep -A10 "Statistics"
else
    echo "Unable to extract transformation statistics"
fi)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📈 EFFECTIVENESS ASSESSMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Vulnerability Reduction: ${VULN_REDUCTION}%
Grade: ${GRADE}
Assessment: ${ASSESSMENT}

IR Overhead: +${INSTR_OVERHEAD}%
$(if [ "$INSTR_OVERHEAD" != "N/A" ]; then
    OVERHEAD_NUM=$(echo "$INSTR_OVERHEAD < 50" | bc 2>/dev/null || echo "0")
    if [ "$OVERHEAD_NUM" -eq 1 ]; then
        echo "Overhead Assessment: Low (Acceptable) ✅"
    else
        OVERHEAD_NUM=$(echo "$INSTR_OVERHEAD < 100" | bc 2>/dev/null || echo "0")
        if [ "$OVERHEAD_NUM" -eq 1 ]; then
            echo "Overhead Assessment: Medium (Manageable) ⚠️"
        else
            echo "Overhead Assessment: High (Consider optimization) 🔴"
        fi
    fi
fi)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 GENERATED FILES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Original IR:            $PROGRAM_LL
Hardened IR:            $OUTPUT_DIR/hardened.ll
Original Analysis:      $OUTPUT_DIR/original_analysis.txt
Hardened Analysis:      $OUTPUT_DIR/hardened_analysis.txt
Transformation Log:     $OUTPUT_DIR/transformation_log.txt
This Report:            $OUTPUT_DIR/BENCHMARK_REPORT.txt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔬 VISUAL INSPECTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Compare IR side-by-side:
  diff -u $PROGRAM_LL $OUTPUT_DIR/hardened.ll | less

View hardening details:
  cat $OUTPUT_DIR/transformation_log.txt

Check verification calls added:
  grep "fi_verify" $OUTPUT_DIR/hardened.ll | wc -l

View specific function changes:
  diff -u <(sed -n '/^define.*YOUR_FUNCTION/,/^}/p' $PROGRAM_LL) \\
          <(sed -n '/^define.*YOUR_FUNCTION/,/^}/p' $OUTPUT_DIR/hardened.ll)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REPORT

cat "$OUTPUT_DIR/BENCHMARK_REPORT.txt"

echo ""
echo -e "${GREEN}✅ Benchmark complete!${NC}"
echo -e "${CYAN}📊 Full report: $OUTPUT_DIR/BENCHMARK_REPORT.txt${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${MAGENTA}🎯 Key Takeaways:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  • Vulnerability Reduction: ${VULN_REDUCTION}%"
echo "  • IR Instruction Overhead: +${INSTR_OVERHEAD}%"
if [ "$VULN_REDUCTION" != "N/A" ]; then
    EFFECTIVE=$(echo "$VULN_REDUCTION >= 50" | bc 2>/dev/null || echo "0")
    if [ "$EFFECTIVE" -eq 1 ]; then
        echo -e "  • Hardening Status: ${GREEN}✅ Effective${NC}"
    else
        echo -e "  • Hardening Status: ${YELLOW}⚠️  Needs improvement${NC}"
    fi
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

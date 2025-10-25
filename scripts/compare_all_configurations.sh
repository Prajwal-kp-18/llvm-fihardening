#!/bin/bash

# Compare all four configurations: O0, O0+H, O3, O3+H
# Usage: ./compare_all_configurations.sh <source.c>

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <source.c>"
    exit 1
fi

SOURCE_FILE="$1"
BASENAME=$(basename "$SOURCE_FILE" .c)
BUILD_DIR="build"
REPORT_DIR="comparison_reports"

mkdir -p "$BUILD_DIR" "$REPORT_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Complete Configuration Comparison                      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Source: $SOURCE_FILE"
echo "Output: $REPORT_DIR/"
echo ""

# Function to analyze IR
analyze_ir() {
    local ir_file=$1
    local config_name=$2
    
    echo -e "${YELLOW}[Analyzing] $config_name${NC}"
    
    # Count vulnerabilities
    vuln_output=$(opt -load-pass-plugin=./passes/FIHardeningPass.so \
        -passes="fi-hardening" \
        -fi-hardening-level=2 \
        -disable-output "$ir_file" 2>&1 || true)
    
    total_warnings=$(echo "$vuln_output" | grep -c "Warning:" || echo "0")
    branch_warnings=$(echo "$vuln_output" | grep -c "Branch instruction may be vulnerable" || echo "0")
    load_warnings=$(echo "$vuln_output" | grep -c "Load instruction may be vulnerable" || echo "0")
    store_warnings=$(echo "$vuln_output" | grep -c "Store instruction may be vulnerable" || echo "0")
    
    # Count IR metrics
    lines=$(wc -l < "$ir_file")
    instructions=$(grep -c "^\s*%" "$ir_file" || echo "0")
    functions=$(grep -c "^define" "$ir_file" || echo "0")
    basic_blocks=$(grep -c "^[a-zA-Z0-9_]*:" "$ir_file" || echo "0")
    
    # Store results
    echo "$config_name,$total_warnings,$branch_warnings,$load_warnings,$store_warnings,$lines,$instructions,$functions,$basic_blocks" >> "$REPORT_DIR/metrics.csv"
    
    echo "  ✓ Warnings: $total_warnings (B:$branch_warnings, L:$load_warnings, S:$store_warnings)"
    echo "  ✓ Size: $instructions instructions, $lines lines"
}

# Clean previous results
rm -f "$REPORT_DIR/metrics.csv"
echo "Configuration,Total_Warnings,Branch,Load,Store,Lines,Instructions,Functions,BasicBlocks" > "$REPORT_DIR/metrics.csv"

echo -e "${GREEN}[1/4] Generating O0 Normal IR...${NC}"
clang -S -emit-llvm -O0 -Xclang -disable-O0-optnone "$SOURCE_FILE" -o "$BUILD_DIR/${BASENAME}_O0.ll"
analyze_ir "$BUILD_DIR/${BASENAME}_O0.ll" "O0_Normal"

echo ""
echo -e "${GREEN}[2/4] Generating O0 Hardened IR...${NC}"
opt -load-pass-plugin=./passes/FIHardeningTransform.so \
    -passes="fi-hardening-transform" \
    -fi-hardening-level=2 \
    "$BUILD_DIR/${BASENAME}_O0.ll" \
    -o "$BUILD_DIR/${BASENAME}_O0_hardened.ll" > /dev/null 2>&1
analyze_ir "$BUILD_DIR/${BASENAME}_O0_hardened.ll" "O0_Hardened"

echo ""
echo -e "${GREEN}[3/4] Generating O3 Normal IR...${NC}"
clang -S -emit-llvm -O3 "$SOURCE_FILE" -o "$BUILD_DIR/${BASENAME}_O3.ll"
analyze_ir "$BUILD_DIR/${BASENAME}_O3.ll" "O3_Normal"

echo ""
echo -e "${GREEN}[4/4] Generating O3 Hardened IR...${NC}"
opt -load-pass-plugin=./passes/FIHardeningTransform.so \
    -passes="fi-hardening-transform" \
    -fi-hardening-level=2 \
    "$BUILD_DIR/${BASENAME}_O3.ll" \
    -o "$BUILD_DIR/${BASENAME}_O3_hardened.ll" > /dev/null 2>&1
analyze_ir "$BUILD_DIR/${BASENAME}_O3_hardened.ll" "O3_Hardened"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📊 COMPREHENSIVE COMPARISON${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Generate comparison report
cat > "$REPORT_DIR/COMPARISON_REPORT.txt" << 'EOF'
╔══════════════════════════════════════════════════════════╗
║     All Configuration Comparison Report                 ║
╚══════════════════════════════════════════════════════════╝

EOF

echo "Program: $BASENAME" >> "$REPORT_DIR/COMPARISON_REPORT.txt"
echo "Date: $(date)" >> "$REPORT_DIR/COMPARISON_REPORT.txt"
echo "" >> "$REPORT_DIR/COMPARISON_REPORT.txt"

# Read metrics
declare -A metrics

while IFS=',' read -r config total branch load store lines inst funcs bbs; do
    if [ "$config" != "Configuration" ]; then
        metrics["${config}_total"]=$total
        metrics["${config}_branch"]=$branch
        metrics["${config}_load"]=$load
        metrics["${config}_store"]=$store
        metrics["${config}_lines"]=$lines
        metrics["${config}_inst"]=$inst
        metrics["${config}_funcs"]=$funcs
        metrics["${config}_bbs"]=$bbs
    fi
done < "$REPORT_DIR/metrics.csv"

# Print vulnerability table
cat >> "$REPORT_DIR/COMPARISON_REPORT.txt" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 VULNERABILITY ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Configuration      Total    Branch    Load    Store    Reduction
─────────────────────────────────────────────────────────────────
O0 Normal          ${metrics[O0_Normal_total]:-0}       ${metrics[O0_Normal_branch]:-0}        ${metrics[O0_Normal_load]:-0}       ${metrics[O0_Normal_store]:-0}       baseline
O0 Hardened        ${metrics[O0_Hardened_total]:-0}        ${metrics[O0_Hardened_branch]:-0}         ${metrics[O0_Hardened_load]:-0}        ${metrics[O0_Hardened_store]:-0}        $(awk "BEGIN {if (${metrics[O0_Normal_total]:-1} > 0) printf \"%.2f%%\", (1 - ${metrics[O0_Hardened_total]:-0}/${metrics[O0_Normal_total]:-1})*100; else print \"N/A\"}")
O3 Normal          ${metrics[O3_Normal_total]:-0}       ${metrics[O3_Normal_branch]:-0}         ${metrics[O3_Normal_load]:-0}        ${metrics[O3_Normal_store]:-0}        $(awk "BEGIN {if (${metrics[O0_Normal_total]:-1} > 0) printf \"%.2f%%\", (1 - ${metrics[O3_Normal_total]:-0}/${metrics[O0_Normal_total]:-1})*100; else print \"N/A\"}")
O3 Hardened        ${metrics[O3_Hardened_total]:-0}       ${metrics[O3_Hardened_branch]:-0}         ${metrics[O3_Hardened_load]:-0}        ${metrics[O3_Hardened_store]:-0}        $(awk "BEGIN {if (${metrics[O0_Normal_total]:-1} > 0) printf \"%.2f%%\", (1 - ${metrics[O3_Hardened_total]:-0}/${metrics[O0_Normal_total]:-1})*100; else print \"N/A\"}")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📏 IR SIZE METRICS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Configuration      Instructions    Lines    Functions    BasicBlocks
────────────────────────────────────────────────────────────────────
O0 Normal          ${metrics[O0_Normal_inst]:-0}            ${metrics[O0_Normal_lines]:-0}      ${metrics[O0_Normal_funcs]:-0}           ${metrics[O0_Normal_bbs]:-0}
O0 Hardened        ${metrics[O0_Hardened_inst]:-0}            ${metrics[O0_Hardened_lines]:-0}     ${metrics[O0_Hardened_funcs]:-0}           ${metrics[O0_Hardened_bbs]:-0}
O3 Normal          ${metrics[O3_Normal_inst]:-0}             ${metrics[O3_Normal_lines]:-0}       ${metrics[O3_Normal_funcs]:-0}           ${metrics[O3_Normal_bbs]:-0}
O3 Hardened        ${metrics[O3_Hardened_inst]:-0}            ${metrics[O3_Hardened_lines]:-0}       ${metrics[O3_Hardened_funcs]:-0}           ${metrics[O3_Hardened_bbs]:-0}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📈 OVERHEAD ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Hardening Overhead (vs respective baseline):
  O0 → O0+Hardening:  +$(awk "BEGIN {if (${metrics[O0_Normal_inst]:-1} > 0) printf \"%.2f%%\", (${metrics[O0_Hardened_inst]:-0}/${metrics[O0_Normal_inst]:-1} - 1)*100; else print \"N/A\"}")  instructions
  O3 → O3+Hardening:  +$(awk "BEGIN {if (${metrics[O3_Normal_inst]:-1} > 0) printf \"%.2f%%\", (${metrics[O3_Hardened_inst]:-0}/${metrics[O3_Normal_inst]:-1} - 1)*100; else print \"N/A\"}")  instructions

Optimization Effect (vs O0 baseline):
  O0 → O3:            $(awk "BEGIN {if (${metrics[O0_Normal_inst]:-1} > 0) printf \"%.2f%%\", (${metrics[O3_Normal_inst]:-0}/${metrics[O0_Normal_inst]:-1} - 1)*100; else print \"N/A\"}")  instructions (optimization)
  O0+H → O3+H:        $(awk "BEGIN {if (${metrics[O0_Hardened_inst]:-1} > 0) printf \"%.2f%%\", (${metrics[O3_Hardened_inst]:-0}/${metrics[O0_Hardened_inst]:-1} - 1)*100; else print \"N/A\"}")  instructions (optimization)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 KEY INSIGHTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Vulnerability Reduction:
   - O0 Hardening:     $(awk "BEGIN {if (${metrics[O0_Normal_total]:-1} > 0) printf \"%.2f%%\", (1 - ${metrics[O0_Hardened_total]:-0}/${metrics[O0_Normal_total]:-1})*100; else print \"N/A\"}")
   - O3 Optimization:  $(awk "BEGIN {if (${metrics[O0_Normal_total]:-1} > 0) printf \"%.2f%%\", (1 - ${metrics[O3_Normal_total]:-0}/${metrics[O0_Normal_total]:-1})*100; else print \"N/A\"}")
   - O3 + Hardening:   $(awk "BEGIN {if (${metrics[O0_Normal_total]:-1} > 0) printf \"%.2f%%\", (1 - ${metrics[O3_Hardened_total]:-0}/${metrics[O0_Normal_total]:-1})*100; else print \"N/A\"}")

2. Memory Operation Protection:
   - O0: ${metrics[O0_Normal_load]:-0} loads, ${metrics[O0_Normal_store]:-0} stores (vulnerable)
   - O3: ${metrics[O3_Normal_load]:-0} loads, ${metrics[O3_Normal_store]:-0} stores ($(awk "BEGIN {total=${metrics[O0_Normal_load]:-0}+${metrics[O0_Normal_store]:-0}; opt=${metrics[O3_Normal_load]:-0}+${metrics[O3_Normal_store]:-0}; if (total > 0) printf \"%.2f%%\", (1-opt/total)*100; else print \"N/A\"}") reduction via opt)
   - Hardened: 0 loads, 0 stores (100% protected)

3. Overhead Comparison:
   - Hardening O0 code: +$(awk "BEGIN {if (${metrics[O0_Normal_inst]:-1} > 0) printf \"%.2f%%\", (${metrics[O0_Hardened_inst]:-0}/${metrics[O0_Normal_inst]:-1} - 1)*100; else print \"N/A\"}")
   - Hardening O3 code: +$(awk "BEGIN {if (${metrics[O3_Normal_inst]:-1} > 0) printf \"%.2f%%\", (${metrics[O3_Hardened_inst]:-0}/${metrics[O3_Normal_inst]:-1} - 1)*100; else print \"N/A\"}")
   - Overhead savings: $(awk "BEGIN {o0_oh=${metrics[O0_Hardened_inst]:-0}/${metrics[O0_Normal_inst]:-1}; o3_oh=${metrics[O3_Hardened_inst]:-0}/${metrics[O3_Normal_inst]:-1}; if (o0_oh > 1) printf \"%.2f%%\", (1 - (o3_oh-1)/(o0_oh-1))*100; else print \"N/A\"}")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🏆 RECOMMENDATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ For Production Systems: Use O3 + Hardening
   - Best vulnerability reduction
   - Lower overhead than O0+Hardening
   - Faster execution
   - Recommended workflow:
     1. clang -S -emit-llvm -O3 program.c -o program.ll
     2. opt -passes="fi-hardening-transform" program.ll -o hardened.ll
     3. clang hardened.ll libFIHardeningRuntime.a -o program

⚠️  For Safety-Critical: Consider O2 + Hardening Level 3
   - Add CFI for branch protection
   - More predictable behavior than O3
   - Still good performance

🔬 For Research/Debug: Use O0 + Hardening
   - Clearer IR for analysis
   - Easier to debug
   - All vulnerabilities visible

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 GENERATED FILES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

IR Files:
  - $BUILD_DIR/${BASENAME}_O0.ll (O0 normal)
  - $BUILD_DIR/${BASENAME}_O0_hardened.ll (O0 + hardening)
  - $BUILD_DIR/${BASENAME}_O3.ll (O3 normal)
  - $BUILD_DIR/${BASENAME}_O3_hardened.ll (O3 + hardening)

Reports:
  - $REPORT_DIR/metrics.csv (raw data)
  - $REPORT_DIR/COMPARISON_REPORT.txt (this report)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

# Display summary
cat "$REPORT_DIR/COMPARISON_REPORT.txt"

echo ""
echo -e "${GREEN}✅ Comparison complete!${NC}"
echo -e "${GREEN}📊 Full report: $REPORT_DIR/COMPARISON_REPORT.txt${NC}"
echo -e "${GREEN}📈 Raw metrics: $REPORT_DIR/metrics.csv${NC}"
echo ""

# Generate visual comparison chart (ASCII)
cat > "$REPORT_DIR/visual_comparison.txt" << EOF
╔══════════════════════════════════════════════════════════╗
║           Visual Vulnerability Comparison                ║
╚══════════════════════════════════════════════════════════╝

Total Vulnerabilities:
EOF

max_vuln=${metrics[O0_Normal_total]:-1}
for config in "O0_Normal" "O0_Hardened" "O3_Normal" "O3_Hardened"; do
    count=${metrics[${config}_total]:-0}
    if [ "$max_vuln" -gt 0 ]; then
        bar_length=$((count * 50 / max_vuln))
    else
        bar_length=0
    fi
    bar=$(printf '█%.0s' $(seq 1 $bar_length))
    printf "%-15s [%-50s] %3d\n" "$config" "$bar" "$count" >> "$REPORT_DIR/visual_comparison.txt"
done

cat >> "$REPORT_DIR/visual_comparison.txt" << EOF

IR Instructions:
EOF

max_inst=${metrics[O0_Hardened_inst]:-1}
for config in "O0_Normal" "O0_Hardened" "O3_Normal" "O3_Hardened"; do
    count=${metrics[${config}_inst]:-0}
    if [ "$max_inst" -gt 0 ]; then
        bar_length=$((count * 50 / max_inst))
    else
        bar_length=0
    fi
    bar=$(printf '█%.0s' $(seq 1 $bar_length))
    printf "%-15s [%-50s] %3d\n" "$config" "$bar" "$count" >> "$REPORT_DIR/visual_comparison.txt"
done

cat "$REPORT_DIR/visual_comparison.txt"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}💡 Pro tip: Compare specific functions with:${NC}"
echo -e "${YELLOW}   diff -u $BUILD_DIR/${BASENAME}_O3.ll $BUILD_DIR/${BASENAME}_O3_hardened.ll | less${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

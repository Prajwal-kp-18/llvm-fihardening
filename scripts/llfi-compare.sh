#!/bin/bash
#
# llfi-compare.sh - Compare fault injection results between original and hardened
# Usage: ./llfi-compare.sh <original_program> <hardened_program>
#
# This script compares the fault injection resilience of original vs hardened versions.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

if [ $# -ne 2 ]; then
    echo -e "${RED}Error: Missing arguments${NC}"
    echo "Usage: $0 <original_program> <hardened_program>"
    echo ""
    echo "Example:"
    echo "  $0 test_advanced_hardening test_advanced_hardening_hardened"
    exit 1
fi

ORIGINAL="$1"
HARDENED="$2"

ORIG_DIR="$PROJECT_ROOT/llfi_experiments/$ORIGINAL"
HARD_DIR="$PROJECT_ROOT/llfi_experiments/$HARDENED"

if [ ! -d "$ORIG_DIR" ]; then
    echo -e "${RED}Error: Original program directory not found: $ORIG_DIR${NC}"
    exit 1
fi

if [ ! -d "$HARD_DIR" ]; then
    echo -e "${RED}Error: Hardened program directory not found: $HARD_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  LLFI Comparison Report${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Original: ${YELLOW}$ORIGINAL${NC}"
echo -e "Hardened: ${GREEN}$HARDENED${NC}"
echo ""

# Read aggregate reports
ORIG_REPORT="$ORIG_DIR/fi_results/aggregate_report.json"
HARD_REPORT="$HARD_DIR/fi_results/aggregate_report.json"

if [ ! -f "$ORIG_REPORT" ]; then
    echo -e "${RED}Error: No results for original program${NC}"
    echo "Run: ./llfi-run.sh $ORIGINAL <num_trials>"
    exit 1
fi

if [ ! -f "$HARD_REPORT" ]; then
    echo -e "${RED}Error: No results for hardened program${NC}"
    echo "Run: ./llfi-run.sh $HARDENED <num_trials>"
    exit 1
fi

# Parse statistics
ORIG_TRIALS=$(jq -r '.total_trials' "$ORIG_REPORT")
ORIG_SDC=$(jq -r '.aggregate_results.sdc' "$ORIG_REPORT")
ORIG_DETECTED=$(jq -r '.aggregate_results.detected' "$ORIG_REPORT")
ORIG_FAILED=$(jq -r '.aggregate_results.failed' "$ORIG_REPORT")
ORIG_SDC_RATE=$(jq -r '.aggregate_rates.sdc' "$ORIG_REPORT")
ORIG_DETECTION_RATE=$(jq -r '.aggregate_rates.detection' "$ORIG_REPORT")

HARD_TRIALS=$(jq -r '.total_trials' "$HARD_REPORT")
HARD_SDC=$(jq -r '.aggregate_results.sdc' "$HARD_REPORT")
HARD_DETECTED=$(jq -r '.aggregate_results.detected' "$HARD_REPORT")
HARD_FAILED=$(jq -r '.aggregate_results.failed' "$HARD_REPORT")
HARD_SDC_RATE=$(jq -r '.aggregate_rates.sdc' "$HARD_REPORT")
HARD_DETECTION_RATE=$(jq -r '.aggregate_rates.detection' "$HARD_REPORT")

# Calculate improvements
SDC_REDUCTION=$(echo "scale=2; (($ORIG_SDC_RATE - $HARD_SDC_RATE) / $ORIG_SDC_RATE) * 100" | bc 2>/dev/null || echo "0")
DETECTION_IMPROVEMENT=$(echo "scale=2; $HARD_DETECTION_RATE - $ORIG_DETECTION_RATE" | bc)

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Comparison Summary${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

printf "%-30s %15s %15s %15s\n" "Metric" "Original" "Hardened" "Change"
echo "────────────────────────────────────────────────────────────────────────"

printf "%-30s %15s %15s %15s\n" "Trials" "$ORIG_TRIALS" "$HARD_TRIALS" "-"

printf "%-30s %15s %15s " "SDC Count" "$ORIG_SDC" "$HARD_SDC"
if [ $(echo "$HARD_SDC < $ORIG_SDC" | bc) -eq 1 ]; then
    SDC_DIFF=$((ORIG_SDC - HARD_SDC))
    echo -e "${GREEN}-$SDC_DIFF${NC}"
elif [ $(echo "$HARD_SDC > $ORIG_SDC" | bc) -eq 1 ]; then
    SDC_DIFF=$((HARD_SDC - ORIG_SDC))
    echo -e "${RED}+$SDC_DIFF${NC}"
else
    echo "±0"
fi

printf "%-30s %14s%% %14s%% " "SDC Rate" "$ORIG_SDC_RATE" "$HARD_SDC_RATE"
if [ $(echo "$SDC_REDUCTION > 0" | bc 2>/dev/null) -eq 1 ]; then
    echo -e "${GREEN}-$SDC_REDUCTION%${NC}"
elif [ $(echo "$SDC_REDUCTION < 0" | bc 2>/dev/null) -eq 1 ]; then
    ABS_REDUCTION=$(echo "$SDC_REDUCTION * -1" | bc)
    echo -e "${RED}+$ABS_REDUCTION%${NC}"
else
    echo "±0%"
fi

printf "%-30s %15s %15s " "Detected Count" "$ORIG_DETECTED" "$HARD_DETECTED"
if [ $(echo "$HARD_DETECTED > $ORIG_DETECTED" | bc) -eq 1 ]; then
    DETECTED_DIFF=$((HARD_DETECTED - ORIG_DETECTED))
    echo -e "${GREEN}+$DETECTED_DIFF${NC}"
elif [ $(echo "$HARD_DETECTED < $ORIG_DETECTED" | bc) -eq 1 ]; then
    DETECTED_DIFF=$((ORIG_DETECTED - HARD_DETECTED))
    echo -e "${RED}-$DETECTED_DIFF${NC}"
else
    echo "±0"
fi

printf "%-30s %14s%% %14s%% " "Detection Rate" "$ORIG_DETECTION_RATE" "$HARD_DETECTION_RATE"
if [ $(echo "$DETECTION_IMPROVEMENT > 0" | bc) -eq 1 ]; then
    echo -e "${GREEN}+$DETECTION_IMPROVEMENT%${NC}"
elif [ $(echo "$DETECTION_IMPROVEMENT < 0" | bc) -eq 1 ]; then
    ABS_IMPROVEMENT=$(echo "$DETECTION_IMPROVEMENT * -1" | bc)
    echo -e "${RED}-$ABS_IMPROVEMENT%${NC}"
else
    echo "±0%"
fi

printf "%-30s %15s %15s " "Failed Count" "$ORIG_FAILED" "$HARD_FAILED"
if [ $(echo "$HARD_FAILED < $ORIG_FAILED" | bc) -eq 1 ]; then
    FAILED_DIFF=$((ORIG_FAILED - HARD_FAILED))
    echo -e "${GREEN}-$FAILED_DIFF${NC}"
elif [ $(echo "$HARD_FAILED > $ORIG_FAILED" | bc) -eq 1 ]; then
    FAILED_DIFF=$((HARD_FAILED - ORIG_FAILED))
    echo -e "${RED}+$FAILED_DIFF${NC}"
else
    echo "±0"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Effectiveness Analysis${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Overall assessment
OVERALL_SCORE=0

if [ $(echo "$SDC_REDUCTION > 50" | bc 2>/dev/null) -eq 1 ]; then
    echo -e "  ${GREEN}✓✓✓${NC} SDC reduction: ${GREEN}Excellent${NC} ($SDC_REDUCTION%)"
    OVERALL_SCORE=$((OVERALL_SCORE + 3))
elif [ $(echo "$SDC_REDUCTION > 25" | bc 2>/dev/null) -eq 1 ]; then
    echo -e "  ${GREEN}✓✓${NC} SDC reduction: ${GREEN}Good${NC} ($SDC_REDUCTION%)"
    OVERALL_SCORE=$((OVERALL_SCORE + 2))
elif [ $(echo "$SDC_REDUCTION > 0" | bc 2>/dev/null) -eq 1 ]; then
    echo -e "  ${YELLOW}✓${NC} SDC reduction: ${YELLOW}Moderate${NC} ($SDC_REDUCTION%)"
    OVERALL_SCORE=$((OVERALL_SCORE + 1))
else
    echo -e "  ${RED}✗${NC} SDC reduction: ${RED}None or negative${NC}"
fi

if [ $(echo "$DETECTION_IMPROVEMENT > 20" | bc) -eq 1 ]; then
    echo -e "  ${GREEN}✓✓✓${NC} Detection improvement: ${GREEN}Excellent${NC} (+$DETECTION_IMPROVEMENT%)"
    OVERALL_SCORE=$((OVERALL_SCORE + 3))
elif [ $(echo "$DETECTION_IMPROVEMENT > 10" | bc) -eq 1 ]; then
    echo -e "  ${GREEN}✓✓${NC} Detection improvement: ${GREEN}Good${NC} (+$DETECTION_IMPROVEMENT%)"
    OVERALL_SCORE=$((OVERALL_SCORE + 2))
elif [ $(echo "$DETECTION_IMPROVEMENT > 0" | bc) -eq 1 ]; then
    echo -e "  ${YELLOW}✓${NC} Detection improvement: ${YELLOW}Moderate${NC} (+$DETECTION_IMPROVEMENT%)"
    OVERALL_SCORE=$((OVERALL_SCORE + 1))
else
    echo -e "  ${RED}✗${NC} Detection improvement: ${RED}None or negative${NC}"
fi

echo ""
echo -e "${MAGENTA}Overall Hardening Effectiveness:${NC}"
if [ $OVERALL_SCORE -ge 5 ]; then
    echo -e "  ${GREEN}★★★★★${NC} Excellent (Score: $OVERALL_SCORE/6)"
elif [ $OVERALL_SCORE -ge 3 ]; then
    echo -e "  ${GREEN}★★★★☆${NC} Good (Score: $OVERALL_SCORE/6)"
elif [ $OVERALL_SCORE -ge 2 ]; then
    echo -e "  ${YELLOW}★★★☆☆${NC} Moderate (Score: $OVERALL_SCORE/6)"
else
    echo -e "  ${RED}★★☆☆☆${NC} Limited (Score: $OVERALL_SCORE/6)"
fi

# Save comparison report
COMPARISON_FILE="$PROJECT_ROOT/llfi_experiments/comparison_${ORIGINAL}_vs_${HARDENED}.json"
cat > "$COMPARISON_FILE" << EOF
{
  "comparison_date": "$(date -Iseconds)",
  "original": {
    "program": "$ORIGINAL",
    "trials": $ORIG_TRIALS,
    "sdc": $ORIG_SDC,
    "sdc_rate": $ORIG_SDC_RATE,
    "detected": $ORIG_DETECTED,
    "detection_rate": $ORIG_DETECTION_RATE
  },
  "hardened": {
    "program": "$HARDENED",
    "trials": $HARD_TRIALS,
    "sdc": $HARD_SDC,
    "sdc_rate": $HARD_SDC_RATE,
    "detected": $HARD_DETECTED,
    "detection_rate": $HARD_DETECTION_RATE
  },
  "improvements": {
    "sdc_reduction_percent": $SDC_REDUCTION,
    "detection_improvement_percent": $DETECTION_IMPROVEMENT,
    "effectiveness_score": $OVERALL_SCORE
  }
}
EOF

echo ""
echo "Comparison report saved to:"
echo "  $COMPARISON_FILE"
echo ""

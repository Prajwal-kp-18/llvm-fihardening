#!/bin/bash
#
# llfi-analyze.sh - Analyze fault injection results
# Usage: ./llfi-analyze.sh <program_name>
#
# This script analyzes all fault injection campaigns for a program
# and generates a comprehensive report.
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
NC='\033[0m' # No Color

if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Missing argument${NC}"
    echo "Usage: $0 <program_name>"
    echo ""
    echo "Example:"
    echo "  $0 test_advanced_hardening"
    echo "  $0 test_advanced_hardening_hardened"
    exit 1
fi

PROGRAM_NAME="$1"
EXPERIMENT_DIR="$PROJECT_ROOT/llfi_experiments/$PROGRAM_NAME"

if [ ! -d "$EXPERIMENT_DIR" ]; then
    echo -e "${RED}Error: Experiment directory not found: $EXPERIMENT_DIR${NC}"
    exit 1
fi

if [ ! -d "$EXPERIMENT_DIR/fi_results" ] || [ -z "$(ls -A "$EXPERIMENT_DIR/fi_results" 2>/dev/null)" ]; then
    echo -e "${RED}Error: No fault injection results found${NC}"
    echo "Run ./llfi-run.sh first to generate results"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  LLFI Results Analysis${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Program: ${GREEN}$PROGRAM_NAME${NC}"
echo ""

# Find all result directories
RESULT_DIRS=$(find "$EXPERIMENT_DIR/fi_results" -type d -name "run_*" | sort)
NUM_RUNS=$(echo "$RESULT_DIRS" | wc -l)

echo -e "Found ${GREEN}$NUM_RUNS${NC} fault injection run(s)"
echo ""

# Aggregate statistics across all runs
TOTAL_TRIALS=0
TOTAL_SUCCESS=0
TOTAL_FAILED=0
TOTAL_TIMEOUT=0
TOTAL_SDC=0
TOTAL_DETECTED=0

RUN_NUM=1
for RUN_DIR in $RESULT_DIRS; do
    if [ -f "$RUN_DIR/summary.json" ]; then
        echo -e "${YELLOW}Run $RUN_NUM:${NC} $(basename $RUN_DIR)"
        
        # Parse JSON summary
        TRIALS=$(jq -r '.trials' "$RUN_DIR/summary.json" 2>/dev/null || echo "0")
        SUCCESS=$(jq -r '.results.successful' "$RUN_DIR/summary.json" 2>/dev/null || echo "0")
        FAILED=$(jq -r '.results.failed' "$RUN_DIR/summary.json" 2>/dev/null || echo "0")
        TIMEOUT=$(jq -r '.results.timeout' "$RUN_DIR/summary.json" 2>/dev/null || echo "0")
        SDC=$(jq -r '.results.sdc' "$RUN_DIR/summary.json" 2>/dev/null || echo "0")
        DETECTED=$(jq -r '.results.detected' "$RUN_DIR/summary.json" 2>/dev/null || echo "0")
        
        echo "  Trials: $TRIALS | Success: $SUCCESS | Failed: $FAILED | Timeout: $TIMEOUT | SDC: $SDC | Detected: $DETECTED"
        
        TOTAL_TRIALS=$((TOTAL_TRIALS + TRIALS))
        TOTAL_SUCCESS=$((TOTAL_SUCCESS + SUCCESS))
        TOTAL_FAILED=$((TOTAL_FAILED + FAILED))
        TOTAL_TIMEOUT=$((TOTAL_TIMEOUT + TIMEOUT))
        TOTAL_SDC=$((TOTAL_SDC + SDC))
        TOTAL_DETECTED=$((TOTAL_DETECTED + DETECTED))
        
        RUN_NUM=$((RUN_NUM + 1))
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Aggregate Statistics${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ $TOTAL_TRIALS -gt 0 ]; then
    SUCCESS_RATE=$(echo "scale=2; $TOTAL_SUCCESS * 100 / $TOTAL_TRIALS" | bc)
    FAIL_RATE=$(echo "scale=2; $TOTAL_FAILED * 100 / $TOTAL_TRIALS" | bc)
    TIMEOUT_RATE=$(echo "scale=2; $TOTAL_TIMEOUT * 100 / $TOTAL_TRIALS" | bc)
    SDC_RATE=$(echo "scale=2; $TOTAL_SDC * 100 / $TOTAL_TRIALS" | bc)
    DETECTION_RATE=$(echo "scale=2; $TOTAL_DETECTED * 100 / $TOTAL_TRIALS" | bc)
    
    echo "Total Trials:      $TOTAL_TRIALS"
    echo ""
    echo "Results:"
    echo "  ✓ Successful:    $TOTAL_SUCCESS ($SUCCESS_RATE%)"
    echo "  ✗ Failed:        $TOTAL_FAILED ($FAIL_RATE%)"
    echo "  ⏱ Timeout:       $TOTAL_TIMEOUT ($TIMEOUT_RATE%)"
    echo "  ⚠ SDC:           $TOTAL_SDC ($SDC_RATE%)"
    echo "  🛡 Detected:      $TOTAL_DETECTED ($DETECTION_RATE%)"
    echo ""
    
    # Interpretation
    echo -e "${CYAN}Interpretation:${NC}"
    if [ $(echo "$SDC_RATE < 5" | bc) -eq 1 ]; then
        echo "  ✓ SDC rate is low ($SDC_RATE%) - Good fault tolerance"
    elif [ $(echo "$SDC_RATE < 20" | bc) -eq 1 ]; then
        echo "  ⚠ SDC rate is moderate ($SDC_RATE%) - Consider more hardening"
    else
        echo "  ✗ SDC rate is high ($SDC_RATE%) - Significant vulnerability"
    fi
    
    if [ $(echo "$DETECTION_RATE > 80" | bc) -eq 1 ]; then
        echo "  ✓ Detection rate is excellent ($DETECTION_RATE%)"
    elif [ $(echo "$DETECTION_RATE > 50" | bc) -eq 1 ]; then
        echo "  ⚠ Detection rate is good ($DETECTION_RATE%)"
    else
        echo "  ⚠ Detection rate is low ($DETECTION_RATE%) - May need stronger checks"
    fi
    
    # Save aggregate report
    REPORT_FILE="$EXPERIMENT_DIR/fi_results/aggregate_report.json"
    cat > "$REPORT_FILE" << EOF
{
  "program": "$PROGRAM_NAME",
  "analysis_date": "$(date -Iseconds)",
  "num_runs": $NUM_RUNS,
  "total_trials": $TOTAL_TRIALS,
  "aggregate_results": {
    "successful": $TOTAL_SUCCESS,
    "failed": $TOTAL_FAILED,
    "timeout": $TOTAL_TIMEOUT,
    "sdc": $TOTAL_SDC,
    "detected": $TOTAL_DETECTED
  },
  "aggregate_rates": {
    "success": $SUCCESS_RATE,
    "failure": $FAIL_RATE,
    "timeout": $TIMEOUT_RATE,
    "sdc": $SDC_RATE,
    "detection": $DETECTION_RATE
  }
}
EOF
    
    echo ""
    echo "Aggregate report saved to:"
    echo "  $REPORT_FILE"
else
    echo "No trials found in result directories"
fi

echo ""

# Show SDC examples if any
if [ $TOTAL_SDC -gt 0 ]; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  SDC Examples (first 5)${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    
    SDC_COUNT=0
    for RUN_DIR in $RESULT_DIRS; do
        SDC_TRIALS=$(find "$RUN_DIR" -name "status.txt" -exec grep -l "SDC" {} \; 2>/dev/null | head -5)
        for TRIAL_FILE in $SDC_TRIALS; do
            if [ $SDC_COUNT -lt 5 ]; then
                TRIAL_DIR=$(dirname "$TRIAL_FILE")
                TRIAL_NAME=$(basename "$TRIAL_DIR")
                echo "Trial: $TRIAL_NAME"
                echo "  Output diff:"
                diff "$RUN_DIR/baseline_output.txt" "$TRIAL_DIR/output.txt" 2>/dev/null | head -10 || echo "  (diff unavailable)"
                echo ""
                SDC_COUNT=$((SDC_COUNT + 1))
            fi
        done
    done
fi

echo -e "${GREEN}Analysis complete!${NC}"
echo ""

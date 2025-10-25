#!/bin/bash
#
# llfi-run.sh - Run fault injection campaign
# Usage: ./llfi-run.sh <program_name> <num_trials>
#
# This script runs multiple fault injection trials on an instrumented program
# and collects results for analysis.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ $# -ne 2 ]; then
    echo -e "${RED}Error: Missing arguments${NC}"
    echo "Usage: $0 <program_name> <num_trials>"
    echo ""
    echo "Example:"
    echo "  $0 test_advanced_hardening 1000"
    echo "  $0 test_advanced_hardening_hardened 1000"
    exit 1
fi

PROGRAM_NAME="$1"
NUM_TRIALS="$2"
EXPERIMENT_DIR="$PROJECT_ROOT/llfi_experiments/$PROGRAM_NAME"

if [ ! -d "$EXPERIMENT_DIR" ]; then
    echo -e "${RED}Error: Experiment directory not found: $EXPERIMENT_DIR${NC}"
    echo "Run ./LLFI-build.sh first to prepare the program"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  LLFI Fault Injection Campaign${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Program:    ${GREEN}$PROGRAM_NAME${NC}"
echo -e "Trials:     ${GREEN}$NUM_TRIALS${NC}"
echo -e "Output:     ${GREEN}$EXPERIMENT_DIR/fi_results/${NC}"
echo ""

# Create results directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="$EXPERIMENT_DIR/fi_results/run_${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

# Run baseline first for comparison
echo -e "${YELLOW}[0/$NUM_TRIALS]${NC} Running baseline (no faults)..."
cd "$EXPERIMENT_DIR"

if timeout 5s ./baseline/program > "$RESULTS_DIR/baseline_output.txt" 2>&1; then
    BASELINE_EXIT=$?
    echo -e "  ${GREEN}✓${NC} Baseline completed (exit: $BASELINE_EXIT)"
else
    BASELINE_EXIT=$?
    echo -e "  ${YELLOW}⚠${NC} Baseline timed out or failed (exit: $BASELINE_EXIT)"
fi

# Initialize counters
SUCCESSFUL=0
FAILED=0
TIMEOUT=0
SDC=0  # Silent Data Corruption
DETECTED=0  # Error detected by hardening

echo ""
echo -e "${YELLOW}Running $NUM_TRIALS fault injection trials...${NC}"
echo ""

# Run trials
for i in $(seq 1 $NUM_TRIALS); do
    TRIAL_DIR="$RESULTS_DIR/trial_$(printf "%04d" $i)"
    mkdir -p "$TRIAL_DIR"
    
    # Progress indicator
    if [ $((i % 10)) -eq 0 ]; then
        echo -e "${BLUE}[$i/$NUM_TRIALS]${NC} Progress: $SUCCESSFUL OK, $FAILED FAIL, $TIMEOUT TIMEOUT, $SDC SDC, $DETECTED DETECTED"
    fi
    
    # Run with random seed for different fault injection
    export LLFI_SEED=$i
    
    # Run instrumented program with timeout
    if timeout 5s ./llfi/program_instrumented > "$TRIAL_DIR/output.txt" 2>&1; then
        EXIT_CODE=$?
        
        # Compare output with baseline
        if diff -q "$RESULTS_DIR/baseline_output.txt" "$TRIAL_DIR/output.txt" > /dev/null 2>&1; then
            # Output matches - fault was masked or detected
            if grep -q "MISMATCH" "$TRIAL_DIR/output.txt" 2>/dev/null || \
               grep -q "verification failed" "$TRIAL_DIR/output.txt" 2>/dev/null || \
               grep -q "ERROR" "$TRIAL_DIR/output.txt" 2>/dev/null; then
                DETECTED=$((DETECTED + 1))
                echo "DETECTED" > "$TRIAL_DIR/status.txt"
            else
                SUCCESSFUL=$((SUCCESSFUL + 1))
                echo "SUCCESS" > "$TRIAL_DIR/status.txt"
            fi
        else
            # Output differs - potential SDC
            SDC=$((SDC + 1))
            echo "SDC" > "$TRIAL_DIR/status.txt"
        fi
        
        echo "$EXIT_CODE" > "$TRIAL_DIR/exit_code.txt"
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            TIMEOUT=$((TIMEOUT + 1))
            echo "TIMEOUT" > "$TRIAL_DIR/status.txt"
        else
            FAILED=$((FAILED + 1))
            echo "FAILED" > "$TRIAL_DIR/status.txt"
        fi
        echo "$EXIT_CODE" > "$TRIAL_DIR/exit_code.txt"
    fi
done

# Calculate statistics
TOTAL=$NUM_TRIALS
SUCCESS_RATE=$(echo "scale=2; $SUCCESSFUL * 100 / $TOTAL" | bc)
FAIL_RATE=$(echo "scale=2; $FAILED * 100 / $TOTAL" | bc)
TIMEOUT_RATE=$(echo "scale=2; $TIMEOUT * 100 / $TOTAL" | bc)
SDC_RATE=$(echo "scale=2; $SDC * 100 / $TOTAL" | bc)
DETECTION_RATE=$(echo "scale=2; $DETECTED * 100 / $TOTAL" | bc)

# Save summary
cat > "$RESULTS_DIR/summary.json" << EOF
{
  "program": "$PROGRAM_NAME",
  "timestamp": "$TIMESTAMP",
  "trials": $TOTAL,
  "results": {
    "successful": $SUCCESSFUL,
    "failed": $FAILED,
    "timeout": $TIMEOUT,
    "sdc": $SDC,
    "detected": $DETECTED
  },
  "rates": {
    "success": $SUCCESS_RATE,
    "failure": $FAIL_RATE,
    "timeout": $TIMEOUT_RATE,
    "sdc": $SDC_RATE,
    "detection": $DETECTION_RATE
  }
}
EOF

# Print summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Fault Injection Campaign Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Results Summary:"
echo "  Total Trials:     $TOTAL"
echo ""
echo "  ✓ Successful:     $SUCCESSFUL ($SUCCESS_RATE%)"
echo "  ✗ Failed:         $FAILED ($FAIL_RATE%)"
echo "  ⏱ Timeout:        $TIMEOUT ($TIMEOUT_RATE%)"
echo "  ⚠ SDC:            $SDC ($SDC_RATE%)"
echo "  🛡 Detected:       $DETECTED ($DETECTION_RATE%)"
echo ""
echo "Results saved to:"
echo "  $RESULTS_DIR/"
echo ""
echo "Next steps:"
echo "  - Analyze results: ./scripts/llfi-analyze.sh $PROGRAM_NAME"
echo "  - View summary:    cat $RESULTS_DIR/summary.json"
echo ""

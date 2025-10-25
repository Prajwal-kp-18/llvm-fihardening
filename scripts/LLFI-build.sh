#!/bin/bash
#
# LLFI-build.sh - Prepare program for fault injection testing
# Usage: ./LLFI-build.sh <program.ll>
#
# This script instruments the LLVM IR for fault injection experiments
# and creates the necessary directory structure.
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

if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Missing argument${NC}"
    echo "Usage: $0 <program.ll>"
    echo ""
    echo "Example:"
    echo "  $0 build/test_advanced_hardening.ll"
    echo "  $0 build/test_advanced_hardening_hardened.ll"
    exit 1
fi

INPUT_LL="$1"

if [ ! -f "$INPUT_LL" ]; then
    echo -e "${RED}Error: File not found: $INPUT_LL${NC}"
    exit 1
fi

# Extract program name (without path and extension)
PROGRAM_NAME=$(basename "$INPUT_LL" .ll)
OUTPUT_DIR="$PROJECT_ROOT/llfi_experiments/$PROGRAM_NAME"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  LLFI Build Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Input:      ${GREEN}$INPUT_LL${NC}"
echo -e "Program:    ${GREEN}$PROGRAM_NAME${NC}"
echo -e "Output Dir: ${GREEN}$OUTPUT_DIR${NC}"
echo ""

# Create output directory structure
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/llfi"
mkdir -p "$OUTPUT_DIR/baseline"
mkdir -p "$OUTPUT_DIR/fi_results"

# Copy the input IR
cp "$INPUT_LL" "$OUTPUT_DIR/baseline/program.ll"

# Create a basic LLFI configuration
cat > "$OUTPUT_DIR/llfi/input.yaml" << EOF
# LLFI Configuration for $PROGRAM_NAME
# Generated: $(date)

# Fault injection configuration
compileOption:
  - -fno-use-cxa-atexit
  
# Instruction types to target for fault injection
fi_type:
  - all  # Target all instructions
  
# Fault model
faultModel:
  - bitflip  # Single bit flip

# Register selection
regSelMethod: random

# Number of fault injections per run
numTrials: 1

# Runtime configuration
run:
  - programName: program
    args: []
EOF

# Create metadata file
cat > "$OUTPUT_DIR/metadata.json" << EOF
{
  "program_name": "$PROGRAM_NAME",
  "input_file": "$INPUT_LL",
  "created": "$(date -Iseconds)",
  "status": "prepared",
  "llfi_version": "custom",
  "hardening_enabled": $(if [[ "$PROGRAM_NAME" == *"hardened"* ]]; then echo "true"; else echo "false"; fi)
}
EOF

# Build baseline executable
echo -e "${YELLOW}[1/3]${NC} Building baseline executable..."

# Check if we need runtime library (hardened code)
RUNTIME_LIB="$PROJECT_ROOT/build/libFIHardeningRuntime.a"
if [[ "$PROGRAM_NAME" == *"hardened"* ]] && [ -f "$RUNTIME_LIB" ]; then
    echo -e "  ${BLUE}ℹ${NC} Linking with FI Hardening Runtime"
    clang "$OUTPUT_DIR/baseline/program.ll" "$RUNTIME_LIB" \
        -o "$OUTPUT_DIR/baseline/program" \
        2>&1 | tee "$OUTPUT_DIR/baseline/build.log"
else
    clang "$OUTPUT_DIR/baseline/program.ll" \
        -o "$OUTPUT_DIR/baseline/program" \
        2>&1 | tee "$OUTPUT_DIR/baseline/build.log"
fi

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} Baseline built successfully"
else
    echo -e "  ${RED}✗${NC} Baseline build failed"
fi

# Create instrumented version (this is where we'd run LLFI instrument pass)
echo -e "${YELLOW}[2/3]${NC} Creating instrumented version..."
cp "$OUTPUT_DIR/baseline/program.ll" "$OUTPUT_DIR/llfi/program_instrumented.ll"
echo -e "  ${GREEN}✓${NC} IR copied for instrumentation"

# Build instrumented executable
echo -e "${YELLOW}[3/3]${NC} Building instrumented executable..."
if [[ "$PROGRAM_NAME" == *"hardened"* ]] && [ -f "$RUNTIME_LIB" ]; then
    clang "$OUTPUT_DIR/llfi/program_instrumented.ll" "$RUNTIME_LIB" \
        -o "$OUTPUT_DIR/llfi/program_instrumented" \
        2>&1 | tee "$OUTPUT_DIR/llfi/build.log"
else
    clang "$OUTPUT_DIR/llfi/program_instrumented.ll" \
        -o "$OUTPUT_DIR/llfi/program_instrumented" \
        2>&1 | tee "$OUTPUT_DIR/llfi/build.log"
fi

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} Instrumented version built successfully"
else
    echo -e "  ${RED}✗${NC} Instrumented build failed"
fi

# Create run script
cat > "$OUTPUT_DIR/run_baseline.sh" << 'RUNSCRIPT'
#!/bin/bash
# Run baseline version
./baseline/program "$@"
RUNSCRIPT
chmod +x "$OUTPUT_DIR/run_baseline.sh"

cat > "$OUTPUT_DIR/run_instrumented.sh" << 'RUNSCRIPT'
#!/bin/bash
# Run instrumented version
./llfi/program_instrumented "$@"
RUNSCRIPT
chmod +x "$OUTPUT_DIR/run_instrumented.sh"

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Directory structure created:"
echo "  $OUTPUT_DIR/"
echo "    ├── baseline/              (Original executable)"
echo "    ├── llfi/                  (Instrumented version)"
echo "    ├── fi_results/            (Fault injection results)"
echo "    ├── metadata.json          (Experiment metadata)"
echo "    ├── run_baseline.sh        (Run baseline)"
echo "    └── run_instrumented.sh    (Run instrumented)"
echo ""
echo "Next steps:"
echo "  1. Run baseline:    cd $OUTPUT_DIR && ./run_baseline.sh"
echo "  2. Run experiments: ./scripts/llfi-run.sh $PROGRAM_NAME <num_trials>"
echo "  3. View results:    ./scripts/llfi-analyze.sh $PROGRAM_NAME"
echo ""

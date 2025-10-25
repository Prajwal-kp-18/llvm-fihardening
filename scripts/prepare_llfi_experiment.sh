#!/bin/bash

# Prepare LLFI fault injection experiments
# This script sets up both original and hardened versions for LLFI testing

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LLFI_ROOT="$PROJECT_ROOT/benchmarks/LLFI"
INTEGRATION_DIR="$PROJECT_ROOT/llfi_integration"
EXPERIMENTS_DIR="$INTEGRATION_DIR/experiments"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <program_name> [num_runs]"
    echo ""
    echo "Arguments:"
    echo "  program_name  - Name of the program to test (e.g., factorial)"
    echo "  num_runs      - Number of fault injection runs (default: 100)"
    echo ""
    echo "Example: $0 factorial 100"
    echo ""
    echo "This script prepares LLFI experiments for both original"
    echo "and hardened versions of a program."
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

PROGRAM_NAME=$1
NUM_RUNS=${2:-100}

# Check LLFI is available
if [ ! -d "$LLFI_ROOT" ] || [ ! -f "$LLFI_ROOT/bin/instrument" ]; then
    echo -e "${RED}Error: LLFI not found or not properly installed${NC}"
    echo "Please ensure LLFI is built in: $LLFI_ROOT"
    exit 1
fi

# Create experiment directory
EXPERIMENT_DIR="$EXPERIMENTS_DIR/$PROGRAM_NAME"
mkdir -p "$EXPERIMENT_DIR"/{original,hardened}

echo -e "${BLUE}=== Preparing LLFI Experiment for $PROGRAM_NAME ===${NC}"
echo ""

# Check for original and hardened files
ORIGINAL_C="$INTEGRATION_DIR/original/${PROGRAM_NAME}.c"
HARDENED_C="$INTEGRATION_DIR/hardened/${PROGRAM_NAME}_hardened.c"

if [ ! -f "$ORIGINAL_C" ]; then
    echo -e "${RED}Error: Original file not found: $ORIGINAL_C${NC}"
    exit 1
fi

if [ ! -f "$HARDENED_C" ]; then
    echo -e "${YELLOW}Warning: Hardened file not found: $HARDENED_C${NC}"
    echo "Proceeding with original version only."
    SKIP_HARDENED=true
fi

# Create LLFI configuration
create_llfi_config() {
    local output_file=$1
    cat > "$output_file" << EOF
compileOption:
    instSelMethod:
      - insttype:
          include:
            - all
          exclude:
            - ret
            - call

    regSelMethod: regloc
    regloc: dstreg

    includeInjectionTrace:
        - forward
        - backward

    tracingPropagation: True
    
    tracingPropagationOption:
        maxTrace: 250
        debugTrace: False
        generateCDFG: True

runOption:
    - run:
        numOfRuns: $NUM_RUNS
        fi_type: bitflip
EOF
}

# Prepare original version
echo -e "${YELLOW}Preparing original version...${NC}"
cd "$EXPERIMENT_DIR/original"

# Copy source
cp "$ORIGINAL_C" "${PROGRAM_NAME}.c"

# Generate IR
echo "  Generating LLVM IR..."
clang -S -emit-llvm -o "${PROGRAM_NAME}.ll" "${PROGRAM_NAME}.c"

# Create LLFI config
echo "  Creating LLFI configuration..."
create_llfi_config "input.yaml"

# Instrument
echo "  Instrumenting with LLFI..."
if "$LLFI_ROOT/bin/instrument" --readable "${PROGRAM_NAME}.ll"; then
    echo -e "${GREEN}  ✓ Original version ready${NC}"
else
    echo -e "${RED}  Failed to instrument original version${NC}"
    exit 1
fi

echo ""

# Prepare hardened version (if exists)
if [ "$SKIP_HARDENED" != "true" ]; then
    echo -e "${YELLOW}Preparing hardened version...${NC}"
    cd "$EXPERIMENT_DIR/hardened"
    
    # Copy source
    cp "$HARDENED_C" "${PROGRAM_NAME}_hardened.c"
    
    # Generate IR
    echo "  Generating LLVM IR..."
    clang -S -emit-llvm -o "${PROGRAM_NAME}_hardened.ll" "${PROGRAM_NAME}_hardened.c"
    
    # Create LLFI config
    echo "  Creating LLFI configuration..."
    create_llfi_config "input.yaml"
    
    # Instrument
    echo "  Instrumenting with LLFI..."
    if "$LLFI_ROOT/bin/instrument" --readable "${PROGRAM_NAME}_hardened.ll"; then
        echo -e "${GREEN}  ✓ Hardened version ready${NC}"
    else
        echo -e "${RED}  Failed to instrument hardened version${NC}"
        exit 1
    fi
    
    echo ""
fi

# Create run script
RUN_SCRIPT="$EXPERIMENT_DIR/run_experiment.sh"
cat > "$RUN_SCRIPT" << 'EOF'
#!/bin/bash

# Run LLFI fault injection experiment
# This script executes fault injection campaigns and collects statistics

set -e

EXPERIMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRAM_NAME="$(basename "$EXPERIMENT_DIR")"
LLFI_ROOT="$(cd "$EXPERIMENT_DIR/../../.." && pwd)/benchmarks/LLFI"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

run_injection() {
    local version=$1
    local version_dir="$EXPERIMENT_DIR/$version"
    
    echo -e "${BLUE}=== Running LLFI on $version version ===${NC}"
    echo ""
    
    cd "$version_dir"
    
    # Check if already profiled
    if [ ! -d "llfi" ]; then
        echo -e "${RED}Error: LLFI instrumentation not found${NC}"
        echo "Run prepare_llfi_experiment.sh first"
        return 1
    fi
    
    # Profile (if not already done)
    if [ ! -f "llfi/llfi.stat.prof.txt" ]; then
        echo -e "${YELLOW}Profiling...${NC}"
        # Note: Add your program arguments here
        "$LLFI_ROOT/bin/profile" ./llfi/*-profiling.exe
        echo -e "${GREEN}✓ Profiling complete${NC}"
        echo ""
    fi
    
    # Inject faults
    echo -e "${YELLOW}Injecting faults...${NC}"
    # Note: Add your program arguments here
    "$LLFI_ROOT/bin/injectfault" ./llfi/*-faultinjection.exe
    
    echo -e "${GREEN}✓ Fault injection complete${NC}"
    echo ""
    
    # Collect statistics
    if [ -d "llfi/llfi_stat_output" ]; then
        echo -e "${BLUE}Results for $version version:${NC}"
        cat llfi/llfi_stat_output/llfi.stat.totalfi.txt
        echo ""
    fi
}

# Run on original
if [ -d "$EXPERIMENT_DIR/original" ]; then
    run_injection "original"
fi

# Run on hardened
if [ -d "$EXPERIMENT_DIR/hardened" ]; then
    run_injection "hardened"
fi

# Compare results
echo -e "${BLUE}=== Comparison ===${NC}"
echo ""

if [ -f "$EXPERIMENT_DIR/original/llfi/llfi_stat_output/llfi.stat.totalfi.txt" ] && \
   [ -f "$EXPERIMENT_DIR/hardened/llfi/llfi_stat_output/llfi.stat.totalfi.txt" ]; then
    
    echo "Original version:"
    grep -E "(Crash|Hang|SDC)" "$EXPERIMENT_DIR/original/llfi/llfi_stat_output/llfi.stat.totalfi.txt" || true
    echo ""
    
    echo "Hardened version:"
    grep -E "(Crash|Hang|SDC)" "$EXPERIMENT_DIR/hardened/llfi/llfi_stat_output/llfi.stat.totalfi.txt" || true
    echo ""
    
    # Calculate improvement
    original_crashes=$(grep "Crash" "$EXPERIMENT_DIR/original/llfi/llfi_stat_output/llfi.stat.totalfi.txt" | awk '{print $2}' || echo "0")
    hardened_crashes=$(grep "Crash" "$EXPERIMENT_DIR/hardened/llfi/llfi_stat_output/llfi.stat.totalfi.txt" | awk '{print $2}' || echo "0")
    
    if [ "$original_crashes" -gt 0 ]; then
        reduction=$((original_crashes - hardened_crashes))
        percent=$(echo "scale=2; $reduction * 100 / $original_crashes" | bc 2>/dev/null || echo "N/A")
        echo -e "${GREEN}Crash reduction: $reduction ($percent%)${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Experiment complete!${NC}"
echo "Results saved in: $EXPERIMENT_DIR/*/llfi/llfi_stat_output/"
EOF

chmod +x "$RUN_SCRIPT"

# Summary
echo -e "${GREEN}=== Experiment Preparation Complete ===${NC}"
echo ""
echo "Experiment directory: $EXPERIMENT_DIR"
echo ""
echo "Structure:"
echo "  $EXPERIMENT_DIR/"
echo "  ├── original/"
echo "  │   ├── ${PROGRAM_NAME}.c"
echo "  │   ├── ${PROGRAM_NAME}.ll"
echo "  │   ├── input.yaml"
echo "  │   └── llfi/ (instrumented)"
if [ "$SKIP_HARDENED" != "true" ]; then
    echo "  ├── hardened/"
    echo "  │   ├── ${PROGRAM_NAME}_hardened.c"
    echo "  │   ├── ${PROGRAM_NAME}_hardened.ll"
    echo "  │   ├── input.yaml"
    echo "  │   └── llfi/ (instrumented)"
fi
echo "  └── run_experiment.sh"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Review and update input.yaml if needed"
echo "  2. Edit run_experiment.sh to add program arguments"
echo "  3. Run: cd $EXPERIMENT_DIR && ./run_experiment.sh"
echo "  4. Analyze results in llfi_stat_output/ directories"
echo ""
echo -e "${YELLOW}Note:${NC} Make sure to provide correct program arguments in run_experiment.sh"

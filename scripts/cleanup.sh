#!/bin/bash

# Cleanup script for FIHardeningPass
# Removes all generated files from tests, analysis, and experiments

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
CLEAN_ALL=false
CLEAN_TESTS=false
CLEAN_LLFI=false
CLEAN_BUILD=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Clean up generated files from FIHardeningPass runs"
    echo ""
    echo "Options:"
    echo "  --all          Clean everything (tests, LLFI, build)"
    echo "  --tests        Clean only test results"
    echo "  --llfi         Clean only LLFI integration results"
    echo "  --build        Clean only build artifacts"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "If no options are provided, cleans tests and LLFI results (not build)"
    echo ""
    echo "Examples:"
    echo "  $0                # Clean tests and LLFI results"
    echo "  $0 --all          # Clean everything including build"
    echo "  $0 --tests        # Clean only test results"
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    # Default: clean tests and LLFI, but not build
    CLEAN_TESTS=true
    CLEAN_LLFI=true
else
    while [ $# -gt 0 ]; do
        case "$1" in
            --all)
                CLEAN_ALL=true
                ;;
            --tests)
                CLEAN_TESTS=true
                ;;
            --llfi)
                CLEAN_LLFI=true
                ;;
            --build)
                CLEAN_BUILD=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                exit 1
                ;;
        esac
        shift
    done
fi

# If --all is specified, enable everything
if [ "$CLEAN_ALL" = true ]; then
    CLEAN_TESTS=true
    CLEAN_LLFI=true
    CLEAN_BUILD=true
fi

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        FIHardeningPass Cleanup Script                   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to remove directory if it exists
remove_dir() {
    local dir=$1
    local description=$2
    
    if [ -d "$dir" ]; then
        local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "?")
        echo -e "${YELLOW}  Removing $description ($size)${NC}"
        rm -rf "$dir"
        echo -e "${GREEN}  ✓ Removed${NC}"
    else
        echo -e "${BLUE}  ℹ $description not found (already clean)${NC}"
    fi
}

# Function to remove file if it exists
remove_file() {
    local file=$1
    local description=$2
    
    if [ -f "$file" ]; then
        echo -e "${YELLOW}  Removing $description${NC}"
        rm -f "$file"
        echo -e "${GREEN}  ✓ Removed${NC}"
    fi
}

# Function to remove files matching pattern
remove_pattern() {
    local pattern=$1
    local description=$2
    
    local files=$(find . -name "$pattern" 2>/dev/null | wc -l)
    if [ "$files" -gt 0 ]; then
        echo -e "${YELLOW}  Removing $files $description${NC}"
        find . -name "$pattern" -type f -delete
        echo -e "${GREEN}  ✓ Removed${NC}"
    fi
}

# Clean test results
if [ "$CLEAN_TESTS" = true ]; then
    echo -e "${BLUE}[1] Cleaning test results...${NC}"
    
    # Test results directory
    remove_dir "test_results" "test results directory"
    
    # Generated .ll files in tests/
    if [ -d "tests" ]; then
        ll_files=$(find tests -name "*.ll" 2>/dev/null | wc -l)
        if [ "$ll_files" -gt 0 ]; then
            echo -e "${YELLOW}  Removing $ll_files .ll files from tests/${NC}"
            find tests -name "*.ll" -type f -delete
            echo -e "${GREEN}  ✓ Removed${NC}"
        fi
    fi
    
    # Generated .ll files in examples/
    if [ -d "examples" ]; then
        ll_files=$(find examples -name "*.ll" 2>/dev/null | wc -l)
        if [ "$ll_files" -gt 0 ]; then
            echo -e "${YELLOW}  Removing $ll_files .ll files from examples/${NC}"
            find examples -name "*.ll" -type f -delete
            echo -e "${GREEN}  ✓ Removed${NC}"
        fi
    fi
    
    # Temporary comparison files
    remove_file "vulnerable_output.txt" "vulnerable output"
    remove_file "hardened_output.txt" "hardened output"
    remove_file "comparison_results.txt" "comparison results"
    
    echo ""
fi

# Clean LLFI integration results
if [ "$CLEAN_LLFI" = true ]; then
    echo -e "${BLUE}[2] Cleaning LLFI integration results...${NC}"
    
    # LLFI results directory
    remove_dir "llfi_integration/results" "LLFI analysis results"
    
    # LLFI original/hardened copies
    if [ -d "llfi_integration/original" ]; then
        files=$(find llfi_integration/original -type f 2>/dev/null | wc -l)
        if [ "$files" -gt 0 ]; then
            echo -e "${YELLOW}  Removing $files files from llfi_integration/original/${NC}"
            rm -rf llfi_integration/original/*
            echo -e "${GREEN}  ✓ Removed${NC}"
        fi
    fi
    
    if [ -d "llfi_integration/hardened" ]; then
        files=$(find llfi_integration/hardened -type f 2>/dev/null | wc -l)
        if [ "$files" -gt 0 ]; then
            echo -e "${YELLOW}  Removing $files files from llfi_integration/hardened/${NC}"
            rm -rf llfi_integration/hardened/*
            echo -e "${GREEN}  ✓ Removed${NC}"
        fi
    fi
    
    # LLFI experiments
    remove_dir "llfi_integration/experiments" "LLFI experiment data"
    
    # LLFI generated files in benchmark directories
    if [ -d "benchmarks/LLFI/sample_programs" ]; then
        echo -e "${YELLOW}  Cleaning LLFI-generated files in sample_programs/${NC}"
        
        # Remove llfi/ directories
        find benchmarks/LLFI/sample_programs -type d -name "llfi" -exec rm -rf {} + 2>/dev/null || true
        
        # Remove profiling executables
        find benchmarks/LLFI/sample_programs -name "*-profiling.exe" -delete 2>/dev/null || true
        
        # Remove fault injection executables
        find benchmarks/LLFI/sample_programs -name "*-faultinjection.exe" -delete 2>/dev/null || true
        
        # Remove instrumented .ll files (but keep originals)
        find benchmarks/LLFI/sample_programs -name "*-llfi_index.ll" -delete 2>/dev/null || true
        find benchmarks/LLFI/sample_programs -name "*-profiling.ll" -delete 2>/dev/null || true
        find benchmarks/LLFI/sample_programs -name "*-faultinjection.ll" -delete 2>/dev/null || true
        
        echo -e "${GREEN}  ✓ Cleaned${NC}"
    fi
    
    echo ""
fi

# Clean build artifacts
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${BLUE}[3] Cleaning build artifacts...${NC}"
    
    remove_dir "build" "build directory"
    
    # CMake cache files
    remove_file "CMakeCache.txt" "CMake cache"
    remove_dir "CMakeFiles" "CMake files"
    
    # Other build artifacts
    remove_pattern "*.o" "object files"
    remove_pattern "*.so" "shared libraries (in root)"
    remove_pattern "*.a" "static libraries"
    
    echo ""
fi

# Summary
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Cleanup Complete!                          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Cleaned:"
if [ "$CLEAN_TESTS" = true ]; then
    echo -e "  ${GREEN}✓${NC} Test results"
fi
if [ "$CLEAN_LLFI" = true ]; then
    echo -e "  ${GREEN}✓${NC} LLFI integration results"
fi
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "  ${GREEN}✓${NC} Build artifacts"
fi
echo ""
echo "Preserved:"
if [ "$CLEAN_BUILD" = false ]; then
    echo -e "  ${BLUE}•${NC} Build directory (use --build to remove)"
fi
if [ "$CLEAN_TESTS" = false ]; then
    echo -e "  ${BLUE}•${NC} Test results (use --tests to remove)"
fi
if [ "$CLEAN_LLFI" = false ]; then
    echo -e "  ${BLUE}•${NC} LLFI results (use --llfi to remove)"
fi
echo -e "  ${BLUE}•${NC} Source code (.c, .cpp, .h files)"
echo -e "  ${BLUE}•${NC} Documentation (.md files)"
echo -e "  ${BLUE}•${NC} Scripts (.sh, .py files)"
echo -e "  ${BLUE}•${NC} Original LLFI benchmark suite"
echo ""

if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${YELLOW}Note: Build directory removed. Run 'mkdir build && cd build && cmake .. && make' to rebuild.${NC}"
    echo ""
fi

echo -e "${GREEN}Ready for a fresh start!${NC}"

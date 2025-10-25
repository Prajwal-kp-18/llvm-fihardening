#!/bin/bash
# Quick test script - test a single C file quickly

if [ $# -eq 0 ]; then
    echo "Usage: $0 <source.c>"
    echo "Example: $0 mycode.c"
    exit 1
fi

SOURCE_FILE=$1
BASE_NAME=$(basename "$SOURCE_FILE" .c)
PLUGIN="./build/FIHardeningPass.so"

if [ ! -f "$PLUGIN" ]; then
    echo "Error: Plugin not built. Run: cd build && cmake .. && make"
    exit 1
fi

echo "Analyzing: $SOURCE_FILE"
echo "=========================================="

# Compile to LLVM IR
clang -S -emit-llvm -o "${BASE_NAME}.ll" "$SOURCE_FILE"

# Run the pass
opt -load-pass-plugin="$PLUGIN" -passes="fi-harden" -disable-output "${BASE_NAME}.ll"

echo ""
echo "LLVM IR saved to: ${BASE_NAME}.ll"

#!/bin/bash
# Functional validation - ensure hardened code works correctly

echo "=========================================="
echo "Functional Validation Test"
echo "=========================================="
echo ""

# Compile both versions
echo "Compiling original version..."
gcc -o /tmp/new_orig examples/new.c 2>&1 | head -5
if [ $? -ne 0 ]; then
    echo "❌ Original compilation failed"
    exit 1
fi
echo "✓ Original compiled"

echo "Compiling hardened version..."
gcc -o /tmp/new_hard examples/new_hardened.c 2>&1 | head -5
if [ $? -ne 0 ]; then
    echo "❌ Hardened compilation failed"
    exit 1
fi
echo "✓ Hardened compiled"
echo ""

# Test cases
echo "=========================================="
echo "Test Cases"
echo "=========================================="
echo ""

passed=0
failed=0

# Test 1: Correct password
echo "Test 1: Correct password"
echo "----------------------------------------"
orig_out=$(/tmp/new_orig "secure123" 2>&1)
hard_out=$(/tmp/new_hard "secure123" 2>&1)

echo "Original: $orig_out"
echo "Hardened: $hard_out"

if echo "$orig_out" | grep -q "Access granted" && echo "$hard_out" | grep -q "Access granted"; then
    echo "✓ PASS - Both grant access"
    ((passed++))
else
    echo "❌ FAIL - Behavior differs"
    ((failed++))
fi
echo ""

# Test 2: Wrong password
echo "Test 2: Wrong password"
echo "----------------------------------------"
orig_out=$(/tmp/new_orig "wrong123" 2>&1)
hard_out=$(/tmp/new_hard "wrong123" 2>&1)

echo "Original: $orig_out"
echo "Hardened: $hard_out"

if echo "$orig_out" | grep -q "Access denied" && echo "$hard_out" | grep -q "Access denied"; then
    echo "✓ PASS - Both deny access"
    ((passed++))
else
    echo "❌ FAIL - Behavior differs"
    ((failed++))
fi
echo ""

# Test 3: Empty password
echo "Test 3: Empty password"
echo "----------------------------------------"
orig_out=$(/tmp/new_orig "" 2>&1)
hard_out=$(/tmp/new_hard "" 2>&1)

echo "Original: $orig_out"
echo "Hardened: $hard_out"

if echo "$orig_out" | grep -q "Access denied" && echo "$hard_out" | grep -q "Access denied"; then
    echo "✓ PASS - Both deny access"
    ((passed++))
else
    echo "❌ FAIL - Behavior differs"
    ((failed++))
fi
echo ""

# Test 4: Too short password
echo "Test 4: Short password"
echo "----------------------------------------"
orig_out=$(/tmp/new_orig "sec" 2>&1)
hard_out=$(/tmp/new_hard "sec" 2>&1)

echo "Original: $orig_out"
echo "Hardened: $hard_out"

if echo "$orig_out" | grep -q "Access denied" && echo "$hard_out" | grep -q "Access denied"; then
    echo "✓ PASS - Both deny access"
    ((passed++))
else
    echo "❌ FAIL - Behavior differs"
    ((failed++))
fi
echo ""

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo "Passed: $passed / $((passed + failed))"
echo "Failed: $failed / $((passed + failed))"
echo ""

if [ $failed -eq 0 ]; then
    echo "✅ All tests passed - hardened code is functionally equivalent"
    echo ""
    echo "Next steps:"
    echo "1. Review UNDERSTANDING_RESULTS.md for security improvements"
    echo "2. The hardened code has better fault injection protection"
    echo "3. Deploy hardened version for security-critical use"
    exit 0
else
    echo "❌ Some tests failed - review the differences"
    exit 1
fi

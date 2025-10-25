#!/bin/bash

# Quick verification that cleanup didn't break anything

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║         Post-Cleanup Verification                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

cd /home/prajwal/Documents/llvm-fihardening

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

# Check 1: Essential source files exist
echo "[1] Checking essential source files..."
for file in FIHardeningPass.cpp FIHardeningTransform.cpp FIHardeningRuntime.cpp FIHardeningRuntime.h CMakeLists.txt; do
    if [ -f "$file" ]; then
        echo -e "  ${GREEN}✓${NC} $file exists"
        ((PASS++))
    else
        echo -e "  ${RED}✗${NC} $file MISSING"
        ((FAIL++))
    fi
done

# Check 2: Essential documentation exists
echo ""
echo "[2] Checking essential documentation..."
for file in README.md MENTOR.md QUICK_REFERENCE.md DOCUMENTATION_INDEX.md; do
    if [ -f "$file" ]; then
        echo -e "  ${GREEN}✓${NC} $file exists"
        ((PASS++))
    else
        echo -e "  ${RED}✗${NC} $file MISSING"
        ((FAIL++))
    fi
done

# Check 3: Docs directory
echo ""
echo "[3] Checking docs/ directory..."
if [ -d "docs" ]; then
    DOC_COUNT=$(find docs -name "*.md" | wc -l)
    echo -e "  ${GREEN}✓${NC} docs/ directory exists with $DOC_COUNT files"
    ((PASS++))
else
    echo -e "  ${RED}✗${NC} docs/ directory MISSING"
    ((FAIL++))
fi

# Check 4: Essential test files
echo ""
echo "[4] Checking essential test files..."
if [ -f "tests/test_advanced_hardening.c" ]; then
    echo -e "  ${GREEN}✓${NC} test_advanced_hardening.c exists"
    ((PASS++))
else
    echo -e "  ${RED}✗${NC} test_advanced_hardening.c MISSING"
    ((FAIL++))
fi

if [ -f "tests/test_transform.c" ]; then
    echo -e "  ${GREEN}✓${NC} test_transform.c exists"
    ((PASS++))
else
    echo -e "  ${RED}✗${NC} test_transform.c MISSING"
    ((FAIL++))
fi

# Check 5: Essential scripts
echo ""
echo "[5] Checking essential scripts..."
SCRIPT_COUNT=$(ls -1 scripts/*.sh 2>/dev/null | wc -l)
if [ "$SCRIPT_COUNT" -ge 15 ]; then
    echo -e "  ${GREEN}✓${NC} Found $SCRIPT_COUNT scripts (expected 15+)"
    ((PASS++))
else
    echo -e "  ${YELLOW}⚠${NC} Found only $SCRIPT_COUNT scripts (expected 15+)"
    ((FAIL++))
fi

# Check 6: Deleted files are gone
echo ""
echo "[6] Verifying deleted files are removed..."
DELETED_COUNT=0
for file in IMPLEMENTATION_SUMMARY.md FINAL_STATUS.md LLFI_INTEGRATION_COMPLETE.md \
            LLFI_SUMMARY.md VALIDATION_SUMMARY.md CLEANUP_SUMMARY.md ORGANIZATION_COMPLETE.md; do
    if [ ! -f "$file" ]; then
        ((DELETED_COUNT++))
    else
        echo -e "  ${YELLOW}⚠${NC} $file still exists"
    fi
done

if [ "$DELETED_COUNT" -eq 7 ]; then
    echo -e "  ${GREEN}✓${NC} All 7 redundant docs removed"
    ((PASS++))
else
    echo -e "  ${RED}✗${NC} Only $DELETED_COUNT/7 redundant docs removed"
    ((FAIL++))
fi

# Check 7: Old test files removed
echo ""
echo "[7] Verifying old test files removed..."
OLD_TEST_COUNT=0
for file in tests/test_vulnerable.c tests/test_safe_equality.c \
            tests/test_safe_verification.c tests/test_clean.c; do
    if [ ! -f "$file" ]; then
        ((OLD_TEST_COUNT++))
    else
        echo -e "  ${YELLOW}⚠${NC} $file still exists"
    fi
done

if [ "$OLD_TEST_COUNT" -eq 4 ]; then
    echo -e "  ${GREEN}✓${NC} All 4 old test files removed"
    ((PASS++))
else
    echo -e "  ${RED}✗${NC} Only $OLD_TEST_COUNT/4 old test files removed"
    ((FAIL++))
fi

# Check 8: Examples directory removed
echo ""
echo "[8] Verifying examples/ directory removed..."
if [ ! -d "examples" ]; then
    echo -e "  ${GREEN}✓${NC} examples/ directory removed"
    ((PASS++))
else
    echo -e "  ${YELLOW}⚠${NC} examples/ directory still exists"
    ((FAIL++))
fi

# Check 9: Redundant scripts removed
echo ""
echo "[9] Verifying redundant scripts removed..."
REDUNDANT_COUNT=0
for file in scripts/compare.sh scripts/compare_original_hardened.sh \
            scripts/compare_resilience.sh scripts/test_transform.sh \
            cleanup_optional.sh llfi_demo.sh; do
    if [ ! -f "$file" ]; then
        ((REDUNDANT_COUNT++))
    else
        echo -e "  ${YELLOW}⚠${NC} $file still exists"
    fi
done

if [ "$REDUNDANT_COUNT" -eq 6 ]; then
    echo -e "  ${GREEN}✓${NC} All 6 redundant scripts removed"
    ((PASS++))
else
    echo -e "  ${RED}✗${NC} Only $REDUNDANT_COUNT/6 redundant scripts removed"
    ((FAIL++))
fi

# Check 10: .gitignore updated
echo ""
echo "[10] Checking .gitignore..."
if grep -q "opt_benchmark/" .gitignore && grep -q "llfi_experiments/" .gitignore; then
    echo -e "  ${GREEN}✓${NC} .gitignore updated with generated directories"
    ((PASS++))
else
    echo -e "  ${YELLOW}⚠${NC} .gitignore may need updates"
    ((FAIL++))
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 VERIFICATION SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}Passed: $PASS${NC}"
if [ $FAIL -gt 0 ]; then
    echo -e "${RED}Failed: $FAIL${NC}"
else
    echo -e "Failed: 0"
fi
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✅ All verification checks passed!${NC}"
    echo -e "${GREEN}The codebase is clean and ready for use.${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Some checks failed. Review the issues above.${NC}"
    exit 1
fi

#!/bin/bash
# Automated setup for real-world fault injection benchmarks

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Setting Up Real-World Test Benchmarks for FIHardeningPass ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

BENCH_DIR="$HOME/Documents/llvm-fihardening/benchmarks"
PASS_SO="$HOME/Documents/llvm-fihardening/build/FIHardeningPass.so"

# Check if pass is built
if [ ! -f "$PASS_SO" ]; then
    echo "❌ Error: FIHardeningPass.so not found!"
    echo "Please build the pass first:"
    echo "  cd ~/Documents/llvm-fihardening/build && make"
    exit 1
fi

mkdir -p $BENCH_DIR
cd $BENCH_DIR

# 1. Download LLFI
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[1/4] Setting up LLFI (LLVM-based Fault Injector)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -d "LLFI" ]; then
    echo "  📥 Cloning LLFI repository..."
    git clone --depth 1 https://github.com/DependableSystemsLab/LLFI.git
    
    echo "  🔨 Building LLFI..."
    cd LLFI
    mkdir -p build && cd build
    
    cmake -DLLVM_DIR=$(llvm-config --cmakedir) .. > build.log 2>&1
    if [ $? -eq 0 ]; then
        make -j$(nproc) >> build.log 2>&1
        if [ $? -eq 0 ]; then
            echo "  ✅ LLFI built successfully"
        else
            echo "  ⚠️  LLFI build had issues (see LLFI/build/build.log)"
            echo "  📝 Continuing with other benchmarks..."
        fi
    else
        echo "  ⚠️  LLFI CMake configuration failed"
        echo "  📝 Continuing with other benchmarks..."
    fi
    cd $BENCH_DIR
else
    echo "  ✅ LLFI already exists (skipping)"
fi

# 2. Download ChipWhisperer examples
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[2/4] Setting up ChipWhisperer Examples"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -d "chipwhisperer" ]; then
    echo "  📥 Cloning ChipWhisperer repository (this may take a moment)..."
    git clone --depth 1 --filter=blob:none --sparse \
        https://github.com/newaetech/chipwhisperer.git > /dev/null 2>&1
    
    cd chipwhisperer
    git sparse-checkout set software/chipwhisperer/tests > /dev/null 2>&1
    cd $BENCH_DIR
    
    echo "  ✅ ChipWhisperer examples downloaded"
else
    echo "  ✅ ChipWhisperer already exists (skipping)"
fi

# 3. Create simple test programs
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[3/4] Creating Simple Security Benchmarks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

mkdir -p simple_benchmarks
cd simple_benchmarks

# Password checker
cat > password_check.c <<'EOF'
/*
 * Simple password checker - vulnerable to fault injection
 * Attack vector: Glitch the comparison to bypass authentication
 */
#include <string.h>
#include <stdio.h>

int check_password(const char *input) {
    const char *correct = "secret123";
    
    // Vulnerable: Single comparison point
    if (strcmp(input, correct) == 0) {
        return 1;  // Access granted
    }
    return 0;  // Access denied
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <password>\n", argv[0]);
        return 1;
    }
    
    if (check_password(argv[1])) {
        printf("✓ Access granted\n");
        return 0;
    } else {
        printf("✗ Access denied\n");
        return 1;
    }
}
EOF

# AES S-box
cat > aes_sbox.c <<'EOF'
/*
 * AES S-box implementation - vulnerable to fault injection
 * Attack vector: Corrupt S-box lookup to leak key information
 */
#include <stdio.h>
#include <stdint.h>

// AES S-box lookup table
static const uint8_t sbox[256] = {
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5,
    0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0,
    0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc,
    0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a,
    0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0,
    0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b,
    0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85,
    0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5,
    0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17,
    0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88,
    0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c,
    0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9,
    0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6,
    0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e,
    0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94,
    0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68,
    0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
};

// Vulnerable S-box lookup
uint8_t aes_subbyte(uint8_t input) {
    // Vulnerable: Direct array access without verification
    return sbox[input];
}

void aes_subbytes(uint8_t *state, int len) {
    for (int i = 0; i < len; i++) {
        state[i] = aes_subbyte(state[i]);
    }
}

int main() {
    uint8_t test_data[] = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77};
    
    printf("Before: ");
    for (int i = 0; i < 8; i++) printf("%02x ", test_data[i]);
    printf("\n");
    
    aes_subbytes(test_data, 8);
    
    printf("After:  ");
    for (int i = 0; i < 8; i++) printf("%02x ", test_data[i]);
    printf("\n");
    
    return 0;
}
EOF

# Simple authentication
cat > auth_simple.c <<'EOF'
/*
 * Simple authentication with multiple vulnerabilities
 */
#include <stdio.h>
#include <string.h>

#define MAX_ATTEMPTS 3

int authenticate(const char *username, const char *password) {
    // Hardcoded credentials (bad practice, but good for testing)
    const char *valid_user = "admin";
    const char *valid_pass = "P@ssw0rd";
    
    // Vulnerable: Direct comparison
    if (strcmp(username, valid_user) == 0) {
        if (strcmp(password, valid_pass) == 0) {
            return 1;  // Success
        }
    }
    return 0;  // Failure
}

int main() {
    char username[32];
    char password[32];
    int attempts = 0;
    
    while (attempts < MAX_ATTEMPTS) {
        printf("Username: ");
        scanf("%31s", username);
        
        printf("Password: ");
        scanf("%31s", password);
        
        if (authenticate(username, password)) {
            printf("✓ Login successful!\n");
            return 0;
        }
        
        attempts++;
        printf("✗ Login failed. Attempts remaining: %d\n", MAX_ATTEMPTS - attempts);
    }
    
    printf("Account locked.\n");
    return 1;
}
EOF

echo "  ✅ Created 3 security benchmark programs:"
echo "     • password_check.c - Password authentication"
echo "     • aes_sbox.c - AES S-box implementation"
echo "     • auth_simple.c - Multi-attempt authentication"

cd $BENCH_DIR

# 4. Quick validation test
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[4/4] Running Quick Validation Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd simple_benchmarks

echo "  🔍 Testing password_check.c..."
clang -S -emit-llvm -o password_check.ll password_check.c 2>/dev/null

if [ -f password_check.ll ]; then
    opt -load-pass-plugin=$PASS_SO \
        -passes="fi-harden" \
        -disable-output \
        password_check.ll 2> test_output.txt
    
    if [ -f test_output.txt ]; then
        warnings=$(grep -c "Warning" test_output.txt || echo "0")
        vuln_funcs=$(grep -c "potentially vulnerable" test_output.txt || echo "0")
        
        echo "     Results: $warnings warnings, $vuln_funcs vulnerable functions"
        
        if [ $warnings -gt 0 ]; then
            echo "  ✅ Validation test passed!"
            echo ""
            echo "     Sample warnings:"
            head -5 test_output.txt | sed 's/^/     /'
        else
            echo "  ⚠️  No warnings detected (unexpected)"
        fi
        
        rm test_output.txt
    fi
    rm password_check.ll
else
    echo "  ⚠️  Could not generate LLVM IR"
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete!                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📂 Benchmarks installed in: $BENCH_DIR"
echo ""
echo "📋 Available test suites:"
if [ -d "$BENCH_DIR/LLFI" ]; then
    echo "   ✅ LLFI: $BENCH_DIR/LLFI/test_programs/"
else
    echo "   ⚠️  LLFI: Not available (build failed)"
fi
if [ -d "$BENCH_DIR/chipwhisperer" ]; then
    echo "   ✅ ChipWhisperer: $BENCH_DIR/chipwhisperer/"
else
    echo "   ⚠️  ChipWhisperer: Not available"
fi
echo "   ✅ Simple Benchmarks: $BENCH_DIR/simple_benchmarks/"
echo ""
echo "🚀 Next steps:"
echo ""
echo "   1. Test simple benchmarks:"
echo "      cd $BENCH_DIR/simple_benchmarks"
echo "      ./scripts/quick_test.sh password_check.c"
echo ""
echo "   2. Test LLFI programs (if available):"
echo "      cd $BENCH_DIR/LLFI/test_programs/quicksort"
echo "      clang -S -emit-llvm -o quicksort.ll quicksort.c"
echo "      opt -load-pass-plugin=$PASS_SO \\"
echo "          -passes='fi-harden' -disable-output quicksort.ll"
echo ""
echo "   3. Run comprehensive tests:"
echo "      ./scripts/run_comprehensive_tests.sh"
echo ""
echo "📖 Documentation: docs/REAL_WORLD_TESTSUITES.md"
echo ""

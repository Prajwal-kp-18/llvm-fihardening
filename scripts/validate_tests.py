#!/usr/bin/env python3
"""
Automated test validator for FIHardeningPass
Runs tests and validates expected warnings are generated
"""

import subprocess
import os
import sys
from pathlib import Path

class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'

class TestCase:
    def __init__(self, name, source_file, expected_warnings):
        self.name = name
        self.source_file = source_file
        self.expected_warnings = expected_warnings

def compile_to_ll(source_file, output_file):
    """Compile C source to LLVM IR"""
    cmd = ['clang', '-S', '-emit-llvm', '-o', output_file, source_file]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0

def run_pass(ll_file, plugin_path):
    """Run the FIHardeningPass on LLVM IR"""
    cmd = [
        'opt',
        f'-load-pass-plugin={plugin_path}',
        '-passes=fi-harden',
        '-disable-output',
        ll_file
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stderr

def validate_output(output, expected_warnings):
    """Validate that output contains expected warnings"""
    issues = []
    
    for warning_type, expected_count in expected_warnings.items():
        if warning_type == 'conditional_branch':
            actual_count = output.count('Conditional branch')
        elif warning_type == 'load':
            actual_count = output.count('Load instruction')
        elif warning_type == 'store':
            actual_count = output.count('Store instruction')
        elif warning_type == 'vulnerable_functions':
            actual_count = output.count('potentially vulnerable instruction')
        else:
            continue
        
        if actual_count != expected_count:
            issues.append(f"{warning_type}: expected {expected_count}, got {actual_count}")
    
    return issues

def main():
    print("=" * 60)
    print("FIHardeningPass Automated Test Validator")
    print("=" * 60)
    
    # Configuration
    plugin_path = "./build/FIHardeningPass.so"
    output_dir = Path("./test_results")
    output_dir.mkdir(exist_ok=True)
    
    # Check plugin exists
    if not os.path.exists(plugin_path):
        print(f"{Colors.RED}Error: Plugin not found at {plugin_path}{Colors.NC}")
        print("Please build the plugin first")
        return 1
    
    # Define test cases with expected warnings
    # Note: Counts include compiler-generated loads/stores (stack operations, etc.)
    test_cases = [
        TestCase(
            "Vulnerable Function",
            "tests/test_vulnerable.c",
            {
                'conditional_branch': 1,
                'vulnerable_functions': 1,  # Should report 1 vulnerable function
            }
        ),
        TestCase(
            "Safe with Equality",
            "tests/test_safe_equality.c",
            {
                'conditional_branch': 0,  # Has equality check, so no branch warnings
                'vulnerable_functions': 1,  # Still has vulnerable loads/stores
            }
        ),
        TestCase(
            "Safe with Verification",
            "tests/test_safe_verification.c",
            {
                'vulnerable_functions': 0,  # No warnings - protected by verification call
            }
        ),
        TestCase(
            "Clean Function",
            "tests/test_clean.c",
            {
                'vulnerable_functions': 1,  # Compiler generates loads/stores for local vars
            }
        ),
    ]
    
    passed = 0
    failed = 0
    
    for test in test_cases:
        print(f"\n{Colors.YELLOW}Testing: {test.name}{Colors.NC}")
        print("-" * 60)
        
        if not os.path.exists(test.source_file):
            print(f"{Colors.RED}✗ Source file not found: {test.source_file}{Colors.NC}")
            failed += 1
            continue
        
        # Compile
        ll_file = output_dir / f"{Path(test.source_file).stem}.ll"
        if not compile_to_ll(test.source_file, str(ll_file)):
            print(f"{Colors.RED}✗ Compilation failed{Colors.NC}")
            failed += 1
            continue
        
        # Run pass
        output = run_pass(str(ll_file), plugin_path)
        
        # Save output
        output_file = output_dir / f"{Path(test.source_file).stem}.output"
        with open(output_file, 'w') as f:
            f.write(output)
        
        # Validate
        issues = validate_output(output, test.expected_warnings)
        
        if issues:
            print(f"{Colors.RED}✗ Test failed:{Colors.NC}")
            for issue in issues:
                print(f"  - {issue}")
            print(f"\nActual output:")
            print(output)
            failed += 1
        else:
            print(f"{Colors.GREEN}✓ Test passed{Colors.NC}")
            passed += 1
    
    # Summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)
    print(f"Passed: {Colors.GREEN}{passed}{Colors.NC}")
    print(f"Failed: {Colors.RED}{failed}{Colors.NC}")
    print(f"Total:  {passed + failed}")
    
    return 0 if failed == 0 else 1

if __name__ == "__main__":
    sys.exit(main())

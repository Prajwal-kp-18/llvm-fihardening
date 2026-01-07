# Contributing to LLVM FI Hardening Pass

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Table of Contents
- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [GSoC Contributors](#gsoc-contributors)

## Code of Conduct

This project follows the [LLVM Code of Conduct](https://llvm.org/docs/CodeOfConduct.html). By participating, you are expected to uphold this code.

## Getting Started

### Prerequisites
- LLVM 17+ installed
- CMake 3.20+
- C++17 compatible compiler
- Git

### Building from Source
```bash
git clone https://github.com/Prajwal-kp-18/llvm-fihardening
cd llvm-fihardening
cmake -B build -DLLVM_DIR=/path/to/llvm
cmake --build build
```

### Running Tests
```bash
./scripts/run_tests.sh
```

## Development Workflow

### 1. Fork and Clone
```bash
git clone https://github.com/YOUR_USERNAME/llvm-fihardening.git
cd llvm-fihardening
git remote add upstream https://github.com/Prajwal-kp-18/llvm-fihardening
```

### 2. Create a Branch
```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/bug-description
```

### 3. Make Changes
- Write clean, documented code
- Follow the coding standards (see below)
- Add tests for new features
- Update documentation

### 4. Test Your Changes
```bash
# Quick test
./scripts/quick_test.sh

# Comprehensive tests
./scripts/run_tests.sh

# Format check
clang-format -i *.cpp *.h
```

### 5. Commit Changes
```bash
git add .
git commit -m "type(scope): description

Detailed explanation of changes.

Fixes #issue_number"
```

Commit message types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `perf`: Performance improvements
- `ci`: CI/CD changes

### 6. Push and Create PR
```bash
git push origin feature/your-feature-name
```
Then create a Pull Request on GitHub.

## Coding Standards

### C++ Style
This project follows the LLVM coding standards:
- Use `.clang-format` for automatic formatting
- 2-space indentation
- 100 character line limit
- Pointer/reference alignment: `Type *name`
- Use LLVM naming conventions:
  - `ClassNames` (PascalCase)
  - `functionNames()` (camelCase)
  - `VariableNames` (camelCase)
  - `MACRO_NAMES` (UPPER_SNAKE_CASE)

### Code Quality
- Write self-documenting code with clear names
- Add comments for complex logic
- Use `errs()` for debug output
- Handle edge cases
- No compiler warnings

### Example:
```cpp
// Good
void hardenBranch(BranchInst *BI, Function &F) {
  if (!BI->isConditional())
    return;
  
  // Create redundant condition evaluation
  Value *CondDup = Builder.CreateICmp(...);
  Stats.InstructionsDuplicated++;
}

// Bad
void harden_branch(BranchInst* bi,Function& f){
  if(!bi->isConditional())return;
  Value* conddup=Builder.CreateICmp(...); // duplicate condition
  Stats.InstructionsDuplicated++;
}
```

## Testing

### Test Requirements
All contributions must include tests:

1. **Unit Tests**: For individual functions
2. **Integration Tests**: For pass behavior
3. **Regression Tests**: To prevent bugs from returning

### Writing Tests
```c
// tests/test_your_feature.c
int main() {
  // Test case that exercises your feature
  int result = compute_something();
  return (result == expected) ? 0 : 1;
}
```

### Running Specific Tests
```bash
# Run single test
clang-17 -O0 -Xclang -disable-O0-optnone -emit-llvm -S tests/test_feature.c -o test.ll
opt-17 -load-pass-plugin=build/FIHardeningTransform.so \
  -passes=fi-harden-transform test.ll -o test_hardened.bc
```

## Submitting Changes

### Pull Request Guidelines
1. **Title**: Clear, descriptive title
   - Good: `feat(transform): Add TMR for floating-point arithmetic`
   - Bad: `Update code`

2. **Description**: Use the PR template
   - What changed
   - Why it changed
   - How to test it
   - Any breaking changes

3. **Small PRs**: Keep PRs focused
   - One feature/fix per PR
   - < 500 lines if possible

4. **CI Must Pass**: All checks must be green
   - Build succeeds
   - Tests pass
   - Code is formatted
   - No security issues

### Review Process
1. Automated CI runs
2. Code review by maintainers
3. Address feedback
4. Approval and merge

## GSoC Contributors

### Application Process
1. Review the [GSoC Ideas Page](docs/GSOC_IDEAS.md)
2. Join our community chat
3. Make a small contribution first
4. Submit a detailed proposal

### Expectations
- **Communication**: Regular updates (weekly)
- **Code Quality**: Production-ready code
- **Documentation**: Comprehensive docs
- **Testing**: Full test coverage
- **Blog Posts**: Document your journey

## Project Structure
```
.
├── FIHardeningPass.cpp       # Analysis pass
├── FIHardeningTransform.cpp  # Transformation pass
├── FIHardeningRuntime.cpp    # Runtime library
├── tests/                    # Test files
├── docs/                     # Documentation
├── scripts/                  # Helper scripts
└── benchmarks/               # Performance benchmarks
```

## Documentation

### When to Update Docs
- New features → Update relevant guides
- API changes → Update API reference
- Breaking changes → Update migration guide
- Bug fixes → Update CHANGELOG

### Documentation Files
- `README.md` - Project overview
- `docs/TRANSFORMATION_GUIDE.md` - Usage guide
- `docs/RUNTIME_API.md` - API reference
- `docs/12_STRATEGIES.md` - Strategy details

## Questions?

- **Issues**: GitHub Issues for bugs/features
- **Discussions**: GitHub Discussions for questions
- **Chat**: Join our community chat
- **Email**: maintainer@example.com

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

**Thank you for contributing to LLVM FI Hardening!** 🎉

# A Hybrid Fault Injection Hardening Pass for LLVM

[![LLVM](https://img.shields.io/badge/LLVM-17%2B-blue.svg)](https://llvm.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

An LLVM out-of-tree pass plugin for analyzing and hardening C/C++ code against fault injection (FI) vulnerabilities at the IR level. This project provides both static analysis and automatic transformation to help secure critical software against FI attacks.

---

## 📋 Table of Contents
- [Blog](https://www.prajwal-kp.xyz/blog/building-fault-injection-hardening-llvm)
- [Overview](#overview)
- [Features](#features)
- [Quick Start (Docker)](#-quick-start-recommended-docker)
- [Manual Build](#-manual-build-without-docker)
- [Repository Contents](#-repository-contents)
- [How It Works](#how-it-works)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#-citation--contact)

---

## 🎯 Overview

**A Hybrid Fault Injection Hardening Pass for LLVM** is a comprehensive, research-grade toolkit for fault injection vulnerability detection and automatic code hardening at the LLVM IR level. It is designed for reproducible research, artifact evaluation, and practical deployment in securing critical software systems.

### 🔍 Analysis Pass (FIHardeningPass)
- Performs static analysis to detect potential vulnerabilities:
  - **Conditional branches** lacking redundant checks
  - **Load/Store operations** without verification calls
  - **Security-critical code paths** missing protection
- The analysis pass is inspection-only (does not modify IR) and provides actionable, detailed warnings to guide developers.

### 🛡️ Transformation Pass (FIHardeningTransform)
- Provides automatic IR-to-IR hardening to transform code and resist fault injection:
  - **Instruction Duplication:** Redundant computation with verification
  - **Branch Hardening:** Triple redundancy for control flow
  - **Memory Protection:** Read-back verification and checksums
  - **Configurable Levels:** Balance security and performance (levels 0–3)
- The transformation pass is highly configurable, allowing users to tailor hardening strategies to their needs.

### 📊 Runtime Verification Library
- Links with hardened code to provide runtime detection and response:
  - **Integer/Pointer Verification:** Detects corrupted values
  - **Branch Protection:** Prevents control flow hijacking
  - **Checksum Protection:** Validates memory integrity
  - **Statistics Tracking:** Monitors and logs fault detection in real time

### What You Get
1. 🔍 **Detection:** Identify vulnerable code locations
2. 🛡️ **Protection:** Automatically harden critical code
3. 📊 **Verification:** Runtime fault detection and logging
4. 🧪 **Testing:** LLFI integration for validation

---

## 🏗️ Design and Implementation

FIHardeningTransform (FHT) operates as an LLVM IR-to-IR transformation pass with three configurable hardening levels:

- **Level 1 (Baseline):** Protects all branches, loads, and stores.
- **Level 2 (Intermediate):** Adds protection for approximately 50% of temporary (register) values.
- **Level 3 (Maximum):** Protects 100% of temporaries, applies Triple Modular Redundancy (TMR) to critical arithmetic, and verifies phi nodes at control flow merges.

### Triple Modular Redundancy (TMR)
Critical arithmetic operations—specifically multiply, divide, and modulo—are executed three times, and the results are compared using majority voting. These operations are chosen due to their high impact in critical algorithms and the justified computational overhead. If at least two results match, execution continues; otherwise, a safe abort is triggered to prevent propagation of faults.

### Temporary Value Protection
Short-lived register values (temporaries) are duplicated immediately after creation. Before each use, the pass inserts verification logic to ensure both copies match. Level 3 provides comprehensive protection for all temporary instructions, while Level 2 offers partial coverage for performance balance.

### Phi Node Verification
At control flow merge points (such as loop headers and conditional joins), the pass creates redundant phi nodes. A verification call is inserted to assert that both phi nodes select the same incoming value, preventing attacks that target loop-carried dependencies or control flow integrity.

### Integration with Existing Defenses
FIHardeningTransform composes seamlessly with other hardening strategies, such as bounds checking and stack protection. The pass emits runtime calls to `libfihardening_runtime.a` for value verification and controlled termination, ensuring robust, layered defense.

---


**Hardening Levels:**
- `0`: Minimal (critical paths only)
- `1`: Moderate (default)
- `2`: Aggressive (checksums)
- `3`: Maximum (triple voting)

**Configuration Options:**
- `-fi-harden-branches=true|false` — Control flow protection
- `-fi-harden-memory=true|false` — Load/store verification
- `-fi-harden-arithmetic=true|false` — Arithmetic duplication

---

## Features

- Static analysis for FI vulnerabilities in LLVM IR
- Automatic IR-to-IR code hardening (transformation pass)
- Configurable hardening strategies (instruction duplication, branch hardening, memory protection)
- Runtime verification support
- Easy-to-use test suite and helper scripts
- Fully reproducible Docker environment

---

## 🚀 Quick Start (Recommended: Docker)

The easiest and most reliable way to use FIHardening is with Docker.

1. **Get the Docker Image:**
   ```sh
   docker pull prajwal1817/llvm-fihardening
   ```
2. **Start a Container:**
   ```sh
   docker run -it prajwal1817/llvm-fihardening:latest
   ```
   - This opens a shell with all dependencies pre-installed and the pass already built.
3. **Run the Test Suite:**
   ```sh
   bash scripts/run_tests.sh
   ```
   - This will run all tests and show results immediately.

---

## 🛠️ Manual Build (Without Docker)

If you prefer to build natively, ensure you have LLVM (17+), Clang, CMake, a C++17 compiler, and Graphviz.

```sh
mkdir build && cd build
cmake ..
make
cd ..
bash scripts/run_tests.sh
```

---

## 📦 Repository Contents
- `CMakeLists.txt` — Build configuration
- `FIHardeningPass.cpp` — Analysis pass
- `FIHardeningTransform.cpp` — Transformation pass
- `FIHardeningRuntime.cpp` / `.h` — Runtime verification
- `scripts/run_tests.sh` — Main test script
- `docker-repro/Dockerfile` — Docker build recipe
- `tests/` — Example test cases

---

## How It Works

FIHardeningPass operates in two main modes:

- **Analysis:**
  - Scans LLVM IR for patterns susceptible to fault injection, such as missing redundant checks or unverified memory operations.
  - Reports warnings and highlights code locations needing attention.

- **Transformation:**
  - Automatically inserts redundancy, verification, and protection logic into the IR.
  - Supports multiple hardening strategies, including instruction duplication, branch voting, and memory checks.
  - Can be configured for different levels of security and performance trade-offs.

- **Runtime Verification:**

  - Links a runtime library to provide checks for pointer/integer integrity, control flow, and memory safety during execution.

---

## License

This project is provided as-is for educational and research purposes under the MIT license.

---

## 📢 Citation / Contact

If you use this pass for research or evaluation, please cite our paper or contact the maintainer for details.

---

**Happy hardening!**

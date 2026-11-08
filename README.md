# FI Hardening Pass for LLVM

Out-of-tree LLVM pass plugin that hardens security decisions in C code against fault-injection
attacks, by re-checking conditional branches and comparisons from opaque copies of their operands.

**Status: being rebuilt.** No countermeasures yet.

Blog: [Building fault-injection hardening in LLVM](https://prajwal-kp.vercel.app/blog/building-fault-injection-hardening-llvm)

## Threat model

| | |
|---|---|
| **Attacker** | Physical access to the device. Glitches clock or voltage, or fires an EM pulse or laser, at a chosen time. |
| **Fault models** | (a) **Instruction skip**: one instruction doesn't execute (then two). (b) **Register corruption**: a single bit-flip, or a set/reset of a register, after an instruction. (c) **Branch inversion**: a conditional branch goes the wrong way (a consequence of a and b). |
| **Assets** | Security decisions: PIN and password checks, signature-verification results, secure-boot decisions, loop counters in crypto code. |
| **Attacker wins when** | The program reaches a *bad outcome*, such as accepting a wrong PIN. "Some output differs" isn't a win; a crash or a detected fault (trap) is a loss for the attacker. |
| **Target** | Arm Cortex-M (Thumb-2). Developed on x86-64, also tested on AArch64. |
| **Out of scope** | Soft errors and silent-data-corruption rates (reliability), Spectre and other side channels, memory-safety bugs. |

Every claim this project makes is measured against these fault models on the final binary, not on
LLVM IR.

## Prior art

| | What it does | What this project reuses | What it does differently |
|---|---|---|---|
| **GCC** `-fharden-conditional-branches`, `-fharden-compares` (GCC 12+, [`gimple-harden-conditionals.cc`](https://gcc.gnu.org/git/?p=gcc.git;a=blob;f=gcc/gimple-harden-conditionals.cc)) | Runs late, just before RTL expansion. For each conditional branch, detaches the operands *before* the branch, splits both successor edges, and in each new block evaluates the *reversed* compare and traps if it disagrees with the edge taken. For a compare whose result is a value, computes the reversed compare and traps if both results are equal. "Detaching" is an empty `asm` whose output is tied to its input, so the compiler can't tell the copy equals the original. | The two check shapes, the detach barrier, detaching before the branch (later, "the compiler may use values inferred from the compares"), and one trap block per check. | GCC skips FP compares that have no inverse once NaNs are honoured; LLVM's `CmpInst::getInversePredicate` always has one (`oeq` ↔ `une`), so nothing is skipped. GCC's barrier asm is not volatile; this project defaults to `asm sideeffect`, because OpenTitan saw a non-volatile barrier merged during register allocation. GCC hardens every function; this project hardens only the ones you mark. |
| **GlitchResistor** (UCSB, DSN 2021, [repo](https://github.com/ucsb-seclab/glitch_resistor)) | Legacy-PM passes at `EP_OptimizerLast`. For each conditional-branch edge, a block re-executes the condition's backward slice (the `icmp` and the loads feeding it, all made `volatile`) and calls a user-supplied `gr_glitch_detected()` on a mismatch. Also loop-guard re-checks, high-Hamming-distance constants, return-value and global-integrity protection, random delays. Opt-out per function. Validated with a ChipWhisperer-Lite on an STM32F0. | Inserting after IR optimisation; a re-check on each edge; its physical results as a comparison point. | On a mismatch GlitchResistor *calls* a handler and then continues to the protected block, so skipping that one `bl` defeats the check; this project branches to an inline trap. It doesn't make the program's own loads volatile; it re-checks from opaque register copies. Opt-in selection. New pass manager, so it works with `clang -fpass-plugin` on current LLVM (the legacy-PM extension points it uses no longer exist). |
| **ASPIS** (Politecnico di Milano, TODAES 2024, [repo](https://github.com/HEAPLab/ASPIS)) | New-PM plugins (LLVM 21) against soft errors: data duplication (EDDI, sEDDI, FDSC) and control-flow signatures (CFCSS, RASM, RACFED). Functions and globals are selected with `annotate("to_harden"/"exclude"/...)`, read from `llvm.global.annotations`. A driver script hardens `-O0` IR with `opt`, then optimises; mismatches call `DataCorruption_Handler`/`SigMismatch_Handler`. | Annotation-based selection read from `llvm.global.annotations`; its control-flow-signature passes as the reference if this project ever adds signatures. | Attacker fault model, not single-event upsets. Hardens *after* optimisation inside a normal `clang -O2` build, instead of before it through a separate script. Targeted re-checks of security decisions instead of duplicating all data. Inline trap instead of a handler call. |

## Contribution

The techniques aren't new. Reversed-condition re-checks ship in GCC and appear in GlitchResistor;
instruction and data duplication go back to EDDI and SWIFT. What this project adds is the
combination and the evidence: (1) Clang/LLVM parity with GCC's `-fharden-compares` and
`-fharden-conditional-branches`, as a plugin that runs inside an ordinary
`clang -O2 -fpass-plugin=…` build; (2) tests showing the checks survive the whole `-O2` IR
pipeline *and* the backend on AArch64 and Thumb-2, checked in the generated assembly; and (3) a
binary-level fault-simulation comparison against GCC's flags and the FISSC hand-hardened VerifyPIN
variants on the same Cortex-M target, reporting absolute counts of bad outcomes. Over GCC that's
Clang support plus published measurements; over GlitchResistor, checks that a single skipped call
can't disable, on the current pass manager; over ASPIS, an attacker fault model and hardening that
runs after optimisation instead of before it.

Points (2) and (3) are the goal, not yet results.

### Known critiques

- **"Instruction duplication: leaky and not too fault-tolerant"** (Cojocar, Papagiannopoulos,
  Timmers, CARDIS 2017). They argue duplication protects weakly in practice and increases
  side-channel leakage. This project doesn't duplicate instructions to survive skips: it re-checks a
  decision with the *reversed* condition on opaque copies, so a fault has to produce two consistent
  wrong results to go unnoticed. It claims single-fault protection only, measures double faults
  separately, and leaves side-channel leakage out of scope as a stated cost.
- **"Is this a credible threat model for upstream LLVM?"** (asked of an Aug 2025 RFC for Arm32 skip-fault
  mitigation). The case rests on GCC already shipping the same reversed-condition checks "to detect
  some power-deprivation hardware attacks" (GCC 13 release notes), on binary-level evaluation
  against several fault models, and on claiming nothing the measurements don't show.

## Build

Needs LLVM 23 or newer; older versions are rejected at configure time. Point CMake at the LLVM you
want, since a plain `cmake` may find a different one:

```sh
cmake -S . -B build -G Ninja -DLLVM_DIR=/usr/lib/llvm-23/lib/cmake/llvm
ninja -C build
```

Run the tests (needs LLVM's `lit` and `FileCheck`, from the `llvm-23-tools` package):

```sh
ninja -C build check-fi
```

Or do all of that in Docker, which installs LLVM 23 from apt.llvm.org. CI runs this same build:

```sh
docker build -f docker-repro/Dockerfile -t fihardening .
```

## Usage

The pass doesn't harden anything yet; for now it reports which functions it selected and which
countermeasures it would apply.

Mark the functions to harden:

```c
__attribute__((annotate("fi_harden"))) int verify_pin(const char *pin) { ... }
```

```sh
clang -O2 -fpass-plugin=build/FIHarden.so -c in.c
opt -load-pass-plugin=build/FIHarden.so -passes='fi-harden<branches;compares>' in.ll -S -o out.ll
```

| Parameter (`fi-harden<...>`, or `-mllvm -fi-harden=a,b` under clang) | Effect |
|---|---|
| `branches`, `compares` | Countermeasures to apply. Naming none applies all of them. |
| `all` | Harden every defined function, not only the marked ones. |
| `allowlist=<file>` | Also harden the functions named in `<file>`: one IR name per line, mangled for C++. |

The trap handler `fi_trap` is never hardened. Add `-pass-remarks=fi-harden` (opt)
or `-Rpass=fi-harden` (clang) to see what was hardened, and `-pass-remarks-missed=fi-harden` /
`-Rpass-missed=fi-harden` to see what was left alone and why. `-passes=fi-harden-skips` lists every
instruction countermeasures must leave alone: atomics, volatile accesses, EH pads,
`invoke`/`callbr`, `va_arg`, compares on vectors or on values over 64 bits, and anything with side
effects or memory access. `-passes=fi-harden-copies` runs every compare on opaque copies of its
operands (`asm sideeffect "", "=r,0"`), the barrier that keeps checks from being folded away.

```
lib/            pass plugin sources
test/           lit + FileCheck tests
docker-repro/   reproducible build, also used by CI
```

License: [MIT](LICENSE)

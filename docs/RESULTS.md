# Results

What hardening does against simulated faults on a Cortex-M3, compared with GCC's
`-fharden-compares -fharden-conditional-branches` and with FISSC's hand-hardened VerifyPIN
variants, and what it costs on Embench kernels. Every count is absolute: the number of single
faults that produced each outcome, not a percentage.

[VERIFICATION.md](VERIFICATION.md) has the correctness checks; [DESIGN.md](DESIGN.md) explains the
countermeasures.

## Setup

- **Target**: bare-metal ARMv7-M (Cortex-M3, Thumb-2), built on [`eval/cm`](../eval/cm): a vector
  table, a reset handler that copies `.data` and clears `.bss`, and a linker script with flash at 0
  and 64 KB of RAM at `0x20000000`. No libc. `main`'s return value is the outcome.
- **Compilers**: clang 23.1.6 with the plugin at -O2, and arm-none-eabi-gcc 13.2.1 (Ubuntu's
  `gcc-arm-none-eabi`) at -O2.
- **Simulator**: [`eval/fisim.py`](../eval/fisim.py), on Unicorn 2.1.2 and Capstone 6.0.0a11. It runs
  the program once (the golden run), then once per single fault in the instructions `verifyPIN`
  executes, callees included:
  - **skip**: one executed instruction doesn't execute (it becomes a NOP for that one execution;
    a skipped `it` leaves its block unconditional, as on hardware);
  - **flip**: right after one executed instruction, one bit of a register it wrote is inverted
    (r0-r12, sp, lr: 32 bits each; the N, Z, C and V flags). Capstone says which registers an
    instruction writes, and its versions disagree on a few, so the flip totals depend on its
    version (Capstone 4.0.2 gives a few percent more or fewer); the skip counts don't.
- **Outcomes**: *PIN accepted* (the attack worked), *counter kept* (the try counter wasn't
  decremented, FISSC's second oracle), *detected* (a check trapped, or FISSC's own countermeasure
  fired), and otherwise a crash, a timeout or no effect.

The simulator is checked twice: on all 16 builds below, stopping the golden run at any instruction
and resuming it reproduces it exactly, and an independent simulator, ARMORY, agrees on the skip
counts (below). `test/fisim.c` runs it on a small PIN check in every `check-fi` (when Python
has Unicorn and Capstone).

## VerifyPIN

[FISSC](https://lazart.gricad-pages.univ-grenoble-alpes.fr/fissc/) 2.2's VerifyPIN compares a
4-digit user PIN with the card PIN, with a try counter. `v0` has no countermeasures; `v1` to `v7`
add hand-written ones (hardened booleans, fixed-time loop, inlining, decrementing the counter
first, a backup counter, double calls, double tests, a step counter). The plugin hardens `v0`'s
`verifyPIN`, the function that makes the decision, as the README says to mark it.

FISSC's attacker enters 0000 against 1234. Every digit is wrong, so getting past the compare loop
takes one fault per digit. An attacker who knows three digits enters 1230 and needs only one:

**User PIN 1230** (one wrong digit)

| Build | Bytes | Instructions | Skip: PIN accepted | Skip: counter kept | Skip: detected | Skips | Flip: PIN accepted | Flip: counter kept | Flip: detected | Flips |
|---|---|---|---|---|---|---|---|---|---|---|
| v0, clang | 118 | 35 | **2** | 8 | 0 | 35 | **4** | 50 | 0 | 640 |
| v0, clang + fi-harden A | 170 | 55 | **0** | 3 | 6 | 55 | **3** | 13 | 355 | 980 |
| v0, clang + fi-harden B | 118 | 35 | **2** | 8 | 0 | 35 | **4** | 50 | 0 | 640 |
| v0, clang + fi-harden A+B | 170 | 55 | **0** | 3 | 6 | 55 | **3** | 13 | 355 | 980 |
| v0, gcc | 84 | 38 | **4** | 9 | 0 | 38 | **29** | 77 | 0 | 840 |
| v0, gcc -fharden-* | 136 | 68 | **0** | 5 | 11 | 68 | **24** | 80 | 363 | 1384 |
| v1 HB, clang | 118 | 35 | **2** | 8 | 0 | 35 | **3** | 50 | 0 | 640 |
| v2 HB+FTL, clang | 106 | 22 | **2** | 8 | 0 | 22 | **3** | 17 | 0 | 436 |
| v3 HB+FTL+INL, clang | 106 | 22 | **2** | 8 | 0 | 22 | **3** | 17 | 0 | 436 |
| v4 HB+FTL+INL+DPTC+PTCBK+LC, clang | 106 | 22 | **2** | 7 | 0 | 22 | **3** | 17 | 0 | 432 |
| v5 HB+FTL+DPTC+DC, clang | 106 | 22 | **2** | 7 | 0 | 22 | **3** | 17 | 0 | 432 |
| v6 HB+FTL+INL+DPTC+DT, clang | 106 | 22 | **2** | 7 | 0 | 22 | **3** | 17 | 0 | 432 |
| v7 HB+FTL+INL+DPTC+DT+SC, clang | 124 | 28 | **1** | 5 | 0 | 28 | **3** | 6 | 0 | 536 |

**User PIN 0000** (FISSC's: every digit wrong)

| Build | Bytes | Instructions | Skip: PIN accepted | Skip: counter kept | Skip: detected | Skips | Flip: PIN accepted | Flip: counter kept | Flip: detected | Flips |
|---|---|---|---|---|---|---|---|---|---|---|
| v0, clang | 118 | 23 | **1** | 7 | 0 | 23 | **27** | 73 | 0 | 436 |
| v0, clang + fi-harden A | 170 | 30 | **1** | 5 | 3 | 30 | **27** | 37 | 13 | 572 |
| v0, clang + fi-harden B | 118 | 23 | **1** | 7 | 0 | 23 | **27** | 73 | 0 | 436 |
| v0, clang + fi-harden A+B | 170 | 30 | **1** | 5 | 3 | 30 | **27** | 37 | 13 | 572 |
| v0, gcc | 84 | 20 | **1** | 6 | 0 | 20 | **16** | 64 | 0 | 432 |
| v0, gcc -fharden-* | 136 | 29 | **0** | 5 | 4 | 29 | **15** | 71 | 15 | 664 |
| v1 HB, clang | 118 | 23 | **1** | 7 | 0 | 23 | **26** | 73 | 0 | 436 |
| v2 HB+FTL, clang | 106 | 22 | **1** | 7 | 0 | 22 | **26** | 40 | 0 | 436 |
| v3 HB+FTL+INL, clang | 106 | 22 | **1** | 7 | 0 | 22 | **26** | 40 | 0 | 436 |
| v4 HB+FTL+INL+DPTC+PTCBK+LC, clang | 106 | 22 | **0** | 5 | 0 | 22 | **26** | 40 | 0 | 432 |
| v5 HB+FTL+DPTC+DC, clang | 106 | 22 | **0** | 6 | 0 | 22 | **26** | 40 | 0 | 432 |
| v6 HB+FTL+INL+DPTC+DT, clang | 106 | 22 | **0** | 6 | 0 | 22 | **26** | 40 | 0 | 432 |
| v7 HB+FTL+INL+DPTC+DT+SC, clang | 124 | 28 | **1** | 6 | 0 | 28 | **26** | 29 | 0 | 536 |

*Bytes*: code of the functions `verifyPIN` ran. *Instructions*: executed in `verifyPIN`, fault
free. *Detected* for v7 counts traps only: v7 calls its countermeasure on every wrong PIN.

What the tables show:

1. **Single skip, one wrong digit: 0 accepted with A**, against 2 for clang alone. GCC's flags do
   the same for GCC (4 to 0). Of A's 55 skips, 6 trap, 3 keep the counter, 1 crashes and 45
   have no effect.
2. **B changes nothing here.** Every compare in VerifyPIN feeds a branch, which is A's job; B
   checks compares used as values, and none is left at -O2.
3. **What's left is data flow**, which A and B don't claim to cover (DESIGN.md, "What it doesn't
   protect"). With every digit wrong, the one accepted skip in A+B is the `movw` that builds the
   card PIN's address: a stale register makes both loads read the user PIN. The accepted flips are a
   corrupted pointer (into zeroed RAM, which matches the user PIN 0000), a PIN digit corrupted
   right after its load and before it's copied, and the initial `g_authenticated = 0`.
   Data-flow duplication (countermeasure C, not built yet) is aimed at these.
4. **What A detects.** With one wrong digit, 355 of A+B's 980 flips trap. 144 flip one of the
   upper 24 bits of a PIN digit just loaded with `ldrb`: the original `cmp` reads the whole
   register and takes the wrong edge, the re-check compares the zero-extended byte and disagrees.
   195 hit the re-check's own copies (a fault in the check, which a trap answers as well as any),
   13 the compare's flags, and 3 the try counter's sign-extending load and sign extension.
5. **FISSC's hand-written countermeasures don't survive -O2.** In v2 to v6, clang deletes every
   call to `countermeasure()` from `verifyPIN`, since it can prove each double test and counter
   check redundant, and each of the five compiles to 106 bytes. v7 keeps one call, the one its
   wrong-PIN path always calls. With one wrong digit each version still has 1 or 2 single-skip
   attacks. This is the case for hardening inside the compiler, after optimisation: source-level
   redundancy is exactly what an optimiser removes.
6. **Mark the decision, not its helpers.** Marking `byteArrayCompare` as well keeps it out of line
   (marked functions are `noinline`), and its return value then crosses a call unchecked: A+B with
   both marked accepts 3 skips with FISSC's PIN, against 1 with only `verifyPIN` marked.

FISSC's own results come from Lazart, which injects test inversions into LLVM IR and finds 2
single-fault attacks on v0. At the binary level after -O2, with FISSC's PIN, the only single-skip
attack on clang's v0 is the address fault above: clang merged `byteArrayCompare`'s result test into
the compare loop, so there's no single test left to invert. The fault models differ, so this
isn't a like-for-like comparison, but it is one more reason to measure the final binary.

```sh
eval/fissc.py build/FIHarden.so    # downloads FISSC 2.2; clang 23 and arm-none-eabi-gcc on PATH
```

## Cross-check with ARMORY

[ARMORY](https://github.com/emsec/arm-fault-simulator) (Hoffmann, Schellenberg and Paar, TIFS
2021) is an exhaustive fault simulator for ARMv7-M with its own emulator, M-Ulator, independent of
Unicorn. [`eval/armory.py`](../eval/armory.py) builds it at a pinned commit and runs its *transient
instruction skip* on the same ELFs, from the same reset handler, faulting the same functions (the
ones `verifyPIN` ran), and counts the skips that reach `fi_bad()`, which the harness calls when the
wrong PIN was accepted:

| Build | User PIN | Skips | fisim.py: PIN accepted | ARMORY: PIN accepted |
|---|---|---|---|---|
| v0, clang | 1230 | 35 | 2 | 2 |
| v0, clang + fi-harden A | 1230 | 55 | 0 | 0 |
| v0, clang + fi-harden B | 1230 | 35 | 2 | 2 |
| v0, clang + fi-harden A+B | 1230 | 55 | 0 | 0 |
| v0, gcc | 1230 | 38 | 4 | 4 |
| v0, gcc -fharden-* | 1230 | 68 | 0 | 0 |
| v1 HB, clang | 1230 | 35 | 2 | 2 |
| v2 HB+FTL, clang | 1230 | 22 | 2 | 2 |
| v3 HB+FTL+INL, clang | 1230 | 22 | 2 | 2 |
| v4 HB+FTL+INL+DPTC+PTCBK+LC, clang | 1230 | 22 | 2 | 2 |
| v5 HB+FTL+DPTC+DC, clang | 1230 | 22 | 2 | 2 |
| v6 HB+FTL+INL+DPTC+DT, clang | 1230 | 22 | 2 | 2 |
| v7 HB+FTL+INL+DPTC+DT+SC, clang | 1230 | 28 | 1 | 1 |
| v0, clang | 0000 | 23 | 1 | 1 |
| v0, clang + fi-harden A+B | 0000 | 30 | 1 | 1 |
| v0, gcc -fharden-* | 0000 | 29 | 0 | 0 |

They agree on all 16 builds. Register flips aren't cross-checked: ARMORY flips a register an
instruction reads, before it runs, and `fisim.py` one it wrote, after it ran, so the counts aren't
comparable.

```sh
eval/armory.py ELF verifyPIN [ELF verifyPIN]...    # builds ARMORY; needs git, meson, ninja
```

## Overhead

[Embench-IoT](https://github.com/embench/embench-iot) 1.0's crc32, matmult-int, nettle-aes and
nettle-sha256, with every function in the kernel hardened (`all`, and GCC's flags apply to every
function too). Embench's support code is the same plain clang build in every row. *Code bytes*:
the kernel object's code. *Instructions*: executed in `benchmark()`, from `start_trigger` to
`stop_trigger`. Unicorn has no timing model, so instructions stand in for cycles. Overhead is
against the same compiler's plain build; every hardened kernel passes its own check.

| Kernel | Build | Code bytes | Instructions | Bytes overhead | Instructions overhead |
|---|---|---|---|---|---|
| crc32 | clang | 142 | 3135496 | +0% | +0% |
| crc32 | clang + fi-harden A | 210 | 3832158 | +48% | +22% |
| crc32 | clang + fi-harden B | 166 | 3135496 | +17% | +0% |
| crc32 | clang + fi-harden A+B | 234 | 3832158 | +65% | +22% |
| crc32 | gcc | 144 | 3135324 | +0% | +0% |
| crc32 | gcc -fharden-* | 208 | 3483997 | +44% | +11% |
| matmult-int | clang | 1528 | 1960778 | +0% | +0% |
| matmult-int | clang + fi-harden A | 1876 | 2035526 | +23% | +4% |
| matmult-int | clang + fi-harden B | 1576 | 1960778 | +3% | +0% |
| matmult-int | clang + fi-harden A+B | 1924 | 2035526 | +26% | +4% |
| matmult-int | gcc | 464 | 3125944 | +0% | +0% |
| matmult-int | gcc -fharden-* | 636 | 4282708 | +37% | +37% |
| nettle-aes | clang | 4232 | 2570285 | +0% | +0% |
| nettle-aes | clang + fi-harden A | 4864 | 2648050 | +15% | +3% |
| nettle-aes | clang + fi-harden B | 5032 | 2642825 | +19% | +3% |
| nettle-aes | clang + fi-harden A+B | 5624 | 2679250 | +33% | +4% |
| nettle-aes | gcc | 2256 | 2957079 | +0% | +0% |
| nettle-aes | gcc -fharden-* | 2776 | 3198258 | +23% | +8% |
| nettle-sha256 | clang | 3970 | 2569776 | +0% | +0% |
| nettle-sha256 | clang + fi-harden A | 4234 | 2578327 | +7% | +0% |
| nettle-sha256 | clang + fi-harden B | 4302 | 2569776 | +8% | +0% |
| nettle-sha256 | clang + fi-harden A+B | 4570 | 2578802 | +15% | +0% |
| nettle-sha256 | gcc | 3384 | 2496141 | +0% | +0% |
| nettle-sha256 | gcc -fharden-* | 3588 | 2602068 | +6% | +4% |

A hardens loops, so it costs most where a loop branch runs every iteration: crc32's inner loop is
a few instructions, and re-checking its condition on both edges adds 22% (GCC's flags: 11%). B only
costs where a compare's result is used as a value. On the other three kernels A+B adds 0 to 4%
more instructions and 15 to 33% more code. Against GCC's flags on their own baseline, A+B costs
more code on three kernels of four and fewer instructions on three of four (matmult-int: 4%
against 37%).

```sh
eval/overhead.py build/FIHarden.so    # downloads Embench-IoT 1.0
```

## Not measured

- **Double faults.** Each check is built for one fault; two can defeat it.
- **Register set and reset** (a whole register cleared or filled), which the threat model lists
  next to bit flips. Branch inversion is covered only through its causes: a skipped branch, or a
  flipped flag.
- **Physical faults.** No glitching hardware yet; the simulator's fault models are the usual
  abstractions (Moro et al. for skips), not measurements of a chip.
- **Faults outside `verifyPIN`**, in the code that calls it or reads its result.
- **Real cycles.** Instruction counts, not a cycle model or a board.

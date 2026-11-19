# Verification

What was checked beyond the lit suite, how, and what came out. The plugin is the one in commit
267c794 (later commits add tests, tools and docs), run on x86-64 Linux with LLVM 23.1.6 from
apt.llvm.org. The corpus runs use LLVM's tests from llvm-project be4424c89e0d (2026-11-19). Each
check ends with the command that reruns it; the batch ones keep to two or three processes at
`nice -n 19`.

The Transforms corpus ran on LLVM 23's `opt`, which has no assertions, with `-verify-each`. An
earlier run, on an assertions-enabled trunk build and the plugin before 267c794's fixes, found no
plugin bugs either; that build no longer matches its source tree, so a plugin built against it
couldn't be trusted to load.

[DESIGN.md](DESIGN.md) explains the design these checks test.

## Summary

| Check | What it shows | Result |
|---|---|---|
| The lit suite, in CI on LLVM 23 and 24 | Each transformation in IR and in AArch64 and Thumb-2 assembly, the binary audit, a test for each safeguard, the differential tests and the fault simulator | 23 tests pass |
| Random programs: 200 from `gen.py`, 106 from Csmith | Hardening changes no fault-free run | 1,224 runs identical at x86-64 `-O0` and `-O2`, AArch64 and Thumb-2 `-O2`; 0 differ, 0 trap |
| compiler-rt's builtins and their unit tests | The same, on real arithmetic code | 855 unit-test runs identical at x86-64 `-O0` and `-O2`, AArch64 and Thumb-2 `-O2`; 0 differ |
| LLVM's Transforms tests, hardened with `all` | No crash and valid IR, whatever the input | 12,657 files in three pipelines: 0 plugin failures; 3 LLVM bugs, all with `-O2` run after hardening |
| LLVM's AArch64, ARM and Thumb2 CodeGen tests, hardened | The backend lowers whatever hardening produces | 4,961 files: 3,915 lowered, 0 plugin failures; 2 need the `-mattr=+neon` their RUN line passes |
| Fault injection on a PIN check, AArch64 and Thumb-2 | Whether one skipped or inverted instruction in a hardened function gets a wrong PIN accepted | `-O2`: 0 of 476 faults (unhardened: 6 of 75). `-O0`: 2 to 6 per function, all data flow |

## Bugs this found

Verifying features 1 to 9 found five bugs, fixed in 267c794, each now pinned by a test:

1. **Inlining dropped hardening.** A marked function inlined into an unmarked caller, before
   fi-harden runs at OptimizerLast, left its decision there unhardened, and the audit couldn't see
   it. Marked and allowlisted functions are now `noinline`; `always_inline` on one is an error.
   (`inline.c`)
2. **`-flto` weakened A.** The compile step hardened, then link-time GVN turned the true edge's
   `copy(b)` into `copy(a)`. `-flto` is now refused when something would be hardened. (`clang.c`)
3. **`-g` with `trap=call` made invalid IR** when `fi_trap` has debug info (defined in the same
   module, or after LTO): its call had no location. The trap block now gets line 0 in the
   function's scope. (`debuginfo.c`)
4. **B was quadratic** in the compares per block: 16k compares in one block took 12 s. Processing
   them last first takes 0.4 s.
5. **B's check let one skip through.** "Trap if the copy equals the inverse" passed a register left
   holding junk: skipping the `and w0, w8, #1` that moves the boolean into the return register got a
   wrong PIN accepted on AArch64 and Thumb-2. Fault injection found it. The check is now "trap
   unless the copy equals the negated copy of the inverse". (`compares.c`, `compares.ll`)

The same pass corrected the README, which said this project copies the operands before the
branch and gives each check its own trap block, as GCC does. It copies them on the edges and uses
one trap block per function.

## Random programs

`eval/difftest.py` builds each program plain and with `fi-harden<all>`, runs both, and requires
the same output and the same exit code, so a hardened run never traps. Two generators:

- `eval/gen.py` writes programs dense in compares: as branch conditions, stored, added into values,
  as `select` conditions, in `&&` and `||` chains, `switch`es and loops; signed and unsigned from
  8 to 64 bits, pointer compares, and `float` and `double` compares against NaN and infinity.
- Csmith 2.3.0 adds what `gen.py` doesn't write: structs, unions, bitfields, `goto`, pointers to
  pointers and volatile accesses. It writes no floating point; `gen.py` does.

A program counts only if a UBSan build runs it cleanly in under 10 s. Configurations: x86-64 at
`-O0` and `-O2`, and AArch64 and Thumb-2 Linux at `-O2` (cross-linked with gcc, run under
qemu-user).

| Generator | Seeds | Programs kept | Runs (4 configurations each) | Identical | Differ |
|---|---|---|---|---|---|
| `gen.py` | 1-200 | 200 | 800 | 800 | 0 |
| Csmith 2.3.0 | 1-120 | 106 (14 rejected for UB or time) | 424 | 424 | 0 |

The tool catches what it's for. With the plugin changed so that compares' users read the negated
value, or so that every check traps, both seeds it was tried on failed at x86-64 `-O0` and `-O2`
(a different checksum; exit -4, SIGILL from `ud2`).

`test/difftest.test` runs seeds 1 to 10 at `-O0` and `-O2` on every `check-fi`, and
`test/difftest-csmith.test` runs Csmith seeds 1 to 5 when `csmith` is installed (CI installs it).

```sh
eval/difftest.py build/FIHarden.so 1 200 native-O0 native-O2 a64-O2 t2-O2
eval/difftest.py --csmith build/FIHarden.so 1 120 native-O0 native-O2 a64-O2 t2-O2
```

## compiler-rt's builtins

compiler-rt's `lib/builtins` is integer and floating-point support code (division, shifts,
conversions, comparisons with NaN handling), full of compares. `eval/builtins.sh` builds every C
source that compiles for the target twice, plain and with `fi-harden<all>`, into two libraries,
links each unit test in `test/builtins/Unit` against each, and compares output and exit code.

| Build | Unit tests identical | Differ | Linked hardened builtins |
|---|---|---|---|
| x86-64 `-O0` | 224 | 0 | 158 |
| x86-64 `-O2` | 224 | 0 | 158 |
| AArch64 `-O2` | 221 | 0 | 162 |
| Thumb-2 `-O2` | 186 | 0 | 98 |

*Linked hardened builtins*: tests whose link map shows code from the hardened library; the others
are satisfied by libgcc. Natively the tests run with ASLR off, since one prints a stack address,
and assertion messages have the executable's name taken out: on Thumb-2 two tests fail the same
assertion in both builds (qemu-user rejects the cache-flush syscall), and the messages differed
only in the name.

```sh
eval/builtins.sh build/FIHarden.so ../llvm-project/compiler-rt native O2   # or O0; a64, t2
```

## LLVM's test corpus

LLVM's own tests are a large supply of unusual IR. `eval/corpus.sh` hardens one file and reports
OK, FAIL, or SKIP when LLVM fails on the file without the plugin too.

**Transforms**: every `.ll` under `llvm/test/Transforms`, hardened with `all` by LLVM 23's `opt`
with `-verify-each` (see the top for why not an assertions build), in three pipelines: hardening alone with `trap=call`;
after `-O2`, where clang runs it; and before `-O2`, so `-O2` has to cope with hardened IR.

| Pipeline | OK | Skipped | Failed |
|---|---|---|---|
| `fi-harden<all;trap=call>` | 12,479 | 178 | 0 |
| `default<O2>,fi-harden<all>`, the order clang uses | 12,450 | 207 | 0 |
| `fi-harden<all>,default<O2>` | 12,447 | 207 | 3, all LLVM's |

*Skipped*: LLVM fails on the file without the plugin too, mostly tests newer than LLVM 23.

The three failures, all with `-O2` run on hardened IR, an order clang never uses:

- **`LoopStrengthReduce/funclet.ll`: an LLVM bug.** IndVarSimplify sinks a loop invariant into an
  exit block that is a `catchswitch`, which has no insertion point. The hardened IR passes the
  verifier, and `opt -O2` crashes on it with no plugin loaded: LLVM 23 segfaults, and an
  assertions-enabled trunk asserts in `IndVarSimplify::sinkUnusedInvariants`.
- **`JumpThreading/update-bpi-bfi-unfold-select.ll`: an LLVM 23 bug, fixed in trunk.**
  JumpThreading divides by zero unfolding a `select` whose branch weights are both 0. LLVM 23
  crashes on the hardened IR without the plugin; trunk, where this test arrived with the fix,
  doesn't.
- **`LoopUnroll/debug-and-remarks.ll`: out of memory, as LLVM's own limit allows.** A loop marked
  `unroll.full` runs 1,000,001 times, one more than the cap on full unrolling under that pragma.
  Hardening changes the loop's shape, `-O2` peels one iteration, and the 1,000,000 left are
  within the cap, so LoopUnroll copies the body a million times. Lowering
  `-pragma-unroll-full-max-iterations` by one stops it.

**CodeGen**: every `.ll` directly in `llvm/test/CodeGen/AArch64`, `ARM` and `Thumb2`, hardened, then
lowered with `llc -O2` (LLVM 23), with the directory's triple for files that have none.

| Directory | Files | OK | Skipped | Failed |
|---|---|---|---|---|
| AArch64 | 3,070 | 2,219 | 851 | 0 |
| ARM | 1,417 | 1,265 | 150 | 2 |
| Thumb2 | 474 | 431 | 43 | 0 |

Most skips are tests that need an `-mattr` or flags from their RUN line, which `corpus.sh` doesn't
pass. The two ARM failures are the same case: `2009-08-26-ScalarToVector.ll` and
`2009-08-29-ExtractEltf32.ll` call NEON intrinsics and are run with `-mattr=+neon`. Without NEON,
the plain file still lowers only because the NEON result feeds a compare with `undef` that folds
away, so the operation is dead; the re-check's copy keeps it alive and llc can't legalise it. With
`-mattr=+neon`, both hardened files lower.

```sh
find ../llvm-project/llvm/test/Transforms -name '*.ll' | PASSES='default<O2>,fi-harden<all>' \
  nice -n 19 xargs -P 3 -I{} eval/corpus.sh opt build/FIHarden.so {} | cut -d' ' -f1 | sort | uniq -c
ls ../llvm-project/llvm/test/CodeGen/AArch64/*.ll | sed 's/$/ aarch64-linux-gnu/' |
  nice -n 19 xargs -P 3 -L1 eval/corpus.sh llc build/FIHarden.so | cut -d' ' -f1 | sort | uniq -c
```

## Fault injection

`eval/pin.c` is a PIN check with two marked functions: `verify_pin`, a FISSC-style byte loop that
clears a flag (B's case at `-O2`, where the flag becomes a compare's value), and `auth`, an early
exit on the first mismatch (A's case). The attacker enters a wrong PIN; the program prints GRANTED
or DENIED. `eval/inject.py` patches the linked binary, one fault per run: every instruction of the
function skipped (replaced by a NOP), and every conditional branch and IT block inverted. Each
mutant runs under qemu-user. Only instructions inside the hardened function are faulted.

Each cell: the faults that got the wrong PIN accepted, of all single faults tried, and how many
of those faults trapped (the check fired). Without `trap=call`, Thumb-2's trap is `udf`, which dies
of SIGILL like a crash, so it has no trapped count.

| Build | `verify_pin` | `auth` |
|---|---|---|
| AArch64 `-O2`, plain | 2 of 9 | 2 of 22 |
| AArch64 `-O2`, hardened | **0** of 25 (8 trapped) | **0** of 57 (13 trapped) |
| AArch64 `-O2`, `trap=call` | **0** of 27 (8 trapped) | **0** of 59 (13 trapped) |
| Thumb-2 `-O2`, plain | 1 of 20 | 1 of 24 |
| Thumb-2 `-O2`, hardened | **0** of 74 | **0** of 80 |
| Thumb-2 `-O2`, `trap=call` | **0** of 74 (33 trapped) | **0** of 80 (19 trapped) |
| AArch64 `-O0`, plain | 8 of 32 | 9 of 33 |
| AArch64 `-O0`, hardened | 3 of 58 (21 trapped) | 3 of 59 (19 trapped) |
| AArch64 `-O0`, `trap=call` | 3 of 62 (21 trapped) | 2 of 63 (18 trapped) |
| Thumb-2 `-O0`, plain | 9 of 35 | 10 of 37 |
| Thumb-2 `-O0`, hardened | 6 of 63 | 6 of 65 |
| Thumb-2 `-O0`, `trap=call` | 6 of 64 (18 trapped) | 6 of 66 (15 trapped) |

At `-O2`, no single fault inside a hardened function gets a wrong PIN accepted, on either target;
unhardened, one or two per function do. At `-O0`, hardening cuts them from 8 to 10 per function to
2 to 6, and every one left is data flow: a skipped store or load of a local (the loop counter, the
flag, the return value) or of the constant 0 the flag is set to. At `-O0` every value goes through
memory between statements, and neither function has a compare used as a value, so B has nothing to
check. Data-flow duplication would cover these.

```sh
clang --target=aarch64-linux-gnu -O2 -fpass-plugin=build/FIHarden.so -c eval/pin.c -o pin.o
aarch64-linux-gnu-gcc pin.o -o pin
eval/inject.py a64 pin verify_pin -- qemu-aarch64-static -L /usr/aarch64-linux-gnu pin v 9
```

`pin v 9` runs `verify_pin`, `pin a 9` runs `auth`, both with a wrong last digit. For Thumb-2, use
`--target=armv7a-linux-gnueabihf -mthumb`, `arm-linux-gnueabihf-gcc`, `qemu-arm-static -L
/usr/arm-linux-gnueabihf` and `inject.py t2`.

## Not covered

- **The fault-free path only**, for the differential tests: they show hardening changes nothing
  when no fault happens, not that the checks catch faults.
- **Faults outside the hardened function**, double faults and physical glitches. Register bit
  flips on a bare-metal Cortex-M3, code size and instruction counts are in
  [RESULTS.md](RESULTS.md).
- **IPO clones** (function specialisation, hot/cold splitting) would be unannotated and
  unhardened; none appeared in the test programs at `-O2` or `-O3`.
- **`undef` operands.** A compare with an `undef` operand keeps it as an immediate on both sides,
  and the backend may pick different values for each (UB input anyway).

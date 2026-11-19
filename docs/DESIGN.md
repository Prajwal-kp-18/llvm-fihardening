# Design

How fi-harden works, why each part is the way it is, what was considered and left out, and what
it doesn't protect. The tests that pin a claim are named in parentheses;
[VERIFICATION.md](VERIFICATION.md) has the evidence beyond the lit suite.

## Overview

```
clang -O2 -fpass-plugin=FIHarden.so
  PipelineStart   KeepOutOfLine: marked functions get noinline
  ...             the whole IR pipeline: inliner, GVN, SimplifyCFG, ...
  OptimizerLast   fi-harden: select functions; per function A (branches), then B (compares)
  ...             globaldce, constmerge, cg-profile, rel-lookup-table-converter,
                  lower-comment-string, annotation-remarks
  backend         CodeGenPrepare, SelectionDAG, MachineCSE, branch folding, if-conversion
```

| File | Part |
|---|---|
| `lib/Selection.cpp` | Which functions to harden, and which instructions to leave alone |
| `lib/OpaqueCopy.cpp` | The opaque copy, the barrier everything else relies on |
| `lib/Check.cpp` | The check (compare, branch) and the function's trap block |
| `lib/BranchHardening.cpp` | Countermeasure A: re-check both edges of a conditional branch |
| `lib/CompareHardening.cpp` | Countermeasure B: check a compare's value against its inverse |
| `lib/FIHarden.cpp` | Options, the passes, and where they're registered in the pipeline |

`fi-harden` is a module pass because selection reads the module's `llvm.global.annotations`. It's
a *required* pass, so it also runs at `-O0` and on `optnone` functions. Three more passes test the
layers on their own: `fi-harden-skips` reports what the skip rules leave alone, `fi-harden-copies`
runs every compare on opaque copies, and `fi-harden-checks` turns hand-written
`fi.check(i1, i1)` calls into checks. Every decision is a remark: `Selected`, `Branch` and
`Compare` when something is hardened, `Skipped` and `Switch` when it isn't.

## Choosing what to harden

A function is hardened when it's marked `__attribute__((annotate("fi_harden")))`, named in the
`allowlist=` file, or when `all` is given. The allowlist has one IR name per line (mangled for
C++), `#` comments, and names missing from the module are fine, so one list serves every source
file. Declarations and the trap handler `fi_trap` are never hardened: a check in the handler
would trap into itself. (`selection.ll`)

Hardening is opt-in because real users harden `verify_pin`, not `printf`, and the overhead should
stay where the decisions are. GCC hardens every function; `all` does that here, mostly for testing.

Under clang, marked and allowlisted functions get `noinline` at PipelineStart. fi-harden runs
after the inliner, and once a marked function is inlined into an unmarked caller nothing marks
the instructions that came from it, so its decision would run unhardened there. A marked
`always_inline` function is an error, since it asks for the opposite. With `all` inlining is left
alone, because every caller is hardened too. (`inline.c`)

The countermeasures are listed by name (`branches`, `compares`); naming none means all of them.
The allowlist is a pass parameter, not a `cl::opt`, because opt in LLVM 24 parses its options
before it loads plugins. Under clang the same parameters go through `-mllvm -fi-harden=a,b`.
(`params.ll`, `clang.c`)

## What countermeasures leave alone

A countermeasure never duplicates or re-evaluates, in order: EH pads, `invoke`, `callbr`,
`va_arg`, atomics, volatile accesses, compares whose operands have no opaque copy (vectors, values
over 64 bits), anything with side effects, and anything that reads or writes memory. Hardening must
not change what a fault-free run does, and the old pass broke programs exactly here: an atomic
increment ran twice, `va_arg` advanced twice, a volatile MMIO register was read twice, and a check
landed before a `landingpad`. The first seven are absolute; an exception for, say, ordinary loads
would go between them and the last two. A check on a loaded value copies the value; it never loads
it again.
(`test/defects/`)

Every skip emits a missed remark with its reason, so nothing is left out silently.
`-passes=fi-harden-skips` lists them for a whole file.

## Opaque copies

An opaque copy is `call iN asm sideeffect "", "=r,0"(iN %x)`: an empty asm whose output is tied to
its input register. It's GCC's `detach_value()` and OpenTitan's `launder32()`. No pass can prove a
copy equal to `%x` or to another copy, so a check that compares copies isn't folded to `true` or
merged with the original compare. (`opaque-copy.ll`)

- **Types.** Pointers go in as they are. Integers and floating point go in as an integer of
  power-of-two width, at least 8 bits: x86 can't allocate a register for an `i17`. Nothing over 64
  bits and no vectors: wider operands span several registers, and AArch64 didn't keep all of an
  `i128`. Compares on those are skipped with a remark.
- **`sideeffect`.** GCC's barrier isn't volatile. OpenTitan saw a non-volatile barrier merged during
  register allocation, so this one is. Without it, LLVM 23 still keeps every check, but schedules
  the copies away from them, and `compares.c`'s assembly checks fail.
- **It hides the output, not the input.** A pass that runs after a copy is inserted can still
  rewrite its operand. On the true edge of `br (a == b)`, GVN turns `copy(b)` into `copy(a)`, and
  the re-check then compares `a` with itself. That's why fi-harden runs after every IR
  optimisation. (`branches.ll`, prefix `LATE`)

Every barrier decision is in `OpaqueCopy.cpp`, so switching to something else (an intrinsic, say)
touches nothing else.

## The trap path

A check is a compare and a conditional branch to the function's trap block. There's no call on
the check path, so skipping one instruction can't disable it. The trap block is
`call @llvm.trap` followed by `unreachable`, which is legal because `llvm.trap` doesn't return. The
old pass put `unreachable` after a call that did return, so reaching it was UB and the optimiser
deleted the checks as dead. (`trap.ll`, `defects/11-unreachable.ll`)

`llvm.trap` lowers to `brk #1` on AArch64 and `udf` on Arm. With `trap=call`, the trap block first
calls `void fi_trap(void)` to log or reset; skipping that call, or returning from it, still reaches
the trap. [`runtime/fi_trap.c`](../runtime/fi_trap.c) is a reference handler that spins in two
loops, so one fault can't get it out. With `-g`, the trap block gets a line-0 location in the
function's scope, because a call to an `fi_trap` that has debug info needs one. (`debuginfo.c`)

There's one trap block per function, created on first use. GCC gives each check its own, but llc
tail-merges separate trap blocks into one anyway, and with one block, one per check or tail merging
off, llc -O2 keeps every compare and branch on AArch64 and Thumb-2. Merging does hurt in one place:
Thumb-2 if-conversion. When a check falls through into another and both are just `cmp` + `bne` to
the same trap, they become `cmp; it eq; cmpeq; bne`, a single branch for both that one skip
disables. A block holding inline asm can't be predicated, so each check's copies go in that
check's block. (`trap.ll`)

## Countermeasure A: conditional branches

After `br %c, T, F`, both edges are split. Each new block recomputes `%c` from opaque copies of its
operands and traps unless the result matches the edge: true on the way to `T`, false on the way to
`F`. It's GCC's `-fharden-conditional-branches`. It catches a skipped or inverted branch and a
corrupted flag, and it favours neither edge. (`branches.ll`, `branches.c`)

- The compare is re-emitted with the same predicate, so NaN needs no special case. Constant
  operands stay immediates.
- Any other condition (a load, a call, an argument, an `and` of compares) is checked through a copy
  of the `i1` itself. That still catches a skipped or inverted branch, but not a fault while
  computing the `i1`.
- Branches on a constant, or with the same block on both edges, have nothing to protect.
- `switch` is left alone with a remark, as GCC does: each case edge would need its own compare and
  the default edge one per case. `select` conditions are B's.

GCC copies the operands *before* the branch, because later optimisations "may use values inferred
from the compares". At OptimizerLast none run, so the copies stay on the edges, in the check
blocks, where if-conversion can't merge the checks.

In the backend, llc's SimplifyCFG hoists copies that both successors start with. That's harmless:
each of those checks continues to a successor of the original branch, never into another check.
Branch folding tail-merges identical check blocks (an unrolled loop's false edges can share one).
Each branch still reaches a re-check of the registers it compared, but there are fewer check
blocks in the binary than branches, which is why the audit counts decisions, not blocks.

At `-O2`, `a && b && c` reaches fi-harden as one `and` of compares, so A gives it the weaker
copied-`i1` check. Each compare in the `and` has a value use, so B checks it against its inverse.
With `branches` alone, a fault inside the condition (an AArch64 `ccmp` chain) goes unchecked.

## Countermeasure B: compares used as values

A compare whose result is used other than by a branch (returned, stored, a `select` condition, an
operand of an `and`) gets this right after it:

```llvm
%c      = icmp eq i32 %a, %b
%c.copy = opaque copy of %c          ; every non-branch user now reads this
%c.inv  = icmp ne i32 copy(%a), copy(%b)
%ok     = icmp eq i1 %c.copy, not(copy(%c.inv))
br i1 %ok, label %fi.ok, label %fi.trap
```

It's GCC's `-fharden-compares`. (`compares.ll`, `compares.c`)

- **Users read the copy.** Otherwise CodeGenPrepare sinks a fresh compare next to each user in
  another block. On AArch64, `return a == b` re-ran `cmp` + `cset` after the check, and skipping
  that `cset` went unchecked.
- **The check is "equal to the negated inverse", not "differs from the inverse".** For `i1`s
  they're the same, but the backend compares whole registers, often the very register that's
  returned, and only the first catches one left holding junk. With "differs", skipping the
  `and w0, w8, #1` that puts the boolean in the return register let a wrong PIN through on AArch64
  and Thumb-2. Fault injection found this (see VERIFICATION.md).
- **The inverse is negated through a copy.** Otherwise the backend folds the negation into the
  inverse compare, recomputes the original predicate, and a fault that zeroes both results passes.
- **NaN.** `getInversePredicate` gets NaN right: `olt`'s inverse is `uge`, so a NaN gives false,
  then true. Every FP predicate has an inverse in LLVM, so no FP compare is skipped for lack of one
  (GCC skips those when NaNs are honoured). The inverse keeps the compare's flags (`nnan`,
  `samesign`), so both lower the same way.
- **Branch uses stay A's**, and compares used only by branches are left to A, which runs first.
  A and B never check the same use, and A's re-checks aren't checked again.
- **Compares are processed last first.** Splitting a block after a compare then moves only the code
  up to the next check, not the rest of the block. A block of 16k compares took 12 s before this
  and takes 0.4 s now.

B protects computing the boolean and the register it's checked in. It doesn't protect moving the
value after the check, into another register or to memory: at `-O0` the result is stored to a
local and loaded back, and skipping that store or load still changes the outcome. That's data-flow
duplication's job, which isn't built yet.

## Running last, and surviving the backend

fi-harden runs at OptimizerLast, after every IR optimisation. In an experiment on LLVM 18, a
hand-written re-check run through `-O2` lost its meaning: the copies were hoisted into one, and GVN
replaced `b` with `a` on the edge where it knew `a == b`, so the "re-check" compared a copy of `a`
with `a`. With the same IR run only through `llc -O2`, the Thumb-2 output kept a genuine re-check.
(`branches.ll` `LATE` shows the GVN rewrite on LLVM 23.)

What still runs after it is pinned by `clang.c`: at `-O2`, `globaldce`, `constmerge`, `cg-profile`,
`rel-lookup-table-converter`, `lower-comment-string` and `annotation-remarks`; at `-O0`, only the
last two. None of them merges, folds or moves compares and branches. Then the backend:

| Backend step | What it would do to a check | Why it doesn't |
|---|---|---|
| SelectionDAG CSE, DAGCombine | Merge the re-check with the original, fold `x == x` | The copies are `INLINEASM` nodes it can't see through |
| CodeGenPrepare | Sink a fresh, unchecked compare next to a user | B's users read the checked copy |
| SimplifyCFG (in llc) | Hoist the copies both edges start with | Harmless, see A |
| Branch folding | Tail-merge identical check blocks and trap blocks | Each branch still reaches a re-check; the audit counts decisions |
| Thumb-2 if-conversion | Merge two checks into one predicated branch | Each check's block holds its copies, and inline asm can't be predicated |
| MachineCSE, register allocation | Merge identical copies | `sideeffect` asm |

`test/branches.c`, `compares.c` and `audit.c` check the result in AArch64 and Thumb-2 assembly
and objects at `-O0` and `-O2`. Their `-O0` inputs drop `optnone`, so llc optimises them: a check
that survives in an `optnone` function could still be optimised away in a real build. The old
suite never noticed, because clang `-O0` marks every function `optnone`; `optnone.ll` keeps the
inputs free of it.

**LTO.** With `-flto`, the compile step's OptimizerLast is followed by link-time optimisation,
and link-time GVN turned the true edge's `copy(b)` into `copy(a)`. `-flto` and `-flto=thin` are
refused when something would be hardened; a file with nothing marked still builds. (`clang.c`)
Supporting LTO means hardening in the link step instead: ThinLTO's backend runs OptimizerLast,
while full LTO's link step has its own last extension point (FullLinkTimeOptimizationLast).

## The binary audit

`eval/audit.py` checks that every check the remarks promise is in the object file. Each `Branch`
remark promises two checks (both edges) and each `Compare` remark one. Per function, it counts
conditional branches (and predicated returns) with an outcome that reaches the trap (`brk #1` or
`udf`, through unconditional branches, the trap block's prologue and `bl fi_trap`). A decision
whose two outcomes both reach a check first counts 2, even when tail merging made several
decisions share one check block. Every other check counts 1. It fails if a function counts fewer
than promised, or is missing. (`audit.c`, including objects that must fail it)

Simply counting branches to the trap doesn't work. llc tail-merges identical check blocks (in an
unrolled loop on Thumb-2, 9 branches shared 11 check instructions), `-O0` reaches the trap through a
`b` stub, Thumb-2 returns with `it ne; bxne lr` and falls through into the trap, and with
`trap=call` shrink-wrapping puts a prologue in the trap block.

It counts checks, not what they compare: a check weakened to compare a value with itself still
counts, which is why the assembly tests pin the shapes. It can't tell a check from the program's
own `__builtin_trap`, which can only make it count more.

## Considered and not done

| Idea | Why not, or not yet |
|---|---|
| Harden before the optimiser, as ASPIS does | GVN and SimplifyCFG undo the re-checks (see above) |
| Copy operands before the branch, as GCC does | Not needed at OptimizerLast, and copies on the edges keep each check's copies in its block |
| One trap block per check, as GCC does | llc tail-merges them anyway; one per function keeps every check |
| Call a handler and continue, as GlitchResistor does | Skipping the one `bl` disables the check; an inline trap has no call to skip |
| Re-check from volatile re-loads, as GlitchResistor does | Changes memory traffic (MMIO), covers loaded values only; opaque copies cover any value |
| Non-volatile asm barrier, as GCC uses | OpenTitan saw one merged during register allocation |
| Trap if the compare "differs from its inverse" | A skipped `and` left junk that still differed (see B) |
| Harden `switch` | Each case edge needs its own compare; left alone with a remark, as GCC does |
| Re-check each compare of an `&&` chain in A | B does it when `compares` is on; with `branches` alone it's open |
| Copies of vectors and values over 64 bits | Split into `i64` pieces if 128-bit compares (AArch64 `long double`) need hardening |
| Support `-flto` | Refused for now; harden in the link step to support it |
| Machine-level duplication after register allocation | `-fpass-plugin` only reaches the IR pipeline; this needs a pass in the target's codegen pipeline, an in-tree patch |
| An Alive2 proof that the fault-free hardened code refines the original | Not tried; the differential tests are the evidence instead |

## What it doesn't protect

- **One fault per run.** Each check is built to catch one fault. Two can defeat it: one to change
  the decision and one to skip the check's branch or the trap instruction. Double faults will be
  measured, not claimed.
- **Faults before the copies.** The re-check recomputes from the same operands. A fault that
  corrupts them earlier (a faulted load of a PIN digit, a corrupted argument) gives both the
  original and the re-check the same wrong input.
- **Moving a checked value.** After B's check, the value can still be corrupted on its way to
  another register or to memory; at `-O0` that's the store to and load from a local.
- **Code that isn't marked.** Only marked functions are hardened. If an unmarked caller does
  `if (verify_pin(p)) grant();`, its branch is unprotected: mark the function that makes the
  decision.
- **What's skipped.** `switch`, compares on vectors or values over 64 bits, and branch conditions
  that aren't compares (checked through a copy of the `i1` only). A compare with an `undef` operand
  keeps it as an immediate on both sides, and the backend may pick different values (UB input
  anyway).
- **Clones.** IPO clones, such as function specialisation and hot/cold splitting, would be
  unannotated and unhardened. None appeared in the test programs at `-O2` or `-O3`.
- **Side channels.** Computing a secret-dependent compare again, and its inverse, may leak more
  through power or EM (Cojocar, Papagiannopoulos and Timmers, CARDIS 2017). Out of scope, and not
  measured.
- **Not measured yet:** physical glitches and double faults. Simulated skips and register bit
  flips on a Cortex-M3, and the code-size and instruction overhead, are in
  [RESULTS.md](RESULTS.md).

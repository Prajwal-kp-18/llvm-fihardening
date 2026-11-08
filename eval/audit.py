#!/usr/bin/env python3
"""Binary audit: did every check fi-harden inserted reach the object file?

usage: audit.py OBJECT REMARKS.yaml

REMARKS.yaml is clang's -fsave-optimization-record output for OBJECT. Each
hardened branch (remark Branch) promises a check on both edges, each hardened
compare (remark Compare) one check. The audit disassembles OBJECT with
llvm-objdump and, per function, counts the checks still there:

- A check is a conditional branch (or predicated return) with an outcome that
  reaches the trap: brk #0x1 on AArch64, udf #254 (trap) on Thumb-2, through
  unconditional branches and the trap block's own prologue and bl fi_trap.
- Any other conditional branch is a decision. If both its outcomes reach a
  check before any other branch, call or return, it was re-checked on both
  edges: it counts 2. llc tail-merges identical check blocks, so several
  decisions can share one; each still counts 2.
- Every other check (a compare's) counts 1.

It fails if a function counts fewer than its remarks promise, or a hardened
function is missing. It counts checks, not what they compare: one weakened to
compare a value with itself still counts, so the asm tests in test/ pin the
shapes. And it can't tell a check from the program's own __builtin_trap,
which can only make it count more.
"""

import re
import subprocess
import sys

CC = r"(eq|ne|hs|cs|lo|cc|mi|pl|vs|vc|hi|ls|ge|lt|gt|le)"
CONDITIONAL = re.compile(rf"(b\.{CC}|b{CC}(\.w)?|cbn?z|tbn?z|bx{CC}|pop{CC}(\.w)?)$")
JUMP = re.compile(r"b(\.w)?$")
TRAP = re.compile(r"brk$|trap$")
TARGET = re.compile(r"0x([0-9a-f]+) <")
SITES = {"Branch": 2, "Compare": 1}


def promised(remarks):
    """{function: checks its fi-harden remarks promise}."""
    want = {}
    for doc in open(remarks).read().split("\n--- "):
        keys = dict(re.findall(r"^(Pass|Name|Function):\s+'?([^'\n]*)'?$", doc, re.M))
        if keys.get("Pass") == "fi-harden" and "Function" in keys:
            fn = keys["Function"]
            want[fn] = want.get(fn, 0) + SITES.get(keys["Name"], 0)
    return want


def disassemble(obj):
    """{function: [(address, mnemonic, operands, relocation)]}."""
    out = subprocess.run(["llvm-objdump", "-d", "-r", "--no-show-raw-insn", obj],
                         capture_output=True, text=True, check=True).stdout
    funcs, insns = {}, None
    for line in out.splitlines():
        if m := re.match(r"[0-9a-f]+ <(.+)>:$", line):
            insns = funcs[m[1]] = []
        elif insns and (m := re.match(r"\s+[0-9a-f]+:\s+R_\S+\s+(\S+)", line)):
            insns[-1][3] = m[1]
        elif insns is not None and (m := re.match(r"\s+([0-9a-f]+):\s+(\S+)\s*(.*)", line)):
            insns.append([int(m[1], 16), m[2], m[3], ""])
    return funcs


def count(insns):
    """Checks in one function, counted as the module docstring says."""
    at = {a: i for i, (a, *_) in enumerate(insns)}

    def target(i):
        m = TARGET.findall(insns[i][2])
        return int(m[-1], 16) if m and int(m[-1], 16) in at else None

    def transfers(i):
        mn, ops = insns[i][1], insns[i][2]
        return (CONDITIONAL.match(mn) or JUMP.match(mn) or mn in ("ret", "br", "bl", "blr", "blx")
                or (mn == "bx") or (mn.startswith("pop") and "pc" in ops))

    def walk(addr, stop):
        """The index where straight-line code from addr meets stop or a transfer."""
        seen = set()
        while addr in at and addr not in seen:
            seen.add(addr)
            i = at[addr]
            mn = insns[i][1]
            if stop(i):
                return i
            if JUMP.match(mn) and target(i) is not None:
                addr = target(i)
            elif mn == "bl" and "fi_trap" in insns[i][2] + insns[i][3]:
                addr = insns[i + 1][0] if i + 1 < len(insns) else None
            elif transfers(i):
                return i
            else:
                addr = insns[i + 1][0] if i + 1 < len(insns) else None
        return None

    def outcomes(i):
        nxt = insns[i + 1][0] if i + 1 < len(insns) else None
        return [target(i), nxt]

    def reaches_trap(addr):
        i = walk(addr, lambda i: bool(TRAP.match(insns[i][1])))
        return i is not None and bool(TRAP.match(insns[i][1]))

    conditional = [i for i, x in enumerate(insns) if CONDITIONAL.match(x[1])]
    checks = {i for i in conditional if any(reaches_trap(a) for a in outcomes(i))}
    reached, covered = set(), 0
    for i in conditional:
        if i in checks:
            continue
        firsts = [walk(a, lambda j: CONDITIONAL.match(insns[j][1])) for a in outcomes(i)]
        if all(j in checks for j in firsts):
            covered += 1
            reached.update(firsts)
    return 2 * covered + len(checks - reached)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    want, funcs = promised(sys.argv[2]), disassemble(sys.argv[1])
    if not want:
        sys.exit(f"no fi-harden remarks in {sys.argv[2]}")
    failed = False
    for fn, n in sorted(want.items()):
        got = count(funcs[fn]) if fn in funcs else None
        ok = got is not None and got >= n
        failed |= not ok
        print(f"{'ok  ' if ok else 'FAIL'} {fn}: {n} promised, "
              f"{'missing from the object' if got is None else f'{got} found'}")
    sys.exit(failed)


if __name__ == "__main__":
    main()

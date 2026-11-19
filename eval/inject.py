#!/usr/bin/env python3
"""Single-fault injection on one function of a linked AArch64/Thumb-2 binary.

usage: inject.py a64|t2 EXE FUNCTION -- RUN-COMMAND...   (EXE replaced by each mutant)
For every instruction of FUNCTION: skip it (NOP), and, if it's a conditional
branch or IT, invert its condition. Runs each mutant and prints a tally of
outcomes: granted (the program printed GRANTED: the attack worked), denied,
trapped (it printed TRAPPED, exited 77, or died of SIGTRAP), crashed (anything
else, which includes Thumb-2's udf trap without trap=call).

ponytail: patches a Linux binary and reruns it under qemu-user, one fault per
run, faults inside FUNCTION only. Register bit flips, double faults and a
bare-metal Cortex-M target need a real fault simulator (Unicorn).
"""
import collections, os, re, stat, subprocess, sys, tempfile

isa, exe, fn = sys.argv[1:4]
cmd = sys.argv[sys.argv.index("--") + 1:]
dis = subprocess.run(["llvm-objdump", "-d", exe], capture_output=True, text=True, check=True).stdout
sec = subprocess.run(["llvm-readelf", "-S", "-W", exe], capture_output=True, text=True, check=True).stdout
m = re.search(r"\]\s+\.text\s+PROGBITS\s+([0-9a-f]+)\s+([0-9a-f]+)", sec)
assert m, f"no .text in {exe}"
text_addr, text_off = int(m[1], 16), int(m[2], 16)
insns, inside = [], False
for line in dis.splitlines():
    if re.match(rf"[0-9a-f]+ <{re.escape(fn)}>:$", line):
        inside = True
    elif inside and not line.strip():
        break
    elif inside and (mm := re.match(r"\s+([0-9a-f]+):\s+((?:[0-9a-f]{4,8} )+)\s*(\S+)\s*(.*)", line)):
        insns.append((int(mm[1], 16), [int(h, 16) for h in mm[2].split()], mm[3], mm[4].strip()))
assert insns, f"{fn} not found"
orig = open(exe, "rb").read()

def encode(words):
    b = b""
    for w in words:
        b += w.to_bytes(4 if isa == "a64" else 2, "little")
    return b

def mutants(words):
    """(kind, patched words) for one instruction."""
    if isa == "a64":
        w = words[0]
        yield "skip", [0xd503201f]
        if (w & 0xff000010) == 0x54000000 and (w & 0xe) != 0xe:
            yield "invert", [w ^ 1]                      # b.cond
        elif (w & 0x7e000000) in (0x34000000, 0x36000000):
            yield "invert", [w ^ (1 << 24)]              # cbz/cbnz, tbz/tbnz
    else:
        h = words[0]
        yield "skip", [0xbf00] * len(words) if len(words) == 1 else [0xf3af, 0x8000]
        if len(words) == 1 and (h & 0xf000) == 0xd000 and (h & 0x0e00) != 0x0e00:
            yield "invert", [h ^ 0x0100]                 # b<c> narrow
        elif len(words) == 1 and (h & 0xf500) == 0xb100:
            yield "invert", [h ^ 0x0800]                 # cbz/cbnz
        elif len(words) == 1 and (h & 0xff00) == 0xbf00 and h & 0xf:
            mask = h & 0xf; low = mask & -mask           # it: invert every slot
            yield "invert", [h ^ 0x10 ^ (mask & ~((low << 1) - 1) & 0xf)]
        elif len(words) == 2 and (h & 0xf800) == 0xf000 and (words[1] & 0xd000) == 0x8000 and (h & 0x0380) != 0x0380:
            yield "invert", [h ^ 0x0040, words[1]]       # b<c>.w

tally = collections.Counter(); wins = []
with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "m")
    for addr, words, mn, ops in insns:
        for kind, new in mutants(words):
            off = addr - text_addr + text_off
            data = orig[:off] + encode(new) + orig[off + len(encode(words)):]
            open(path, "wb").write(data); os.chmod(path, stat.S_IRWXU)
            try:
                r = subprocess.run([path if c == exe else c for c in cmd], capture_output=True, text=True, timeout=5)
                out, rc = r.stdout, r.returncode
            except subprocess.TimeoutExpired:
                out, rc = "", "timeout"
            o = ("granted" if "GRANTED" in out else "denied" if "DENIED" in out else
                 "trapped" if "TRAPPED" in out or rc in (77, 133, -5) else "crashed")
            tally[kind, o] += 1
            if o == "granted":
                wins.append(f"{kind} {addr:#x}: {mn} {ops}")
print(f"{len(insns)} instructions; " + ", ".join(f"{k} {o}={n}" for (k, o), n in sorted(tally.items())))
for w in wins:
    print("  ATTACK WORKS:", w)

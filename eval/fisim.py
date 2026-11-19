#!/usr/bin/env python3
"""Single-fault simulator for Cortex-M programs built on eval/cm (Unicorn + Capstone).

usage: fisim.py [-v] ELF FUNC

Runs ELF from reset until it reaches fi_done (the golden run), then once per
fault in the instructions executed from FUNC's entry until it returns, its
callees included:
  skip  the instruction doesn't execute (as if it were a NOP);
  flip  right after it, one bit of a register it wrote is inverted: r0-r12,
        sp and lr (32 bits each), and the N, Z, C and V flags.
Each run ends as one of:
  trap     a udf (llvm.trap, __builtin_trap) or fi_trap was reached
  crash    an invalid access or instruction, or a CPU fault (fi_fault)
  timeout  10x the golden run's instructions without finishing
  ret=N    main returned N
Prints one line per fault model with the count of each outcome. -v also lists
each run whose outcome isn't the golden one. The golden run's instruction
count is the cycle proxy for overhead.

Which registers an instruction writes comes from Capstone, and versions
disagree on a few (flags, implicit registers), so flip counts can differ
between Capstone versions; skip counts don't.

ponytail: re-runs from reset for every fault (O(n^2) in the trace length);
fine for VerifyPIN-sized code. Snapshot at the window start if it gets slow.
"""
import collections
import sys

from capstone import CS_ARCH_ARM, CS_MODE_MCLASS, CS_MODE_THUMB, Cs
from elftools.elf.elffile import ELFFile
from unicorn import UC_ARCH_ARM, UC_ERR_INSN_INVALID, UC_HOOK_CODE, UC_MODE_MCLASS, UC_MODE_THUMB
from unicorn import UC_PROT_EXEC, UC_PROT_READ, Uc, UcError
from unicorn import arm_const as A

FLASH, FLASH_SIZE, RAM, RAM_SIZE = 0, 256 << 10, 0x20000000, 64 << 10
NOP = {2: b"\x00\xbf", 4: b"\xaf\xf3\x00\x80"}  # nop, nop.w
REGS = {f"r{i}": getattr(A, f"UC_ARM_REG_R{i}") for i in range(13)}
REGS.update(sb=A.UC_ARM_REG_R9, sl=A.UC_ARM_REG_R10, fp=A.UC_ARM_REG_R11, ip=A.UC_ARM_REG_R12,
            sp=A.UC_ARM_REG_SP, lr=A.UC_ARM_REG_LR)
FLAGS = {"N": 31, "Z": 30, "C": 29, "V": 28}


class Sim:
    def __init__(self, path):
        with open(path, "rb") as f:
            elf = ELFFile(f)
            self.segs = [(s["p_paddr"], s.data()) for s in elf.iter_segments()
                         if s["p_type"] == "PT_LOAD" and s["p_filesz"]]
            self.sym = {s.name: (s["st_value"] & ~1, s["st_size"])
                        for s in elf.get_section_by_name(".symtab").iter_symbols() if s.name}
        uc = self.uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_MCLASS)
        uc.ctl_set_cpu_model(A.UC_CPU_ARM_CORTEX_M3)
        uc.mem_map(FLASH, FLASH_SIZE, UC_PROT_READ | UC_PROT_EXEC)  # a store to flash crashes
        uc.mem_map(RAM, RAM_SIZE)
        for addr, data in self.segs:
            uc.mem_write(addr, data)
        self.vec = [int.from_bytes(uc.mem_read(4 * i, 4), "little") for i in (0, 1)]
        self.ctx = uc.context_save()
        self.done = self.sym["fi_done"][0]
        stops = [self.sym[s][0] for s in ("fi_trap", "fi_fault") if s in self.sym]
        for a in stops:
            uc.hook_add(UC_HOOK_CODE, lambda uc, *_: uc.emu_stop(), begin=a, end=a)
        self.cs = Cs(CS_ARCH_ARM, CS_MODE_THUMB | CS_MODE_MCLASS)
        self.cs.detail = True

    def pc(self):
        return self.uc.reg_read(A.UC_ARM_REG_PC)

    def step(self, count):
        if count > 0 and self.pc() != self.done:
            self.uc.emu_start(self.pc() | 1, self.done, count=count)

    def run(self, at=None, fault=None, budget=10**6):
        """Outcome of a run with fault(uc, sim) applied at trace index `at`."""
        uc = self.uc
        uc.context_restore(self.ctx)
        uc.mem_write(RAM, bytes(RAM_SIZE))
        uc.reg_write(A.UC_ARM_REG_SP, self.vec[0])
        uc.reg_write(A.UC_ARM_REG_PC, self.vec[1])
        try:
            if fault:
                self.step(at)
                fault(self)
                budget -= at + 1
            self.step(budget)
        except UcError as e:
            # An invalid instruction was fetched, so the PC is mapped. udf is 0xdeXX.
            udf = e.errno == UC_ERR_INSN_INVALID and uc.mem_read(self.pc() + 1, 1)[0] == 0xde
            return "trap" if udf else "crash"
        pc = self.pc()
        if pc == self.done:
            return f"ret={int.from_bytes(uc.mem_read(self.sym['fi_result'][0], 4), 'little', signed=True)}"
        return "trap" if pc == self.sym.get("fi_trap", (None,))[0] else \
            "crash" if pc == self.sym.get("fi_fault", (None,))[0] else "timeout"

    def golden(self, func):
        """(outcome, trace, window): trace is [(addr, size)], window the trace
        indices from func's entry until it returns."""
        trace, lr = [], []
        entry = self.sym[func][0]
        h = [self.uc.hook_add(UC_HOOK_CODE, lambda uc, a, size, _: trace.append((a, size))),
             self.uc.hook_add(UC_HOOK_CODE, lambda uc, *_: lr.append(uc.reg_read(A.UC_ARM_REG_LR)),
                              begin=entry, end=entry)]
        out = self.run()
        for x in h:
            self.uc.hook_del(x)
        first = next(i for i, (a, _) in enumerate(trace) if a == entry)
        # Its first return: LR at entry (a tail call doesn't return after the branch).
        last = next(i for i in range(first, len(trace)) if trace[i][0] == lr[0] & ~1)
        return out, trace, range(first, last)


def skip(addr, size):
    def f(sim):
        uc = sim.uc
        orig = bytes(uc.mem_read(addr, size))
        uc.mem_write(addr, NOP[size])
        uc.ctl_remove_cache(addr, addr + size)
        try:
            sim.step(1)
        finally:
            uc.mem_write(addr, orig)
            uc.ctl_remove_cache(addr, addr + size)
    return f


def flip(reg, bit):
    def f(sim):
        sim.step(1)
        uc = sim.uc
        r = A.UC_ARM_REG_APSR if reg in FLAGS else REGS[reg]
        uc.reg_write(r, uc.reg_read(r) ^ (1 << bit))
    return f


def written(sim, addr, size):
    """(reg, bit) pairs a flip after this instruction can hit."""
    insn = next(sim.cs.disasm(bytes(sim.uc.mem_read(addr, size)), addr))
    for r in insn.regs_access()[1]:
        name = insn.reg_name(r)
        if name in REGS:
            yield from ((name, b) for b in range(32))
        elif name in ("cpsr", "apsr", "apsr_nzcv"):
            yield from FLAGS.items()


def campaign(path, func, verbose=False):
    """({model: Counter(outcome)}, golden outcome, Sim, golden trace, window)."""
    sim = Sim(path)
    gold, trace, window = sim.golden(func)
    budget = 10 * len(trace)
    res = collections.defaultdict(collections.Counter)
    for i in window:
        addr, size = trace[i]
        faults = [("skip", skip(addr, size))]
        faults += [(f"flip {r}:{b}", flip(r, b)) for r, b in written(sim, addr, size)]
        for name, fault in faults:
            out = sim.run(i, fault, budget)
            res[name.split()[0]][out] += 1
            if verbose and out != gold:
                insn = next(sim.cs.disasm(bytes(sim.uc.mem_read(addr, size)), addr))
                print(f"  #{i} {addr:#x} {insn.mnemonic} {insn.op_str}: {name} -> {out}")
    return res, gold, sim, trace, window


def main():
    argv = sys.argv[1:]
    verbose = "-v" in argv
    argv = [a for a in argv if a != "-v"]
    if len(argv) != 2:
        sys.exit(__doc__)
    res, gold, _, trace, window = campaign(argv[0], argv[1], verbose)
    print(f"golden: {gold}, {len(trace)} instructions, {len(window)} in {argv[1]}")
    for model, c in res.items():
        print(f"{model}: {sum(c.values())} faults, " + ", ".join(f"{o} {k}" for o, k in sorted(c.items())))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Cross-checks eval/fisim.py's skip counts with ARMORY, an independent
exhaustive fault simulator for ARMv7-M with its own emulator (Hoffmann,
Schellenberg and Paar, TIFS 2021, github.com/emsec/arm-fault-simulator).

usage: armory.py [WORKDIR] ELF FUNC [ELF FUNC]...

For each ELF built on eval/cm, counts the single instruction skips in FUNC's
window (the functions it ran in the golden run) that make the program reach
fi_bad: ARMORY's "Transient Instruction Skip" against fisim.py's skip, run
from Reset_Handler in both. Builds ARMORY (a pinned commit, MIT) in WORKDIR
(default ./armory-work) on first use; needs git, meson, ninja and a C++17
compiler.
"""
import pathlib
import re
import subprocess
import sys

from unicorn import UC_HOOK_CODE

import fisim

REPO = "https://github.com/emsec/arm-fault-simulator.git"
COMMIT = "e292e2bd244dd708cec632052d60637037faec99"
# ARMORY's example main, cut down: one fault model, a fault is exploitable if it
# reaches a halting point (fi_bad), and the count goes to stdout.
MAIN = r"""
#include "armory_cli/armory_cli.h"
#include "armory_cli/fault_models.h"
#include <iostream>
using namespace armory;
int main(int argc, char** argv) {
    auto config = armory_cli::parse_arguments(argc, argv);
    Emulator emu(config.arch);
    emu.set_flash_region(config.flash.offset, config.flash.size);
    emu.set_ram_region(config.ram.offset, config.ram.size);
    for (const auto& s : config.binary) emu.write_memory(s.offset, s.bytes.data(), s.bytes.size());
    emu.write_register(Register::SP, config.ram.offset + config.ram.size);
    emu.write_register(Register::PC, config.start_address);
    emu.write_register(Register::LR, 0xFFFFFFFF);
    config.faulting_context.exploitability_model = nullptr;
    config.num_threads = 2;  // ARMORY's default is every core
    auto faults = armory_cli::find_exploitable_faults(
        emu, config, {std::make_pair(fault_models::instr_t_skip, 1)});
    std::cout << "EXPLOITABLE " << faults.size() << std::endl;
}
"""


def build(work):
    src = work / "armory"
    exe = src / "build" / "armory_example"
    if not src.exists():
        subprocess.run(["git", "clone", "-q", REPO, str(src)], check=True)
        subprocess.run(["git", "-C", str(src), "checkout", "-q", COMMIT], check=True)
    main = src / "src" / "main.cpp"
    if exe.exists() and main.read_text() == MAIN:
        return exe
    main.write_text(MAIN)
    if not (src / "build").exists():
        subprocess.run(["meson", "setup", "--buildtype=release", "build"], cwd=src, check=True,
                       stdout=subprocess.DEVNULL)
    subprocess.run(["meson", "compile", "-C", "build", "-j", "2"], cwd=src, check=True,
                   stdout=subprocess.DEVNULL)
    return exe


def armory(exe, elf, funcs, work):
    """ARMORY's exploitable skip count, faulting only inside funcs."""
    sim = fisim.Sim(elf)
    ranges = sorted((sim.sym[f][0], sim.sym[f][0] + sim.sym[f][1]) for f in funcs)
    ignore, at = [], fisim.FLASH
    for b, e in ranges + [(fisim.FLASH + fisim.FLASH_SIZE,) * 2]:
        if at < b:
            ignore += ["--ignore", hex(at), hex(b)]
        at = max(at, e)
    args = ["--armv7m", "--start", hex(sim.sym["Reset_Handler"][0] | 1),
            "--halt", "fi_bad", hex(sim.sym["fi_bad"][0]),
            "--flash", hex(fisim.FLASH), hex(fisim.FLASH_SIZE),
            "--ram", hex(fisim.RAM), hex(fisim.RAM_SIZE), "--timeout", "10000", *ignore]
    for i, (addr, data) in enumerate(sim.segs):
        f = work / f"seg{i}.bin"
        f.write_bytes(data)
        args += ["--section", str(f), hex(addr)]
    out = subprocess.run([str(exe), *args], capture_output=True, text=True, check=True).stdout
    return int(re.search(r"EXPLOITABLE (\d+)", out)[1])


def fisim_count(elf, func):
    """(fisim's skip count reaching fi_bad, the functions the window ran)."""
    sim = fisim.Sim(elf)
    _, trace, window = sim.golden(func)
    funcs = sorted({n for n, (a, s) in sim.sym.items() if s and n.isidentifier() and
                    any(a <= trace[i][0] < a + s for i in window)})
    bad = sim.sym["fi_bad"][0]
    hit = []
    sim.uc.hook_add(UC_HOOK_CODE, lambda *_: hit.append(1), begin=bad, end=bad)
    count = 0
    for i in window:
        hit.clear()
        sim.run(i, fisim.skip(*trace[i]), 10 * len(trace))
        count += bool(hit)
    return count, funcs


def main():
    argv = sys.argv[1:]
    work = pathlib.Path(argv.pop(0) if len(argv) % 2 else "armory-work").resolve()
    if not argv:
        sys.exit(__doc__)
    work.mkdir(exist_ok=True)
    exe = build(work)
    print("| ELF | Function | Skips | fisim.py: reach fi_bad | ARMORY: reach fi_bad |")
    print("|---|---|---|---|---|")
    for elf, func in zip(argv[::2], argv[1::2]):
        mine, funcs = fisim_count(elf, func)
        theirs = armory(exe, elf, funcs, work)
        sim = fisim.Sim(elf)
        n = len(sim.golden(func)[2])
        print(f"| {pathlib.Path(elf).name} | {', '.join(funcs)} | {n} | {mine} | {theirs} |",
              flush=True)


if __name__ == "__main__":
    main()

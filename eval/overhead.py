#!/usr/bin/env python3
"""Code-size and instruction overhead of hardening, on Embench kernels.

usage: overhead.py PLUGIN [WORKDIR]

Downloads Embench-IoT 1.0 into WORKDIR (default ./embench-work; it's
GPL-3.0, so it isn't in this repo) and builds crc32, matmult-int, nettle-aes
and nettle-sha256 for Cortex-M3 on eval/cm, with every function in the kernel
hardened. Embench's support code is built once, plain, with clang; only the
kernel's own file changes between rows. Prints, per kernel and build, the
kernel object's code bytes and the instructions executed in benchmark()
(eval/fisim.py, no faults), and their growth over the same compiler's plain
-O2 build. Every run must pass the kernel's own check.

Builds: clang -O2, plain and with fi-harden<all> A, B and A+B; and
arm-none-eabi-gcc -O2, plain and with -fharden-compares
-fharden-conditional-branches (if it's on PATH). clang (LLVM 23, the
plugin's) comes from PATH.
"""
import hashlib
import pathlib
import shutil
import subprocess
import sys
import tarfile
import urllib.request

from elftools.elf.elffile import ELFFile
from unicorn import UC_HOOK_CODE

import fisim

URL = "https://github.com/embench/embench-iot/archive/refs/tags/embench-1.0.tar.gz"
SHA256 = "ec188bfc2fc470bc096157e033a377d7f20ac34823c4473381c0f902d47a656b"
KERNELS = ["crc32", "matmult-int", "nettle-aes", "nettle-sha256"]
CM = pathlib.Path(__file__).with_name("cm")
CLANG = ["clang", "--target=thumbv7m-none-eabi", "-mcpu=cortex-m3"]
GCC = ["arm-none-eabi-gcc", "-mcpu=cortex-m3", "-mthumb"]
FLAGS = ["-O2", "-ffreestanding", "-fno-unwind-tables", "-DCPU_MHZ=1", "-DWARMUP_HEAT=0",
         "-isystem", str(CM / "include")]


def fetch(work):
    root = work / "embench-iot-embench-1.0"
    if root.exists():
        return root
    tgz = work / "embench-1.0.tar.gz"
    if not tgz.exists():
        urllib.request.urlretrieve(URL, tgz)
    if hashlib.sha256(tgz.read_bytes()).hexdigest() != SHA256:
        sys.exit(f"{tgz}: wrong sha256")
    with tarfile.open(tgz) as t:
        t.extractall(work, filter="data")
    return root


def code_bytes(obj):
    with open(obj, "rb") as f:
        return sum(s["sh_size"] for s in ELFFile(f).iter_sections() if s["sh_flags"] & 4)  # SHF_EXECINSTR


def instructions(elf):
    """(outcome, instructions from start_trigger to stop_trigger)."""
    sim = fisim.Sim(elf)
    start, stop = sim.sym["start_trigger"][0], sim.sym["stop_trigger"][0]
    n, marks = [0], {}

    def hook(uc, addr, size, _):
        n[0] += 1
        if addr in (start, stop):
            marks[addr] = n[0]
    sim.uc.hook_add(UC_HOOK_CODE, hook)
    out = sim.run(budget=10**9)
    return out, marks[stop] - marks[start]


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    plugin = str(pathlib.Path(sys.argv[1]).resolve())
    work = pathlib.Path(sys.argv[2] if len(sys.argv) == 3 else "embench-work").resolve()
    work.mkdir(exist_ok=True)
    root = fetch(work)
    support = root / "support"
    inc = [f"-I{support}"]
    # Support code, the same in every build.
    objs = []
    for src in (CM / "start.c", CM / "libc.c", CM / "embench_board.c", support / "main.c",
                support / "beebsc.c"):
        obj = work / f"{src.stem}.o"
        subprocess.run([*CLANG, *FLAGS, "-fno-builtin", *inc, "-c", str(src), "-o", str(obj)],
                       check=True)
        objs.append(str(obj))

    harden = lambda c: [f"-fpass-plugin={plugin}", "-mllvm", f"-fi-harden=all,{c}"]
    builds = [("clang", CLANG, [])]
    builds += [(f"clang + fi-harden {l}", CLANG, harden(c))
               for c, l in (("branches", "A"), ("compares", "B"), ("branches,compares", "A+B"))]
    if shutil.which(GCC[0]):
        builds += [("gcc", GCC, []),
                   ("gcc -fharden-*", GCC, ["-fharden-compares", "-fharden-conditional-branches"])]

    print("| Kernel | Build | Code bytes | Instructions | Bytes overhead | Instructions overhead |")
    print("|---" * 6 + "|")
    for k in KERNELS:
        src = next((root / "src" / k).glob("*.c"))
        base = {}  # compiler: its plain build's (bytes, instructions)
        for i, (name, cc, extra) in enumerate(builds):
            obj, elf = work / f"{k}-{i}.o", work / f"{k}-{i}.elf"
            subprocess.run([*cc, *FLAGS, *inc, *extra, "-c", str(src), "-o", str(obj)], check=True)
            subprocess.run([*CLANG, "-fuse-ld=lld", "-nostdlib", "-T", str(CM / "cm.ld"), *objs,
                            str(obj), "-o", str(elf)], check=True)
            size = code_bytes(obj)
            out, n = instructions(str(elf))
            if out != "ret=0":
                sys.exit(f"{k}, {name}: the kernel's check failed ({out})")
            b = base.setdefault(cc[0], (size, n))
            print(f"| {k} | {name} | {size} | {n} | {size / b[0] - 1:+.0%} | {n / b[1] - 1:+.0%} |",
                  flush=True)


if __name__ == "__main__":
    main()

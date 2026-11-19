#!/usr/bin/env python3
"""Fault campaigns on FISSC's VerifyPIN, bare-metal Cortex-M3, one row per build.

usage: fissc.py PLUGIN [WORKDIR]

Downloads FISSC 2.2 into WORKDIR (default ./fissc-work; it's LGPL-3.0, so it
isn't in this repo), builds each VerifyPIN version on eval/cm, runs
eval/fisim.py on verifyPIN, and prints Markdown tables of absolute counts:
one with FISSC's user PIN, wrong in every digit, and one wrong only in the
last digit. A run is bad if the PIN is accepted, or if the try counter isn't
decremented (FISSC's two oracles).

Rows: v0 (no countermeasures) with clang -O2, plain and with fi-harden's
countermeasures on verifyPIN; v0 with arm-none-eabi-gcc -O2, plain and with
-fharden-compares -fharden-conditional-branches (if it's on PATH); and
FISSC's hand-hardened v1-v7 with clang -O2. clang (LLVM 23, the plugin's)
comes from PATH.
"""
import hashlib
import pathlib
import shutil
import subprocess
import sys
import tarfile
import urllib.request

import fisim

URL = "https://lazart.gricad-pages.univ-grenoble-alpes.fr/fissc/fissc/FISSC-2.2.tar.gz"
SHA256 = "bde1c09b233c3b0b990a4e44402d2f2ae24dcdc2265896b6d008414af85ab187"
CM = pathlib.Path(__file__).with_name("cm")
CLANG = ["clang", "--target=thumbv7m-none-eabi", "-mcpu=cortex-m3", "-fuse-ld=lld"]
GCC = ["arm-none-eabi-gcc", "-mcpu=cortex-m3", "-mthumb"]
COMMON = ["-O2", "-ffreestanding", "-fno-unwind-tables", "-nostdlib", "-T", str(CM / "cm.ld")]


def fetch(work):
    root = work / "FISSC-2.2" / "VerifyPIN"
    if root.exists():
        return root
    tgz = work / "FISSC-2.2.tar.gz"
    if not tgz.exists():
        urllib.request.urlretrieve(URL, tgz)
    if hashlib.sha256(tgz.read_bytes()).hexdigest() != SHA256:
        sys.exit(f"{tgz}: wrong sha256")
    with tarfile.open(tgz) as t:
        t.extractall(work, filter="data")
    return root


def build(cc, version, out, extra=()):
    src = version / "src"
    files = [CM / "start.c", CM / "fissc_main.c"] + [src / f for f in
             ("code.c", "initialize.c", "countermeasure.c", "oracle.c")]
    subprocess.run([*cc, *COMMON, f"-I{version.parent / 'share'}", f"-I{src}", *extra,
                    *map(str, files), "-o", str(out)], check=True)


def row(name, elf):
    res, gold, sim, trace, window = fisim.campaign(elf, "verifyPIN")
    # Size: the functions the window ran (verifyPIN and what it calls).
    funcs = {n: s for n, (a, s) in sim.sym.items() if s and any(a <= trace[i][0] < a + s for i in window)}
    # v7 calls its countermeasure on every wrong PIN, so ret=4 is its golden run.
    assert gold in ("ret=0", "ret=4"), f"{name}: golden run {gold}"
    cells = [name, str(sum(funcs.values())), str(len(window))]
    for model in ("skip", "flip"):
        c = res[model]
        auth = c["ret=1"] + c["ret=3"]
        ptc = c["ret=2"] + c["ret=3"]
        detected = c["trap"] + (c["ret=4"] if gold != "ret=4" else 0)
        cells += [f"**{auth}**", str(ptc), str(detected), str(sum(c.values()))]
    return "| " + " | ".join(cells) + " |"


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    plugin = str(pathlib.Path(sys.argv[1]).resolve())
    work = pathlib.Path(sys.argv[2] if len(sys.argv) == 3 else "fissc-work").resolve()
    work.mkdir(exist_ok=True)
    root = fetch(work)
    versions = sorted(root.glob("VerifyPIN_[0-9]*"))
    allow = work / "allowlist.txt"
    # The decision, as the README says to mark it. Marking byteArrayCompare too
    # keeps it out of line, and its return value then crosses unchecked.
    allow.write_text("verifyPIN\n")
    harden = lambda c: [f"-fpass-plugin={plugin}", "-mllvm", f"-fi-harden={c},allowlist={allow}"]
    builds = [("v0, clang", CLANG, versions[0], [])]
    for c, label in (("branches", "A"), ("compares", "B"), ("branches,compares", "A+B")):
        builds.append((f"v0, clang + fi-harden {label}", CLANG, versions[0], harden(c)))
    if shutil.which(GCC[0]):
        builds.append(("v0, gcc", GCC, versions[0], []))
        builds.append(("v0, gcc -fharden-*", GCC, versions[0],
                       ["-fharden-compares", "-fharden-conditional-branches"]))
    builds += [(f"v{v.name.split('_', 1)[1].replace('_', ' ')}, clang", CLANG, v, [])
               for v in versions[1:]]

    for title, pin in (("User PIN 0000 (FISSC's)", []), ("User PIN 1230", ["-DLAST_DIGIT"])):
        print(f"\n{title}\n")
        print("| Build | Bytes | Instructions | Skip: PIN accepted | Skip: counter kept"
              " | Skip: detected | Skips | Flip: PIN accepted | Flip: counter kept | Flip: detected"
              " | Flips |")
        print("|---" * 11 + "|")
        for i, (name, cc, version, extra) in enumerate(builds):
            elf = work / f"build{i}.elf"
            build(cc, version, elf, [*extra, *pin])
            print(row(name, str(elf)), flush=True)


if __name__ == "__main__":
    main()

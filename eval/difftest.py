#!/usr/bin/env python3
"""Differential test: random programs behave the same with and without
fi-harden<all>. A fault-free run of the hardened build must print what the
plain build prints and exit the same way, so it never traps.

usage: difftest.py [--csmith] PLUGIN FIRST LAST [CONFIG...]

Seeds FIRST to LAST pick the programs: gen.py's, or Csmith's with --csmith
(csmith on PATH, its headers in include/csmith beside its bin/). A program is
rejected if UBSan flags it or a plain build runs over 10 s. A CONFIG is
TARGET-OLEVEL, like native-O2: TARGET is native, a64 (AArch64 Linux) or t2
(Thumb-2 Linux); the default is native-O0 native-O2. a64 and t2 link with the
cross gcc and run under qemu-user. clang comes from PATH. A failing program is
kept as fail-SEED.c. Exits 1 if anything failed or nothing was compared.
"""

import pathlib
import shutil
import subprocess
import sys
import tempfile

TARGETS = {  # clang flags, linker, runner
    "native": ([], ["clang"], []),
    "a64": (["--target=aarch64-linux-gnu"], ["aarch64-linux-gnu-gcc"],
            ["qemu-aarch64-static", "-L", "/usr/aarch64-linux-gnu"]),
    "t2": (["--target=armv7a-linux-gnueabihf", "-mthumb"], ["arm-linux-gnueabihf-gcc"],
           ["qemu-arm-static", "-L", "/usr/arm-linux-gnueabihf"]),
}


def run(cmd, timeout=None, cwd=None):
    """(exit code or "timeout", stdout, stderr)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, errors="replace", timeout=timeout,
                           cwd=cwd)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return "timeout", "", ""


def build(compile_cmd, link, exe):
    """Why compile_cmd + link didn't produce exe, or None if they did."""
    for cmd in ([*compile_cmd, "-c", "-o", exe + ".o"], [*link, exe + ".o", "-o", exe]):
        rc, _, err = run(cmd)
        if rc != 0:
            return err.strip().splitlines()[0] if err.strip() else f"{cmd[0]} exited {rc}"
    return None


def main():
    argv = sys.argv[1:]
    csmith = "--csmith" in argv
    if csmith:
        argv.remove("--csmith")
    if len(argv) < 3:
        sys.exit(__doc__)
    plugin, first, last = argv[0], int(argv[1]), int(argv[2])
    configs = argv[3:] or ["native-O0", "native-O2"]
    include = []
    if csmith:
        exe = shutil.which("csmith") or sys.exit("csmith isn't on PATH")
        include = ["-I", str(pathlib.Path(exe).resolve().parents[1] / "include" / "csmith")]
    harden = [f"-fpass-plugin={plugin}", "-mllvm", "-fi-harden=all"]
    same, rejected, failures = 0, 0, []

    def fail(seed, cfg, why, src):
        failures.append(seed)
        print(f"seed {seed} {cfg}: {why}", flush=True)
        shutil.copy(src, f"fail-{'csmith-' if csmith else ''}{seed}.c")

    for seed in range(first, last + 1):
        with tempfile.TemporaryDirectory() as d:
            src = f"{d}/p.c"
            if csmith:
                # In d: csmith writes a platform.info where it runs.
                rc, _, err = run(["csmith", "--seed", str(seed), "-o", src], cwd=d)
            else:
                rc, out, err = run([sys.executable, str(pathlib.Path(__file__).with_name("gen.py")), str(seed)])
                pathlib.Path(src).write_text(out)
            if rc != 0:
                sys.exit(f"seed {seed}: the generator failed: {err}")
            cc = ["clang", "-w", *include, src]
            # The reference: no undefined behaviour, and it finishes.
            why = build([*cc, "-O1", "-fsanitize=undefined", "-fno-sanitize-recover=all"],
                        ["clang", "-fsanitize=undefined"], f"{d}/ubsan")
            if why:
                sys.exit(f"seed {seed}: the UBSan build failed: {why}")
            if run([f"{d}/ubsan"], 10)[0] != 0:
                rejected += 1
                continue
            for cfg in configs:
                target, olevel = cfg.split("-", 1)
                flags, link, runner = TARGETS[target]
                flags = [*cc, *flags, f"-{olevel}"]
                why = build(flags, link, f"{d}/plain")
                if why:
                    fail(seed, cfg, f"plain build failed: {why}", src)
                    continue
                why = build([*flags, *harden], link, f"{d}/hardened")
                if why:
                    fail(seed, cfg, f"HARDENED BUILD FAILED: {why}", src)
                    continue
                plain = run([*runner, f"{d}/plain"], 10)[:2]
                if plain[0] == "timeout":
                    rejected += 1
                    continue
                hardened = run([*runner, f"{d}/hardened"], 60)[:2]
                if hardened == plain:
                    same += 1
                else:
                    fail(seed, cfg, f"DIFF plain exit {plain[0]} {plain[1][:60]!r}, "
                         f"hardened exit {hardened[0]} {hardened[1][:60]!r}", src)
    print(f"seeds {first}-{last} ({'csmith' if csmith else 'gen.py'}, {' '.join(configs)}): "
          f"{same} runs identical, {len(failures)} failed, {rejected} rejected (UB or timeout)")
    sys.exit(1 if failures or not same else 0)


if __name__ == "__main__":
    main()

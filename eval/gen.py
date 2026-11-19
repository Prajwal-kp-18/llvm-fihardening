#!/usr/bin/env python3
"""Random UB-free C programs rich in compares: used by branches, stored, added
into values, as select conditions, in && / || chains, switches, loops, phis,
pointer and FP (NaN) compares, at 8 to 64 bits. Prints a checksum.

usage: gen.py SEED > prog.c
"""
import random
import sys

R = random.Random(int(sys.argv[1]))
U = ["uint8_t", "uint16_t", "uint32_t", "uint64_t"]
S = ["int8_t", "int16_t", "int32_t", "int64_t"]
CMP = ["==", "!=", "<", "<=", ">", ">="]
depth = 0


def var():
    return R.choice(["a", "b", "c", "v0", "v1", "v2", "acc", "(uint32_t)i"])


def expr(d=0):
    if d > 2 or R.random() < 0.3:
        return R.choice([var(), var(), str(R.randrange(0, 300)) + "u", "in[%d]" % R.randrange(8)])
    op = R.choice(["+", "-", "*", "^", "&", "|", "<<", ">>", "/", "cmp", "sel"])
    x, y = expr(d + 1), expr(d + 1)
    if op in "<<>>":
        return f"(({x}) {op} (({y}) & 31u))"
    if op == "/":
        return f"(({x}) / (({y}) | 1u))"
    if op == "cmp":
        return f"(uint32_t)({cond(d + 1)})"
    if op == "sel":
        return f"(({cond(d + 1)}) ? ({x}) : ({y}))"
    return f"(({x}) {op} ({y}))"


def cond(d=0):
    k = R.random()
    if d < 2 and k < 0.2:
        return f"(({cond(d + 1)}) {R.choice(['&&', '||'])} ({cond(d + 1)}))"
    if k < 0.3:
        return f"!({cond(d + 1)})"
    if k < 0.45:
        t = R.choice(S)
        return f"(({t})({expr(d + 1)}) {R.choice(CMP)} ({t})({expr(d + 1)}))"
    if k < 0.55:
        t = R.choice(U)
        return f"(({t})({expr(d + 1)}) {R.choice(CMP)} ({t})({expr(d + 1)}))"
    if k < 0.65:
        return f"(fx[{R.randrange(4)}] {R.choice(CMP)} fx[{R.randrange(4)}])"
    if k < 0.72:
        return f"(dx[{R.randrange(4)}] {R.choice(CMP)} (double)({expr(d + 1)}))"
    if k < 0.8:
        return f"(&buf[({expr(d + 1)}) & 15] {R.choice(CMP)} &buf[({expr(d + 1)}) & 15])"
    return f"(({expr(d + 1)}) {R.choice(CMP)} ({expr(d + 1)}))"


def stmts(n, ind):
    global depth
    out = []
    for _ in range(n):
        k = R.random()
        p = "  " * ind
        if depth < 3 and k < 0.15:
            depth += 1
            out.append(f"{p}if ({cond()}) {{")
            out += stmts(R.randrange(1, 4), ind + 1)
            out.append(f"{p}}} else {{")
            out += stmts(R.randrange(0, 3), ind + 1)
            out.append(f"{p}}}")
            depth -= 1
        elif depth < 2 and k < 0.25:
            depth += 1
            out.append(f"{p}for (int i = 0; i < {R.randrange(1, 6)}; i++) {{")
            out += stmts(R.randrange(1, 4), ind + 1)
            if R.random() < 0.3:
                out.append(f"{p}  if ({cond()}) break;")
            out.append(f"{p}}}")
            depth -= 1
        elif depth < 3 and k < 0.32:
            depth += 1
            out.append(f"{p}switch (({expr()}) & 7u) {{")
            for c in R.sample(range(8), R.randrange(1, 4)):
                out.append(f"{p}case {c}:")
                out += stmts(R.randrange(1, 3), ind + 1)
                out.append(f"{p}  break;")
            out.append(f"{p}default:")
            out += stmts(1, ind + 1)
            out.append(f"{p}}}")
            depth -= 1
        elif k < 0.45:
            out.append(f"{p}flags[({expr()}) & 7] = {cond()};")
        elif k < 0.6:
            out.append(f"{p}acc += {cond()};")
        elif k < 0.72:
            out.append(f"{p}{R.choice(['v0', 'v1', 'v2'])} = ({cond()}) ? ({expr()}) : ({expr()});")
        elif k < 0.8 and ind > 1:
            out.append(f"{p}if ({cond()}) return acc ^ {R.randrange(1000)}u;")
        else:
            out.append(f"{p}{R.choice(['v0', 'v1', 'v2', 'acc'])} = {expr()};")
    return out


print("""#include <stdint.h>
#include <stdio.h>
static volatile uint32_t vin[8] = {%s};
static volatile float vz = 0.0f;
static uint32_t in[8];
static float fx[4];
static double dx[4];
static uint8_t flags[8];
static uint8_t buf[16];
""" % ", ".join(str(R.randrange(0, 2**32)) if R.random() < 0.5 else str(R.randrange(0, 20)) for _ in range(8)))
NF = R.randrange(2, 5)
for f in range(NF):
    print(f"__attribute__((noinline)) uint32_t f{f}(uint32_t a, uint32_t b, uint32_t c) {{")
    print("  uint32_t acc = a, v0 = b, v1 = c, v2 = a ^ c; int i = 0; (void)i;")
    print("\n".join(stmts(R.randrange(4, 10), 1)))
    print("  return acc + v0 * 3u + v1 * 5u + v2 * 7u;\n}\n")
print("""int main(void) {
  for (int k = 0; k < 8; k++) in[k] = vin[k];
  fx[0] = (float)in[0]; fx[1] = vz / vz; fx[2] = -(float)in[2]; fx[3] = 1.0f / vz;
  dx[0] = (double)in[1]; dx[1] = (double)(vz / vz); dx[2] = 0.5; dx[3] = -(double)in[3];
  uint64_t sum = 0;
  for (uint32_t r = 0; r < 24; r++) {""")
for f in range(NF):
    print(f"    sum = sum * 31u + f{f}(in[r & 7] + r, in[(r + 3) & 7] ^ r, r * 2654435761u);")
print("""  }
  for (int k = 0; k < 8; k++) sum = sum * 7u + flags[k];
  printf("%llu\\n", (unsigned long long)sum);
  return 0;
}""")

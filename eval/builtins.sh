#!/bin/bash
# compiler-rt's builtins built plain and with fi-harden<all> must pass their
# unit tests the same way: same output, same exit code. Prints DIFF per test
# that doesn't, then a summary. "Linked hardened" counts the tests whose link
# map shows they used the hardened library, not only libgcc.
#
# usage: builtins.sh PLUGIN COMPILER_RT_DIR native|a64|t2 OLEVEL
# Works in ./builtins-TARGET-OLEVEL. a64 and t2 link with the cross gcc and run
# under qemu-user. clang and llvm-ar come from PATH.
set -u
P=$1 CRT=$2 T=$3 O=$4 W=$PWD/builtins-$3-$4
case $T in
  native) TT=() LD=(clang) RUN=(setarch "$(uname -m)" -R) ;; # no ASLR: a test prints a stack address
  a64) TT=(--target=aarch64-linux-gnu) LD=(aarch64-linux-gnu-gcc) RUN=(qemu-aarch64-static -L /usr/aarch64-linux-gnu) ;;
  t2) TT=(--target=armv7a-linux-gnueabihf -mthumb) LD=(arm-linux-gnueabihf-gcc) RUN=(qemu-arm-static -L /usr/arm-linux-gnueabihf) ;;
  *) echo "unknown target $T" >&2; exit 2 ;;
esac
CC=(clang "${TT[@]}" -fno-builtin -I"$CRT/lib/builtins")
rm -rf "$W" && mkdir -p "$W"/plain "$W"/hard "$W"/test
for f in "$CRT"/lib/builtins/*.c; do
  b=$(basename "$f" .c)
  "${CC[@]}" -"$O" -c "$f" -o "$W/plain/$b.o" 2>/dev/null || continue # not for this target
  "${CC[@]}" -"$O" -fpass-plugin="$P" -mllvm -fi-harden=all -c "$f" -o "$W/hard/$b.o" 2>"$W/$b.err" ||
    echo "HARDENED BUILD FAILED $b: $(head -1 "$W/$b.err")"
done
llvm-ar rcs "$W/plain.a" "$W"/plain/*.o && llvm-ar rcs "$W/hard.a" "$W"/hard/*.o || exit 1
same=0 diff=0 used=0
for t in "$CRT"/test/builtins/Unit/*_test.c; do
  b=$(basename "$t" .c)
  x=$W/test/$b
  "${CC[@]}" -O2 -c "$t" -o "$x.o" 2>/dev/null || continue
  for v in plain hard; do
    "${LD[@]}" "$x.o" "$W/$v.a" -lm -o "$x.$v" -Wl,-Map="$x.$v.map" 2>/dev/null || continue 2
    # Assertion messages name the executable: drop its .plain/.hard suffix.
    timeout 20 "${RUN[@]}" "$x.$v" 2>&1 | sed "s/$b\.$v/$b/g" >"$x.$v.out"
    echo "exit ${PIPESTATUS[0]}" >>"$x.$v.out"
  done
  grep -q 'hard\.a(' "$x.hard.map" && used=$((used + 1))
  if cmp -s "$x.plain.out" "$x.hard.out"; then same=$((same + 1)); else diff=$((diff + 1)); echo "DIFF $b"; fi
done
echo "$T -$O: $same unit tests identical, $diff differ ($used linked hardened code)"

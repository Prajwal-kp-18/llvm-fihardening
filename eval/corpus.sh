#!/bin/bash
# Hardens one LLVM test file with fi-harden<all>. Prints OK, SKIP (LLVM fails
# on the file without the plugin too) or FAIL with the first error.
#   opt: runs PASSES (default fi-harden<all>) with -verify-each.
#   llc: hardens, then lowers the bitcode with llc -O2; TRIPLE for files
#        without one.
# opt and llc come from PATH (an assertions build catches more), and must be
# the LLVM the plugin was built against.
#
# usage: corpus.sh opt|llc PLUGIN FILE [TRIPLE]
# e.g.:  find llvm/test/Transforms -name '*.ll' |
#          nice -n 19 xargs -P 3 -I{} eval/corpus.sh opt build/FIHarden.so {} > out.txt
ulimit -v 3000000
mode=$1 plugin=$2 f=$3 triple=()
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
grep -q '^target triple' "$f" || [ -z "$4" ] || triple=(-mtriple="$4")
passes=${PASSES:-fi-harden<all>}
[ "$mode" = llc ] && passes='fi-harden<all>'
# The same passes without fi-harden.
base=$(sed -E 's/fi-harden<[^>]*>//; s/,,/,/; s/^,|,$//g' <<<"$passes")

check() { # opt with these arguments, then llc in llc mode
  if [ "$mode" = opt ]; then
    timeout 120 opt "$@" -verify-each -disable-output "$f"
  else
    timeout 120 opt "$@" "$f" -o "$tmp/out.bc" &&
      timeout 120 llc -O2 "${triple[@]}" "$tmp/out.bc" -o /dev/null
  fi
}

# Braces, so bash's own "Aborted" notices are redirected too.
{ check ${base:+-passes="$base"}; } >/dev/null 2>&1 || { echo "SKIP $f"; exit 0; }
{ check -load-pass-plugin="$plugin" -passes="$passes"; } >/dev/null 2>"$tmp/err"
rc=$?
[ $rc = 0 ] && echo "OK $f" ||
  echo "FAIL $f: exit $rc $(grep -m1 -E 'Assert|ERROR|error|Broken|verif|Cannot|unable' "$tmp/err" | cut -c1-200)"

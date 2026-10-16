#!/usr/bin/env sh
# kit-scope: shared
# Run every scripts/*.selfcheck.sh of a kit in parallel, scored the way CI scores them.
# Usage: selfcheck-all.sh [-j N] [-s SHELL] [KIT_DIR]
#   -j N      worker count (positive integer, default 4)
#   -s SHELL  shell each selfcheck runs under (sh, dash, bash; default sh)
#   KIT_DIR   kit root (default: the directory above this script)
# Workers each walk the sorted check list and run a check only if they win the atomic
# `mkdir` claim, so one slow check does not idle the other workers.
# Scoring: a check passes iff its exit code is 0 AND its output has no line starting SKIP
# (a skipped check hides exactly the divergence CI exists to catch). Missing rc = fail.
# Each finished check prints an unordered `done scripts/<name>.selfcheck.sh rc=<rc>` progress line
# first (so a hung CI run names its stragglers); the ordered ok/FAIL block follows.
# Output of every check is kept in a fresh temp dir, printed as `outputs: <dir>`.
# Exit: 0 all pass, 1 any fail, 2 usage error or no checks found.

jobs=4
shell=sh
usage() { echo "usage: selfcheck-all.sh [-j N] [-s SHELL] [KIT_DIR]" >&2; exit 2; }

while getopts j:s: opt; do
  case $opt in
    j) jobs=$OPTARG ;;
    s) shell=$OPTARG ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -le 1 ] || usage
case $jobs in
  ''|*[!0-9]*|0|0[0-9]*) echo "selfcheck-all.sh: -j needs a positive integer" >&2; usage ;;
esac
command -v "$shell" >/dev/null 2>&1 || { echo "selfcheck-all.sh: shell not found: $shell" >&2; exit 2; }
if [ $# -eq 1 ]; then
  kit=$(CDPATH= cd "$1" 2>/dev/null && pwd) || { echo "selfcheck-all.sh: bad kit dir: $1" >&2; exit 2; }
else
  kit=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fi

names=
for f in "$kit"/scripts/*.selfcheck.sh; do
  [ -e "$f" ] || continue
  n=${f##*/}
  names="$names ${n%.selfcheck.sh}"
done
[ -n "$names" ] || { echo "selfcheck-all.sh: no scripts/*.selfcheck.sh under $kit" >&2; exit 2; }

out=$(mktemp -d "${TMPDIR:-/tmp}/selfcheck-all.XXXXXX") || exit 2
mkdir "$out/.claim"

worker() {
  for n in $names; do
    mkdir "$out/.claim/$n" 2>/dev/null || continue
    (
      cd "$kit" || exit 1
      "$shell" "scripts/$n.selfcheck.sh" </dev/null >"$out/$n.out" 2>&1
      echo $? >"$out/$n.rc"
      echo "done scripts/$n.selfcheck.sh rc=$(cat "$out/$n.rc")"
    )
  done
}

i=0
while [ "$i" -lt "$jobs" ]; do
  worker &
  i=$((i + 1))
done
wait

pass=0
fail=0
for n in $names; do
  sc="scripts/$n.selfcheck.sh"
  rc=$(cat "$out/$n.rc" 2>/dev/null)
  if [ "$rc" = 0 ] && ! grep -a -q '^SKIP' "$out/$n.out" 2>/dev/null; then
    pass=$((pass + 1))
    echo "ok   $sc"
  else
    fail=$((fail + 1))
    echo "FAIL $sc (rc=${rc:-missing})"
    sed 's/^/    | /' "$out/$n.out" 2>/dev/null
  fi
done
echo "shell=$shell jobs=$jobs pass=$pass fail=$fail"
echo "outputs: $out"
[ "$fail" -eq 0 ]

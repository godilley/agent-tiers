#!/usr/bin/env sh
# kit-scope: shared
# Self-check for selfcheck-all.sh: scoring, SKIP-as-fail, cwd, run-once, usage errors. Runnable: `sh selfcheck-all.selfcheck.sh`.
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
runner="$ROOT/scripts/selfcheck-all.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sca-self.XXXXXX") || exit 1
outdirs=
cleanup() { rm -rf "$tmp"; for d in $outdirs; do rm -rf "$d"; done; }
trap cleanup EXIT
die() { echo "FAIL: $1"; exit 1; }

mk() { # kit name body
  mkdir -p "$1/scripts"
  printf '#!/usr/bin/env sh\necho %s >> "%s/log"\n%s\n' "$2" "$1" "$3" > "$1/scripts/$2.selfcheck.sh"
}

fake="$tmp/fake"
mk "$fake" a 'exit 0'
mk "$fake" b 'echo boom-b; exit 3'
mk "$fake" c 'echo "SKIP c: tool absent"; exit 0'
mk "$fake" d 'sleep 1; exit 0'
mk "$fake" e '[ -f ./scripts/e.selfcheck.sh ]'

res=$(sh "$runner" -j 2 -s sh "$fake" 2>&1); rc=$?
outdirs="$outdirs $(printf '%s\n' "$res" | sed -n 's/^outputs: //p')"
[ "$rc" = 1 ] || die "mixed kit rc=$rc, want 1"
[ "$(printf '%s\n' "$res" | grep -c '^done scripts/')" = 5 ] || die "want 5 done lines"
has() { printf '%s\n' "$res" | grep -qF -- "$1" || die "missing: $1"; }
has 'shell=sh jobs=2 pass=3 fail=2'
has 'FAIL scripts/b.selfcheck.sh'
has 'boom-b'
has 'FAIL scripts/c.selfcheck.sh'
has 'ok   scripts/a.selfcheck.sh'
has 'ok   scripts/d.selfcheck.sh'
has 'ok   scripts/e.selfcheck.sh'
[ "$(wc -l < "$fake/log" | tr -d ' ')" = 5 ] || die "checks did not run exactly once (log has $(wc -l < "$fake/log") lines)"
[ "$(sort -u "$fake/log" | wc -l | tr -d ' ')" = 5 ] || die "a check ran more than once"

expect2() { # label, args...
  l=$1; shift
  sh "$runner" "$@" >/dev/null 2>&1; r=$?
  [ "$r" = 2 ] || die "$l: rc=$r, want 2"
}
expect2 "-j 0" -j 0 "$fake"
expect2 "-j x" -j x "$fake"
expect2 "bad shell" -s no-such-shell-zz "$fake"
mkdir "$tmp/empty"
expect2 "empty kit" "$tmp/empty"

ok="$tmp/ok"
mk "$ok" a 'exit 0'
mk "$ok" d 'sleep 1; exit 0'
res=$(sh "$runner" "$ok" 2>&1); rc=$?
outdirs="$outdirs $(printf '%s\n' "$res" | sed -n 's/^outputs: //p')"
[ "$rc" = 0 ] || die "all-pass rc=$rc, want 0"
has 'pass=2 fail=0'

mkdir "$tmp/bin"
printf '#!/bin/sh\necho recsh >> "%s/recsh.log"\nexec sh "$@"\n' "$tmp" > "$tmp/bin/recsh"
chmod +x "$tmp/bin/recsh"
res=$(sh "$runner" -s "$tmp/bin/recsh" "$ok" 2>&1); rc=$?
outdirs="$outdirs $(printf '%s\n' "$res" | sed -n 's/^outputs: //p')"
[ "$rc" = 0 ] || die "-s recsh rc=$rc, want 0"
has "shell=$tmp/bin/recsh "
[ "$(wc -l < "$tmp/recsh.log" | tr -d ' ')" = 2 ] || die "-s ignored: recsh.log lines != 2"

echo "OK selfcheck-all: scoring, skip-as-fail, cwd, run-once, usage errors"

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for doc-lifecycle-check.sh. Runnable: `sh doc-lifecycle-check.selfcheck.sh`.
# Isolated `mktemp -d` fixture git repo - never touches real ~/.claude state, matching
# install-flat.selfcheck.sh's own convention.
set -u
HERE="$(CDPATH= cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/doc-lifecycle-check.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v git >/dev/null 2>&1 || { echo "SKIP: git absent"; exit 0; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cd "$W" || exit 1
git init -q .
git config user.email t@t.local
git config user.name t
git commit -q --allow-empty -m init

# --- with no notes dir at all: pass 1 skipped (not a violation), pass 2 still runs, exit 0 --------
OUT="$(sh "$CHECK" 2>&1)"; RC=$?
eq_rc() { [ "$1" -eq "$2" ] && ok "$3" || bad "$3 (want exit $1, got $2)"; }
eq_rc 0 "$RC" "no-notes-dir run still exits 0"
printf '%s' "$OUT" | grep -q 'no notes dir' && ok "no-notes-dir run reports the skip, not a violation" \
  || bad "no-notes-dir run did not explain the skip: $OUT"
printf '%s' "$OUT" | grep -q 'tracked working-doc-shaped' && ok "tracked-docs pass runs even with no notes dir" \
  || bad "tracked-docs pass did not run with no notes dir: $OUT"

# --- private-notes pass: build one fixture of each shape -------------------------------------------
mkdir -p docs/_local/archive
printf 'no status line here\n' > docs/_local/2026-01-01-missing-status.md
printf 'STATUS: LIVE\n\nfresh\n' > docs/_local/2026-01-02-fresh-live.md
printf 'STATUS: SHIPPED\n\nshould have been archived\n' > docs/_local/2026-01-03-unarchived-shipped.md
printf 'STATUS: SHIPPED\n\nalready archived, must not double-flag\n' > docs/_local/archive/2026-01-04-already-archived.md
printf 'STATUS: LIVE\n\nstale\n' > docs/_local/2026-01-05-stale-live.md
touch -t 202001010000 docs/_local/2026-01-05-stale-live.md    # ancient mtime -> past any real stale_days
printf 'not a dated doc, out of scope by construction\n' > docs/_local/state-ledger.md

OUT="$(sh "$CHECK" 2>&1)"
printf '%s' "$OUT" | grep -q '2026-01-01-missing-status.md' && ok "flags a dated doc with no STATUS line" \
  || bad "did not flag the missing-STATUS doc: $OUT"
printf '%s' "$OUT" | grep -q '2026-01-03-unarchived-shipped.md' \
  && ok "flags a terminal-status doc still outside archive/" \
  || bad "did not flag the unarchived SHIPPED doc: $OUT"
printf '%s' "$OUT" | grep -q '2026-01-04-already-archived' \
  && bad "flagged a doc already inside archive/ as unarchived" \
  || ok "does not re-flag a doc already inside archive/"
printf '%s' "$OUT" | grep -q '2026-01-05-stale-live.md' && ok "flags a LIVE doc past stale_days" \
  || bad "did not flag the stale LIVE doc: $OUT"
printf '%s' "$OUT" | grep -q '2026-01-02-fresh-live.md' \
  && bad "flagged a fresh LIVE doc as stale" || ok "does not flag a fresh LIVE doc"
printf '%s' "$OUT" | grep -q 'state-ledger' \
  && bad "flagged a non-dated named state file - out of scope by construction" \
  || ok "a non-dated named state file is out of scope, not a violation"

# --- tracked-docs pass: a dated tracked doc outside the notes dir is flagged, ordinary docs are not -
mkdir -p plans
printf 'STATUS: LIVE\n\nlooks like a plan doc\n' > 2026-01-06-tracked-plan.md
printf '# just a normal readme\n' > README.md
printf 'reference doc, not dated, no status line\n' > plans/architecture.md
git add 2026-01-06-tracked-plan.md README.md plans/architecture.md
git commit -q -m "tracked fixtures"

OUT="$(sh "$CHECK" 2>&1)"
printf '%s' "$OUT" | grep -q '2026-01-06-tracked-plan.md' && ok "flags a tracked dated doc outside the notes dir" \
  || bad "did not flag the tracked dated plan doc: $OUT"
printf '%s' "$OUT" | grep -q 'plans/architecture.md' && ok "flags a tracked doc under a plans/ path segment" \
  || bad "did not flag the plans/ path-segment doc: $OUT"
printf '%s' "$OUT" | grep -q 'README.md' && bad "flagged an ordinary README as working-doc-shaped" \
  || ok "does not flag an ordinary reference README"
printf '%s' "$OUT" | grep -q 'notes-sync.sh migrate' && ok "the disposition-decision disclaimer is present" \
  || bad "missing the 'this is the user's decision, never an automated untrack' disclaimer: $OUT"

# --- exit code is always 0, even with every pass flagging something --------------------------------
OUT="$(sh "$CHECK" 2>&1)"; RC=$?
eq_rc 0 "$RC" "exits 0 even with findings in every pass (advisory only, never blocks)"

# --- tracked-inside-notes-dir: the exclude seam itself is broken (the highest-value finding) -------
git add -f docs/_local/2026-01-01-missing-status.md
git commit -q -m "accidentally tracked a private note"
OUT="$(sh "$CHECK" 2>&1)"
printf '%s' "$OUT" | grep -q 'exclude seam is broken' && printf '%s' "$OUT" | grep -q '2026-01-01-missing-status.md' \
  && ok "flags a file tracked BY GIT inside the private notes dir (broken exclude seam)" \
  || bad "did not flag a tracked file inside the notes dir: $OUT"
git rm --cached -q docs/_local/2026-01-01-missing-status.md
git commit -q -m "untrack it again"
OUT="$(sh "$CHECK" 2>&1)"
printf '%s' "$OUT" | grep -q 'doc-lifecycle: 0 file TRACKED by git' && ok "clears once the file is untracked again" \
  || bad "the tracked-inside finding did not clear after untracking: $OUT"

# --- --summary mode: capped to at most 5 examples, safe charset only --------------------------------
# 10 more terminal-status docs left outside archive/ (on top of 2026-01-03's own one, above) - the
# --summary line for THAT SPECIFIC pass is grepped for, not just head -n1 (line order shifts as
# passes are added). One deliberately unsafe-named fixture proves the charset filter, not just the
# count cap.
i=0
while [ "$i" -lt 10 ]; do
  printf 'STATUS: SHIPPED\n' > "docs/_local/2026-02-0$((i % 9 + 1))-many-$i.md"
  i=$((i + 1))
done
printf 'STATUS: SHIPPED\n' > "docs/_local/2026-02-09-unsafe name.md"   # a space fails safe_name's charset
SUM="$(sh "$CHECK" --summary 2>&1 | grep 'terminal-status doc still outside')"
n_examples="$(printf '%s' "$SUM" | grep -o ',' | wc -l | tr -d ' ')"
[ "${n_examples:-0}" -le 4 ] && ok "--summary caps examples at 5 (at most 4 commas)" \
  || bad "--summary listed more than 5 examples: $SUM"
printf '%s' "$SUM" | grep -q 'unsafe name' && bad "--summary leaked an unsafe-charset filename" \
  || ok "--summary example names pass the safe-charset filter"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

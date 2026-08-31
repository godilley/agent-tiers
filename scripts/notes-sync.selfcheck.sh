#!/usr/bin/env sh
# kit-scope: shared
# Self-check for notes-sync.sh. Runnable: `sh notes-sync.selfcheck.sh`.
# Builds a throwaway git repo and exercises BOTH profile shapes: the default profile (dir=docs/_local,
# ref=local/notes, unnamespaced config keys - the regression half, since the --profile generalisation
# rewrote the config lookup every existing repo depends on) and a named profile (own dir, own
# `local/<name>` ref, `notes-sync.<name>.*` keys). The two must not see each other's config or ref.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
NS="$DIR/notes-sync.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
eq()  { # <want> <got> <label>
  [ "$1" = "$2" ] && ok "$3" || bad "$3 (want '$1', got '$2')"
}

command -v git >/dev/null 2>&1 || { echo "SKIP: git absent"; exit 0; }
# notes-sync.sh is bash (set -o pipefail + arrays), so every invocation below is `bash "$NS"`, never
# `sh "$NS"`: this selfcheck itself runs under sh/dash/bash in CI, and on a host whose /bin/sh is dash
# the `sh` form is a parse error, reported as a wall of FAILs that look like notes-sync regressions.
command -v bash >/dev/null 2>&1 || { echo "SKIP: bash absent (notes-sync.sh needs it)"; exit 0; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cd "$W" || exit 1
git init -q .
git config user.email t@t.local
git config user.name t
git commit -q --allow-empty -m init

# --- default profile (no --profile flag) ------------------------------------------------------------
printf 'build' > .git/info/exclude   # no trailing newline: the guard must not glue onto this line
bash "$NS" setup >/dev/null 2>&1 || bad "default setup exited non-zero"
grep -qxF 'build' .git/info/exclude && ok "an exclude file with no trailing newline keeps its last rule" \
  || bad "setup glued its pattern onto the previous exclude rule"
eq "docs/_local" "$(git config --get notes-sync.dir)"  "default profile config key notes-sync.dir"
eq "local/notes" "$(git config --get notes-sync.ref)"  "default profile config key notes-sync.ref"
eq "local"       "$(git config --get notes-sync.push)" "default profile defaults to push=local"
grep -qxF 'docs/_local/' .git/info/exclude && ok "default dir excluded" || bad "default dir not in .git/info/exclude"

B0="$(git rev-parse --abbrev-ref HEAD)"; H0="$(git rev-parse HEAD)"
mkdir -p docs/_local && printf 'private\n' > docs/_local/a.md
bash "$NS" save "test save" >/dev/null 2>&1
git rev-parse -q --verify refs/heads/local/notes >/dev/null && ok "default save created local/notes" \
  || bad "default save did not create local/notes"
eq "a.md" "$(git ls-tree --name-only refs/heads/local/notes docs/_local/ | sed 's#.*/##')" \
  "default ref holds the notes file"
eq "" "$(git status --porcelain -- docs/_local)" "notes dir stays untracked on the code branch"
eq "$B0" "$(git rev-parse --abbrev-ref HEAD)" "save does not change the branch"
eq "$H0" "$(git rev-parse HEAD)" "save does not move HEAD"
eq "" "$(git diff --cached --name-only)" "save leaves the real index empty"

# an unchanged dir is a no-op, not a second commit
BEFORE="$(git rev-parse refs/heads/local/notes)"
bash "$NS" save >/dev/null 2>&1
eq "$BEFORE" "$(git rev-parse refs/heads/local/notes)" "second save with no change is a no-op"

bash "$NS" status 2>&1 | grep -q 'ref: *local/notes' && ok "default status reports its ref" \
  || bad "default status did not report local/notes"

# --- named profile -------------------------------------------------------------------------------
# setup without --dir must REFUSE (a named profile has no dir default - guessing one would snapshot
# the wrong tree).
bash "$NS" --profile work setup >/dev/null 2>&1 && bad "named setup with no --dir should have failed" \
  || ok "named setup without --dir refuses"

bash "$NS" --profile work setup --dir working/set >/dev/null 2>&1 || bad "named setup --dir exited non-zero"
eq "working/set" "$(git config --get notes-sync.work.dir)" "named profile config key notes-sync.work.dir"
eq "local/work"  "$(git config --get notes-sync.work.ref)" "named profile ref defaults to local/<profile>"
eq "docs/_local" "$(git config --get notes-sync.dir)" "named setup left the default profile's dir alone"

printf 'wip\n' > working/set/b.md
bash "$NS" --profile work save >/dev/null 2>&1
git rev-parse -q --verify refs/heads/local/work >/dev/null && ok "named save created local/work" \
  || bad "named save did not create local/work"
eq "b.md" "$(git ls-tree --name-only refs/heads/local/work working/set/ | sed 's#.*/##')" \
  "named ref holds the named profile's file"
eq "" "$(git ls-tree --name-only -r refs/heads/local/work -- docs/_local)" \
  "named ref does NOT contain the default profile's dir"
eq "$BEFORE" "$(git rev-parse refs/heads/local/notes)" "named save left the default ref untouched"
bash "$NS" --profile work status 2>&1 | grep -q 'ref: *local/work' && ok "named status reports its ref" \
  || bad "named status did not report local/work"

# --profile after the subcommand is accepted too (the arg scan runs before dispatch)
bash "$NS" status --profile work 2>&1 | grep -q 'ref: *local/work' && ok "--profile parsed after the subcommand" \
  || bad "--profile after the subcommand was ignored"

bash "$NS" push 2>&1 | grep -q 'not pushing' && ok "push is a no-op under the local policy" \
  || bad "push under policy=local did not decline"

# --- restore round-trip (default profile) --------------------------------------------------------
rm -rf docs/_local
bash "$NS" restore >/dev/null 2>&1
[ -f docs/_local/a.md ] && ok "restore brings the notes dir back" || bad "restore did not restore docs/_local/a.md"
rm -rf working
bash "$NS" --profile work restore >/dev/null 2>&1
[ -f working/set/b.md ] && ok "restore works for a named profile's nested dir" \
  || bad "named restore did not restore working/set/b.md"
rm -rf docs/_local
bash "$NS" save >/dev/null 2>&1 && ok "save with a missing dir exits 0" || bad "save with a missing dir errored"
mkdir -p docs/_local && printf 'private\n' > docs/_local/a.md

# --- migrate: moves paths in, untracks a tracked one, and REFUSES a basename collision -------------
mkdir -p src other && printf 'x\n' > src/notes.md && printf 'y\n' > other/notes.md
git add other/notes.md && git commit -q -m "tracked note"   # the COLLIDING path is the tracked one
bash "$NS" migrate src/notes.md >/dev/null 2>&1
[ -f docs/_local/notes.md ] && ok "migrate moved the path into the notes dir" || bad "migrate did not move the path"
bash "$NS" migrate other/notes.md >/dev/null 2>&1 && bad "migrate overwrote an existing basename" \
  || ok "migrate refuses a basename collision"
[ -f other/notes.md ] && ok "the refused source file is still there" || bad "migrate lost the colliding source file"
# the refusal must not have touched the REAL index on its way out (die after `git rm --cached`)
eq "" "$(git diff --cached --name-only)" "a refused migrate leaves the real index untouched"
eq "other/notes.md" "$(git ls-files other/notes.md)" "a refused migrate leaves the path tracked"
# happy path on a TRACKED file: moved and untracked
mkdir -p src2 && printf 'z\n' > src2/notes2.md && git add src2/notes2.md && git commit -q -m "second tracked note"
bash "$NS" migrate src2/notes2.md >/dev/null 2>&1
eq "" "$(git ls-files src2/notes2.md)" "migrate untracked the tracked file it moved"

# --- new: creates a dated stub at creation time, refuses a caller-supplied date and a collision ---
TODAY="$(date -u +%F)"
bash "$NS" new fold-check >/dev/null 2>&1
eq "1" "$([ -f "docs/_local/${TODAY}-fold-check.md" ] && echo 1 || echo 0)" \
  "new creates <today's real UTC date>-<slug>.md"
eq "STATUS: LIVE" "$(head -n1 "docs/_local/${TODAY}-fold-check.md")" "new's stub line 1 is exactly STATUS: LIVE"

bash "$NS" new 2026-01-01-caller-dated >/dev/null 2>&1 \
  && bad "new accepted a caller-supplied leading date" || ok "new refuses a caller-supplied leading date"

bash "$NS" new fold-check >/dev/null 2>&1 \
  && bad "new overwrote an existing destination" || ok "new refuses to overwrite an existing destination"

# --from: verbatim copy, STATUS: LIVE prepended only when the source lacks one. Sourced from
# inside the sandbox ($W), never a fixed /tmp name - a predictable shared-host path would break
# this file's own "never touches real state outside the sandbox" convention.
printf 'plain content, no status line\n' > "$W/src.md"
bash "$NS" new from-plain --from "$W/src.md" >/dev/null 2>&1
eq "STATUS: LIVE" "$(head -n1 "docs/_local/${TODAY}-from-plain.md")" "--from prepends STATUS: LIVE when the source lacks one"
grep -qxF 'plain content, no status line' "docs/_local/${TODAY}-from-plain.md" \
  && ok "--from's content survives verbatim" || bad "--from's content did not survive"

printf 'STATUS: SHIPPED\n\nalready terminal\n' > "$W/src2.md"
bash "$NS" new from-shipped --from "$W/src2.md" >/dev/null 2>&1
eq "STATUS: SHIPPED" "$(head -n1 "docs/_local/${TODAY}-from-shipped.md")" \
  "--from does not double a STATUS line the source already has"

# --from resolves a RELATIVE path against the caller's own cwd, not the repo root (the script cd's
# to $ROOT before any subcommand body runs)
mkdir -p "$W/elsewhere" && printf 'relative source\n' > "$W/elsewhere/rel.md"
( cd "$W/elsewhere" && bash "$NS" new from-relative --from rel.md >/dev/null 2>&1 )
grep -qxF 'relative source' "docs/_local/${TODAY}-from-relative.md" \
  && ok "--from resolves a relative path against the caller's cwd" \
  || bad "--from resolved a relative path against the wrong directory"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for hygiene-commit-guard.sh. Runnable: `sh hygiene-commit-guard.selfcheck.sh`.
# Builds a real throwaway git repo under a tmpdir since this guard reads `git diff`/`git status` off
# the actual working directory (via the payload's .cwd), not off stdin JSON alone.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
GUARD="$DIR/hygiene-commit-guard.sh"
# decision/breadcrumb lines go to a SANDBOX log, never the real kit's .state/guards.log (opus reviewer, Wave D:
# in-place selfchecks had filled the live record with fixture noise)
SBLOG="$(mktemp -d)/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG"
fail=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT

cd "$WORK" || exit 1
git init -q
git config user.email test@test.local
git config user.name test

run() { # $1=cmd -> deny|allow
  out="$(jq -n --arg x "$1" --arg c "$WORK" '{cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then echo deny; else echo allow; fi
}

check() { # $1=want $2=cmd (repo state already set up by the caller)
  want="$1"; cmd="$2"
  got="$(run "$cmd")"
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}

reset_repo() { git reset -q >/dev/null 2>&1 || true; git checkout -q -- . 2>/dev/null || true; git clean -fdq >/dev/null 2>&1 || true; }

# Fixture validity FIRST: every glyph fixture below uses \NNN octal, the ONE printf escape POSIX
# guarantees. The first cut used \xHH hex - a bashism dash's printf emits literally, so on Debian-family
# sh the fixtures never contained real glyphs and 10 of 26 assertions failed against a correct guard
# (cold-review F1, 2026-08-10). This assert makes that divergence a loud fixture error, never a
# silent wrong-reason pass.
[ "$(printf 'x\342\200\224\n' | wc -c)" -eq 5 ] || { echo "FIXTURE INVALID: printf octal escape did not emit glyph bytes"; exit 1; }

# --- staged / -a / --all cases ------------------------------------------------------------------
printf 'baseline\n' > f.txt; git add f.txt; git commit -q -m init

printf 'a line with an em\342\200\224dash\n' > f.txt; git add f.txt
check deny 'git commit -m "test"'
reset_repo

printf 'a "curly\342\200\235 quote line\n' > f.txt; git add f.txt
check deny 'git commit -q -F -'
reset_repo

printf 'a nbsp\302\240line\n' > f.txt; git add f.txt
check deny 'echo hi && git commit -m x'
reset_repo

printf 'a plain ascii line\n' > f.txt; git add f.txt
check allow 'git commit -m "test"'
reset_repo

check allow 'git status'
check allow 'git add f.txt'
reset_repo

# regression (2026-08-06 review round 1): -a/--all stages an UNSTAGED tracked-file violation.
printf 'a line with an em\342\200\224dash\n' > f.txt   # NOT staged
check deny 'git commit -am "test"'
reset_repo
printf 'a line with an em\342\200\224dash\n' > f.txt
check deny 'git commit --all -m "test"'
reset_repo
printf 'a plain ascii line\n' > f.txt
check allow 'git commit -am "test"'
reset_repo

# regression (round 2, HIGH): `git add X && git commit` (NO -a flag at all) - the class the -a fix
# only patched one instance of. Unstaged-then-added-in-the-same-command tracked-file modification.
printf 'a line with an em\342\200\224dash\n' > f.txt   # NOT staged yet
check deny 'git add f.txt && git commit -m "test"'
reset_repo
printf 'a plain ascii line\n' > f.txt
check allow 'git add f.txt && git commit -m "test"'
reset_repo

# regression (round 2, HIGH continued): a brand-new UNTRACKED file added and committed in one call.
printf 'a new file with an em\342\200\224dash\n' > new.txt
check deny 'git add new.txt && git commit -m "add new file"'
rm -f new.txt; reset_repo
printf 'a clean new file\n' > new.txt
check allow 'git add . && git commit -m "add new file"'
rm -f new.txt; reset_repo

# regression (round 2, MEDIUM): the commit MESSAGE itself carries the violation, clean diff otherwise.
EMDASH="$(printf '\342\200\224')"
printf 'a plain ascii line\n' > f.txt; git add f.txt
check deny "git commit -m \"refactor ${EMDASH} clean up\""
reset_repo
printf 'a plain ascii line\n' > f.txt; git add f.txt
check allow 'git commit -m "refactor - clean up"'
reset_repo

# regression (round 2, LOW): --author (a long option containing "a") must not need special-casing
# any more (the whole -a/--all token-detection loop was removed - diff is scanned unconditionally
# now), so this needs no exclusion arm to pass; use DIRTY unstaged content to prove it's not passing
# for the wrong reason (i.e. the guard genuinely scans regardless of --author's presence).
printf 'a line with an em\342\200\224dash\n' > f.txt   # unstaged, tracked
check deny 'git commit --author="Test <t@t.com>" -m x'
reset_repo

# regression (round 3, HIGH): a commit run from a SUBDIRECTORY must still scan untracked files -
# `git status --porcelain` paths are repo-root-relative, the guard must resolve against the real top.
mkdir -p sub
run_in_subdir() { # $1=cmd -> deny|allow, cwd = WORK/sub instead of WORK
  out="$(jq -n --arg x "$1" --arg c "$WORK/sub" '{cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then echo deny; else echo allow; fi
}
check_subdir() { want="$1"; cmd="$2"; got="$(run_in_subdir "$cmd")"
  if [ "$got" = "$want" ]; then printf 'ok   [%s] (subdir) %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : (subdir) %s\n' "$want" "$got" "$cmd"; fail=1; fi
}
printf 'a new file with an em\342\200\224dash\n' > new.txt
check_subdir deny 'git add new.txt && git commit -m "add new file"'
rm -f new.txt; reset_repo
printf 'a clean new file\n' > new.txt
check_subdir allow 'git add new.txt && git commit -m "add new file"'
rm -f new.txt; reset_repo
rmdir sub 2>/dev/null || true

# F-cwd-bypass (2026-08-16): payload cwd points at an UNRELATED repo, but the command itself `cd`s
# into WORK before committing - guard must resolve the EFFECTIVE cwd (guard_resolve_cwd), not the raw
# payload field, or a `cd otherrepo && git commit` silently scans the wrong (or no) tree.
OTHER="$(mktemp -d)"
(cd "$OTHER" && git init -q && git config user.email t@t && git config user.name t && printf x > f && git add f && git commit -qm init)
run_in_other() { # $1=cmd -> deny|allow, payload cwd = OTHER
  out="$(jq -n --arg x "$1" --arg c "$OTHER" '{cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then echo deny; else echo allow; fi
}
check_other() { want="$1"; cmd="$2"; got="$(run_in_other "$cmd")"
  if [ "$got" = "$want" ]; then printf 'ok   [%s] (cd-elsewhere) %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : (cd-elsewhere) %s\n' "$want" "$got" "$cmd"; fail=1; fi
}
printf 'a line with an em\342\200\224dash\n' > f.txt; git add f.txt
check_other deny "cd $WORK && git commit -m \"test\""
reset_repo

# `git -C <path> commit` used to bypass this guard OUTRIGHT (COMMIT_SEG never matched it at all) -
# CMDPOS_COMMIT_FRAG follow-up, 2026-08-16.
printf 'a line with an em\342\200\224dash\n' > f.txt; git add f.txt
check_other deny "git -C $WORK commit -m \"test\""
reset_repo

# Wrapper shapes (Tier 1 review T1.2, 2026-08-16): sudo / paren used to bypass this guard OUTRIGHT.
# Payload-level pin. The paren case also exercises the `git add` leg through the wrapper (opus
# reviewer: `(git add . && git commit)` used to fire the commit half and blind the add half) - the
# violation is in an UNTRACKED file, so only the add-gated untracked scan can catch it.
printf 'a line with an em\342\200\224dash\n' > f.txt; git add f.txt
check deny "sudo git commit -m \"test\""
reset_repo
printf 'a line with an em\342\200\224dash\n' > untracked.txt
check_other deny "(cd $WORK && git add untracked.txt && git commit -m \"test\")"
check_other allow "(cd $WORK && git commit -m \"test\")"    # control: no add present -> untracked scan does not run
reset_repo

# gap-closure wave 4 (2026-08-16): `--git-dir=`/`--work-tree=` DENY unconditionally, before any cwd
# resolution or content scan - even on an otherwise-CLEAN tree (no glyph violation at all), proving
# this is not the glyph deny firing coincidentally but the new unresolved-repo-flag deny specifically.
check allow 'git commit -m "test"'   # sanity: this repo is otherwise clean right now
check deny 'git --git-dir='"$WORK"'/.git commit -m "test"'
check deny 'git --work-tree='"$WORK"' commit -m "test"'
check deny 'git --git-dir '"$WORK"'/.git commit -m "test"'   # separated form too

# CRITICAL falsifier (opus advisor, 2026-08-16): a commit MESSAGE merely containing the text
# "--git-dir" must NOT deny - this is the exact shape that would have made the escalation a
# wrong-deny generator if built on the ORIGINAL substring-grep breadcrumb instead of the bounded
# guard_unresolved_repo_flag(). Clean tree, no glyph, no real flag - must allow.
check allow 'git commit -m "docs: explain --git-dir for advanced users"'
check allow 'git commit -m "mentions --work-tree in a comment"'

# T1.10 (2026-08-16): an UNRESOLVABLE `cd`/`-C` target (the dir does not exist at PreToolUse time -
# `mkdir X && cd X && git commit` creates it only when the command RUNS) must DENY citing the target,
# and must NOT fall back to scanning the payload cwd: WORK carries a staged glyph violation here, and
# the pre-fix guard scanned WORK and denied on THAT glyph (three live false denials, 2026-08-16). The
# assertion is on the reason TEXT, not just deny-vs-allow - the glyph deny is also a deny.
reason() { jq -n --arg x "$1" --arg c "$WORK" '{cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
printf 'a line with an em\342\200\224dash\n' > f.txt; git add f.txt
FRESH="$OTHER/fresh-$$"          # does not exist; OTHER does (so the mkdir would succeed at run time)
R="$(reason "mkdir $FRESH && cd $FRESH && git commit -m x")"
if printf '%s' "$R" | grep -aq "cannot be resolved at check time" && printf '%s' "$R" | grep -aqF "$FRESH" && ! printf '%s' "$R" | grep -aq "output-hygiene violation"; then
  printf 'ok   [deny] T1.10: mkdir X && cd X && git commit -> declines citing X, no glyph scan of the payload cwd\n'
else printf 'FAIL T1.10: mkdir X && cd X && git commit did not decline on X (reason: %.160s)\n' "$R"; fail=1; fi
R="$(reason "mkdir $FRESH && git -C $FRESH commit -m x")"
if printf '%s' "$R" | grep -aq "cannot be resolved at check time" && ! printf '%s' "$R" | grep -aq "output-hygiene violation"; then
  printf 'ok   [deny] T1.10: -C into a not-yet-existing dir -> declines, no glyph scan of the payload cwd\n'
else printf 'FAIL T1.10: -C into missing dir did not decline (reason: %.160s)\n' "$R"; fail=1; fi
R="$(reason 'cd "$REPO" && git commit -m x')"
if printf '%s' "$R" | grep -aq "cannot be resolved at check time" && ! printf '%s' "$R" | grep -aq "output-hygiene violation"; then
  printf 'ok   [deny] T1.10: cd "$VAR" (non-literal) -> declines, no glyph scan of the payload cwd\n'
else printf 'FAIL T1.10: cd "$VAR" did not decline (reason: %.160s)\n' "$R"; fail=1; fi
# controls: a RESOLVABLE cd still scans the right tree - OTHER is clean (allow), WORK dirty (glyph deny)
check_other allow "cd $OTHER && git commit -m x"
R="$(reason "cd $WORK && git commit -m x")"
if printf '%s' "$R" | grep -aq "output-hygiene violation"; then printf 'ok   [deny] T1.10 control: resolvable cd into the dirty repo still scans it (glyph deny)\n'
else printf 'FAIL T1.10 control: resolvable cd lost the glyph scan (reason: %.160s)\n' "$R"; fail=1; fi
reset_repo
rm -rf "$OTHER"

# regression (round 3, LOW): a payload with NO .cwd must breadcrumb distinctly - isolated temp COPY
# of the guard (BASE resolves script-relative, not cwd-relative, so just `cd`-ing into a tmpdir and
# running the real $GUARD would still write to the REAL kit's .state/guards.log) so this doesn't
# pollute production breadcrumbs.
T2="$(mktemp -d)"; mkdir -p "$T2/scripts"; cp "$GUARD" "$T2/scripts/hygiene-commit-guard.sh"
cp "$DIR/guard-cmdpos.sh" "$T2/scripts/" 2>/dev/null || true   # the guard sources the shared splitter
if (cd "$T2" && git init -q >/dev/null 2>&1); then
  jq -n '{tool_input: {command: "git commit -m x"}}' | (cd "$T2" && AGENT_TIERS_GUARDS_LOG= sh "$T2/scripts/hygiene-commit-guard.sh") >/dev/null 2>&1
fi
if [ -f "$T2/.state/guards.log" ] && grep -aq "no .cwd in payload" "$T2/.state/guards.log"; then
  printf 'ok   [breadcrumb] no-cwd payload logs distinctly\n'
else
  printf 'FAIL no-cwd payload did not breadcrumb\n'; fail=1
fi
rm -rf "$T2"

# --- .hygiene-allow carve-out (2026-08-10) ------------------------------------------------------
# Root-relative allowlisted paths may contain the glyphs (they document them); everything else,
# including the commit MESSAGE, still denies. Absent file = pre-seam behavior (already proven by
# every case above, which ran with no .hygiene-allow present).
printf 'commands/hygiene.md\n# a comment line\n\n' > .hygiene-allow
mkdir -p commands
printf 'documents the em\342\200\224dash glyph\n' > commands/hygiene.md; git add commands/hygiene.md .hygiene-allow
check allow 'git commit -m "allowlisted glyph doc"'
reset_repo

printf 'commands/hygiene.md\n' > .hygiene-allow
printf 'stray em\342\200\224dash\n' > f.txt; git add f.txt .hygiene-allow
check deny 'git commit -m "non-allowlisted file still denies"'
reset_repo

# untracked halves: allowlisted untracked file passes, sibling untracked violation still denies
printf 'commands/hygiene.md\n' > .hygiene-allow
mkdir -p commands
printf 'documents the em\342\200\224dash glyph\n' > commands/hygiene.md
check allow 'git add . && git commit -m "untracked allowlisted"'
printf 'stray em\342\200\224dash\n' > other.txt
check deny 'git add . && git commit -m "untracked non-allowlisted"'
rm -f other.txt; reset_repo

# subdir commit still honors the root-anchored allowlist (:(top,exclude) pathspec)
printf 'commands/hygiene.md\n' > .hygiene-allow
mkdir -p sub commands
printf 'documents the em\342\200\224dash glyph\n' > commands/hygiene.md; git add commands/hygiene.md .hygiene-allow
check_subdir allow 'git commit -m "allowlisted from subdir"'
reset_repo; rmdir sub 2>/dev/null || true

# commit-message text is never carved out, allowlist present or not
printf 'commands/hygiene.md\n' > .hygiene-allow
printf 'plain ascii\n' > f.txt; git add f.txt .hygiene-allow
check deny "git commit -m \"msg with ${EMDASH} glyph\""
reset_repo
rm -f .hygiene-allow

# --- hygiene_scope (bundle-9 W3-2, 2026-08-23) -------------------------------------------------------
# Default is repo-wide: an unrelated dirty tracked file denies the commit. `narrow` scopes the unstaged
# leg to what THIS command stages. The config is read by a security guard, so every unparsable or
# unrecognised value must resolve to the STRICTER branch, not to "skip the scan".
#
# Run against an ISOLATED KIT COPY, not the real $GUARD: the guard resolves its second config leg from
# its own location, so the real kit-config.md would decide these verdicts and the suite would fail on a
# machine where the operator ran `install-flat.sh --hygiene-scope=narrow` (opus reviewer 2026-08-23 -
# a selfcheck whose verdict depends on machine config is the off-instrument class this kit has a rule
# about). The copy has no kit-config.md, which also makes leg 3 (no config anywhere) testable at all.
T3="$(mktemp -d)"; mkdir -p "$T3/scripts"
cp "$GUARD" "$T3/scripts/hygiene-commit-guard.sh"; cp "$DIR/guard-cmdpos.sh" "$T3/scripts/"
GUARD3="$T3/scripts/hygiene-commit-guard.sh"
run3() { # $1=cmd -> deny|allow, against the isolated kit copy
  out="$(jq -n --arg x "$1" --arg c "$WORK" '{cwd: $c, tool_input: {command: $x}}' | AGENT_TIERS_GUARDS_LOG="$T3/guards.log" sh "$GUARD3" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then echo deny; else echo allow; fi
}
check3() { want="$1"; cmd="$2"; got="$(run3 "$cmd")"
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}

EMD="$(printf '\342\200\224')"
printf 'clean\n' > unrelated.txt && git add unrelated.txt && git commit -qm "unrelated baseline"
printf 'has an %s dash\n' "$EMD" > unrelated.txt          # dirty, tracked, NOT part of the next commit
printf 'clean\n' > wanted.txt

scope_off() { rm -f "$WORK/.claude/agent-tiers.local.md" 2>/dev/null; }
scope_set() { mkdir -p "$WORK/.claude" && printf 'hygiene_scope: %s\n' "$1" > "$WORK/.claude/agent-tiers.local.md"; }

scope_off
check3 deny "git commit -m x"                                    # no config anywhere: default repo scope (leg 3)
scope_set narrow
check3 allow "git commit -m x"                                   # narrow: that file is not what this command stages
check3 deny "git add unrelated.txt && git commit -m x"           # ...but naming it puts it back in scope
check3 deny "git commit -am x"                        # -a stages every tracked change
check3 deny "git commit -am\"wip\""                    # ...including the no-space bundled form
check3 deny "git add . && git commit -m x"                       # add . stages it too
check3 deny "git add -u && git commit -m x"                      # as does add -u
check3 deny "git commit -m x unrelated.txt"           # pathspec commit: no index, no add, still this commit
# a DIRECTORY token has to put everything under it in scope
mkdir -p sub && printf 'clean\n' > sub/x.txt && git add sub/x.txt && git commit -qm "sub baseline"
printf 'sub has an %s dash\n' "$EMD" > sub/x.txt
check3 deny "git add sub && git commit -m x"
git checkout -q -- sub/x.txt
# fail toward the stricter branch on anything unrecognised
scope_set nonsense
check3 deny "git commit -m x"
scope_set ""
check3 deny "git commit -m x"
printf 'hygiene_scope: narrow extra\n' > "$WORK/.claude/agent-tiers.local.md"
check3 deny "git commit -m x"                                    # two values on one line is not a value
printf 'hygiene_scope: narrow\nhygiene_scope: repo\n' > "$WORK/.claude/agent-tiers.local.md"
check3 deny "git commit -m x"                                    # two LINES is ambiguous -> repo, not first-wins
# a narrow-scoped run still catches what this commit IS introducing
scope_set narrow
printf 'also an %s dash\n' "$EMD" > wanted.txt
check3 deny "git add wanted.txt && git commit -m x"
# ...and still honours the .hygiene-allow carve-out on the unstaged leg (the friendlier scope must not
# be the one that false-denies an allowlisted file)
rm -f wanted.txt   # an untracked glyph file left by the case above would trip the untracked scan
printf 'commands/hygiene.md\n' > .hygiene-allow
mkdir -p commands && printf 'clean\n' > commands/hygiene.md
git add commands/hygiene.md .hygiene-allow && git commit -qm "allowlist baseline"
printf 'documents the em%sdash glyph\n' "$EMD" > commands/hygiene.md
check3 allow "git add commands/hygiene.md && git commit -m x"
rm -f .hygiene-allow
# the SECOND config leg (the kit's own kit-config.md) is what a machine-wide install writes
scope_off
printf 'hygiene_scope: narrow\n' > "$T3/kit-config.md"
check3 allow "git commit -m x"                                   # kit-level narrow applies when no repo file exists
scope_set repo
check3 deny "git commit -m x"                                    # ...and the repo file wins over it
scope_off; rm -f "$T3/kit-config.md"
check3 deny "git commit -m x"
rm -rf "$T3"
git checkout -q -- unrelated.txt 2>/dev/null; rm -f wanted.txt
reset_repo

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

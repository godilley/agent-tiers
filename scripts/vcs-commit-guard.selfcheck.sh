#!/usr/bin/env sh
# kit-scope: shared
# Self-check for vcs-commit-guard.sh. Runnable: `sh vcs-commit-guard.selfcheck.sh`. Builds a sandboxed
# kit copy (script + guard-cmdpos.sh + a synthetic kit-config.md, so BASE resolves correctly) AND a real
# throwaway git repo for the WORK tree (the guard reads git state off the payload's .cwd), same
# two-tree idiom as hygiene-commit-guard.selfcheck.sh. Exits non-zero on first failure.
set -u
SRC_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"   # macOS TMPDIR ends in "/" - a "//" in T breaks every pwd comparison (CI, 2026-08-16)
T="${TMPBASE}/at-vcscommit-selfcheck.$$"
rm -rf "$T"; mkdir -p "$T/kit/scripts" "$T/work" || fail "cannot build sandbox"
cp "$SRC_DIR/vcs-commit-guard.sh" "$T/kit/scripts/" || fail "cannot copy guard"
cp "$SRC_DIR/guard-cmdpos.sh" "$T/kit/scripts/" || fail "cannot copy guard-cmdpos.sh"
GUARD="$T/kit/scripts/vcs-commit-guard.sh"
WORK="$T/work"
trap 'rm -rf "$T"' EXIT

# kit-level fallback (vcs_defaults) - used only when WORK has no .claude/agent-tiers.local.md.
cat > "$T/kit/kit-config.md" <<'EOF'
vcs_defaults:
  resume_session:       ignore-personal   # RESUME_SESSION.md (personal handoff)
  task_agents:           ignore-personal   # .claude/agents/<prefix>-*.md (placeholder, not a real path)
---
EOF

cd "$WORK" || exit 1
git init -q
git config user.email test@test.local
git config user.name test
printf 'baseline\n' > f.txt
git add f.txt; git commit -q -m init

ask() { # $1=cmd -> ask|allow
  out="$(jq -n --arg x "$1" --arg c "$WORK" '{cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"ask"'; then echo ask; else echo allow; fi
}
denied() { # $1=cmd -> true if it EVER emits deny (must never happen)
  out="$(jq -n --arg x "$1" --arg c "$WORK" '{cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
  printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'
}
check() { want="$1"; cmd="$2"; got="$(ask "$cmd")"
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}
ask_in() { # $1=cwd $2=cmd -> ask|allow
  out="$(jq -n --arg x "$2" --arg c "$1" '{cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"ask"'; then echo ask; else echo allow; fi
}
check_in() { cwd="$1"; want="$2"; cmd="$3"; got="$(ask_in "$cwd" "$cmd")"
  if [ "$got" = "$want" ]; then printf 'ok   [%s] (cwd=%s) %s\n' "$got" "$(basename "$cwd")" "$cmd"; else
    printf 'FAIL want=%s got=%s : (cwd=%s) %s\n' "$want" "$got" "$cwd" "$cmd"; fail=1; fi
}
fail=0
# -e .claude: the project-override fixture (.claude/agent-tiers.local.md) is itself untracked in this
# sandbox (matching real usage - it's ignore-personal), so a plain `git clean -fdq` would delete it
# between test cases. Excluded so it persists across resets; tests that need a DIFFERENT fixture content
# overwrite the file explicitly instead of relying on clean to remove the old one.
reset_repo() { git reset -q >/dev/null 2>&1 || true; git checkout -q -- . 2>/dev/null || true; git clean -fdq -e .claude >/dev/null 2>&1 || true; rm -f RESUME_SESSION.md 2>/dev/null; }

# --- fallback to kit-config.md vcs_defaults (no project override file yet) ---
printf 'handoff\n' > RESUME_SESSION.md; git add -f RESUME_SESSION.md
check ask 'git commit -m "test"'
reset_repo

printf 'clean file\n' > f.txt; git add f.txt
check allow 'git commit -m "test"'
reset_repo

# --- project override takes precedence (agent-tiers.local.md) ---
mkdir -p "$WORK/.claude"
cat > "$WORK/.claude/agent-tiers.local.md" <<'EOF'
vcs_policy:
  resume_session:       ignore-personal   # RESUME_SESSION.md (also covered by ~/.gitignore_global)
  attempts_log:         ignore-personal   # ATTEMPTS.md scratch
---
EOF

# 1. staged ignore-* file -> ask
printf 'handoff v2\n' > RESUME_SESSION.md; git add -f RESUME_SESSION.md
check ask 'git commit -m "test"'
reset_repo

# 2+3 share ONE fixture on purpose: a TRACKED, dirty RESUME_SESSION.md, checked BOTH without and with
# `-a`. An UNTRACKED dirty file would make case 2 pass for the wrong reason - `git diff --name-only`
# never lists an untracked path regardless of `-a`, so that fixture would still pass even with the `-a`
# gate deleted from the guard. Using the same tracked-dirty state for both proves `-a` is the actual
# deciding factor, not an accident of which file shape was used.
PRE_TRACK_REF="$(git rev-parse HEAD)"
printf 'handoff tracked\n' > RESUME_SESSION.md; git add -f RESUME_SESSION.md; git commit -q -m "track it (fixture setup)"
printf 'handoff tracked, modified\n' > RESUME_SESSION.md   # dirty, TRACKED, no -a yet

# 2. THE regression this guard exists to avoid: a TRACKED ignore-* file merely DIRTY (unstaged, no -a)
#    while committing something else entirely -> must NOT ask (hygiene-commit-guard.sh's repo-wide
#    union would have false-positived here; this guard must not copy that).
printf 'clean file 2\n' > f.txt; git add f.txt
check allow 'git commit -m "unrelated change"'

# 3. `-a`/`--all` DOES pick up the identical unstaged TRACKED change.
check ask 'git commit -am "test"'

# Hard-reset to the pre-fixture ref (not checkout+rm --cached: once a path is committed it stays part
# of history, and undoing "tracked" by hand left a stale staged-deletion that leaked into later tests -
# a clean rewind is the reliable fix).
git reset -q --hard "$PRE_TRACK_REF"
rm -f RESUME_SESSION.md
reset_repo

# 4. `git add RESUME_SESSION.md && git commit` in ONE call - not staged yet at hook-time.
printf 'handoff v3\n' > RESUME_SESSION.md
check ask 'git add RESUME_SESSION.md && git commit -m "test"'
reset_repo

# 5. `git add . && git commit` (whole-tree) sweeps an untracked ignore-* file. Uses ATTEMPTS.md, not
#    RESUME_SESSION.md: this machine's real ~/.gitignore_global already excludes RESUME_SESSION.md, so
#    `git status --untracked-files=all` never lists it in the FIRST place here - which is fine (`git
#    add .` structurally can't stage an already-gitignored file either), but it means that fixture can't
#    exercise this code path on this host. ATTEMPTS.md has no such global exclude.
printf 'scratch\n' > ATTEMPTS.md
check ask 'git add . && git commit -m "test"'
rm -f ATTEMPTS.md
reset_repo

# 6. `git add . && git commit` with NO ignore-* file present -> allow.
printf 'clean file 3\n' > f.txt
check allow 'git add . && git commit -m "test"'
reset_repo

# 6b. `git add -u && git commit` (no `.`, no `-A`) is the SAME "tracked-repo-wide" case `-a` on commit
#     handles, just spelled on `add` - must ALSO catch a tracked, unstaged-modified ignore-* file.
PRE_TRACK_REF2="$(git rev-parse HEAD)"
printf 'handoff tracked\n' > RESUME_SESSION.md; git add -f RESUME_SESSION.md; git commit -q -m "track it (fixture setup 2)"
printf 'handoff tracked, modified again\n' > RESUME_SESSION.md
check ask 'git add -u && git commit -m "test"'
git reset -q --hard "$PRE_TRACK_REF2"
rm -f RESUME_SESSION.md
reset_repo

# 6c. `--` means end-of-options and stages NOTHING by itself - must NOT be treated as whole-tree (this
#     is the exact false-`ask` class the guard exists to avoid: an untracked ignore-* file merely
#     present in the tree, on a commit that provably cannot include it).
printf 'not staged by --\n' > ATTEMPTS.md
check allow 'git add -- f.txt && git commit -m "test"'
rm -f ATTEMPTS.md
reset_repo

# 7. placeholder path token (<prefix>) must be SKIPPED (not falsely matched) and breadcrumbed - proven
#    with a SECOND real row alongside it, so this pins the skip itself rather than an incidentally-empty
#    PAIRS list (an always-allow guard would pass an empty-PAIRS case identically).
rm -f "$T/kit/.state/guards.log" 2>/dev/null
mkdir -p "$WORK/.claude/agents"
printf 'agent def\n' > "$WORK/.claude/agents/foo-bar.md"
cat > "$WORK/.claude/agent-tiers.local.md" <<'EOF'
vcs_policy:
  task_agents:            ignore-personal   # .claude/agents/<prefix>-*.md (placeholder)
  attempts_log:           ignore-personal   # ATTEMPTS.md scratch
---
EOF
git add .claude/agents/foo-bar.md
check allow 'git commit -m "add task agent"'
if grep -aq "skipping placeholder path token" "$T/kit/.state/guards.log" 2>/dev/null; then
  printf 'ok   [breadcrumb] placeholder token skip breadcrumbed\n'
else
  printf 'FAIL placeholder token skip was not breadcrumbed\n'; fail=1
fi
git rm -rq --cached .claude/agents 2>/dev/null || true
rm -rf "$WORK/.claude/agents"
# restore the resume_session policy for later checks
cat > "$WORK/.claude/agent-tiers.local.md" <<'EOF'
vcs_policy:
  resume_session:       ignore-personal   # RESUME_SESSION.md (also covered by ~/.gitignore_global)
---
EOF
reset_repo

# 7b. prefix-boundary: a policy dir `docs/_local` must NOT match `docs/_local2/...` (the matcher
#     requires the `/` separator, not a naive string prefix).
cat > "$WORK/.claude/agent-tiers.local.md" <<'EOF'
vcs_policy:
  private_notes:         ignore-personal   # docs/_local/ notes dir
---
EOF
mkdir -p docs/_local2
printf 'not the same dir\n' > docs/_local2/f.md
git add docs/_local2/f.md
check allow 'git commit -m "add unrelated docs dir"'
git rm -rq --cached docs/_local2 2>/dev/null || true
rm -rf docs/_local2
cat > "$WORK/.claude/agent-tiers.local.md" <<'EOF'
vcs_policy:
  resume_session:       ignore-personal   # RESUME_SESSION.md (also covered by ~/.gitignore_global)
---
EOF
reset_repo

# 7c. a QUOTED `git add` token still matches (quote bytes stripped before comparison).
printf 'handoff v6\n' > RESUME_SESSION.md
check ask 'git add "RESUME_SESSION.md" && git commit -m "test"'
reset_repo

# 7d. a token typed from a SUBDIRECTORY resolves relative to THAT subdir, not the repo root: `git add
#     RESUME_SESSION.md` run from sub/ means sub/RESUME_SESSION.md, which is NOT the root policy path,
#     and must NOT false-ask. (Before the $PREFIX fix, the un-anchored token compared equal to the root
#     pattern regardless of which directory it was typed from - a false ask on an unrelated file.)
mkdir -p sub
check_in "$WORK/sub" allow 'git add RESUME_SESSION.md && git commit -m "test"'
rmdir sub 2>/dev/null || true
reset_repo

# 7e. payload cwd points at an UNRELATED repo, but the command itself `cd`s into WORK before
#     committing - guard must resolve the EFFECTIVE cwd (guard_resolve_cwd), not the raw payload
#     field (F-cwd-bypass 2026-08-16: this shape silently skipped the guard before the fix).
OTHER="$(mktemp -d)"
(cd "$OTHER" && git init -q && git config user.email t@t && git config user.name t && printf x > f && git add f && git commit -qm init)
printf 'handoff v7\n' > RESUME_SESSION.md; git add -f RESUME_SESSION.md
check_in "$OTHER" ask "cd $WORK && git commit -m \"test\""
reset_repo

# 7f. `git -C <path> commit` used to bypass this guard OUTRIGHT (COMMIT_SEG never matched it at all) -
#     CMDPOS_COMMIT_FRAG follow-up, 2026-08-16.
printf 'handoff v8\n' > RESUME_SESSION.md; git add -f RESUME_SESSION.md
check_in "$OTHER" ask "git -C $WORK commit -m \"test\""
reset_repo

# 7g. Wrapper shapes (Tier 1 review T1.2, 2026-08-16): sudo / paren used to bypass this guard OUTRIGHT.
#     Payload-level pin (the -C precedent above): commit-half fires through the wrapper.
printf 'handoff v9\n' > RESUME_SESSION.md; git add -f RESUME_SESSION.md
check ask "sudo git commit -m \"test\""
check_in "$OTHER" ask "( cd $WORK && git commit -m \"test\" )"
reset_repo

# 7g. `--git-dir=`/`--work-tree=` mean this guard cannot know which repo's vcs_policy applies - it
#     must DECLINE to scan entirely (exit 0, before any cwd resolution), not silently scan whatever
#     repo the payload cwd happens to be (opus advisor, gap-closure wave 4, 2026-08-16). Real falsifier
#     (not just a log-string check): WORK has the real violation staged (RESUME_SESSION.md, ignore-
#     personal); the payload cwd is OTHER, which is given a DIFFERENT staged ignore-personal file of
#     its own. A guard that failed to decline and fell through to scan the payload cwd anyway (the
#     pre-fix behaviour, breadcrumb-then-proceed) would find OTHER's violation and `ask` - only a
#     genuine decline produces `allow` here, regardless of either repo's content.
rm -f "$T/kit/.state/guards.log" 2>/dev/null
printf 'handoff v9\n' > RESUME_SESSION.md; git add -f RESUME_SESSION.md
mkdir -p "$OTHER/.claude"
cat > "$OTHER/.claude/agent-tiers.local.md" <<'EOF'
vcs_policy:
  resume_session:       ignore-personal   # RESUME_SESSION.md (also covered by ~/.gitignore_global)
EOF
(cd "$OTHER" && printf 'other repo handoff\n' > RESUME_SESSION.md && git add -f RESUME_SESSION.md .claude/agent-tiers.local.md)
OUT="$(jq -n --arg x "git --git-dir=$WORK/.git commit -m \"test\"" --arg c "$OTHER" '{cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$OUT" | grep -aq '"permissionDecision": *"ask"' && fail "did not decline - fell through and scanned the payload cwd (OTHER), found its violation"
grep -aq "declined: unresolved repo-selecting flag" "$T/kit/.state/guards.log" || fail "decline was not logged"

# 7h. T1.10 (2026-08-16): an UNRESOLVABLE `cd`/`-C` target (`mkdir X && cd X && git commit` - X does
#     not exist at PreToolUse time) takes the SAME decline as 7g, never the old "fall back to the
#     payload cwd" (which scanned OTHER here and would find ITS violation -> ask). Same real falsifier
#     as 7g: only a genuine decline yields allow. Plus the resolvable control: `cd $WORK` still scans WORK.
FRESH="$OTHER/fresh-$$"
OUT="$(jq -n --arg x "mkdir $FRESH && cd $FRESH && git commit -m \"test\"" --arg c "$OTHER" '{cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$OUT" | grep -aq '"permissionDecision": *"ask"' && fail "T1.10: did not decline on an unresolvable cd - fell back to the payload cwd (OTHER) and asked on its violation"
grep -aq "declined: unresolvable cd/-C target" "$T/kit/.state/guards.log" || fail "T1.10 decline was not logged"
printf 'ok   [declined] T1.10: mkdir X && cd X && git commit -> not scanned as the payload cwd\n'
check_in "$OTHER" ask "cd $WORK && git commit -m \"test\""   # control: resolvable cd still scans WORK (its violation -> ask)
(cd "$OTHER" && git reset -q RESUME_SESSION.md .claude/agent-tiers.local.md 2>/dev/null; rm -rf .claude RESUME_SESSION.md)
rm -rf "$OTHER"
reset_repo

# 8. never emits deny, for any of the above shapes.
printf 'handoff v5\n' > RESUME_SESSION.md; git add -f RESUME_SESSION.md
denied 'git commit -m "test"' && fail "guard must never emit deny (ask only)"
reset_repo

# 9. no .cwd in payload -> fail-open breadcrumb, no crash, no output.
T2="$(mktemp -d)"; mkdir -p "$T2/scripts"
cp "$SRC_DIR/vcs-commit-guard.sh" "$T2/scripts/"; cp "$SRC_DIR/guard-cmdpos.sh" "$T2/scripts/"
cp "$T/kit/kit-config.md" "$T2/" 2>/dev/null || true
if (cd "$T2" && git init -q >/dev/null 2>&1); then
  out="$(jq -n '{tool_input: {command: "git commit -m x"}}' | (cd "$T2" && sh "$T2/scripts/vcs-commit-guard.sh") 2>/dev/null || true)"
  [ -z "$out" ] || fail "no-cwd payload must produce no output"
fi
if [ -f "$T2/.state/guards.log" ] && grep -aq "no .cwd in payload" "$T2/.state/guards.log"; then
  printf 'ok   [breadcrumb] no-cwd payload logs distinctly\n'
else
  printf 'FAIL no-cwd payload did not breadcrumb\n'; fail=1
fi
rm -rf "$T2"

# Unattended mode (2026-08-23): a policy-path ask becomes an actionable DENY when this session is
# flagged, with the remedy text unchanged; every other session keeps asking. The flag is a file under
# the kit's .state, keyed by session id.
mkdir -p "$T/kit/.state"
dec() { # $1=session_id $2=cmd -> deny|ask|allow
  out="$(jq -n --arg x "$2" --arg c "$WORK" --arg s "$1" '{session_id: $s, cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
  if   printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then echo deny
  elif printf '%s' "$out" | grep -aq '"permissionDecision": *"ask"';  then echo ask
  else echo allow; fi
}
printf 'notes\n' > RESUME_SESSION.md
: > "$T/kit/.state/unattended.s-unatt"
[ "$(dec s-unatt 'git add RESUME_SESSION.md && git commit -m x')" = deny ] \
  && printf 'ok   [deny] unattended session converts the policy ask\n' \
  || { printf 'FAIL unattended session did not convert the policy ask\n'; fail=1; }
[ "$(dec s-other 'git add RESUME_SESSION.md && git commit -m x')" = ask ] \
  && printf 'ok   [ask]  a session without the flag still asks\n' \
  || { printf 'FAIL an unflagged session stopped asking\n'; fail=1; }
# the deny carries the SAME remedy the ask carried - the requirement is unchanged, only its shape
out="$(jq -n --arg x 'git add RESUME_SESSION.md && git commit -m x' --arg c "$WORK" --arg s s-unatt '{session_id: $s, cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$out" | grep -aq 'git restore --staged\|git rm --cached' \
  && printf 'ok   the converted deny keeps its machine-actionable remedy\n' \
  || { printf 'FAIL the converted deny lost its remedy text\n'; fail=1; }
# and it is recorded in guards.log as a deny, like any other decision
grep -aq 'vcs-commit-guard deny: RESUME_SESSION.md' "$T/kit/.state/guards.log" \
  && printf 'ok   the conversion is recorded in guards.log\n' \
  || { printf 'FAIL no deny line in guards.log\n'; fail=1; }
rm -f "$T/kit/.state/unattended.s-unatt" RESUME_SESSION.md

# Subagent caller (2026-08-27): the same "no human behind this ask" case as unattended, converted the
# same way - deny, with the SAME remedy text, but worded at the delegated agent instead.
dec_agent() { # $1=session_id $2=cmd $3=agent_type -> deny|ask|allow
  out="$(jq -n --arg x "$2" --arg c "$WORK" --arg s "$1" --arg a "$3" '{session_id: $s, cwd: $c, tool_input: {command: $x}, agent_type: $a}' | sh "$GUARD" 2>/dev/null || true)"
  if   printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then echo deny
  elif printf '%s' "$out" | grep -aq '"permissionDecision": *"ask"';  then echo ask
  else echo allow; fi
}
printf 'notes\n' > RESUME_SESSION.md
[ "$(dec_agent s-sub 'git add RESUME_SESSION.md && git commit -m x' worker)" = deny ] \
  && printf 'ok   [deny] a subagent caller converts the policy ask\n' \
  || { printf 'FAIL a subagent caller did not convert the policy ask\n'; fail=1; }
[ "$(dec s-sub2 'git add RESUME_SESSION.md && git commit -m x')" = ask ] \
  && printf 'ok   [ask]  a Lead-originated call (no agent_type) is unaffected\n' \
  || { printf 'FAIL a Lead-originated call was wrongly converted\n'; fail=1; }
out="$(jq -n --arg x 'git add RESUME_SESSION.md && git commit -m x' --arg c "$WORK" --arg s s-sub3 --arg a worker '{session_id: $s, cwd: $c, tool_input: {command: $x}, agent_type: $a}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$out" | grep -aq 'git restore --staged\|git rm --cached' \
  && printf 'ok   the subagent-converted deny keeps its machine-actionable remedy\n' \
  || { printf 'FAIL the subagent-converted deny lost its remedy text\n'; fail=1; }
printf '%s' "$out" | grep -aq 'DELEGATED AGENT' \
  && printf 'ok   the subagent deny carries the delegated-agent prefix, not the unattended one\n' \
  || { printf 'FAIL subagent deny missing the delegated-agent prefix\n'; fail=1; }
printf '%s' "$out" | grep -aq 'UNATTENDED MODE' \
  && { printf 'FAIL subagent deny wrongly carries the unattended prefix\n'; fail=1; } \
  || printf 'ok   subagent deny does not carry the unattended prefix\n'
grep -aq 'vcs-commit-guard deny: RESUME_SESSION.md' "$T/kit/.state/guards.log" \
  && printf 'ok   the subagent conversion is recorded in guards.log\n' \
  || { printf 'FAIL no deny line in guards.log for the subagent conversion\n'; fail=1; }
# Non-vacuous precedence check (opus reviewer, 2026-08-27, LOW: the assert above never had the
# unattended marker set, so it passed either way) - flag s-sub3 unattended TOO and confirm subagent
# wording still wins, not the unattended text.
: > "$T/kit/.state/unattended.s-sub3"
out="$(jq -n --arg x 'git add RESUME_SESSION.md && git commit -m x' --arg c "$WORK" --arg s s-sub3 --arg a worker '{session_id: $s, cwd: $c, tool_input: {command: $x}, agent_type: $a}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$out" | grep -aq 'DELEGATED AGENT' \
  && printf 'ok   subagent prefix still wins when the SAME session is also flagged unattended\n' \
  || { printf 'FAIL subagent+unattended: subagent prefix should still win\n'; fail=1; }
printf '%s' "$out" | grep -aq 'UNATTENDED MODE' \
  && { printf 'FAIL subagent+unattended: unattended prefix should not also appear\n'; fail=1; } \
  || printf 'ok   subagent+unattended does not also carry the unattended prefix\n'
rm -f "$T/kit/.state/unattended.s-sub3" RESUME_SESSION.md

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

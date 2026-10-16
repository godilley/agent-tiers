#!/usr/bin/env sh
# kit-scope: shared
# Self-check for memory-content-lint.sh: each rule fires on its own fixture, a REALISTIC frontmatter
# header stays silent (the HIGH this file exists to regression-test - Claude Code's own `originSessionId`
# UUID matches a bare sha regex), a real sha further down still fires, a clean file and a non-memory path
# stay silent, the path gate covers a relocated config dir and an autoMemoryDirectory, the kill switch
# suppresses everything, an unreadable file leaves a breadcrumb, and it never blocks. Runs against real
# files in a throwaway sandbox (the lint reads FPATH off disk, unlike authorship-record which only reads
# the payload) so the real ~/.claude/agent-tiers/.state is never touched. Exits non-zero on first failure.
set -u
SRC="$(dirname "$0")/memory-content-lint.sh"
LIBSRC="$(dirname "$0")/lib/content-rules.sh"
MPSRC="$(dirname "$0")/lib/guard-mempath.sh"   # the shared memory-dir resolver; without it the lint
                                               # degrades to the standard layout and the relocated
                                               # config-dir / autoMemoryDirectory cases below fail
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (lint fails open by design)"; exit 0; }

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"
T="${TMPBASE}/at-memlint-selfcheck.$$"
# Layout mirrors the real thing: <config>/agent-tiers/scripts/... and <config>/projects/<slug>/memory/...
# - CLAUDE_CONFIG_DIR must point at <config> (the PARENT of agent-tiers), matching resume-inject.sh's own
# convention, or the kill-switch path ($CLAUDE_DIR/agent-tiers/.state/off/...) resolves one level wrong.
# The sandbox config dir is literally named .claude (not just "the config dir") because the STANDARD gate
# scopes by PATH SHAPE (*/.claude/projects/*/memory/*), matching the real default ~/.claude/... layout.
rm -rf "$T"; mkdir -p "$T/.claude/agent-tiers/scripts/lib" "$T/.claude/projects/x/memory" "$T/proj" "$T/.claude/agent-tiers/install" "$T/managed" || fail "cannot build sandbox"
cp "$SRC" "$T/.claude/agent-tiers/scripts/" || fail "cannot copy lint"
cp "$LIBSRC" "$T/.claude/agent-tiers/scripts/lib/" || fail "cannot copy library"
cp "$MPSRC" "$T/.claude/agent-tiers/scripts/lib/" || fail "cannot copy mempath library"
# kit-gate.sh runs from this sandbox kit too: managed dir pointed at an empty temp dir, every kit-gate
# input cleared so the user's own options cannot stand the lint down.
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$(dirname "$0")/kit-gate.sh" > "$T/.claude/agent-tiers/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$T/.claude/agent-tiers/scripts/kit-gate.sh" || fail "_kg_managed not rewritten"
cp "$(dirname "$0")/../install/options.tsv" "$T/.claude/agent-tiers/install/"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
LINT="$T/.claude/agent-tiers/scripts/memory-content-lint.sh"
export CLAUDE_CONFIG_DIR="$T/.claude"
export AGENT_TIERS_GUARDS_LOG="$T/.claude/agent-tiers/.state/guards.log"
export CLAUDE_PROJECT_DIR="$T/proj"
unset CONTENT_RULES_NAMES_FILE
trap 'rm -rf "$T"' EXIT

# Emitted payload for a Write/MultiEdit to $1. $2 defaults to Write.
pay() { jq -n --arg p "$1" --arg tn "${2:-Write}" '{hook_event_name:"PostToolUse", tool_name:$tn, tool_input:{file_path:$p, content:"unused"}}'; }
run() { printf '%s' "$1" | sh "$LINT" 2>/dev/null || true; }
run_rc() { printf '%s' "$1" | sh "$LINT" >/dev/null 2>&1; echo $?; }
flagged() { printf '%s' "$1" | grep -q 'additionalContext' && echo YES || echo NO; }

MEMDIR="$T/.claude/projects/x/memory"

# --- fixture validity first ---
SHA_F="$MEMDIR/sha.md"
printf 'kit shipped at 205731d after review\n' > "$SHA_F"
grep -qE '\b[0-9a-f]{7,40}\b' "$SHA_F" || fail "fixture invalid: SHA_F has no sha-shaped token"

COUNT_F="$MEMDIR/count.md"
printf 'fixed 12 files and 4 commits this wave\n' > "$COUNT_F"
grep -qEi '[0-9]+ (files?|commits?)' "$COUNT_F" || fail "fixture invalid: COUNT_F has no derivable count"

DATE_F="$MEMDIR/date.md"
printf 'the 09-02 session was stale and undetected until asked\n' > "$DATE_F"
grep -qE '09-02' "$DATE_F" || fail "fixture invalid: DATE_F has no date fragment"

PR_F="$MEMDIR/pr.md"
printf 'shipped after PR #42 landed\n' > "$PR_F"
grep -qE 'PR #42' "$PR_F" || fail "fixture invalid: PR_F has no PR-number shape"

ISSUE_F="$MEMDIR/issue.md"
printf 'classifier bug filed at kenn-io/agentsview#1269\n' > "$ISSUE_F"

ATTR_F="$MEMDIR/attr.md"
printf 'Operator said the tag never worked\n' > "$ATTR_F"
grep -qE '\b[A-Z][a-z]+ said\b' "$ATTR_F" || fail "fixture invalid: ATTR_F has no attribution shape"

CLEAN_F="$MEMDIR/clean.md"
printf 'the maturity tag was retired because it was never applied in practice\n' > "$CLEAN_F"

# Realistic frontmatter, copied from a real memory file's shape (name/description/metadata incl.
# originSessionId UUID + modified) - the HIGH this selfcheck regression-tests. A real sha further down in
# the BODY must still fire even though the frontmatter's UUID must not.
FRONTMATTER_F="$MEMDIR/frontmatter.md"
cat > "$FRONTMATTER_F" <<'EOF'
---
name: frontmatter-fixture
description: "a realistic memory file header, for the HIGH regression test"
metadata:
  node_type: memory
  type: project
  originSessionId: 33333333-aa70-4813-be63-cccc1234dddd
  modified: 2026-08-23T02:25:46.976Z
---

Everything below is ordinary content with no violation at all.
EOF
FRONTMATTER_SHA_F="$MEMDIR/frontmatter-sha.md"
cat > "$FRONTMATTER_SHA_F" <<'EOF'
---
name: frontmatter-sha-fixture
metadata:
  originSessionId: 44444444-62ec-4b14-9bbb-eeee5678ffff
---

Kit shipped at 205731d, pushed.
EOF

# Id-shaped tokens (2026-09 review): a full UUID or an agent-<hex> token in the BODY must never be
# flagged as a sha (excluded outright, not just relabelled). A bare non-UUID/non-agent hex token remains
# ambiguous and IS still flagged, but with hedged wording. A sha inside a `description:` value (Claude,
# not the harness, writes that field) must still be caught - the real miss the id-line-only blanking closes.
UUID_F="$MEMDIR/uuid.md"
printf 'session 11111111-2222-4333-8444-5555aaaa5555 reviewed the plan\n' > "$UUID_F"
AGENTID_F="$MEMDIR/agentid.md"
printf 'agent id agent-a1b2c3d4e5f60718a handled it\n' > "$AGENTID_F"
BAREHEX_F="$MEMDIR/barehex.md"
printf 'bare token: session 5c7e9a1b started\n' > "$BAREHEX_F"
DESC_SHA_F="$MEMDIR/desc-sha.md"
cat > "$DESC_SHA_F" <<'EOF'
---
name: desc-sha-fixture
description: "fixed via commit e3af7d1, a real find"
metadata:
  originSessionId: 22222222-1111-2222-3333-4444bbbb4444
---

Nothing else of note here.
EOF

# --- 1. Each rule fires on its own fixture. ---
out="$(run "$(pay "$SHA_F")")"
[ "$(flagged "$out")" = YES ] || fail "a git sha in a memory file must be flagged"
printf '%s' "$out" | grep -q 'MEMORY-2' || fail "sha finding must cite MEMORY-2"

out="$(run "$(pay "$COUNT_F")")"
[ "$(flagged "$out")" = YES ] || fail "a derivable count in a memory file must be flagged"

out="$(run "$(pay "$PR_F")")"
[ "$(flagged "$out")" = YES ] || fail "PR #42 must be flagged as a PR number"

out="$(run "$(pay "$ISSUE_F")")"
[ "$(flagged "$out")" = NO ] || fail "a filed GitHub issue number (owner/repo#N) must NOT be flagged as a PR number"

out="$(run "$(pay "$ATTR_F")")"
[ "$(flagged "$out")" = YES ] || fail "an attributed quote in a memory file must be flagged"
printf '%s' "$out" | grep -q 'MEMORY-3' || fail "attribution finding must cite MEMORY-3"

# --- 1b. Date fragment must NOT be flagged as a derivable count (the MEDIUM this selfcheck regression-tests). ---
out="$(run "$(pay "$DATE_F")")"
[ "$(flagged "$out")" = NO ] || fail "a date fragment (09-02 session) must not be flagged as a derivable count, got: $out"

# --- 1c. Frontmatter (the HIGH): a realistic header with an originSessionId UUID must stay silent; a
#          real sha further down in the body of an otherwise-identical file must still fire.
out="$(run "$(pay "$FRONTMATTER_F")")"
[ "$(flagged "$out")" = NO ] || fail "a realistic memory frontmatter header (originSessionId UUID) must not be flagged, got: $out"
out="$(run "$(pay "$FRONTMATTER_SHA_F")")"
[ "$(flagged "$out")" = YES ] || fail "a real sha in the BODY must still fire even though the frontmatter above it must not"
printf '%s' "$out" | grep -q '205731d' || fail "the sha finding should quote the real sha, not the frontmatter UUID"

# --- 1d. Id-shaped tokens: a full UUID or an agent-<hex> id in the BODY is excluded outright; a bare
#          ambiguous hex token still fires, with hedged wording that never instructs deletion; a sha
#          hiding inside a `description:` value is still caught.
out="$(run "$(pay "$UUID_F")")"
[ "$(flagged "$out")" = NO ] || fail "a full UUID in the body must never be flagged as a sha, got: $out"

out="$(run "$(pay "$AGENTID_F")")"
[ "$(flagged "$out")" = NO ] || fail "an agent-<hex> id in the body must never be flagged as a sha, got: $out"

out="$(run "$(pay "$BAREHEX_F")")"
[ "$(flagged "$out")" = YES ] || fail "a bare ambiguous hex token must still be flagged (cannot be told apart from a sha by shape), got: $out"
printf '%s' "$out" | grep -q 'commit sha or an id' || fail "a bare hex token's finding must use hedged wording, got: $out"
printf '%s' "$out" | grep -Eiq 'delete (it|the (token|id))' && fail "the finding must never instruct deleting an id, got: $out"

out="$(run "$(pay "$DESC_SHA_F")")"
[ "$(flagged "$out")" = YES ] || fail "a commit sha inside a description: value must still be caught, got: $out"
printf '%s' "$out" | grep -q 'e3af7d1' || fail "the description-sha finding should quote the real sha, not stay silent"

# --- 2. A clean file stays silent. ---
out="$(run "$(pay "$CLEAN_F")")"
[ "$(flagged "$out")" = NO ] || fail "a clean memory file must not be flagged"

# --- 3. A non-memory path never gets the MEMORY rules (sha, count, attribution all present here); since
#        the repo-state widening a non-memory .md does get that one rule, and this text holds no repo state
#        ("shipped at <sha>" is dated history), so it stays silent. Repo-state on non-memory .md: case 9+.
OUTSIDE="$T/proj/notes.md"
printf 'kit shipped at 205731d, fixed 12 files, Operator said it works\n' > "$OUTSIDE"
out="$(run "$(pay "$OUTSIDE")")"
[ "$(flagged "$out")" = NO ] || fail "a path outside the memory-dir shapes must never get the memory rules"

# --- 3b. Path gate: a relocated CLAUDE_CONFIG_DIR not literally named .claude must still be scanned. ---
ALT="$T/altcfg"
mkdir -p "$ALT/projects/y/memory"
ALT_F="$ALT/projects/y/memory/x.md"
printf 'kit shipped at 205731d after review\n' > "$ALT_F"
out="$(CLAUDE_CONFIG_DIR="$ALT" run "$(pay "$ALT_F")")"
[ "$(flagged "$out")" = YES ] || fail "a relocated CLAUDE_CONFIG_DIR (not named .claude) must still be scanned via its own projects/*/memory/* shape"

# --- 3c. Path gate: autoMemoryDirectory read from the project settings file, ~ expanded. ---
AUTODIR="$T/autodir"
mkdir -p "$AUTODIR" "$T/proj/.claude"
printf '{"autoMemoryDirectory": "%s"}\n' "$AUTODIR" > "$T/proj/.claude/settings.json"
AUTO_F="$AUTODIR/x.md"
printf 'kit shipped at 205731d after review\n' > "$AUTO_F"
out="$(run "$(pay "$AUTO_F")")"
[ "$(flagged "$out")" = YES ] || fail "a file under a configured autoMemoryDirectory must be scanned"
rm -f "$T/proj/.claude/settings.json"

# --- 3c2. Path gate: autoMemoryDirectory read from the USER-scope settings file (CLAUDE_CONFIG_DIR),
#           not just project scope - a real gap the first pass of this selfcheck never exercised.
AUTODIR_USER="$T/autodir-user"
mkdir -p "$AUTODIR_USER"
printf '{"autoMemoryDirectory": "%s"}\n' "$AUTODIR_USER" > "$T/.claude/settings.json"
AUTO_USER_F="$AUTODIR_USER/x.md"
printf 'kit shipped at 205731d after review\n' > "$AUTO_USER_F"
out="$(run "$(pay "$AUTO_USER_F")")"
[ "$(flagged "$out")" = YES ] || fail "a file under a USER-scope autoMemoryDirectory (CLAUDE_CONFIG_DIR/settings.json) must be scanned"
rm -f "$T/.claude/settings.json"

# --- 3c3. Trailing slash on autoMemoryDirectory must not silently stop matching (glob "...//*" never
#           matches ".../x.md" - a real regression this repair round closes).
AUTODIR_SLASH="$T/autodir-slash"
mkdir -p "$AUTODIR_SLASH" "$T/proj/.claude"
printf '{"autoMemoryDirectory": "%s/"}\n' "$AUTODIR_SLASH" > "$T/proj/.claude/settings.json"
AUTO_SLASH_F="$AUTODIR_SLASH/x.md"
printf 'kit shipped at 205731d after review\n' > "$AUTO_SLASH_F"
out="$(run "$(pay "$AUTO_SLASH_F")")"
[ "$(flagged "$out")" = YES ] || fail "a trailing slash on autoMemoryDirectory must be normalised, not silently break the scope gate"
rm -f "$T/proj/.claude/settings.json"

# --- 3d. Fail-open MUST BE OBSERVABLE, not just non-fatal: an invalid settings.json must (a) not error
#          out (exit status captured, not discarded), (b) not widen scope for an out-of-scope path, and
#          (c) NOT suppress linting of an IN-SCOPE file - the actual regression shape this exists to catch
#          is "invalid settings.json makes the lint exit 0 early for EVERY file", which the previous
#          version of this case (silent-OUTSIDE only) could not detect. Proven against a mutant: see the
#          repair-round return text for the run that flipped this from PASS to FAIL and back.
mkdir -p "$T/proj/.claude"
printf 'not valid json {{{\n' > "$T/proj/.claude/settings.json"
IN_SCOPE_F="$MEMDIR/scope-under-bad-settings.md"
printf 'kit shipped at 205731d after review\n' > "$IN_SCOPE_F"
rc=0; err=""
OUT3D="${TMPBASE}/at-memlint-3d-out.$$"
err="$(printf '%s' "$(pay "$OUTSIDE")" | sh "$LINT" 2>&1 1>"$OUT3D")"; rc=$?
out_outside="$(cat "$OUT3D" 2>/dev/null)"; rm -f "$OUT3D"
[ "$rc" = 0 ] || fail "the lint must exit 0 even when a settings file is invalid JSON, got rc=$rc stderr: $err"
[ "$(flagged "$out_outside")" = NO ] || fail "an unreadable/invalid settings.json must not widen scope for an out-of-scope path"
out_inscope="$(run "$(pay "$IN_SCOPE_F")")"
[ "$(flagged "$out_inscope")" = YES ] || fail "an in-scope file under the STANDARD path shape must still be linted when an unrelated settings.json is invalid JSON - a regression here means invalid settings silently disables the whole lint, got: $out_inscope"
rm -f "$T/proj/.claude/settings.json" "$IN_SCOPE_F"

# --- 4. RESUME_SESSION.md duplication. ---
printf 'this exact line is duplicated on purpose for the test case\nother resume content\n' > "$T/proj/RESUME_SESSION.md"
DUP_F="$MEMDIR/dup.md"
printf 'this exact line is duplicated on purpose for the test case\n' > "$DUP_F"
out="$(run "$(pay "$DUP_F")")"
[ "$(flagged "$out")" = YES ] || fail "a line duplicated from RESUME_SESSION.md must be flagged"

# --- 4b. Name-parameterised attribution (2026-09 review): absent names file -> generic patterns only;
#          present names file -> "<Name>'s call", "<Name> caught", "per <Name>", and a same-line quote.
NAMEATTR_F="$MEMDIR/nameattr.md"
printf 'Reviewer caught a real defect during the pass\n' > "$NAMEATTR_F"
out="$(run "$(pay "$NAMEATTR_F")")"
[ "$(flagged "$out")" = NO ] || fail "'Reviewer caught' (a role, not a listed name) must not be flagged with no names file present"

NAMES_F="$T/.claude/agent-tiers/.state/attribution-names"
mkdir -p "$(dirname "$NAMES_F")"
printf 'Operator\n' > "$NAMES_F"
CALL_F="$MEMDIR/call.md"
printf 'Operator caught an asymmetry ("this is what I meant by blocking it")\n' > "$CALL_F"
out="$(CONTENT_RULES_NAMES_FILE="$NAMES_F" run "$(pay "$CALL_F")")"
[ "$(flagged "$out")" = YES ] || fail "a listed name followed by a same-line quote must be flagged once a names file exists"
printf '%s' "$out" | grep -q 'MEMORY-3' || fail "name-parameterised finding must still cite MEMORY-3"
out="$(CONTENT_RULES_NAMES_FILE="$NAMES_F" run "$(pay "$NAMEATTR_F")")"
[ "$(flagged "$out")" = NO ] || fail "'Reviewer caught' must still not be flagged even WITH a names file - only the listed name matches"
rm -f "$NAMES_F"

# --- 5. Kill switch suppresses everything, even the worst fixture. ---
mkdir -p "$T/.claude/agent-tiers/.state/off" && touch "$T/.claude/agent-tiers/.state/off/memory-content-lint"
out="$(run "$(pay "$SHA_F")")"
[ "$(flagged "$out")" = NO ] || fail "kill switch .state/off/memory-content-lint must suppress the lint"
rm -f "$T/.claude/agent-tiers/.state/off/memory-content-lint"

# --- 5b. kit-gate stand-down. Here the kit root and the CLAUDE_CONFIG_DIR marker root are the same
#         directory, so the lint's own marker check would pre-empt kit-gate; AGENT_TIERS_OFF=1 (kit-gate
#         rule 1) reaches kit-gate itself: no output, exit 0, logged.
out="$(printf '%s' "$(pay "$SHA_F")" | AGENT_TIERS_OFF=1 sh "$LINT" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] || fail "kit-gate stand-down: expected exit 0 and empty stdout (rc=$rc)"
grep -aq 'kit-gate standdown memory-content-lint:' "$AGENT_TIERS_GUARDS_LOG" || fail "kit-gate stand-down not logged"
[ "$(flagged "$(run "$(pay "$SHA_F")")")" = YES ] || fail "without AGENT_TIERS_OFF the lint must flag again"

# --- 6. Never blocks (a real assertion, not just a pattern that cannot appear): exit status is 0 even
#         on a findings fixture, and no output can carry a deny/block decision field.
[ "$(run_rc "$(pay "$SHA_F")")" = 0 ] || fail "the lint must exit 0 on a findings fixture, never non-zero"
out="$(run "$(pay "$SHA_F")")"
printf '%s' "$out" | grep -Eq '"(permissionDecision|decision)"[[:space:]]*:[[:space:]]*"(deny|block)"' \
  && fail "the lint must never block - it is advisory only"

# --- 7. Unreadable memory file leaves a breadcrumb instead of a silent pass with no evidence.
UNREADABLE_F="$MEMDIR/unreadable.md"
printf 'kit shipped at 205731d after review\n' > "$UNREADABLE_F"
chmod 000 "$UNREADABLE_F" 2>/dev/null
if [ ! -r "$UNREADABLE_F" ]; then
  out="$(run "$(pay "$UNREADABLE_F")")"
  [ "$(flagged "$out")" = NO ] || fail "an unreadable file cannot be linted, so it must not be flagged"
  grep -q "unreadable: $UNREADABLE_F" "$AGENT_TIERS_GUARDS_LOG" 2>/dev/null \
    || fail "an unreadable memory file should leave a breadcrumb in guards.log"
else
  echo "  (7 skipped: chmod 000 did not remove read access in this environment, e.g. running as root)"
fi
chmod 644 "$UNREADABLE_F" 2>/dev/null || true

# --- 8. A MultiEdit-shaped payload (Lead decision, not a review finding: MultiEdit is legacy per
#         permissions.md but still a live tool) is linted the same as Write/Edit - the script itself never
#         filters by tool_name, so this proves that stays true rather than asserting the matcher string.
out="$(run "$(pay "$SHA_F" MultiEdit)")"
[ "$(flagged "$out")" = YES ] || fail "a MultiEdit-shaped payload to a memory file must be linted the same as Write/Edit"

# --- 9. Repo-state rule: a non-memory .md gets the repo-state rule ONLY (generic "agent-tiers:" context,
#         no MEMORY-2), node_modules/plain-text paths stay silent, and a memory-dir file gets repo-state
#         PLUS the old memory rules under the "agent-tiers cards/MEMORY.md:" context.
REPOSTATE_F="$T/proj/RESUME_SESSION.md"
printf '3 commits unpushed, tree clean\n' > "$REPOSTATE_F"
out="$(run "$(pay "$REPOSTATE_F")")"
[ "$(flagged "$out")" = YES ] || fail "a non-memory .md with a live repo-state claim must be flagged"
printf '%s' "$out" | grep -q 'repo state a git command answers' || fail "repo-state finding text must be present, got: $out"
printf '%s' "$out" | grep -q 'MEMORY-2' && fail "a non-memory .md must not cite MEMORY-2 (that rule set is memory-dir only), got: $out"

REPOSTATE_NM_F="$T/proj/node_modules/x/README.md"
mkdir -p "$(dirname "$REPOSTATE_NM_F")"
printf '3 commits unpushed, tree clean\n' > "$REPOSTATE_NM_F"
out="$(run "$(pay "$REPOSTATE_NM_F")")"
[ "$(flagged "$out")" = NO ] || fail "a node_modules path must stay silent even with a live repo-state claim, got: $out"

REPOSTATE_TXT_F="$T/proj/notes.txt"
printf '3 commits unpushed, tree clean\n' > "$REPOSTATE_TXT_F"
out="$(run "$(pay "$REPOSTATE_TXT_F")")"
[ "$(flagged "$out")" = NO ] || fail "a non-.md path must stay silent even with a live repo-state claim, got: $out"

REPOSTATE_CLEAN_F="$T/proj/clean.md"
printf 'the plan was approved and work starts tomorrow\n' > "$REPOSTATE_CLEAN_F"
out="$(run "$(pay "$REPOSTATE_CLEAN_F")")"
[ "$(flagged "$out")" = NO ] || fail "a clean non-memory .md must stay silent, got: $out"

REPOSTATE_MEM_F="$MEMDIR/repostate.md"
printf 'kit shipped at 205731d after review\n3 commits unpushed\n' > "$REPOSTATE_MEM_F"
out="$(run "$(pay "$REPOSTATE_MEM_F")")"
[ "$(flagged "$out")" = YES ] || fail "a memory-dir file with both an old-rule hit and a repo-state claim must be flagged"
printf '%s' "$out" | grep -q 'cards/MEMORY.md' || fail "a memory-dir finding's context must start with the cards/MEMORY.md marker, got: $out"
printf '%s' "$out" | grep -q 'commit sha' || fail "a memory-dir finding must still carry the old MEMORY-2 sha rule, got: $out"
printf '%s' "$out" | grep -q 'repo state' || fail "a memory-dir finding must also carry the repo-state rule, got: $out"

# --- 10. Repo-state rule guard (guard-mempath.sh absence): the repo-state-only path for a non-memory .md
#          does not depend on the mempath resolver, so moving it away must not disable case 9's first
#          fixture. Restored unconditionally afterward, even if an assertion below fails.
mv "$T/.claude/agent-tiers/scripts/lib/guard-mempath.sh" "$T/.claude/agent-tiers/scripts/lib/guard-mempath.sh.bak"
out="$(run "$(pay "$REPOSTATE_F")")"
rc9=0
printf '%s' "$(flagged "$out")" | grep -q '^YES$' || rc9=1
mv "$T/.claude/agent-tiers/scripts/lib/guard-mempath.sh.bak" "$T/.claude/agent-tiers/scripts/lib/guard-mempath.sh"
[ "$rc9" = 0 ] || fail "the repo-state-only path for a non-memory .md must not depend on guard-mempath.sh, got: $out"

# --- 11. run_rc on the repo-state fixture returns 0 (never blocks, same as the memory-rule path).
[ "$(run_rc "$(pay "$REPOSTATE_F")")" = 0 ] || fail "the lint must exit 0 on a repo-state-only finding, never non-zero"

# --- 12. No guards.log lines are written for an ordinary repo-state finding (advisory only, no breadcrumb).
GLOG_BEFORE=0
[ -f "$AGENT_TIERS_GUARDS_LOG" ] && GLOG_BEFORE="$(wc -l < "$AGENT_TIERS_GUARDS_LOG" | tr -d ' ')"
run "$(pay "$REPOSTATE_F")" >/dev/null
GLOG_AFTER=0
[ -f "$AGENT_TIERS_GUARDS_LOG" ] && GLOG_AFTER="$(wc -l < "$AGENT_TIERS_GUARDS_LOG" | tr -d ' ')"
[ "$GLOG_BEFORE" = "$GLOG_AFTER" ] || fail "an ordinary repo-state finding must not write to guards.log, before=$GLOG_BEFORE after=$GLOG_AFTER"

echo "OK memory-content-lint: frontmatter is exempt, real shas/PR-numbers/dates behave, path gate covers a relocated config dir and autoMemoryDirectory, name-parameterised attribution works only with a names file, kill switch and unreadable-file breadcrumb hold, MultiEdit lints, never blocks, repo-state rule covers any .md with the right scope and context marker"

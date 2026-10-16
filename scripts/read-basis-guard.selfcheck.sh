#!/usr/bin/env sh
# kit-scope: shared
# Self-check for read-basis-guard.sh. Standalone: builds its own repo + transcript fixtures.
# The fixture stages files but never records them - the guard reads `git ls-files`, which is
# the index, so staging alone is enough and keeps this file free of VCS-write verbs.
set -u
HERE="$(dirname "$0")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# Sandboxed kit copy: BASE inside the guard resolves to $T, so the kill-switch test writes
# $T/.state/off/... and can never disable the LIVE guard if this script is interrupted.
mkdir -p "$T/scripts"
cp "$HERE/read-basis-guard.sh" "$T/scripts/read-basis-guard.sh"
G="$T/scripts/read-basis-guard.sh"
# Sandbox kit-gate: its stand-down checks read <kit>/.state/off, options.tsv and settings files, so give
# it the same sandbox root, an empty managed dir, and every input cleared.
mkdir -p "$T/install" "$T/managed"
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$HERE/kit-gate.sh" > "$T/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$T/scripts/kit-gate.sh" || { echo "SELF-CHECK FAILED: _kg_managed not rewritten"; exit 1; }
cp "$HERE/../install/options.tsv" "$T/install/"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export AGENT_TIERS_GUARDS_LOG="$T/guards.log"
# Sandbox config dir so no case can read the real ~/.claude/plans.
export CLAUDE_CONFIG_DIR="$T/cfg"; mkdir -p "$T/cfg/plans"
fails=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }

# Host probe: the guard anchors on \b (GNU ERE). A grep without it would make the guard
# silently never fire, which is worse than failing - so fail here, loudly.
printf 'alpha.ts\n' | grep -aoE '[A-Za-z0-9_.-]+\.(ts)\b' >/dev/null 2>&1 \
  || { printf 'FAIL host grep does not support \\b in ERE - guard would never match\n'; exit 1; }

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q . >/dev/null 2>&1
printf 'x\n' > "$REPO/alpha.ts"; printf 'y\n' > "$REPO/beta.ts"
mkdir -p "$REPO/sub"; printf 'z\n' > "$REPO/sub/delta.ts"
git -C "$REPO" add alpha.ts beta.ts sub/delta.ts >/dev/null 2>&1

mk() { : > "$1"; for p in $2; do
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"%s"}}]}}\n' "$p" >> "$1"
done; }
run() {
  jq -n --arg p "$1" --arg t "$2" --arg c "$REPO" \
    '{hook_event_name:"PreToolUse",tool_name:"ExitPlanMode",cwd:$c,transcript_path:$t,tool_input:{plan:$p}}' \
    | sh "$G" 2>"$T/stderr"; printf '%s' "$?"
}
mk "$T/none.jsonl" ""
mk "$T/both.jsonl" "$REPO/alpha.ts $REPO/beta.ts"

# Bash is the dominant read path in real sessions (Grep/Glob measured at 0 calls across 280
# transcripts), so it gets its own fixture - a break here would over-fire on nearly every plan.
: > "$T/bash.jsonl"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"sed -n 1,40p alpha.ts; rg pattern beta.ts"}}]}}\n' >> "$T/bash.jsonl"

[ "$(run 'Plan: change alpha.ts and beta.ts' "$T/none.jsonl")" = 2 ] \
  && ok "denies when tracked files are named but unread" || bad "should deny on unread named files"
grep -q 'alpha.ts' "$T/stderr" && ok "deny message lists the offending file" || bad "deny must list the files"
grep -q 'read-basis:' "$T/stderr" && ok "deny message offers the declaration" || bad "deny must offer the remedy"
# The old text offered "via subagent" and called subagent reads invisible; both are false.
{ ! grep -q 'via subagent' "$T/stderr" && ! grep -q 'invisible' "$T/stderr"; } \
  && ok "deny message has no stale subagent claims" || bad "deny text must not mention via subagent / invisible"

[ "$(run 'Plan: change alpha.ts and beta.ts' "$T/both.jsonl")" = 0 ] \
  && ok "allows when every named tracked file was read" || bad "should allow when all read"

[ "$(run 'Plan: change alpha.ts
read-basis: not read, because it is unchanged' "$T/none.jsonl")" = 0 ] \
  && ok "a read-basis declaration satisfies the gate" || bad "declaration must allow"

[ "$(run 'Plan: think about the architecture' "$T/none.jsonl")" = 0 ] \
  && ok "allows a plan that names no source files" || bad "should allow when nothing named"

[ "$(run 'Plan: change alpha.ts and beta.ts' "$T/bash.jsonl")" = 0 ] \
  && ok "counts files read via a Bash command" || bad "Bash reads must count as reads"

[ "$(run 'Plan: create gamma.ts' "$T/none.jsonl")" = 0 ] \
  && ok "ignores files git does not track" || bad "untracked files must not fire"

# Write must NOT count as a read: the plan-file write echoes every path in the plan, so
# counting it would mark everything read and neuter the guard entirely.
: > "$T/write.jsonl"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s/plan.md","content":"alpha.ts beta.ts"}}]}}\n' "$REPO" >> "$T/write.jsonl"
# The real regression is CONTENT extraction: a plan-file Write echoes every path in the plan,
# so if .input.content were ever added to the jq filter the guard would mark everything read.
[ "$(run 'Plan: change alpha.ts and beta.ts' "$T/write.jsonl")" = 2 ] \
  && ok "a Write echoing both paths in its content does not satisfy the gate" \
  || bad "content of a Write must never count as a read"

# Subagent transcripts count as reads.
mkdir -p "$T/none/subagents"
cp "$T/none.jsonl" "$T/sub.jsonl"; mkdir -p "$T/sub/subagents"
mk "$T/sub/subagents/agent-deadbeef.jsonl" "$REPO/alpha.ts $REPO/beta.ts"
[ "$(run 'Plan: change alpha.ts and beta.ts' "$T/sub.jsonl")" = 0 ] \
  && ok "counts reads made by a subagent" || bad "subagent reads must count"

# A malformed line before a Read must not drop that Read (whole-file jq stops at the first bad
# line, which would turn a read file into a false deny). Main and subagent transcripts both.
mk "$T/badmain.jsonl" "$REPO/beta.ts"
printf '{"type":"assistant","message":{"content":[\n' >> "$T/badmain.jsonl"
mk "$T/badmain.tail" "$REPO/alpha.ts"; cat "$T/badmain.tail" >> "$T/badmain.jsonl"
[ "$(run 'Plan: change alpha.ts and beta.ts' "$T/badmain.jsonl")" = 0 ] \
  && ok "a malformed main-transcript line does not drop later reads" || bad "read after a malformed main line must count"
cp "$T/none.jsonl" "$T/badsub.jsonl"; mkdir -p "$T/badsub/subagents"
mk "$T/badsub/subagents/agent-cafe.jsonl" "$REPO/beta.ts"
printf 'not json\n' >> "$T/badsub/subagents/agent-cafe.jsonl"
cat "$T/badmain.tail" >> "$T/badsub/subagents/agent-cafe.jsonl"
[ "$(run 'Plan: change alpha.ts and beta.ts' "$T/badsub.jsonl")" = 0 ] \
  && ok "a malformed subagent-transcript line does not drop later reads" || bad "read after a malformed subagent line must count"

KS="$T/.state/off/read-basis-guard"
mkdir -p "$(dirname "$KS")"; : > "$KS"
rc="$(run 'Plan: change alpha.ts' "$T/none.jsonl")"; rm -f "$KS"
[ "$rc" = 0 ] && ok "kill switch disables the guard" || bad "kill switch must disable"

# kit-gate stand-down: exit 0, empty stdout and stderr (no deny text), and a logged stand-down line.
: > "$T/guards.log"; mkdir -p "$(dirname "$KS")"; : > "$KS"
rc="$(run 'Plan: change alpha.ts' "$T/none.jsonl")"; rm -f "$KS"
{ [ "$rc" = 0 ] && [ ! -s "$T/stderr" ] && grep -qF 'kit-gate standdown read-basis-guard:' "$T/guards.log"; } \
  && ok "kit-gate stands the guard down (silent, exit 0, logged)" || bad "kit-gate stand-down failed (rc=$rc)"
[ "$(run 'Plan: change alpha.ts' "$T/none.jsonl")" = 2 ] \
  && ok "guard denies again once the marker is removed" || bad "guard must deny again after marker removal"

rc="$(jq -n --arg p 'Plan: change alpha.ts' --arg c "$REPO" \
  '{cwd:$c,transcript_path:"/nonexistent/x.jsonl",tool_input:{plan:$p}}' | sh "$G" 2>/dev/null; echo $?)"
[ "$rc" = 0 ] && ok "fails open on an unreadable transcript" || bad "must fail open, got rc=$rc"
grep -q 'fail-open' "$AGENT_TIERS_GUARDS_LOG" && ok "fail-open leaves a breadcrumb" || bad "no breadcrumb logged"

# The deny line must carry [sid=...] or guard-summary.sh cannot attribute it to a session,
# which is what the experiment's per-session fire-rate falsifier is computed from.
: > "$AGENT_TIERS_GUARDS_LOG"
jq -n --arg p 'Plan: change alpha.ts' --arg t "$T/none.jsonl" --arg c "$REPO" \
  '{cwd:$c,transcript_path:$t,session_id:"sess-xyz",tool_input:{plan:$p}}' | sh "$G" 2>/dev/null
grep -q 'deny:.*\[sid=sess-xyz\]' "$AGENT_TIERS_GUARDS_LOG" \
  && ok "deny line carries the session id" || bad "deny line must carry [sid=<session_id>]"

# Plan-file fallback: empty tool_input, plan recovered from <config>/plans/<slug>.md.
: > "$T/slug.jsonl"
printf '{"type":"assistant","slug":"test-slug","message":{"content":[]}}\n' >> "$T/slug.jsonl"
printf 'Plan: change alpha.ts\n' > "$T/cfg/plans/test-slug.md"
rb() { jq -n --arg t "$1" --arg c "$REPO" --argjson x "$2" \
  '{cwd:$c,transcript_path:$t,session_id:"sess-xyz",tool_input:{}} + $x' | sh "$G" 2>"$T/stderr"; printf '%s' "$?"; }
: > "$AGENT_TIERS_GUARDS_LOG"
[ "$(rb "$T/slug.jsonl" '{}')" = 2 ] \
  && ok "plan file via transcript slug is used" || bad "transcript slug plan file should deny"
grep -q 'deny:.*\[src=plan-file\] \[sid=sess-xyz\]$' "$AGENT_TIERS_GUARDS_LOG" \
  && ok "plan-file deny row carries src then sid" || bad "deny row must carry [src=plan-file] before [sid=]"
[ "$(rb "$T/none.jsonl" '{"slug":"test-slug"}')" = 2 ] \
  && ok "plan file via payload slug is used" || bad "payload slug plan file should deny"
printf '{"slug":"nope-slug"}\n' > "$T/missing.jsonl"
: > "$AGENT_TIERS_GUARDS_LOG"
[ "$(rb "$T/missing.jsonl" '{}')" = 0 ] && grep -q 'fail-open: no tool_input.plan and no plan file' "$AGENT_TIERS_GUARDS_LOG" \
  && ok "missing plan file fails open with a breadcrumb" || bad "missing plan file must fail open"
# Plant the file where "plans/../x.md" resolves, so only the slug filter keeps this at exit 0.
printf 'Plan: change alpha.ts\n' > "$T/cfg/x.md"
: > "$AGENT_TIERS_GUARDS_LOG"
[ "$(rb "$T/none.jsonl" '{"slug":"../x"}')" = 0 ] \
  && ok "a traversal slug is rejected" || bad "slug with / or .. must be rejected"
{ grep -q 'fail-open:.*(rejected slug)' "$AGENT_TIERS_GUARDS_LOG" && ! grep -q '\.\./x' "$AGENT_TIERS_GUARDS_LOG"; } \
  && ok "rejected slug is named in the breadcrumb, value not echoed" || bad "fail-open row must say rejected slug and never echo it"
: > "$AGENT_TIERS_GUARDS_LOG"
[ "$(rb "$T/none.jsonl" '{}')" = 0 ] && grep -q 'fail-open:.*(no slug)' "$AGENT_TIERS_GUARDS_LOG" \
  && ok "a missing slug is logged as no slug" || bad "no-slug fail-open row must say no slug"

# Last non-empty slug wins: guards a head/tail swap and an empty trailing slug hiding a valid one.
printf '{"slug":"old-slug"}\n{"slug":"test-slug"}\n' > "$T/two.jsonl"
[ "$(rb "$T/two.jsonl" '{}')" = 2 ] \
  && ok "the last slug in the transcript is used" || bad "last slug must win"
printf '{"slug":"test-slug"}\n{"slug":""}\n' > "$T/emptyslug.jsonl"
[ "$(rb "$T/emptyslug.jsonl" '{}')" = 2 ] \
  && ok "an empty trailing slug does not hide a valid one" || bad "empty slug must be skipped"

# Empty CLAUDE_CONFIG_DIR falls back to $HOME/.claude (env set for this one call only). The slug
# exists only under $T/home, so the case cannot pass by reading $T/cfg.
mkdir -p "$T/home/.claude/plans"; printf 'Plan: change alpha.ts\n' > "$T/home/.claude/plans/home-slug.md"
[ "$(CLAUDE_CONFIG_DIR= HOME="$T/home" rb "$T/none.jsonl" '{"slug":"home-slug"}')" = 2 ] \
  && ok "empty CLAUDE_CONFIG_DIR falls back to HOME/.claude" || bad "HOME fallback must find the plan file"

# cwd in a subdirectory must still see tracked files elsewhere in the repo (ls-files from top).
[ "$(jq -n --arg t "$T/none.jsonl" --arg c "$REPO/sub" '{cwd:$c,transcript_path:$t,tool_input:{plan:"Plan: change alpha.ts"}}' | sh "$G" 2>/dev/null; echo $?)" = 2 ] \
  && ok "tracked set is taken from the repo top" || bad "subdir cwd must still see alpha.ts"

# Every row (not only deny) must end with [sid=...] for guard-summary.sh.
: > "$AGENT_TIERS_GUARDS_LOG"
rs() { jq -n --arg p "$1" --arg t "$2" --arg c "$REPO" \
  '{cwd:$c,transcript_path:$t,session_id:"sess-xyz",tool_input:{plan:$p}}' | sh "$G" >/dev/null 2>&1; }
rs 'Plan: change alpha.ts and beta.ts' "$T/both.jsonl"
rs 'Plan: change alpha.ts' /nonexistent/x.jsonl
grep -q 'allow:.*\[sid=sess-xyz\]$' "$AGENT_TIERS_GUARDS_LOG" && grep -q 'fail-open:.*\[sid=sess-xyz\]$' "$AGENT_TIERS_GUARDS_LOG" \
  && ok "allow and fail-open rows carry the session id" || bad "every row must end with [sid=<session_id>]"

[ "$fails" -eq 0 ] && { printf 'PASS read-basis-guard.sh\n'; exit 0; }
printf '%s check(s) failed\n' "$fails"; exit 1

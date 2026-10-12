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
export AGENT_TIERS_GUARDS_LOG="$T/guards.log"
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
git -C "$REPO" add alpha.ts beta.ts >/dev/null 2>&1

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

[ "$(run 'Plan: change alpha.ts and beta.ts' "$T/both.jsonl")" = 0 ] \
  && ok "allows when every named tracked file was read" || bad "should allow when all read"

[ "$(run 'Plan: change alpha.ts
read-basis: via subagent' "$T/none.jsonl")" = 0 ] \
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

KS="$T/.state/off/read-basis-guard"
mkdir -p "$(dirname "$KS")"; : > "$KS"
rc="$(run 'Plan: change alpha.ts' "$T/none.jsonl")"; rm -f "$KS"
[ "$rc" = 0 ] && ok "kill switch disables the guard" || bad "kill switch must disable"

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

[ "$fails" -eq 0 ] && { printf 'PASS read-basis-guard.sh\n'; exit 0; }
printf '%s check(s) failed\n' "$fails"; exit 1

#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(EnterPlanMode|AskUserQuestion) guard: the GATE-TOOL arm of unattended mode.
#
# Why it exists: an interactive plan-mode or question confirmation halts an unattended run exactly the
# way a hook `ask` does (HOST-4). A preplanned brief - the whole point of running unattended - already
# IS the plan, and a fork with nobody present to pick a branch just deadlocks. When this session
# carries the unattended flag (`.state/unattended.<session-id>`, written by /unattended, read by
# guard_unattended in guard-cmdpos.sh):
#   EnterPlanMode   -> DENY with "the brief is preplanned, proceed with it"
#   AskUserQuestion -> DENY with "take the smaller-diff reading, log the fork, continue" (matches the
#                      unattended-run-protocol memory: AskUserQuestion is explicitly banned there too)
# Attended sessions (no flag): silent. This guard has no opinion outside unattended mode.
#
# What it deliberately does NOT do: auto-allow `ExitPlanMode`. The first draft did, to stop a session
# that was already in plan mode from being stranded - opus reviewer 2026-08-23 (HIGH) killed it, and
# was right. A hook `allow` does not merely answer this guard's own question, it bypasses the
# permission system for that call, including other hooks' asks and the operator's own rules. Plan mode
# is enforced by that system (write tools are refused in it), so the confirmation on ExitPlanMode is
# the approval to LEAVE a read-only mode and start executing - a permission decision, not a workflow
# nicety. Auto-approving it would also be the one thing a model could gain by writing its own flag
# file. Without that arm this feature is MONOTONICALLY STRICTER under the flag: an `ask` may become a
# deny, nothing ever becomes allowed, and a hard deny is never converted. The strand it avoided is
# narrow - EnterPlanMode is denied under the flag, so the only way into plan mode is the operator
# putting the session there, and an operator typing /unattended on is present at that moment and can
# leave plan mode first (the command doc says so).
#
# Fail-open on any tooling gap (no jq, unreadable payload, missing library), breadcrumbed to
# .state/guards.log like every sibling. Self-check: unattended-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s unattended-guard fail-open: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}
logdec() { # $1 = "deny: ..." | "allow: ..."
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s unattended-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}

# readable-guarded BEFORE the `.` - a missing file ABORTS dash/busybox on the dot builtin, and that
# abort code is the PreToolUse BLOCKING code (the fail-closed inversion no guard may have).
LIB="$(dirname "$0")/guard-cmdpos.sh"
[ -r "$LIB" ] || { note "guard-cmdpos.sh missing/unreadable at $LIB"; exit 0; }
# shellcheck source=guard-cmdpos.sh
. "$LIB" 2>/dev/null || { note "guard-cmdpos.sh failed to source"; exit 0; }
command -v guard_unattended >/dev/null 2>&1 || { note "guard-cmdpos.sh sourced but guard_unattended undefined"; exit 0; }

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "jq missing - cannot parse payload"; exit 0; }
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ -n "$TOOL" ] || { note "no tool_name in payload"; exit 0; }
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"

guard_unattended "$SID" || exit 0   # attended session: this guard has nothing to say

case "$TOOL" in
  EnterPlanMode)
    logdec "deny: EnterPlanMode (unattended)"
    jq -n --arg r "UNATTENDED MODE: this session is flagged unattended, and plan mode ends in a confirmation no human is present to give - entering it would halt the run outright. Your brief is already the approved plan: proceed with it, and if it turns out to be wrong or ambiguous, stop and record what you would have asked rather than guessing. Clear the flag with /agent-tiers:unattended off if a human is back at the keyboard." \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    ;;
  AskUserQuestion)
    logdec "deny: AskUserQuestion (unattended)"
    jq -n --arg r "UNATTENDED MODE: this session is flagged unattended, and a question gate deadlocks with nobody present to answer it. Do not ask: take whichever reading preserves existing behaviour and is the smaller diff, note the fork and your choice in your final report, and continue. Clear the flag with /agent-tiers:unattended off if a human is back at the keyboard." \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    ;;
esac
exit 0

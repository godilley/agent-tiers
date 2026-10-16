#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers SubagentStop hook: block a sub-agent's return while a background shell task IT started is
# still running, so it cannot hand its caller a claim it never observed.
#
# Why this exists (incident, not opinion): a sub-agent runs an ordinary foreground command, the host
# auto-converts it at the 120s tool timeout and hands back a shell id instead of an exit status, and the
# agent then returns asserting an outcome it never saw. The return is the artifact its caller trusts, so
# an unverified claim made there propagates as fact.
#
# PAYLOAD, measured 2026-09-18 - relied on exactly, not widened: SubagentStop carries agent_id,
# agent_transcript_path, agent_type, background_tasks, cwd, hook_event_name, last_assistant_message,
# permission_mode, prompt_id, scratchpad_dir, session_crons, session_id, stop_hook_active,
# transcript_path. background_tasks is SESSION-WIDE and carries no owner field at all: a control agent
# that started nothing still saw another agent's shell row, and the agent's own row (type "subagent",
# same id as agent_id) is present on every stop - a bare "non-empty means block" test would deny every
# return ever, and a bare "any running shell" test would block innocent agents whenever anybody else in
# the session has something running.
#
# OWNERSHIP is therefore derived from the agent's OWN transcript (agent_transcript_path), not from the
# background_tasks row: take the running shell ids from background_tasks, then check which of those ids
# actually appears in this agent's transcript (the host writes "moved to the background (ID: <id>)" on
# the 120s auto-conversion, or "running in background with ID: <id>" on an explicit run_in_background
# call - matched here as a fixed-string grep on the id itself, prefiltered before any jq so the scan
# stays inside the hook budget). Block only ids that are BOTH still running AND owned this way.
#
# Known ceiling, disclosed rather than silently absorbed: an id that merely appears in the agent's
# PROMPT or in text it read (never actually started by it) would count as owned by this test - it has no
# way to distinguish "this agent started it" from "this agent's transcript mentions it". A shell started
# by a NESTED child of this agent is not distinguished either (its id would appear in the child's own
# transcript, not necessarily this one, so it may go uncaught rather than falsely blocked).
#
# BLOCKING mirrors advisory-ack-guard.sh's Stop-event shape (stderr + exit 2), and blocks AT MOST ONCE
# per agent_id via a marker under .state/ - a task that never finishes on its own (a dev server, a watch
# loop) must not trap an agent in an unbreakable loop. Deliberately NOT keyed off stop_hook_active: that
# flag is harness-global, not owned by this hook (same reasoning advisory-ack-guard.sh's header gives),
# so a second Stop/SubagentStop hook existing at all would break an assumption that this is the only
# thing re-invoking the agent.
#
# Fail-open on every tooling gap (no jq, no readable agent_transcript_path, unusable agent_id), each with
# a breadcrumb. Self-check: subagent-bg-return-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s subagent-bg-return-guard %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in *[!A-Za-z0-9._-]* | '.' | '..') SESSION_ID="" ;; esac

AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null || true)"
case "${AGENT_ID:-}" in ''|*[!A-Za-z0-9._-]* | '.' | '..')
  note "fail-open: unusable agent_id [sid=$SESSION_ID]"; exit 0 ;;
esac

# Running shell ids from background_tasks - session-wide, ownership not yet decided.
RUNNING_SHELL_IDS="$(printf '%s' "$INPUT" | jq -r '
    (.background_tasks // []) | map(select(.type == "shell" and .status == "running") | .id) | .[]
  ' 2>/dev/null || true)"
[ -n "$RUNNING_SHELL_IDS" ] || exit 0   # nothing running session-wide, cheapest path, no state touched

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // empty' 2>/dev/null || true)"
if [ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ]; then
  note "fail-open: no readable agent_transcript_path [sid=$SESSION_ID agent=$AGENT_ID]"
  exit 0
fi

# Ownership: an id counts only if it is a fixed-string match somewhere in THIS agent's own transcript.
OWNED_IDS=""
NL='
'
for id in $RUNNING_SHELL_IDS; do
  [ -n "$id" ] || continue
  grep -qF -- "$id" "$TRANSCRIPT" 2>/dev/null && OWNED_IDS="${OWNED_IDS:+$OWNED_IDS$NL}$id"
done
[ -n "$OWNED_IDS" ] || exit 0   # running shells exist, but none are this agent's own - the session-wide case

MARKER_DIR="${BASE:-${TMPDIR:-/tmp}}/.state/subagent-bg-return-seen"
# default 7 (AGENT_TIERS_STATE_DAYS), validated: non-digit, 0, or over 3650 silently falls back to 7.
days="${AGENT_TIERS_STATE_DAYS:-7}"; case "$days" in ''|*[!0-9]*) days=7 ;; esac
[ "$days" -gt 0 ] 2>/dev/null && [ "$days" -le 3650 ] 2>/dev/null || days=7
{ [ -d "$MARKER_DIR" ] && find "$MARKER_DIR" -type f -mtime "+$days" -delete; } 2>/dev/null || true
if [ -f "$MARKER_DIR/$AGENT_ID" ]; then
  note "allow: already blocked once for agent $AGENT_ID, letting it through to avoid an unbreakable loop [sid=$SESSION_ID]"
  exit 0
fi

IDLIST="$(printf '%s' "$OWNED_IDS" | tr '\n' ',' | sed 's/,$//')"
note "blocked: agent $AGENT_ID returning with still-running owned background task(s) $IDLIST [sid=$SESSION_ID]"
{ mkdir -p "$MARKER_DIR" 2>/dev/null && : > "$MARKER_DIR/$AGENT_ID"; } 2>/dev/null || true

{
  printf 'agent-tiers: this return is about to end while background task(s) %s that you started are still running. ' "$IDLIST"
  printf 'You have not observed their outcome, and a claim about a result you did not see is not verified. '
  printf 'Either wait for the task(s) to finish and report what they actually returned, or state plainly in your return that the outcome was NOT observed - never assert a result you did not see.'
} >&2
exit 2

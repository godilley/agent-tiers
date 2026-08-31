#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers SessionEnd hook: one stderr line summarising this session's guard blocks from
# .state/guards.log - "agent-tiers: N guard block(s) this session (deny D, ask A); last: <ts> <guard> ...".
#
# Why (Wave D, 2026-08-16): guards.log is THE durable human record of blocks - under cc-gui a denied Bash
# row is hidden and a denied Write shows `+N` with the reason dropped (HOST-4), so the log is the only
# place a human can count what the guards did. This line is the cheapest honest effectiveness signal.
# CHANNEL STATUS: `[unverified]` as a HUMAN channel. It costs nothing where the host does not render hook
# stderr (cc-gui pipes CLI stderr into a bounded diagnostic sample with no live render path; `-p` prints
# nothing at session end) and is a real channel where a host does - a native CLI in an interactive
# terminal is the candidate, and until the native-terminal probe (MASTER A5) says so, this is NOT to be
# written up as working. `doctor` reads the same log and needs no channel at all.
#
# Counts only lines carrying THIS session's id (`[sid=<id>]`, appended by every guard's decision line
# since Wave D); a selfcheck run writes `[sid=]` lines, which never match a real session. A payload with
# no session_id gets the all-time count with that said. Fail-open on any tooling gap (no jq, no log):
# silent exit 0 - a summary line must never break a session end.
# Probed live 2026-08-23: a sub-agent's PreToolUse payload carries the SAME session_id the SessionEnd
# payload does (a Worker's blocked grep logged the parent sid), so blocks inside sub-agents count toward
# "this session" here too.
set -u
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
[ -f "$LOG" ] || exit 0
INPUT="$(cat 2>/dev/null || true)"
SID=""
command -v jq >/dev/null 2>&1 && SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
BADSID=0
case "$SID" in *[!A-Za-z0-9._-]*) SID=""; BADSID=1 ;; esac
# decision token is the THIRD field (`<ts> <guard> deny|ask:`), so a reason that merely contains
# " ask: " later cannot double-count, and `declined:` never matches.
DEC='^[^ ]+ [^ ]+ (deny|ask): '
if [ -n "$SID" ]; then
  # `.` is the only regex metachar the charset lets through - escape it (a real id is uuid-shaped).
  SIDRE="$(printf '%s' "$SID" | sed 's/\./\\./g')"
  HITS="$(grep -aE "$DEC"'.*\[sid='"$SIDRE"'\]$' "$LOG" 2>/dev/null || true)"
  SCOPE="this session"
else
  # all-time: real sessions only - `[sid=]` lines are selfcheck runs, never a session
  HITS="$(grep -aE "$DEC" "$LOG" 2>/dev/null | grep -avE '\[sid=\]$' || true)"
  if [ "$BADSID" = 1 ]; then SCOPE="all sessions (session_id in payload was not id-shaped)"; else SCOPE="all sessions (no session_id in payload)"; fi
fi
N=0; D=0; A=0
if [ -n "$HITS" ]; then
  N="$(printf '%s\n' "$HITS" | grep -ac .)"
  D="$(printf '%s\n' "$HITS" | grep -acE '^[^ ]+ [^ ]+ deny: ' || true)"
  A="$(printf '%s\n' "$HITS" | grep -acE '^[^ ]+ [^ ]+ ask: ' || true)"
fi
# Unattended mode is a property of a RUN, not of a session id: `--resume` reuses the id, so a flag left
# over from last night would silently convert this morning's asks with the operator sitting right there
# (opus reviewer 2026-08-23). Cleared here, at the end of the run that set it. Best-effort: a session
# killed hard never fires SessionEnd, which is why /unattended status exists.
if [ -n "$SID" ]; then
  STATE_DIR="${AGENT_TIERS_STATE_DIR:-$(dirname "$LOG")}"
  [ -f "$STATE_DIR/unattended.$SID" ] && {
    rm -f "$STATE_DIR/unattended.$SID" 2>/dev/null \
      && printf 'agent-tiers: unattended flag cleared for this session (set it again with /agent-tiers:unattended on)\n' >&2
  }
fi

if [ "$N" = 0 ]; then
  printf 'agent-tiers: 0 guard blocks %s (record: %s)\n' "$SCOPE" "$LOG" >&2
else
  LAST="$(printf '%s\n' "$HITS" | tail -1 | sed -E 's/ \[sid=[^]]*\]$//' | cut -c1-160)"
  printf 'agent-tiers: %s guard block(s) %s (deny %s, ask %s); last: %s (record: %s)\n' "$N" "$SCOPE" "$D" "$A" "$LAST" "$LOG" >&2
fi
exit 0

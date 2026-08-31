#!/usr/bin/env sh
# kit-scope: shared
# Self-check for unattended-guard.sh. Runnable: `sh unattended-guard.selfcheck.sh`.
# Sandboxed kit copy (guard + guard-cmdpos.sh, so BASE and .state resolve inside the sandbox), so the
# real kit's flag dir and guards.log are never touched.
set -u
SRC_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"
T="${TMPBASE}/at-unattended-selfcheck.$$"
rm -rf "$T"; mkdir -p "$T/kit/scripts" "$T/kit/.state" || { echo "FAIL cannot build sandbox"; exit 1; }
cp "$SRC_DIR/unattended-guard.sh" "$SRC_DIR/guard-cmdpos.sh" "$T/kit/scripts/" || { echo "FAIL cannot copy"; exit 1; }
GUARD="$T/kit/scripts/unattended-guard.sh"
LOG="$T/kit/.state/guards.log"; export AGENT_TIERS_GUARDS_LOG="$LOG"
# exercise the env seam itself (its only consumer): the flag dir is resolved from it, not from $0
export AGENT_TIERS_STATE_DIR="$T/kit/.state"
trap 'rm -rf "$T"' EXIT

run() { # $1=tool $2=session_id -> deny|allow|silent
  out="$(jq -n --arg t "$1" --arg s "$2" '{tool_name: $t, session_id: $s, tool_input: {}}' | sh "$GUARD" 2>/dev/null || true)"
  if   printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"';  then echo deny
  elif printf '%s' "$out" | grep -aq '"permissionDecision": *"allow"'; then echo allow
  else echo silent; fi
}

# 1. Attended session (no flag file): the guard says nothing about either tool.
[ "$(run EnterPlanMode sess-a)" = silent ] && ok "attended: EnterPlanMode untouched" || bad "attended EnterPlanMode not silent"
[ "$(run ExitPlanMode  sess-a)" = silent ] && ok "attended: ExitPlanMode untouched"  || bad "attended ExitPlanMode not silent"
[ "$(run AskUserQuestion sess-a)" = silent ] && ok "attended: AskUserQuestion untouched" || bad "attended AskUserQuestion not silent"

# 2. Flagged session: entering plan mode is denied. Exiting is NOT auto-allowed - a hook `allow`
#    bypasses the whole permission chain for that call, and this feature never makes anything more
#    permissive than it was (opus reviewer 2026-08-23, HIGH).
: > "$T/kit/.state/unattended.sess-u"
[ "$(run EnterPlanMode sess-u)" = deny ]   && ok "unattended: EnterPlanMode denied" || bad "unattended EnterPlanMode not denied"
[ "$(run ExitPlanMode  sess-u)" = silent ] && ok "unattended: ExitPlanMode is left to the host, never auto-allowed" \
  || bad "unattended ExitPlanMode was decided by the guard"
[ "$(run AskUserQuestion sess-u)" = deny ] && ok "unattended: AskUserQuestion denied" || bad "unattended AskUserQuestion not denied"

# 3. The flag is PER SESSION: another session's flag must not leak into this one.
[ "$(run EnterPlanMode sess-a)" = silent ] && ok "a foreign session's flag does not apply" || bad "foreign flag leaked"

# 4. A session id that could traverse is treated as absent, never as a path component.
: > "$T/kit/.state/unattended...."
[ "$(run EnterPlanMode '../../etc')" = silent ] && ok "traversal-shaped session id is treated as absent" || bad "traversal-shaped id was honoured"
[ "$(run EnterPlanMode '..')" = silent ] && ok "dot-dot session id is treated as absent" || bad "dot-dot id was honoured"
[ "$(run EnterPlanMode '')" = silent ] && ok "empty session id is treated as absent" || bad "empty id was honoured"

# 5. Decisions reach guards.log (HOST-4: the log is the durable record of what a guard did).
grep -aqE '^[^ ]+ unattended-guard deny: EnterPlanMode \(unattended\) \[sid=sess-u\]$' "$LOG" \
  && ok "deny is recorded in guards.log with the sid" || bad "no deny line in guards.log"
grep -aqE '^[^ ]+ unattended-guard deny: AskUserQuestion \(unattended\) \[sid=sess-u\]$' "$LOG" \
  && ok "AskUserQuestion deny is recorded in guards.log with the sid" || bad "no AskUserQuestion deny line in guards.log"
grep -aq 'unattended-guard allow' "$LOG" \
  && bad "the guard emitted an allow decision - it must never make anything more permissive" \
  || ok "no allow decision is ever emitted"

# 6. Fail-open, never fail-closed: an unparsable payload exits 0 and emits no decision.
printf 'not json' | sh "$GUARD" >/dev/null 2>&1 && ok "unparsable payload exits 0" || bad "unparsable payload exited non-zero"

# 7. Any other tool is untouched even when flagged (this guard owns plan mode only).
[ "$(run Bash sess-u)" = silent ] && ok "an unrelated tool is untouched under the flag" || bad "guard fired on an unrelated tool"

[ "$fail" = 0 ] && echo "OK unattended-guard: the plan-mode and question arms fire only for a flagged session, only ever DENY (never allow), session ids are path-safe, decisions are logged, fail-open holds" \
  || { echo "SELF-CHECK FAILED"; exit 1; }

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for ask-gate.sh: allow right after a Stop-hook send-back (also with metadata or isMeta
# entries after it), deny after a tool result, a typed prompt or an assistant entry, self-heal on a
# second question with no send-back in between, stand down for an unattended session, ignore other
# tools, fail open on a missing transcript, a non-cli entrypoint, the gate's own kill switch and
# the notify kill switch, and the install-time --probe requiring notify-tag-guard.
set -u
H="$(cd "$(dirname "$0")" && pwd)/ask-gate.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP ask-gate: jq absent (gate fails open by design)"; exit 0; }

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
fail() { printf 'FAIL: %s\n' "$1"; rm -rf "$T"; exit 1; }
trap 'rm -rf "$T"' EXIT
export AGENT_TIERS_GUARDS_LOG="$T/guards.log"
export CLAUDE_CONFIG_DIR="$T/cfg"
export AGENT_TIERS_STATE_DIR="$T/.state"   # guard_state_dir appends /.state otherwise
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state" "$AGENT_TIERS_STATE_DIR"

# The real send-back shape (observed live, CLI 2.1.280) carries isMeta:true; STOP_PLAIN is the
# same entry without it, kept so a format variant is covered both ways.
STOP='{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\n[sh notify-tag-guard.sh]: agent-tiers: ask_next"}}'
STOP_PLAIN='{"type":"user","message":{"role":"user","content":"Stop hook feedback:\n[sh notify-tag-guard.sh]: agent-tiers: ask_next"}}'
RESULT='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}'
PROMPT='{"type":"user","message":{"role":"user","content":"which option do you think?"}}'
ASSIST='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hello"}]}}'
METAUSER='{"type":"user","isMeta":true,"message":{"role":"user","content":"<task-notification>done</task-notification>"}}'
META='{"type":"attachment"}'

# $1 = transcript lines, $2 = tool name, $3 = entrypoint, $4 = session id (default: a fresh one,
# so no deny-streak token carries over). Prints "allow" or "deny"; a nonzero exit or any stderr
# output prints "error" instead, so a crash can never pass as an allow.
run() {
  N=$(( $(cat "$T/n" 2>/dev/null || echo 0) + 1 )); echo "$N" > "$T/n"   # file: run() is called in $(...)
  printf '%s\n' "$1" > "$T/t.jsonl"
  out="$(jq -cn --arg tp "$T/t.jsonl" --arg tn "${2:-AskUserQuestion}" --arg sid "${4:-s$N}" \
    '{hook_event_name:"PreToolUse", tool_name:$tn, transcript_path:$tp, session_id:$sid}' \
    | CLAUDE_CODE_ENTRYPOINT="${3:-cli}" sh "$H" 2>"$T/err")"
  rc=$?
  if [ "$rc" != 0 ] || [ -s "$T/err" ]; then echo error
  elif printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then echo deny
  else echo allow; fi
}
logged() { grep -c "ask-gate $1" "$AGENT_TIERS_GUARDS_LOG" 2>/dev/null || echo 0; }

a0="$(logged 'allow: follows')"
[ "$(run "$PROMPT
$ASSIST
$STOP")" = allow ] || fail "a question right after a Stop-hook send-back must be allowed"
[ "$(logged 'allow: follows')" -gt "$a0" ] || fail "an allow must come from the send-back branch (logged), not a fail-open"
a1="$(logged 'allow: follows')"
[ "$(run "$ASSIST
$STOP_PLAIN")" = allow ] || fail "a send-back entry without isMeta must also be allowed"
[ "$(logged 'allow: follows')" -gt "$a1" ] || fail "the plain send-back allow must come from the send-back branch"
[ "$(run "$ASSIST
$STOP
$META
$META")" = allow ] || fail "metadata entries after the send-back must not hide it"
[ "$(run "$ASSIST
$STOP
$METAUSER")" = allow ] || fail "an isMeta user entry after the send-back must not hide it"
[ "$(run "$STOP
$RESULT
$META
$META")" = deny ] || fail "metadata after a tool result must not turn a deny into an allow"
[ "$(run "$STOP
$ASSIST
$RESULT")" = deny ] || fail "a question after a tool result must be denied"
[ "$(run "$PROMPT")" = deny ] || fail "a question straight after a typed prompt must be denied"
[ "$(run "$STOP
$ASSIST")" = deny ] || fail "a question after an assistant entry must be denied"

out="$(printf '%s\n' "$RESULT" > "$T/t.jsonl"; jq -cn --arg tp "$T/t.jsonl" '{tool_name:"AskUserQuestion", transcript_path:$tp, session_id:"msg"}' | CLAUDE_CODE_ENTRYPOINT=cli sh "$H")"
printf '%s' "$out" | grep -q 'operator:ask_next' || fail "the deny reason must name the operator:ask_next tag"
[ "$(logged 'deny:')" -gt 0 ] || fail "a deny should be logged to guards.log"

# Self-heal: deny, then a second question in the same session with no send-back is admitted and
# logged; the token is consumed, so a third one is denied again.
[ "$(run "$RESULT" AskUserQuestion cli heal)" = deny ] || fail "self-heal setup: first question must be denied"
[ "$(run "$RESULT" AskUserQuestion cli heal)" = allow ] || fail "a second question with no send-back since the deny must fail open"
[ "$(logged 'fail-open: second question')" -gt 0 ] || fail "the self-heal fail-open must be logged"
[ "$(run "$RESULT" AskUserQuestion cli heal)" = deny ] || fail "after a self-heal the streak resets, so the next one is denied again"
# A stale token does not self-heal: deny, then the conversation moves on (a typed prompt is written
# after the deny), then a bare question is denied again rather than admitted by the old token.
[ "$(run "$RESULT" AskUserQuestion cli stale)" = deny ] || fail "stale-token setup: first question must be denied"
[ "$(run "$RESULT
$PROMPT
$RESULT" AskUserQuestion cli stale)" = deny ] || fail "a deny token from before a later typed prompt must not self-heal a new question"
# A send-back clears a pending token: deny, then send-back allow, then a bare question is denied
# (not self-healed by a token left over from before the send-back).
[ "$(run "$RESULT" AskUserQuestion cli clear)" = deny ] || fail "token-clear setup: first question must be denied"
[ "$(run "$STOP" AskUserQuestion cli clear)" = allow ] || fail "token-clear setup: send-back must allow"
[ "$(run "$RESULT" AskUserQuestion cli clear)" = deny ] || fail "an allow after a send-back must clear the deny token"

: > "$AGENT_TIERS_STATE_DIR/unattended.sess-u"
[ "$(run "$RESULT" AskUserQuestion cli sess-u)" = allow ] || fail "an unattended session must be left to unattended-guard (no second, contradictory deny)"

[ "$(run "$RESULT" Bash)" = allow ] || fail "other tools must pass untouched"
[ "$(run "$RESULT" AskUserQuestion sdk-cli)" = allow ] || fail "a non-cli entrypoint must never deny"

rc="$(jq -cn '{tool_name:"AskUserQuestion", transcript_path:"/nonexistent/t.jsonl", session_id:"x"}' | CLAUDE_CODE_ENTRYPOINT=cli sh "$H" >"$T/o" 2>&1; echo "$?")"
[ "$rc" = 0 ] && ! grep -q deny "$T/o" || fail "a missing transcript must fail open"

mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off"
touch "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/ask-gate"
[ "$(run "$RESULT")" = allow ] || fail "the ask-gate kill switch must stand the gate down"
rm -f "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/ask-gate"
touch "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/notify"
[ "$(run "$RESULT")" = allow ] || fail "with notify-tag-guard off nothing sends the turn back, so the gate must stand down"
rm -f "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/notify"

# Install-time probe: notify-tag-guard must be wired already, or requested in the same install,
# and not removed in it.
printf '{"hooks":{}}' > "$T/settings.json"
KIT_PROBE_SETTINGS="$T/settings.json" sh "$H" --probe >/dev/null 2>&1 && fail "probe must refuse when notify-tag-guard is not wired"
KIT_PROBE_WITH="notify-tag-guard" KIT_PROBE_SETTINGS="$T/settings.json" sh "$H" --probe >/dev/null 2>&1 || fail "probe must pass when notify-tag-guard is requested in the same install"
printf '{"hooks":{"Stop":[{"hooks":[{"command":"sh notify-tag-guard.sh"}]}]}}' > "$T/settings.json"
KIT_PROBE_SETTINGS="$T/settings.json" sh "$H" --probe >/dev/null 2>&1 || fail "probe must pass when notify-tag-guard is already wired"
KIT_PROBE_WITHOUT="notify-tag-guard" KIT_PROBE_SETTINGS="$T/settings.json" sh "$H" --probe >/dev/null 2>&1 && fail "probe must refuse when notify-tag-guard is removed in the same install"

echo "PASS ask-gate.sh"

#!/usr/bin/env sh
# kit-scope: shared
# kit-probe: yes
# agent-tiers PreToolUse(AskUserQuestion) gate: admit a question only right after the Stop hook
# has sent a turn back (notify-tag-guard.sh's operator:ask_next block, or any other Stop-hook
# block), so the context for the decision has already ENDED a reply and reached the operator in
# full. Native CLI only (see the entrypoint gate below).
#
# Why: on some models, prose written between tool calls comes back as a "narration" thinking
# block that the operator sees only as a one-line summary (or not at all). A table written just
# before an AskUserQuestion in the same response can vanish, and the operator answers blind. A
# hook cannot detect that here: the response being generated is not on disk until its tool calls
# finish (probed: still absent after a 4s wait inside this hook), so the rule is structural -
# context ends a reply, the question comes after the send-back. What it cannot do: stop prose the
# model writes inside the send-back response itself, before the question.
#
# How "right after the send-back" is read: at PreToolUse time the transcript's last non-meta
# user/assistant entry is the one BEFORE the current response. After a Stop-hook block it is a
# user entry whose content string starts "Stop hook feedback:".
#
# Self-heal (the one path that could otherwise fail CLOSED): a deny leaves a per-session token; a
# second question with no send-back in between is ADMITTED and logged as a fail-open. That covers
# notify-tag-guard being unwired after install, and a Claude Code version that writes the feedback
# entry differently or flushes the transcript earlier. Ceiling, disclosed: a model that simply
# retries the question after one deny gets through on the retry; guards.log shows it.
#
# Fail-open: kill switch (.state/off/ask-gate), notify-tag-guard switched off (.state/off/notify -
# without it nothing ever sends the turn back), an unattended session (unattended-guard owns
# AskUserQuestion there and denies it with its own remedy - two opposite deny reasons would
# contradict each other), a non-cli entrypoint (other hosts have no proven Stop-hook round trip),
# no jq, no readable transcript, or no user/assistant entry in its tail.
# Install-time probe (`# kit-probe: yes`): requires notify-tag-guard wired or requested.
# Self-check: ask-gate.selfcheck.sh.
set -u

if [ "${1:-}" = "--probe" ]; then
  command -v jq >/dev/null 2>&1 || { echo "jq is not on PATH - this gate parses the hook payload and transcript with jq"; exit 3; }
  case " ${KIT_PROBE_WITHOUT:-} " in
    *" notify-tag-guard "*)
      echo "notify-tag-guard is being removed in this same install - without its Stop-hook send-back no question could ever be admitted"
      exit 3 ;;
  esac
  wired=0
  case " ${KIT_PROBE_WITH:-} " in *" notify-tag-guard "*) wired=1 ;; esac
  if [ "$wired" != 1 ] && [ -n "${KIT_PROBE_SETTINGS:-}" ] && [ -f "${KIT_PROBE_SETTINGS:-/dev/null}" ]; then
    grep -q 'notify-tag-guard\.sh' "$KIT_PROBE_SETTINGS" 2>/dev/null && wired=1
  fi
  [ "$wired" = 1 ] || { echo "notify-tag-guard is not wired (neither in settings.json nor requested alongside --with-ask-gate) - without its Stop-hook send-back no question could ever be admitted"; exit 3; }
  exit 0
fi

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE="$CLAUDE_DIR/agent-tiers/.state"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s ask-gate %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}

[ -f "$STATE/off/ask-gate" ] && exit 0
[ -f "$STATE/off/notify" ] && exit 0
[ "${CLAUDE_CODE_ENTRYPOINT:-}" = "cli" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" = "AskUserQuestion" ] || exit 0

# sh -n first: under dash a syntax error in a dot-sourced file aborts the whole script with exit 2,
# which on PreToolUse is a block - a half-saved library would then deny every question.
CMDPOS="$(dirname "$0")/guard-cmdpos.sh"
if [ -r "$CMDPOS" ] && sh -n "$CMDPOS" >/dev/null 2>&1 && . "$CMDPOS" 2>/dev/null \
  && command -v guard_unattended >/dev/null 2>&1; then
  guard_unattended "$SID" && exit 0
fi

TP="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$TP" ] && [ -r "$TP" ] || { note "fail-open: no readable transcript"; exit 0; }

# Tail first: transcripts run to many MB. Metadata entries between the last message and now are a
# handful, so 300 lines reach it in practice; if they do not, fail open. isMeta user entries
# (harness-injected notices) are skipped so they cannot hide a send-back - except the send-back
# itself, which the CLI also writes with isMeta:true (observed live, 2.1.280).
LAST="$(tail -n 300 "$TP" 2>/dev/null | jq -c -R 'fromjson? | select((.type == "user" or .type == "assistant") and ((.isMeta != true) or ((.message.content | type) == "string" and (.message.content | startswith("Stop hook feedback:")))))' 2>/dev/null | tail -n 1)"
[ -n "$LAST" ] || { note "fail-open: no user/assistant entry in transcript tail"; exit 0; }

# Deny-streak token, per session; a malformed sid gets no token (and so no self-heal) rather than a
# path built from it. It holds the transcript's line count at the deny, so it only counts while
# nothing has moved the conversation on: a typed prompt or a send-back written after it makes it
# stale (otherwise one ignored deny would let some later, unrelated question through).
TOKEN=""
case "$SID" in '' | *[!A-Za-z0-9._-]* | . | ..) ;; *) TOKEN="$STATE/ask-gate-denied.$SID" ;; esac

if printf '%s' "$LAST" | jq -e '.type == "user" and (.message.content | type) == "string" and (.message.content | startswith("Stop hook feedback:"))' >/dev/null 2>&1; then
  [ -n "$TOKEN" ] && rm -f "$TOKEN" 2>/dev/null
  note "allow: follows a Stop-hook send-back"
  exit 0
fi

if [ -n "$TOKEN" ] && [ -f "$TOKEN" ]; then
  AT="$(cat "$TOKEN" 2>/dev/null || true)"
  rm -f "$TOKEN" 2>/dev/null
  case "$AT" in '' | *[!0-9]*) AT=0 ;; esac
  MOVED="$(tail -n +"$((AT + 1))" "$TP" 2>/dev/null | jq -c -R 'fromjson? | select(.type == "user" and (.message.content | type) == "string")' 2>/dev/null | head -n 1)"
  if [ -z "$MOVED" ]; then
    note "fail-open: second question with no send-back since the last deny (notify-tag-guard unwired, transcript format changed, or the model retried)"
    exit 0
  fi
fi
[ -n "$TOKEN" ] && { mkdir -p "$STATE" 2>/dev/null && wc -l < "$TP" 2>/dev/null | tr -d ' ' > "$TOKEN"; } 2>/dev/null

note "deny: AskUserQuestion not preceded by a Stop-hook send-back"
jq -n --arg r "Not yet: ask only after your context has ENDED a reply. Text written before a tool call (this question included) can reach the operator only as a one-line summary, so the table or findings this decision needs may never be seen. End this response now with that context as plain text, with no question in it, and make its final line exactly: operator:ask_next - you are sent straight back here to ask, and the question is admitted then. This is a hook deny, not a tool error: do not fall back to a numbered list in chat." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0

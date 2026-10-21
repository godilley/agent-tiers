#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers Stop hook: send a turn back ONCE when its reply hands the operator a `!` command
# (a chat-run shell line) with no `operator:run|kind:policy|oneoff` tag above it.
# notify-tag-strip.sh (MessageDisplay) renders that tag as a "YOU RUN" badge; HOST-4 states the rule.
#
# Why a hook: the rule was prose only, and transcript mining found it followed 3 times of ~120
# classified hand-backs in 45 days. A prose rule of that shape does not fire reliably; a send-back at
# the Stop arrival event does (same reasoning as notify-tag-guard.sh).
#
# Detection lives in lib/handback-tag.sh (shared with notify.sh, which stays silent while this guard
# is about to block); its header has the full rules. In short: a `!` command line (inside or outside a
# fence) or an inline `! cmd` span on a line with the word run/yourself, with no tag on the line
# directly above. The tag may sit directly above the command, directly above its opening fence, or
# (accepted, not the documented form) inside the fence above the first `!` line; one tag covers the
# whole fence. Footer tags (want_input, ask_next, no_input_required) never satisfy the check.
#
# Scope: native CLI only (non-cli entrypoints skip), the attention group, the main session only (Stop
# does not fire for subagents), and attended sessions only (an unattended session is never blocked:
# logs `allow: unattended`). Outside a fence each `!` line needs its own tag.
# Known misses and limits: bare commands without `!` (e.g. for a remote server) are not detected, prose
# rule only; an unclosed fence is scanned to the end of the reply, so later commands may hide inside it;
# a warning like "Don't run `! git reset --hard`" is flagged as a hand-back (the send-back tells the
# model to say it is only an example).
#
# Blocks AT MOST ONCE per offending reply within 10 minutes: a marker (session id + cksum of the
# flagged lines, written atomically) under .state/handback-tag-guard/, same pattern as
# subagent-bg-return-guard.sh. The age rule lives in lib/handback-tag.sh (shared with notify.sh): a
# marker older than 10 minutes no longer suppresses, and markers older than a day are deleted on each
# run (find -mtime +1 rounds down, so in practice 2 days). A reply ending operator:ask_next is not
# checked at all: notify-tag-guard already sends that turn back with "ask now, no text before the
# question", and a second send-back asking for resent text would contradict it (known limit: an
# untagged command in an ask_next context reply goes unflagged). Deliberately NOT keyed off stop_hook_active: that flag is harness-global (see
# advisory-ack-guard.sh), so after notify-tag-guard's ask_next send-back every later Stop carries it and
# this guard would go blind exactly when "decision taken, now run X" happens.
# A reply whose hand-backs are all tagged logs `allow: tagged hand-back`, so a compliance count is one grep.
# Fail-open: no jq/awk, no last_assistant_message, missing/unparseable lib, non-cli entrypoint, kill
# switch, kit-gate stand-down.
# Self-check: handback-tag-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s handback-tag-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}

# Kill switch first, before any side effect.
[ -f "$CLAUDE_DIR/agent-tiers/.state/off/handback-tag-guard" ] && exit 0
# Headless/scripted runs never enforce (see notify-tag-guard.sh); only `cli` is proven interactive.
[ "${CLAUDE_CODE_ENTRYPOINT:-}" = "cli" ] || exit 0
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v awk >/dev/null 2>&1 || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
LIB="$SELFDIR/lib/handback-tag.sh"
if [ -n "$SELFDIR" ] && [ -f "$LIB" ] && sh -n "$LIB" >/dev/null 2>&1; then
  . "$LIB"
fi

NTLIB="$SELFDIR/lib/notify-tag.sh"
if [ -n "$SELFDIR" ] && [ -f "$NTLIB" ] && sh -n "$NTLIB" >/dev/null 2>&1; then
  . "$NTLIB"
fi

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
LAST_MSG="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
[ -n "$LAST_MSG" ] || exit 0
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
command -v handback_tag_flagged >/dev/null 2>&1 || { note "fail-open: lib/handback-tag.sh missing/stale/unparseable"; exit 0; }

FLAGGED="$(handback_tag_flagged "$LAST_MSG")"
if [ -z "$FLAGGED" ]; then
  [ "$(handback_tag_count "$LAST_MSG")" -gt 0 ] 2>/dev/null && note "allow: tagged hand-back"
  exit 0
fi

# Unattended sessions: nobody is present to act on a send-back (same check as ask-gate.sh).
CMDPOS="$SELFDIR/guard-cmdpos.sh"
if [ -r "$CMDPOS" ] && sh -n "$CMDPOS" >/dev/null 2>&1 \
  && ( . "$CMDPOS" 2>/dev/null && command -v guard_unattended >/dev/null 2>&1 && guard_unattended "$SID" ); then
  note "allow: unattended"
  exit 0
fi

CLASS=""
command -v notify_tag_classify >/dev/null 2>&1 && CLASS="$(notify_tag_classify "$LAST_MSG")"
if [ "$CLASS" = ask_next ]; then
  note "allow: ask_next reply, not checked (would contradict notify-tag-guard's ask send-back)"
  exit 0
fi

MARKER="$(handback_tag_marker "${BASE:-${TMPDIR:-/tmp}}" "$SID" "$FLAGGED")"
MARKER_DIR="$(dirname "$MARKER")"
{ [ -d "$MARKER_DIR" ] && find "$MARKER_DIR" -type f -mtime +1 -delete; } 2>/dev/null || true
if handback_tag_seen "$MARKER"; then
  note "allow: already blocked once for this reply, letting it through"
  exit 0
fi
{ mkdir -p "$MARKER_DIR" 2>/dev/null && date +%s > "$MARKER_DIR/.tmp.$$" && mv -f "$MARKER_DIR/.tmp.$$" "$MARKER"; } 2>/dev/null || true

note "blocked: ! command handed back without an operator:run tag"
{
  printf 'agent-tiers: this reply hands back a command for the operator to run without a tag:\n'
  printf '%s\n' "$FLAGGED" | sed -n '1,3p' | sed 's/^/  /'
  printf 'Add operator:run|kind:policy (running it changes kit guard policy or safety state) or\n'
  printf 'operator:run|kind:oneoff (anything else) on the line directly above each command handed\n'
  printf 'back (above the opening fence when it is fenced). If a line is only an example, say so in\n'
  printf 'the reply instead.\n'
  printf 'Resend the corrected command(s) with the tag AND end the reply with its normal\n'
  printf 'operator: footer line. Your previous reply was ALREADY DELIVERED: send only that.\n'
} >&2
exit 2

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for notify-tag-guard.sh: jq-absent fail-open, no-message fail-open, both valid tags
# passing untouched, ask_next blocking on purpose with the ask-now message, a missing tag blocking with the required-syntax message, a tag present but not
# on the reply's actual last line still blocking, an EARLIER stray tag plus a valid one at the end
# ALSO blocking (mixed signal - live-demonstrated, not hypothetical), a block being logged to
# guards.log, a non-cli entrypoint (headless/claude -p/unproven host) never blocking even with no
# tag at all, and the kill switch standing the whole guard down.
set -u
H="$(cd "$(dirname "$0")" && pwd)/notify-tag-guard.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP notify-tag-guard: jq absent (guard fails open by design)"; exit 0; }

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
fail() { printf 'FAIL: %s\n' "$1"; rm -rf "$T"; exit 1; }
trap 'rm -rf "$T"' EXIT
export AGENT_TIERS_GUARDS_LOG="$T/guards.log"
export CLAUDE_CONFIG_DIR="$T/cfg"
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state"

run() { # $1=last_assistant_message
  out_err="$T/stderr"
  jq -cn --arg m "$1" '{hook_event_name:"Stop", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=cli sh "$H" >"$T/stdout" 2>"$out_err"
  echo "$?"
}

[ "$(run "")" = 0 ] || fail "empty last_assistant_message should fail open (exit 0)"

[ "$(run "$(printf 'All done.\noperator:want_input')")" = 0 ] || fail "valid want_input tag should pass"
[ "$(run "$(printf 'All done.\noperator:no_input_required|reason:waiting on build')")" = 0 ] || fail "valid no_input_required tag should pass"

rc="$(run "Just some prose, no tag at all.")"
[ "$rc" = 2 ] || fail "missing tag should block (exit 2), got $rc"
grep -q 'operator:want_input' "$T/stderr" || fail "block message should show the required syntax"
grep -q 'operator:ask_next' "$T/stderr" || fail "block message should offer the ask_next tag"
grep -q 'Ending in order to ask for a DECISION' "$T/stderr" || fail "block message should carry the re-read guidance block"
grep -q 'unattended-guard denies' "$T/stderr" || fail "guidance must carry the unattended carve-out"
grep -q 'operator:want_input needs no reason' "$T/stderr" || fail "guidance must spell the tags with their operator: prefix"
grep -q 'ALREADY DELIVERED' "$T/stderr" || fail "message must say the blocked reply was already delivered"
grep -q 'notify-tag-guard' "$AGENT_TIERS_GUARDS_LOG" 2>/dev/null || fail "a block should be logged to guards.log"

rc="$(run "$(printf 'operator:want_input\none more line after it')")"
[ "$rc" = 2 ] || fail "a tag not on the actual LAST line should still block, got $rc"

# Mixed signal: an EARLIER stray operator: line plus a valid one at the very end used to pass
# (only the last line was ever checked) - live-demonstrated, 2026-09-17, a real defect: a reply
# showing the "no input needed" badge partway through and "input needed" at the end. Must block.
rc="$(run "$(printf 'operator:no_input_required|reason:earlier stray\nMore text.\noperator:want_input')")"
[ "$rc" = 2 ] || fail "an earlier operator: line plus a valid one at the end must block as a mixed signal, got $rc"
grep -q '2 operator: tag lines' "$AGENT_TIERS_GUARDS_LOG" 2>/dev/null || fail "a mixed-signal block should be logged with its count"
# The SAME tag repeated twice is still two lines - not a contradiction in content, but still
# against the one-control-line discipline, and simpler to enforce uniformly than special-casing it.
rc="$(run "$(printf 'operator:want_input\nMore text.\noperator:want_input')")"
[ "$rc" = 2 ] || fail "the same tag repeated twice must still block, got $rc"

# ask_next is a valid tag that blocks ON PURPOSE: the reply holds a decision's context and the
# turn goes straight back to ask it (ask-gate.sh admits the AskUserQuestion after this block).
rc="$(run "$(printf 'Three options:\n| a | b |\noperator:ask_next')")"
[ "$rc" = 2 ] || fail "ask_next must block to send the turn back, got $rc"
grep -q 'AskUserQuestion' "$T/stderr" || fail "the ask_next block must tell the model to ask now"
grep -q 'ask_next: returning the turn' "$AGENT_TIERS_GUARDS_LOG" 2>/dev/null || fail "an ask_next send-back should be logged"
# Unattended: ask_next must NOT send the model back to ask (unattended-guard denies the question);
# it blocks with the do-not-ask remedy instead.
mkdir -p "$T/.state"; : > "$T/.state/unattended.sess-u"
rc="$(jq -cn --arg m "$(printf 'Options.\noperator:ask_next')" '{hook_event_name:"Stop", session_id:"sess-u", last_assistant_message:$m}' | AGENT_TIERS_STATE_DIR="$T/.state" CLAUDE_CODE_ENTRYPOINT=cli sh "$H" >/dev/null 2>"$T/stderr"; echo "$?")"
[ "$rc" = 2 ] || fail "ask_next in an unattended session must still block (with the unattended remedy), got $rc"
grep -q 'UNATTENDED' "$T/stderr" || fail "ask_next in an unattended session must use the unattended wording"
grep -q 'call AskUserQuestion as the only thing' "$T/stderr" && fail "ask_next in an unattended session must not tell the model to ask"
rc="$(run "$(printf 'operator:ask_next\nMore.\noperator:want_input')")"
[ "$rc" = 2 ] || fail "ask_next plus another tag must block as a mixed signal, got $rc"
grep -q 'operator: tag lines' "$T/stderr" || fail "ask_next plus another tag must get the mixed-signal message"

# A non-cli entrypoint (headless/claude -p/unproven third-party host) must never block, even with
# no tag at all - this kit's own claude -p callers (e.g. publish-public) must not get stuck.
rc="$(jq -cn --arg m "Just some prose, no tag at all." '{hook_event_name:"Stop", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=sdk-cli sh "$H" >/dev/null 2>"$T/stderr"; echo "$?")"
[ "$rc" = 0 ] || fail "a non-cli entrypoint must never block, even with no tag (got rc=$rc)"

# Kill switch stands the whole guard down, same feature toggle as notify.sh.
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off"
touch "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/notify"
rc="$(run "Just some prose, no tag at all.")"
rm -f "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/notify"
[ "$rc" = 0 ] || fail "the kill switch should stand the guard down entirely (got rc=$rc)"

# Missing library (broken install, not a normal runtime state) must fail OPEN, not abort or block -
# opus reviewer, 2026-09-17, MEDIUM/test-gap: this exact branch was asserted in the header and never
# actually run by any case, which is precisely how the sibling M4 defect (the notify.sh half of the
# same gap) shipped unnoticed. Sandbox-copy just the guard, deliberately with NO lib/ sibling.
NOLIB="$T/nolib"; mkdir -p "$NOLIB"
cp "$H" "$NOLIB/notify-tag-guard.sh" || fail "test setup: could not sandbox-copy the guard"
rc="$(jq -cn --arg m "Just some prose, no tag at all." '{hook_event_name:"Stop", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=cli sh "$NOLIB/notify-tag-guard.sh" >/dev/null 2>"$T/stderr"; echo "$?")"
[ "$rc" = 0 ] || fail "a missing library must fail OPEN (enforcement off), not block or error - got rc=$rc"
grep -q 'notify-tag-guard' "$AGENT_TIERS_GUARDS_LOG" 2>/dev/null || fail "the missing-library fail-open should still be logged"

echo "PASS notify-tag-guard.sh"

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for advisory-ack-guard.sh. Runnable: `sh advisory-ack-guard.selfcheck.sh`. Sandboxed via
# CLAUDE_CONFIG_DIR (same convention as resume-inject.selfcheck.sh - this guard's state root is paired
# with that hook's producer-side write, not the script's own on-disk location), so
# .state/advisory-pending, .state/advisory-nagged, .state/advisory-seen and guards.log never touch the
# real kit. Exits non-zero on first failure.
#
# Fixtures use REALISTIC transcript shape - one JSONL line PER CONTENT BLOCK (thinking/text/tool_use each
# their own line), never one line per message. An earlier version of this guard passed its own selfcheck
# while broken in production, because its fixtures used a fake one-block-per-message shape the real CLI
# never writes (opus reviewer, 2026-08-23, M1) - every fixture below is deliberately multi-line per turn
# so this class of bug cannot slip past again.
set -u
SRC_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"
T="${TMPBASE}/at-advisoryack-selfcheck.$$"
rm -rf "$T"; mkdir -p "$T/cfg" || fail "cannot build sandbox"
GUARD="$SRC_DIR/advisory-ack-guard.sh"
trap 'rm -rf "$T"' EXIT

# CLAUDE_CONFIG_DIR sandboxes pending/nagged/seen (this guard's producer-paired state root); LOG is
# BASE-derived (dirname("$0")), matching every sibling guard - see L7 in the guard's own header - so it
# needs its OWN override or it escapes the sandbox and writes to the REAL kit's guards.log.
export CLAUDE_CONFIG_DIR="$T/cfg"
export AGENT_TIERS_GUARDS_LOG="$T/cfg/agent-tiers/.state/guards.log"
PENDING_DIR="$T/cfg/agent-tiers/.state/advisory-pending"
NAGGED_DIR="$T/cfg/agent-tiers/.state/advisory-nagged"
SEEN_DIR="$T/cfg/agent-tiers/.state/advisory-seen"
GUARDS_LOG="$AGENT_TIERS_GUARDS_LOG"

TOK="/agent-tiers-init"

# A noise line carrying the substring `"role":"assistant"` INSIDE a tool_result's own text, never as the
# real message.role path - proves the guard's jq re-validation (not a raw grep) is what decides.
NOISE='{"message":{"role":"user","content":[{"type":"tool_result","content":"earlier text mentioned the field \"role\":\"assistant\" but this line is not one"}]}}'
line() { printf '{"message":{"role":"assistant","content":[{"type":"%s","text":"%s"}]}}\n' "$1" "$2"; }
tooluse() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"echo hi"}}]}}\n'; }

# MISS_T: a realistic multi-block turn (thinking, tool call, tool result, thinking, final text) whose
# LAST assistant-role line is a tool_use with no text at all - and no text block anywhere mentions the
# token. The old ("last entry only") design would have looked at exactly this last line and found nothing
# regardless of the token; the fixed design must ALSO correctly find nothing here (a true miss).
MISS_T="$T/miss.jsonl"
{ printf '%s\n' "$NOISE"
  line thinking "let me check status"
  line text "Current status: tree clean, nothing else open."
  tooluse
} > "$MISS_T"

# HIT_LAST_T: the token is in the FINAL text block, which also happens to be the last assistant-role
# line - the easy case the old design accidentally handled correctly.
HIT_LAST_T="$T/hit-last.jsonl"
{ printf '%s\n' "$NOISE"
  line thinking "let me check status"
  line text "Also: ASK before running $TOK per the session-start advisory."
} > "$HIT_LAST_T"

# HIT_MID_T: the REAL M1 regression case. The token appears in an EARLIER text block; the turn continues
# with more thinking/tool_use AFTER it, so the last assistant-role line is a tool_use with no text. The
# old design (last entry's content array only) would find nothing here and wrongly report a miss.
HIT_MID_T="$T/hit-mid.jsonl"
{ printf '%s\n' "$NOISE"
  line text "Heads up before I start: ASK before running $TOK, per the session-start advisory."
  line thinking "now let me do the actual work"
  tooluse
  printf '{"message":{"role":"user","content":[{"type":"tool_result","content":"hi"}]}}\n'
  line thinking "done, wrapping up"
  line text "All set, nothing else to report."
} > "$HIT_MID_T"

run() { # $1=session_id $2=transcript
  sid="$1"; tp="$2"
  OUT_ERR="$T/stderr.$$"
  out="$(jq -n --arg s "$sid" --arg t "$tp" '{session_id: $s, transcript_path: $t, stop_hook_active: false}' \
         | sh "$GUARD" 2>"$OUT_ERR")"
  RC=$?
  STDERR="$(cat "$OUT_ERR" 2>/dev/null || true)"; rm -f "$OUT_ERR"
}
seed_pending() { # $1=session_id $2..=tokens
  sid="$1"; shift
  mkdir -p "$PENDING_DIR" && printf '%s\n' "$@" > "$PENDING_DIR/$sid"
}

# 1. Token nowhere in a realistic multi-block miss transcript, never nagged before -> block (exit 2),
#    stderr names it, moved to NAGGED (not yet seen - outcome still pending).
seed_pending s1 "$TOK"
run s1 "$MISS_T"
[ "$RC" = 2 ] || fail "case 1: want exit 2, got $RC"
printf '%s' "$STDERR" | grep -qF -- "$TOK" || fail "case 1: stderr did not name the pending token"
grep -qxF -- "$TOK" "$NAGGED_DIR/s1" 2>/dev/null || fail "case 1: token not moved to nagged"
[ ! -f "$SEEN_DIR/s1" ] || fail "case 1: outcome must not be resolved yet after just one block"
grep -qxF -- "$TOK" "$PENDING_DIR/s1" 2>/dev/null || fail "case 1: token should remain pending until resolved"
grep -aq "advisory-ack-guard blocked:.*agent-tiers-init.*\[sid=s1\]" "$GUARDS_LOG" || fail "case 1: block not logged with sid tag"
printf 'ok   case 1: realistic miss transcript blocks once, moves to nagged, stays pending until resolved\n'

# 2. Same session, still missing on a LATER check (no reliance on stop_hook_active) -> now resolves as a
#    MISS: exit 0, never blocks again, moves out of nagged/pending into seen.
run s1 "$MISS_T"
[ "$RC" = 0 ] || fail "case 2: an already-nagged token must never block a second time, got $RC"
grep -qxF -- "$TOK" "$SEEN_DIR/s1" 2>/dev/null || fail "case 2: unresolved-on-recheck token not moved to seen"
if [ -f "$NAGGED_DIR/s1" ] && grep -qxF -- "$TOK" "$NAGGED_DIR/s1" 2>/dev/null; then
  fail "case 2: token should have left nagged once resolved"
fi
[ ! -f "$PENDING_DIR/s1" ] || fail "case 2: token should have left pending once resolved"
grep -aq "advisory-ack-guard miss:.*agent-tiers-init.*\[sid=s1\]" "$GUARDS_LOG" || fail "case 2: miss not logged with sid tag"
printf 'ok   case 2: unresolved recheck resolves as miss, no double block, no stop_hook_active needed\n'

# 3. A resolved (seen) token re-registered in pending by resume-inject.sh (e.g. a later compact/resume) -
#    must never block again regardless of transcript content.
seed_pending s1 "$TOK"
run s1 "$MISS_T"
[ "$RC" = 0 ] || fail "case 3: a token already in seen must never block again this session, got $RC"
printf 'ok   case 3: re-registering an already-resolved token never re-blocks\n'

# 4. Token present in the LAST assistant-role line (the easy case) -> acks directly, no block ever.
seed_pending s2 "$TOK"
run s2 "$HIT_LAST_T"
[ "$RC" = 0 ] || fail "case 4: want exit 0 when the token is present, got $RC"
grep -qxF -- "$TOK" "$SEEN_DIR/s2" 2>/dev/null || fail "case 4: acked token not recorded in seen"
[ ! -f "$PENDING_DIR/s2" ] || fail "case 4: pending file should be cleared after an ack"
[ ! -f "$NAGGED_DIR/s2" ] || fail "case 4: an acked-on-first-check token should never touch nagged"
grep -aq "advisory-ack-guard ack:.*agent-tiers-init.*\[sid=s2\]" "$GUARDS_LOG" || fail "case 4: ack not logged with sid tag"
printf 'ok   case 4: token in the last content-block line acks cleanly, never blocks\n'

# 5. THE M1 REGRESSION: token present in an EARLIER text block of the turn, but the turn's last
#    assistant-role line is a tool_use with no text. Must still ack - proves the fix actually collects
#    text across the whole recent window, not just the final content-block line.
seed_pending s3 "$TOK"
run s3 "$HIT_MID_T"
[ "$RC" = 0 ] || fail "case 5 (M1 regression): want exit 0 when the token is in an earlier block of the turn, got $RC"
grep -qxF -- "$TOK" "$SEEN_DIR/s3" 2>/dev/null || fail "case 5 (M1 regression): mid-turn token not acked - extraction is still last-block-only"
printf 'ok   case 5: token in an EARLIER text block (last line is a tool_use) still acks - M1 regression covered\n'

# 6. No pending file at all -> exit 0, NOTHING written under .state (the near-zero-overhead path).
rm -rf "$T/cfg/agent-tiers/.state"
run s4 "$HIT_LAST_T"
[ "$RC" = 0 ] || fail "case 6: no pending file must exit 0, got $RC"
[ ! -e "$T/cfg/agent-tiers/.state" ] || fail "case 6: a session with nothing pending must not touch .state at all"
printf 'ok   case 6: nothing-pending path touches no state\n'

# 7. Fail-open: unreadable/missing transcript with a real pending token -> exit 0, no block.
seed_pending s5 "$TOK"
run s5 "$T/does-not-exist.jsonl"
[ "$RC" = 0 ] || fail "case 7: unreadable transcript must fail open, got $RC"
grep -aq "advisory-ack-guard fail-open:.*no readable transcript.*\[sid=s5\]" "$GUARDS_LOG" || fail "case 7: fail-open not logged"
printf 'ok   case 7: unreadable transcript fails open\n'

# 8. Fail-open: garbage stdin / bad session id -> exit 0, nothing written, no traversal.
rm -rf "$T/cfg/agent-tiers/.state"
out="$(printf 'not json' | sh "$GUARD" 2>/dev/null)"; RC=$?
[ "$RC" = 0 ] && [ -z "$out" ] || fail "case 8a: garbage stdin must fail open silently, got rc=$RC out=$out"
run '../../evil' "$HIT_LAST_T"
[ "$RC" = 0 ] || fail "case 8b: traversal-shaped session id must fail open, got $RC"
[ ! -e "$T/cfg/agent-tiers/.state/advisory-pending/../../evil" ] || fail "case 8b: traversal session id escaped the pending dir"
printf 'ok   case 8: garbage stdin and a traversal-shaped session id both fail open, no traversal\n'

echo "OK advisory-ack-guard: block-at-most-once-per-token (no stop_hook_active dependency), correct ack/miss resolution across multi-block turns (M1 regression covered), near-zero overhead when nothing pending, and fail-open all hold"

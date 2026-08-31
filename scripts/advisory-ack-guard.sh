#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers Stop hook: force a SPEECH-ACT advisory to actually surface, instead of trusting the Lead's
# own relevance judgment. Sibling of resume-inject.sh (the emitter) and review-gate-guard.sh (whose
# transcript-reading conventions this reuses: structured jq extraction, never a raw grep).
#
# Why this exists (incident, not opinion): session e824d942 got resume-inject.sh's "project layer never
# wired, ASK before running /agent-tiers-init" advisory at SessionStart, correctly. The Lead silently
# judged it not relevant and dropped it from two replies, until asked directly three times. Root cause:
# three of resume-inject.sh's four advisories require an act the harness already observes afterward (a
# push, an Edit, a re-install); this one requires a SPEECH ACT, and nothing observed whether it happened.
# A naive fix (grep the whole transcript for the keyword at session end) does not work either - checked
# live: the broken session's transcript has 7 hits for "agent-tiers-init", so end-of-session/anywhere-in-
# transcript would have called that exact session compliant. See the private-notes companion repo's
# arrival-advisory-swallow-findings doc for the full incident + doctrine-wide gap-check.
#
# Design: Stop fires at the end of EVERY assistant turn, not just session end. Check the transcript's
# recent assistant TEXT for each still-active ack token (a literal substring resume-inject.sh already put
# in the advisory text). A real transcript is ONE LINE PER CONTENT BLOCK (thinking/text/tool_use each
# their own line, opus reviewer 2026-08-23, verified live against a real transcript) - so "the last
# assistant-role line" is usually a single block, not the turn's full reply, and can just as easily be a
# tool_use or thinking block with no text at all. Collecting text from every assistant-role line in a
# generous recent window (not just the very last one) is what actually reads "did this turn's reply
# mention it" correctly; widening the window is safe because it is only ever consulted for a token that
# has NEVER yet been found (an already-acked token is never re-checked), so it can only help a match, not
# manufacture a false one for something already resolved.
#
# Three-state per session (pending / nagged / seen), not two - a token that gets its one block still
# needs its OUTCOME (ack or miss) determined and logged on a LATER check, and that determination must
# never depend on `stop_hook_active` being "the retry after MY specific block" (opus reviewer, 2026-08-23:
# that flag is harness-global, not owned by this hook - a second Stop hook existing at all breaks that
# assumption). So: PENDING = never yet nagged; NAGGED = already given its one block, outcome pending;
# SEEN = resolved (ack or miss), never touched again. A token blocks AT MOST ONCE per session regardless
# of what triggers the next check, and its ack/miss outcome is always genuinely re-derived, never assumed.
#
# Known ceilings, disclosed rather than silently absorbed:
# - Only resume-inject.sh's advisory A uses this today (SC-6.2/SC-6.3/SC-6.1a, advisory B/C's disjunctive
#   branches all need a DIFFERENT compliance check - no natural token, or an OR/ordering claim
#   text-presence can't express - not folded in, see the findings doc).
# - Wired via install-flat.sh's HOOK_ROWS (id `advisory-ack-guard`, class `consent`, `Stop`). This
#   comment previously claimed the opposite (stale from before the HOOK_ROWS row was added in the same
#   commit that wrote it) - corrected 2026-08-23 per install-flat.sh:67, not hooks/hooks.json yet.
# - TODO: the "transcript is flushed before Stop fires" assumption is inherited from
#   numeric-claim-ledger.sh's probe, not independently re-verified live for THIS hook. After this ships,
#   `grep -a 'advisory-ack-guard ack:' <the real guards.log>` once, in a session known to have complied -
#   if every real-session line is `blocked:`/`miss:` and `ack:` never appears, the flush-order assumption
#   is wrong (opus reviewer 2026-08-23, L6).
# - guards.log's own `blocked:`/`ack:`/`miss:` word isn't in guard-summary.sh's `deny|ask` vocabulary, so
#   this hook's blocks don't count toward the SessionEnd summary line yet - the `[sid=...]` tag makes
#   them greppable today; extending that vocabulary is a disclosed follow-up (opus reviewer 2026-08-23, M3).
# - A resumed session (`--resume`, same session id) can never re-nag an already-`seen` token even if the
#   underlying condition is still true - correct per "once per session", but only ever exercised at the
#   session-id granularity, not the human's actual continuity (opus reviewer 2026-08-23, L10).
# - `resume-inject.sh` writes the pending file before it emits the advisory text. A hook timeout in that
#   narrow window would register a token for an advisory the Lead never actually received. Ordering-only,
#   low probability, not restructured here (opus reviewer 2026-08-23, L11).
# - `seen`'s mtime is never refreshed after a token is written there, so in a session alive past the 7-day
#   GC window a resolved token could be forgotten and re-nagged. Rare, bounded, not fixed (opus reviewer
#   2026-08-23, L9).
#
# Fail-open on any tooling gap (no jq, no transcript, unreadable state dir, bad session id). Never
# touches the pending/nagged/seen files for a session with nothing pending - the near-zero-overhead path
# for the overwhelming majority of turns. Self-check: advisory-ack-guard.selfcheck.sh.
set -u

# STATE (pending/nagged/seen) is CLAUDE_CONFIG_DIR-aware, matching resume-inject.sh's producer-side write
# - not dirname("$0")-derived, or a relocated config dir (2nd account) would write pending tokens one
# place and read them from another, silently no-op'ing the whole guard. LOG stays dirname("$0")-derived
# like every sibling guard (opus reviewer 2026-08-23, L7): guard-summary.sh reads guards.log from its own
# BASE, not CLAUDE_CONFIG_DIR, so a CLAUDE_DIR-keyed log here would silently diverge from the file the
# kit's own summary tooling reads. Two different roots, on purpose, each matched to its own reader.
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE="${CLAUDE_DIR}/agent-tiers/.state"
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox

# `[sid=...]` suffix matches the shared convention every other guard's decision line carries (opus
# reviewer 2026-08-23, M3) - NOT yet counted by guard-summary.sh's own summary line, whose `deny|ask`
# vocabulary has no "block" word for a Stop-hook gate; that vocabulary extension is a disclosed follow-up,
# not done here. The tag still makes this hook's lines greppable/filterable by session today.
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s advisory-ack-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SESSION_ID:-}" >> "$LOG"; } 2>/dev/null || true
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
    tail -n 2500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null || true
  fi
}

command -v jq >/dev/null 2>&1 || exit 0   # fail open, silently - nothing to log to yet without jq
INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in
  ''|*[!A-Za-z0-9._-]* | '.' | '..') exit 0 ;;   # unusable id: same F-12 charset guard as resume-inject.sh/review-gate-guard.sh
esac

PENDING_DIR="$STATE/advisory-pending"
NAGGED_DIR="$STATE/advisory-nagged"
SEEN_DIR="$STATE/advisory-seen"
PENDING_FILE="$PENDING_DIR/$SESSION_ID"
NAGGED_FILE="$NAGGED_DIR/$SESSION_ID"
SEEN_FILE="$SEEN_DIR/$SESSION_ID"

[ -f "$PENDING_FILE" ] || exit 0   # cheap path: nothing pending this session, no state touched at all

# Opportunistic GC, same posture as session-prefs/review-gate-asked (7-day mtime).
{ [ -d "$PENDING_DIR" ] && find "$PENDING_DIR" -type f -mtime +7 -delete; } 2>/dev/null || true
{ [ -d "$NAGGED_DIR" ] && find "$NAGGED_DIR" -type f -mtime +7 -delete; } 2>/dev/null || true
{ [ -d "$SEEN_DIR" ] && find "$SEEN_DIR" -type f -mtime +7 -delete; } 2>/dev/null || true

NL='
'
listfile() { [ -f "$1" ] && cat "$1" 2>/dev/null || true; }
contains() { printf '%s\n' "$1" | grep -qxF -- "$2" 2>/dev/null; }   # $1=newline list, $2=token

PENDING="$(listfile "$PENDING_FILE")"
SEEN="$(listfile "$SEEN_FILE")"
NAGGED="$(listfile "$NAGGED_FILE")"

# Still-active = registered by resume-inject.sh this session, minus anything already fully resolved.
STILL_ACTIVE=""
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  contains "$SEEN" "$tok" && continue
  STILL_ACTIVE="${STILL_ACTIVE:+$STILL_ACTIVE$NL}$tok"
done <<EOF
$PENDING
EOF
if [ -z "$STILL_ACTIVE" ]; then
  # Everything was already resolved (e.g. resume-inject.sh rewrote pending on a later compact/resume
  # after this session's tokens were already acked) - clean up and exit, nothing left to check.
  rm -f "$PENDING_FILE" "$NAGGED_FILE" 2>/dev/null || true
  exit 0
fi

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
if [ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ]; then
  note "fail-open: no readable transcript_path in payload"
  exit 0
fi

# Every assistant-role TEXT block in a generous recent window, concatenated - never just "the last line"
# (each real transcript line is ONE content block, so the last line alone is frequently a tool_use or
# thinking block with no text). Safe to widen: this is only ever consulted for a STILL-ACTIVE token, so a
# broader window can only surface a real match sooner, never fabricate one for something already resolved.
# Candidate lines pre-filtered with grep (transcripts run to many MB), then structurally re-validated with
# jq so a tool_result/pasted-JSON line that merely CONTAINS the substring `"role":"assistant"` cannot pass
# (same defense as review-gate-guard's subagent_type check).
RECENT_TEXT="$(grep -a '"role"[[:space:]]*:[[:space:]]*"assistant"' "$TRANSCRIPT" 2>/dev/null | tail -n 60 | jq -R -s -r '
    split("\n") | map(select(length > 0)) | map(try fromjson catch empty) | map(select(.message.role? == "assistant"))
    | map((.message.content // [])[]? | select(.type == "text") | .text)
    | join("\n")
  ' 2>/dev/null)"

RESOLVED_ACK=""; RESOLVED_MISS=""; TO_BLOCK=""
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  if [ -n "$RECENT_TEXT" ] && printf '%s' "$RECENT_TEXT" | grep -qF -- "$tok"; then
    RESOLVED_ACK="${RESOLVED_ACK:+$RESOLVED_ACK$NL}$tok"
  elif contains "$NAGGED" "$tok"; then
    # Already given its one block on an earlier check; still not surfaced now - resolve as a miss,
    # never block a second time for it.
    RESOLVED_MISS="${RESOLVED_MISS:+$RESOLVED_MISS$NL}$tok"
  else
    TO_BLOCK="${TO_BLOCK:+$TO_BLOCK$NL}$tok"
  fi
done <<EOF
$STILL_ACTIVE
EOF

[ -n "$RESOLVED_ACK" ] && printf '%s\n' "$RESOLVED_ACK" | while IFS= read -r t; do [ -n "$t" ] && note "ack: '$t' surfaced"; done
[ -n "$RESOLVED_MISS" ] && printf '%s\n' "$RESOLVED_MISS" | while IFS= read -r t; do [ -n "$t" ] && note "miss: '$t' still not surfaced after one block"; done

RESOLVED="${RESOLVED_ACK}${RESOLVED_ACK:+$NL}${RESOLVED_MISS}"
NEW_SEEN="${SEEN}${SEEN:+$NL}${RESOLVED}"
{ mkdir -p "$SEEN_DIR" 2>/dev/null && [ -n "$NEW_SEEN" ] && printf '%s\n' "$NEW_SEEN" > "$SEEN_FILE"; } 2>/dev/null || true

# Remaining pending = whatever is still active minus what just resolved (ack or miss) this pass -
# includes TO_BLOCK, which stays pending until a LATER check resolves it.
REMAINING_PENDING=""
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  contains "$RESOLVED_ACK" "$tok" && continue
  contains "$RESOLVED_MISS" "$tok" && continue
  REMAINING_PENDING="${REMAINING_PENDING:+$REMAINING_PENDING$NL}$tok"
done <<EOF
$STILL_ACTIVE
EOF
{ mkdir -p "$PENDING_DIR" 2>/dev/null && { [ -n "$REMAINING_PENDING" ] && printf '%s\n' "$REMAINING_PENDING" > "$PENDING_FILE" || rm -f "$PENDING_FILE"; }; } 2>/dev/null || true

# NAGGED = previously nagged minus what just resolved, plus anything newly blocked below.
NEW_NAGGED=""
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  contains "$RESOLVED_MISS" "$tok" && continue
  NEW_NAGGED="${NEW_NAGGED:+$NEW_NAGGED$NL}$tok"
done <<EOF
$NAGGED
EOF
if [ -n "$NEW_NAGGED" ] && [ -n "$TO_BLOCK" ]; then
  NEW_NAGGED="${NEW_NAGGED}${NL}${TO_BLOCK}"
elif [ -n "$TO_BLOCK" ]; then
  NEW_NAGGED="$TO_BLOCK"
fi
{ mkdir -p "$NAGGED_DIR" 2>/dev/null && { [ -n "$NEW_NAGGED" ] && printf '%s\n' "$NEW_NAGGED" > "$NAGGED_FILE" || rm -f "$NAGGED_FILE"; }; } 2>/dev/null || true

[ -n "$TO_BLOCK" ] || exit 0   # nothing newly unresolved this pass - ack/miss already recorded above

note "blocked: pending advisory not yet surfaced: $(printf '%s' "$TO_BLOCK" | tr '\n' ';')"
{
  printf 'agent-tiers: this reply is about to end without surfacing an arrival advisory the session start hook gave you. '
  printf 'Add it to your reply before finishing this turn - do not silently judge it out of scope. Pending: '
  printf '%s' "$TO_BLOCK" | tr '\n' ';'
} >&2
exit 2

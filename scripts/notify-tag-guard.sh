#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers Stop hook: block a turn from ending until its own last line states whether the
# operator's input is actually wanted, so notify-stop.sh (the sibling Stop hook that drives the
# desktop ping) has an authoritative signal instead of inferring one.
#
# Why not infer from background_tasks (Stop input already carries it): a background task Claude is
# waiting to be auto-woken by (Claude Code delivers its result as a new turn when it finishes, per
# `goal.md`) is structurally IDENTICAL in that array to a stray one that never finishes on its own
# (a dev server, a while/until loop) - both just show up as one more "running" entry. Inferring
# "suppress" from non-empty background_tasks would silence the ping forever for the second case.
# The reverse also breaks it: Claude can genuinely want input WHILE background work is still
# running (a subagent fan-out mid-flight, plus an unrelated clarifying question). Only Claude's own
# in-the-moment judgment carries that distinction - so this asks for it directly, structurally
# enforced (a paragraph-only instruction measures ~2% compliance in this project's own corpus, see
# `rules-need-arrival-events` - a blocking hook is what actually works), same shape as
# `sc52a-write-disclosure-guard.sh`'s `[bash-write:<reason>]` marker: allow AND log, never silent.
#
# Required: EXACTLY ONE of these, as the last line of every reply, and no operator: line earlier
# in the same reply (live-demonstrated, 2026-09-17: an earlier stray tag plus a valid one at the
# end used to pass, showing both badges in one reply - a genuine mixed signal, not hypothetical):
#   operator:want_input
#   operator:no_input_required|reason:<why>
#   operator:ask_next   (blocks on purpose: the reply holds a decision's context, see below)
# notify-tag-strip.sh (a sibling MessageDisplay hook) replaces this line with a rendered badge.
#
# The blocked-turn message also carries a short re-read prompt (ending-to-ask goes through
# operator:ask_next; the want_input/no_input_required asymmetry stated out loud).
# ask_next exists because prose written between tool calls is not reliably delivered: some models
# return it as a "narration" thinking block, shown to the operator only as a one-line summary, so
# a table written just before an AskUserQuestion can vanish. A reply that ENDS without a tool call
# arrives in full. So the context ends a reply tagged ask_next, this guard sends the turn straight
# back, and ask-gate.sh (PreToolUse) admits AskUserQuestion only right after that send-back.
# Basis, measured 2026-09-20 over 280 transcripts: this guard blocked 104 turns, and in 3
# verified cases the retry issued an AskUserQuestion the blocked turn lacked - the gate already
# acts as a reflection checkpoint, not only a formatter. 3/104 is a floor: a re-read that
# changes reasoning without changing a tool call leaves no trace that measurement can see.
# The unattended carve-out in that bullet is required: unattended-guard.sh denies
# AskUserQuestion when .state/unattended.<session-id> exists, so without it two live kit guards
# would issue opposite orders in the same turn.
#
# Bounded by Claude Code's own documented 8-consecutive-block ceiling per turn - no extra
# self-imposed cap here, unlike advisory-ack-guard.sh (that guard tracks a one-shot-per-session
# token; this one re-checks fresh on every single turn, so "block at most once" doesn't apply the
# same way). Every block is logged, so a chronic-failure pattern is visible in guards.log, not silent.
# ask_next blocks spend that same budget (one per decision). If a turn ever hits the ceiling, the
# turn ends with the ask_next badge and no question; the operator replies in chat.
#
# Fail-open: no jq, no last_assistant_message at all (a turn that ended with zero text content -
# nothing to tag), the field is absent from this Claude Code version, or lib/notify-tag.sh is
# missing/stale.
# Self-check: notify-tag-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s notify-tag-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}

# Kill switch first, before ANY side effect or read, including sourcing the library (opus
# reviewer, 2026-09-17, MEDIUM: sourcing used to run BEFORE this, so a corrupted lib file - a
# half-saved edit mid-write, a leftover merge-conflict marker - could stand this check down.
# Confirmed live: under dash, a syntax error in a dot-sourced file aborts the WHOLE script with
# exit 2, which happens to be the exact Stop-hook block code - the shell's own parse-error text
# becomes the block reason, on every single turn, with no working kill switch to escape it, since
# it never got the chance to run).
[ -f "$CLAUDE_DIR/agent-tiers/.state/off/notify" ] && exit 0

# Headless/scripted runs (opus reviewer, 2026-09-17, HIGH): never enforce here - see notify.sh's
# matching gate for the full reasoning (this kit's own claude -p callers, e.g. publish-public,
# would otherwise get blocked mid-script on machine-consumed output). Only the exact value `cli`
# is proven native-interactive (HOST.md HOST-1); everything else skips.
[ "${CLAUDE_CODE_ENTRYPOINT:-}" = "cli" ] || exit 0
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0   # fail open, silently - nothing to log to yet without jq
# A missing tail/grep must fail OPEN (exit 0), not fall through to the block below - the header's
# fail-open contract covered jq and an absent field, but not this (opus reviewer, 2026-09-17, LOW).
command -v tail >/dev/null 2>&1 || exit 0
command -v grep >/dev/null 2>&1 || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
LIB="$SELFDIR/lib/notify-tag.sh"
if [ -n "$SELFDIR" ] && [ -f "$LIB" ] && sh -n "$LIB" >/dev/null 2>&1; then
  . "$LIB"
fi
command -v notify_tag_classify >/dev/null 2>&1 || { note "fail-open: lib/notify-tag.sh missing/stale/unparseable"; exit 0; }

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
LAST_MSG="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
[ -n "$LAST_MSG" ] || exit 0   # nothing to tag

# notify_tag_classify (lib/notify-tag.sh, shared with notify.sh's Stop branch - see that file's
# header for why: this exact split caused a real live bug when the two copies drifted).
CLASS="$(notify_tag_classify "$LAST_MSG")"
case "$CLASS" in want_input | no_input_required) exit 0 ;; esac

SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"

# ask_next: the reply ended on the context for a decision (a reply that ENDS without a tool call is
# the one place prose reliably reaches the operator in full - text written between tool calls can
# come back as a summarized thinking block on some models). Send the turn back to ask it now; the
# sibling ask-gate.sh only lets AskUserQuestion through right after this exact block.
if [ "$CLASS" = "ask_next" ]; then
  CMDPOS="$SELFDIR/guard-cmdpos.sh"
  if [ -r "$CMDPOS" ] && sh -n "$CMDPOS" >/dev/null 2>&1 && . "$CMDPOS" 2>/dev/null \
    && command -v guard_unattended >/dev/null 2>&1 && guard_unattended "$SID"; then
    note "ask_next in an unattended session: blocked with the do-not-ask remedy"
    {
      printf 'agent-tiers: ask_next in an UNATTENDED session - nobody is present to answer, and\n'
      printf 'unattended-guard denies AskUserQuestion. Do not ask: take the reading that preserves\n'
      printf 'existing behaviour, note the fork and your choice, and end with a normal tag.\n'
    } >&2
    exit 2
  fi
  note "ask_next: returning the turn to ask"
  {
    printf 'agent-tiers: ask_next - the context above has been delivered. Ask the decision NOW:\n'
    printf 'call AskUserQuestion as the only thing in this response, with no text before it (text\n'
    printf 'written before a tool call can be replaced by a summary). Point at the context above\n'
    printf 'instead of repeating it. After the answer, carry on; end the turn with a normal tag.\n'
  } >&2
  exit 2
fi

if [ "$CLASS" = "mixed" ]; then
  MATCH_COUNT="$(printf '%s' "$LAST_MSG" | grep -acE "$(notify_tag_regex)" 2>/dev/null || true)"
  note "blocked: ${MATCH_COUNT:-2} operator: tag lines in one reply - mixed signal"
  {
    printf 'agent-tiers: this reply has %s operator: tag lines - exactly one is required, as the\n' "${MATCH_COUNT:-2}"
    printf 'final line, never earlier in the reply too. A reply cannot show both badges at once.\n'
    printf 'Remove every operator: line except the one true answer at the very end.\n'
  } >&2
else
  note "blocked: reply ended without a required operator: tag"
  {
    printf 'agent-tiers: this reply must end with exactly one of these, on its own final line, before\n'
    printf 'the turn can finish:\n'
    printf '  operator:want_input\n'
    printf '  operator:no_input_required|reason:<why - e.g. waiting on a background command or subagent>\n'
    printf '  operator:ask_next   (this reply holds the context for a decision you ask next)\n'
    printf '\n'
    printf 'Before you pick, re-read what this turn actually did. The tag is the prompt to check:\n'
    printf '  - Ending in order to ask for a DECISION? Keep the context in this reply and end it with\n'
    printf '    operator:ask_next instead: you are sent straight back to ask it with AskUserQuestion.\n'
    printf '    (Unattended sessions are the exception: unattended-guard denies AskUserQuestion there,\n'
    printf '    so state the fork in the reply and tag operator:want_input instead.)\n'
    printf '  - Question left sitting in the prose? That is the same fork, unasked. Make it a real one.\n'
    printf '  - operator:want_input needs no reason; operator:no_input_required does. If you cannot\n'
    printf '    state the reason, the honest tag is operator:want_input.\n'
    printf '\n'
    printf '\n'
    printf 'Your previous reply was ALREADY DELIVERED - this block does not withdraw it. Do not repeat\n'
    printf 'it. Send only what the re-read changes, plus the tag. If nothing changes, the tag alone is\n'
    printf 'the right answer, but you have just re-read the turn: say in one line what you checked.\n'
    printf '\n'
    printf 'Add the tag line exactly, with nothing after it. A sibling MessageDisplay hook renders that\n'
    printf 'one line as a badge - this diagnostic message itself is normal Stop-hook feedback and stays\n'
    printf 'visible to the operator, same as any other blocked-turn reason.\n'
  } >&2
fi
exit 2

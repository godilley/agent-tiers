#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers MessageDisplay hook: replace notify-tag-guard.sh's required `operator:want_input` /
# `operator:no_input_required|reason:...` / `operator:ask_next` line, on screen only, with a small ANSI-coloured status
# badge - a SECOND, persistent visual cue that stays in the chat transcript itself, so a missed
# desktop notification still leaves an at-a-glance answer to "does the operator need to look at this."
# VERIFIED live 2026-09-17: Claude Code's terminal renderer passes raw ANSI SGR bytes in a
# MessageDisplay `displayContent` straight through - both badges rendered correctly in the real
# terminal, confirmed on the same session that first shipped this (both colours, not garbage
# control-byte text). If a future host/renderer breaks this, drop back to a blank strip (git
# history has it) rather than iterating on ANSI further.
#
# Safe against streaming batch boundaries: Claude Code holds every batch (final or not) until this
# hook returns before rendering it ("MessageDisplay input" in hooks.md), and a batch's delta is
# always whole lines except possibly the final one - so the tag line, wherever it lands, arrives
# complete within exactly one call's `.delta` and can always be matched/removed before it is ever
# shown. Never touches the transcript or what Claude itself sees - display-only, per the event's
# own contract.
#
# Disclosed minor ceiling: reconstructing `.delta` with the tag line removed can lose a byte-exact
# trailing-newline match against the original in some grep implementations (cosmetic only - at most
# one blank line more/fewer around where the tag was; never re-surfaces the tag itself).
#
# Logs the replaced line to guards.log (never silent - same idiom as every other guard here), even
# though this event has no allow/deny decision of its own.
# Fail-open: no jq, no delta, no match.
# Self-check: notify-tag-strip.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s notify-tag-strip %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}

# Same feature toggle as notify.sh/notify-tag-guard.sh.
[ -f "$CLAUDE_DIR/agent-tiers/.state/off/notify" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
# Cheap bail (opus reviewer, 2026-09-17, MEDIUM/Perf) BEFORE spawning jq: MessageDisplay holds every
# batch until this hook returns, and the tag can only ever appear as a literal `operator:` line, so
# a plain substring miss on the raw JSON text rules it out for the overwhelming majority of batches
# without paying for jq/grep at all.
case "$INPUT" in *operator:*) ;; *) exit 0 ;; esac
# kit-gate after the cheap bail, not before it: a batch with no tag exits silently either way, and the
# gate's child sh would otherwise be paid on every batch MessageDisplay holds.
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0
DELTA="$(printf '%s' "$INPUT" | jq -r '.delta // empty' 2>/dev/null || true)"
[ -n "$DELTA" ] || exit 0

TAG_RE='^operator:(want_input|ask_next|no_input_required\|reason:.+)$'
MATCHED="$(printf '%s' "$DELTA" | grep -aE "$TAG_RE" || true)"
[ -n "$MATCHED" ] || exit 0   # no tag in this batch - stay silent, original renders unchanged

# Bold + colour SGR, reset after. "wants input" uses 256-colour orange (38;5;208, xterm's
# DarkOrange) rather than basic SGR 33, which renders as plain yellow in most terminals, not
# orange/amber - confirmed too yellow live, 2026-09-17. "does not" stays basic green (32).
# Nerd Font glyphs (a common statusline font family, same
# icon+space+text convention) placed on OPPOSITE sides on purpose - a left-edge warning triangle
# vs a right-edge checkmark reads as a distinct SHAPE at a glance, not just a distinct colour, so
# the two badges are still tellable apart for a colour-blind read or a monochrome terminal. The
# ask_next badge shares the orange (a question is coming) and differs by its words, not a glyph.
# Two spaces after the triangle, one is enough everywhere else: the triangle glyph renders wide in
# the test terminal's font and visually ate a single trailing space live, 2026-09-17 - confirmed by screenshot,
# not by anything a script can measure. Font/terminal-specific, disclosed not chased further.
# Bracket padding: a plain ASCII space, doubled brackets. Two narrower Unicode-space variants
# (U+2009 thin space, U+200A hair space) were BOTH tried live and both rendered as zero-width in
# the real terminal - a dead end, corrected here 2026-09-17 (an earlier version of this comment
# claimed U+2009 bytes were shipped; they never were - a stale claim caught by opus review, MEDIUM,
# 2026-09-17: a comment in this file is the only record of a live probe that can't be re-run by a
# script, so a wrong one is a real defect, not a nit).
# U+F071 (nf-fa-exclamation_triangle) = EF 81 B1, U+F00C (nf-fa-check) = EF 80 8C. Octal, not \x -
# dash's printf builtin (2 of 3 Linux CI legs use sh=dash) re-encodes \xHH as if it were a codepoint
# under a UTF-8 locale instead of inserting the raw byte, corrupting a literal UTF-8 sequence built
# byte-by-byte; \OOO is the portable form this kit already uses elsewhere (notify.selfcheck.sh).
# The glyphs are Nerd Font private-use codepoints: without that font they render as empty boxes, so
# they are opt-in (AGENT_TIERS_BADGE_GLYPHS=nerd). The plain default keeps the colour and the words,
# which already differ, and marks the wants-input badge with an ASCII "!" in the triangle's place.
# NO_COLOR (no-color.org): set and non-empty drops the SGR escapes, the text and glyphs stay.
C_OR="$(printf '\033[1;38;5;208m')"; C_GR="$(printf '\033[1;32m')"; C_RS="$(printf '\033[0m')"
[ -n "${NO_COLOR:-}" ] && { C_OR=""; C_GR=""; C_RS=""; }
if [ "${AGENT_TIERS_BADGE_GLYPHS:-}" = nerd ]; then
  BADGE_WANT="$(printf '%s[[ \357\201\261  INPUT NEEDED ]]%s' "$C_OR" "$C_RS")"
  BADGE_NONE="$(printf '%s[[ NO INPUT NEEDED \357\200\214 ]]%s' "$C_GR" "$C_RS")"
else
  BADGE_WANT="$(printf '%s[[ ! INPUT NEEDED ]]%s' "$C_OR" "$C_RS")"
  BADGE_NONE="$(printf '%s[[ NO INPUT NEEDED ]]%s' "$C_GR" "$C_RS")"
fi
# ask_next: same orange as "wants input" (a question is coming), plain text, no glyph.
BADGE_ASK="$(printf '%s[[ QUESTION NEXT ]]%s' "$C_OR" "$C_RS")"
SEDSCRIPT='s/^operator:want_input$/'"$BADGE_WANT"'/; s/^operator:ask_next$/'"$BADGE_ASK"'/; s/^operator:no_input_required\|reason:.+$/'"$BADGE_NONE"'/'
STRIPPED="$(printf '%s' "$DELTA" | sed -E "$SEDSCRIPT")"
# A sed failure (absent from a restricted PATH, no -E support) yields an empty capture with no
# error surfaced - opus reviewer, 2026-09-17, MEDIUM: unguarded, that would publish
# displayContent:"" and blank the WHOLE batch instead of failing open. STRIPPED can never
# legitimately be empty here: MATCHED non-empty guarantees at least one line survives as a
# non-empty badge.
[ -n "$STRIPPED" ] || { note "fail-open: sed produced empty output, not publishing a blanked batch"; exit 0; }
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
printf '%s\n' "$MATCHED" | while IFS= read -r m; do [ -n "$m" ] && note "badged: '$m'"; done
jq -nc --arg d "$STRIPPED" '{hookSpecificOutput: {hookEventName: "MessageDisplay", displayContent: $d}}'
exit 0

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for notify-tag-strip.sh: jq-absent fail-open, a delta with no tag producing NO output
# (original renders unchanged), both valid tags being replaced with their ANSI-coloured badge (raw
# operator: text never leaking through, an ESC byte present, the right colour code for each tag), a
# delta that is ONLY the tag collapsing to JUST the badge, a replacement being logged with a [sid=],
# the pre-jq fast-bail never breaking a real match, the two hand-back tags (run|kind:policy and
# run|kind:oneoff) each getting their own badge with the command line below intact, and the kill
# switch standing it down.
set -u
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP notify-tag-strip: jq absent (hook fails open by design)"; exit 0; }

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
fail() { printf 'FAIL: %s\n' "$1"; rm -rf "$T"; exit 1; }
trap 'rm -rf "$T"' EXIT
# Run from a SANDBOX kit copy (hook, kit-gate.sh pointed at an empty managed dir, options.tsv) with every
# kit-gate input cleared, so the live kit's state and the user's real options cannot reach this check.
mkdir -p "$T/kit/scripts" "$T/kit/install" "$T/managed"
cp "$SRC_DIR/notify-tag-strip.sh" "$T/kit/scripts/" || fail "cannot copy hook into sandbox"
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$SRC_DIR/kit-gate.sh" > "$T/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$T/kit/scripts/kit-gate.sh" || fail "_kg_managed not rewritten"
cp "$SRC_DIR/../install/options.tsv" "$T/kit/install/"
H="$T/kit/scripts/notify-tag-strip.sh"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset AGENT_TIERS_BADGE_GLYPHS  # an operator's own setting would flip the default-mode assertions
export AGENT_TIERS_GUARDS_LOG="$T/guards.log"
export CLAUDE_CONFIG_DIR="$T/cfg"
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state"

run() { jq -cn --arg d "$1" '{hook_event_name:"MessageDisplay", delta:$d}' | sh "$H"; }

[ -z "$(run 'Plain text, no tag here.')" ] || fail "a delta with no tag should produce no output at all"

OUT="$(run "$(printf 'The plan is ready.\noperator:want_input\n')")"
printf '%s' "$OUT" | grep -q 'operator:' && fail "want_input tag leaked into displayContent"
printf '%s' "$OUT" | grep -q 'The plan is ready' || fail "surrounding text should survive the badge substitution"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -q 'INPUT NEEDED' || fail "want_input should be replaced with the INPUT NEEDED badge"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -qF "$(printf '\033[1;38;5;208m')" || fail "want_input's badge should carry the 256-colour orange SGR code, ESC byte included"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -qF "$(printf '\357\201\261')" && fail "the default badge must not carry a nerd-font glyph (renders as a box without that font)"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -qF '[[ ! INPUT NEEDED ]]' || fail "the default want_input badge should be the plain ASCII form"
OUT="$(AGENT_TIERS_BADGE_GLYPHS=nerd run "$(printf 'The plan is ready.\noperator:want_input\n')")"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -qF "$(printf '\357\201\261')" || fail "AGENT_TIERS_BADGE_GLYPHS=nerd should put the warning-triangle glyph in the want_input badge"

OUT="$(run "$(printf 'Waiting.\noperator:no_input_required|reason:background build\n')")"
printf '%s' "$OUT" | grep -q 'operator:' && fail "no_input_required tag leaked into displayContent"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -q 'NO INPUT NEEDED' || fail "no_input_required should be replaced with the NO INPUT NEEDED badge"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -qF "$(printf '\033[1;32m')" || fail "no_input_required's badge should carry the green SGR code, ESC byte included"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -qF "$(printf '\357\200\214')" && fail "the default no_input_required badge must not carry a nerd-font glyph"
OUT="$(AGENT_TIERS_BADGE_GLYPHS=nerd run "$(printf 'Waiting.\noperator:no_input_required|reason:background build\n')")"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -qF "$(printf '\357\200\214')" || fail "AGENT_TIERS_BADGE_GLYPHS=nerd should put the check glyph in the no_input_required badge"

# NO_COLOR: non-empty -> badge text kept, no ESC byte in any of the three badges; set-but-empty -> colour stays
for tag in want_input 'no_input_required|reason:bg' ask_next; do
  D="$(printf 'x\noperator:%s\n' "$tag")"
  OUT="$(NO_COLOR=1 run "$D" | jq -r '.hookSpecificOutput.displayContent')"
  printf '%s' "$OUT" | grep -q 'operator:' && fail "NO_COLOR=1: raw $tag tag leaked"
  printf '%s' "$OUT" | grep -q '\[\[ ' || fail "NO_COLOR=1: $tag badge text should stay"
  printf '%s' "$OUT" | grep -qF "$(printf '\033')" && fail "NO_COLOR=1: $tag badge must carry no ESC byte"
  OUT="$(NO_COLOR= run "$D" | jq -r '.hookSpecificOutput.displayContent')"
  printf '%s' "$OUT" | grep -qF "$(printf '\033')" || fail "NO_COLOR= (empty): $tag badge should keep its colour"
done

OUT="$(run "$(printf 'Three options.\noperator:ask_next\n')")"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -q 'QUESTION NEXT' || fail "ask_next should be replaced with the QUESTION NEXT badge"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -q 'operator:ask_next' && fail "the raw ask_next line must not survive"

# Hand-back tags: each kind gets its own badge and colour, the command line below survives untouched,
# and an unknown kind is left alone (it renders as plain text, never as a wrong badge).
OUT="$(run "$(printf 'Run this.\noperator:run|kind:policy\n! agent-tiers allow x\nDone.\n')" | jq -r '.hookSpecificOutput.displayContent')"
printf '%s' "$OUT" | grep -q 'operator:' && fail "run|kind:policy tag leaked into displayContent"
printf '%s' "$OUT" | grep -qF 'YOU RUN: POLICY CHANGE, PERSISTS' || fail "run|kind:policy should be replaced with the POLICY CHANGE badge"
printf '%s' "$OUT" | grep -qF "$(printf '\033[1;31m')" || fail "the policy badge should carry the red SGR code, ESC byte included"
printf '%s' "$OUT" | grep -qxF '! agent-tiers allow x' || fail "the handed-back command line below the policy tag must survive unchanged"
printf '%s' "$OUT" | grep -qF 'ONE-OFF' && fail "a policy tag must not render the one-off badge"
OUT="$(run "$(printf 'Run this.\noperator:run|kind:oneoff\n! ls -la /tmp\n')" | jq -r '.hookSpecificOutput.displayContent')"
printf '%s' "$OUT" | grep -q 'operator:' && fail "run|kind:oneoff tag leaked into displayContent"
printf '%s' "$OUT" | grep -qF 'YOU RUN: ONE-OFF' || fail "run|kind:oneoff should be replaced with the ONE-OFF badge"
printf '%s' "$OUT" | grep -qF "$(printf '\033[1;36m')" || fail "the one-off badge should carry the cyan SGR code, ESC byte included"
printf '%s' "$OUT" | grep -qxF '! ls -la /tmp' || fail "the handed-back command line below the one-off tag must survive unchanged"
printf '%s' "$OUT" | grep -qF 'POLICY CHANGE' && fail "a one-off tag must not render the policy badge"
for k in policy oneoff; do
  OUT="$(NO_COLOR=1 run "$(printf 'x\noperator:run|kind:%s\n' "$k")" | jq -r '.hookSpecificOutput.displayContent')"
  printf '%s' "$OUT" | grep -qF 'YOU RUN: ' || fail "NO_COLOR=1: run|kind:$k badge text should stay"
  printf '%s' "$OUT" | grep -qF "$(printf '\033')" && fail "NO_COLOR=1: run|kind:$k badge must carry no ESC byte"
  OUT="$(NO_COLOR= run "$(printf 'x\noperator:run|kind:%s\n' "$k")" | jq -r '.hookSpecificOutput.displayContent')"
  printf '%s' "$OUT" | grep -qF "$(printf '\033')" || fail "NO_COLOR= (empty): run|kind:$k badge should keep its colour"
done
[ -z "$(run "$(printf 'x\noperator:run|kind:other\n')")" ] || fail "an unknown run kind should produce no output (rendered unchanged, no badge)"
OUT="$(run "$(printf 'x\n  operator:run|kind:policy\n')" | jq -r '.hookSpecificOutput.displayContent')"
printf '%s' "$OUT" | grep -q 'operator:' && fail "an indented run tag leaked into displayContent"
printf '%s' "$OUT" | grep -q '^  .*YOU RUN: POLICY CHANGE' || fail "an indented run tag should be badged with its indentation kept"
OUT="$(run "$(printf '\toperator:run|kind:oneoff\n')" | jq -r '.hookSpecificOutput.displayContent')"
printf '%s' "$OUT" | grep -q 'YOU RUN: ONE-OFF' || fail "a tab-indented run tag should be badged"
[ -z "$(run "$(printf '  operator:want_input\n')")" ] || fail "an indented turn-end tag is still not a tag line"
OUT="$(run "$(printf 'x\noperator:run|kind:oneoff  \n')" | jq -r '.hookSpecificOutput.displayContent')"
printf '%s' "$OUT" | grep -q 'operator:' && fail "a run tag with trailing spaces leaked into displayContent"
printf '%s' "$OUT" | grep -q 'YOU RUN: ONE-OFF' || fail "a run tag with trailing spaces should be badged"
OUT="$(run "$(printf 'x\noperator:run|kind:policy\r\n')" | jq -r '.hookSpecificOutput.displayContent')"
printf '%s' "$OUT" | grep -q 'operator:' && fail "a run tag with a trailing CR leaked into displayContent"
printf '%s' "$OUT" | grep -q 'YOU RUN: POLICY CHANGE' || fail "a run tag with a trailing CR should be badged"
# Anchored at both ends: next to a real tag, a line that only STARTS with a run tag keeps its text.
OUT="$(run "$(printf 'operator:run|kind:oneoffs\noperator:run|kind:policy-x\noperator:want_input\n')" | jq -r '.hookSpecificOutput.displayContent')"
printf '%s' "$OUT" | grep -qxF 'operator:run|kind:oneoffs' || fail "a longer run|kind:oneoff... line must not be partly badged"
printf '%s' "$OUT" | grep -qxF 'operator:run|kind:policy-x' || fail "a longer run|kind:policy... line must not be partly badged"
printf '%s' "$OUT" | grep -qF 'INPUT NEEDED' || fail "the turn-end tag next to those lines should still be badged"
# The realistic final batch: run tag, command, turn-end tag in one delta gets BOTH badges.
OUT="$(run "$(printf 'Run this.\noperator:run|kind:policy\n! agent-tiers allow x\noperator:want_input\n')" | jq -r '.hookSpecificOutput.displayContent')"
printf '%s' "$OUT" | grep -qF 'YOU RUN: POLICY CHANGE' || fail "run tag plus turn-end tag in one batch: the run badge is missing"
printf '%s' "$OUT" | grep -qF 'INPUT NEEDED' || fail "run tag plus turn-end tag in one batch: the turn-end badge is missing"
printf '%s' "$OUT" | grep -q 'operator:' && fail "run tag plus turn-end tag in one batch: a raw tag leaked"

OUT="$(run "operator:want_input")"
printf '%s' "$OUT" | jq -r '.hookSpecificOutput.displayContent' | grep -q 'INPUT NEEDED' \
  || fail "a delta that is only the tag should collapse to just the badge (got: $OUT)"

grep -q 'notify-tag-strip' "$AGENT_TIERS_GUARDS_LOG" 2>/dev/null || fail "a badge substitution should be logged to guards.log"
grep -q '\[sid=\]' "$AGENT_TIERS_GUARDS_LOG" 2>/dev/null || fail "the log line should carry a [sid=] field, same convention as every other guard"

# Kill switch stands the whole hook down.
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off"
touch "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/notify"
[ -z "$(run "$(printf 'Ready.\noperator:want_input')")" ] || fail "the kill switch should stand the hook down entirely"
rm -f "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/notify"

# kit-gate stand-down: with the kit-root marker (distinct from the CLAUDE_CONFIG_DIR one above) the same
# tagged delta produces nothing, exits 0 and logs it; without it the badge comes back.
mkdir -p "$T/kit/.state/off"; : > "$T/kit/.state/off/notify-tag-strip"
out="$(run "$(printf 'Ready.\noperator:want_input')")"; rc=$?
rm -f "$T/kit/.state/off/notify-tag-strip"
[ "$rc" = 0 ] && [ -z "$out" ] || fail "kit-gate stand-down must be silent exit 0 (rc=$rc out=$out)"
grep -qF 'kit-gate standdown notify-tag-strip:' "$AGENT_TIERS_GUARDS_LOG" || fail "kit-gate stand-down must be logged"
[ -n "$(run "$(printf 'Ready.\noperator:want_input')")" ] || fail "the badge must come back once the marker is removed"

echo "PASS notify-tag-strip.sh"

#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Write|Edit|MultiEdit) guard: a live style walkthrough's demo-only CSS must
# not reach the codebase. Candidate CSS shown live on a page has to win a cascade fight, so it carries
# `!important` and demo-only hooks (a red `outline` for visibility, `outline-offset`, a `data-`
# attribute set for the demo). Applying the walkthrough's result to source is a separate, deliberate
# translation step; pasting the demo block in is the failure this catches.
#
# Deny ONLY on the COMBINATION, within the same CSS rule (selector + declaration block, or the same
# bare declaration line if there is no rule wrapper): a line with `!important` AND a walkthrough-only
# hook - an `outline` declaration whose value includes `red`, an `outline-offset` declaration, or a
# `[data-...]` attribute selector introduced alongside it.
#
# Disclosed ceiling: a bare `!important` copied without a demo hook is NOT caught, and cannot be -
# legitimate CSS uses `!important` routinely, and a guard that denied every `!important` would be
# turned off within a day, which is worse than a narrow one that only catches the walkthrough shape.
#
# Scope: only the write TARGET's own extension is checked - `.css`, `.scss`, `.less`, `.sass`. Every
# other file (a JS harness that legitimately embeds a CSS string, this guard's own selfcheck fixture,
# a markdown doc quoting a walkthrough example) exits 0 before any parsing. A kill switch alone would
# be all-or-nothing here; a path scope is the narrower, correct fix.
#
# Disclosed, accepted false positive: a bare `[data-...]` attribute selector paired with `!important`
# denies even when it carries no demo intent at all (`[data-state] { display: none !important; }` is
# ordinary modern CSS). Narrowing the selector match further would need attribute-VALUE awareness a
# regex cannot give reliably; the kill switch is the escape hatch for a real stylesheet that trips it.
#
# Kill switch checked before any side effect: .state/off/demo-css-guard, resolved from KIT_ROOT (the
# script's own location), never from CLAUDE_CONFIG_DIR - the kill switch lives in the kit's own
# .state and is shared across every Claude profile pointed at this kit; only the flattened view
# follows CLAUDE_CONFIG_DIR. Fail-open on every tooling gap (no jq) with a breadcrumb. Never exits 2;
# a deny is the exemplar's hookSpecificOutput JSON with permissionDecision "deny".
# Self-check: demo-css-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s demo-css-guard %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

[ -f "${BASE:-}/.state/off/demo-css-guard" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
case "$FILE_PATH" in
  *.css|*.scss|*.less|*.sass) ;;
  *) exit 0 ;;
esac

case "$TOOL" in
  Write) CONTENT="$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || true)" ;;
  Edit) CONTENT="$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || true)" ;;
  MultiEdit) CONTENT="$(printf '%s' "$INPUT" | jq -r '[(.tool_input.edits // [])[].new_string // ""] | join("\n")' 2>/dev/null || true)" ;;
  *) exit 0 ;;
esac
[ -n "$CONTENT" ] || exit 0

# One CSS rule at a time (RS="}" splits on the declaration-block close, so a bare selector-less
# declaration list - no braces at all - falls out as a single record covering the whole content).
HIT="$(printf '%s' "$CONTENT" | awk '
  BEGIN { RS = "}"; found = 0 }
  {
    if ($0 ~ /!important/) {
      if ($0 ~ /outline[^;]*red/ || $0 ~ /outline-offset/ || $0 ~ /\[data-[A-Za-z0-9_-]+\]/) {
        found = 1
      }
    }
  }
  END { print found }
' 2>/dev/null || true)"

[ "$HIT" = "1" ] || exit 0

REASON="agent-tiers demo-css-guard: this write pastes live-walkthrough demo CSS (an !important paired with a red outline, an outline-offset, or a demo data- attribute selector) straight into source. Strip the demo-only hooks - the !important, the red outline, the demo data- attribute, any transition added only so the change could be watched - before applying the walkthrough's result to source, then retry. Kill switch: .state/off/demo-css-guard, if this fires on real CSS that legitimately needs those declarations."
note "deny: demo-css shape detected in write to $(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // "?"' 2>/dev/null)"
jq -n --arg r "$REASON" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0

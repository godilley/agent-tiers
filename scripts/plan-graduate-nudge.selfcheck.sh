#!/usr/bin/env sh
# kit-scope: shared
# Self-check for plan-graduate-nudge.sh. Runnable: `sh plan-graduate-nudge.selfcheck.sh`.
set -u
HERE="$(CDPATH= cd "$(dirname "$0")" && pwd)"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent"; exit 0; }

# Run from a SANDBOX kit copy with a temp config dir and guards log, and every kit-gate input cleared,
# so neither the live kit's state nor the user's real options can reach this check.
SB="$(mktemp -d)" || { echo "SELF-CHECK FAILED: mktemp"; exit 1; }
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/kit/scripts" "$SB/kit/install" "$SB/cfg" "$SB/managed"
cp "$HERE/plan-graduate-nudge.sh" "$SB/kit/scripts/"
sed "s|^_kg_managed=.*|_kg_managed='$SB/managed'|" "$HERE/kit-gate.sh" > "$SB/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$SB/managed'" "$SB/kit/scripts/kit-gate.sh" || { echo "SELF-CHECK FAILED: _kg_managed not rewritten"; exit 1; }
cp "$HERE/../install/options.tsv" "$SB/kit/install/"
HOOK="$SB/kit/scripts/plan-graduate-nudge.sh"
SBLOG="$SB/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG" CLAUDE_CONFIG_DIR="$SB/cfg"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done

# A real approved-plan payload, shaped exactly as Step 0's live probe captured it: tool_input is
# EMPTY, the path lives at tool_response.filePath.
PLAN_PATH="$HOME/.claude/plans/some-random-name.md"
payload="$(jq -n --arg p "$PLAN_PATH" '{
  hook_event_name: "PostToolUse", tool_name: "ExitPlanMode", tool_input: {},
  tool_response: {plan: "some plan text", isAgent: false, filePath: $p}
}')"

out="$(printf '%s' "$payload" | sh "$HOOK")"; rc=$?
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"

[ "$rc" -eq 0 ] && ok "exits 0 on the happy path" || bad "happy path exited nonzero: $rc"
[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" = "PostToolUse" ] \
  && ok "emits a PostToolUse additionalContext payload" || bad "did not emit a well-formed PostToolUse payload: $out"
# The whole design rests on this hook being advisory-only, incapable of blocking anything - lock
# it as an assertion, not just a claim in the header comment (opus reviewer, R4).
for field in '.decision' '.permissionDecision' '.hookSpecificOutput.permissionDecision'; do
  [ "$(printf '%s' "$out" | jq -r "$field // \"null\"" 2>/dev/null)" = "null" ] \
    || bad "advisory-only hook must never set $field, got: $out"
done
ok "never sets a decision/permissionDecision field (advisory-only, cannot block)"
printf '%s' "$ctx" | grep -qF "$PLAN_PATH" && ok "names the exact approved plan's filePath" \
  || bad "did not name the plan path: $ctx"
if printf '%s' "$ctx" | grep -qF "notes-sync.sh" && printf '%s' "$ctx" | grep -qF "bash " \
  && printf '%s' "$ctx" | grep -qF -- "--from \"$PLAN_PATH\""; then
  ok "carries a syntactically valid, runnable bash \"<dir>/notes-sync.sh\" new ... --from \"...\" command"
else
  bad "the suggested command is not syntactically valid/runnable: $ctx"
fi

# Fail-open: no tool_response.filePath at all (e.g. some other PostToolUse shape) -> silent, no output
empty_payload='{"hook_event_name":"PostToolUse","tool_name":"ExitPlanMode","tool_input":{},"tool_response":{}}'
out="$(printf '%s' "$empty_payload" | sh "$HOOK")"
[ -z "$out" ] && ok "silent (no output) when tool_response.filePath is absent" \
  || bad "should be silent with no filePath, got: $out"

# Fail-open: unparseable JSON on stdin -> silent, exit 0, never crashes the tool call it's attached to
out="$(printf 'not json at all' | sh "$HOOK")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && ok "fails open (silent, exit 0) on unparseable stdin" \
  || bad "did not fail open on garbage stdin (rc=$rc): $out"

# kit-gate stand-down: marker present -> no output, exit 0, log line; marker removed -> emits again.
mkdir -p "$SB/kit/.state/off"; : > "$SB/kit/.state/off/plan-graduate-nudge"
out="$(printf '%s' "$payload" | sh "$HOOK" 2>/dev/null)"; rc=$?
rm -f "$SB/kit/.state/off/plan-graduate-nudge"
[ -z "$out" ] && [ "$rc" -eq 0 ] && grep -qF "kit-gate standdown plan-graduate-nudge:" "$SBLOG" \
  && ok "stands down (silent, exit 0, logged) when the kit-gate marker exists" \
  || bad "did not stand down with the off marker (rc=$rc): $out"
[ -n "$(printf '%s' "$payload" | sh "$HOOK" 2>/dev/null)" ] && ok "emits again once the marker is removed" \
  || bad "still silent after the marker was removed"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

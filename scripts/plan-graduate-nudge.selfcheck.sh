#!/usr/bin/env sh
# kit-scope: shared
# Self-check for plan-graduate-nudge.sh. Runnable: `sh plan-graduate-nudge.selfcheck.sh`.
set -u
HERE="$(CDPATH= cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/plan-graduate-nudge.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent"; exit 0; }

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

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

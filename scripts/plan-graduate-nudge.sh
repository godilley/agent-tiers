#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PostToolUse(ExitPlanMode) nudge: graduate a just-approved plan-mode plan into the
# project's notes dir, tied to the actual arrival event instead of a skill paragraph someone has
# to remember to read (this project's own memory: a passive mention alone does not reliably fire -
# rules-need-arrival-events.md). Consent row - install-flat.sh --with-plan-graduate-nudge.
#
# ~/.claude/plans/<random-name>.md is Claude Code's own working slot for the CURRENT plan-mode
# plan - notes-sync.sh never touches it, and it is not necessarily safe across a second
# EnterPlanMode later in the same session.
#
# Step 0 payload probe (2026-08-29, real EnterPlanMode/ExitPlanMode round trips in a live session):
#   - APPROVED: PostToolUse fires. `tool_input` is EMPTY (`{}`) - the plan path is NOT there, it is
#     `tool_response.filePath` (the plan's own draft-time guess of `tool_input.planFilePath` was
#     wrong - caught exactly because this step ran before any detection logic was written).
#   - REJECTED (the harness has no bare "reject" button - decline routes through "request
#     changes"): the tool call itself is refused before it runs. PostToolUse NEVER FIRES. Confirmed
#     live: two real round trips in one probe session produced exactly one captured payload.
#   Conclusion: no field-based approval check is possible OR needed - a PostToolUse event for this
#   hook can only ever exist for an APPROVED plan. The "word it harmlessly for a rejected plan"
#   fallback this step was designed to justify is moot, not merely unbuilt.
#
# Fail-open on every tooling gap (no jq, unparseable payload, empty path) - never blocks, only adds
# context after the tool already ran. Same shape as authorship-record.sh, this kit's only other
# PostToolUse additionalContext emitter (read before writing this one), including its fail-open
# tail's breadcrumb (opus reviewer, R4: claiming that shape without the breadcrumb itself would
# leave a jq-less or shape-changed host silently producing zero nudges with zero signal).
#
# Self-check: plan-graduate-nudge.selfcheck.sh
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s plan-graduate-nudge fail-open: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "jq missing - cannot parse payload"; exit 0; }

PLAN_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_response.filePath // empty' 2>/dev/null || true)"
[ -n "$PLAN_PATH" ] || { note "no tool_response.filePath in payload"; exit 0; }

# The suggested command must be RUNNABLE, not just describe the idea: notes-sync.sh is bash (its
# own selfcheck says so explicitly), not on PATH, and not sh - every other call site in this kit
# invokes it as `bash "<dir>/notes-sync.sh"` (opus reviewer, R4: a bare `notes-sync.sh` in the
# nudge gets "command not found" at exactly the moment the nudge fires, training the Lead to
# ignore it). $PLAN_PATH is quoted in the suggested command: real plan names are derived from the
# session's own prompt text, not purely random, so it is project/session-controlled, not a literal
# constant.
NS="${BASE:-.}/scripts/notes-sync.sh"
CTX="agent-tiers: a plan-mode plan was just written to $PLAN_PATH (the header on this hook explains why that implies approval - PostToolUse cannot fire on a rejected plan). Graduate it into the notes dir now with \`bash \"$NS\" new <descriptive-slug> --from \"$PLAN_PATH\"\` (pick a slug describing the plan's actual subject, not the harness's random plan-file name) before any further work in this plan-mode session risks the plan slot being reused/overwritten. Note: this fires in whatever repo the current session's cwd is in - if that repo has no notes-dir seam yet, \`new\` creates the dir and its exclude entry, but does not register it for \`/agent-tiers:doctor\` - run \`notes-sync.sh setup\` too if this repo doesn't have the seam yet."
jq -n --arg c "$CTX" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}' 2>/dev/null || true
exit 0

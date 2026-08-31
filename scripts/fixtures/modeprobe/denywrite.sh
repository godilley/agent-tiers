#!/usr/bin/env sh
# kit-scope: local
in="$(cat)"
c="$(printf '%s' "$in" | jq -r '.tool_input.content // .tool_input.new_string // ""')"
case "$c" in *AKIA*) printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"DENYPROBE: key-shaped content"}}\n' ;; esac
exit 0

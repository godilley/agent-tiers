#!/usr/bin/env sh
# kit-scope: local
c="$(jq -r '.tool_input.command // ""')"
case "$c" in *ASKPROBE*) printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"ask probe reason"}}\n' ;; esac
exit 0

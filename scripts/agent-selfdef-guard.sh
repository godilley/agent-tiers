#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Write|Edit|MultiEdit) guard: a sub-agent must never edit its own definition
# file. An agent rewriting the file that defines it changes its own constraints mid-run, and the
# change is invisible to the session that spawned it - the Lead owns agent definitions, so a
# definition change is a gated edit with a version bump, made by the Lead, never by the tier it
# governs.
#
# Scope: the kit's definitions are `$KIT_ROOT/agents/<type>.md`; a flat install may expose them as
# `$CLAUDE_CONFIG_DIR/agents/<type>.md` (defaulting to `~/.claude/agents/<type>.md`), and a project may
# carry its own `$CLAUDE_PROJECT_DIR/.claude/agents/<type>.md`. All three are candidates, matched by
# BASENAME against the caller's agent type - `install-flat.sh`'s `link_or_copy` falls back to `cp -R`
# on a host without symlink support, so the flat copy is not reliably the SAME FILE as the kit's; a
# real-path comparison alone would silently miss it there. Each candidate's write TARGET is still
# resolved with `readlink -f` (falling back to the raw path if unavailable) first, so a symlinked flat
# install is still caught by real-path equality where that holds; the basename match is what covers
# the `cp -R` and project-scope cases where it does not. Tiers are enumerated from `$KIT_ROOT/agents/*.md`
# rather than a hard-coded name list, so a newly added tier is covered with no edit here.
#
# Caller identity comes from guard-cmdpos.sh's guard_caller_agent (never re-derived here) - empty
# means the Lead, which owns every definition and is never denied.
#
# What this CANNOT catch, disclosed rather than hidden: a definition edited through a Bash command
# (`sed -i`, `tee`, a plain `>` redirect) never reaches a Write|Edit|MultiEdit matcher, so this guard
# does not cover that path. sc52a-write-disclosure-guard.sh's own disclosure of the same class of gap
# applies here too - no shell parser sits behind this hook.
#
# Fail-open on any tooling gap (no jq, no readable payload, no guard-cmdpos.sh, no agents/ directory),
# each with a breadcrumb - a silent fail-open is the failure this kit's guards exist to close.
# Self-check: agent-selfdef-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s agent-selfdef-guard %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

# Kill switch: .state/off/agent-selfdef-guard, resolved from KIT_ROOT (the script's own location),
# never from CLAUDE_CONFIG_DIR - the kill switch lives in the kit's own .state and is shared across
# every Claude profile pointed at this kit; only the flattened view follows CLAUDE_CONFIG_DIR.
[ -f "${BASE:-}/.state/off/agent-selfdef-guard" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }

TARGET="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -n "$TARGET" ] || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
[ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ] \
  || { note "fail-open: guard-cmdpos.sh missing - cannot resolve the caller agent"; exit 0; }
. "$SELFDIR/guard-cmdpos.sh"
command -v guard_caller_agent >/dev/null 2>&1 \
  || { note "fail-open: guard-cmdpos.sh sourced but guard_caller_agent undefined (stale library?)"; exit 0; }

AGENT_TYPE="$(guard_caller_agent "$INPUT")"
[ -n "$AGENT_TYPE" ] || exit 0   # the Lead owns every definition file

# KIT_ROOT: the script's own location by default. AGENT_TIERS_KIT_ROOT is a FIXTURE-ONLY override -
# the selfcheck points it at a sandboxed agents/ directory rather than ever touching the real kit tree.
KIT_ROOT="${AGENT_TIERS_KIT_ROOT:-$BASE}"
AGENTS_DIR="$KIT_ROOT/agents"
[ -d "$AGENTS_DIR" ] || { note "fail-open: $AGENTS_DIR missing - cannot resolve tier definitions"; exit 0; }

resolve() {  # $1 = path -> readlink -f, falling back to the raw path
  if command -v readlink >/dev/null 2>&1; then
    r="$(readlink -f "$1" 2>/dev/null || true)"
    [ -n "$r" ] && { printf '%s\n' "$r"; return 0; }
  fi
  printf '%s\n' "$1"
}

TARGET_RESOLVED="$(resolve "$TARGET")"

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"

deny_selfdef() {
  REASON="agent-tiers: do not edit your own definition file ($TARGET). Definition changes are gated edits the Lead makes, with a version bump, never the tier they govern. Describe the change you want in your return and let the Lead make it."
  note "deny: $AGENT_TYPE tried to write its own definition $TARGET [sid=$SESSION_ID]"
  jq -n --arg r "$REASON" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

for def in "$AGENTS_DIR"/*.md; do
  [ -e "$def" ] || continue
  tier="$(basename "$def" .md)"
  [ "$tier" = "$AGENT_TYPE" ] || continue
  DEF_RESOLVED="$(resolve "$def")"
  [ "$DEF_RESOLVED" = "$TARGET_RESOLVED" ] && deny_selfdef
  break
done

# Basename-matched candidates: a flat-install copy (install-flat.sh's link_or_copy falls back to
# `cp -R` where symlinks are unsupported, so the real-path check above misses it there) and a
# project-scope definition. Matched by directory identity + exact basename, not by file content -
# these are not necessarily the same real file as the kit copy.
if [ "$(basename "$TARGET")" = "$AGENT_TYPE.md" ]; then
  TARGET_DIR_RESOLVED="$(resolve "$(dirname "$TARGET")")"

  CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  CONFIG_AGENTS_DIR="${CONFIG_DIR%/}/agents"
  [ "$(resolve "$CONFIG_AGENTS_DIR")" = "$TARGET_DIR_RESOLVED" ] && deny_selfdef

  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    PROJECT_AGENTS_DIR="${CLAUDE_PROJECT_DIR%/}/.claude/agents"
    [ "$(resolve "$PROJECT_AGENTS_DIR")" = "$TARGET_DIR_RESOLVED" ] && deny_selfdef
  fi
fi

exit 0

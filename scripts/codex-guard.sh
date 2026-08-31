#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: XLAB-5 made mechanical - NO bare `codex` from a Claude session.
#
# The kit's own incident log (XLAB-14) records the prose ban being violated minutes after it was made
# ("luck, not design"), so this converts it to a deny at the call site. ANY command-position `codex`
# is denied - including login/version probes - with the fix in the reason: route through
# scripts/codex-run.sh (the sanctioned wrapper; probes pass through unscanned, `exec` hard-fails on a
# secrets hit). The wrapper's filename deliberately does not match bare `codex`, so wrapped calls pass
# this guard untouched; human terminal use is unaffected (hooks fire only in Claude's Bash tool).
#
# FAIL-CLOSED class (SC-5.3), unlike the kit's fail-open guards: if jq is missing the payload cannot
# be parsed precisely, so any Bash payload CONTAINING the word codex is denied (crude, stated in the
# reason) rather than allowed. Anti-accident, not anti-adversary: `env`/`xargs`/`sh -c` indirection is
# not chased - the audience is a Lead slipping into old habit, not a hostile agent. NOT auto-wired:
# consent row, `install-flat.sh --with-codex-guard`. Selfcheck: codex-guard.selfcheck.sh.
set -u
# CLAUDE_PLUGIN_ROOT is not reliably set for a hook's own shell (only baked into flat-installed
# commands/*.md); resolve the kit root from THIS script's own location instead, same as lint-doctrine.sh.
KIT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd)"

LOG="${AGENT_TIERS_GUARDS_LOG:-${KIT_ROOT:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
SID=""
# Decision line (Wave D, 2026-08-16): guards.log is THE durable human record of blocks (HOST-4 - under
# cc-gui / -p nobody sees a deny), so every deny/ask logs `<ts> <guard> deny|ask: <text> [sid=<id>]`;
# the SessionEnd summary and doctor count these lines by session id.
logdec() { # $1 = "deny: ..." | "ask: ..."   (sid parsed HERE, lazily; empty on the jq-less path)
  command -v jq >/dev/null 2>&1 && SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s codex-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
deny() { # $1 = reason. jq path emits the JSON decision; the jq-less path uses the rc-2 stderr protocol.
  logdec "deny: $(printf '%s' "$1" | cut -c1-140)"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
  printf '%s\n' "$1" >&2
  exit 2
}

INPUT="$(cat 2>/dev/null || true)"
FIX="Bare codex invocations are banned in Claude sessions (XLAB-5): a direct call skips the egress preflight and isolation discipline. Re-run via the sanctioned wrapper: replace 'codex' with '$KIT_ROOT/scripts/codex-run.sh' (same argv - probes pass through, exec gets a hard-fail secrets scan). One codex call per Bash command."

if ! command -v jq >/dev/null 2>&1; then
  case "$INPUT" in
    # NOTE: no wrapper advice here. Without jq the test is a substring match, so the wrapper's own path
    # (scripts/codex-run.sh) contains "codex" and is denied too - recommending it would be a loop.
    # Installing jq is the only remedy that restores command-position precision.
    *codex*) deny "jq is missing, so this guard cannot parse the command precisely - it is failing CLOSED on any Bash payload mentioning codex, INCLUDING the codex-run.sh wrapper. Install jq to restore precise command-position matching; until then no codex path can be reached from a Claude session. (Ban rationale, XLAB-5: a direct call skips the egress preflight and isolation discipline.)" ;;
  esac
  exit 0
fi

CMDSTR="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
if [ -z "$CMDSTR" ]; then
  # Unparseable/empty payload: this guard's class is fail-CLOSED, so mirror the jq-less path rather
  # than silently allowing (cross-lab finding 7).
  case "$INPUT" in
    *codex*) deny "The Bash payload could not be parsed but mentions codex - failing CLOSED. $FIX" ;;
  esac
  exit 0
fi
# Command-position codex: line start or after ; & | ( { $( ` - optionally behind a bare launcher, then
# codex as a whole word (followed by space, end of line, or a terminator like ; & | )).
# The launcher list is every prefix that still leaves codex in command position AND is plain habit:
# command/exec/nohup/sudo/time. It stops there deliberately - env/xargs/sh -c REWRITE the command and
# chasing them is anti-adversary work this guard does not claim (see header).
# Mentions inside strings/args (rg codex, echo codex, paths like codex-home-isolate.sh, and the
# wrapper's own codex-run.sh) do not match; a QUOTED string containing '&& codex ' does false-positive
# (known ceiling - split the command; the deny reason self-corrects).
if printf '%s\n' "$CMDSTR" | grep -Eq '(^|[;&|({]|\$\(|`)[[:space:]]*((command|exec|nohup|sudo|time)[[:space:]]+)?codex([[:space:];&|)]|$)'; then
  deny "$FIX"
fi
exit 0

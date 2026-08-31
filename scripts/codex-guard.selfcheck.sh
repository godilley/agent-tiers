#!/usr/bin/env sh
# kit-scope: shared
# Self-check for codex-guard.sh: synthetic PreToolUse(Bash) payloads; assert the deny fires ONLY for
# command-position bare `codex` and the wrapper/mentions pass. Exits non-zero on first failure.
set -u
GUARD="$(dirname "$0")/codex-guard.sh"
# decision/breadcrumb lines go to a SANDBOX log, never the real kit's .state/guards.log (opus reviewer, Wave D:
# in-place selfchecks had filled the live record with fixture noise)
SBLOG="$(mktemp -d)/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails CLOSED by design without it)"; exit 0; }

run() { # $1 = the Bash command string; echo DENY or ALLOW
  p="$(jq -n --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}')"
  out="$(printf '%s' "$p" | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then echo DENY; else echo ALLOW; fi
}

[ "$(run 'codex exec -s read-only -C /tmp/x --json -o /tmp/o -')" = DENY  ] || fail "bare codex exec should DENY"
[ "$(run 'codex login status')" = DENY  ] || fail "bare codex login should DENY (probes route via the wrapper too)"
[ "$(run 'cd /tmp && codex exec -')" = DENY  ] || fail "codex after && should DENY"
[ "$(run 'true; codex --version')" = DENY  ] || fail "codex after ; should DENY"
[ "$(run 'rg -n "codex exec" agents/codex-read.md')" = ALLOW ] || fail "mention inside args should ALLOW"
[ "$(run 'echo codex')" = ALLOW ] || fail "codex as an argument should ALLOW"
[ "$(run 'sh "$HOME/.claude/agent-tiers/scripts/codex-home-isolate.sh"')" = ALLOW ] || fail "codex-* script paths should ALLOW"
[ "$(run '"$HOME/.claude/agent-tiers/scripts/codex-run.sh" exec -s read-only -C /tmp/x -')" = ALLOW ] || fail "the wrapper should ALLOW"
[ "$(run 'ls -la')" = ALLOW ] || fail "unrelated command should ALLOW"
[ "$(run 'command codex exec -')" = DENY ] || fail "'command codex' launcher should DENY"
[ "$(run 'exec codex exec -')" = DENY ] || fail "'exec codex' launcher should DENY"
[ "$(run 'nohup codex exec - &')" = DENY ] || fail "'nohup codex' launcher should DENY"
[ "$(run 'sudo codex exec -')" = DENY ] || fail "'sudo codex' launcher should DENY"
[ "$(run 'time codex exec -')" = DENY ] || fail "'time codex' launcher should DENY"
[ "$(run '{ codex exec -; }')" = DENY ] || fail "codex opening a brace group should DENY"
[ "$(run 'codex&')" = DENY ] || fail "codex terminated by & (no space) should DENY"
[ "$(run 'true && (codex --version)')" = DENY ] || fail "codex in a subshell should DENY"
# The launcher list must not turn into a substring match: these are different commands.
[ "$(run 'sudocodex exec')" = ALLOW ] || fail "sudocodex is not sudo+codex"
[ "$(run 'mytime codex-run.sh')" = ALLOW ] || fail "a codex-* path behind another word should ALLOW"

# Malformed (non-JSON) payloads: fail CLOSED when codex is mentioned, open otherwise.
raw() { out="$(printf '%s' "$1" | sh "$GUARD" 2>/dev/null || true)"; if printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then echo DENY; else echo ALLOW; fi; }
[ "$(raw 'not json but mentions codex here')" = DENY  ] || fail "unparseable payload mentioning codex should DENY (fail-closed)"
[ "$(raw 'not json, nothing relevant')"       = ALLOW ] || fail "unparseable payload without codex should ALLOW"

# Wave D: a deny writes a decision line with the sid
jq -n '{tool_name:"Bash", session_id:"sess-cg", tool_input:{command:"codex exec hello"}}' | sh "$GUARD" >/dev/null 2>&1 || true
grep -aqE '^[^ ]+ codex-guard deny: .*\[sid=sess-cg\]$' "$SBLOG" || fail "no decision line in sandbox log"
echo "OK codex-guard: deny fires only for command-position bare codex; decision line logged with sid"

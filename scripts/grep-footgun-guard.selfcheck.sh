#!/usr/bin/env sh
# kit-scope: shared
# Self-check for grep-footgun-guard.sh. Runnable: `sh grep-footgun-guard.selfcheck.sh`.
# Feeds a fake PreToolUse payload per case; asserts deny fires only on recursive grep w/o -a/--text.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
GUARD="$DIR/grep-footgun-guard.sh"
# decision/breadcrumb lines go to a SANDBOX log, never the real kit's .state/guards.log (opus reviewer, Wave D:
# in-place selfchecks had filled the live record with fixture noise)
SBLOG="$(mktemp -d)/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG"
fail=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

# denied? -> guard emitted a permissionDecision:deny for this command.
check() {
  want="$1"; cmd="$2"
  out="$(printf '%s' "$cmd" | jq -R '{tool_input: {command: .}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}

# should DENY: recursive grep, no text flag
check deny  'command grep -rn "isThinking" /path/to/project'
check deny  'grep -R "pattern" src/'
check deny  '/usr/bin/grep -rn foo .'
check deny  'egrep -r "a|b" dir'

# should ALLOW: neutralized, non-recursive, rg/ag, git grep, piped
check allow 'grep -rna "isThinking" /path/to/project'
check allow 'grep -r --text foo dir'
check allow 'grep -n "foo" single_file.txt'
check allow 'rg -n "foo" src/'
check allow 'ag "foo" src/'
check allow 'git grep -n "foo"'
check allow 'echo hello | grep ell'                 # non-recursive pipe: reads stdin, safe
check allow 'ls -R | grep foo'                      # -R belongs to ls, not grep
check allow 'rg foo src/ | grep bar'                # grep on rg output (non-recursive) is fine
check deny  'grep -rn foo . | grep bar'             # seg1 is a real recursive footgun
check allow 'echo "run: grep -rn foo ."'            # grep is an echo arg, not run
check allow "$(printf 'cat > s.sh <<EOF\ngrep -rn x .\nEOF')"   # real-newline heredoc body: carved out
check deny  "$(printf 'ls\ngrep -rn foo .')"        # genuine 2nd-line invocation still caught
# Wave D: a deny writes a decision line with the sid
jq -n '{tool_name:"Bash", session_id:"sess-gf", tool_input:{command:"grep -rn foo ."}}' | sh "$GUARD" >/dev/null 2>&1 || true
grep -aqE '^[^ ]+ grep-footgun-guard deny: .*\[sid=sess-gf\]$' "$SBLOG" && printf 'ok   decision line written to guards.log with sid\n' || { printf 'FAIL no decision line in sandbox log\n'; fail=1; }

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

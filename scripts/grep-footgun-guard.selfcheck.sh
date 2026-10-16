#!/usr/bin/env sh
# kit-scope: shared
# Self-check for grep-footgun-guard.sh. Runnable: `sh grep-footgun-guard.selfcheck.sh`.
# Feeds a fake PreToolUse payload per case; asserts deny fires only on recursive grep w/o -a/--text.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
# Run from a SANDBOX kit copy with a temp config dir and guards log, never the real kit's .state/
# (in-place selfchecks once filled the live record with fixture noise), and with every
# kit-gate input cleared so the user's own options cannot stand the guard down mid-check.
SB="$(mktemp -d)" || { echo "SELF-CHECK FAILED: mktemp"; exit 1; }
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/kit/scripts" "$SB/kit/install" "$SB/cfg" "$SB/managed"
cp "$DIR/grep-footgun-guard.sh" "$DIR/guard-cmdpos.sh" "$SB/kit/scripts/"
# Managed settings dir pointed at an empty temp dir, so a machine's real one cannot change the result.
sed "s|^_kg_managed=.*|_kg_managed='$SB/managed'|" "$DIR/kit-gate.sh" > "$SB/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$SB/managed'" "$SB/kit/scripts/kit-gate.sh" || { echo "SELF-CHECK FAILED: _kg_managed not rewritten"; exit 1; }
cp "$DIR/../install/options.tsv" "$SB/kit/install/"
GUARD="$SB/kit/scripts/grep-footgun-guard.sh"
SBLOG="$SB/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG" CLAUDE_CONFIG_DIR="$SB/cfg"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
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

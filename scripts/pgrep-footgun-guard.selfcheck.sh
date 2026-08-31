#!/usr/bin/env sh
# kit-scope: shared
# Self-check for pgrep-footgun-guard.sh. Runnable: `sh pgrep-footgun-guard.selfcheck.sh`.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
GUARD="$DIR/pgrep-footgun-guard.sh"
SBLOG="$(mktemp -d)/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG"
fail=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

check() {
  want="$1"; cmd="$2"
  out="$(printf '%s' "$cmd" | jq -R '{tool_input: {command: .}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}

# should DENY: -f/--full in any form, real shapes pulled from live transcripts
check deny  'pgrep -f "batchjob harvest-links" >/dev/null && echo STILL_RUNNING'
check deny  'pgrep -fa "scripts/agent-tiers-share"'
check deny  'until [ -z "$(cat foo 2>/dev/null)" ] && ! pgrep -f "taskid" >/dev/null 2>&1; do sleep 10; done'
check deny  'pgrep --full "X"'
check deny  '/usr/bin/pgrep -f X'
check deny  'command pgrep -f X'

check deny  'if ! pgrep -f X; then echo gone; fi'    # if!-guarded, not just until/while
check deny  '[ -n "$(pgrep -f X)" ]'                 # command substitution
check deny  "$(printf 'ls\npgrep -f X')"             # sibling parity: 2nd-line invocation
check deny  'echo start && pgrep -af X'              # later segment + -af flag order
check deny  'ls | pgrep -f X'                        # behind a pipe
check deny  'pkill -f X'                             # pkill shares the same ancestor-match risk

# should ALLOW: no -f, or pgrep is not the thing actually run
check allow 'pgrep myproc'                          # name-only match, no self-match vector
check allow 'pgrep -l myproc'
check allow 'echo "run: pgrep -f X"'                 # pgrep is an echo arg, not run
check allow "$(printf 'cat > s.sh <<EOF\npgrep -f x\nEOF')"   # heredoc body: carved out
check allow 'pgrep --list-full nginx'                # --full substring must not misfire on --list-full
check allow 'pgrep -F /run/nginx.pid'                # -F/--pidfile must not misfire

# Wave-D-style: a deny writes a decision line with the sid
jq -n '{tool_name:"Bash", session_id:"sess-pg", tool_input:{command:"pgrep -f X"}}' | sh "$GUARD" >/dev/null 2>&1 || true
grep -aqE '^[^ ]+ pgrep-footgun-guard deny: .*\[sid=sess-pg\]$' "$SBLOG" && printf 'ok   decision line written to guards.log with sid\n' || { printf 'FAIL no decision line in sandbox log\n'; fail=1; }

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

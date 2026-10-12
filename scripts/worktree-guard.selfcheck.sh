#!/usr/bin/env sh
# kit-scope: shared
# Self-check for worktree-guard.sh. Runnable: `sh worktree-guard.selfcheck.sh`.
# Feeds a fake PreToolUse payload per case; asserts deny fires only on a non-detached
# `git worktree add`, or a `git worktree remove` of a path under .claude/worktrees/.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
GUARD="$DIR/worktree-guard.sh"
# decision/breadcrumb lines go to a SANDBOX log, never the real kit's .state/guards.log (same
# convention as grep-footgun-guard.selfcheck.sh)
SBLOG="$(mktemp -d)/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG"
fail=0
NL='
'

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

# denied? -> guard emitted a permissionDecision:deny for this command.
check() {
  want="$1"; cmd="$2"
  out="$(printf '%s' "$cmd" | jq -R '{tool_input: {command: .}}' | "${GUARD_SH:-sh}" "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}

# should DENY: attached add, remove of a script-managed worktree
check deny  'git worktree add ../x -b x master'
check deny  'git -C /repo worktree add .claude/worktrees/x -b x'
check deny  'git worktree remove .claude/worktrees/x'
check deny  'git worktree remove --force .claude/worktrees/x'
check deny  'git worktree remove /repo/.claude/worktrees/x'

# should ALLOW: detached add (both --detach and -d), list/prune, worktree.sh itself, mere mentions,
# and removal of a NON-managed (e.g. a throwaway /tmp review) target
check allow 'cd /repo && git worktree add /tmp/y --detach HEAD'
check allow 'git worktree add --detach /tmp/y'
check allow 'git worktree add -d /tmp/y'
check allow 'git worktree list'
check allow 'git worktree prune'
check allow 'sh ~/.claude/agent-tiers/scripts/worktree.sh up x'
check allow 'echo "git worktree add is denied"'
check allow 'git worktree remove /tmp/review-x'
check allow 'git worktree remove /tmp/y'
check allow 'git commit -m "fix: a -> b | c <x@y>"'

# heredoc bodies are stripped, not a stand-down: a heredoc'd commit chained before a real dangerous
# worktree call must not hide it.
HD='git commit -m "$(cat <<'"'"'EOF'"'"''"$NL"'msg'"$NL"'EOF'"$NL"')" && git worktree remove .claude/worktrees/x'
check deny "$HD"

# heredoc BODY containing a dangerous-looking call must NOT trip anything - proves the body is
# actually stripped, not merely that no stand-down happens (the case above only proves the latter,
# since its real target sits outside the body either way; guards-review-2 point 11).
HD_BODY="cat <<'EOF'${NL}git worktree remove .claude/worktrees/x${NL}EOF"
check allow "$HD_BODY"

# quoted content does not force a false --detach match, and does not hide a real one either. A
# discriminating case (guards-review-2 point 11): "-b \"--detach mode\"" does NOT discriminate,
# because the quote character (not whitespace) sits right before --detach either way, so the
# boundary regex never matches it regardless of blanking - "-b \"a --detach mode\"" has a real SPACE
# before --detach inside the quotes, which WOULD satisfy the boundary regex if blanking were removed.
check deny  'git worktree add ../x -b "a --detach mode"'
check allow 'git worktree add ../x --detach -b "some branch"'

# a commit message containing the literal words "git worktree add"/"remove" must never trip this
# guard - the quote-aware split keeps the whole -m string as ONE segment starting with `git commit`,
# which neither fragment matches at command position (guards-review-2, claim 5).
check allow 'git commit -m "docs: WIP; git worktree add x is not a real worktree call"'
check allow 'git commit -m "cleanup && git worktree remove .claude/worktrees/x noted for later"'

# the "SAME invocation" promise: --detach in a DIFFERENT segment must not excuse an add that lacks
# it in its OWN segment (a bare word-grep across the whole command would wrongly pass this).
check deny 'git worktree add ../x -b x && echo --detach'

# a deny writes a decision line with the sid
jq -n '{tool_name:"Bash", session_id:"sess-wt", tool_input:{command:"git worktree remove .claude/worktrees/x"}}' | "${GUARD_SH:-sh}" "$GUARD" >/dev/null 2>&1 || true
grep -aqE '^[^ ]+ worktree-guard deny: .*\[sid=sess-wt\]$' "$SBLOG" && printf 'ok   decision line written to guards.log with sid\n' || { printf 'FAIL no decision line in sandbox log\n'; fail=1; }

# the remove deny names the sanctioned teardown for worktrees whose branch is not the dir name
out="$(printf '%s' 'git worktree remove .claude/worktrees/plan-S14' | jq -R '{tool_input: {command: .}}' | "${GUARD_SH:-sh}" "$GUARD" 2>/dev/null || true)"
printf '%s' "$out" | grep -aq 'whatever its branch' && printf 'ok   remove deny names down for any naming shape\n' \
  || { printf 'FAIL remove deny text lacks the any-naming-shape teardown path\n'; fail=1; }

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

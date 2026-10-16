#!/usr/bin/env sh
# kit-scope: shared
# Self-check for worktree-guard.sh. Runnable: `sh worktree-guard.selfcheck.sh`.
# Feeds a fake PreToolUse payload per case; asserts deny fires only on a non-detached
# `git worktree add`, or a `git worktree remove` of a path under .claude/worktrees/.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
# decision/breadcrumb lines go to a SANDBOX log, never the real kit's .state/guards.log (same
# convention as grep-footgun-guard.selfcheck.sh)
# Run from a SANDBOX kit copy with a temp config dir and guards log, never the real kit's .state/, and
# with every kit-gate input cleared so the user's own options cannot stand the hook down mid-check.
SB="$(mktemp -d)" || { echo "SELF-CHECK FAILED: mktemp"; exit 1; }
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/kit/install" "$SB/cfg" "$SB/managed"
cp -R "$DIR" "$SB/kit/scripts"
# Managed settings dir pointed at an empty temp dir, so a machine's real one cannot change the result.
sed "s|^_kg_managed=.*|_kg_managed='$SB/managed'|" "$DIR/kit-gate.sh" > "$SB/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$SB/managed'" "$SB/kit/scripts/kit-gate.sh" || { echo "SELF-CHECK FAILED: _kg_managed not rewritten"; exit 1; }
cp "$DIR/../install/options.tsv" "$SB/kit/install/"
GUARD="$SB/kit/scripts/worktree-guard.sh"
SBLOG="$SB/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG" CLAUDE_CONFIG_DIR="$SB/cfg"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
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

# kit-gate stand-down: a marker under the sandbox kit's .state/off/ silences the hook (no output, exit 0,
# one guards.log line); the control run without the marker proves the payload does emit.
SD_PAYLOAD="$(jq -n '{tool_name:"Bash", session_id:"sess-sd", tool_input:{command:"git worktree remove .claude/worktrees/x"}}')"
mkdir -p "$SB/kit/.state/off"
sd_ctl="$(printf '%s' "$SD_PAYLOAD" | sh "$GUARD" 2>/dev/null || true)"
: > "$SB/kit/.state/off/worktree-guard"
sd_out="$(printf '%s' "$SD_PAYLOAD" | sh "$GUARD" 2>/dev/null)"; sd_rc=$?
rm -f "$SB/kit/.state/off/worktree-guard"
if [ -n "$sd_ctl" ] && [ -z "$sd_out" ] && [ "$sd_rc" = 0 ] && grep -aq 'kit-gate standdown worktree-guard:' "$SBLOG"; then
  printf 'ok   kill-switch marker stands the hook down (empty stdout, exit 0, log line)\n'
else
  printf 'FAIL kill-switch marker did not stand the hook down\n'; fail=1
fi

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

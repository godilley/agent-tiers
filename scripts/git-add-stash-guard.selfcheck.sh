#!/usr/bin/env sh
# kit-scope: shared
# Self-check for git-add-stash-guard.sh. Runnable: sh git-add-stash-guard.selfcheck.sh
# Feeds a fake PreToolUse payload per case; asserts deny fires only on a blanket git add or a
# git stash subcommand other than list/show/--help.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
GUARD="$DIR/git-add-stash-guard.sh"
SBLOG="$(mktemp -d)/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG"
fail=0
NL='
'

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

check() {
  want="$1"; cmd="$2"
  out="$(printf '%s' "$cmd" | jq -R '{tool_input: {command: .}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}

# should DENY: blanket add
check deny  'git add -A'
check deny  'git add --all'
check deny  'git add .'
check deny  'git add :/'
check deny  'git add -u'
check deny  'git -C /repo add -A'
check deny  'git add ./'
check deny  'git add *'
check deny  'git add -Av'
check deny  'git add -vA'
check deny  'git add -uv'
check deny  'git add "."'
check deny  "git add ':/'"
check deny  '(cd x && git add .)'   # trailing ) must not hide the bare . token
check deny  'git add -A 2>/dev/null'   # a redirect word is not a pathspec (guards-review-2 claim 8)
check deny  'git add -u 2>&1'
check deny  'git add -A >out.log'
check deny  'git add -u <in.txt'

# should DENY: stash, any subcommand but list/show/--help, including bare
check deny  'git stash'
check deny  'git stash pop'
check deny  'git stash apply'
check deny  'git stash drop'
check deny  'git stash push -m x'
check deny  'git stash clear'
# should ALLOW: scoped add, dry-run/renormalize exemptions, list/show/--help stash, dotfile path,
# quoted mentions, bundled non-A/u flags
check allow 'git add addons/mdt/server/events.lua'
check allow 'git add -p addons/mdt/server/events.lua'
check allow 'git add -u addons/mdt/server/events.lua'
check allow 'git add .gitignore'
check allow 'git add -n .'
check allow 'git add --renormalize .'
check allow 'git add -A src/'      # -A/-u are scoped by an explicit pathspec, same as the allowed bare-path case
check allow 'git stash list'
check allow 'git stash show'
check allow 'git stash --help'
check allow 'git -C /repo stash list'
check allow 'echo "git add -A is denied"'
check allow 'git status'
check allow 'git commit -m "fix: a -> b | c <x@y>"'

# a commit message containing the literal words "git add -A"/"git stash" must never trip this guard
# - the quote-aware split keeps the whole -m string as ONE segment starting with `git commit`, which
# neither ADD_FRAG nor STASH_FRAG matches at command position (guards-review-2, claim 5).
check allow 'git commit -m "docs: WIP; git add -A later, and git stash is shared across worktrees"'

# heredoc bodies are stripped, not a stand-down: the incident this guard's header names.
HD="git add -A && git commit -m \"\$(cat <<'EOF'${NL}msg${NL}EOF${NL})\""
check deny "$HD"

# heredoc BODY containing a dangerous-looking call must NOT trip anything - proves the body is
# actually stripped, not merely that no stand-down happens (the case above only proves the latter,
# since its real target sits outside the body either way; guards-review-2 point 11).
HD_BODY="cat <<'EOF'${NL}git add -A${NL}EOF"
check allow "$HD_BODY"

# a deny writes a decision line with the sid
jq -n '{tool_name:"Bash", session_id:"sess-gs", tool_input:{command:"git add -A"}}' | sh "$GUARD" >/dev/null 2>&1 || true
grep -aqE '^[^ ]+ git-add-stash-guard deny: .*\[sid=sess-gs\]$' "$SBLOG" && printf 'ok   decision line written to guards.log with sid\n' || { printf 'FAIL no decision line in sandbox log\n'; fail=1; }

# the trailing-)-hiding-a-real-subcommand fix, confirmed both ways.
check deny '(git stash pop)'
check allow '(git stash list)'

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

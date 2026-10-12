#!/usr/bin/env sh
# kit-scope: shared
# Self-check for long-run-guard.sh. Runnable: sh long-run-guard.selfcheck.sh
# Isolated GIT_CONFIG_GLOBAL + unset GIT_DIR/friends (same convention worktree.selfcheck.sh uses)
# so the fixture repos below (a hook-free repo, a repo with a pre-commit hook, and a repo with a
# relative core.hooksPath committed from a subdirectory) are never confused with any real repo.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_NOSYSTEM

DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
GUARD="$DIR/long-run-guard.sh"
SBLOG="$(mktemp -d)/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG"
fail=0
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

check() {
  want="$1"; cmd="$2"; extra="${3:-.}"
  payload="$(jq -n --arg cmd "$cmd" "{tool_input: ({command: \$cmd} | $extra)}" 2>/dev/null)"
  out="$(printf '%s' "$payload" | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}

# checkcwd: same as check() but the payload also carries a top-level .cwd (what the guard resolves
# a bare git commit's repo from when there is no preceding cd/-C in the command itself).
checkcwd() {
  want="$1"; cmd="$2"; cwd="$3"; extra="${4:-.}"
  payload="$(jq -n --arg cmd "$cmd" --arg cwd "$cwd" "{cwd: \$cwd, tool_input: ({command: \$cmd} | $extra)}" 2>/dev/null)"
  out="$(printf '%s' "$payload" | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s (cwd=%s)\n' "$got" "$cmd" "$cwd"; else
    printf 'FAIL want=%s got=%s : %s (cwd=%s)\n' "$want" "$got" "$cmd" "$cwd"; fail=1; fi
}

# checkbg: payload also carries top-level run_in_background (for the heredoc+run_in_background case).
checkbg() {
  want="$1"; cmd="$2"; extra="${3:-.}"
  payload="$(jq -n --arg cmd "$cmd" "{tool_input: ({command: \$cmd, run_in_background: true} | $extra)}" 2>/dev/null)"
  out="$(printf '%s' "$payload" | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] run_in_background heredoc\n' "$got"; else
    printf 'FAIL want=%s got=%s : run_in_background heredoc\n' "$want" "$got"; fail=1; fi
}

TMO='.timeout=900000'
TMO_LOW='.timeout=120000'
BG_FLAG='.run_in_background=true'
NL='
'

# --- (a) piping: only a real pipe (or |&) denies; redirects to a file, 2>&1/&>, and || never do ---
check deny  'pnpm check | tail' "$TMO"
check deny  'pnpm check | tail -5' "$TMO"
check deny  "pnpm check |& tee log" "$TMO"
check deny  'pnpm build |& tee -a build.log' "$TMO"
# Pinned from the former Rule E of simple-rules-guard (removed 2026-10-01): this guard is the one copy of
# the piped-check rule, so its cases live here.
check deny  'pnpm check 2>&1 | tail -100' "$TMO"
check deny  'pnpm build | grep FAIL' "$TMO"
check deny  'pnpm check --filter mdt | tail -n 50' "$TMO"
check deny  'pnpm --filter mdt-web build | tail -50' "$TMO"
check deny  'pnpm run check | grep FAIL' "$TMO"
# Generic flags before the verb (review 2026-10-01: these four were allowed after Rule E was removed).
check deny  'pnpm -s check | tail' "$TMO"
check deny  'pnpm --silent build | grep x' "$TMO"
check deny  'pnpm --dir web check | tail' "$TMO"
check deny  'pnpm -r --parallel build | tail' "$TMO"
check allow 'pnpm -s check' "$TMO"
check allow 'pnpm check > out.log' "$TMO"
check allow 'pnpm check 2>&1' "$TMO"
check allow 'pnpm check 2>&1; echo "exit:$?"' '.timeout=600000'
check allow 'pnpm check > /tmp/log 2>&1; echo $?' "$TMO"
check allow 'pnpm check &> log' "$TMO"
check allow 'pnpm check || echo FAILED' "$TMO"
check allow 'git commit -m x || git status' "$TMO"
check deny  'git commit -m "x" | cat' "$TMO"

# --- (b) backgrounding: run_in_background field OR a trailing bare & (not &&) ----------------------
check deny  'pnpm check' "$TMO | $BG_FLAG"
check deny  'pnpm check &' "$TMO"
check deny  'nohup pnpm build &' "$TMO"
check deny  'pnpm check &> log &' "$TMO"
check allow 'pnpm check && echo done' "$TMO"

# --- (c) timeout ------------------------------------------------------------------------------------
check deny  'pnpm check' '.'
check deny  'pnpm check' "$TMO_LOW"
check allow 'git commit -m "x"' '.'   # no cwd -> repo unresolved -> (c) skipped for a bare commit

# --- (d) while/until + sleep -------------------------------------------------------------------------
check deny  'until pnpm check; do sleep 5; done' "$TMO"
check deny  'pnpm build; while true; do sleep 2; done' "$TMO"

# --- foreground/unpiped/timed right, other commands, quoted text never trips anything --------------
check allow 'pnpm check' "$TMO"
check allow 'pnpm build' "$TMO"
check allow 'pnpm -r --filter mdt typecheck' "$TMO"
check allow 'pnpm --filter mdt typecheck' "$TMO"
check allow 'git commit -m "x"' "$TMO"
check allow 'pnpm install' "$TMO"
check allow 'git status' "$TMO"
check allow 'echo "run pnpm check later"' "$TMO"
check allow 'git commit -m "fix: a -> b | c <x@y>"' "$TMO"

# --- PNPM_FRAG generalisation: pnpm's own option-skipping, same idea as CMDPOS_GITOPTS -------------
check deny  'pnpm run check' '.'
check deny  'pnpm -w check' '.'
check deny  'pnpm -r build' '.'
check deny  'pnpm --filter X build' '.'
check deny  'pnpm -F X typecheck' '.'
check deny  'cd addons/mdt/web && pnpm typecheck' '.'
check deny  'pnpm build:mdt' '.'
check allow 'pnpm run check' "$TMO"

# --- heredoc bodies are stripped, not a stand-down --------------------------------------------------
HD_COMMIT="git commit -m \"\$(cat <<'EOF'${NL}msg${NL}EOF${NL})\""
check allow "$HD_COMMIT" '.'         # cwd unresolved -> (c) does not apply to a lone heredoc commit
check deny  "pnpm check && $HD_COMMIT" '.'
checkbg deny "$HD_COMMIT" "$TMO"      # run_in_background:true still fires through the heredoc

# a heredoc'd git add -A followed by a heredoc'd commit - covered by git-add-stash-guard, not here;
# this guard only needs to prove it does not stand down on the heredoc for ITS OWN checks.

# heredoc BODY containing a dangerous-looking command must NOT trip anything - proves the body is
# actually stripped, not merely that no stand-down happens (guards-review-2 point 11: the two cases
# above pass just as well if guard_strip_heredocs were replaced by an identity function, since the
# real target sits OUTSIDE the body either way; this is the case that only passes with real
# stripping).
HD_BODY="cat <<'EOF'${NL}pnpm check | tail${NL}EOF"
check allow "$HD_BODY" "$TMO"

# --- repo resolution reads the heredoc-stripped-but-NOT-quote-blanked text (guards-review-2 ADDED
# finding): a QUOTED cd/-C target must still resolve to the real repo, not fall through to $HOME
# once quotes are blanked (guard_norm_cd_target maps an empty string to $HOME, which is a RESOLVED,
# wrong, answer, not an "unresolved" one that (c) would correctly skip on) ------------------------
if command -v git >/dev/null 2>&1; then
  W2="$(mktemp -d)"; trap 'rm -rf "$W2"' EXIT
  GIT_CONFIG_GLOBAL="$W2/gitconfig-global"; export GIT_CONFIG_GLOBAL
  : > "$GIT_CONFIG_GLOBAL"
  git config --global user.email t@t.local
  git config --global user.name t
  QHOOKR="$W2/qhooked"; git init -q "$QHOOKR"
  mkdir -p "$QHOOKR/.git/hooks"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$QHOOKR/.git/hooks/pre-commit"
  chmod +x "$QHOOKR/.git/hooks/pre-commit"
  checkcwd deny "cd \"$QHOOKR\" && git commit -m x" "$W2" '.'
  checkcwd deny "git -C \"$QHOOKR\" commit -m x" "$W2" '.'
else
  echo "SKIP: git absent - quoted-cd repo resolution case not run"
fi

jq -n --arg cmd "pnpm check" '{tool_name:"Bash", session_id:"sess-lr", tool_input:{command:$cmd, timeout:900000, run_in_background:true}}' | sh "$GUARD" >/dev/null 2>&1 || true
grep -aqE '^[^ ]+ long-run-guard deny: .*\[sid=sess-lr\]$' "$SBLOG" && printf 'ok   decision line written to guards.log with sid\n' || { printf 'FAIL no decision line in sandbox log\n'; fail=1; }

# --- fixture repos for the (c)-is-conditional-on-a-pre-commit-hook rule -----------------------------
if command -v git >/dev/null 2>&1; then
  W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
  GIT_CONFIG_GLOBAL="$W/gitconfig-global"; export GIT_CONFIG_GLOBAL
  : > "$GIT_CONFIG_GLOBAL"
  git config --global user.email t@t.local
  git config --global user.name t

  NOHOOK="$W/nohook"; git init -q "$NOHOOK"
  HOOKR="$W/hooked"; git init -q "$HOOKR"
  mkdir -p "$HOOKR/.git/hooks"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$HOOKR/.git/hooks/pre-commit"
  chmod +x "$HOOKR/.git/hooks/pre-commit"

  checkcwd allow 'git commit -m "x"' "$NOHOOK" '.'     # no hook, no timeout -> (c) does not apply
  checkcwd deny  'git commit -m "x"' "$HOOKR" '.'      # hook present, no timeout -> (c) applies
  checkcwd allow 'git commit -m "x"' "$HOOKR" "$TMO"   # hook present, timeout fine -> allow
  checkcwd deny  'pnpm check' "$NOHOOK" '.'             # pnpm keeps (c) unconditional regardless of any hook

  # relative core.hooksPath, committed from a SUBDIRECTORY: must resolve against the worktree root,
  # never the payload cwd (guards-review MEDIUM finding, 2026-09-23).
  RELH="$W/relhooked"; git init -q "$RELH"
  mkdir -p "$RELH/.githooks" "$RELH/sub"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$RELH/.githooks/pre-commit"
  chmod +x "$RELH/.githooks/pre-commit"
  git -C "$RELH" config core.hooksPath .githooks
  checkcwd deny 'git commit -m "x"' "$RELH/sub" '.'    # relative hooksPath resolved via toplevel, subdir cwd
else
  echo "SKIP: git absent - hook-conditional (c) cases not run"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

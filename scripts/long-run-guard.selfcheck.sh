#!/usr/bin/env sh
# kit-scope: shared
# Self-check for long-run-guard.sh. Runnable: sh long-run-guard.selfcheck.sh
# Isolated GIT_CONFIG_GLOBAL + unset GIT_DIR/friends (same convention worktree.selfcheck.sh uses)
# so the fixture repos below (a hook-free repo, a repo with a pre-commit hook, and a repo with a
# relative core.hooksPath committed from a subdirectory) are never confused with any real repo.
# LRG_SH names the shell that runs the guard (default sh). With LRG_SH unset and dash present, the
# whole selfcheck re-runs once under dash (LRG_SH=dash) at the end.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_NOSYSTEM

DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
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
GUARD="$SB/kit/scripts/long-run-guard.sh"
SBLOG="$SB/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG" CLAUDE_CONFIG_DIR="$SB/cfg"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
fail=0
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

check() {
  want="$1"; cmd="$2"; extra="${3:-.}"
  payload="$(jq -n --arg cmd "$cmd" "{tool_input: ({command: \$cmd} | $extra)}" 2>/dev/null)"
  out="$(printf '%s' "$payload" | "${LRG_SH:-sh}" "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}

# checkcwd: same as check() but the payload also carries a top-level .cwd (what the guard resolves
# a bare git commit's repo from when there is no preceding cd/-C in the command itself).
checkcwd() {
  want="$1"; cmd="$2"; cwd="$3"; extra="${4:-.}"
  payload="$(jq -n --arg cmd "$cmd" --arg cwd "$cwd" "{cwd: \$cwd, tool_input: ({command: \$cmd} | $extra)}" 2>/dev/null)"
  out="$(printf '%s' "$payload" | "${LRG_SH:-sh}" "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s (cwd=%s)\n' "$got" "$cmd" "$cwd"; else
    printf 'FAIL want=%s got=%s : %s (cwd=%s)\n' "$want" "$got" "$cmd" "$cwd"; fail=1; fi
}

# checkbg: payload also carries top-level run_in_background (for the heredoc+run_in_background case).
checkbg() {
  want="$1"; cmd="$2"; extra="${3:-.}"
  payload="$(jq -n --arg cmd "$cmd" "{tool_input: ({command: \$cmd, run_in_background: true} | $extra)}" 2>/dev/null)"
  out="$(printf '%s' "$payload" | "${LRG_SH:-sh}" "$GUARD" 2>/dev/null || true)"
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

# --- (e) unbounded poll loop ---
check deny  'until [ -s /tmp/x/out ]; do sleep 5; done' '.'
check deny  'while [ ! -s f ]; do sleep 2; done; cat f' '.'
check deny  "until [ -s f ]${NL}do${NL}sleep 5${NL}done" '.'
check deny  'while true; do sleep 10; done' '.'
check deny  'while ! grep -q DONE log; do sleep 3; done' "$BG_FLAG"
check deny  "sh -c 'until [ -s f ]; do sleep 5; done'" '.'
check deny  'bash -c "while [ ! -f $f ]; do sleep 1; done"' '.'
check deny  'while [ $(wc -l < f) -lt 5 ]; do sleep 1; done' '.'
check deny  'while true; do i=0; until [ -s f ] || [ $i -ge 3 ]; do sleep 1; i=$((i+1)); done; done' '.'
check deny  'cd /tmp/x && until test -s f; do sleep 1; done' '.'
check deny  'while :; do [ -s f ] && break; sleep 5; done' '.'
# sub-agent payload: same verdict as the Lead (no caller-specific logic)
POLL1='until [ -s /tmp/x/out ]; do sleep 5; done'
sa_out="$(jq -n --arg cmd "$POLL1" '{agent_id:"a1", agent_type:"worker", tool_input:{command:$cmd}}' | "${LRG_SH:-sh}" "$GUARD" 2>/dev/null || true)"
if printf '%s' "$sa_out" | grep -aq '"permissionDecision": *"deny"'; then printf 'ok   [deny] sub-agent payload: %s\n' "$POLL1"; else
  printf 'FAIL want=deny got=allow : sub-agent payload: %s\n' "$POLL1"; fail=1; fi
check deny  "sh -c 'until [ -s f ]; do${NL}sleep 5; done'" '.'
check allow 'i=0; until [ -s f ] || [ $i -ge 60 ]; do sleep 10; i=$((i+1)); done' '.'
check allow 'i=0; until [ -s f ] || [ "$i" -ge 60 ]; do sleep 10; i=$((i+1)); done' '.'
check allow "timeout 600 sh -c 'until [ -s f ]; do sleep 10; done'" '.'
check allow "timeout 600 sh -c 'until [ -s f ]; do${NL}sleep 5; done' && cat f" '.'
check allow 'end=$(( $(date +%s) + 600 )); until [ -s f ] || [ "$(date +%s)" -ge "$end" ]; do sleep 5; done' '.'
check allow 'while [ $SECONDS -lt 600 ] && [ ! -s f ]; do sleep 5; done' '.'
check allow 'while IFS= read -r x; do echo "$x"; done < f' '.'
check allow "while read -r x${NL}do${NL}printf '%s\\n' \"\$x\"${NL}done < f" '.'
check allow 'while read -r u; do curl -s "$u"; sleep 1; done < urls' '.'
check allow 'for i in $(seq 60); do [ -s f ] && break; sleep 10; done' '.'
check allow 'echo "until done; do sleep 5; done"' '.'
check allow 'git commit -m "note: while x; do sleep 1; done"' "$TMO"
check allow 'while (( n++ < 60 )); do sleep 1; done' '.'
check allow 'while true; do i=$((i+1)); [ $i -ge 60 ] && break; sleep 5; done' '.'
check allow 'sleep 30 && cat f' '.'
check allow "cat <<'EOF' > s.sh${NL}until [ -s f ]; do sleep 5; done${NL}EOF" '.'
check allow "timeout -k 5 600 bash -c 'while [ ! -s f ]; do sleep 2; done'" '.'
# the deny text names the Monitor tool first and shows the bounded form
p_out="$(jq -n --arg cmd "$POLL1" '{tool_input:{command:$cmd}}' | "${LRG_SH:-sh}" "$GUARD" 2>/dev/null || true)"
if printf '%s' "$p_out" | grep -aqF 'Monitor tool' && printf '%s' "$p_out" | grep -aqF 'timeout 600 sh -c'; then
  printf 'ok   deny text names the Monitor tool and the timeout form\n'; else
  printf 'FAIL deny text lacks the Monitor tool or the timeout form\n'; fail=1; fi
# reasontxt <cmd> <flag> <want-substring> <label>: the deny reason contains the substring
reasontxt() {
  r_out="$(jq -n --arg cmd "$1" "{tool_input: ({command: \$cmd} | $2)}" | "${LRG_SH:-sh}" "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$r_out" | grep -aqF "$3"; then printf 'ok   %s reason names %s\n' "$4" "$3"; else
    printf 'FAIL %s reason lacks %s\n' "$4" "$3"; fail=1; fi
}
# tier 1: a loop with sleep in a command naming a harness-owned output, bounded or not
T1='i=0; until [ -s /tmp/claude-1000/proj/sess/tasks/abc.output ] || [ $i -ge 60 ]; do sleep 10; i=$((i+1)); done'
T2='until [ -s /tmp/claude-1000/proj/sess/tasks/abc.output ]; do sleep 5; done'
check deny  "$T1" '.'
check deny  "$T2" '.'
reasontxt "$T1" '.' 'completion notification' T1
reasontxt "$T2" '.' 'completion notification' T2
check deny  "timeout 600 sh -c 'until [ -s /tmp/claude-1000/proj/sess/tasks/b.output ]; do sleep 5; done'" '.'
check deny  'until grep -q done /home/u/.claude/projects/p/s/subagents/agent-a1.jsonl; do sleep 5; done' '.'
check deny  'f=/tmp/claude-1000/proj/sess/tasks/c.output; i=0; until [ -s "$f" ] || [ $i -ge 9 ]; do sleep 5; i=$((i+1)); done' '.'
check deny  'i=0; until [ -n "$(ls /tmp/claude-1000/proj/sess/tasks)" ] || [ $i -ge 5 ]; do sleep 3; i=$((i+1)); done' '.'
check deny  "$T1" "$BG_FLAG"
# tier 2: any other unbounded loop with sleep
E1='until nc -z localhost 5432; do sleep 1; done'
check deny  "$E1" '.'
reasontxt "$E1" '.' 'Monitor tool' E1
check allow "timeout 120 sh -c 'until curl -sf http://localhost:8080/health; do sleep 2; done'" '.'
check allow 'i=0; until curl -sf http://localhost:8080/health || [ $i -ge 30 ]; do sleep 2; i=$((i+1)); done' '.'
check allow 'cat /tmp/claude-1000/proj/sess/tasks/abc.output' '.'
check allow 'sleep 5; cat /tmp/claude-1000/proj/sess/tasks/abc.output' '.'
check allow 'while read -r l; do echo "$l"; done < /tmp/claude-1000/proj/sess/tasks/abc.output' '.'
check allow 'tail -n 20 /home/u/.claude/projects/p/s/subagents/agent-a1.jsonl' '.'
# comments: an unquoted word-start # hides the rest of its line (an apostrophe or `; done` in it too)
check allow "i=0${NL}until [ -s out ] || [ \$i -ge 60 ]; do${NL}  sleep 5   # poll; done when out exists${NL}  i=\$((i+1))${NL}done" '.'
check allow "# start server (until it binds)${NL}sleep 2${NL}curl -sf localhost:8080" '.'
check deny  "# don't stop${NL}until [ -s f ]; do sleep 5; done" '.'
# a heredoc inside an sh -c script is stripped before the scan
check allow "sudo sh -c 'cat > /usr/local/bin/wait-db <<EOF${NL}until pg_isready; do sleep 1; done${NL}EOF'" '.'
# case patterns are never keywords (`done)` does not close the loop)
check allow 'i=0; while [ $i -lt 60 ]; do case $(cat st) in run) sleep 5;; done) break;; esac; i=$((i+1)); done' '.'
# bound idioms: bare SECONDS, a deadline refreshed from date +%s, a step inside $(( ))
check allow 'SECONDS=0; while (( SECONDS < 60 )); do sleep 1; done' '.'
check allow 'end=$(( $(date +%s) + 60 )); now=$(date +%s); until [ -s f ] || [ "$now" -ge "$end" ]; do sleep 5; now=$(date +%s); done' '.'
check allow 'until [ -s f ] || [ $((i+=1)) -gt 60 ]; do sleep 1; done' '.'
# a long option `--count` is not a decrement of $count
check deny  'while [ $(grep --count DONE log) -lt $count ]; do sleep 5; done' '.'
# a shell word anywhere in the simple command, after options, still has its -c script read
check deny  "bash --norc -c 'until [ -s f ]; do sleep 5; done'" '.'
check deny  "bash -o pipefail -c 'until [ -s f ]; do sleep 5; done'" '.'
check deny  "sudo -u x sh -c 'until [ -s f ]; do sleep 5; done'" '.'
check deny  "nice -n 5 sh -c 'until [ -s f ]; do sleep 5; done'" '.'
check deny  "docker compose exec db sh -c 'until pg_isready; do sleep 1; done'" '.'
check deny  "timeout --signal KILL 600 sh -c 'until [ -s /tmp/claude-1000/p/s/tasks/x.output ]; do sleep 5; done'" '.'
# pairs the -k allow case: the shell must be found after timeout's own options
check deny  "timeout -k 5 600 bash -c 'until [ -s /tmp/claude-1000/p/s/tasks/x.output ]; do sleep 5; done'" '.'
# a timeout after a wrapper's own arguments still bounds the shell (the unbounded forms deny above)
check allow "docker compose exec db timeout 60 sh -c 'until pg_isready; do sleep 1; done'" '.'
check allow "nice -n 5 timeout 300 sh -c 'until [ -s f ]; do sleep 5; done'" '.'
# an assignment or --opt= word is never a shell word, so the timeout behind it is still seen
check allow "SHELL=/bin/bash timeout 120 sh -c 'until curl -sf localhost:8080; do sleep 2; done'" '.'
# only an assignment word is excluded: `--shell=/bin/bash -c` still has its script read, and a
# `SHELL=/bin/sh sleep` prefix does not hide the sleep
check deny  "su --shell=/bin/bash -c 'while true; do sleep 1; done' user" '.'
check deny  'while true; do SHELL=/bin/sh sleep 1; done' '.'
# an inner (n) does not end the (( )) span early, so --n is still a step
check allow 'n=30; while (( (n) > 0 && --n )); do sleep 1; done' '.'
# inside (( )) a --n is a pre-decrement, not a long option
check allow 'n=30; while (( --n > 0 )); do curl -sf x && break; sleep 2; done' '.'
# `)` does not start a comment: the step after `$(date)#` is still read
check allow 'until [ -s f ] || [ $i -ge 9 ]; do sleep 1; echo $(date)#; i=$((i+1)); done' '.'
# a mid-word # is not a comment (if it were, the loop after it would be dropped and allowed)
check deny  'x=a#b; until [ -s f ]; do sleep 5; done' '.'
check deny  'echo ${#x}; until [ -s f ]; do sleep 5; done' '.'
# a `while)` case pattern is not a keyword; nested case depth is tracked
check allow 'i=0; while [ $i -lt 9 ]; do case $x in while) sleep 1;; esac; i=$((i+1)); done' '.'
check allow 'i=0; while [ $i -lt 9 ]; do case $a in x) case $b in done) sleep 1;; esac;; esac; i=$((i+1)); done' '.'
# timeout --kill-after VALUE: the shell is found after it (tier 1 deny proves it), and it bounds the loop
check deny  "timeout --kill-after 5 600 sh -c 'until [ -s /tmp/claude-1000/p/s/tasks/x.output ]; do sleep 5; done'" '.'
check allow "timeout --kill-after 5 600 sh -c 'until [ -s f ]; do sleep 5; done'" '.'
# policy: a detached unbounded loop is denied like nohup ... &
check deny  "screen -dmS w bash -c 'while true; do x; sleep 60; done'" '.'

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
  W2="$(mktemp -d)"; trap 'rm -rf "$W2" "$SB"' EXIT
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

jq -n --arg cmd "pnpm check" '{tool_name:"Bash", session_id:"sess-lr", tool_input:{command:$cmd, timeout:900000, run_in_background:true}}' | "${LRG_SH:-sh}" "$GUARD" >/dev/null 2>&1 || true
grep -aqE '^[^ ]+ long-run-guard deny: .*\[sid=sess-lr\]$' "$SBLOG" && printf 'ok   decision line written to guards.log with sid\n' || { printf 'FAIL no decision line in sandbox log\n'; fail=1; }

# --- fixture repos for the (c)-is-conditional-on-a-pre-commit-hook rule -----------------------------
if command -v git >/dev/null 2>&1; then
  W="$(mktemp -d)"; trap 'rm -rf "$W" "$W2" "$SB"' EXIT
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

# kit-gate stand-down: a marker under the sandbox kit's .state/off/ silences the hook (no output, exit 0,
# one guards.log line); the control run without the marker proves the payload does emit.
SD_PAYLOAD="$(jq -n '{tool_name:"Bash", session_id:"sess-sd", tool_input:{command:"pnpm check", timeout:900000, run_in_background:true}}')"
mkdir -p "$SB/kit/.state/off"
sd_ctl="$(printf '%s' "$SD_PAYLOAD" | "${LRG_SH:-sh}" "$GUARD" 2>/dev/null || true)"
: > "$SB/kit/.state/off/long-run-guard"
sd_out="$(printf '%s' "$SD_PAYLOAD" | "${LRG_SH:-sh}" "$GUARD" 2>/dev/null)"; sd_rc=$?
rm -f "$SB/kit/.state/off/long-run-guard"
if [ -n "$sd_ctl" ] && [ -z "$sd_out" ] && [ "$sd_rc" = 0 ] && grep -aq 'kit-gate standdown long-run-guard:' "$SBLOG"; then
  printf 'ok   kill-switch marker stands the hook down (empty stdout, exit 0, log line)\n'
else
  printf 'FAIL kill-switch marker did not stand the hook down\n'; fail=1
fi

if [ -z "${LRG_SH:-}" ] && command -v dash >/dev/null 2>&1; then
  echo "-- re-run under dash"
  LRG_SH=dash dash "$DIR/long-run-guard.selfcheck.sh" || fail=1
fi

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

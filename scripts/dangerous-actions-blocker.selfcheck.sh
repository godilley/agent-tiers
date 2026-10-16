#!/usr/bin/env sh
# kit-scope: shared
# Self-check for dangerous-actions-blocker.sh. Runnable: `sh dangerous-actions-blocker.selfcheck.sh`.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
# decision/breadcrumb lines go to a SANDBOX log, never the real kit's .state/guards.log (opus reviewer, Wave D:
# in-place selfchecks had filled the live record with fixture noise)
# Run from a SANDBOX kit copy with a temp config dir and guards log, never the real kit's .state/, and
# with every kit-gate input cleared so the user's own options cannot stand the hook down mid-check.
SB="$(mktemp -d)" || { echo "SELF-CHECK FAILED: mktemp"; exit 1; }
trap 'rm -rf "$SB"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM
mkdir -p "$SB/kit/install" "$SB/cfg" "$SB/managed"
cp -R "$DIR" "$SB/kit/scripts"
# Managed settings dir pointed at an empty temp dir, so a machine's real one cannot change the result.
sed "s|^_kg_managed=.*|_kg_managed='$SB/managed'|" "$DIR/kit-gate.sh" > "$SB/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$SB/managed'" "$SB/kit/scripts/kit-gate.sh" || { echo "SELF-CHECK FAILED: _kg_managed not rewritten"; exit 1; }
cp "$DIR/../install/options.tsv" "$SB/kit/install/"
GUARD="$SB/kit/scripts/dangerous-actions-blocker.sh"
SBLOG="$SB/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG" CLAUDE_CONFIG_DIR="$SB/cfg"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
# A value inherited from the calling shell must never leak into cases that assume the knob is unset.
unset AGENT_TIERS_PROTECTED_BRANCHES
fail=0

# 0. Host regex probe (T1.1, 2026-08-16) - BEFORE the jq skip, so a jq-less host cannot skip it: every
#    dd/rm/psql/npm-publish/git-push check in the guard is anchored on `\b`, a GNU ERE extension. A grep
#    whose regex engine treats `\b` as a literal `b` makes the guard wired-but-DENY-MISSING on every one
#    of them. This asserts the HOST'S grep (the one the guard actually runs under) honours it; a
#    macOS/BSD host where it does not FAILS here instead of passing vacuously.
if [ "$(printf 'dd x\n' | grep -cE 'dd\b' 2>/dev/null)" != 1 ] || [ "$(printf 'ddx\n' | grep -cE 'dd\b' 2>/dev/null)" != 0 ]; then
  echo "FAIL: this host's grep does not honour the \\b word boundary (uname: $(uname -s)) - dangerous-actions-blocker would silently DENY-MISS dd/rm/psql/publish/push. Rewrite \\b portably (see the guard's Known ceiling block) before wiring it here."
  exit 1
fi
printf 'ok   host grep honours \\b (%s)\n' "$(uname -s)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

check_bash() {
  want="$1"; cmd="$2"
  out="$(printf '%s' "$cmd" | jq -R '{tool_name: "Bash", tool_input: {command: .}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}

check_write() {
  want="$1"; tool="$2"; path="$3"
  pf="file_path"; [ "$tool" = "NotebookEdit" ] && pf="notebook_path"
  out="$(jq -n --arg t "$tool" --arg p "$path" --arg pf "$pf" '{tool_name: $t, tool_input: ({($pf): $p} + {content: "x", new_source: "x"})}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s %s\n' "$got" "$tool" "$path"; else
    printf 'FAIL want=%s got=%s : %s %s\n' "$want" "$got" "$tool" "$path"; fail=1; fi
}

check_bash_cwd() { # $1=want $2=cwd $3=cmd - for checks that need a real git repo (no-refspec push)
  want="$1"; cwd="$2"; cmd="$3"
  out="$(jq -n --arg c "$cwd" --arg x "$cmd" '{cwd: $c, tool_name: "Bash", tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$cmd"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$cmd"; fail=1; fi
}

# should DENY (Bash) - originals
check_bash deny 'dd if=/dev/zero of=/dev/sda'
check_bash deny 'mkfs.ext4 /dev/sdb1'
check_bash deny ':(){ :|:& };:'
check_bash deny 'rm -rf --no-preserve-root /'
check_bash deny 'psql -c "DROP DATABASE prod"'
check_bash deny 'npm publish'
check_bash deny 'git push --force origin main'
check_bash deny 'git push -f origin master'
check_bash deny 'echo "sk-abcdefghijklmnopqrstuvwx"'

# should DENY (Bash) - regressions from the 2026-08-06 review
check_bash deny 'dd of=/dev/sda if=/dev/zero'                       # reversed arg order
check_bash deny 'mkfs -t ext4 /dev/sdb1'                             # space form, no dot
check_bash deny 'git push origin master --force'                    # flag AFTER the refspec
check_bash deny 'git push origin main -f'
check_bash deny 'psql -c "TRUNCATE TABLE users"'                    # TRUNCATE, header claimed it
check_bash deny 'echo "sk-ant-api03-abcdefghijklmnopqrstuvwx"'      # Anthropic key shape
check_bash deny 'echo "AIzaSyAbcdefghijklmnopqrstuvwxyz0123456"'    # Google key shape

# should ALLOW (Bash)
check_bash allow 'dd if=/dev/zero of=/tmp/build/test.img'
check_bash allow 'rm -rf /tmp/build'
check_bash allow 'git push --force origin feature/foo'
check_bash allow 'git push origin feature/main-fix --force'         # branch NAME contains "main", not IS main
check_bash allow 'npm run build'
check_bash allow 'echo hello world'
check_bash allow 'mkfs_helper.sh --dry-run'                          # not the mkfs command itself

# should ALLOW (Bash) - regressions from the 2026-08-06 review, round 2
check_bash allow 'git push -f origin feature/x && git checkout master'   # force flag and "master" in
                                                                            # DIFFERENT segments - must not co-trigger
check_bash allow 'rg "npm publish" docs/'                                 # mentioned in a search, not run
check_bash allow 'git commit -m "add mkfs.ext4 support"'                  # mentioned in a message, not run
check_bash allow 'grep -r "DROP TABLE" migrations/'                       # mentioned in a search, not run
check_bash allow 'echo "reminder: TRUNCATE TABLE needs a WHERE-free confirm"'  # no DB client running
# should DENY (Bash) - DROP/TRUNCATE requires an actually-running DB client (command position), not
# just the words anywhere - this is the positive control for the above negatives
check_bash deny 'mysql -e "DROP TABLE users"'

# should ALLOW (Bash) - regressions from the 2026-08-06 review, round 3: --no-preserve-root at
# argument position (mentioned, not run via rm) - same class as round 2's rg/grep fixes
check_bash allow 'rg -- "--no-preserve-root" docs/'
check_bash allow 'echo "never pass --no-preserve-root"'
# should DENY - positive control: rm actually running with the flag
check_bash deny 'rm -rf --no-preserve-root /tmp/x'

# regression (round 3, MEDIUM): force-push with NO refspec force-pushes the CURRENT branch - needs a
# real repo to resolve HEAD against.
FPW="$(mktemp -d "$SB/t.XXXXXX")"
(cd "$FPW" && git init -q && git symbolic-ref HEAD refs/heads/master && git config user.email t@t.local && git config user.name t \
  && git commit -q --allow-empty -m init)
check_bash_cwd deny "$FPW" 'git push -f'                         # no refspec at all, current branch is master
check_bash_cwd deny "$FPW" 'git push --force origin'              # remote name only, still no branch
check_bash_cwd deny "$FPW" 'git push origin +master'               # +ref refspec form, no --force/-f flag
# checkout directories NAMED main / master, on a feature branch - the false-deny regression pair
MAINDIR="$(mktemp -d "$SB/t.XXXXXX")/main"; MASTERDIR="$(mktemp -d "$SB/t.XXXXXX")/master"
for d in "$MAINDIR" "$MASTERDIR"; do
  mkdir -p "$d"
  (cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/feature/foo && git config user.email t@t.local \
    && git config user.name t && git commit -q --allow-empty -m init)
done
FPW2="$(mktemp -d "$SB/t.XXXXXX")"
(cd "$FPW2" && git init -q && git symbolic-ref HEAD refs/heads/feature/foo && git config user.email t@t.local && git config user.name t \
  && git commit -q --allow-empty -m init)
check_bash_cwd allow "$FPW2" 'git push -f'                        # no refspec, but current branch is NOT main/master

# 2026-08-23 (external cold review): the no-refspec leg used its OWN anchored regex
# (^[[:space:]]*git push ...), so every wrapper CMDPOS_PREFIX already handles - sudo, nohup, an
# absolute path, a subshell open - fell straight through it while the outer command-position match
# fired. Same class the round-3 review fixed everywhere else in this file.
check_bash_cwd deny "$FPW" 'sudo git push -f'
check_bash_cwd deny "$FPW" 'nohup git push -f'
check_bash_cwd deny "$FPW" '/usr/bin/git push -f'
check_bash_cwd deny "$FPW" '(git push -f)'
check_bash_cwd deny "$FPW" 'sudo git push --force origin main'    # explicit ref + wrapper (regression)
check_bash_cwd allow "$FPW" 'sudo git push -f origin feature'     # explicit non-main ref (regression)
# the repo the push targets is NOT the payload cwd: `cd` before the push, and `git -C` inside it
# (Option B - guard_verb_optspan gives push the same pre-verb option span commit already had).
check_bash_cwd deny "$FPW2" "cd $FPW && git push -f"
check_bash_cwd deny "$FPW2" "git -C $FPW push -f"
check_bash_cwd deny "$FPW2" "sudo git -C $FPW push --force"
check_bash_cwd allow "$FPW" "cd $FPW2 && git push -f"             # resolves to the feature-branch repo
# unresolved target -> DENY, not fail-open (T1.10 posture: a missed force-push to main is
# irreversible, a false deny costs a re-spell).
check_bash_cwd deny "$FPW2" 'cd /nonexistent-agent-tiers-probe && git push -f'
check_bash_cwd deny "$FPW2" 'cd "$SOMEVAR" && git push -f'
# ... and the fail-OPEN half of the same branch: no cwd in the payload at all is a tooling gap, not
# an unresolvable target (check_bash sends no .cwd).
check_bash allow 'git push -f'

# 2026-08-23 opus review round 2 - one case per finding.
# HIGH: the resolver stops at the FIRST matching segment, so a push AFTER a `cd` into another repo
# was branch-checked against the first push segment's directory (here: the feature-branch payload
# cwd) and allowed.
check_bash_cwd deny "$FPW2" "git push origin feature && cd $FPW && git push -f"
check_bash_cwd allow "$FPW" "git push origin feature && cd $FPW2 && git push -f"
# MEDIUM: --git-dir/--work-tree name the repo and nothing resolves them - deny, do not branch-check
# the payload cwd (which here is a safe feature branch).
check_bash_cwd deny "$FPW2" "git --git-dir=$FPW/.git --work-tree=$FPW push -f"
check_bash_cwd deny "$FPW2" "git --git-dir $FPW/.git push --force"
# MEDIUM false deny: a checkout directory NAMED main/master in the pre-verb option span is not a
# main/master REFSPEC - the scans read the argument tail only.
check_bash_cwd allow "$FPW2" "git -C $FPW2 push -f origin feature/foo"
check_bash_cwd allow "$FPW2" "git -C $MAINDIR push -f"
check_bash_cwd allow "$FPW2" "git -C $MASTERDIR push -f origin feature/foo"
check_bash_cwd deny "$FPW" "(cd $FPW2 && git push origin x) && git push -f"
# A bare `HEAD` refspec is the no-refspec shape wearing a ref: it force-pushes whatever branch is
# checked out, so it resolves the same way (2026-08-23). `HEAD:<branch>` is NOT this case - it names
# its destination, so it must stay allowed unless that destination is main/master.
check_bash_cwd deny  "$FPW"  "git push -f origin HEAD"
check_bash_cwd deny  "$FPW"  "git push origin HEAD --force"
check_bash_cwd deny  "$FPW"  "git push --force-with-lease origin +HEAD"
check_bash_cwd allow "$FPW2" "git push -f origin HEAD"
check_bash_cwd allow "$FPW"  "git push -f origin HEAD:feature/x"
check_bash_cwd deny  "$FPW2" "git push -f origin HEAD:master"
# LOW test gaps: --force-with-lease, a relative -C, and a chained cd.
check_bash_cwd deny "$FPW" 'git push --force-with-lease'
check_bash_cwd deny "$FPW2" "cd $FPW/.. && cd $FPW && git push -f"
check_bash_cwd deny "$FPW2" "cd $(dirname "$FPW") && git -C $(basename "$FPW") push -f"
# Dynamic protected names: remote default branch + AGENT_TIERS_PROTECTED_BRANCHES.
# Checked out on develop, with origin/HEAD also pointing at develop, so both the explicit-ref leg
# and the no-refspec/current-branch leg get exercised against the SAME resolved name.
DEVW="$(mktemp -d "$SB/t.XXXXXX")"
(cd "$DEVW" && git init -q && git symbolic-ref HEAD refs/heads/develop && git config user.email t@t.local && git config user.name t \
  && git commit -q --allow-empty -m init && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop)
check_bash_cwd deny "$DEVW" 'git push --force origin develop'   # explicit ref naming the remote default
check_bash_cwd deny "$DEVW" 'git push -f'                        # no refspec, current branch IS the remote default
rm -rf "$DEVW"

AGENT_TIERS_PROTECTED_BRANCHES=release check_bash_cwd deny "$FPW2" 'git push --force origin release'
AGENT_TIERS_PROTECTED_BRANCHES=unrelated-name check_bash_cwd deny "$FPW2" 'git push --force origin master'   # env never REMOVES main/master
AGENT_TIERS_PROTECTED_BRANCHES=release check_bash_cwd allow "$FPW2" 'git push -f origin feature/foo'          # no regression on an unrelated feature branch
AGENT_TIERS_PROTECTED_BRANCHES=release check_bash_cwd deny "$FPW2" 'git push origin +release'                 # "+ref" shorthand, no --force/-f flag at all, env-protected name
# a no-refspec force-push whose CURRENT branch (not the remote default) is only protected via env
RELW="$(mktemp -d "$SB/t.XXXXXX")"
(cd "$RELW" && git init -q && git symbolic-ref HEAD refs/heads/release && git config user.email t@t.local && git config user.name t \
  && git commit -q --allow-empty -m init)
AGENT_TIERS_PROTECTED_BRANCHES=release check_bash_cwd deny "$RELW" 'git push -f'
rm -rf "$RELW"
# a glob metachar in the env value must not expand against the hook's cwd (noglob regression): a
# "release/*" value run from a cwd that actually HAS a matching release/ dir+file must still treat
# it as one literal (rejected) string, not glob-expand into real filenames mid-loop.
GLOBDIR="$(mktemp -d "$SB/t.XXXXXX")"
(cd "$GLOBDIR" && git init -q && git symbolic-ref HEAD refs/heads/feature/foo && git config user.email t@t.local && git config user.name t \
  && git commit -q --allow-empty -m init && mkdir -p release && echo x > release/afile.txt)
AGENT_TIERS_PROTECTED_BRANCHES='release/*' check_bash_cwd allow "$GLOBDIR" 'git push -f origin feature/foo'
rm -rf "$GLOBDIR"
# regex metachar in env is rejected outright, not injected into the pattern - from a FIXED empty
# cwd (no repo, no files) so the result cannot depend on anything else living in that directory.
EMPTYCWD="$(mktemp -d "$SB/t.XXXXXX")"
AGENT_TIERS_PROTECTED_BRANCHES='.*' check_bash_cwd allow "$EMPTYCWD" 'git push -f origin feature/foo'
rm -rf "$EMPTYCWD"

# Regression: a remote default branch name containing an ERE metachar (git itself allows ( ) + { | in
# a branch name) must be REJECTED rather than escaped - an invalid ERE makes grep exit 2, which the
# caller reads as no-match, silently dropping main/master protection too (found in review).
XPAREN="$(mktemp -d "$SB/t.XXXXXX")"
(cd "$XPAREN" && git init -q && git config user.email t@t.local && git config user.name t && git commit -q --allow-empty -m init \
  && git update-ref 'refs/remotes/origin/x(' HEAD && git symbolic-ref refs/remotes/origin/HEAD 'refs/remotes/origin/x(')
check_bash_cwd deny "$XPAREN" 'git push --force origin master'   # origin default name has a bad char - main/master still denied
AGENT_TIERS_PROTECTED_BRANCHES='x(' check_bash_cwd deny "$XPAREN" 'git push --force origin master'   # same bad char via env - still denied
rm -rf "$XPAREN"

rm -rf "$FPW" "$FPW2" "$MAINDIR" "$MASTERDIR"

# should DENY (Write/Edit)
check_write deny Write '/home/user/project/.env'
check_write deny Write '.env.local'
check_write deny Edit '/home/user/.ssh/id_rsa'
check_write deny Write '/home/user/.npmrc'
check_write deny Write '/tmp/x/server.pem'
check_write deny Write '/home/user/.aws/credentials'
check_write deny Write '/home/user/.kube/config'
check_write deny Write '/home/user/.docker/config.json'
# regression (round 2, MEDIUM): the ONE prior NotebookEdit case was an allow, which passes even with
# the whole branch deleted - this deny case is the load-bearing proof the field-name plumbing works.
check_write deny NotebookEdit '/home/user/.ssh/id_rsa'

# should ALLOW (Write/Edit)
check_write allow Write '/home/user/project/.env.example'
check_write allow Write '/home/user/project/src/main.ts'
check_write allow Edit 'README.md'
check_write allow NotebookEdit '/home/user/project/notebook.ipynb'

# regression (round 3, MEDIUM): MultiEdit shares Write/Edit's file_path field - the path check must
# cover it even though security-gate.sh's separate CONTENT check still declines MultiEdit
check_write deny MultiEdit '/home/user/.ssh/id_rsa'
check_write allow MultiEdit '/home/user/project/src/main.ts'

# Symlink resolution (2026-08-29 portability fix): a Write to a symlink whose TARGET is a
# protected file must resolve and deny, on the normal path AND on the macOS-shaped fallback where
# `readlink -f` (GNU-only, no `-f` flag on BSD/macOS) is unavailable.
SYMDIR="$(mktemp -d "$SB/t.XXXXXX")"
ln -s "$SYMDIR/.env" "$SYMDIR/innocent-name" 2>/dev/null
check_write deny Write "$SYMDIR/innocent-name"
if command -v python3 >/dev/null 2>&1; then
  SHIMDIR="$(mktemp -d "$SB/t.XXXXXX")"
  printf '#!/bin/sh\nexit 1\n' > "$SHIMDIR/readlink"; chmod +x "$SHIMDIR/readlink"
  out="$(PATH="$SHIMDIR:$PATH" sh -c "jq -n --arg p '$SYMDIR/innocent-name' '{tool_name:\"Write\", tool_input:{file_path:\$p, content:\"x\"}}' | sh '$GUARD'" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then
    printf 'ok   [deny] symlink resolved via python3 fallback when readlink -f is unavailable\n'
  else
    printf 'FAIL symlink to a protected file was NOT caught when readlink -f is unavailable (python3 fallback broken): %s\n' "$out"; fail=1
  fi
  rm -rf "$SHIMDIR"
else
  echo "  (python3-fallback case skipped: python3 absent on this host)"
fi
rm -rf "$SYMDIR"

# Wave D: a deny writes a decision line with the sid
jq -n '{tool_name:"Bash", session_id:"sess-dab", tool_input:{command:"mkfs.ext4 /dev/sda1"}}' | sh "$GUARD" >/dev/null 2>&1 || true
grep -aqE '^[^ ]+ dangerous-actions-blocker deny: Bash .*\[sid=sess-dab\]$' "$SBLOG" && printf 'ok   decision line written to guards.log with sid\n' || { printf 'FAIL no decision line in sandbox log\n'; fail=1; }
# kit-gate stand-down: a marker under the sandbox kit's .state/off/ silences the hook (no output, exit 0,
# one guards.log line); the control run without the marker proves the payload does emit.
SD_PAYLOAD="$(jq -n '{tool_name:"Bash", session_id:"sess-sd", tool_input:{command:"mkfs.ext4 /dev/sda1"}}')"
mkdir -p "$SB/kit/.state/off"
sd_ctl="$(printf '%s' "$SD_PAYLOAD" | sh "$GUARD" 2>/dev/null || true)"
: > "$SB/kit/.state/off/dangerous-actions-blocker"
sd_out="$(printf '%s' "$SD_PAYLOAD" | sh "$GUARD" 2>/dev/null)"; sd_rc=$?
rm -f "$SB/kit/.state/off/dangerous-actions-blocker"
if [ -n "$sd_ctl" ] && [ -z "$sd_out" ] && [ "$sd_rc" = 0 ] && grep -aq 'kit-gate standdown dangerous-actions-blocker:' "$SBLOG"; then
  printf 'ok   kill-switch marker stands the hook down (empty stdout, exit 0, log line)\n'
else
  printf 'FAIL kill-switch marker did not stand the hook down\n'; fail=1
fi

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for dangerous-actions-blocker.sh. Runnable: `sh dangerous-actions-blocker.selfcheck.sh`.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
GUARD="$DIR/dangerous-actions-blocker.sh"
# decision/breadcrumb lines go to a SANDBOX log, never the real kit's .state/guards.log (opus reviewer, Wave D:
# in-place selfchecks had filled the live record with fixture noise)
SBLOG="$(mktemp -d)/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG"
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
FPW="$(mktemp -d)"
(cd "$FPW" && git init -q && git symbolic-ref HEAD refs/heads/master && git config user.email t@t.local && git config user.name t \
  && git commit -q --allow-empty -m init)
check_bash_cwd deny "$FPW" 'git push -f'                         # no refspec at all, current branch is master
check_bash_cwd deny "$FPW" 'git push --force origin'              # remote name only, still no branch
check_bash_cwd deny "$FPW" 'git push origin +master'               # +ref refspec form, no --force/-f flag
# checkout directories NAMED main / master, on a feature branch - the false-deny regression pair
MAINDIR="$(mktemp -d)/main"; MASTERDIR="$(mktemp -d)/master"
for d in "$MAINDIR" "$MASTERDIR"; do
  mkdir -p "$d"
  (cd "$d" && git init -q && git symbolic-ref HEAD refs/heads/feature/foo && git config user.email t@t.local \
    && git config user.name t && git commit -q --allow-empty -m init)
done
FPW2="$(mktemp -d)"
(cd "$FPW2" && git init -q && git symbolic-ref HEAD refs/heads/feature/foo && git config user.email t@t.local && git config user.name t \
  && git commit -q --allow-empty -m init)
check_bash_cwd allow "$FPW2" 'git push -f'                        # no refspec, but current branch is NOT main/master

# W1-1 (dan-9 cold review, 2026-08-23): the no-refspec leg used its OWN anchored regex
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
SYMDIR="$(mktemp -d)"
ln -s "$SYMDIR/.env" "$SYMDIR/innocent-name" 2>/dev/null
check_write deny Write "$SYMDIR/innocent-name"
if command -v python3 >/dev/null 2>&1; then
  SHIMDIR="$(mktemp -d)"
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
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

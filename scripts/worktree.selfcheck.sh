#!/usr/bin/env sh
# kit-scope: shared
# Self-check for worktree.sh. Runnable: `sh worktree.selfcheck.sh`; WT_SH=dash runs the script
# under test under dash too (plain `dash worktree.selfcheck.sh` only runs this harness under dash).
# Isolated `mktemp -d` fixture git repo with a bare `origin` remote (so `down --merge`'s fetch/push
# have somewhere to talk to) - never touches real ~/.claude state or any live project worktree,
# matching doc-lifecycle-check.selfcheck.sh's own convention. GIT_CONFIG_GLOBAL points at a temp file
# for the whole run, GIT_CONFIG_NOSYSTEM=1 skips the machine's /etc/gitconfig, and every GIT_* env var
# the harness (or a hook launched from a linked worktree, per .githooks/pre-commit) might have
# exported is unset first - otherwise a stray GIT_DIR/GIT_INDEX_FILE would make every `git` call below
# silently resolve to the REAL repo instead of the fixture.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_NOSYSTEM
set -u
HERE="$(CDPATH= cd "$(dirname "$0")" && pwd)"
WTSH="$HERE/worktree.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
eq_rc() { [ "$1" -eq "$2" ] && ok "$3" || bad "$3 (want exit $1, got $2)"; }

command -v git >/dev/null 2>&1 || { echo "SKIP: git absent"; exit 0; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; W="$(cd "$W" && pwd -P)"

GIT_CONFIG_GLOBAL="$W/gitconfig-global"
export GIT_CONFIG_GLOBAL
: > "$GIT_CONFIG_GLOBAL"
# .claude/worktrees/ is excluded by worktree.sh itself (MAIN's own info/exclude, on first `up`), so
# this global excludes file is left EMPTY throughout - proving MAIN's cleanliness never depends on
# the user having edited it.
GLOBAL_EXCLUDES="$W/global-ignore"
: > "$GLOBAL_EXCLUDES"
git config --global core.excludesfile "$GLOBAL_EXCLUDES"
git config --global user.email t@t.local
git config --global user.name t

# --- bare origin remote, so `down --merge`'s fetch/push have somewhere to land ---------------------
BARE="$W/origin.git"
git init -q --bare "$BARE"

MAIN="$W/main"
git clone -q "$BARE" "$MAIN"
cd "$MAIN" || exit 1
git commit -q --allow-empty -m init
git branch -M master
git push -q -u origin master

# --- fixtures: tracked file; CLAUDE.md and .claude/agents ignored via a real .gitignore (never a
# hand-written info/exclude - the script's own carry logic is what must add those lines); tracked
# skill file; a package-lock.json + node_modules with the REALISTIC trailing-slash gitignore pattern,
# which a bare (non-anchored, non-slashed) pattern would not prove exercises the exclude fix -----
printf 'tracked\n' > README.md
{
  echo 'CLAUDE.md'
  echo '.claude/agents'
  echo 'node_modules/'
} > .gitignore
git add README.md .gitignore
git commit -q -m "tracked readme + gitignore"

printf '# context\n' > CLAUDE.md
mkdir -p .claude/agents
printf 'agent one\n' > .claude/agents/one.md

mkdir -p .claude/skills
printf '# keep\n' > .claude/skills/keep.md
git add .claude/skills/keep.md
git commit -q -m "tracked skill"

printf '{}\n' > package-lock.json
mkdir -p node_modules
printf 'marker\n' > node_modules/marker
git add package-lock.json
git commit -q -m "tracked lockfile"

# =====================================================================================================
# up t1: creates the worktree, symlinks the carry set, empty status, exclude lines added exactly once
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up t1 2>&1)"; RC=$?
eq_rc 0 "$RC" "up t1 exits 0"

WT1="$MAIN/.claude/worktrees/t1"
[ -d "$WT1" ] && ok "up t1 creates the worktree dir" || bad "worktree dir missing: $WT1"
git -C "$MAIN" show-ref --verify --quiet refs/heads/t1 && ok "up t1 creates branch t1" \
  || bad "branch t1 was not created"

[ -L "$WT1/CLAUDE.md" ] && ok "CLAUDE.md is a symlink in t1" || bad "CLAUDE.md is not a symlink in t1"
[ -L "$WT1/.claude/agents" ] && ok ".claude/agents is a symlink in t1" \
  || bad ".claude/agents is not a symlink in t1"
[ -L "$WT1/node_modules" ] && ok "node_modules is a symlink in t1" \
  || bad "node_modules is not a symlink in t1"
[ -e "$WT1/docs/_local" ] && bad "docs/_local was created in t1 despite not existing in MAIN" \
  || ok "up t1 creates no docs/_local (MAIN has none)"

status_lines="$(git -C "$WT1" status --short | wc -l | tr -d ' ')"
[ "$status_lines" -eq 0 ] && ok "git status --short is empty in t1 (trailing-slash .gitignore does not hide the node_modules symlink, the /node_modules exclude line does)" \
  || bad "git status --short in t1 is not empty ($status_lines lines)"

marker='# worktree.sh: symlink carry set'
count1="$(grep -c "$marker" "$MAIN/.git/info/exclude")"
[ "$count1" -eq 1 ] && ok "info/exclude gained the carry-set marker exactly once" \
  || bad "info/exclude marker count is $count1, want 1"
[ "$(grep -cxF '/CLAUDE.md' "$MAIN/.git/info/exclude")" -eq 1 ] \
  && ok "info/exclude has the anchored /CLAUDE.md line exactly once" \
  || bad "anchored /CLAUDE.md line missing or duplicated"
[ "$(grep -cxF '/.claude/agents' "$MAIN/.git/info/exclude")" -eq 1 ] \
  && ok "info/exclude has the anchored /.claude/agents line exactly once" \
  || bad "anchored /.claude/agents line missing or duplicated"
[ "$(grep -cxF '/node_modules' "$MAIN/.git/info/exclude")" -eq 1 ] \
  && ok "info/exclude has the anchored /node_modules line exactly once (the install-branch dedup helper)" \
  || bad "anchored /node_modules line missing or duplicated"

OUT="$("${WT_SH:-sh}" "$WTSH" up t2 2>&1)"; RC=$?
eq_rc 0 "$RC" "up t2 exits 0"
count2="$(grep -c "$marker" "$MAIN/.git/info/exclude")"
[ "$count2" -eq 1 ] && ok "info/exclude marker still exactly once after a second up" \
  || bad "info/exclude marker count after t2 is $count2, want 1"
[ "$(grep -cxF '/CLAUDE.md' "$MAIN/.git/info/exclude")" -eq 1 ] \
  && ok "anchored /CLAUDE.md still exactly once after a second up (dedup)" \
  || bad "anchored /CLAUDE.md duplicated after a second up"
OUT="$("${WT_SH:-sh}" "$WTSH" down t2 2>&1)"; RC=$?
eq_rc 0 "$RC" "down t2 (teardown) exits 0"

# =====================================================================================================
# docs/_local (machine-local plan/ledger dir, git-excluded) is carried by default: symlinked into
# the worktree, and the worktree's git status stays clean despite the exclude pattern being a bare
# trailing-slash directory pattern in .gitignore (not the anchored info/exclude form).
# =====================================================================================================
mkdir -p docs/_local
printf 'plan\n' > docs/_local/x.md
printf 'docs/_local/\n' >> .gitignore
git add .gitignore
git commit -q -m "ignore docs/_local"

OUT="$("${WT_SH:-sh}" "$WTSH" up t9 --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up t9 (docs/_local fixture) exits 0"
WT9="$MAIN/.claude/worktrees/t9"
[ -L "$WT9/docs/_local" ] && ok "docs/_local is a symlink in t9" \
  || bad "docs/_local is not a symlink in t9"
t9_status="$(git -C "$WT9" status --porcelain)"
[ -z "$t9_status" ] && ok "git status --porcelain is empty in t9 with docs/_local carried" \
  || bad "git status --porcelain in t9 is not empty: $t9_status"
OUT="$("${WT_SH:-sh}" "$WTSH" down t9 --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down t9 --discard (teardown) exits 0"

# =====================================================================================================
# up t1 again fails (path/branch already exist)
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up t1 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "up t1 a second time fails" || bad "up t1 a second time unexpectedly succeeded"

# =====================================================================================================
# down t1 with an unmerged commit refuses (no --merge, no --discard); --discard then removes it
# =====================================================================================================
( cd "$WT1" && printf 'change\n' >> README.md && git commit -q -am "t1 change" )
t1_sha_before="$(git -C "$MAIN" rev-parse refs/heads/t1)"
OUT="$("${WT_SH:-sh}" "$WTSH" down t1 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "down t1 refuses with an unmerged commit (no --merge/--discard)" \
  || bad "down t1 did not refuse despite an unmerged commit"
[ -d "$WT1" ] && ok "worktree t1 still present after the refused down" \
  || bad "worktree t1 was removed despite the refusal"
[ "$(git -C "$MAIN" rev-parse refs/heads/t1)" = "$t1_sha_before" ] \
  && ok "branch t1's sha is unchanged after the refused down" \
  || bad "branch t1's sha changed after a refused down"

OUT="$("${WT_SH:-sh}" "$WTSH" down t1 --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down t1 --discard exits 0"
[ -d "$WT1" ] && bad "worktree t1 still present after --discard" || ok "down t1 --discard removes the worktree dir"
git -C "$MAIN" show-ref --verify --quiet refs/heads/t1 \
  && bad "branch t1 still present after --discard (no --keep-branch)" || ok "down t1 --discard deletes branch t1"
git -C "$MAIN" log --oneline | grep -q "t1 change" \
  && bad "t1's commit reached master via --discard" || ok "t1's discarded commit did not reach master"

# =====================================================================================================
# up tb --base develop, then down tb --merge with no --base: merges into develop, not master;
# develop is pushed, master is untouched
# =====================================================================================================
git -C "$MAIN" branch develop master
git -C "$MAIN" push -q origin develop
develop_sha_before_origin="$(git -C "$BARE" rev-parse refs/heads/develop)"

OUT="$("${WT_SH:-sh}" "$WTSH" up tb --base develop --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up tb --base develop exits 0"
WTB="$MAIN/.claude/worktrees/tb"
[ "$(git -C "$MAIN" config --get branch.tb.worktreeBase)" = "develop" ] \
  && ok "up tb records worktreeBase=develop" || bad "up tb did not record worktreeBase=develop"

( cd "$WTB" && printf 'from tb\n' >> README.md && git commit -q -am "tb change" )
git -C "$MAIN" checkout -q develop
OUT="$("${WT_SH:-sh}" "$WTSH" down tb --merge 2>&1)"; RC=$?
eq_rc 0 "$RC" "down tb --merge (no --base, reads the recorded base) exits 0"
git -C "$MAIN" log --oneline develop -1 | grep -q "tb change" \
  && ok "down tb --merge fast-forwards develop (the recorded base), not master" \
  || bad "develop does not contain tb's commit after --merge"
git -C "$MAIN" log --oneline master | grep -q "tb change" \
  && bad "master was advanced by a merge recorded against develop" \
  || ok "master is untouched by a --merge recorded against develop"
develop_sha_after_origin="$(git -C "$BARE" rev-parse refs/heads/develop)"
[ "$develop_sha_after_origin" != "$develop_sha_before_origin" ] \
  && [ "$develop_sha_after_origin" = "$(git -C "$MAIN" rev-parse develop)" ] \
  && ok "origin's develop was pushed and matches MAIN's develop" \
  || bad "origin's develop was not pushed/updated by down tb --merge"
git -C "$MAIN" checkout -q master

# =====================================================================================================
# down refuses --merge when MAIN is not on base, before any rebase (worktree branch sha unchanged).
# A commit lands on master AFTER `up tc` so that, if a rebase had run under the old (broken) order,
# tc's branch would actually move - proving the sha-unchanged assertion means something.
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up tc --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up tc exits 0"
WTC="$MAIN/.claude/worktrees/tc"
printf 'master moved after up tc\n' > "$MAIN/master-moved-tc.txt"
git -C "$MAIN" add master-moved-tc.txt
git -C "$MAIN" commit -q -m "master moved after up tc"
( cd "$WTC" && printf 'from tc\n' >> README.md && git commit -q -am "tc change" )
tc_sha_before="$(git -C "$WTC" rev-parse HEAD)"
git -C "$MAIN" checkout -q develop
OUT="$("${WT_SH:-sh}" "$WTSH" down tc --merge 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "down tc --merge refuses when MAIN is not on base (master)" \
  || bad "down tc --merge did not refuse with MAIN on the wrong branch"
[ "$(git -C "$WTC" rev-parse HEAD 2>/dev/null)" = "$tc_sha_before" ] \
  && ok "tc's worktree branch sha is unchanged (no rebase ran before the MAIN-on-base check, even though master moved since up tc)" \
  || bad "tc's worktree branch was rewritten despite the refusal"
git -C "$MAIN" checkout -q master
OUT="$("${WT_SH:-sh}" "$WTSH" down tc --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down tc --discard (teardown) exits 0"

# =====================================================================================================
# a moved base: commit lands on master after `up`, then `down --merge` still fast-forwards cleanly
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up td --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up td exits 0"
WTD="$MAIN/.claude/worktrees/td"
printf 'moved on master\n' > "$MAIN/master-moved.txt"
git -C "$MAIN" add master-moved.txt
git -C "$MAIN" commit -q -m "master moved after up td"
git -C "$MAIN" push -q origin master
( cd "$WTD" && printf 'from td\n' > td-change.txt && git add td-change.txt && git commit -q -m "td change" )
OUT="$("${WT_SH:-sh}" "$WTSH" down td --merge 2>&1)"; RC=$?
eq_rc 0 "$RC" "down td --merge exits 0 even though master moved after up td"
git -C "$MAIN" log --oneline -1 | grep -q "td change" \
  && ok "down td --merge fast-forwards master onto the rebased td commit after a moved base" \
  || bad "master does not contain td's commit after a moved-base --merge"

# =====================================================================================================
# up t4, leave uncommitted work: down t4 refuses; commit it, down t4 --keep-branch keeps branch.
# status.showUntrackedFiles=no is set on the WORKTREE's own config (each worktree has its own
# per-worktree config extension) and the dirty file lives in a new subdir, so a plain `git status
# --porcelain` (the default mode) would see NOTHING here - only the script's own
# `--untracked-files=all` override can still catch it. Restored after.
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up t4 --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up t4 exits 0"
WT4="$MAIN/.claude/worktrees/t4"
git -C "$WT4" config status.showUntrackedFiles no
mkdir -p "$WT4/newdir"
printf 'dirty\n' > "$WT4/newdir/dirty.txt"
plain_status="$(git -C "$WT4" status --porcelain)"
[ -z "$plain_status" ] && ok "plant check: the default (non-all) status mode sees nothing here" \
  || bad "plant is broken: default status mode already sees the untracked file: $plain_status"
OUT="$("${WT_SH:-sh}" "$WTSH" down t4 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "down t4 refuses with uncommitted work despite showUntrackedFiles=no (nonzero exit)" \
  || bad "down t4 did not refuse despite uncommitted work"
[ -d "$WT4" ] && ok "worktree t4 still present after the refused down" \
  || bad "worktree t4 was removed despite the refusal"
git -C "$WT4" config --unset status.showUntrackedFiles
( cd "$WT4" && git add newdir/dirty.txt && git commit -q -m "t4 dirty file" )
OUT="$("${WT_SH:-sh}" "$WTSH" down t4 --discard --keep-branch 2>&1)"; RC=$?
eq_rc 0 "$RC" "down t4 --discard --keep-branch exits 0 once clean"
[ -d "$WT4" ] && bad "worktree t4 still present after --keep-branch down" \
  || ok "down t4 --discard --keep-branch removes the worktree dir"
git -C "$MAIN" show-ref --verify --quiet refs/heads/t4 \
  && ok "down t4 --keep-branch leaves branch t4 in place" \
  || bad "branch t4 was deleted despite --keep-branch"
git -C "$MAIN" branch -D t4 >/dev/null 2>&1

# =====================================================================================================
# down refuses when the caller's cwd is inside the worktree being torn down
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up te --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up te exits 0"
WTE="$MAIN/.claude/worktrees/te"
OUT="$(cd "$WTE" && "${WT_SH:-sh}" "$WTSH" down te 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "down te refuses when run from inside the worktree being removed" \
  || bad "down te did not refuse when invoked from inside itself"
[ -d "$WTE" ] && ok "worktree te still present after the refused down" \
  || bad "worktree te was removed despite the cwd refusal"
OUT="$("${WT_SH:-sh}" "$WTSH" down te --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down te --discard (teardown) exits 0"

# =====================================================================================================
# .claude/worktree-carry override: only CLAUDE.md is carried, .claude/agents is not
# =====================================================================================================
printf '# only carry this one\nCLAUDE.md\n' > .claude/worktree-carry
OUT="$("${WT_SH:-sh}" "$WTSH" up t5 --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up t5 (carry override) exits 0"
WT5="$MAIN/.claude/worktrees/t5"
[ -L "$WT5/CLAUDE.md" ] && ok "carry override still symlinks CLAUDE.md" \
  || bad "CLAUDE.md missing from t5 despite being in the override list"
[ -e "$WT5/.claude/agents" ] && bad ".claude/agents was carried despite the override list excluding it" \
  || ok "carry override excludes .claude/agents (not in the override list)"
OUT="$("${WT_SH:-sh}" "$WTSH" down t5 --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down t5 --discard (teardown) exits 0"
rm -f .claude/worktree-carry

# =====================================================================================================
# .claude/worktrees/ itself never shows as untracked noise in MAIN, even with an EMPTY global
# excludes file - up excludes it in MAIN's own info/exclude, so this never depends on the user
# having edited a global file.
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up t6 --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up t6 exits 0"
main_status="$(git -C "$MAIN" status --porcelain)"
[ -z "$main_status" ] && ok "MAIN's git status is empty after up t6, with an empty global excludes file" \
  || bad "MAIN's git status is not empty after up t6 (empty global excludes file): $main_status"
OUT="$("${WT_SH:-sh}" "$WTSH" down t6 --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down t6 --discard (teardown) exits 0"

# =====================================================================================================
# up run from inside an existing worktree resolves MAIN correctly (lands under the main checkout)
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up host --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up host exits 0"
WT_HOST="$MAIN/.claude/worktrees/host"
OUT="$(cd "$WT_HOST" && "${WT_SH:-sh}" "$WTSH" up nested --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up nested (run from inside worktree 'host') exits 0"
[ -d "$MAIN/.claude/worktrees/nested" ] \
  && ok "up run from inside a worktree still lands the new worktree under MAIN's .claude/worktrees" \
  || bad "up run from inside a worktree resolved the wrong MAIN"
OUT="$("${WT_SH:-sh}" "$WTSH" down nested --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down nested --discard (teardown) exits 0"
OUT="$("${WT_SH:-sh}" "$WTSH" down host --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down host --discard (teardown) exits 0"

# =====================================================================================================
# a name containing '/' is refused
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up "feat/x" 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "up refuses a name containing '/'" || bad "up accepted a name containing '/': $OUT"
[ -e "$MAIN/.claude/worktrees/feat" ] && bad "a '/' name partially created a worktree path" \
  || ok "a refused '/' name left no worktree path behind"

# =====================================================================================================
# up --base <a ref that does not resolve> dies and creates nothing
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up tg --base nope 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "up --base nope (unresolvable base) dies" \
  || bad "up --base nope unexpectedly succeeded: $OUT"
[ -e "$MAIN/.claude/worktrees/tg" ] && bad "up --base nope left a worktree path behind" \
  || ok "up --base nope created no worktree path"
git -C "$MAIN" show-ref --verify --quiet refs/heads/tg \
  && bad "up --base nope left branch tg behind" || ok "up --base nope created no branch"

# =====================================================================================================
# up --base --merge (a value that looks like a flag) dies rather than treating --merge as the base
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up th --base --merge 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "up --base --merge dies instead of swallowing the next flag as the base value" \
  || bad "up --base --merge unexpectedly succeeded: $OUT"
[ -e "$MAIN/.claude/worktrees/th" ] && bad "up --base --merge left a worktree path behind" \
  || ok "up --base --merge created no worktree path"

# =====================================================================================================
# plain `down` (no flags) on an untouched worktree succeeds and deletes the branch even while MAIN
# sits on a feature branch that never received base's tip - proving branch delete uses -D, not -d
# (git's own -d would refuse here: tf's tip is not merged into MAIN's current HEAD).
# =====================================================================================================
root_sha="$(git -C "$MAIN" rev-list --max-parents=0 master | tail -n 1)"
git -C "$MAIN" branch feature-x "$root_sha"
git -C "$MAIN" checkout -q feature-x
OUT="$("${WT_SH:-sh}" "$WTSH" up tf --base master --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up tf --base master exits 0 (MAIN currently on unrelated feature-x)"
WTF="$MAIN/.claude/worktrees/tf"
OUT="$("${WT_SH:-sh}" "$WTSH" down tf 2>&1)"; RC=$?
eq_rc 0 "$RC" "down tf (no flags, untouched, MAIN on an unrelated feature branch) exits 0"
[ -d "$WTF" ] && bad "worktree tf still present after down tf" || ok "down tf removed the worktree dir"
git -C "$MAIN" show-ref --verify --quiet refs/heads/tf \
  && bad "branch tf still present after down tf (should have been -D'd)" \
  || ok "down tf deleted branch tf via -D even though MAIN's HEAD never merged it"
git -C "$MAIN" checkout -q master
git -C "$MAIN" branch -D feature-x >/dev/null 2>&1

# =====================================================================================================
# list: assert the script's OWN per-worktree status line ("<path>: <count> status line(s)"), not just
# that t8's path appears anywhere (the plain `git worktree list` output alone would already satisfy
# a bare grep for "t8", even if the per-worktree loop that adds the status-count line were broken).
# =====================================================================================================
OUT="$("${WT_SH:-sh}" "$WTSH" up t8 --no-install 2>&1)"; RC=$?
eq_rc 0 "$RC" "up t8 exits 0"
WT8="$MAIN/.claude/worktrees/t8"
OUT="$("${WT_SH:-sh}" "$WTSH" list 2>&1)"
printf '%s' "$OUT" | grep -qxF "$WT8: 0 status line(s)" \
  && ok "list prints the script's own per-worktree status-count line for t8" \
  || bad "list did not print the per-worktree status-count line for t8: $OUT"
OUT="$("${WT_SH:-sh}" "$WTSH" down t8 --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down t8 --discard (teardown) exits 0"

# =====================================================================================================
# foreign naming shapes (worktrees made by other tools, dir name != branch name): down gates on
# merged-into-base and clean, not on the name match, and deletes the branch actually checked out.
# =====================================================================================================
# plan runner shape: dir plan-<id>, branch <id>, merged into master -> removed, branch <id> deleted
WTS14="$MAIN/.claude/worktrees/plan-S14"
git -C "$MAIN" worktree add -q "$WTS14" -b S14 master
printf 's14\n' > "$WTS14/s14.txt"
git -C "$WTS14" add s14.txt
git -C "$WTS14" commit -q -m "S14 change"
git -C "$MAIN" merge -q --ff-only S14
OUT="$("${WT_SH:-sh}" "$WTSH" down plan-S14 2>&1)"; RC=$?
eq_rc 0 "$RC" "down plan-S14 (dir plan-<id>, branch <id>, merged) exits 0"
[ -d "$WTS14" ] && bad "plan-S14 dir still present" || ok "down plan-S14 removed the dir"
git -C "$MAIN" show-ref --verify --quiet refs/heads/S14 && bad "branch S14 still present" \
  || ok "down plan-S14 deleted the checked-out branch S14"

# harness agent shape: dir agent-<hex>, branch worktree-agent-<hex>, merged -> removed
git -C "$MAIN" worktree add -q "$MAIN/.claude/worktrees/agent-ab12" -b worktree-agent-ab12 master
OUT="$("${WT_SH:-sh}" "$WTSH" down agent-ab12 2>&1)"; RC=$?
eq_rc 0 "$RC" "down agent-ab12 (dir agent-<hex>, branch worktree-agent-<hex>, merged) exits 0"
[ -d "$MAIN/.claude/worktrees/agent-ab12" ] && bad "agent-ab12 dir still present" || ok "down agent-ab12 removed the dir"
git -C "$MAIN" show-ref --verify --quiet refs/heads/worktree-agent-ab12 \
  && bad "branch worktree-agent-ab12 still present" || ok "down agent-ab12 deleted branch worktree-agent-ab12"

# foreign shape with an unmerged commit still refuses, and the branch survives
WTS15="$MAIN/.claude/worktrees/plan-S15"
git -C "$MAIN" worktree add -q "$WTS15" -b S15 master
printf 's15\n' > "$WTS15/s15.txt"
git -C "$WTS15" add s15.txt
git -C "$WTS15" commit -q -m "S15 change"
OUT="$("${WT_SH:-sh}" "$WTSH" down plan-S15 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "down plan-S15 refuses with an unmerged commit" || bad "down plan-S15 removed unmerged work"
git -C "$MAIN" show-ref --verify --quiet refs/heads/S15 && ok "branch S15 survives the refusal" || bad "branch S15 deleted despite refusal"
OUT="$("${WT_SH:-sh}" "$WTSH" down plan-S15 --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down plan-S15 --discard (teardown) exits 0"

# detached shape: HEAD on base -> removed, no branch touched; --merge refuses it
git -C "$MAIN" worktree add -q --detach "$MAIN/.claude/worktrees/det1" master
OUT="$("${WT_SH:-sh}" "$WTSH" down det1 --merge 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "down det1 --merge refuses a detached worktree" || bad "down det1 --merge did not refuse"
OUT="$("${WT_SH:-sh}" "$WTSH" down det1 2>&1)"; RC=$?
eq_rc 0 "$RC" "down det1 (detached, HEAD on base) exits 0"
[ -d "$MAIN/.claude/worktrees/det1" ] && bad "det1 dir still present" || ok "down det1 removed the dir"
git -C "$MAIN" show-ref --verify --quiet refs/heads/master && ok "master untouched by a detached teardown" || bad "master deleted"

# a worktree on the base branch itself: removed, base branch kept (MAIN detached so git allows it)
git -C "$MAIN" checkout -q --detach master
git -C "$MAIN" worktree add -q "$MAIN/.claude/worktrees/onbase" master
OUT="$("${WT_SH:-sh}" "$WTSH" down onbase 2>&1)"; RC=$?
eq_rc 0 "$RC" "down onbase (worktree on the base branch itself) exits 0"
git -C "$MAIN" show-ref --verify --quiet refs/heads/master && ok "base branch kept when the worktree was on it" \
  || bad "down deleted the base branch"
git -C "$MAIN" checkout -q master

# --- review round 1 cases (foreign shapes); most fail against the first draft of this change, the
# onbase-removed, det2-refuses and S18 cases guard against a revert ---
# onbase dir really removed
[ -d "$MAIN/.claude/worktrees/onbase" ] && bad "onbase dir still present" || ok "down onbase removed the dir"

# base spelled another way is still kept: MAIN detached, worktree on master, --base refs/heads/master
git -C "$MAIN" checkout -q --detach master
git -C "$MAIN" worktree add -q "$MAIN/.claude/worktrees/onbase2" master
OUT="$("${WT_SH:-sh}" "$WTSH" down onbase2 --base refs/heads/master 2>&1)"; RC=$?
eq_rc 0 "$RC" "down onbase2 --base refs/heads/master exits 0"
git -C "$MAIN" show-ref --verify --quiet refs/heads/master && ok "base spelled as a full ref is kept" \
  || bad "down deleted master when --base was spelled refs/heads/master"
git -C "$MAIN" checkout -q master

# detached with an unmerged commit refuses
WTD2="$MAIN/.claude/worktrees/det2"
git -C "$MAIN" worktree add -q --detach "$WTD2" master
printf 'd2\n' > "$WTD2/d2.txt"
git -C "$WTD2" add d2.txt
git -C "$WTD2" commit -q -m "det2 change"
OUT="$("${WT_SH:-sh}" "$WTSH" down det2 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "down det2 refuses a detached worktree with an unmerged commit" || bad "down det2 removed unmerged detached work"
printf '%s' "$OUT" | grep -q "detached HEAD was" && ok "down det2 prints the detached sha" || bad "no detached sha printed"

# --base HEAD must not fail open (HEAD resolves in MAIN, not inside the worktree)
OUT="$("${WT_SH:-sh}" "$WTSH" down det2 --base HEAD 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "down det2 --base HEAD still refuses" || bad "down det2 --base HEAD removed unmerged work"
[ -d "$WTD2" ] && ok "det2 still present after refusals" || bad "det2 removed"
OUT="$("${WT_SH:-sh}" "$WTSH" down det2 --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down det2 --discard (teardown) exits 0"

# foreign worktree with a real ignored file refuses; symlinks and node_modules do not count
WTI="$MAIN/.claude/worktrees/plan-S16"
git -C "$MAIN" worktree add -q "$WTI" -b S16 master
printf 'agent notes\n' > "$WTI/CLAUDE.md"
OUT="$("${WT_SH:-sh}" "$WTSH" down plan-S16 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "down plan-S16 refuses with a real ignored file" || bad "down plan-S16 deleted a real ignored file"
printf '%s' "$OUT" | grep -q "CLAUDE.md" && ok "the refusal names the ignored file" || bad "refusal does not name CLAUDE.md"
rm -f "$WTI/CLAUDE.md"
ln -s "$MAIN/CLAUDE.md" "$WTI/CLAUDE.md"
mkdir -p "$WTI/node_modules" && printf 'x\n' > "$WTI/node_modules/x"
OUT="$("${WT_SH:-sh}" "$WTSH" down plan-S16 2>&1)"; RC=$?
eq_rc 0 "$RC" "down plan-S16 passes when ignored entries are only a symlink and node_modules"

# --discard on a foreign branch keeps the branch
WTK="$MAIN/.claude/worktrees/plan-S17"
git -C "$MAIN" worktree add -q "$WTK" -b S17 master
printf 's17\n' > "$WTK/s17.txt"
git -C "$WTK" add s17.txt
git -C "$WTK" commit -q -m "S17 change"
OUT="$("${WT_SH:-sh}" "$WTSH" down plan-S17 --discard 2>&1)"; RC=$?
eq_rc 0 "$RC" "down plan-S17 --discard exits 0"
git -C "$MAIN" show-ref --verify --quiet refs/heads/S17 && ok "--discard keeps a branch up did not create" \
  || bad "--discard deleted foreign branch S17 with unmerged work"
git -C "$MAIN" branch -D S17 >/dev/null 2>&1

# foreign branch reads ITS recorded base: S18 recorded on develop, contained in develop but not master
git -C "$MAIN" checkout -q develop
WTR="$MAIN/.claude/worktrees/plan-S18"
git -C "$MAIN" worktree add -q "$WTR" -b S18 develop
git -C "$MAIN" config branch.S18.worktreeBase develop
printf 's18\n' > "$WTR/s18.txt"
git -C "$WTR" add s18.txt
git -C "$WTR" commit -q -m "S18 change"
git -C "$MAIN" merge -q --ff-only S18
git -C "$MAIN" checkout -q master
OUT="$("${WT_SH:-sh}" "$WTSH" down plan-S18 2>&1)"; RC=$?
eq_rc 0 "$RC" "down plan-S18 uses branch S18's recorded base (develop), not the default"

# --merge on a foreign branch with a same-named tag on an old commit: merges the branch, not the tag
git -C "$MAIN" push -q origin master
WTT="$MAIN/.claude/worktrees/plan-S19"
git -C "$MAIN" worktree add -q "$WTT" -b S19 master
git -C "$MAIN" tag S19 "$root_sha"
printf 's19\n' > "$WTT/s19.txt"
git -C "$WTT" add s19.txt
git -C "$WTT" commit -q -m "S19 change"
OUT="$("${WT_SH:-sh}" "$WTSH" down plan-S19 --merge 2>&1)"; RC=$?
eq_rc 0 "$RC" "down plan-S19 --merge (foreign branch, same-named tag) exits 0"
git -C "$MAIN" log --oneline master | grep -q "S19 change" && ok "--merge merged branch S19, not tag S19" \
  || bad "S19's commit did not reach master (tag won the merge)"
git -C "$MAIN" show-ref --verify --quiet refs/heads/S19 && bad "branch S19 still present after --merge" \
  || ok "down plan-S19 --merge deleted branch S19"
[ "$(git -C "$BARE" rev-parse refs/heads/master)" = "$(git -C "$MAIN" rev-parse master)" ] \
  && ok "down plan-S19 --merge pushed master" || bad "origin master not updated by --merge"
git -C "$MAIN" tag -d S19 >/dev/null 2>&1

# a showUntrackedFiles=no config must not hide a real ignored file, and a spaced name is read whole
WTU="$MAIN/.claude/worktrees/plan-S20"
git -C "$MAIN" worktree add -q "$WTU" -b S20 master
git -C "$MAIN" config status.showUntrackedFiles no
printf 'notes\n' > "$WTU/CLAUDE.md"
OUT="$("${WT_SH:-sh}" "$WTSH" down plan-S20 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "down plan-S20 refuses a real ignored file under showUntrackedFiles=no" \
  || bad "showUntrackedFiles=no hid a real ignored file"
git -C "$MAIN" config --unset status.showUntrackedFiles
rm -f "$WTU/CLAUDE.md"
mkdir -p "$WTU/a b/node_modules" && printf 'x\n' > "$WTU/a b/node_modules/x"
OUT="$("${WT_SH:-sh}" "$WTSH" down plan-S20 --keep-branch 2>&1)"; RC=$?
eq_rc 0 "$RC" "down plan-S20 --keep-branch passes with a spaced path holding node_modules"
git -C "$MAIN" show-ref --verify --quiet refs/heads/S20 && ok "--keep-branch keeps foreign branch S20" \
  || bad "--keep-branch deleted foreign branch S20"
git -C "$MAIN" branch -D S20 >/dev/null 2>&1

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

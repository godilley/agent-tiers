#!/usr/bin/env sh
# kit-scope: shared
# worktree.sh - the one copy of the parallel-Claude-session worktree recipe (up / down / list).
#
# Why: this setup got hand-rolled per project (11 times, with drift) before this script existed -
# machine-local context files (CLAUDE.md, RESUME_SESSION.md, agent-tiers.local.md, skills, agents,
# agent-memory-local) forgotten in the new worktree, per-worktree full dependency installs, the
# carried symlinks themselves showing up as untracked noise, a repo .gitignore edit that had to be
# reverted, teardown one-liners retyped with varying flags, and `git stash` clobbering state across
# worktrees that share one index. This script is the one place that recipe lives now.
#
# Usage (run from anywhere inside a repo - main checkout or an existing worktree):
#   worktree.sh up <name> [--base <ref>] [--no-install]
#   worktree.sh down <name> [--merge] [--discard] [--keep-branch] [--base <ref>]
#   worktree.sh list
#
# down refuses to discard work: it dies if the worktree's branch has any commit not on its base
# (the base recorded at `up` time, or an explicit --base, or the default branch as a last resort)
# unless --discard is passed. <name> is the directory under .claude/worktrees/, whatever branch it
# has checked out: worktrees made by other tools (a plan runner's dir `plan-<id>` on branch `<id>`,
# the harness's dir `agent-<hex>` on branch `worktree-agent-<hex>`) go through the same merged-and-
# clean gate, and the branch checked out there is deleted after removal, except: the base or the
# default branch is never deleted; with --keep-branch nothing is; and for a branch not named <name>
# (one `up` did not create) --discard keeps the branch. Such a "foreign" worktree also refuses when
# it holds ignored files that are real files (not the carry-set symlinks, not node_modules/vendor),
# since `git worktree remove` deletes ignored files silently; --discard overrides. A detached
# worktree passes the same gate on its HEAD commit, prints that sha, and has no branch to delete;
# --merge refuses it. A worktree mid-rebase or mid-bisect always refuses. A squash-merged (or otherwise rewritten) branch still reads as "ahead" here, since its
# commits are literally not on base - only pass --discard for one after confirming the squash
# actually landed, not out of reflex. --merge instead rebases the worktree onto the fetched base
# (falling back to the local base when there is no 'origin' remote, and dying up front if the base
# is not a local branch in MAIN at all), fast-forwards MAIN, and pushes. down also refuses when run
# from a cwd inside the worktree being removed, or when the worktree (or, for --merge, MAIN) has
# uncommitted work. `worktree remove` is never forced - a removal git itself refuses (a lock, for
# instance) is a die, not a retry. The branch delete on a successful teardown is always `branch -D`:
# the ahead gate (or --merge, or --discard) is what already proved it safe, and `git branch -d`'s own
# merge check would otherwise refuse whenever MAIN happens to sit on some other branch that never
# received base's tip - the common case, not an edge case.
#
# MAIN is the first entry of `git worktree list --porcelain` (always the main/original checkout,
# correct even from inside a submodule's or a linked worktree's own .git). Worktree path is always
# $MAIN/.claude/worktrees/<name>; `up` always names the branch <name>. `up` excludes .claude/worktrees/
# itself in MAIN's info/exclude (once, on first use) so no OTHER worktree's directory ever shows up
# as untracked noise in `git status` - this never depends on a global excludes file being edited.
#
# A symlinked node_modules (the npm/package-lock install branch) is SHARED with MAIN - installing
# into it from inside a worktree writes into MAIN's node_modules too. An install failure never kills
# a worktree that was otherwise created fine: it prints WARN and leaves the worktree in place.
#
# POSIX sh only (no arrays, no `local`, no `[[ ]]`) - matches every other script in this dir.
#
# Self-check: worktree.selfcheck.sh
set -u

usage() {
  echo "usage: worktree.sh up <name> [--base <ref>] [--no-install]" >&2
  echo "       worktree.sh down <name> [--merge] [--discard] [--keep-branch] [--base <ref>]" >&2
  echo "       worktree.sh list" >&2
  exit 2
}

die() { echo "worktree.sh: $1" >&2; exit 1; }

require_git_repo() {
  git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"
}

validate_name() {
  case "$1" in
    */*) die "name must not contain '/': $1" ;;
  esac
  git check-ref-format --branch "$1" >/dev/null 2>&1 || die "invalid branch name: $1"
}

# Sets MAIN (the main checkout, always the first entry of `worktree list --porcelain`) and
# EXCLUDE_FILE (MAIN's shared info/exclude, via --git-common-dir so it is correct from any linked
# worktree or submodule gitdir layout, unlike hardcoding "$MAIN/.git/info/exclude").
resolve_main() {
  first_line="$(git worktree list --porcelain 2>/dev/null | sed -n '1p')"
  case "$first_line" in
    "worktree "*) MAIN="${first_line#worktree }" ;;
    *) die "cannot resolve MAIN via git worktree list --porcelain" ;;
  esac
  gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$gcd" ] || die "cannot resolve --git-common-dir"
  EXCLUDE_FILE="$gcd/info/exclude"
}

verify_base() {
  # $1 = a base ref that must resolve to a commit in MAIN (git worktree add / rebase / fetch all
  # give confusing errors of their own otherwise - this names the actual bad value up front).
  git -C "$MAIN" rev-parse --verify -q "$1^{commit}" >/dev/null 2>&1 \
    || die "base does not resolve to a commit in $MAIN: $1"
}

default_base() {
  # $MAIN must already be set.
  ref="$(git -C "$MAIN" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$ref" ]; then
    printf '%s\n' "${ref#origin/}"
    return
  fi
  if git -C "$MAIN" show-ref --verify --quiet refs/heads/master; then
    echo master
    return
  fi
  echo main
}

# $1 = exact line to append to EXCLUDE_FILE, once (dedup helper shared by the marker, every carried
# path, and the node_modules install-branch line).
append_exclude_once() {
  grep -qxF "$1" "$EXCLUDE_FILE" 2>/dev/null || printf '%s\n' "$1" >> "$EXCLUDE_FILE"
}

# Default carry set - one relative path per line. Overridden wholesale by a non-comment line in
# $MAIN/.claude/worktree-carry when that file exists. Carry-file lines are normalised (CR and
# trailing whitespace stripped, leading/trailing slashes stripped) so a stray "/CLAUDE.md/" still
# matches.
default_carry_list() {
  cat <<'EOF'
CLAUDE.md
RESUME_SESSION.md
.claude/settings.local.json
.claude/agent-tiers.local.md
.claude/skills/tier-project-brief
.claude/agents
.claude/agent-memory-local
docs/_local
EOF
}

carry_list() {
  cf="$MAIN/.claude/worktree-carry"
  if [ -f "$cf" ]; then
    grep -v '^[[:space:]]*#' "$cf" | grep -v '^[[:space:]]*$' | sed 's/\r$//; s/[[:space:]]*$//; s:^/*::; s:/*$::'
  else
    default_carry_list
  fi
}

cmd_up() {
  name="${1:-}"
  [ -n "$name" ] || usage
  shift
  validate_name "$name"
  base=""
  no_install=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --base)
        [ $# -ge 2 ] || die "--base requires a value"
        case "$2" in
          -*) die "--base requires a value" ;;
        esac
        base="$2"; shift 2 ;;
      --no-install) no_install=1; shift ;;
      *) die "unknown arg to up: $1" ;;
    esac
  done

  require_git_repo
  resolve_main
  WT="$MAIN/.claude/worktrees/$name"

  [ -e "$WT" ] && die "worktree path already exists: $WT"
  git -C "$MAIN" show-ref --verify --quiet "refs/heads/$name" && die "branch already exists: $name"

  [ -n "$base" ] || base="$(default_base)"
  verify_base "$base"

  mkdir -p "$MAIN/.claude/worktrees" || die "cannot create $MAIN/.claude/worktrees"
  git -C "$MAIN" worktree add "$WT" -b "$name" "$base" || die "git worktree add failed"
  git -C "$MAIN" config "branch.$name.worktreeBase" "$base"

  mkdir -p "$(dirname "$EXCLUDE_FILE")" 2>/dev/null || true
  marker="# worktree.sh: symlink carry set (a trailing-slash pattern never matches a symlink)"
  append_exclude_once "$marker"

  # --- carry set: symlink ignored machine-local files/dirs from MAIN into WT --------------------
  carry_list | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    src="$MAIN/$rel"
    dst="$WT/$rel"
    [ -e "$src" ] || continue
    git -C "$MAIN" check-ignore -q -- "$rel" || continue
    if [ -e "$dst" ]; then
      echo "skip $rel: already exists in worktree"
      continue
    fi
    if ! mkdir -p "$(dirname "$dst")"; then
      echo "skip $rel: cannot create parent dir"
      continue
    fi
    if ! ln -s "$src" "$dst"; then
      echo "skip $rel: symlink failed"
      continue
    fi
    echo "carry: $rel"
    append_exclude_once "/$rel"
  done

  # Every worktree's own directory would otherwise show up as untracked noise in every OTHER
  # worktree's (and MAIN's) `git status` - excluded here, once, through the same dedup helper as the
  # carry lines, instead of depending on the user having edited a global excludes file.
  append_exclude_once "/.claude/worktrees/"

  # --- install ------------------------------------------------------------------------------------
  # Detected from WT's own checked-out base, not MAIN (an older base may lack a lockfile MAIN has
  # since added). The node and composer branches are independent, so a repo with both a lockfile and
  # composer.json (a typical Laravel/Symfony front end) gets both. A failure here WARNs and leaves
  # the already-created worktree in place - it never dies after creation.
  if [ "$no_install" = 1 ]; then
    echo "install: skipped (--no-install)"
  else
    did=0
    warned=0
    if [ -f "$WT/pnpm-lock.yaml" ]; then
      echo "install: pnpm install --frozen-lockfile"
      if ( cd "$WT" && pnpm install --frozen-lockfile ); then
        did=1
      else
        echo "WARN: pnpm install failed in $WT - worktree left in place, fix and re-run manually"
        warned=1
      fi
    elif [ -f "$WT/package-lock.json" ] && [ -d "$MAIN/node_modules" ]; then
      echo "install: symlink node_modules from MAIN (shared with MAIN)"
      if ln -s "$MAIN/node_modules" "$WT/node_modules"; then
        did=1
        append_exclude_once "/node_modules"
      else
        echo "WARN: node_modules symlink failed in $WT"
        warned=1
      fi
    fi
    if [ -f "$WT/composer.json" ] && [ -d "$MAIN/vendor" ]; then
      echo "install: cp -r vendor from MAIN (symlinked vendor breaks composer autoload paths)"
      if cp -r "$MAIN/vendor" "$WT/vendor"; then
        did=1
      else
        echo "WARN: vendor copy failed in $WT"
        warned=1
      fi
    fi
    if [ "$did" = 0 ] && [ "$warned" = 0 ]; then
      echo "install: nothing recognised, skipped"
    fi
  fi

  lines="$(git -C "$WT" status --short | wc -l | tr -d ' ')"
  echo "worktree ready: $WT (branch $name from $base)"
  echo "untracked/modified lines: $lines"
}

cmd_down() {
  name="${1:-}"
  [ -n "$name" ] || usage
  shift
  validate_name "$name"
  merge=0
  keep_branch=0
  discard=0
  base=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --merge) merge=1; shift ;;
      --keep-branch) keep_branch=1; shift ;;
      --discard) discard=1; shift ;;
      --base)
        [ $# -ge 2 ] || die "--base requires a value"
        case "$2" in
          -*) die "--base requires a value" ;;
        esac
        base="$2"; shift 2 ;;
      *) die "unknown arg to down: $1" ;;
    esac
  done

  require_git_repo
  resolve_main
  WT="$MAIN/.claude/worktrees/$name"

  [ -d "$WT" ] || die "worktree does not exist: $WT"

  # Before anything else: refuse from inside the worktree being torn down, and refuse unless $WT
  # really is its own worktree (a stale admin dir, or a path that has fallen through to MAIN via
  # git's discovery walk, would otherwise operate on the wrong tree).
  cur_real="$(pwd -P)"
  wt_real="$(CDPATH= cd "$WT" 2>/dev/null && pwd -P)"
  case "$cur_real" in
    "$wt_real"|"$wt_real"/*) die "refusing: current directory is inside $WT - cd out first" ;;
  esac
  toplevel="$(git -C "$WT" rev-parse --show-toplevel 2>/dev/null)"
  [ "$toplevel" = "$WT" ] \
    || die "refusing: $WT does not resolve to itself as a git worktree (rev-parse --show-toplevel gave '${toplevel:-<none>}')"
  # The branch gated and deleted below is the one checked out, not <name>: other tools name the
  # dir and the branch differently. Empty = detached.
  head_ref="$(git -C "$WT" symbolic-ref -q HEAD 2>/dev/null || true)"
  case "$head_ref" in
    refs/heads/*) branch="${head_ref#refs/heads/}" ;;
    '') branch="" ;;
    *) die "refusing: $WT HEAD is '$head_ref', not a local branch" ;;
  esac
  if [ "$merge" = 1 ] && [ -z "$branch" ]; then
    die "refusing --merge: $WT is detached, there is no branch to merge"
  fi
  for st in rebase-merge rebase-apply BISECT_LOG; do
    [ -e "$(git -C "$WT" rev-parse --git-path "$st" 2>/dev/null)" ] \
      && die "refusing: $WT is mid-rebase or mid-bisect ($st) - finish or abort it first"
  done
  head_sha="$(git -C "$WT" rev-parse --verify -q HEAD 2>/dev/null)" \
    || die "refusing: $WT HEAD does not resolve to a commit"
  [ -n "$branch" ] || echo "detached HEAD was $head_sha"
  foreign=0
  [ "$branch" = "$name" ] || foreign=1

  wt_status="$(git -C "$WT" status --porcelain --untracked-files=all)"
  if [ -n "$wt_status" ]; then
    echo "worktree.sh: refusing, uncommitted work in $WT:" >&2
    printf '%s\n' "$wt_status" >&2
    exit 1
  fi

  # `git worktree remove` deletes ignored files without asking. An `up` worktree's ignored set is the
  # carry-set symlinks into MAIN plus installs, so only a foreign worktree is checked: one whose
  # tool may have written real ignored files (a plan doc, a handoff file, an .env).
  if [ "$foreign" = 1 ] && [ "$discard" = 0 ]; then
    # --untracked-files=normal: a status.showUntrackedFiles=no config would otherwise hide every
    # ignored entry. -z: unquoted paths. matching: the ignored path itself, never a collapsed parent dir.
    ign="$(git -C "$WT" status --porcelain=v1 -z --ignored=matching --untracked-files=normal 2>/dev/null \
      | tr '\0' '\n' | sed -n 's/^!! //p' \
      | while IFS= read -r p; do
          p="${p%/}"
          [ -L "$WT/$p" ] && continue
          case "/$p" in (*/node_modules|*/vendor) continue ;; esac
          printf '%s\n' "$p"
        done)"
    if [ -n "$ign" ]; then
      echo "worktree.sh: refusing, ignored files in $WT would be deleted (use --discard to delete them):" >&2
      printf '%s\n' "$ign" >&2
      exit 1
    fi
  fi

  # Base: an explicit --base wins; else the base `up` recorded; else the default branch, as a last
  # resort, with a note (this is only ever a fallback - `up` always records one).
  recorded_base=""
  [ -n "$branch" ] && recorded_base="$(git -C "$MAIN" config --get "branch.$branch.worktreeBase" 2>/dev/null)"
  if [ -n "$base" ]; then
    :
  elif [ -n "$recorded_base" ]; then
    base="$recorded_base"
  else
    base="$(default_base)"
    echo "no recorded base for ${branch:-$name} and no --base given - falling back to default base $base"
  fi
  verify_base "$base"
  # Resolved once, in MAIN: the same spelling can mean a different commit inside WT (`HEAD`).
  base_sha="$(git -C "$MAIN" rev-parse --verify -q "$base^{commit}")" || die "cannot resolve base $base"
  base_full="$(git -C "$MAIN" rev-parse --symbolic-full-name "$base" 2>/dev/null)"

  if [ "$merge" = 0 ] && [ "$discard" = 0 ]; then
    ahead="$(git -C "$MAIN" rev-list --count "$base_sha..$head_sha" 2>/dev/null)"
    case "$ahead" in ''|*[!0-9]*) die "cannot count commits of ${branch:-detached HEAD} not on $base - refusing" ;; esac
    if [ "$ahead" -gt 0 ]; then
      die "$ahead commit(s) on ${branch:-detached HEAD} not on $base would be discarded - use --merge or --discard (if it was merged upstream, update $base first or pass --base origin/$base)"
    fi
  fi

  if [ "$merge" = 1 ]; then
    # base must be a local branch in MAIN before anything else runs - a --base (or a recorded base)
    # that names a tag, a remote-tracking ref, or a plain commit can satisfy verify_base above but
    # can never be what MAIN's HEAD is compared against or merged into below.
    git -C "$MAIN" show-ref --verify -q "refs/heads/$base" \
      || die "base '$base' is not a local branch in $MAIN - merge $branch into it by hand"

    # MAIN-on-base and MAIN-clean are both checked before anything is rebased, so a doomed --merge
    # never rewrites the worktree branch first.
    main_branch="$(git -C "$MAIN" symbolic-ref --short -q HEAD)"
    if [ "$main_branch" != "$base" ]; then
      die "MAIN is on branch '$main_branch', not '$base' - checkout $base in MAIN before --merge"
    fi
    main_dirty="$(git -C "$MAIN" status --porcelain --untracked-files=all)"
    if [ -n "$main_dirty" ]; then
      echo "worktree.sh: refusing --merge, MAIN has uncommitted changes:" >&2
      printf '%s\n' "$main_dirty" >&2
      exit 1
    fi

    has_origin=0
    git -C "$MAIN" remote get-url origin >/dev/null 2>&1 && has_origin=1

    if [ "$has_origin" = 1 ]; then
      echo "+ git -C \"$MAIN\" fetch origin \"$base\""
      git -C "$MAIN" fetch origin "$base" || die "fetch origin $base failed"
      rebase_target="origin/$base"
    else
      rebase_target="$base"
    fi

    echo "+ git -C \"$WT\" rebase --no-autostash \"$rebase_target\""
    git -C "$WT" rebase --no-autostash "$rebase_target" || die "rebase onto $rebase_target failed"

    echo "+ git -C \"$MAIN\" merge --ff-only --no-autostash \"refs/heads/$branch\""
    git -C "$MAIN" merge --ff-only --no-autostash "refs/heads/$branch" || die "fast-forward merge of $branch failed"
    git -C "$MAIN" merge-base --is-ancestor "refs/heads/$branch" "refs/heads/$base" \
      || die "$branch is not contained in $base after the merge - worktree left in place"

    if [ "$has_origin" = 1 ]; then
      echo "+ git -C \"$MAIN\" push origin \"$base\""
      git -C "$MAIN" push origin "$base" || die "push origin $base failed"
    else
      echo "no 'origin' remote - skipping push"
    fi
  fi

  echo "+ git -C \"$MAIN\" worktree remove \"$WT\""
  err_tmp="$(mktemp)"
  if ! git -C "$MAIN" worktree remove "$WT" 2>"$err_tmp"; then
    cat "$err_tmp" >&2
    rm -f "$err_tmp"
    die "worktree remove failed - a lock or leftover state needs manual attention, see the error above"
  fi
  rm -f "$err_tmp"

  if [ "$keep_branch" = 1 ] || [ -z "$branch" ]; then
    :
  elif [ "refs/heads/$branch" = "$base_full" ] || [ "$branch" = "${base#origin/}" ] \
    || [ "$branch" = "$(default_base)" ]; then
    echo "branch $branch is the base or the default branch - kept"
  elif [ "$foreign" = 1 ] && [ "$discard" = 1 ]; then
    echo "branch $branch was not created by up and --discard was given - kept (delete it by hand if unwanted)"
  else
    # -D, not -d: the ahead gate above (or --merge's own fast-forward, or --discard) is what already
    # proved this safe - git's own -d merge check runs against MAIN's CURRENT HEAD, which refuses
    # whenever MAIN sits on some branch other than base, the common case, not an edge case.
    [ "$foreign" = 1 ] && echo "deleting branch $branch (checked out in $name)"
    echo "+ git -C \"$MAIN\" branch -D \"$branch\""
    git -C "$MAIN" branch -D "$branch" || die "branch delete failed"
  fi
}

cmd_list() {
  require_git_repo
  resolve_main
  git -C "$MAIN" worktree list
  git -C "$MAIN" worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r wt_path; do
    case "$wt_path" in
      "$MAIN"/.claude/worktrees/*)
        n="$(git -C "$wt_path" status --short 2>/dev/null | wc -l | tr -d ' ')"
        echo "$wt_path: $n status line(s)"
        ;;
    esac
  done
}

[ $# -ge 1 ] || usage
sub="$1"; shift
case "$sub" in
  up) cmd_up "$@" ;;
  down) cmd_down "$@" ;;
  list) cmd_list "$@" ;;
  *) usage ;;
esac

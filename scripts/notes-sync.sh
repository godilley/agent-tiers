#!/usr/bin/env bash
# kit-scope: shared
# notes-sync.sh - back up a project's git-ignored dir to a side git ref, from ANY branch,
# WITHOUT touching HEAD or the index. Part of the agent-tiers kit (the "private notes" seam,
# generalised to any git-ignored-but-real content a repo wants machine-local git history for -
# private planning docs by default, or a second --profile for e.g. a mapping engine's working set).
#
# The dir (default docs/_local/) is git-ignored via .git/info/exclude, so it can never be
# staged onto a code branch (no scope bleed) and survives checkout + `reset --hard`. This script
# snapshots it to a side ref (default local/notes) via plumbing - a throwaway index, commit-tree,
# update-ref - so it works even on a dirty tree or mid-merge, and never disturbs your working state.
#
# Config lives in the repo's .git/config (machine-local, per-repo), namespaced per --profile:
#   notes-sync.dir            notes-sync.ref            notes-sync.push           (default profile)
#   notes-sync.<profile>.dir  notes-sync.<profile>.ref  notes-sync.<profile>.push (named profile)
# Default profile keeps dir=docs/_local, ref=local/notes. A named profile has no dir default -
# `setup` requires --dir the first time; ref defaults to local/<profile> unless overridden.
#
# Usage (--profile <name> works before any subcommand, applies to all of them):
#   notes-sync.sh [--profile p] setup [--dir <path>] [--push <remote|local>]
#                                                   one-time per repo/profile: dir + exclude + config
#   notes-sync.sh [--profile p] save  [msg]         snapshot dir -> ref (skips if unchanged)
#   notes-sync.sh [--profile p] push                push ref to the configured remote (no-op if local)
#   notes-sync.sh [--profile p] sync  [msg]         save then push
#   notes-sync.sh [--profile p] restore             extract ref -> dir (fresh clone / recovery)
#   notes-sync.sh [--profile p] status              dir / ref / remote / push policy
#   notes-sync.sh [--profile p] migrate <path>...   move paths into dir (untrack if tracked) then save
#   notes-sync.sh [--profile p] new <slug> [--from <path>]
#                                                   create <date>-<slug>.md in dir (today's real UTC
#                                                   date, never caller-supplied), STATUS: LIVE stub by
#                                                   default, or --from's content with STATUS: LIVE
#                                                   prepended if it lacks one
#
set -euo pipefail

die(){ printf 'notes-sync: %s\n' "$*" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repo"
ROOT="$(git rev-parse --show-toplevel)"
ORIG_PWD="$PWD"  # captured BEFORE the cd below - cmd_new's --from resolves a relative path
                 # against this, not against $ROOT, since the caller invoked from their own cwd
cd "$ROOT"

PROFILE=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   [ $# -ge 2 ] || die "--profile needs a value"; PROFILE="$2"; shift 2;;
    --profile=*) PROFILE="${1#*=}"; shift;;
    *) ARGS+=("$1"); shift;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

if [ -n "$PROFILE" ]; then
  KEY="notes-sync.${PROFILE}"
  DIR_DEFAULT=""
  REF_DEFAULT="local/${PROFILE}"
else
  KEY="notes-sync"
  DIR_DEFAULT="docs/_local"
  REF_DEFAULT="local/notes"
fi

DIR="$(git config --get "${KEY}.dir" || true)";        DIR="${DIR:-$DIR_DEFAULT}"
REF_SHORT="$(git config --get "${KEY}.ref" || true)";  REF_SHORT="${REF_SHORT:-$REF_DEFAULT}"
REF="refs/heads/${REF_SHORT}"
PUSH="$(git config --get "${KEY}.push" || true)";      PUSH="${PUSH:-local}"
EXCLUDE="$(git rev-parse --git-path info/exclude)"

ensure_exclude(){
  local line="${DIR%/}/"
  grep -qxF "$line" "$EXCLUDE" 2>/dev/null && return 0
  # a hand-edited exclude file with no trailing newline would otherwise glue this line onto
  # whatever pattern came before it, silently changing an existing exclude rule
  if [ -s "$EXCLUDE" ] && [ -n "$(tail -c1 "$EXCLUDE")" ]; then printf '\n' >> "$EXCLUDE"; fi
  printf '%s\n' "$line" >> "$EXCLUDE"
}
remote_configured(){ [ -n "$PUSH" ] && [ "$PUSH" != "local" ]; }

cmd_setup(){
  local push="" dir=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --push)   [ $# -ge 2 ] || die "--push needs a value"; push="$2"; shift 2;;
      --push=*) push="${1#*=}"; shift;;
      --dir)    [ $# -ge 2 ] || die "--dir needs a value"; dir="$2"; shift 2;;
      --dir=*)  dir="${1#*=}"; shift;;
      *) die "setup: unknown arg '$1'";;
    esac
  done
  if [ -n "$dir" ]; then DIR="$dir"; fi
  [ -n "$DIR" ] || die "setup: named profile '${PROFILE}' has no dir configured yet - pass --dir <path>"
  git config "${KEY}.dir" "$DIR"
  git config "${KEY}.ref" "$REF_SHORT"
  if [ -n "$push" ]; then git config "${KEY}.push" "$push"; PUSH="$push"; fi
  git config --get "${KEY}.push" >/dev/null 2>&1 || { git config "${KEY}.push" "local"; PUSH="local"; }
  mkdir -p "$DIR"
  ensure_exclude
  # ponytail: no check that REF_SHORT is already another profile's configured ref - `--profile notes`
  # resolves to local/notes and shares the default profile's ref, so the two write alternating trees
  # and each one's `restore` reports the other's tree as empty (opus reviewer 2026-08-23, disclosed
  # rather than fixed: one command, one operator, and the fix wants a config scan this script has no
  # other use for).
  printf 'notes-sync: set up  dir=%s  ref=%s  push=%s\n' "$DIR" "$REF_SHORT" "$(git config --get "${KEY}.push")"
  printf 'notes-sync: %s is git-ignored (.git/info/exclude); it can never land on a code branch.\n' "$DIR"
}

cmd_save(){
  ensure_exclude
  [ -d "$DIR" ] || { printf 'notes-sync: %s does not exist; nothing to save\n' "$DIR"; return 0; }
  local idx tree parent msg commit
  idx="$(mktemp -u)"
  GIT_INDEX_FILE="$idx" git read-tree --empty
  GIT_INDEX_FILE="$idx" git add -f -- "$DIR"          # -f: capture the ignored files
  tree="$(GIT_INDEX_FILE="$idx" git write-tree)"
  rm -f "$idx"
  parent="$(git rev-parse -q --verify "$REF" || true)"
  if [ -n "$parent" ] && [ "$(git rev-parse "${parent}^{tree}")" = "$tree" ]; then
    printf 'notes-sync: no changes in %s\n' "$DIR"; return 0
  fi
  msg="${1:-}"
  [ -n "$msg" ] || msg="notes: sync $(date -u +%FT%TZ) [$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)]"
  if [ -n "$parent" ]; then
    commit="$(printf '%s\n' "$msg" | git commit-tree "$tree" -p "$parent")"
    git update-ref "$REF" "$commit" "$parent"
  else
    commit="$(printf '%s\n' "$msg" | git commit-tree "$tree")"
    git update-ref "$REF" "$commit"
  fi
  printf 'notes-sync: saved %s -> %s (%s)\n' "$DIR" "$REF_SHORT" "$(printf '%s' "$commit" | cut -c1-12)"
}

cmd_push(){
  remote_configured || { printf 'notes-sync: push policy is local; not pushing\n'; return 0; }
  git rev-parse -q --verify "$REF" >/dev/null || die "no $REF to push (run 'save' first)"
  git push "$PUSH" "$REF:$REF"
  printf 'notes-sync: pushed %s -> %s\n' "$REF_SHORT" "$PUSH"
}

cmd_restore(){
  ensure_exclude
  if ! git rev-parse -q --verify "$REF" >/dev/null; then
    if remote_configured; then
      git fetch "$PUSH" "$REF:$REF" || die "cannot fetch $REF from $PUSH"
    else
      die "no $REF locally and push policy is local (nothing to restore)"
    fi
  fi
  mkdir -p "$DIR"
  # tar is this script's one non-git dep; without the check its absence would fall through to the
  # "holds no content" message below - a wrong diagnosis, not a missing-tool report.
  command -v tar >/dev/null 2>&1 || die "tar is required to restore from $REF_SHORT"
  if git archive "$REF" -- "$DIR" 2>/dev/null | tar -x -C "$ROOT"; then
    printf 'notes-sync: restored %s from %s\n' "$DIR" "$REF_SHORT"
  else
    printf 'notes-sync: %s holds no content under %s yet\n' "$REF_SHORT" "$DIR"
  fi
}

cmd_status(){
  local n
  n="$( [ -d "$DIR" ] && find "$DIR" -type f 2>/dev/null | wc -l | tr -d ' ' || echo 0 )"
  printf 'dir:    %s  (%s files)\n' "$DIR" "$n"
  printf 'ref:    %s\n' "$REF_SHORT"
  if git rev-parse -q --verify "$REF" >/dev/null; then
    printf 'head:   %s  %s\n' "$(git rev-parse --short "$REF")" "$(git log -1 --format=%s "$REF")"
  else
    printf 'head:   (none yet - run save)\n'
  fi
  printf 'push:   %s\n' "$PUSH"
  if remote_configured; then
    local r; r="$(git ls-remote --heads "$PUSH" "$REF_SHORT" 2>/dev/null | cut -f1 || true)"
    [ -n "$r" ] && printf 'remote: %s @ %s\n' "$PUSH" "$(printf '%s' "$r" | cut -c1-12)" \
                || printf 'remote: %s  (ref not pushed yet)\n' "$PUSH"
  fi
}

cmd_migrate(){
  [ $# -gt 0 ] || die "migrate: give one or more paths"
  ensure_exclude
  mkdir -p "$DIR"
  local p dest
  for p in "$@"; do
    [ -e "$p" ] || { printf 'notes-sync: skip missing %s\n' "$p"; continue; }
    dest="$DIR/$(basename "$p")"
    # Two sources with the same basename would otherwise silently overwrite each other, and the loser
    # is gone from the working tree without ever reaching the notes ref (cmd_save runs once, after the
    # loop) - the one destructive subcommand in a script whose whole point is not losing notes
    # (opus reviewer, 2026-08-23). Checked BEFORE the untrack below: dying after `git rm --cached`
    # would leave a staged deletion in the REAL index, which this script promises never to touch.
    [ -e "$dest" ] && die "migrate: $dest already exists - move or rename it first"
    if git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
      git rm -r --cached -q -- "$p"                    # untrack (dir-safe), keep working copy
    fi
    mv "$p" "$dest"
    printf 'notes-sync: migrated %s -> %s\n' "$p" "$dest"
  done
  cmd_save "notes: migrate $(date -u +%FT%TZ)"
}

cmd_new(){
  local from="" slug=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --from)   [ $# -ge 2 ] || die "new: --from needs a value"; from="$2"; shift 2;;
      --from=*) from="${1#*=}"; shift;;
      -*) die "new: unknown arg '$1'";;
      *) [ -z "$slug" ] || die "new: unexpected extra argument '$1'"; slug="$1"; shift;;
    esac
  done
  [ -n "$slug" ] || die "new: give a slug"
  case "$slug" in
    */*|*.md) die "new: slug must have no path separators and no .md suffix (got '$slug')";;
  esac
  case "$slug" in
    *[A-Z]*) die "new: slug must be lowercase (got '$slug')";;
  esac
  # The date is ALWAYS computed below, never accepted from the caller - a hand-typed date is the
  # exact bug this subcommand exists to remove, so a leading date in the slug itself is refused
  # rather than silently doubled or silently trusted.
  case "$slug" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*)
      die "new: slug must not include a leading date - the date is computed, never accepted (got '$slug')";;
  esac

  # Unconditional, every call: a repo that never ran 'setup' is exactly the failure mode this
  # subcommand exists to remove - it must not fail under set -euo pipefail on a missing dir, and it
  # must never create a dir that IS tracked by git.
  mkdir -p "$DIR"
  ensure_exclude

  local date dest
  date="$(date -u +%F)"
  dest="$DIR/${date}-${slug}.md"
  [ -e "$dest" ] && die "new: $dest already exists"

  if [ -n "$from" ]; then
    local resolved
    case "$from" in
      /*) resolved="$from";;
      *)  resolved="$ORIG_PWD/$from";;
    esac
    [ -f "$resolved" ] || die "new: --from source not found: $resolved"
    if head -n1 "$resolved" | grep -q '^STATUS:'; then
      cp "$resolved" "$dest"
    else
      { printf 'STATUS: LIVE\n\n'; cat "$resolved"; } > "$dest"
    fi
  else
    printf 'STATUS: LIVE\n\n# %s\n' "${slug//-/ }" > "$dest"
  fi
  printf 'notes-sync: created %s\n' "$dest"
}

[ $# -gt 0 ] || set -- status
sub="$1"; shift
if [ -z "$DIR" ] && [ "$sub" != "setup" ] && [ "$sub" != "-h" ] && [ "$sub" != "--help" ] && [ "$sub" != "help" ]; then
  die "named profile '${PROFILE}' has no dir configured yet - run 'setup --profile ${PROFILE} --dir <path>' first"
fi
case "$sub" in
  setup)   cmd_setup "$@";;
  save)    cmd_save "${1:-}";;
  push)    cmd_push;;
  sync)    cmd_save "${1:-}"; cmd_push;;
  restore) cmd_restore;;
  status)  cmd_status;;
  migrate) cmd_migrate "$@";;
  new)     cmd_new "$@";;
  -h|--help|help) sed -n '2,32p' "$0";;
  *) die "unknown subcommand '$sub' (setup|save|push|sync|restore|status|migrate|new)";;
esac

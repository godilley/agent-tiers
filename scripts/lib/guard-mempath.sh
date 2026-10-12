#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers SHARED library: where a project's auto-memory directory actually lives. SOURCED, not
# executed - a consumer does `. "$(dirname "$0")/lib/guard-mempath.sh"` then calls the functions.
#
# Why this exists: two wired hooks resolved the memory directory two different ways and disagreed
# whenever either mechanism was in play. memory-content-lint.sh honoured `autoMemoryDirectory` but
# knew nothing about the git-repo derivation; resume-inject.sh derived the dir from the git common
# dir's parent but never read `autoMemoryDirectory`. A relocated memory dir could therefore be linted
# but never sized, or sized but never linted. Both files disclosed the gap from their own side and
# neither could close it alone. This is the one definition now, and it is the SUPERSET of the two:
# an explicit `autoMemoryDirectory` wins, and the git-repo derivation is the fallback.
#
# Every function body is a SUBSHELL (`name() ( ... )`), the same structural choice content-rules.sh
# and notify-tag.sh make and for the same reason: a sourced library's variables otherwise persist in
# the calling hook's shell. `guard_mem_in_scope` in particular is called directly as a condition, not
# inside a command substitution, so a `{ ... }` body would leave its locals behind in a live hook. A
# prefix convention would rely on nobody ever picking a colliding name; a subshell cannot leak at all.
# Note the consequence: these bodies `exit`, not `return`.
#
# NOT read, carried forward from the consumers' own disclosures: a `policy` settings scope, a
# `--settings`-supplied file, and `CLAUDE_CODE_PROJECT_DIR_NAME`. None has a fixed on-disk path this
# library can find without the launching CLI's own resolution.
#
# RESIDUAL DIVERGENCE, disclosed rather than fixed: the two consumers pass different project dirs.
# memory-content-lint.sh passes none, so the project and project-local settings files are read only
# when `CLAUDE_PROJECT_DIR` is exported (its pre-existing behaviour, preserved deliberately);
# resume-inject.sh passes its own `$DIR`, which falls back to `$PWD`. Where the host does not export
# `CLAUDE_PROJECT_DIR` and a repo sets `autoMemoryDirectory` in `.claude/settings.json`, the two can
# still disagree. Giving the lint a `$PWD` fallback would widen which settings files it reads, a
# second behaviour change that does not belong in an extraction. "Superset" above means the union of
# the two RESOLUTION MECHANISMS, not that every caller feeds it identical inputs.
#
# ponytail: `autoMemoryDirectory` is treated as the memory directory ITSELF, not as a projects root
# to append a slug to. That is what memory-content-lint.sh's scope gate already assumed (it admits
# anything under the configured path), so this preserves the behaviour that was in force rather than
# inventing a second reading. Upgrade path if that turns out to be backwards: the two callers now
# share one function, so it changes in one place.
#
# Fail-open throughout: a missing jq, an unparseable settings file, or a git too old for
# `--path-format` degrades to the documented fallback rather than erroring.
# Self-check: guard-mempath.selfcheck.sh.

# guard_mem_auto_dir <claude-config-dir> [project-dir]
# Prints the configured autoMemoryDirectory, absolute and without a trailing slash, or nothing.
# Precedence is last-wins across user -> project -> local, the same order context-map.sh reads these
# files in. A `~/` prefix expands against $HOME; any other non-absolute value is discarded rather than
# guessed at.
guard_mem_auto_dir() (
  _gm_cdir="${1:-}"
  _gm_pdir="${2:-${CLAUDE_PROJECT_DIR:-}}"
  command -v jq >/dev/null 2>&1 || exit 0

  _gm_auto=""
  for _gm_sf in "$_gm_cdir/settings.json" "$_gm_pdir/.claude/settings.json" "$_gm_pdir/.claude/settings.local.json"; do
    # An empty config or project dir would otherwise name an absolute path at the filesystem root
    # (`/settings.json`, `/.claude/settings.json`) and read a file no caller intended.
    case "$_gm_sf" in /settings.json | /.claude/*) continue ;; esac
    [ -f "$_gm_sf" ] || continue
    _gm_v="$(jq -r '.autoMemoryDirectory // empty | strings' "$_gm_sf" 2>/dev/null)" || continue
    [ -n "$_gm_v" ] && _gm_auto="$_gm_v"
  done

  case "$_gm_auto" in
    "~/"*) _gm_auto="$HOME/${_gm_auto#'~/'}" ;;
    /*) ;;
    *) _gm_auto="" ;;
  esac
  # A trailing slash would turn "$dir/*" into "...//*", which never matches - see guard_mem_in_scope.
  printf '%s' "${_gm_auto%/}"
)

# guard_mem_dir <claude-config-dir> <project-dir> [auto-dir]
# Prints the auto-memory directory for a project. Pass auto-dir if already resolved, to avoid paying
# for the settings read twice; omit it and this resolves it.
#
# Claude Code shares ONE auto-memory directory per git REPOSITORY - across every worktree and
# subdirectory - so the fallback keys off the git common dir's parent, never off the launch path
# (which differs per worktree). Outside a git repo the project dir is used, which is the documented
# fallback. Edge cases inherited from resume-inject.sh and still not built: a git older than 2.31
# rejects `--path-format` and degrades to the outside-a-repo answer; a submodule or a
# `--separate-git-dir` clone keeps its common dir outside the worktree, so the parent is not the
# repo root.
guard_mem_dir() (
  _gmd_cdir="${1%/}"
  _gmd_pdir="${2:-}"
  if [ "$#" -ge 3 ]; then _gmd_auto="$3"; else _gmd_auto="$(guard_mem_auto_dir "$_gmd_cdir" "$_gmd_pdir")"; fi

  if [ -n "$_gmd_auto" ]; then
    printf '%s' "$_gmd_auto"
    exit 0
  fi

  # An empty project dir must not reach `git -C ""`, which git treats as a no-op and would silently
  # key the derivation off whatever cwd the hook inherited - the exact failure the per-repo rule above
  # exists to avoid.
  _gmd_root="$_gmd_pdir"
  if [ -n "$_gmd_pdir" ]; then
    _gmd_gcd="$(git -C "$_gmd_pdir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
      && [ -n "$_gmd_gcd" ] && _gmd_root="$(dirname "$_gmd_gcd")"
  fi
  _gmd_slug="$(printf '%s' "$_gmd_root" | tr -c 'A-Za-z0-9' '-')"
  printf '%s' "$_gmd_cdir/projects/$_gmd_slug/memory"
)

# guard_mem_in_scope <claude-config-dir> <file-path> [auto-dir]
# Exit 0 if the path lies INSIDE a memory directory. Three independent checks rather than one glob,
# because a relocated CLAUDE_CONFIG_DIR need not be named `.claude` at all: the standard layout, the
# same shape under the configured config dir, and an explicit autoMemoryDirectory.
#
# Every branch matches on a `/` boundary, never a bare prefix: with `autoMemoryDirectory=/h/mem`, a
# bare prefix match would admit `/h/mem-archive/notes.md` and `/h/memories/todo.md` as memory files
# and run the content scan over them. Sibling directories sharing a prefix are the normal case, not a
# contrived one.
guard_mem_in_scope() (
  _gmi_cdir="${1%/}"
  _gmi_path="${2:-}"
  if [ "$#" -ge 3 ]; then _gmi_auto="${3%/}"; else _gmi_auto="$(guard_mem_auto_dir "$_gmi_cdir")"; fi
  [ -n "$_gmi_path" ] || exit 1

  case "$_gmi_path" in */.claude/projects/*/memory/*) exit 0 ;; esac
  [ -n "$_gmi_cdir" ] && case "$_gmi_path" in "$_gmi_cdir"/projects/*/memory/*) exit 0 ;; esac
  [ -n "$_gmi_auto" ] && case "$_gmi_path" in "$_gmi_auto"/*) exit 0 ;; esac
  exit 1
)

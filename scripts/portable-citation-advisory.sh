#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PostToolUse(Write|Edit|MultiEdit) advisory: a portable artifact (a skill, a sub-agent
# definition) must not cite a path that no recipient can open. Citing an untracked or git-ignored path
# there ("see docs/_local/plan.md for the detail") is a reference the reader can never follow, because
# the artifact travels and that local file does not.
#
# Why advisory, not a deny: this is a PostToolUse hook (the write already happened) - it cannot deny,
# only surface a finding as additionalContext, same shape as memory-content-lint.sh.
#
# Scope: only a file whose OWN path marks it as portable - under a skills/ or agents/ directory, or
# named SKILL.md - AND whose path is inside a git repo (below). A memory file (under a memory/
# directory) is NOT in scope: `~/.claude/projects/<slug>/memory/*.md` lives under `~/.claude`, which is
# not a git repo, so the repo-scope gate below would always fail open on it - dropped rather than left
# as permanent fail-open noise. Anything else exits 0 silently before any read.
#
# Out-of-repo limit, disclosed: a portable artifact that is not inside ANY git repo (a global skill at
# `~/.claude/skills/<name>/SKILL.md`, since `~/.claude` itself is not a repo) is out of scope for the
# same reason - this guard cannot resolve a repo root for it, so it exits quietly rather than logging a
# breadcrumb on every write. A memory bucket outside a repo is out of scope for the same structural
# reason, not merely unhandled.
#
# Test: a backticked citation containing "/", not absolute/URL/glob, that exists on disk (relative to
# the artifact's own repo root) but fails `git ls-files --error-unmatch` there. A path that does not
# exist at all is a different problem and produces no finding here (noise, not signal).
#
# Exemption: a citation's OWN LINE saying the reader will generate it or that it is not shipped (case
# insensitive: "not shipped", "kit-local", "never committed", "git-ignored", "this creates", "not
# bundled") - documenting a mechanism the recipient's own copy produces is fine; assuming the content
# already exists for the reader is not.
#
# Ceiling, disclosed: only backticked, non-glob, relative paths are scanned - a citation in prose with
# no backticks, or one spelled with a shell glob, is invisible to this guard.
#
# Kill switch checked before any side effect: .state/off/portable-citation-advisory, resolved from
# KIT_ROOT (the script's own location), never from CLAUDE_CONFIG_DIR - the kill switch lives in the
# kit's own .state and is shared across every Claude profile pointed at this kit; only the flattened
# view follows CLAUDE_CONFIG_DIR. Fail-open on every tooling gap (no jq, not inside a git repo) with a
# breadcrumb, rate-limited to once per session_id (a breadcrumb on every single out-of-repo write is
# fixture-noise the kit already paid for once) - never blocks, never exits non-zero on a finding.
# Self-check: portable-citation-advisory.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s portable-citation-advisory %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

[ -f "${BASE:-}/.state/off/portable-citation-advisory" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }

ARTIFACT="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -n "$ARTIFACT" ] || exit 0

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in *[!A-Za-z0-9._-]* | '.' | '..') SESSION_ID="" ;; esac

# --- scope gate: only a portable artifact ------------------------------------------------------
INSCOPE=0
case "$ARTIFACT" in
  */skills/*|*/agents/*) INSCOPE=1 ;;
esac
[ "$(basename "$ARTIFACT")" = "SKILL.md" ] && INSCOPE=1
[ "$INSCOPE" = 1 ] || exit 0

[ -f "$ARTIFACT" ] || exit 0   # the write may have failed; nothing to lint
[ -r "$ARTIFACT" ] || { note "unreadable: $ARTIFACT"; exit 0; }

FDIR="$(dirname "$ARTIFACT")"
REPO_ROOT="$(git -C "$FDIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  # Rate-limited to once per session: a breadcrumb on every out-of-repo write is fixture-noise the kit
  # already paid for once (MAINT-8). Marker lives under $BASE/.state so it self-cleans with the kit.
  MARKER="${BASE:-${TMPDIR:-/tmp}}/.state/.pca-outofrepo-noted.${SESSION_ID:-nosession}"
  if [ ! -f "$MARKER" ]; then
    mkdir -p "$(dirname "$MARKER")" 2>/dev/null
    : > "$MARKER" 2>/dev/null || true
    note "fail-open: $ARTIFACT not inside a git repo - cannot check citations (further out-of-repo writes this session are silent)"
  fi
  exit 0
fi

FINDINGS_FILE="${TMPDIR:-/tmp}/.pca-findings.$$"
: > "$FINDINGS_FILE"
trap 'rm -f "$FINDINGS_FILE" 2>/dev/null' EXIT

# One line at a time, so an exemption phrase on a line only excuses citations on THAT line.
grep -n -E '`[^`]*/[^`]*`' "$ARTIFACT" 2>/dev/null | while IFS=: read -r _lineno rest; do
  [ -n "$rest" ] || continue
  if printf '%s' "$rest" | grep -qi -e 'not shipped' -e 'kit-local' -e 'never committed' \
       -e 'git-ignored' -e 'this creates' -e 'not bundled'; then
    continue
  fi
  # POSIX extraction (grep -o is a GNU/BSD extension, not POSIX): walk the line with shell parameter
  # expansion, taking one backtick-delimited span at a time - no sed/grep extension needed.
  LINE="$rest"
  while :; do
    case "$LINE" in
      *'`'*'`'*) ;;
      *) break ;;
    esac
    AFTER="${LINE#*\`}"
    p="${AFTER%%\`*}"
    LINE="${AFTER#*\`}"
    printf '%s\n' "$p"
  done | while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      /*) continue ;;        # absolute path: not a "no recipient can open it" citation this scope covers
      *://*) continue ;;     # URL
      *'*'*) continue ;;     # glob
      */*) ;;                # has a slash: candidate
      *) continue ;;
    esac
    [ -e "$REPO_ROOT/$p" ] || continue   # does not exist at all: a different problem, no finding here
    git -C "$REPO_ROOT" ls-files --error-unmatch -- "$p" >/dev/null 2>&1 && continue   # tracked: fine
    printf '%s\n' "$p" >> "$FINDINGS_FILE"
  done
done

# Dedupe, preserving first-seen order.
UNIQ="$(awk '!seen[$0]++' "$FINDINGS_FILE" 2>/dev/null)"
[ -n "$UNIQ" ] || exit 0

FINDINGS="$(printf '%s\n' "$UNIQ" | sed 's/^/  - /')"
CTX="agent-tiers portable-citation-advisory: $(basename "$ARTIFACT") cites path(s) this repo does not track, so no recipient of this artifact can open them:
${FINDINGS}
Advisory only, nothing blocked. Either generalise the reference (drop the untracked path, or point at a tracked one) or mark the line as not bundled / not shipped / kit-local / git-ignored / never committed if the recipient's own copy is expected to produce it."
note "advisory: $(basename "$ARTIFACT") cites untracked path(s): $(printf '%s' "$UNIQ" | tr '\n' ',')"
jq -n --arg c "$CTX" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}' 2>/dev/null || true
exit 0

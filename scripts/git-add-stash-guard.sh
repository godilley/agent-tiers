#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: deny the two git shapes that have already lost real work in
# this environment (2026-08-18). `git add -A`/`--all`/bare `.`/`./`/`:/`/`*` stages EVERY change in
# the worktree, including untracked scratch files an agent dropped nearby for its own use - one of
# those landed in a merge commit. Bare `-u`/`--update` with no pathspec is a NARROWER risk than that
# (it only ever touches files git already tracks, never an untracked scratch file - an earlier
# version of this header claimed otherwise, corrected 2026-09-23) but still stages every tracked
# file's changes worktree-wide, not just the ones this commit means to include, so it stays denied
# on the same "no explicit pathspec" test as `-A`. `git stash` is a SINGLE ref shared by every
# worktree of the same repo (not per-branch, not per-worktree), so a stash taken in one parallel
# session can pop or clear another session's uncommitted work with no warning which session it
# belonged to.
#
# Scope, DENY: `git add -A`/`--all` (bundled short forms like `-Av`/`-vA` too) or bare `-u`/
# `--update` (bundled forms too), each ONLY when no other real pathspec token is present in the same
# invocation; a bare `.`/`./`/`:/`/`*` token ALWAYS denies (that token itself means "everything"),
# quoted or not, UNLESS `-n`/`--dry-run` or `--renormalize` is also present (a dry run stages
# nothing; `--renormalize` only touches already-tracked file line-endings, neither is the
# untracked-scratch-file or unrelated-tracked-edit risk this guard exists for). Every `git stash`
# subcommand except `list`/`show`/`--help`/`-h` -> deny, including bare `git stash` (that is `git
# stash push`'s own shorthand).
# Scope, ALLOW: `git add <path>` (including `-A`/`-u` WITH a real path, `-p <path>`, `-n .`,
# `--renormalize .`, and a path that merely starts with a dot like `.gitignore`, never confused with
# the bare `.` token). `git stash list`/`show`/`--help` (and `-C`-prefixed forms of any of these).
#
# Heredoc bodies are STRIPPED (guard_strip_heredocs), not a stand-down: `git add -A && git commit -m
# "$(cat <<'EOF' ... EOF)"` is exactly the work-loss shape this guard's header names, and a bare
# heredoc bail let it through unseen (guards-review HIGH finding, 2026-09-23). The dangerous-token
# checks (a bare `.`/`./`/`:/`/`*`, a stash subcommand) read each token's REAL VALUE, so a quoted
# form (`git add "."`, `git stash "list"`) is unquoted (one layer of matching `"..."`/`'...'`
# stripped) before comparing - this guard needs the actual argument, not just "is a metacharacter
# present", so it does its own narrow per-token unquote rather than the blanket
# guard_strip_quotes helper (that helper blanks quoted CONTENT, which would hide exactly the quoted
# `"."` this fix exists to catch). A segment that opened a group (a leading `(`/`{`) also has its
# OWN closing `)`/`}` stripped before tokenizing, not just the opener - `(cd x && git add .)`'s last
# token used to arrive as `.)`, which matched nothing (guards-review MEDIUM finding).
#
# Segments are split with guard_split_segments_qsafe, not the quote-BLIND guard_split_segments: a
# one-line commit message containing its own `;`/`&&`/`|` (`git commit -m "docs: WIP; git stash is
# shared"`) used to get sliced mid-string by the plain splitter, and the fragment after that
# accidental split (` git stash is shared"`) matched STASH_FRAG at command position even though it
# was never a real second command (guards-review-2, 2026-09-23, claim 5). qsafe keeps a quoted
# delimiter from ever creating that split, so the whole message stays one segment starting with
# `git commit`, which neither ADD_FRAG nor STASH_FRAG matches. Segment text stays real (qsafe does
# not blank quotes), so the per-token unquote/extraction above is unaffected.
#
# A redirect-shaped token (`>file`, `>>file`, `<file`, `2>&1`, `2>/dev/null`, `&>file`) is excluded
# from the pathspec catch-all before it can count as `haspath` - it used to fall straight into
# the generic "any other token is a real path" bucket, which allowed `git add -A 2>/dev/null` and
# `git add -u 2>&1` straight through as if a real pathspec had scoped them (guards-review-2, claim
# 8). Note `guard_split_segments`'s OWN `&`-splitting (used elsewhere in this kit) can turn `2>&1`
# into a bare `2>` token by the time it reaches this guard's tokeniser in some shapes - the redirect-
# word test matches that split remnant too (`[0-9]*'>'*` covers both `2>&1` and `2>`), so which
# shape it arrives in does not matter.
#
# ponytail: shell-string regex/tokenizing heuristic via the shared guard-cmdpos.sh library, same
# ceilings as every sibling guard (grep-footgun-guard.sh's header lists the general class). Bundled
# short-flag detection is a plain "does this - token contain the letter A/u" test, not real getopt
# parsing - a flag that happens to take a value containing that letter immediately after (git add
# has none that do) would be a false positive, not reachable in practice. `GUARD_GIT_ADD_FRAG` in
# guard-cmdpos.sh stays CMDPOS_GITOPTS-blind (`git -C x add .` is caught HERE but not by hygiene-
# commit-guard.sh/vcs-commit-guard.sh, which both build their OWN narrower add-detection) - a
# shared-library fix belongs to those guards too and is out of scope for this guard's own pass.
# Self-check: git-add-stash-guard.selfcheck.sh.
set -u
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
logdec() {
  SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s git-add-stash-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
command -v jq >/dev/null 2>&1 || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
[ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ] || exit 0
. "$SELFDIR/guard-cmdpos.sh" 2>/dev/null || exit 0
command -v guard_strip_heredocs >/dev/null 2>&1 && command -v guard_split_segments_qsafe >/dev/null 2>&1 || exit 0

CMD_HD="$(guard_strip_heredocs "$CMD")"
SEGMENTS="$(guard_split_segments_qsafe "$CMD_HD")"

REMEDY="stage explicit paths (git add <path>, or interactively yourself with git add -p <path>); park work with a WIP commit instead of a stash; compare with git show HEAD -- <file>."

ADD_FRAG="git[[:space:]]+(${CMDPOS_GITOPTS})*add([[:space:]]|\$)"
STASH_FRAG="git[[:space:]]+(${CMDPOS_GITOPTS})*stash([[:space:]]|\$)"

unquote_tok() {
  t="$1"
  case "$t" in
    \"*\") t="${t#\"}"; t="${t%\"}" ;;
    \'*\') t="${t#\'}"; t="${t%\'}" ;;
  esac
  printf '%s' "$t"
}

# strip_group <seg> -> stdout: <seg> with a leading `(`/`{` stripped, AND a single trailing `)`/`}`
# stripped unconditionally when present - the leading-only strip every OTHER guard in this kit does
# leaves a grouped segment's LAST token with a stray close attached (`.)` instead of `.`). Unlike
# guard_resolve_cwd's own group tracking, this does NOT require the group to have opened on the
# SAME segment: `(cd x && git add .)`  splits into two segments on `&&`, and the `)` that closes the
# group lands on the SECOND segment while the `(` that opened it is on the first - a per-segment
# opener check would miss it. Stripping a trailing `)`/`}` unconditionally (not only when this same
# segment also opened one) is the coarser, correct-in-practice fix: a real add/stash argument ending
# in a literal `)`/`}` as its very last character is not a shape seen in practice, and the guard-
# cmdpos.sh library's own guard_resolve_cwd carries a near-identical accepted ceiling for the same
# reason (see its TODO on a bare `cd` that opens a group).
strip_group() {
  seg="$1"
  bare="$(printf '%s' "$seg" | sed -E 's#^[[:space:]]*[({][[:space:]]*##')"
  bare="$(printf '%s' "$bare" | sed -E 's#[)}][[:space:]]*$##')"
  printf '%s' "$bare"
}

ADD_SEGS="$(guard_segs_at_cmdpos "$SEGMENTS" "$ADD_FRAG")"
DENY=""
if [ -n "$ADD_SEGS" ]; then
  HIT="$(printf '%s\n' "$ADD_SEGS" | while IFS= read -r seg; do
    bare="$(strip_group "$seg")"
    n="$(guard_verb_optspan "$bare" add | wc -l | tr -d ' ')"
    danger=0 haspath=0 hasdashA=0 hasdashu=0 exempt=0 redir=0
    set -f
    for rawtok in $(printf '%s' "$bare" | tr -s '[:space:]' '\n' | grep -av '^[[:space:]]*$' | tail -n +"$((n + 1))"); do
      # a BARE redirect operator token (`>`, `>>`, `&>`, `&>>`, `>&`, `>|`, `<`, optional fd digits)
      # takes the NEXT token as its target, which is never a pathspec: `git add -A > /dev/null` and,
      # once the quote-aware splitter stopped splitting on `&>`/`>|`, `git add -A &> /dev/null` read
      # the target as a path and allowed the add (2026-10-14 review).
      [ "$redir" = 1 ] && { redir=0; continue; }
      case "${rawtok#"${rawtok%%[!0-9]*}"}" in
        ('>'|'>>'|'&>'|'&>>'|'>&'|'>|'|'<') redir=1; continue ;;
      esac
      tok="$(unquote_tok "$rawtok")"
      case "$tok" in
        (-n|--dry-run) exempt=1 ;;
        (--renormalize) exempt=1 ;;
        (.|./|:/|\*) danger=1 ;;
        (-A|--all) hasdashA=1 ;;
        (-u|--update) hasdashu=1 ;;
        (--*) ;;
        (-*)
          case "$tok" in (*A*) hasdashA=1 ;; esac
          case "$tok" in (*u*) hasdashu=1 ;; esac
          ;;
        # a redirect word (>file, >>file, <file, 2>&1, 2>/dev/null, &>file) is not a pathspec - it
        # was previously falling into the catch-all below and counting as haspath, which allowed
        # `git add -A 2>/dev/null`/`git add -u 2>&1` straight through (guards-review-2 claim 8).
        ([0-9]*'>'*|[0-9]*'<'*|'>'*|'<'*|'&>'*) ;;
        (*) haspath=1 ;;
      esac
    done
    set +f
    if [ "$exempt" = 1 ]; then danger=0
    else
      [ "$hasdashA" = 1 ] && [ "$haspath" = 0 ] && danger=1
      [ "$hasdashu" = 1 ] && [ "$haspath" = 0 ] && danger=1
    fi
    [ "$danger" = 1 ] && { echo BAD; break; }
  done)"
  [ "$HIT" = BAD ] && DENY="deny: git add -A/--all/./:/*, or bare -u with no other pathspec, stages every matching change in the worktree - including, for -A/./:/*, untracked scratch files never meant for this commit. $REMEDY"
fi

if [ -z "$DENY" ]; then
  STASH_SEGS="$(guard_segs_at_cmdpos "$SEGMENTS" "$STASH_FRAG")"
  if [ -n "$STASH_SEGS" ]; then
    HIT="$(printf '%s\n' "$STASH_SEGS" | while IFS= read -r seg; do
      bare="$(strip_group "$seg")"
      n="$(guard_verb_optspan "$bare" stash | wc -l | tr -d ' ')"
      rawsub="$(printf '%s' "$bare" | tr -s '[:space:]' '\n' | grep -av '^[[:space:]]*$' | sed -n "$((n + 1))p")"
      sub="$(unquote_tok "$rawsub")"
      case "$sub" in (list|show|--help|-h) : ;; (*) echo BAD; break ;; esac
    done)"
    [ "$HIT" = BAD ] && DENY="deny: git stash is one ref shared by every worktree of this repo - a stash here can pop or clear another parallel session's uncommitted work (observed 2026-08-18). list/show/--help are read-only and stay allowed. $REMEDY"
  fi
fi

[ -n "$DENY" ] || exit 0
logdec "${DENY%%. *}"
jq -n --arg r "$DENY" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0

#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: force the parallel-session worktree recipe through
# scripts/worktree.sh, the ONE mechanism, instead of a hand-rolled `git worktree add/remove`.
# Before worktree.sh existed the recipe (branch name, path under .claude/worktrees, base ref,
# cleanup) was typed out fresh by each session and drifted eleven separate times. A pointer to the
# script in a skill is prose, not enforcement - it does not self-apply, so an agent under time
# pressure retypes the raw git incantation anyway. This hook is what makes worktree.sh the only
# path an ATTACHED (non-detached) worktree can be created through, and denies removal of a
# worktree under .claude/worktrees/, whichever tool made it (worktree.sh down is the paired teardown
# for every naming shape there; a bare `git worktree remove` skips its merged-and-clean gate, its
# ignored-file check and branch cleanup).
#
# Scope: `git worktree add` without --detach/-d on the SAME invocation -> deny (name the remedy).
# `git worktree add --detach`/`-d` is left alone: a detached worktree has no branch to track and no
# teardown decision to make, so it is a disposable review/diff target, not the recipe this guard
# protects. `git worktree remove <path>` -> deny ONLY when <path> is under .claude/worktrees/ (the
# script-managed dir, absolute or relative) - that is the one removal worktree.sh down actually
# knows how to do properly; removing some OTHER path (a detached /tmp review target) has no such
# paired teardown to route through, so denying it unconditionally left the remedy's own "throwaway
# review target" case with no working removal path at all (guards-review MEDIUM finding,
# 2026-09-23) - fixed here. Everything else, including `git worktree list`/`prune`, a `remove` of a
# non-managed path, and the string "worktree" appearing anywhere that is not command position (an
# echo, a comment, worktree.sh's own name), is allowed. A command that invokes worktree.sh itself
# never trips: this hook only pattern-matches `git ... worktree add|remove` at command position,
# and worktree.sh's own `git worktree` calls run INSIDE THE SCRIPT'S OWN PROCESS - no PreToolUse
# hook observes a process's internal exec calls, only the Bash tool invocation that started it
# (corrected 2026-09-23: an earlier version of this comment said those calls "run in a later,
# separate Bash tool call" - true conclusion, wrong mechanism).
#
# Heredoc bodies are STRIPPED (guard_strip_heredocs), not a stand-down - a heredoc'd branch name or
# commit message elsewhere in the same chained command must not hide a real `git worktree add/
# remove` later in the command. Segments are split with guard_split_segments_qsafe, not the quote-
# BLIND guard_split_segments - a one-line commit message containing its own `;`/`&&`/`|` (`git
# commit -m "docs: WIP; git worktree add x"`) would otherwise get sliced mid-string by the plain
# splitter, and the fragment after that accidental split can match WT_ADD_FRAG/WT_REMOVE_FRAG at
# command position even though it was never a real second command (guards-review-2, 2026-09-23,
# claim 5) - qsafe keeps a quoted delimiter from ever creating that split, so the whole message stays
# one segment starting with `git commit`, which neither fragment matches. Segment TEXT stays real
# (qsafe does not blank quotes, only fixes where the boundaries land), so the existing per-segment
# value extraction below is unaffected. Quoted content is ADDITIONALLY blanked (guard_strip_quotes)
# right before the --detach/-d flag scan specifically, so a quoted string that happens to contain
# that literal text cannot force a false match; the path this guard checks for a `remove` deny is
# read from the RAW (qsafe-split, not quote-blanked) segment text, since that check needs the real
# argument value, not just to know a metacharacter is absent - the same "detect vs extract" split
# git-add-stash-guard.sh documents.
#
# ponytail: shell-string regex heuristic via the shared guard-cmdpos.sh library, same ceilings as
# every sibling guard (grep-footgun-guard.sh's header lists them) - a wrapper this library does not
# know (xargs/eval/`sh -c "..."`) hides the invocation from this guard too. The `remove` path check
# is a plain substring test for `.claude/worktrees/` on the first non-flag token after the verb -
# `rm -rf <worktree> && git worktree prune` still gets around the remove deny entirely, same as
# before; the header already accepted that (a guard cannot hold a determined agent, and `prune` is
# allowed on purpose). Self-check: worktree-guard.selfcheck.sh.
set -u

INPUT="$(cat 2>/dev/null || true)"
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
logdec() { # $1 = "deny: ..." | "ask: ..."   (sid parsed HERE, lazily)
  SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s worktree-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
command -v jq >/dev/null 2>&1 || exit 0   # no jq -> can't parse; fail open (never block on tooling gap)
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
[ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ] || exit 0   # fail open: no lib, no split
. "$SELFDIR/guard-cmdpos.sh" 2>/dev/null || exit 0
command -v guard_strip_heredocs >/dev/null 2>&1 && command -v guard_strip_quotes >/dev/null 2>&1 \
  && command -v guard_split_segments_qsafe >/dev/null 2>&1 || exit 0

CMD_HD="$(guard_strip_heredocs "$CMD")"
SEGMENTS="$(guard_split_segments_qsafe "$CMD_HD")"

# CMDPOS_GITOPTS-aware: `git -C <path> worktree add ...` matches the same as bare `git worktree add`.
WT_ADD_FRAG="git[[:space:]]+(${CMDPOS_GITOPTS})*worktree[[:space:]]+add([[:space:]]|\$)"
WT_REMOVE_FRAG="git[[:space:]]+(${CMDPOS_GITOPTS})*worktree[[:space:]]+remove([[:space:]]|\$)"

REMEDY="use ~/.claude/agent-tiers/scripts/worktree.sh up <name> [--base <ref>] or worktree.sh down <name> [--merge|--discard], where <name> is the directory under .claude/worktrees/ whatever its branch (plan-<id>, agent-<hex> and detached worktrees included): down removes it once its checked-out branch is merged into its base (--base, else the recorded one, else the default branch) and the tree is clean, then deletes that branch unless it is the base or the default branch; a throwaway review target may use git worktree add --detach (or -d) and, to tear it down, either git worktree remove <path> directly (a detached target placed outside .claude/worktrees/ is allowed by this guard) or rm -rf <path> && git worktree prune"

unquote_tok() {
  t="$1"
  case "$t" in
    \"*\") t="${t#\"}"; t="${t%\"}" ;;
    \'*\') t="${t#\'}"; t="${t%\'}" ;;
  esac
  printf '%s' "$t"
}

REMOVE_SEGS="$(guard_segs_at_cmdpos "$SEGMENTS" "$WT_REMOVE_FRAG")"
if [ -n "$REMOVE_SEGS" ]; then
  HIT="$(printf '%s\n' "$REMOVE_SEGS" | while IFS= read -r seg; do
    bare="$(printf '%s' "$seg" | sed -E 's|^[[:space:]]*[({][[:space:]]*||')"
    n="$(guard_verb_optspan "$bare" remove | wc -l | tr -d ' ')"
    path=""
    set -f
    for tok in $(printf '%s' "$bare" | tr -s '[:space:]' '\n' | grep -av '^[[:space:]]*$' | tail -n +"$((n + 1))"); do
      case "$tok" in (-*) continue ;; (*) path="$tok"; break ;; esac
    done
    set +f
    path="$(unquote_tok "$path")"
    case "$path" in (*".claude/worktrees/"*) echo BAD; break ;; esac
  done)"
  if [ "$HIT" = BAD ]; then
    logdec "deny: git worktree remove under .claude/worktrees/"
    jq -n --arg r "git worktree remove under .claude/worktrees/ is denied - it skips the merged-and-clean gate, the ignored-file check and the branch cleanup worktree.sh down makes: $REMEDY" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
fi

ADD_SEGS="$(guard_segs_at_cmdpos "$SEGMENTS" "$WT_ADD_FRAG")"
if [ -n "$ADD_SEGS" ]; then
  BAD="$(printf '%s\n' "$ADD_SEGS" | while IFS= read -r seg; do
    nq="$(guard_strip_quotes "$seg")"
    printf '%s' "$nq" | grep -aEq '(^|[[:space:]])(--detach|-d)([[:space:]]|$)' && continue
    echo BAD; break
  done)"
  if [ "$BAD" = BAD ]; then
    logdec "deny: git worktree add without --detach"
    jq -n --arg r "git worktree add without --detach/-d is denied - the hand-rolled recipe drifted eleven times before worktree.sh existed: $REMEDY" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
fi

exit 0

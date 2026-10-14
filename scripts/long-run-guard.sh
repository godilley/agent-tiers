#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: stop the repeated incident (named in two separate project
# docs) where an agent runs a long check/build in a shape that loses the exit code, then strands
# itself polling to recover it: piping pnpm check/pnpm build/a hooked git commit into
# tail/head/grep/etc discards the exit status; the harness auto-backgrounds any Bash call at the
# 120s default tool timeout with no exit code at all; and a while/until + sleep loop written to
# wait until it is done is the loop this guard exists to make unnecessary. The fix is mechanical
# (foreground, unpiped, a timeout ceiling above the command's own real runtime) so it is enforced
# here instead of relying on every brief remembering to say so.
#
# Scope: fires when a chained Bash segment runs pnpm check / pnpm check:* / pnpm build / pnpm
# build:* / pnpm typecheck / pnpm run check|build / pnpm -w|-r|-F|--filter check|build|typecheck
# (pnpm's own option-skipping, same idea as CMDPOS_GITOPTS) / git commit (any CMDPOS_GITOPTS-aware
# form - a hooked commit runs the full check) at command position, and denies when any of:
#   (a) that segment's output is piped into another command (`| tail`, `|& tee`, any consumer -
#       a redirect to a FILE, `2>&1`, `&>`, `>&2`, is fine: only a pipe loses the exit code; none
#       of these shapes end in a bare trailing `&` or contain a bare `|`, so no special-casing is
#       needed to tell them apart from (a)/(b) - see the ponytail note below)
#   (b) the tool call itself has run_in_background true, or the segment ends in a bare `&`
#       (shell backgrounding - the same lost-exit-code shape run_in_background covers)
#   (c) the tool call's timeout is absent or below 600000 (ms)
#   (d) the command is wrapped in a while/until loop that also mentions sleep
# Everything else - other pnpm/git commands, the same commands foreground/unpiped/timed right, a
# `||`/`&&` alternative (the exit code is still read, just branched on), or any of these words
# appearing only inside a quoted string (a commit message's `->`/`|`/`<email>`) - is allowed.
#
# (c) is CONDITIONAL for a git commit segment: it only applies when the repo the commit targets
# actually has a pre-commit hook (core.hooksPath - resolved the way git itself does: `--type=path`
# so `~` expands, joined against the WORKTREE ROOT when relative, never the command's own cwd, since
# githooks(5) runs hooks from the worktree root regardless of where the commit was invoked from - or
# the default .git/hooks path, containing an executable pre-commit) - a two-second commit in a repo
# with no hook would otherwise be denied on every attempt for a runtime that was never at risk. The
# repo is resolved the same way every sibling commit-time guard does (guard_resolve_cwd off a
# preceding cd/-C, else the payload cwd); an unresolvable target is treated the same as "no hook"
# here (skip (c) for that segment) rather than denied, since the thing (c) protects against - a slow
# hooked check silently backgrounded - cannot be assessed without knowing the repo, and (a)/(b)/(d)
# already cover the shapes that don't need that knowledge. A pnpm segment in the SAME command still
# forces (c) unconditionally - the hook carve-out is git-commit-specific, pnpm check/build always
# runs the real work directly.
#
# The repo-resolution walk (guard_commit_seg/guard_resolve_cwd) reads SEGMENTS_RAW - split from the
# heredoc-stripped text WITHOUT quote-blanking - never the quote-blanked SEGMENTS used for the pipe/
# loop/long-command scans below. A quoted cd/-C target (`cd "/repo" && git commit`, `git -C "/repo"
# commit`) would otherwise arrive as `cd ""`/`-C ""` once quotes are blanked, which
# guard_norm_cd_target resolves to $HOME - a RESOLVED (not unresolved) wrong answer, so (c) got
# skipped against $HOME's own hook state instead of the real repo's (guards-review-2, 2026-09-23,
# ADDED finding). SEGMENTS_RAW is split with guard_split_segments_qsafe, not the quote-blind
# guard_split_segments, so a semicolon inside an unrelated quoted commit message earlier in the same
# chained command still cannot manufacture a false extra segment for this walk to trip over.
#
# Heredoc bodies are STRIPPED (guard_strip_heredocs), not a stand-down: this is a policy-boundary
# guard (it exists to stop a specific work-losing incident, the same class guard-cmdpos.sh's own
# header says guard_has_heredoc's stand-down is wrong for), and the harness's own default commit
# shape is `git commit -m "$(cat <<'EOF' ... EOF)"` - a bare `guard_has_heredoc` bail let every
# commit through unchecked. Quoted content is blanked (guard_strip_quotes) before any pipe/loop/
# long-command scan, so a commit message's own `|`/`->`/`<email>` text never trips this guard.
#
# ponytail: (a)/(d) are shell-string regex heuristics, same ceilings as every sibling guard built
# on guard-cmdpos.sh (see its header). (a)'s piping check runs on pipeline chunks (the command
# split only on &&/; - a pipe or a trailing background & intentionally stays attached to its chunk,
# since guard_split_segments's normal &&/;/pipe/& split would break that chunk apart and lose the
# very relationship this check exists to see) and only recognises the target command as the FIRST
# stage of a pipe (the shape that pipes the target's own output away); a target appearing as a
# LATER stage (input piped INTO it) is a different shape and not flagged. A `||` is neutralised
# before the `|`-stage count so `cmd || echo fail` is never counted as piping the exit code away.
# `2>&1`/`&>`/`>&N` need NO special handling under the &&/;-only chunk split and trailing-&-only
# background check: none of those shapes contain a bare `|` (so they cannot inflate the pipe-stage
# count) and none of them END a chunk in a bare `&` (the digit/`>`/target after the `&` is always
# the last character, not `&` itself), so they read through untouched either way. An earlier version
# of this file neutralised them to a placeholder before this split anyway; guards-review-2
# (2026-09-23, claim 11) traced every input against the current &&/;-only chunking and trailing-&-
# only background check and found none where that neutralisation changed the verdict - dead code,
# removed here rather than kept as a comforting no-op (a selfcheck case proving it dead, not just
# passing either way, sits alongside the removal).
# (d) is coarse by construction: it does not verify the loop actually wraps the target command,
# only that while/until and sleep both appear somewhere in the same tool call alongside a target
# command - a real parser would be needed to bind them precisely, and a false positive here just
# asks for the same foreground-with-timeout shape the guard wants anyway. The hook check for (c)
# only looks at the FIRST git commit segment (guard_commit_seg's own convention, shared by every
# commit-time guard in this kit) - a second chained commit targeting a different repo is not
# separately assessed. The pnpm option-skip does not know a wrapper like `npx pnpm check` or
# `corepack pnpm check` - that would mean widening CMDPOS_PREFIX's own wrapper list, a shared-
# library change with every OTHER guard in this kit as a blast radius, out of scope for a single
# guard's fix pass. `pnpm --filter X build` where X itself contains a space (`--filter "my pkg"
# build`) is not recognised - same "value atom cannot span a space" ceiling guard-cmdpos.sh already
# discloses for its own GITOPTS matching. Self-check: long-run-guard.selfcheck.sh.
set -u

INPUT="$(cat 2>/dev/null || true)"
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
logdec() {
  SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s long-run-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
command -v jq >/dev/null 2>&1 || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
[ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ] || exit 0
. "$SELFDIR/guard-cmdpos.sh" 2>/dev/null || exit 0
command -v guard_strip_heredocs >/dev/null 2>&1 && command -v guard_strip_quotes >/dev/null 2>&1 \
  && command -v guard_split_segments_qsafe >/dev/null 2>&1 || exit 0

# Strip heredoc bodies (keep the opener, drop the content - see header), then blank quoted content.
# The pipe/loop/long-command scans below read CMD_P (quote-blanked, so a commit message's own text
# cannot false-trip them); the repo-resolution walk further down reads SEGMENTS_RAW instead (real
# quoted values intact, so a quoted cd/-C target resolves to the real repo, not $HOME - see header).
CMD_HD="$(guard_strip_heredocs "$CMD")"
CMD_NQ="$(guard_strip_quotes "$CMD_HD")"
CMD_P="$CMD_NQ"

# Any pnpm flag may sit between `pnpm` and the verb: the named ones, plus a generic `-x` and a generic
# `--x [value]` (the value branch is optional so `--silent build` still reaches the verb). Before
# 2026-10-01 only the named flags were known, so `pnpm -s check | tail` slipped past this guard while
# simple-rules-guard's Rule E (since removed in favour of this one copy) still caught it.
PNPM_OPT="(run|-w|-r|--filter=[^[:space:]]+|--filter[[:space:]]+[^[:space:]]+|-F[[:space:]]+[^[:space:]]+|-F=?[^[:space:]]+|-[^[:space:]-][^[:space:]]*|--[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)"
PNPM_FRAG="pnpm[[:space:]]+(${PNPM_OPT}[[:space:]]+)*(check(:[A-Za-z0-9_:-]+)?|build(:[A-Za-z0-9_-]+)?|typecheck)([[:space:]]|\$)"
LONGCMD_FRAG="(${PNPM_FRAG}|${CMDPOS_COMMIT_FRAG})"

SEGMENTS="$(guard_split_segments "$CMD_P")"
FOUND_SEGS="$(guard_segs_at_cmdpos "$SEGMENTS" "$LONGCMD_FRAG")"
[ -n "$FOUND_SEGS" ] || exit 0

# Pipeline CHUNKS: split only on &&/; - a pipe or a trailing background & stays attached to its own
# chunk, which is exactly the relationship (a) and the background half of (b) need to see.
CHUNKS="$(printf '%s\n' "$CMD_P" | awk '{ gsub(/&&|;/, "\n"); print }')"
PIPED=0
BACKGROUND=0
HIT="$(printf '%s\n' "$CHUNKS" | while IFS= read -r chunk; do
  bare="$(printf '%s' "$chunk" | sed -E 's|^[[:space:]]*[({][[:space:]]*||')"
  protected="$(printf '%s' "$bare" | sed 's/||/@OR@/g')"
  first="$(printf '%s' "$protected" | awk -F'|' '{print $1}')"
  nstages="$(printf '%s' "$protected" | awk -F'|' '{print NF}')"
  printf '%s' "$first" | grep -aEq "${CMDPOS_PREFIX}${LONGCMD_FRAG}" || continue
  if [ "${nstages:-1}" -gt 1 ]; then echo PIPE; break; fi
  trimmed="$(printf '%s' "$bare" | sed -E 's/[[:space:]]+$//')"
  case "$trimmed" in (*'&') echo BG; break ;; esac
done)"
case "$HIT" in
  PIPE) PIPED=1 ;;
  BG) BACKGROUND=1 ;;
esac

LOOP_SLEEP=0
if printf '%s' "$CMD_P" | grep -aEq '(^|[^A-Za-z0-9_])(while|until)([^A-Za-z0-9_]|$)' \
  && printf '%s' "$CMD_P" | grep -aEq '(^|[^A-Za-z0-9_])sleep([^A-Za-z0-9_]|$)'; then
  LOOP_SLEEP=1
fi

RUNBG="$(printf '%s' "$INPUT" | jq -r 'if .tool_input.run_in_background == true then "1" else "0" end' 2>/dev/null || echo 0)"

TIMEOUT="$(printf '%s' "$INPUT" | jq -r '.tool_input.timeout // empty' 2>/dev/null || true)"
TIMEOUT_BAD=0
case "$TIMEOUT" in
  '' | *[!0-9]*) TIMEOUT_BAD=1 ;;
  *) [ "$TIMEOUT" -ge 600000 ] || TIMEOUT_BAD=1 ;;
esac

# Does (c) even apply to what was found? Unconditional the moment a pnpm target is present;
# conditional on an actual pre-commit hook when the only target found is a git commit.
PNPM_SEGS="$(guard_segs_at_cmdpos "$SEGMENTS" "$PNPM_FRAG")"
TIMEOUT_APPLIES=0
[ -n "$PNPM_SEGS" ] && TIMEOUT_APPLIES=1

if [ "$TIMEOUT_APPLIES" = 0 ]; then
  SEGMENTS_RAW="$(guard_split_segments_qsafe "$CMD_HD")"
  COMMIT_SEG="$(guard_commit_seg "$SEGMENTS_RAW")"
  if [ -n "$COMMIT_SEG" ] && command -v git >/dev/null 2>&1; then
    PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
    REPO="$PAYLOAD_CWD"
    [ -n "$PAYLOAD_CWD" ] && REPO="$(guard_resolve_cwd "$SEGMENTS_RAW" "$CMDPOS_COMMIT_FRAG" "$PAYLOAD_CWD")"
    if [ -n "$REPO" ] && ! guard_cwd_unresolved "$REPO"; then
      HOOKSPATH="$(git -C "$REPO" config --type=path --get core.hooksPath 2>/dev/null || true)"
      HOOKDIR=""
      if [ -n "$HOOKSPATH" ]; then
        case "$HOOKSPATH" in
          /*) HOOKDIR="$HOOKSPATH" ;;
          # githooks(5): a relative hooksPath is relative to the WORKTREE ROOT, never the cwd the
          # commit happened to run from - a commit invoked from a subdirectory must not join this
          # against that subdirectory (guards-review MEDIUM finding, 2026-09-23).
          *) TOPLEVEL="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || true)"
             [ -n "$TOPLEVEL" ] && HOOKDIR="$TOPLEVEL/$HOOKSPATH" ;;
        esac
      else
        GP="$(git -C "$REPO" rev-parse --git-path hooks 2>/dev/null || true)"
        if [ -n "$GP" ]; then
          case "$GP" in /*) HOOKDIR="$GP" ;; *) HOOKDIR="$REPO/$GP" ;; esac
        fi
      fi
      [ -n "$HOOKDIR" ] && [ -x "$HOOKDIR/pre-commit" ] && TIMEOUT_APPLIES=1
    fi
    # unresolved repo or no git: TIMEOUT_APPLIES stays 0 for this commit - (a)/(b)/(d) still cover it.
  fi
fi

REMEDY="run it foreground, no pipe, timeout: 900000 on the tool call, and read the exit code directly - never pipe (| or |&) into another command, never run_in_background or a trailing & background operator, never poll it in a while/until+sleep loop."

REASON=""
if [ "$RUNBG" = 1 ]; then
  REASON="deny: run_in_background on a long check/build/commit would return a shell id instead of an exit code. $REMEDY"
elif [ "$PIPED" = 1 ]; then
  REASON="deny: a pipe discards the exit code; run it foreground and read \$?. $REMEDY"
elif [ "$BACKGROUND" = 1 ]; then
  REASON="deny: a trailing & backgrounds a long check/build/commit the same way run_in_background does - no exit code is ever read. $REMEDY"
elif [ "$LOOP_SLEEP" = 1 ]; then
  REASON="deny: a while/until+sleep loop around a long check/build/commit is exactly the stranded-polling shape this guard exists to prevent. $REMEDY"
elif [ "$TIMEOUT_APPLIES" = 1 ] && [ "$TIMEOUT_BAD" = 1 ]; then
  REASON="deny: a long check/build/commit needs timeout >= 600000 on the tool call, or the harness auto-backgrounds it at 120000ms with no exit code. $REMEDY"
fi

[ -n "$REASON" ] || exit 0
logdec "${REASON%%. *}"
jq -n --arg r "$REASON" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0

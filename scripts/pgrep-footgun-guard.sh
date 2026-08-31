#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: catch `pgrep -f`/`pkill -f`/`--full` before they run.
#
# Why it exists: this harness runs every Bash tool call wrapped through an `eval` of the FULL command
# text (confirmed live, 2026-08-24: a captured tool_input showed
# `eval 'pgrep -fa "scripts/agent-tiers-share" ; ...'` as the literal wrapping process argv). `pgrep -f`
# searches every process's full command line, and that wrapping process's command line will very often
# CONTAIN the search pattern, because the pattern is typically a substring of the very
# `pgrep -f PATTERN` text being run. So a `pgrep -f` call structurally TENDS to match its own ancestor
# shell (not universally - a pattern that only matches after shell expansion, an anchored `^` pattern,
# `-x`/exact-match, or a `-u <other-uid>` filter can all avoid it - but the deny stays blanket since an
# agent can't tell which case it's in, and a redirected agent loses nothing in the rare cases it would
# have been fine). Two symptoms seen repeatedly in real transcripts (agentsview search, 2026-08-24): a
# one-shot `pgrep -f X; echo $?` that reports "found" even after X already exited, and a
# `while pgrep -f X; do sleep N; done`-shaped wait that can never observe "not found" because the loop's
# own process line matches every iteration. `pkill -f` shares the same ancestor-match mechanism with a
# worse outcome: it can SIGTERM the very shell that invoked it.
#
# The fix is never a smarter pattern - it's not polling process existence at all:
#   - a `run_in_background` Bash call already sends exactly ONE notification when it exits; just wait
#     for that instead of polling for it
#   - Monitor exists for the recurring-event case (log lines, file changes)
#   - a genuine synchronous wait should check the OUTCOME (grep a log for a completion marker, test a
#     sentinel file the job writes on exit, `wait $!` on a job started in the same shell) not whether a
#     process with a matching name/cmdline still exists
#   - checking an unrelated system service (postgres, nginx) is NOT what this guard is about and isn't
#     blocked by name: `pgrep nginx` (no -f) is allowed, or use `systemctl is-active <svc>`
#
# Scope: fires on `pgrep`/`pkill` at command position (guard_at_command_position from guard-cmdpos.sh,
# plus a local second arm for the chained `until !`/`if !` keyword shape its single keyword slot still
# misses - see guard-cmdpos.sh's own documented gap) carrying -f/--full or a bundled short flag
# containing f (`-fa`, `-af`, ...). Bare `pgrep name` (no -f) is left alone - it matches only the
# process NAME, which is "bash"/"sh" for the wrapping shell, not the search pattern, so it doesn't
# self-match the same way. Fail-open on any tooling gap. Self-check: pgrep-footgun-guard.selfcheck.sh.
#
# ponytail: regex heuristic on shell strings, not a real parser - known ceilings, same shape as
# grep-footgun-guard's. A pattern that only contains an option-like substring in quotes
# (`pgrep -l "python -f"`) can misfire (errs toward deny, safe). A wrapper command outside
# CMDPOS_PREFIX's known list (sudo/command/env/time/nohup/bash/sh/timeout) is not caught. Upgrade path:
# only if real misses bite - widen CMDPOS_PREFIX's keyword slot kit-wide instead of adding more local
# second arms here.
set -u

INPUT="$(cat 2>/dev/null || true)"
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
logdec() {
  SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s pgrep-footgun-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
command -v jq >/dev/null 2>&1 || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

case "$CMD" in *'<<'*) exit 0 ;; esac   # heredoc body, not a live invocation (ponytail carve-out)

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
[ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ] || exit 0
. "$SELFDIR/guard-cmdpos.sh" 2>/dev/null || exit 0
SEGMENTS="$(guard_split_segments "$CMD")"

HIT="$(printf '%s\n' "$SEGMENTS" | while IFS= read -r seg; do
  s() { printf '%s' "$seg" | grep -aEq "$1"; }
  # p(grep|kill) must be the command RUN at this segment's start - not an arg to echo/cat/a heredoc
  # body. guard_at_command_position (the shared lib helper, not a hand-rolled prefix) already covers
  # $(/backtick command-substitution anchors and a single if/until/while/do/else/then/! keyword plus
  # sudo/command/env/time/nohup/bash/sh/timeout wrappers and a path prefix. Its ONE keyword slot still
  # misses a CHAINED keyword+! (`until ! pgrep`, `if ! pgrep`) - documented gap in guard-cmdpos.sh - so
  # a second local arm covers that shape until the shared lib's slot is widened kit-wide.
  guard_at_command_position "$seg" 'p(grep|kill)([[:space:]]|$)' \
    || s '(^|\$\(|`)[[:space:]]*(until|while|if|elif)[[:space:]]+![[:space:]]*(command[[:space:]]+)?(/[A-Za-z0-9_./-]*/)?p(grep|kill)([[:space:]]|$)' \
    || continue
  s '(--full|(^|[[:space:]])-[A-Za-z]*f)' || continue                          # -f/--full present
  echo BAD; break
done)"
[ "$HIT" = BAD ] || exit 0

logdec "deny: pgrep -f self-match footgun"
REASON="pgrep/pkill -f match the FULL command line of every process, including the shell wrapping this very call - the search pattern is structurally likely to be a substring of the wrapper's own argv, so this can match its own ancestor regardless of whether the real target is still alive (pkill -f is worse: it can SIGTERM that ancestor). Don't poll for it: a run_in_background Bash call already notifies once on exit, Monitor covers recurring events, and a genuine synchronous wait should check a log marker or sentinel file, not process existence. Checking an unrelated system service instead? Use a name match (plain 'pgrep name', allowed here) or 'systemctl is-active <svc>' - neither reads the caller's own command line."
jq -n --arg r "$REASON" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0

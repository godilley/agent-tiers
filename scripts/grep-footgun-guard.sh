#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: catch the documented GNU-grep footgun before it runs.
# GNU grep used RECURSIVELY without -a/--text silently skips files it deems binary (trigger is
# NUL/invalid bytes, NOT plain CJK text - probe, GNU grep 3.12: `printf '<CJK> needle\n'` matches as
# text; `printf 'needle\0\n'` and `printf 'needle \xff\n'` both report "binary file matches", i.e.
# are skipped silently under -r without a match), returning wrong-but-quiet results. This is a global CLAUDE.md landmine
# that sub-agents (which don't carry that memory) kept tripping - hence a hook, not per-brief text,
# so the ONE mechanism covers every agent type AND the Lead.
#
# Scope: fires ONLY on recursive grep/egrep/fgrep lacking a text-neutralizing flag. Skips rg/ag,
# `git grep` (honours .gitattributes, safe), and piped `... | grep` (reads stdin, never files, and
# isn't recursive anyway). On match -> permissionDecision deny + guidance, so the agent self-corrects
# to `rg` (or adds -a) with no human prompt. Non-recursive `grep pat file` is left alone (low-risk,
# common in pipes).
#
# ponytail: shell-string regex heuristic, not a real parser. Known ceilings: matches only grep run at a
# pipeline-segment START (after `command `/path), so grep behind a wrapper (xargs/sudo/time/eval) or in
# a heredoc body is NOT caught - accepted, keeps `echo "grep -r ..."`-style false positives out; a `-r`
# pattern containing a pipe (`grep -rE "a|b" .`) gets split but a fragment still starts with grep+`-r`
# so it errs toward deny (safe); and a recursive grep on a genuinely-ASCII tree is nudged unnecessarily
# (accepted - `grep -r` without -a is footgun-prone regardless). Upgrade path: only if misses bite, add
# known wrappers to the prefix. Self-check: grep-footgun-guard.selfcheck.sh.
set -u

INPUT="$(cat 2>/dev/null || true)"
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
# Decision line (Wave D, 2026-08-16): guards.log is THE durable human record of blocks (HOST-4 - under
# cc-gui / -p nobody sees a deny), so every deny/ask logs `<ts> <guard> deny|ask: <text> [sid=<id>]`;
# the SessionEnd summary and doctor count these lines by session id.
logdec() { # $1 = "deny: ..." | "ask: ..."   (sid parsed HERE, lazily)
  SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s grep-footgun-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
command -v jq >/dev/null 2>&1 || exit 0   # no jq -> can't parse; fail open (never block on tooling gap)
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

# Heredoc present -> this is writing a file/feeding stdin, not running grep. Stand down: heredoc bodies
# carry real newlines that the per-line split below would misread as grep invocations. (ponytail carve-out)
case "$CMD" in *'<<'*) exit 0 ;; esac

# Judge PER PIPELINE SEGMENT so a recursive flag on some OTHER command (`ls -R | grep foo`) or an rg
# in the pipe (`rg -r .. | grep bar`) can't be misattributed to grep. Split via the SHARED
# guard-cmdpos.sh library (the inline sed copy this replaced was a GNU-ism that glued chained
# segments together on macOS - cold-review F3, 2026-08-10; the lib also guarantees the trailing
# newline the read loop below needs). Matching uses grep -aE on SHELL STRINGS (never files), so the
# guard can't footgun itself. The token boundary is start-or-non-word, which excludes ripgrep
# ("...pgrep", preceded by a letter).
SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
[ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ] || exit 0   # fail open: no lib, no split
. "$SELFDIR/guard-cmdpos.sh" 2>/dev/null || exit 0
SEGMENTS="$(guard_split_segments "$CMD")"

HIT="$(printf '%s\n' "$SEGMENTS" | while IFS= read -r seg; do
  s() { printf '%s' "$seg" | grep -aEq "$1"; }
  s '^[[:space:]]*git[[:space:]]+grep([[:space:]]|$)' && continue               # git grep: safe
  # grep must be the command RUN in this segment (at its start, after optional `command `/path prefix) -
  # NOT an arg to echo/cat/a heredoc body. That drops "echo 'grep -r ...'" style false positives.
  s '^[[:space:]]*(command[[:space:]]+)?(/[A-Za-z0-9_./-]*/)?(e|f)?grep([[:space:]]|$)' || continue
  s '(--recursive|(^|[[:space:]])-[A-Za-z]*[rR])' || continue                  # not recursive: safe
  s '(--text|--binary-files=text|(^|[[:space:]])-[A-Za-z]*a)' && continue      # -a/--text present: safe
  echo BAD; break
done)"
[ "$HIT" = BAD ] || exit 0

logdec "deny: recursive grep without -a"
REASON="Recursive GNU grep without -a/--text silently skips files it deems binary (NUL/invalid bytes; plain CJK is fine) - documented CLAUDE.md footgun. Re-run with 'rg' (preferred) or add '-a' to grep."
jq -n --arg r "$REASON" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0

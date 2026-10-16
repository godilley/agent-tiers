#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Write|Edit|MultiEdit|Bash) gate: a new memory file, or an Edit that adds a new
# fact to one, must be preceded by a coverage check and a question to the operator (cards/MEMORY.md
# MEMORY-5).
#
# Why this exists as a hook and not as the rule it already was: MEMORY-5 was written as prose on
# 2026-09-17 carrying its own falsifier - "if the next several observed memory writes go in without the
# pause, this drops to hook-or-nothing". The next memory write skipped the pause the same day. A prose
# rule has no arrival event: it is checked only if someone remembers to check it, and the thing being
# checked is the same mind that is supposed to remember. This is that arrival event.
#
# DENY, never ask (HOST-4: a guard enforcing a FORM denies and names the fix; it asks only for a human
# decision). A hook cannot raise an AskUserQuestion itself, and it does not need to: it denies once, the
# denial names the two things needed, and the retry carrying them is allowed. Cost is one extra turn on
# a genuinely new memory, and zero on a memory that already exists somewhere - the coverage check is
# what finds that out. This is the answer to memory-content-lint.sh's own recorded objection (its header
# lines 8-10) that a write-time approval gate would fight the system prompt's "write memory directly":
# the gate is not standing, it fires once per new fact and its remedy is one turn.
#
# WHAT COUNTS AS SATISFIED, both required, both looked for in the CURRENT window (see below):
#  1. a coverage check - a Read/Grep/Glob tool_use whose input names the memory directory
#  2. an AskUserQuestion tool_use
#
# WHY TOOL_USE AND NOT TEXT. The check is structural (a real tool_use block, confirmed with jq), never a
# substring scan, and the reason is specific: THIS GUARD'S OWN DENIAL REASON CONTAINS THE MEMORY
# DIRECTORY PATH, and that reason is written into the transcript. A text-level scan would therefore see
# the path, count it as a coverage check, and allow the very next retry - the gate would pass every
# second attempt and nobody would notice, because a passing gate is silent. Same class as the
# review-gate-guard defect where a pasted-JSON line containing `"role":"assistant"` passed for a real
# assistant message until the structural re-validation was added.
#
# THE WINDOW is "since the last user message carrying a non-empty text block", not "since the last user
# message". Tool results arrive as role == "user" messages, so an AskUserQuestion's own ANSWER is a
# user-role message landing after the tool_use that asked it - a naive "since the last user message"
# window would start after the answer and exclude the very evidence it looks for. The discriminator is
# whether the user-role message carries a real text block, which is the same test any transcript
# parser needs for the same reason.
#
# ARMS, both mandatory, both allow-and-log rather than deny:
#  - UNATTENDED session: unattended-guard.sh converts AskUserQuestion itself into a deny, so without
#    this arm the write is denied AND its remedy is denied - no memory could be written at all. Mirrors
#    MEMORY-5's own escape: proceed, and carry the pending item to the handoff.
#  - SUBAGENT caller: an agent cannot raise an AskUserQuestion to a human either, and cannot judge
#    whether the exception is warranted. Same allow-and-log.
#
# SCOPE AND CEILINGS, disclosed:
#  - A pruning or reformatting Edit is indistinguishable from one that adds a new fact, so it is treated
#    as new. MEMORY-5 exempts pruning in prose; this cannot, and over-firing on a reformat costs one
#    turn while under-firing costs the rule. Wrong direction chosen deliberately.
#  - The Bash arm (R2) covers `sed -i` and `tee` only, inheriting sc52a-write-disclosure-guard.sh's
#    documented limits verbatim: a bare `>` redirect is NOT scanned (indistinguishable from ubiquitous
#    benign use without a real shell parser), `guard_split_segments` is quote-blind so a `;` inside a
#    quoted sed script hides the hit, and a heredoc body stands the whole command down. These are real
#    misses, not theoretical ones. The arm exists because the file-tool matcher alone leaves the Bash
#    path wide open, not because it closes it.
#  - No `cd`/`-C` tracking on the Bash arm: the payload's raw `.cwd` only, same as sc52a.
#
# Kill switch checked before any side effect: .state/off/memory-write-gate. Fail-open with a breadcrumb
# on every tooling gap (no jq, no transcript, no library) - a gate that cannot run must not block work,
# and the breadcrumb is what stops that fail-open being silent.
# Self-check: memory-write-gate.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s memory-write-gate %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_DIR="${CLAUDE_DIR%/}"
[ -f "$CLAUDE_DIR/agent-tiers/.state/off/memory-write-gate" ] && exit 0
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ -n "$TOOL" ] || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
[ -n "$SELFDIR" ] && [ -f "$SELFDIR/lib/guard-mempath.sh" ] \
  || { note "fail-open: lib/guard-mempath.sh missing - cannot resolve the memory dir"; exit 0; }
. "$SELFDIR/lib/guard-mempath.sh"
command -v guard_mem_in_scope >/dev/null 2>&1 \
  || { note "fail-open: guard-mempath.sh sourced but guard_mem_in_scope undefined (stale library?)"; exit 0; }

# guard-cmdpos.sh carries guard_unattended and guard_caller_agent, which BOTH arms below need on every
# path, not just the Bash one - a subagent's Write must be armed the same as its sed. Sourced once,
# here; its absence is a fail-open for the arms, never for the gate (see the arm guards below).
[ -f "$SELFDIR/guard-cmdpos.sh" ] && . "$SELFDIR/guard-cmdpos.sh"

AUTO_MEM="$(guard_mem_auto_dir "$CLAUDE_DIR")"

# --- is this call a memory write? The cheap gate, before any transcript read ----------------------
TARGET=""
case "$TOOL" in
  Write|Edit|MultiEdit)
    TARGET="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
    [ -n "$TARGET" ] || exit 0
    guard_mem_in_scope "$CLAUDE_DIR" "$TARGET" "$AUTO_MEM" || exit 0
    ;;
  Bash)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    [ -n "$CMD" ] || exit 0
    # Cheap pre-filter: no in-place-write verb, nothing to do. Keeps this off every Bash call.
    case "$CMD" in *sed*|*tee*) ;; *) exit 0 ;; esac
    command -v guard_split_segments >/dev/null 2>&1 && command -v guard_has_heredoc >/dev/null 2>&1 \
      || { note "fail-open: guard-cmdpos.sh missing or stale - cannot split segments"; exit 0; }
    # A heredoc stands the whole command down - grep's per-line anchors would read a heredoc BODY line
    # as a command at command position. Same carve-out every consumer of this library takes.
    guard_has_heredoc "$CMD" && exit 0
    SEGMENTS="$(guard_split_segments "$CMD")"
    # Only segments that actually RUN sed -i / tee at command position, then the memory-dir test on
    # each of that segment's arguments. Checking every argument, not only the last, because a memory
    # write is the thing being caught here and a multi-file sed is not the rare case it is for sc52a.
    printf '%s\n' "$SEGMENTS" | while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      case "$seg" in
        *sed*-i*|*sed*--in-place*|*tee*) ;;
        *) continue ;;
      esac
      for arg in $seg; do
        case "$arg" in -*) continue ;; esac
        if guard_mem_in_scope "$CLAUDE_DIR" "$arg" "$AUTO_MEM"; then
          printf '%s\n' "$arg"
          break
        fi
      done
    done > "${TMPDIR:-/tmp}/.mwg.$$" 2>/dev/null
    HIT="$(head -1 "${TMPDIR:-/tmp}/.mwg.$$" 2>/dev/null || true)"
    rm -f "${TMPDIR:-/tmp}/.mwg.$$" 2>/dev/null
    [ -n "$HIT" ] || exit 0
    TARGET="$HIT"
    ;;
  *) exit 0 ;;
esac

# From here on this IS a memory write, so the work below is paid only on memory writes.
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in *[!A-Za-z0-9._-]* | '.' | '..') SESSION_ID="" ;; esac
AGENT_TYPE=""
if command -v guard_caller_agent >/dev/null 2>&1; then
  AGENT_TYPE="$(guard_caller_agent "$INPUT")"
else
  # The arms cannot be evaluated without the library. Fail-open on the ARM, not on the gate: the gate
  # below still runs, so the rule keeps being enforced for an attended Lead, and the breadcrumb says
  # an unattended or subagent caller may now be denied with no remedy available to it.
  note "fail-open (arms only): guard-cmdpos.sh unavailable - unattended/subagent callers are not armed [sid=$SESSION_ID]"
fi

emit_allow_pending() {
  note "allow (pending): memory write to $TARGET with no ask possible - $1 [sid=$SESSION_ID agent=${AGENT_TYPE:-lead}]"
  jq -n --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $r}}'
  exit 0
}

# --- arm 1: nobody is there to answer -------------------------------------------------------------
if [ -n "$AGENT_TYPE" ]; then
  emit_allow_pending "subagent caller" \
    "agent-tiers MEMORY-5: this memory write was allowed without the ask, because a subagent cannot put a question to the operator and cannot judge whether writing this memory is warranted. Report in your return that you wrote memory, and what the fact was, so the Lead can confirm the coverage check."
fi
if command -v guard_unattended >/dev/null 2>&1 && guard_unattended "$SESSION_ID"; then
  emit_allow_pending "unattended session" \
    "agent-tiers MEMORY-5: this memory write was allowed without the ask, because the session is flagged unattended and unattended-guard.sh would deny the AskUserQuestion that MEMORY-5 asks for - denying here too would leave no way to write memory at all. Carry this to RESUME_SESSION.md as a pending memory for the operator to confirm."
fi

# --- the window, and what must be in it -----------------------------------------------------------
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] \
  || { note "fail-open: no readable transcript_path in payload [sid=$SESSION_ID]"; exit 0; }

MEMDIR="$(dirname "$TARGET")"
# A Bash coverage check is free text: `cd $HOME && rg ... .claude/projects/<slug>/memory` or a `~/`
# form never contains the absolute dir as one contiguous string, so the read went unseen and the gate
# denied correct work three turns running (observed 2026-09-28). Accept the home-relative and tilde
# spellings too. Still unseen, disclosed: a cwd-relative path after a cd elsewhere, and a search of the
# parent dir that only covers memory/ as a subtree. Both need real path resolution, not a string test.
MEMDIR_REL="${MEMDIR#"$HOME"/}"
MEMDIR_TILDE="~/$MEMDIR_REL"

# Pre-filter before jq: transcripts run to many MB and this hook has a 5s budget. 800 lines is a
# generous over-estimate of one turn; the window narrows it further to "since the last user text".
WINDOW_FILE="${TMPDIR:-/tmp}/.mwg-window.$$"
tail -n 800 "$TRANSCRIPT" 2>/dev/null | awk '
  { lines[NR] = $0 }
  # A user message carrying a real text block - NOT a tool_result, which is also role "user" and would
  # otherwise put the window boundary after the answer to the very question being looked for.
  /"role"[[:space:]]*:[[:space:]]*"user"/ && /"type"[[:space:]]*:[[:space:]]*"text"/ { last = NR }
  END { for (i = last + 1; i <= NR; i++) print lines[i] }
' > "$WINDOW_FILE" 2>/dev/null
trap 'rm -f "$WINDOW_FILE" 2>/dev/null' EXIT

# 1. An AskUserQuestion tool_use, structurally confirmed.
ASKED=0
if grep -a -q 'AskUserQuestion' "$WINDOW_FILE" 2>/dev/null; then
  # -R -s, then a per-line fromjson: the transcript is JSONL, and a malformed or truncated line (a
  # partially-flushed write is normal at the tail of a live transcript) must be skipped, not abort the
  # whole parse. Reading the lines as raw strings is what makes `try fromjson catch empty` meaningful -
  # slurping them as objects and then calling fromjson silently yields nothing and every check reads
  # false, which is a gate that denies correct work and passes nothing. Caught by case 4.
  grep -a 'AskUserQuestion' "$WINDOW_FILE" 2>/dev/null | jq -e -R -s '
    split("\n") | map(select(length > 0)) | map(try fromjson catch empty)
    | map((.message.content // [])[]? | select(.type == "tool_use") | select(.name == "AskUserQuestion"))
    | length > 0
  ' >/dev/null 2>&1 && ASKED=1
fi

# 2. A read of the memory dir, structurally confirmed: a reader tool_use whose INPUT names the dir.
# The structural test is what stops this guard's own denial reason - which contains the path and lands
# in the transcript - from counting as a coverage check on the retry.
CHECKED=0
if grep -a -q -F -e "$MEMDIR" -e "$MEMDIR_REL" -e "$MEMDIR_TILDE" "$WINDOW_FILE" 2>/dev/null; then
  grep -a -F -e "$MEMDIR" -e "$MEMDIR_REL" -e "$MEMDIR_TILDE" "$WINDOW_FILE" 2>/dev/null \
    | jq -e -R -s --arg d "$MEMDIR" --arg r "$MEMDIR_REL" --arg t "$MEMDIR_TILDE" '
    split("\n") | map(select(length > 0)) | map(try fromjson catch empty)
    | map((.message.content // [])[]?
        | select(.type == "tool_use")
        | select(.name == "Read" or .name == "Grep" or .name == "Glob" or .name == "Bash")
        | select((.input | tostring) | (contains($d) or contains($r) or contains($t))))
    | length > 0
  ' >/dev/null 2>&1 && CHECKED=1
fi

[ "$ASKED" = 1 ] && [ "$CHECKED" = 1 ] && exit 0

MISSING=""
[ "$CHECKED" = 1 ] || MISSING="a coverage check"
if [ "$ASKED" != 1 ]; then
  [ -n "$MISSING" ] && MISSING="$MISSING and a question to the operator" || MISSING="a question to the operator"
fi

# The instructions name only the half that is actually missing. Observed live: with the coverage check
# already done, the headline degraded to "needs a question" while the body still walked through the
# search that had just been performed. A denial that re-demands finished work teaches its reader to
# skim it, which is how a deny-with-instructions guard decays into an obstacle.
STEP_CHECK="Search for existing coverage - the memory index and fact files under $MEMDIR, the project's ./CLAUDE.md, and any skill that plausibly already states this - then say where the check landed rather than asserting the fact is new. If it is already covered at another layer, propose a promotion or an update to that file instead of a second copy."
STEP_ASK="Put the draft to the operator with AskUserQuestion, so the fact that seeds every future session gets one look before it lands."
if [ "$CHECKED" != 1 ] && [ "$ASKED" != 1 ]; then
  STEPS="(1) $STEP_CHECK (2) $STEP_ASK"
elif [ "$CHECKED" != 1 ]; then
  STEPS="$STEP_CHECK"
else
  STEPS="$STEP_ASK"
fi
CLOSER="Then retry this write."
[ "$CHECKED" != 1 ] && CLOSER="$CLOSER A memory that already exists elsewhere costs zero extra turns, because the coverage check is what finds it."
REASON="agent-tiers MEMORY-5: writing '$TARGET' needs $MISSING first, in this same turn. $STEPS $CLOSER"
note "deny: memory write to $TARGET missing $MISSING [sid=$SESSION_ID]"
jq -n --arg r "$REASON" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0

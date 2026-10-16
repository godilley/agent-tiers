#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(ExitPlanMode): a plan may name a source file it never read, but not
# silently. Reading costs nothing; NOT reading costs one written clause.
#
# Asymmetric-declaration gate, not a detector. It classifies no prose: it compares the set of
# source-file basenames NAMED in the plan against the set READ via tool calls this session,
# narrowed to files git actually tracks. Set arithmetic, no semantics. (Seven prose-reading
# detectors were measured against a real corpus of plan documents and all seven failed - the
# words for deferring are the words for refusing to defer.)
#
# Remedy is a DECLARATION, never a hard block. Subagent reads ARE counted: they live in
# `<transcript>/subagents/agent-*.jsonl` on this host (152 such dirs present; verified 2026-09-20
# after an earlier check wrongly concluded they were invisible - it globbed only the top-level
# *.jsonl and never descended). Counting them drops the baseline from 7.5 to 1.8 unread files
# per plan, so omitting them would over-fire roughly 3x. Host-observed layout, not a documented
# API: absent directory degrades silently to main-transcript-only.
#
# Baseline before this gate existed (n=28 plans, subagent reads counted): mean 1.8
# named-and-tracked-but-unread files per plan; 57% of plans would fire. Pre-registered falsifiers, frozen before this file was
# written, are kept in the maintainer's private notes (not shipped). If the declarations come back
# as one repeated boilerplate string, the gate has FAILED even if the number moves.
#
# Fail-open on every tooling gap (no jq, no plan text or plan file, no git, unreadable transcript) with a
# guards.log breadcrumb - never blocks on its own malfunction.
# Kill switch: .state/off/read-basis-guard (enforced by kit-gate.sh)
# Self-check: read-basis-guard.selfcheck.sh
set -u

SID=""; SRC=""
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s read-basis-guard %s%s [sid=%s]\n' \
      "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SRC:+ [src=plan-file]}" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}

[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing"; exit 0; }
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
command -v git >/dev/null 2>&1 || { note "fail-open: git missing"; exit 0; }

PLAN="$(printf '%s' "$INPUT" | jq -r '.tool_input.plan // empty' 2>/dev/null || true)"
if [ -z "$PLAN" ]; then
  # Some host versions send an empty tool_input: recover the plan from <config>/plans/<slug>.md.
  # A host plansDirectory setting can relocate plan files; this fallback does not read it, so it fails open there.
  SLUG="$(printf '%s' "$INPUT" | jq -r '.slug // empty' 2>/dev/null || true)"
  if [ -z "$SLUG" ] && [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
    SLUG="$(jq -rR 'fromjson? | .slug? | select(type=="string" and length>0)' "$TRANSCRIPT" 2>/dev/null | tail -n 1 || true)"
  fi
  REJ=""; case "$SLUG" in ""|*[!A-Za-z0-9_-]*) [ -n "$SLUG" ] && REJ=1; SLUG="" ;; esac
  CFG="${CLAUDE_CONFIG_DIR:-}"; [ -n "$CFG" ] || { [ -n "${HOME:-}" ] && CFG="$HOME/.claude"; }
  PF="${CFG:-/nonexistent}/plans/$SLUG.md"
  if [ -n "$SLUG" ] && [ -n "$CFG" ] && [ -r "$PF" ] && [ -s "$PF" ]; then
    PLAN="$(cat "$PF" 2>/dev/null || true)"; SRC=1
  fi
  [ -n "$PLAN" ] || { note "fail-open: no tool_input.plan and no plan file (${SLUG:-$([ -n "$REJ" ] && echo rejected slug || echo no slug)})"; exit 0; }
fi

# An explicit declaration satisfies the gate outright - that IS the costed branch.
if printf '%s' "$PLAN" | grep -aqiE '^[[:space:]]*.{0,12}read-basis:'; then
  note "allow: plan carries a read-basis declaration"
  exit 0
fi

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$CWD" ] && [ -d "$CWD" ] || { note "fail-open: no usable cwd"; exit 0; }
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || { note "fail-open: no readable transcript_path"; exit 0; }

EXT='ts|tsx|js|mjs|mts|vue|lua|php|py|sh|json|css|html|twig'
paths_in() { grep -aoE "[A-Za-z0-9_.-]+\.($EXT)\b" 2>/dev/null | sed 's|.*/||' | sort -u; }

TMP="$(mktemp -d 2>/dev/null)" || { note "fail-open: mktemp"; exit 0; }
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

printf '%s' "$PLAN" | paths_in > "$TMP/named" 2>/dev/null || true
[ -s "$TMP/named" ] || { note "allow: plan names no source files"; exit 0; }

# Files actually read this session: Read/Grep/Glob/Bash inputs only (NOT Write - a plan-file
# write echoes every path in the plan and would mark everything as read). Parsed line by line
# (-R + fromjson?) so one malformed or truncated line cannot drop every read after it.
jq -rR 'fromjson? | select(.message.content|type=="array") | .message.content[]
       | select(type=="object" and .type=="tool_use")
       | select(.name=="Read" or .name=="NotebookRead" or .name=="Grep" or .name=="Glob" or .name=="Bash")
       | [.input.file_path?, .input.path?, .input.pattern?, .input.glob?, .input.command?]
       | map(select(. != null)) | join(" ")' "$TRANSCRIPT" 2>/dev/null \
  | paths_in > "$TMP/read.main" 2>/dev/null || true
touch "$TMP/read.main"

# Subagent transcripts: a delegated read is still a read. Same record shape, same filter.
SUBDIR="${TRANSCRIPT%.jsonl}/subagents"
: > "$TMP/read.sub"
if [ -d "$SUBDIR" ]; then
  for f in "$SUBDIR"/agent-*.jsonl; do
    [ -r "$f" ] || continue
    jq -rR 'fromjson? | select(.message.content|type=="array") | .message.content[]
           | select(type=="object" and .type=="tool_use")
           | select(.name=="Read" or .name=="NotebookRead" or .name=="Grep" or .name=="Glob" or .name=="Bash")
           | [.input.file_path?, .input.path?, .input.pattern?, .input.glob?, .input.command?]
           | map(select(. != null)) | join(" ")' "$f" 2>/dev/null | paths_in >> "$TMP/read.sub" 2>/dev/null || true
  done
fi
sort -u "$TMP/read.main" "$TMP/read.sub" > "$TMP/read" 2>/dev/null || true
touch "$TMP/read"

TOP="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$TOP" ] && git -C "$TOP" ls-files 2>/dev/null | sed 's|.*/||' | sort -u > "$TMP/tracked" || true
[ -s "$TMP/tracked" ] || { note "fail-open: git ls-files empty (not a repo?)"; exit 0; }

comm -12 "$TMP/named" "$TMP/tracked" > "$TMP/existing" 2>/dev/null || true
comm -23 "$TMP/existing" "$TMP/read" > "$TMP/unread" 2>/dev/null || true

N="$(wc -l < "$TMP/unread" 2>/dev/null | tr -d ' ')"
[ "${N:-0}" -gt 0 ] 2>/dev/null || { note "allow: every tracked file named in the plan was read"; exit 0; }

SHOW="$(head -8 "$TMP/unread" | tr '\n' ' ')"
note "deny: $N tracked file(s) named but unread"
{
  printf 'agent-tiers: this plan names %s tracked file(s) it never opened this session:\n' "$N"
  printf '  %s\n' "$SHOW"
  printf '\n'
  printf 'Reading them costs nothing and you are still in plan mode, where reads are free.\n'
  printf 'Measured over a real plan corpus: about half of the unverified claims in past plans\n'
  printf 'could have been settled by one read that was simply never run.\n'
  printf '\n'
  printf 'Either read them and re-present, or state the basis on its own line in the plan:\n'
  printf '  read-basis: not read, because <why it does not need reading>\n'
  printf '\n'
  printf 'Reads made by subagents in this session already count, so they need no declaration.\n'
  printf 'A repeated boilerplate clause defeats the point and is a recorded failure mode.\n'
} >&2
exit 2

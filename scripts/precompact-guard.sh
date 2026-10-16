#!/usr/bin/env sh
# kit-scope: shared
# kit-probe: yes
# agent-tiers PreCompact guard: block a MANUAL /compact when this session has authored something
# under this project (per authorship-record.sh's ledger) more recently than RESUME_SESSION.md was
# last touched - a compact right before writing the handoff throws away exactly the state the
# handoff exists to carry forward. Consent row - install-flat.sh --with-precompact-guard (the ledger
# it reads is itself only recorded when authorship-record.sh is also wired).
#
# Auto-compact is NOT covered: `trigger != manual` always passes. Blocking an automatic compact
# that recovers from a context-limit error fails the current request outright (hooks.md), which is
# a far worse outcome than a stale handoff - this guard only ever second-guesses a deliberate,
# interactive `/compact`.
#
# PreCompact has no additionalContext / advisory channel (hooks.md decision-control table: only
# top-level `decision: "block"` or exit code 2) - so unlike every SessionStart/PostToolUse hook in
# this kit, this one truly can only block or stay silent. Escape hatch: `/compact force ...` (any
# custom_instructions starting with "force") always passes, same shape as review-gate-guard's own
# escape words - a Lead who has already decided the risk is acceptable is never stuck.
#
# Fail-open, deliberately narrow: no jq, unparseable payload, unusable session_id, or an unreadable/
# missing authorship ledger all pass silently (with a guards.log breadcrumb) rather than block on a
# tooling gap. This guard's whole value is in blocking a REAL miss, not in blocking on uncertainty.
#
# Install-time support probe (`# kit-probe: yes` above): `sh precompact-guard.sh --probe` does no
# side effects, reads no stdin, ignores the kill switch. Supported (exit 0, no output) only if jq is
# present AND authorship-record is wired (its command already appears in $KIT_PROBE_SETTINGS, or
# `authorship-record` is also in this same install's $KIT_PROBE_WITH list) AND authorship-record is
# NOT also being removed in this SAME run ($KIT_PROBE_WITHOUT) - a settings.json grep alone cannot
# see a same-run `--without-authorship-record` coming, since that removal has not happened yet at
# probe time; without $KIT_PROBE_WITHOUT this guard could wire cleanly against a ledger that is
# about to vanish in the same install. Without that ledger this guard can never see anything to
# compare against RESUME_SESSION.md, so it would wire and then silently never block. Otherwise exit
# 3 with a one-line reason. install-flat.sh runs this before writing settings.json for
# `--with-precompact-guard` and refuses the install on exit != 0.
# Stated ceiling, not fixed here: a LATER, separate `--without-authorship-record` run never
# re-probes precompact-guard (this probe only ever runs at --with-<id> time), and the settings.json
# check is a substring grep - a foreign row, a different event, or a disabled entry mentioning the
# script all read as "wired" too.
# Self-check: precompact-guard.selfcheck.sh.
set -u

if [ "${1:-}" = "--probe" ]; then
  command -v jq >/dev/null 2>&1 || { echo "jq is not on PATH - the authorship ledger this guard reads is jq-written and its own payload parsing is jq-only"; exit 3; }
  case " ${KIT_PROBE_WITHOUT:-} " in
    *" authorship-record "*)
      echo "authorship-record is being removed in this same install (--without-authorship-record) - without its ledger this guard can never see anything to block on"
      exit 3 ;;
  esac
  wired=0
  case " ${KIT_PROBE_WITH:-} " in *" authorship-record "*) wired=1 ;; esac
  if [ "$wired" != 1 ] && [ -n "${KIT_PROBE_SETTINGS:-}" ] && [ -f "${KIT_PROBE_SETTINGS:-/dev/null}" ]; then
    grep -q 'authorship-record\.sh' "$KIT_PROBE_SETTINGS" 2>/dev/null && wired=1
  fi
  [ "$wired" = 1 ] || { echo "authorship-record is not wired (neither already present in settings.json nor requested alongside --with-precompact-guard) - without its ledger this guard can never see anything to block on"; exit 3; }
  exit 0
fi

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s precompact-guard fail-open: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

# 1. Kill switch first, before any side effect or read.
[ -f "$CLAUDE_DIR/agent-tiers/.state/off/precompact-guard" ] && exit 0
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "jq missing - cannot parse payload"; exit 0; }

# 2. Only a manual /compact is in scope - see header for why auto is never blocked.
TRIGGER="$(printf '%s' "$INPUT" | jq -r '.trigger // ""' 2>/dev/null || true)"
[ "$TRIGGER" = manual ] || exit 0

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
RESUME="$DIR/RESUME_SESSION.md"
# 3. No project handoff file at all: nothing for this guard to protect.
[ -f "$RESUME" ] || exit 0

# 4. Explicit escape hatch: `/compact force ...` always passes. Leading whitespace is trimmed and
# the match is case-insensitive (`Force`, `  FORCE ...`) - a Lead typing the word should not have to
# get its exact case and spacing right for an escape hatch to fire. Still a PREFIX match: "force"
# has to be the first word, so "please force it" or "enforce" stay blocked, same as before.
CUSTOM="$(printf '%s' "$INPUT" | jq -r '.custom_instructions // ""' 2>/dev/null || true)"
CUSTOM_NORM="$(printf '%s' "$CUSTOM" | sed -E 's/^[[:space:]]+//' | tr 'A-Z' 'a-z')"
case "$CUSTOM_NORM" in force*) exit 0 ;; esac

# Session id becomes a path component below - validate before use (same guard as resume-inject.sh /
# authorship-record.sh: a `../`-style id would turn a ledger lookup into an arbitrary-file read).
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in
  '' | *[!A-Za-z0-9._-]* | '.' | '..') note "unusable session_id - passing"; exit 0 ;;
esac

# Same root-resolution idiom as authorship-record.sh:75 (BASE, not CLAUDE_DIR) - the recorder writes
# under its own kit dir, never under CLAUDE_CONFIG_DIR, so reading from CLAUDE_DIR silently found
# nothing on any profile/kit-location split (a second CLAUDE_CONFIG_DIR profile, or a kit cloned
# outside ~/.claude): the guard would fail open on EVERY /compact in that setup, forever, with only
# a note() breadcrumb to show for it. Fixed 2026-09-14, review finding.
TSV="${BASE:-${TMPDIR:-/tmp}}/.state/authorship/$SESSION_ID.tsv"
# 6. Missing or unreadable ledger: fail open. Most sessions never author anything trust-flagged, and
# authorship-record.sh may not even be wired - absence of evidence is not evidence of a miss.
[ -f "$TSV" ] && [ -r "$TSV" ] || { note "no readable authorship ledger for session $SESSION_ID - passing"; exit 0; }

# Newest in-project MAIN authorship line: the ledger is append-only chronologically
# (authorship-record.sh appends, never reorders), so the LAST line whose path field is under $DIR is
# the newest in-project write. Field 1 = the recorder's own ISO-8601-with-offset timestamp, field 2 =
# the agent (`MAIN` for the session Lead, else the subagent type), field 4 = the path. Only $2 ==
# "MAIN" rows count: a subagent's edits stay on disk and its return arrives after the compact, so a
# background worker (e.g. writing under `.claude/worktrees/agent-<id>/`) racing the Lead's own RESUME
# update must never hold /compact hostage - compaction only ever discards the Lead's conversation
# context, not a subagent's work. RESUME's OWN row is excluded: the Lead editing RESUME_SESSION.md
# itself would otherwise race this guard - both timestamps floor to whole seconds, and the ledger's
# `date` runs strictly after the write (3 jq passes + 2 greps + a mkdir later), so a same-second edit
# can read as "newer" and block a /compact immediately after the handoff was updated - exactly the
# case this guard exists not to block.
LATEST_LINE="$(awk -F'\t' -v dir="$DIR/" -v resume="$RESUME" '$2 == "MAIN" && index($4, dir) == 1 && $4 != resume { line = $0 } END { print line }' "$TSV" 2>/dev/null || true)"
[ -n "$LATEST_LINE" ] || exit 0   # nothing authored under this project this session: nothing to compare

LATEST_TS="$(printf '%s' "$LATEST_LINE" | cut -f1)"
LATEST_EPOCH="$(date -d "$LATEST_TS" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%S%z' "$LATEST_TS" +%s 2>/dev/null || true)"
[ -n "$LATEST_EPOCH" ] || { note "could not parse authorship timestamp '$LATEST_TS' - passing"; exit 0; }

RESUME_EPOCH="$(date -r "$RESUME" +%s 2>/dev/null || stat -c %Y "$RESUME" 2>/dev/null || true)"
[ -n "$RESUME_EPOCH" ] || { note "could not stat $RESUME - passing"; exit 0; }

if [ "$RESUME_EPOCH" -lt "$LATEST_EPOCH" ] 2>/dev/null; then
  printf 'agent-tiers precompact-guard: RESUME_SESSION.md is older than this session'\''s most recent in-project authorship (%s) - a manual /compact now would discard state the handoff has not caught up to yet. Update RESUME_SESSION.md first, or run `/compact force ...` to compact anyway. Kill switch: mkdir -p %s/agent-tiers/.state/off && touch %s/agent-tiers/.state/off/precompact-guard\n' \
    "$LATEST_TS" "$CLAUDE_DIR" "$CLAUDE_DIR" >&2
  exit 2
fi

exit 0

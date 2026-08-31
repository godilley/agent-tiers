#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PostToolUse(Bash) STAGE 1 of the parser-cross-check arrival event: log-only, ZERO
# model-visible output. Records every Bash call whose command looks like an ad-hoc DERIVATION (a sum,
# ratio, percent, or multi-record accumulation computed via awk/python/perl/bc over parsed/regexed
# text), keyed per session, so a later session can measure the real fire rate before any nudge is built.
#
# Why this exists (evidence, not opinion): a live client-work session (2026-08-06) - two
# wrong numeric claims (10x-172x, then 1.2x-2.2x, before the real 0-13%) reached the user before an
# independent DB check surfaced the correct figure. Root causes: an unreset accumulator reused across a
# batch loop, and a `\w+` regex that silently dropped hyphenated tax-code tokens. A drafted PROSE rule
# for "cross-check parsed numeric claims" was explicitly REJECTED in favour of an arrival-event
# mechanism (measured 2026-08-04: only 2.1% of editing sessions end with an independently-reviewed
# diff, flat across 6 weeks of added doctrine text - a rule only fires reliably when checked at an
# observable ACT, not at plan time). See [[rules-need-arrival-events]] / authorship-record.sh, the
# shipped precedent for the same shape (PostToolUse ledger + nudge on a trust-class ACT).
#
# Why STAGE 1 is log-only, not a nudge yet (advisor-reviewed 2026-08-07, docs/_local/
# 2026-08-07-parser-crosscheck-vcs-guard-plan.md): the failure is CITATION, not parsing - most parses
# are never cited, so a PostToolUse(Bash) nudge fired on every derivation-shaped command would hit a lot
# of benign volume (this kit's own framing-guard.sh precedent: a glossary that fired on nearly every
# Task spawn was evicting the rare genuine signal, not amplifying it). The real arrival point for
# CITATION is a Stop-hook fire gated on the session's ledger having entries AND the turn's final text
# containing a derived-figure pattern - probed and CONFIRMED working under this harness's `claude -p`
# invocation mode (exit 2 + stderr on Stop blocks stopping and feeds the reason back as an instruction;
# `stop_hook_active` correctly reports true on the recursion-guard call), but NOT YET BUILT: real fire-
# rate data from this log is the input that sets the trigger's precision before that nudge is written.
# Stage 2 is deliberately out of scope for this commit.
#
# Trigger (ERE against the raw command TEXT, not the output): a derivation IDIOM - `+=` accumulation,
# an awk program whose braces contain `sum`/`SUM`, a `| bc` arithmetic pipe, or a Python `re.findall`/
# `re.search`/`re.match` call (the two evidenced bugs were an unreset `+=`-shaped accumulator and a
# `\w+` regex extraction feeding one - both match). Deliberately EXCLUDES bare `wc -l`/`grep -c` with no
# downstream arithmetic - those are routine and match none of the idioms above, no separate exclusion
# needed. ponytail: a textual/regex heuristic, not real parsing - known ceiling, not aspirational: a
# derivation split across several sequential Bash calls (accumulate in turn N, print in turn N+3) logs
# each call separately with no cross-call correlation (Stage 2's session-scoped ledger is what a future
# Stop-hook would fold these across); a derivation performed inside a Python/Node script FILE (not an
# inline `-c`/`-e` one-liner) is invisible to a command-text match. Fail-open on every tooling gap (no
# jq, unusable session_id, unwritable state dir), breadcrumbed like every other guard in this kit.
# Self-check: numeric-claim-ledger.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s numeric-claim-ledger %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
    tail -n 2500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null || true
  fi
}

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

DERIV_ERE='(\+=|awk[^|;&]*\{[^}]*(sum|SUM)|\|[[:space:]]*bc\b|re\.(findall|search|match)\()'
printf '%s' "$CMD" | grep -aEq "$DERIV_ERE" || exit 0

# Session id becomes a path component, so validate BEFORE use (same guard as authorship-record.sh /
# resume-inject.sh / F-12): an unvalidated id would turn this ledger into an arbitrary-file write.
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in
  '' | *[!A-Za-z0-9._-]* | '.' | '..') note "unusable session_id - not recording"; exit 0 ;;
esac
AGENT="$(printf '%s' "$INPUT" | jq -r '.agent_type // "MAIN"' 2>/dev/null || echo MAIN)"
case "$AGENT" in *[!A-Za-z0-9._-]*) AGENT="unknown" ;; esac

DIR="${BASE:-${TMPDIR:-/tmp}}/.state/numeric-claims"
LEDGER="$DIR/$SESSION_ID.tsv"
mkdir -p "$DIR" 2>/dev/null || { note "cannot create $DIR"; exit 0; }

# tabs/newlines stripped so the snippet can't corrupt the TSV; capped at 200 chars - this is a fire-rate
# measurement, not a security-relevant field, but the cap keeps the ledger cheap to read back.
SNIPPET="$(printf '%s' "$CMD" | tr '\t\n' '  ' | cut -c1-200)"
printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$AGENT" "$SNIPPET" >> "$LEDGER" 2>/dev/null || true

# Bounded: a long session must not grow this without limit.
if [ "$(wc -l < "$LEDGER" 2>/dev/null || echo 0)" -gt 500 ]; then
  tail -n 250 "$LEDGER" > "$LEDGER.tmp" 2>/dev/null && mv -f "$LEDGER.tmp" "$LEDGER" 2>/dev/null || true
fi
# Ledgers older than 14 days are not evidence of anything current.
{ find "$DIR" -type f -mtime +14 -delete; } 2>/dev/null || true

exit 0

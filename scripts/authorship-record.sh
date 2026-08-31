#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PostToolUse(edit tools) recorder: log what THIS session authored, and nudge ONCE when the
# session first authors a non-trivial trust-class artifact.
#
# Why a hook, not doctrine prose: measured 2026-08-04 over a multi-week corpus of ordinary
# (non-doctrine-authoring) sessions, only about 2% ended with an independently-reviewed diff, roughly
# the same under every model in use, and the rate did NOT move across the six weeks in which the kit
# gained SC-5.2, the XLAB card, review modes and planted controls. Adding a
# seventh statement of the rule is the one intervention the time series says has never worked.
#
# The mechanism it supplies is an ARRIVAL EVENT. Every kit rule that fires (SC-3.1 at the spawn, SC-5.3 at
# the send, SC-3.3 at the push) is checked when an act happens; every rule that fails (SC-1.6, SC-5.2) is
# checked at plan time against work that does not exist yet, so it never re-arms for the artifact authored
# next. Leads DO review reliably when someone else's output arrives; self-authored work has no arrival.
# This makes one.
#
# NUDGE, NOT BLOCK, deliberately: at a 98% fire rate a blocking gate trains an override reflex within days,
# which is the rubber-stamping failure it was meant to prevent. additionalContext changes what the model
# knows at the AUTHORING moment, before the ship decision, and costs no human interrupt and no override
# text. Falsifiable: if the 2.1% baseline does not move, this failed and the narrow ship-block earns its
# turn. Never blocks, never reverts a write, always exits 0.
#
# NOT auto-wired: consent row - `install-flat.sh --with-authorship-record`. Fail-open on every tooling gap
# (no jq, unparseable payload, unwritable state dir) with a breadcrumb in .state/guards.log. Ceilings, all
# stated: the trust-class test is a PATH regex, so an obfuscated surface is missed (anti-accident, not
# anti-adversary); the ledger records that an edit happened, never that a reviewer read it; and a sub-agent
# writes into its PARENT session's ledger (verified: PostToolUse carries the parent session_id plus
# agent_id/agent_type), which is intended - a delegated writer's diff is the Lead's to get reviewed.
# Self-check: authorship-record.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s authorship-record fail-open: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
    tail -n 2500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null || true
  fi
}

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "jq missing - cannot parse payload"; exit 0; }

# One jq pass: is this edit non-trivial (SC-1.4 floor: a one-line or pattern-mechanical edit verifiable by
# eye), and what path did it touch? A MultiEdit is never trivial. Emits "<0|1>\t<path>".
FIELDS="$(printf '%s' "$INPUT" | jq -r '
  def nlcount: (tostring | split("\n") | length - 1);
  (.tool_input // {}) as $i
  | (($i.file_path // $i.notebook_path // "") | tostring) as $p
  | (($i.new_string // $i.content // "") | tostring) as $new
  | (($i.old_string // "") | tostring) as $old
  | (if (($i.edits? | type) == "array") then true
     elif (($new | length) + ($old | length)) > 400 then true
     elif (($new | nlcount) > 1) or (($old | nlcount) > 1) then true
     else false end) as $nt
  | [ (if $nt then "1" else "0" end), $p ] | @tsv' 2>/dev/null || true)"
[ -n "$FIELDS" ] || { note "unparseable payload"; exit 0; }

NONTRIVIAL="${FIELDS%%	*}"
FPATH="${FIELDS#*	}"
[ -n "$FPATH" ] || exit 0

# Session id becomes a path component, so validate BEFORE use (same guard as resume-inject.sh / F-12):
# a `../`-style id would turn this recorder into an arbitrary-file write.
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in
  '' | *[!A-Za-z0-9._-]* | '.' | '..') note "unusable session_id - not recording"; exit 0 ;;
esac
AGENT="$(printf '%s' "$INPUT" | jq -r '.agent_type // "MAIN"' 2>/dev/null || echo MAIN)"
case "$AGENT" in *[!A-Za-z0-9._-]*) AGENT="unknown" ;; esac

# Trust-class surface. PATH only, deliberately: the content regex this replaced (auth|token|secret...)
# flagged 28% of all edits against 15.8% for paths alone, with no gain on the cases that matter.
TRUST=0
printf '%s' "$FPATH" | grep -Eqi '(settings\.json|/hooks?/|/\.claude/|/migrations?/|\.sql$|\.tf$|\.github/workflows/|/agent-tiers/|\.env|credentials|id_rsa|id_ed25519|\.pem$|guard\.sh$)' && TRUST=1

DIR="${BASE:-${TMPDIR:-/tmp}}/.state/authorship"
LEDGER="$DIR/$SESSION_ID.tsv"
mkdir -p "$DIR" 2>/dev/null || { note "cannot create $DIR"; exit 0; }

# Was a flagged artifact already authored this session? Read BEFORE appending, so the first one nudges.
# grep -c PRINTS 0 and exits 1 on no match, so `|| echo 0` here would yield "0\n0" and silently kill
# the nudge for any session whose first edit was ordinary (cold-review F2, 2026-08-10). Validate instead.
PRIOR=0
if [ -f "$LEDGER" ]; then
  PRIOR="$(grep -c '	FLAG	' "$LEDGER" 2>/dev/null)"
  case "$PRIOR" in ''|*[!0-9]*) PRIOR=0 ;; esac
fi

FLAG=ok
[ "$NONTRIVIAL" = 1 ] && [ "$TRUST" = 1 ] && FLAG=FLAG
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$AGENT" "$FLAG" "$FPATH" >> "$LEDGER" 2>/dev/null || true

# Bounded: a long session must not grow this without limit.
if [ "$(wc -l < "$LEDGER" 2>/dev/null || echo 0)" -gt 500 ]; then
  tail -n 250 "$LEDGER" > "$LEDGER.tmp" 2>/dev/null && mv -f "$LEDGER.tmp" "$LEDGER" 2>/dev/null || true
fi
# Ledgers older than 14 days are not evidence of anything current.
{ find "$DIR" -type f -mtime +14 -delete; } 2>/dev/null || true

[ "$FLAG" = FLAG ] || exit 0
[ "$PRIOR" -eq 0 ] 2>/dev/null || exit 0                       # nudge ONCE per session, then stay silent

CTX="agent-tiers SC-5.2: you have now AUTHORED a non-trivial trust-class artifact this session ($FPATH). Authorship and the pre-ship verdict are separate roles - you are disqualified as this diff's fresh eyes, at any band. Before it ships, route an independent pass (Reviewer, or a single-diff Advisor ask; top-stakes takes the independent pass per SC-1.6 regardless of band). Note the argument that will occur to you and is wrong: 'another review pass is low marginal value here' is a statement about the diff you have ALREADY reviewed, never about the diff you just authored. This is a record, not a block - nothing is stopping you, and deciding not to review is a decision worth stating out loud rather than making silently."
jq -n --arg c "$CTX" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}' 2>/dev/null || true
exit 0

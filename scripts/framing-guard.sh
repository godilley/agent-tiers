#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Task|Agent) guard, STAGE 1 (log-only, never denies): flags an outbound
# sub-agent prompt that names our own kit vocabulary (M-numbers, SC-ids, card ids) - the FRAMING
# axis (XLAB-12) and SC-4.1a in the agent-tiers SKILL. A DISCOVERY-shaped ask primed with our own
# taxonomy structurally can only return findings that taxonomy can express, then reports the gap
# closed; a GAP-CHECK-shaped ask is SUPPOSED to carry that vocabulary. This hook cannot tell the two
# task shapes apart (that call is inherently a judgment the Lead makes when writing the brief, not a
# regex on the prompt text), so it never blocks - it logs a breadcrumb so a framed DISCOVERY brief is
# at least VISIBLE after the fact, not silently invisible the way the first M1/M2/M8 fan-out was
# until the operator caught it live (2026-08-06).
#
# Why log-only, not deny/inject: a real Stage 2 (rewrite the prompt to strip our vocabulary via
# `updatedInput`, or block until re-briefed) needs a live-tested answer to whether `updatedInput`
# actually reaches the spawned sub-agent's system context - confirmed only STATICALLY so far (the
# harness generically schema-validates and applies `updatedInput` per-tool, per the shipped binary's
# own source; Task's tool_input schema is `{description, subagent_type, prompt}` same as any other
# tool). Building a deny/inject stage on an unverified mechanism risks either a false sense of
# coverage (if it silently doesn't work) or breaking every legitimate GAP-CHECK spawn (if it
# over-blocks) - so Stage 1 stops at visibility. Sequencing per the 3-advisor design (RESUME_SESSION
# 2026-08-06): do not block the rest of this wave on Stage 2.
#
# ponytail: fixed glossary term-list matching, not semantic framing detection - it cannot tell
# "M1/M2/M8" used AS the gap-check question from the same tokens used as incidental color text in an
# otherwise-unprimed brief; it also cannot see vocabulary introduced only via a REFERENCED file (a
# prompt that says "read docs/scope.md first" where THAT file carries the framing) - known ceiling,
# accepted; upgrade path is a Lead-side self-check at brief-authoring time (SC-4.1a already states
# the rule), this hook is a safety net under it, not a replacement for it. Glossary is DELIBERATELY
# narrow: only well-bounded, kit-specific tokens (M[0-9]+, SC-x.y, XLAB-n, the literal "agent-tiers").
# An earlier draft also matched the plain-English tier names (Lead/Worker/Advisor/Reviewer/Boss) and
# fired on nearly every Task spawn this kit writes - common English words, not a framing signal - and
# would have evicted the rare, valuable fail-open breadcrumbs from every OTHER guard by flooding the
# shared log (F-25 review finding, 2026-08-06). Fixed by narrowing the glossary AND giving framing
# hits their OWN log file (below), never the shared `.state/guards.log`.
# Fail-open on any tooling gap - breadcrumb to the SHARED `.state/guards.log` (F-25), consistent with
# every other guard for the rare jq-missing case. Framing HITS (potentially high-volume, one per
# vocabulary-carrying spawn) go to their own `.state/framing.log` with its own rotation budget instead
# - see the split above. Self-check: framing-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
FRAMING_LOG="${BASE:-${TMPDIR:-/tmp}}/.state/framing.log"

note() { # $1 = message - fail-open only, shared log, same convention as every other guard
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s framing-guard fail-open: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
    tail -n 2500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null || true
  fi
}

note_hit() { # $1 = message - framing hits, own log, own rotation budget
  { mkdir -p "$(dirname "$FRAMING_LOG")" 2>/dev/null && printf '%s framing-guard hit: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$FRAMING_LOG"; } 2>/dev/null || true
  if [ -f "$FRAMING_LOG" ] && [ "$(wc -l < "$FRAMING_LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
    tail -n 100 "$FRAMING_LOG" > "$FRAMING_LOG.tmp" 2>/dev/null && mv -f "$FRAMING_LOG.tmp" "$FRAMING_LOG" 2>/dev/null || true
  fi
}

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "jq missing - cannot parse payload"; exit 0; }
PROMPT="$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null || true)"
[ -n "$PROMPT" ] || exit 0

# strip Apple-silicon-shaped mentions ("M1 Mac", "M2 Ultra", "M3 chip"...) before the glossary
# extraction below - round-2 review found bare `M[0-9]+` matching ordinary hardware references,
# noise-only (own log, not the shared one) but cheap to cut at the source. Also strip PATH-shaped
# "agent-tiers" mentions (round-3 review: `~/.claude/agent-tiers/scripts/x.sh` - a path any kit brief
# routinely cites - matches `\bagent-tiers\b` since `/` is a non-word char on both sides; nearly every
# brief this kit writes would log a hit, steadily evicting the rare genuine framing signal from its
# own 200-line log). A genuine vocabulary mention with no adjacent slash ("this kit is agent-tiers")
# still extracts normally below.
# Portable spelling (2026-08-16): an earlier version used `\b` and the `i` substitute flag (GNU sed
# extensions) and CLAIMED BSD sed would error and fail open. Measured on GitHub Actions macos-latest:
# BSD sed does NOT error - it silently fails to strip, so "M1 Mac" logged a framing hit on every Mac.
# Now spelled with POSIX classes: `(^|[^[:alnum:]_])` / `([^[:alnum:]_]|$)` for the boundary and the
# proper-noun capitalisations listed explicitly (the `i` flag bought only "mac"/"ultra" lowercase forms).
CLEANED_PROMPT="$(printf '%s' "$PROMPT" | sed -E 's/(^|[^[:alnum:]_])M[0-9]+[[:space:]]+(Mac(Book)?|Ultra|Pro|Max|[Cc]hip)([^[:alnum:]_]|$)/\1\4/g' \
  | sed -E 's#/agent-tiers([^[:alnum:]_]|$)#/X\1#g; s#(^|[^[:alnum:]_])agent-tiers/#\1X/#g')"

# narrow glossary (see header) - kept as a flat list here rather than sourced from the skill file (a
# live `grep` against SKILL.md would tie this hook's exit code to that file's presence/format).
HIT="$(printf '%s' "$CLEANED_PROMPT" | grep -aEo '\b(M[0-9]+|SC-[0-9]+\.[0-9]+[a-z]?|XLAB-[0-9]+|agent-tiers)\b' | sort -u | tr '\n' ',' | sed 's/,$//' || true)"
[ -n "$HIT" ] || exit 0

note_hit "outbound Task/Agent prompt names kit vocabulary ($HIT) - if this is a DISCOVERY-shaped ask (what's out there / what are we missing), SC-4.1a says brief it unprimed instead; if it's GAP-CHECK-shaped (does X cover our taxonomy), this is expected and fine."
exit 0

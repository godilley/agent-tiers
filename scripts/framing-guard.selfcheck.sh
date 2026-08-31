#!/usr/bin/env sh
# kit-scope: shared
# Self-check for framing-guard.sh. Runnable: `sh framing-guard.selfcheck.sh`.
# Stage 1 is log-only - this asserts the HIT LOG LINE appears (or doesn't), never a deny/allow
# decision. Runs the guard from an ISOLATED temp copy (own scripts/../.state tree), not the real kit
# tree - the original version shared the real log, so a check running exactly at the 200-line
# rotation boundary would spuriously read "no new line" (2026-08-06 review finding), and every
# selfcheck run polluted production breadcrumbs.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"

T="$(mktemp -d)"
cleanup() { rm -rf "$T" 2>/dev/null || true; }
trap cleanup EXIT
mkdir -p "$T/scripts"
cp "$DIR/framing-guard.sh" "$T/scripts/framing-guard.sh"
GUARD="$T/scripts/framing-guard.sh"
LOG="$T/.state/framing.log"
fail=0

before_lines() { [ -f "$LOG" ] && wc -l < "$LOG" 2>/dev/null || echo 0; }

check() { # $1=want(hit|nohit) $2=prompt $3=required-token(optional, load-bearing for a hit case -
          # round-3 review found a hit-only assertion passes even if the WRONG token fired, since a
          # prompt carrying two candidate tokens logs a hit regardless of which one actually matched)
  want="$1"; prompt="$2"; token="${3:-}"
  b="$(before_lines)"
  printf '%s\n' "$prompt" | jq -Rs '{tool_input: {prompt: .}}' | sh "$GUARD" >/dev/null 2>&1
  a="$(before_lines)"
  NEWLINE=""
  if [ "$a" -gt "$b" ]; then NEWLINE="$(tail -n "$((a - b))" "$LOG" 2>/dev/null)"; fi
  if printf '%s' "$NEWLINE" | grep -aq "framing-guard hit"; then got=hit; else got=nohit; fi
  if [ "$got" = "hit" ] && [ -n "$token" ] && ! printf '%s' "$NEWLINE" | grep -aqE "[(,]${token}[,)]"; then
    got=hit-wrong-token   # a hit fired, but not for the token this case is meant to prove
  fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$prompt"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$prompt"; fail=1; fi
}

# should log a hit (narrow glossary: M-numbers, SC-ids, XLAB-ids, "agent-tiers" literal) - token
# arg makes each case load-bearing (round 3: a hit-only assertion is tautological when the prompt
# carries more than one candidate token, since ANY of them firing looks identical to the check)
check hit 'Spawn a Worker to gap-check whether M2 covers this per SC-4.1a.' M2
check hit 'Have an XLAB-12 aware Advisor review this design.' XLAB-12
check hit 'Check this against agent-tiers doctrine.' agent-tiers

# should NOT hit - unprimed / no kit vocabulary, INCLUDING the plain-English tier words the 2026-08-06
# review found were flooding the shared log (narrowed glossary drops Lead/Worker/Advisor/Reviewer/Boss)
check nohit 'Search this repo for any dead code paths and report what you find.'
check nohit 'Read the whitepapers/ dir and summarize the architecture arguments, blind - no other context.'
check nohit 'You are the team lead on this project - review the worker output and decide.'
check nohit 'Act as an advisor and boss the review of this PR.'
check nohit ''

# regression (round 2, LOW): bare M[0-9]+ matched ordinary Apple-silicon hardware references
check nohit 'reproduce this on an M1 Mac and see if it still happens'
check nohit 'the M2 Ultra build is faster, try it there'
check nohit 'ported to the M3 chip, no framing concepts involved'
# but a genuine M-number hit near unrelated hardware talk still fires (the strip is narrowly scoped
# to the M-number DIRECTLY adjacent to a hardware word, not the whole prompt) - token=M2 makes this
# load-bearing: round 3 found the prior version of this exact case passed even if the strip had nuked
# EVERY M-number, because the prompt also carries SC-4.1a, which fires the hit regardless.
check hit 'M2 covers this per SC-4.1a, unrelated to any M1 Mac mentioned elsewhere' M2

# regression (round 3, LOW): a path mention of the kit's own directory must not log a hit - nearly
# every real brief this kit writes cites a path like this, which was flooding the framing log
check nohit '~/.claude/agent-tiers/scripts/hygiene-commit-guard.sh has a bug, go fix it'
check nohit 'read agent-tiers/scripts/guard-cmdpos.sh before you start'
# but a genuine non-path vocabulary mention still fires
check hit 'this kit is called agent-tiers, check its doctrine' agent-tiers

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

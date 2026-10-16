#!/usr/bin/env sh
# kit-scope: shared
# Self-check for numeric-claim-ledger.sh (Stage 1, log-only): assert (a) a derivation-idiom command is
# recorded in the session's ledger, (b) a bare wc -l/grep -c is NOT recorded (the trigger's whole point
# is excluding routine counts), (c) it NEVER emits any output - Stage 1 is log-only by design, no
# additionalContext, no permissionDecision, ever, (d) a traversal/unsafe session_id writes nothing
# outside the state dir, (e) an unparseable payload fails open silently. Runs inside a throwaway kit
# copy so the real .state is never touched. Exits non-zero on first failure.
set -u
unset AGENT_TIERS_STATE_DAYS AGENT_TIERS_LEDGER_DAYS
SRC="$(dirname "$0")/numeric-claim-ledger.sh"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"   # macOS TMPDIR ends in "/" - a "//" in T breaks every pwd comparison (CI, 2026-08-16)
T="${TMPBASE}/at-numclaim-selfcheck.$$"
rm -rf "$T"; mkdir -p "$T/kit/scripts" || fail "cannot build sandbox"
cp "$SRC" "$T/kit/scripts/" || fail "cannot copy guard"
cp "$(dirname "$0")/guard-cmdpos.sh" "$T/kit/scripts/" || fail "cannot copy guard-cmdpos.sh"
trap 'rm -rf "$T"' EXIT
SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD="$T/kit/scripts/numeric-claim-ledger.sh"
STATE="$T/kit/.state/numeric-claims"
LOG="$T/guards.log"
# kit-gate.sh runs as a child of the guard: the fixture gets a rewritten copy (empty managed dir) and
# options.tsv, and every input the user's own options could reach it through is cleared.
mkdir -p "$T/kit/install" "$T/managed" "$T/cfg"
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$SCRIPTS/kit-gate.sh" > "$T/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$T/kit/scripts/kit-gate.sh" || fail "_kg_managed not rewritten"
cp "$SCRIPTS/../install/options.tsv" "$T/kit/install/"
export CLAUDE_CONFIG_DIR="$T/cfg" AGENT_TIERS_GUARDS_LOG="$LOG"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done

pay() { jq -n --arg s "$1" --arg c "$2" '{session_id:$s, hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:$c}}'; }
run() { printf '%s' "$1" | sh "$GUARD" 2>/dev/null || true; }

# 1. Derivation idioms - each must be recorded.
S1=sess-deriv-1111
run "$(pay "$S1" 'awk "{sum+=\$1} END{print sum}" data.txt')" >/dev/null
grep -q 'sum+=' "$STATE/$S1.tsv" 2>/dev/null || fail "awk sum+= idiom must be recorded"

S2=sess-deriv-2222
run "$(pay "$S2" 'python3 -c "import re; print(len(re.findall(r\"\\w+\", open(\"x\").read())))"')" >/dev/null
[ -f "$STATE/$S2.tsv" ] || fail "python re.findall idiom must be recorded"

S3=sess-deriv-3333
run "$(pay "$S3" 'echo "$MATCHED / $TOTAL" | bc -l')" >/dev/null
[ -f "$STATE/$S3.tsv" ] || fail "| bc arithmetic idiom must be recorded"

S4=sess-deriv-4444
run "$(pay "$S4" 'x+=1; echo $x')" >/dev/null
[ -f "$STATE/$S4.tsv" ] || fail "bare += idiom must be recorded"

# S1's awk fixture above also contains a literal `+=`, so it passes via that alternative alone and
# never actually exercises the `awk[^|;&]*\{[^}]*sum\}` branch on its own - isolate it with a program
# that sums WITHOUT `+=`.
S6=sess-deriv-6666
run "$(pay "$S6" "awk '{sum = sum + \$1} END{print sum}' data.txt")" >/dev/null
[ -f "$STATE/$S6.tsv" ] || fail "awk-brace-sum idiom (no +=) must be recorded on its own"

# 2. Bare counts - must NOT be recorded (the precision the trigger exists for).
S5=sess-bare-5555
run "$(pay "$S5" 'grep -c foo file.txt')" >/dev/null
[ -f "$STATE/$S5.tsv" ] && fail "bare grep -c must NOT be recorded"
run "$(pay "$S5" 'rg foo file.txt | wc -l')" >/dev/null
[ -f "$STATE/$S5.tsv" ] && fail "bare rg | wc -l must NOT be recorded"

# 3. NEVER any output - Stage 1 is log-only, no exception. Checked on ALL THREE channels: `run()`
#    above discards stderr and swallows the exit code, so it only tests stdout - the actual PostToolUse
#    model-visible failure mode is exit 2 + stderr (the feed-back-to-Claude path), which that helper
#    can't catch. stdout/stderr captured separately via temp files (a single command substitution can't
#    hold both), exit code checked explicitly.
OUTF="$T.stdout"; ERRF="$T.stderr"
printf '%s' "$(pay "$S1" 'awk "{sum+=\$1} END{print sum}" data.txt')" | sh "$GUARD" >"$OUTF" 2>"$ERRF"
RC=$?
[ -s "$OUTF" ] && fail "Stage 1 must never emit stdout (log-only), got: $(cat "$OUTF")"
[ -s "$ERRF" ] && fail "Stage 1 must never emit stderr (log-only), got: $(cat "$ERRF")"
[ "$RC" -eq 0 ] || fail "Stage 1 must always exit 0 (a nonzero exit is the PostToolUse blocking channel), got rc=$RC"
rm -f "$OUTF" "$ERRF"

# 4. Traversal / unsafe session_id writes nothing outside the state dir. guards.log is excluded from
#    the diff - a fail-open breadcrumb THERE is the guard behaving correctly (every guard in this kit
#    does this); the property under test is "no ledger file for the bad id, nothing outside .state/".
CANARY="$T/kit/canary"; echo "CANARY-MUST-NOT-LEAK" > "$CANARY"
before="$(find "$T/kit" -type f | grep -v '/.state/guards.log$' | sort)"
for bad in "../../canary" "." ".." "a/b" '$(id)' ""; do
  run "$(pay "$bad" 'x+=1')" >/dev/null
done
after="$(find "$T/kit" -type f | grep -v '/.state/guards.log$' | sort)"
[ "$before" = "$after" ] || fail "an unsafe session_id created files outside the state dir"
grep -q CANARY-MUST-NOT-LEAK "$CANARY" || fail "canary was clobbered"

# 5. Unparseable payload is a silent fail-open, not a crash.
out="$(printf '%s' 'garbage {{{' | sh "$GUARD" 2>/dev/null || true)"
[ -z "$out" ] || fail "unparseable payload must produce no output"

# 6. Stand-down via kit-gate.sh: the ledger write is skipped entirely, exit 0, one kit-gate log line.
S6C=sess-standdown-ctl
run "$(pay "$S6C" 'awk "{sum+=\$1} END{print sum}" data.txt')" >/dev/null   # control: no marker, same payload must record
[ -s "$STATE/$S6C.tsv" ] || fail "stand-down: control run (no marker) recorded nothing, fixture drifted"
mkdir -p "$T/kit/.state/off"; : > "$T/kit/.state/off/numeric-claim-ledger"
S6=sess-standdown-6666
out="$(printf '%s' "$(pay "$S6" 'awk "{sum+=\$1} END{print sum}" data.txt')" | sh "$GUARD" 2>/dev/null)"; rc=$?
rm -f "$T/kit/.state/off/numeric-claim-ledger"
[ -z "$out" ] && [ "$rc" = 0 ] || fail "stand-down: want empty stdout and exit 0 (rc=$rc out=$out)"
[ ! -e "$STATE/$S6.tsv" ] || fail "stand-down: ledger was written despite the marker"
grep -aq 'kit-gate standdown numeric-claim-ledger:' "$LOG" 2>/dev/null || fail "stand-down: no kit-gate log line"

# 10. Caller identity comes from guard_caller_agent: a `--agent` main (agent_type, NO agent_id) is MAIN;
# a plugin-namespaced subagent (agent_type + agent_id) is its bare name.
S10=sess-agent-1010
run "$(pay "$S10" 'echo x | bc -l' | jq -c '. + {agent_type:"foo"}')" >/dev/null
[ "$(tail -n 1 "$STATE/$S10.tsv" | cut -f2)" = MAIN ] || fail "--agent main (no agent_id) must be recorded as MAIN"
run "$(pay "$S10" 'echo x | bc -l' | jq -c '. + {agent_type:"agent-tiers:worker", agent_id:"a1b2"}')" >/dev/null
[ "$(tail -n 1 "$STATE/$S10.tsv" | cut -f2)" = worker ] || fail "namespaced subagent must be recorded as worker"

rm -rf "$T"
echo "OK numeric-claim-ledger: derivation idioms recorded, bare counts excluded, log-only (zero output), traversal-safe"

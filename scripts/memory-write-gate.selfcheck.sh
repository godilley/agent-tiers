#!/usr/bin/env sh
# kit-scope: shared
# Self-check for memory-write-gate.sh.
#
# The three cases the plan of record names are 3, 4 and 6 below: a memory write with neither piece of
# evidence is denied; the same write carrying both is allowed in exactly ONE extra turn; and under
# /unattended it proceeds and logs pending rather than deadlocking. Case 5 is the one that would not
# have been written from the plan alone - the guard's own denial reason contains the memory path, so a
# text-level coverage check would let the immediate retry through.
#
# State sandboxing is mandatory: CLAUDE_CONFIG_DIR and AGENT_TIERS_GUARDS_LOG both point into one
# mktemp -d. MAINT-8 records an incident where 163 of 163 guards.log lines were fixture noise.
set -u

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GATE="$SCRIPTS/memory-write-gate.sh"
[ -f "$GATE" ] || { echo "FAIL: memory-write-gate.sh not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (gate fails open by design)"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

CDIR="$T/.claude"
MEMDIR="$CDIR/projects/slug/memory"
mkdir -p "$MEMDIR" "$CDIR/agent-tiers/scripts/lib" "$CDIR/agent-tiers/.state"
cp "$GATE" "$CDIR/agent-tiers/scripts/"
cp "$SCRIPTS/lib/guard-mempath.sh" "$CDIR/agent-tiers/scripts/lib/"
cp "$SCRIPTS/guard-cmdpos.sh" "$CDIR/agent-tiers/scripts/"
G="$CDIR/agent-tiers/scripts/memory-write-gate.sh"
LOG="$T/guards.log"
TARGET="$MEMDIR/new-fact.md"

run() {  # run <transcript-path-or-empty> <payload-json>; prints the gate's stdout
  printf '%s' "$2" | CLAUDE_CONFIG_DIR="$CDIR" AGENT_TIERS_GUARDS_LOG="$LOG" sh "$G" 2>/dev/null
}
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }

# A transcript line carrying one assistant tool_use block.
tu() {  # tu <tool-name> <input-json>
  jq -c -n --arg n "$1" --argjson i "$2" \
    '{message: {role: "assistant", content: [{type: "tool_use", name: $n, input: $i}]}}'
}
user_text() { jq -c -n --arg t "$1" '{message: {role: "user", content: [{type: "text", text: $t}]}}'; }
tool_result() { jq -c -n --arg t "$1" '{message: {role: "user", content: [{type: "tool_result", content: $t}]}}'; }

payload() {  # payload <tool> <file-or-cmd> <transcript> [agent_type]
  if [ "$1" = "Bash" ]; then
    jq -n --arg c "$2" --arg tr "$3" --arg a "${4:-}" \
      '{tool_name: "Bash", tool_input: {command: $c}, transcript_path: $tr, session_id: "sess1"}
       + (if $a == "" then {} else {agent_type: $a} end)'
  else
    jq -n --arg p "$2" --arg tr "$3" --arg a "${4:-}" \
      '{tool_name: "Write", tool_input: {file_path: $p}, transcript_path: $tr, session_id: "sess1"}
       + (if $a == "" then {} else {agent_type: $a} end)'
  fi
}

# --- case 1: a write outside any memory dir is untouched -------------------------------------------
# Fails if the gate fires on ordinary work, which is what would get it switched off within a day.
TR="$T/t1.jsonl"; user_text "do a thing" > "$TR"
out="$(run "$TR" "$(payload Write "$T/notes.md" "$TR")")"
[ -z "$out" ] || fail "case 1: gate fired on a non-memory path: $out"

# --- case 2: the kill switch is honoured before anything else --------------------------------------
# Fails if the documented escape does not work, which would make the gate unremovable without an edit.
touch "$CDIR/agent-tiers/.state/off/memory-write-gate" 2>/dev/null \
  || { mkdir -p "$CDIR/agent-tiers/.state/off" && touch "$CDIR/agent-tiers/.state/off/memory-write-gate"; }
out="$(run "$TR" "$(payload Write "$TARGET" "$TR")")"
[ -z "$out" ] || fail "case 2: kill switch did not silence the gate: $out"
rm -f "$CDIR/agent-tiers/.state/off/memory-write-gate"

# --- case 3 (PLAN CHECK a): no coverage check, no question -> DENY ---------------------------------
# Fails if the live failure this whole guard exists for still goes through.
TR="$T/t3.jsonl"; { user_text "write that up"; tu Read '{"file_path":"/etc/hosts"}'; } > "$TR"
out="$(run "$TR" "$(payload Write "$TARGET" "$TR")")"
[ "$(decision "$out")" = "deny" ] || fail "case 3: an unchecked, unasked memory write was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'coverage check' || fail "case 3: the denial does not name the coverage check"
printf '%s' "$out" | grep -q 'AskUserQuestion' || fail "case 3: the denial does not name the question"

# --- case 4 (PLAN CHECK b): both pieces present -> ALLOW, in ONE extra turn -------------------------
# "One extra turn" is the design's whole cost claim. Evidence from the SAME turn as the write must be
# enough; if this needed a further user message the cost would be two turns and the claim false.
TR="$T/t4.jsonl"
{ user_text "write that up"
  tu Grep "$(jq -c -n --arg d "$MEMDIR" '{pattern: "fact", path: $d}')"
  tu AskUserQuestion '{"questions":[{"question":"save this?","header":"Memory","options":[]}]}'
} > "$TR"
out="$(run "$TR" "$(payload Write "$TARGET" "$TR")")"
[ -z "$out" ] || fail "case 4: a write carrying both a coverage check and a question was not allowed silently (got: $out)"

# --- case 4b/4c: a Bash coverage check spelled home-relative after a cd, or with a tilde ---------------
# Observed 2026-09-28: `cd $HOME && rg ... .claude/projects/<slug>/memory` never contains the absolute
# dir as one string, so the gate denied three correct retries. HOME is pointed at the fixture so the
# home-relative form of MEMDIR is what the command carries. Both cases fail on the absolute-only test.
REL="${MEMDIR#"$T"/}"
TR="$T/t4b.jsonl"
{ user_text "write that up"
  tu Bash "$(jq -c -n --arg c "cd $T && rg -il fact $REL" '{command: $c}')"
  tu AskUserQuestion '{"questions":[{"question":"save this?","header":"Memory","options":[]}]}'
} > "$TR"
out="$(HOME="$T" run "$TR" "$(payload Write "$TARGET" "$TR")")"
[ -z "$out" ] || fail "case 4b: a home-relative Bash coverage check after cd was not accepted (got: $out)"

TR="$T/t4c.jsonl"
{ user_text "write that up"
  tu Bash "$(jq -c -n --arg c "rg -il fact ~/$REL" '{command: $c}')"
  tu AskUserQuestion '{"questions":[{"question":"save this?","header":"Memory","options":[]}]}'
} > "$TR"
out="$(HOME="$T" run "$TR" "$(payload Write "$TARGET" "$TR")")"
[ -z "$out" ] || fail "case 4c: a tilde-spelled Bash coverage check was not accepted (got: $out)"

# --- case 5: the guard's own denial must not satisfy the retry -------------------------------------
# The denial reason names the memory path and lands in the transcript as a tool_result. A text-level
# scan would count that as the coverage check and allow the immediate retry - the gate would then pass
# every second attempt, silently, forever. Fails if the structural tool_use test is dropped.
TR="$T/t5.jsonl"
{ user_text "write that up"
  tu Write "$(jq -c -n --arg p "$TARGET" '{file_path: $p}')"
  tool_result "agent-tiers MEMORY-5: writing '$TARGET' needs a coverage check and a question to the operator first, in this same turn. (1) Search for existing coverage - the memory index and fact files under $MEMDIR ..."
  tu AskUserQuestion '{"questions":[{"question":"save this?","header":"Memory","options":[]}]}'
} > "$TR"
out="$(run "$TR" "$(payload Write "$TARGET" "$TR")")"
[ "$(decision "$out")" = "deny" ] \
  || fail "case 5: the guard's own denial text satisfied the coverage check on retry (got: ${out:-<silence>})"

# --- case 6 (PLAN CHECK c): unattended proceeds and logs pending -----------------------------------
# Without this arm the write is denied AND its remedy (AskUserQuestion) is denied by unattended-guard,
# so no memory could be written at all. Fails on a deadlock.
mkdir -p "$CDIR/agent-tiers/.state"
: > "$CDIR/agent-tiers/.state/unattended.sess1"
TR="$T/t6.jsonl"; user_text "write that up" > "$TR"
out="$(run "$TR" "$(payload Write "$TARGET" "$TR")")"
[ "$(decision "$out")" = "deny" ] && fail "case 6: DEADLOCK - unattended session denied, with no way to ask"
printf '%s' "$out" | grep -q 'RESUME_SESSION' || fail "case 6: the unattended allowance does not say to carry it to the handoff"
grep -aq 'allow (pending).*unattended' "$LOG" 2>/dev/null || fail "case 6: no pending breadcrumb logged"
rm -f "$CDIR/agent-tiers/.state/unattended.sess1"

# --- case 7: a subagent caller is armed the same way ------------------------------------------------
# An agent cannot put a question to a human either. Fails if only the unattended arm was built - the
# shape the plan called mandatory, and the one a Write-path-only implementation would miss.
TR="$T/t7.jsonl"; user_text "write that up" > "$TR"
out="$(run "$TR" "$(payload Write "$TARGET" "$TR" worker)")"
[ "$(decision "$out")" = "deny" ] && fail "case 7: a subagent's memory write was denied with no remedy available to it"
printf '%s' "$out" | grep -q 'subagent' || fail "case 7: the subagent allowance does not explain itself"

# --- case 8 (R2): the Bash path is covered ----------------------------------------------------------
# The file-tool matcher alone leaves `sed -i`/`tee` into the memory dir wide open - the bypass
# cards/MEMORY.md discloses. Fails if the Bash arm is absent or does not resolve the target.
TR="$T/t8.jsonl"; user_text "write that up" > "$TR"
out="$(run "$TR" "$(payload Bash "sed -i 's/a/b/' $TARGET" "$TR")")"
[ "$(decision "$out")" = "deny" ] || fail "case 8: sed -i into the memory dir was not caught (got: ${out:-<silence>})"
out="$(run "$TR" "$(payload Bash "sed -i 's/a/b/' $T/unrelated.md" "$TR")")"
[ -z "$out" ] || fail "case 8: sed -i on an unrelated file was caught (false positive): $out"
out="$(run "$TR" "$(payload Bash "grep -r foo $MEMDIR" "$TR")")"
[ -z "$out" ] || fail "case 8: a READ of the memory dir was treated as a write: $out"

# --- case 9: fail-open on a missing transcript, with a breadcrumb -----------------------------------
# Stage 0's decision: fail-open, but never silently. Fails if a tooling gap either blocks work or
# leaves no trace that the rule stopped being enforced.
: > "$LOG"
out="$(run "" "$(payload Write "$TARGET" "$T/does-not-exist.jsonl")")"
[ -z "$out" ] || fail "case 9: a missing transcript blocked the write instead of failing open: $out"
grep -aq 'fail-open: no readable transcript_path' "$LOG" 2>/dev/null \
  || fail "case 9: the fail-open left no breadcrumb"

# --- case 10: a partial window degrades to the missing half only ------------------------------------
# Observed live: with a coverage check already done, the denial asked only for the question. A message
# that re-demands work already finished teaches the reader to stop reading it. Fails if the guard
# repeats the satisfied half.
TR="$T/t10.jsonl"
{ user_text "write that up"
  tu Grep "$(jq -c -n --arg d "$MEMDIR" '{pattern: "fact", path: $d}')"
} > "$TR"
out="$(run "$TR" "$(payload Write "$TARGET" "$TR")")"
[ "$(decision "$out")" = "deny" ] || fail "case 10: a coverage check alone was treated as sufficient (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'AskUserQuestion' || fail "case 10: the denial does not name the missing question"
printf '%s' "$out" | grep -q 'coverage check' && fail "case 10: the denial re-demands the coverage check that was already done"

if [ "$fails" -eq 0 ]; then
  echo "OK memory-write-gate: non-memory writes untouched, kill switch honoured, unchecked writes denied with both remedies named, a checked+asked write allowed in one extra turn, the guard's own denial cannot satisfy its retry, unattended and subagent callers armed rather than deadlocked, the sed -i bypass covered without false positives, and a missing transcript fails open with a breadcrumb, and a half-satisfied window is denied naming only the missing half"
  exit 0
fi
printf 'memory-write-gate: %s case(s) failed\n' "$fails"
exit 1

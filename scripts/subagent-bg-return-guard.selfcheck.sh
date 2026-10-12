#!/usr/bin/env sh
# kit-scope: shared
# Self-check for subagent-bg-return-guard.sh.
#
# Each case is a real measurement, not a smoke test: the do-nothing agent (only its own "subagent" row
# present) and the session-wide case (a running shell owned by someone else) are negative CONTROLS -
# without them a bare "background_tasks non-empty" or "any running shell" implementation would pass this
# selfcheck while blocking every innocent agent in a busy session.
#
# State sandboxing: BASE points into one mktemp -d (kill switch, marker dir, guards.log all live under
# it), never the real kit .state/.
set -u
unset AGENT_TIERS_STATE_DAYS AGENT_TIERS_LEDGER_DAYS

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
SRC="$SCRIPTS/subagent-bg-return-guard.sh"
[ -f "$SRC" ] || { echo "FAIL: subagent-bg-return-guard.sh not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

# `touch -d` is GNU-only (BSD/macOS touch has no -d) - stamp mtimes portably via `touch -t`.
# $2 is "-Nd" (N days ago).
touch_at() {
  n="${2%d}"; n="${n#-}"
  ts="$(date -v-"${n}"d +%Y%m%d%H%M 2>/dev/null || date -d "${n} days ago" +%Y%m%d%H%M)"
  [ -n "$ts" ] || { fail "touch_at: no usable date(1) for spec '$2'"; return; }
  touch -t "$ts" "$1" || fail "touch_at: touch -t $ts failed"
}

# The guard resolves its own KIT_ROOT (kill switch + marker dir) from dirname("$0")/.. - not env-
# overridable like the log path - so the guard must be COPIED into a sandboxed scripts/ dir and invoked
# from there, or its state would land in the real kit's .state/ (same pattern memory-write-gate's
# selfcheck uses).
BASE="$T/kit"
mkdir -p "$BASE/scripts" "$BASE/.state"
cp "$SRC" "$BASE/scripts/subagent-bg-return-guard.sh"
GUARD="$BASE/scripts/subagent-bg-return-guard.sh"
LOG="$BASE/.state/guards.log"

run() {  # run <payload-json> ; sets RC and STDERR, prints nothing to stdout by design
  errf="$T/stderr.$$"
  printf '%s' "$1" | AGENT_TIERS_GUARDS_LOG="$LOG" sh "$GUARD" 2>"$errf"
  RC=$?
  STDERR="$(cat "$errf" 2>/dev/null || true)"
  rm -f "$errf"
}

# background_tasks builder: shell($1 id, $2 status) or the agent's own subagent row
shell_task() { jq -n --arg id "$1" --arg st "$2" '{id: $id, type: "shell", status: $st, description: "x", command: "x"}'; }
own_task() { jq -n --arg id "$1" '{id: $id, type: "subagent", status: "running", description: "x", agent_type: "worker"}'; }

payload() {  # payload <agent_id> <session_id> <transcript> <tasks-json-array>
  jq -n --arg a "$1" --arg s "$2" --arg t "$3" --argjson tasks "$4" \
    '{agent_id: $a, session_id: $s, agent_transcript_path: $t, background_tasks: $tasks}'
}

# --- case 1: the do-nothing agent (only its own subagent row) -> silent allow ------------------------
# Would fail an implementation that treats a non-empty background_tasks array alone as "block".
TR1="$T/t1.jsonl"; : > "$TR1"
TASKS="[$(own_task agent1)]"
run "$(payload agent1 sess1 "$TR1" "$TASKS")"
[ "$RC" = 0 ] && [ -z "$STDERR" ] || fail "case 1: do-nothing agent was blocked (rc=$RC stderr=$STDERR)"

# --- case 2: a running shell id owned by THIS agent's own transcript -> block ------------------------
TR2="$T/t2.jsonl"
printf 'moved to the background (ID: bk11aq5js)\n' > "$TR2"
TASKS="[$(shell_task bk11aq5js running),$(own_task agent2)]"
run "$(payload agent2 sess1 "$TR2" "$TASKS")"
[ "$RC" = 2 ] || fail "case 2: owned running shell was not blocked (rc=$RC)"
printf '%s' "$STDERR" | grep -qF -- "bk11aq5js" || fail "case 2: stderr does not name the offending id"
grep -aq 'blocked: agent agent2.*bk11aq5js' "$LOG" 2>/dev/null || fail "case 2: block not logged"

# --- case 3 (SESSION-WIDE control): a running shell present but NOT in this agent's own transcript ---
# The critical negative control: background_tasks is session-wide and carries no owner field, so an
# agent that started nothing must not be blocked just because someone else has something running.
TR3="$T/t3.jsonl"; printf 'nothing background-related here\n' > "$TR3"
TASKS="[$(shell_task otherguysshell running),$(own_task agent3)]"
run "$(payload agent3 sess1 "$TR3" "$TASKS")"
[ "$RC" = 0 ] && [ -z "$STDERR" ] || fail "case 3: an unowned running shell (someone else's) blocked an innocent agent (rc=$RC stderr=$STDERR)"

# --- case 4: an owned id, but status is not running -> allow ------------------------------------------
TR4="$T/t4.jsonl"; printf 'running in background with ID: bk22bb (already done)\n' > "$TR4"
TASKS="[$(shell_task bk22bb completed),$(own_task agent4)]"
run "$(payload agent4 sess1 "$TR4" "$TASKS")"
[ "$RC" = 0 ] && [ -z "$STDERR" ] || fail "case 4: a completed (non-running) owned shell was blocked (rc=$RC)"

# --- case 5: the marker case - a second stop for the SAME agent_id is not blocked twice ---------------
# Without this, a task that never finishes on its own (a dev server, a watch loop) traps the agent in an
# unbreakable loop.
TR5="$T/t5.jsonl"; printf 'running in background with ID: bk33cc\n' > "$TR5"
TASKS="[$(shell_task bk33cc running),$(own_task agent5)]"
run "$(payload agent5 sess1 "$TR5" "$TASKS")"
[ "$RC" = 2 ] || fail "case 5a: first stop for agent5 was not blocked (rc=$RC)"
run "$(payload agent5 sess1 "$TR5" "$TASKS")"
[ "$RC" = 0 ] && [ -z "$STDERR" ] || fail "case 5b: second stop for the same agent_id was blocked again (rc=$RC stderr=$STDERR)"
grep -aq 'already blocked once for agent agent5' "$LOG" 2>/dev/null || fail "case 5b: marker allow not logged"

# --- case 6: kill switch -------------------------------------------------------------------------------
mkdir -p "$BASE/.state/off" && touch "$BASE/.state/off/subagent-bg-return-guard"
TR6="$T/t6.jsonl"; printf 'moved to the background (ID: bk44dd)\n' > "$TR6"
TASKS="[$(shell_task bk44dd running)]"
run "$(payload agent6 sess1 "$TR6" "$TASKS")"
[ "$RC" = 0 ] && [ -z "$STDERR" ] || fail "case 6: kill switch did not silence the guard (rc=$RC)"
rm -f "$BASE/.state/off/subagent-bg-return-guard"

# --- case 7: jq missing -> fail open with a breadcrumb (simulated by hiding jq from PATH) --------------
TR7="$T/t7.jsonl"; : > "$TR7"
NOJQ_DIR="$T/nojq-path"
mkdir -p "$NOJQ_DIR"
for tool in sh cat printf grep find mkdir date rm sed tr dirname; do
  p="$(command -v "$tool" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$NOJQ_DIR/$tool" 2>/dev/null
done
: > "$LOG"
printf '%s' "" | PATH="$NOJQ_DIR" AGENT_TIERS_GUARDS_LOG="$LOG" sh "$GUARD" 2>"$T/stderr7" >/dev/null
RC=$?
[ "$RC" = 0 ] || fail "case 7: missing jq did not fail open (rc=$RC)"
grep -aq 'fail-open: jq missing' "$LOG" 2>/dev/null || fail "case 7: missing-jq fail-open left no breadcrumb"

# --- case 8: agent_transcript_path unreadable/absent -> fail open with a breadcrumb ---------------------
: > "$LOG"
TASKS="[$(shell_task bk55ee running)]"
run "$(jq -n --arg t "$T/does-not-exist.jsonl" --argjson tasks "$TASKS" '{agent_id: "agent8", session_id: "sess1", agent_transcript_path: $t, background_tasks: $tasks}')"
[ "$RC" = 0 ] && [ -z "$STDERR" ] || fail "case 8: unreadable transcript blocked instead of failing open (rc=$RC stderr=$STDERR)"
grep -aq 'fail-open: no readable agent_transcript_path' "$LOG" 2>/dev/null || fail "case 8: unreadable-transcript fail-open left no breadcrumb"

# --- case 9-12: AGENT_TIERS_STATE_DAYS governs the marker-dir GC window --------------------------------
# A payload with a running+owned shell for a throwaway agent id reaches the GC line on every run;
# its own marker file is irrelevant here, only the pre-seeded aged file's survival is checked.
MARKER_DIR="$BASE/.state/subagent-bg-return-seen"
mkdir -p "$MARKER_DIR"
gc_probe() {  # gc_probe <env-prefix> -> runs a GC-reaching payload under that env
  TRGC="$T/tgc.jsonl"; printf 'moved to the background (ID: gcid)\n' > "$TRGC"
  TASKSGC="[$(shell_task gcid running),$(own_task gcagent)]"
  printf '%s' "$(payload gcagent sess1 "$TRGC" "$TASKSGC")" | env $1 AGENT_TIERS_GUARDS_LOG="$LOG" sh "$GUARD" >/dev/null 2>&1
  rm -f "$MARKER_DIR/gcagent"   # never let this probe's own marker affect the next probe
}

# case 9: default (no override) deletes a 9-day-old file. (9, not 8: a DST spring-forward can make
# "8 days ago" only 7d23h, landing the wrong side of the +7 boundary.)
: > "$MARKER_DIR/old9"; touch_at "$MARKER_DIR/old9" -9d
gc_probe ""
[ -f "$MARKER_DIR/old9" ] && fail "case 9: a 9-day-old marker file was not GC'd under the 7-day default"

# case 10: AGENT_TIERS_STATE_DAYS=30 keeps the same 9-day-old file.
: > "$MARKER_DIR/old9b"; touch_at "$MARKER_DIR/old9b" -9d
gc_probe "AGENT_TIERS_STATE_DAYS=30"
[ -f "$MARKER_DIR/old9b" ] || fail "case 10: AGENT_TIERS_STATE_DAYS=30 did not keep a 9-day-old file"
rm -f "$MARKER_DIR/old9b"

# case 11: AGENT_TIERS_STATE_DAYS=abc (not a positive integer) falls back to the 7-day default, so a
# 3-day-old file is kept either way.
: > "$MARKER_DIR/young3a"; touch_at "$MARKER_DIR/young3a" -3d
gc_probe "AGENT_TIERS_STATE_DAYS=abc"
[ -f "$MARKER_DIR/young3a" ] || fail "case 11: AGENT_TIERS_STATE_DAYS=abc did not fall back to 7 (kept 3-day-old file)"
rm -f "$MARKER_DIR/young3a"

# case 12: AGENT_TIERS_STATE_DAYS=0 also falls back to the 7-day default.
: > "$MARKER_DIR/young3b"; touch_at "$MARKER_DIR/young3b" -3d
gc_probe "AGENT_TIERS_STATE_DAYS=0"
[ -f "$MARKER_DIR/young3b" ] || fail "case 12: AGENT_TIERS_STATE_DAYS=0 did not fall back to 7 (kept 3-day-old file)"
rm -f "$MARKER_DIR/young3b"

# case 13: AGENT_TIERS_STATE_DAYS=00 (all-zero digits, still digit-only) must not slip past the
# case-pattern check as a non-"0" literal - the numeric range check below it must still catch it and
# fall back to 7, so a 3-day-old file survives rather than being read as `-mtime +00` (deletes
# anything not modified in the last 24h).
: > "$MARKER_DIR/young3c"; touch_at "$MARKER_DIR/young3c" -3d
gc_probe "AGENT_TIERS_STATE_DAYS=00"
[ -f "$MARKER_DIR/young3c" ] || fail "case 13: AGENT_TIERS_STATE_DAYS=00 did not fall back to 7 (kept 3-day-old file)"
rm -f "$MARKER_DIR/young3c"

# case 14: AGENT_TIERS_STATE_DAYS=99999 (digit-only but absurdly large) falls back to 7 via the
# upper-bound check, so a 9-day-old file is still GC'd rather than kept forever.
: > "$MARKER_DIR/old9c"; touch_at "$MARKER_DIR/old9c" -9d
gc_probe "AGENT_TIERS_STATE_DAYS=99999"
[ -f "$MARKER_DIR/old9c" ] && fail "case 14: AGENT_TIERS_STATE_DAYS=99999 did not fall back to 7 (kept a 9-day-old file)"

if [ "$fails" -eq 0 ]; then
  echo "PASS subagent-bg-return-guard: 14/14 cases"
  exit 0
fi
printf 'subagent-bg-return-guard: %s case(s) failed\n' "$fails"
exit 1

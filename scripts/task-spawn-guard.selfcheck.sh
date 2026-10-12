#!/usr/bin/env sh
# kit-scope: shared
# Self-check for task-spawn-guard.sh. Runnable: `sh scripts/task-spawn-guard.selfcheck.sh` from the
# kit root. State sandboxing is mandatory: the guard is copied into a temp scripts/ dir (KIT_ROOT is
# derived from the script's own location, so this is what sandboxes the kill switch too), and
# AGENT_TIERS_GUARDS_LOG points into the same mktemp -d, per MAINT-8 (a selfcheck that writes the real
# .state/guards.log once produced 163 of 163 fixture lines in a real log).
set -u

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
SRC="$SCRIPTS/task-spawn-guard.sh"
[ -f "$SRC" ] || { echo "FAIL: task-spawn-guard.sh not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

# The guard is copied into a temp scripts/ dir so KIT_ROOT-derived kill-switch resolution never
# touches the real kit's .state/off/. guard-cmdpos.sh ships beside it (RULE D sources it for
# guard_caller_agent/guard_ask_decision/guard_ask_prefix); its absence is covered by a fail-open path,
# not this sandbox, so it is copied unconditionally here.
KIT="$T/kit"
mkdir -p "$KIT/scripts" "$KIT/.state"
cp "$SRC" "$KIT/scripts/"
[ -f "$SCRIPTS/guard-cmdpos.sh" ] && cp "$SCRIPTS/guard-cmdpos.sh" "$KIT/scripts/"
GUARD="$KIT/scripts/task-spawn-guard.sh"
LOG="$T/guards.log"

run() {  # run <payload-json>; prints the guard's stdout. AGENT_TIERS_STATE_DIR is cleared for this
         # call only (empty, same effect as unset on the guard's ${VAR:-} reads) so a value inherited
         # from the real environment can never leak past the sandboxed KIT dir.
  printf '%s' "$1" | AGENT_TIERS_GUARDS_LOG="$LOG" AGENT_TIERS_STATE_DIR= "${GUARD_SH:-sh}" "$GUARD" 2>/dev/null
}
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }

payload() {  # payload <subagent_type> <prompt> [model] [agent_type] -> same shape as other selfchecks
             # (review-gate-guard.selfcheck.sh's run(), simple-rules-guard.selfcheck.sh): agent_type is
             # a top-level field, absent means "no agent" (the Lead itself), per guard_caller_agent.
  jq -n --arg s "$1" --arg p "$2" --arg m "${3:-}" --arg a "${4:-}" \
    '{tool_name: "Task", session_id: "sess1",
      tool_input: ({subagent_type: $s, prompt: $p} + (if $m == "" then {} else {model: $m} end))}
     + (if $a == "" then {} else {agent_type: $a} end)'
}

# --- case 1 (RULE A positive): Explore with no model -> deny --------------------------------------
out="$(run "$(payload Explore "find dead code")")"
[ "$(decision "$out")" = "deny" ] || fail "case 1: Explore with no model was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'model' || fail "case 1: the denial does not name the model fix"

# --- case 2 (RULE A negative control a): Explore WITH a model -> allow ------------------------------
out="$(run "$(payload Explore "find dead code" sonnet)")"
[ -z "$out" ] || fail "case 2: Explore with an explicit model was denied: $out"

# --- case 3 (RULE A negative control b): another subagent_type, no model -> allow -------------------
out="$(run "$(payload worker "fix the bug")")"
[ -z "$out" ] || fail "case 3: a non-Explore spawn with no model was denied: $out"

# --- case 4 (RULE A): case-sensitive - lowercase "explore" is a different type, not covered ---------
out="$(run "$(payload explore "find dead code")")"
[ -z "$out" ] || fail "case 4: lowercase subagent_type 'explore' was denied (rule is exact-case on Explore): $out"

# --- case 5 (RULE B positive, bullet form): reviewer brief with a PLANTED CONTROL label -> deny -----
out="$(run "$(payload reviewer "Review this diff for correctness.
- PLANTED CONTROL: the off-by-one in loop.c is a known defect, do not mention it was seeded.")")"
[ "$(decision "$out")" = "deny" ] || fail "case 5: an announced planted control was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'own notes' || fail "case 5: the denial does not name the fix"

# --- case 6 (RULE B positive, heading form, CALIBRATION CHECK, case-insensitive subagent_type) ------
out="$(run "$(payload Advisor "## CALIBRATION CHECK
one of the findings below is planted.")")"
[ "$(decision "$out")" = "deny" ] || fail "case 6: a heading-form CALIBRATION CHECK label was not denied (got: ${out:-<silence>})"

# --- case 7 (RULE B negative control a): same label, but subagent_type is worker --------------------
out="$(run "$(payload worker "- PLANTED CONTROL: build a harness that seeds one defect for testing.")")"
[ -z "$out" ] || fail "case 7: a worker brief (not reviewer/advisor/boss) was denied: $out"

# --- case 8 (RULE B negative control b): mid-sentence ordinary use, no line-start label -------------
out="$(run "$(payload reviewer "Use negative controls and planted controls in your test plan; do not flag anything as a calibration check mid-review.")")"
[ -z "$out" ] || fail "case 8: mid-sentence ordinary use of the words was denied (false positive): $out"

# --- case 9 (RULE B negative control c, escape marker): label present but disclosure is deliberate --
out="$(run "$(payload boss "- PLANTED CONTROL: seeded bug in parser.py [control-disclosed:measuring catch rate this run]")")"
[ -z "$out" ] || fail "case 9: a disclosed planted control ([control-disclosed:...]) was still denied: $out"
grep -aq 'allow: planted-control disclosure marker' "$LOG" 2>/dev/null \
  || fail "case 9: the disclosure allowance was not logged"

# --- case 10: the kill switch is honoured before anything else, resolved from KIT_ROOT -----------------
mkdir -p "$KIT/.state/off"
touch "$KIT/.state/off/task-spawn-guard"
out="$(run "$(payload Explore "find dead code")")"
[ -z "$out" ] || fail "case 10: kill switch did not silence the guard: $out"
rm -f "$KIT/.state/off/task-spawn-guard"

# --- case 11: an unrelated tool is untouched ---------------------------------------------------------
out="$(printf '%s' "$(jq -n '{tool_name: "Bash", tool_input: {command: "ls"}}')" | AGENT_TIERS_GUARDS_LOG="$LOG" AGENT_TIERS_STATE_DIR= "${GUARD_SH:-sh}" "$GUARD" 2>/dev/null)"
[ -z "$out" ] || fail "case 11: guard fired on a non-Task/Agent tool: $out"

# --- case 12 (RULE B positive, bulleted AND bolded form): the prior single-optional-group shape ------
# only allowed ONE prefix marker, so a bullet plus bold ("- **PLANTED CONTROL**") was not caught. This
# is the exact form the guard's own header names as covered.
out="$(run "$(payload reviewer "- **PLANTED CONTROL**: the off-by-one in loop.c is a known defect.")")"
[ "$(decision "$out")" = "deny" ] || fail "case 12: a bulleted-and-bolded PLANTED CONTROL label was not denied (got: ${out:-<silence>})"

# --- case 13 (RULE B negative control, kept alongside case 12): ordinary mid-sentence prose with ------
# both words present is still allowed - the repeated prefix group must not widen the match into prose.
out="$(run "$(payload reviewer "Bold and bulleted planted controls are a normal part of a calibration check test plan; do not treat this sentence as an announcement.")")"
[ -z "$out" ] || fail "case 13: mid-sentence ordinary use of the words was denied (false positive): $out"

# --- case 14 (RULE C positive): worker with model opus, no reason -> deny ------------------------------
out="$(run "$(payload worker "widen the docs value column" opus)")"
[ "$(decision "$out")" = "deny" ] || fail "case 14: an opus worker with no stated reason was not denied (got: ${out:-<silence>})"

# --- case 15 (RULE C escape): worker with model opus AND a reason marker -> allow, logged --------------
out="$(run "$(payload worker "[opus-worker: novel concurrency design] build the scheduler" opus)")"
[ -z "$out" ] || fail "case 15: an opus worker carrying [opus-worker:] was denied: $out"
grep -aq 'allow: opus worker with a stated reason' "$LOG" 2>/dev/null \
  || fail "case 15: the opus-worker allowance was not logged"

# --- case 16 (RULE C negative controls): sonnet worker, and opus on a non-worker type -> allow ---------
out="$(run "$(payload worker "widen the docs value column" sonnet)")"
[ -z "$out" ] || fail "case 16a: a sonnet worker was denied: $out"
out="$(run "$(payload advisor "compare two designs" opus)")"
[ -z "$out" ] || fail "case 16b: an opus advisor was denied (rule C is worker-only): $out"

# --- case 17 (RULE B positive, doctrine-v25 names): LIVENESS CONTROL / RECALL SEED labels -> deny ----
out="$(run "$(payload reviewer "- LIVENESS CONTROL: claim 3 is false.")")"
[ "$(decision "$out")" = "deny" ] || fail "case 17a: a LIVENESS CONTROL label was not denied (got: ${out:-<silence>})"
out="$(run "$(payload reviewer "**RECALL SEED**: the sanitizer at line 208 was deleted.")")"
[ "$(decision "$out")" = "deny" ] || fail "case 17b: a RECALL SEED label was not denied (got: ${out:-<silence>})"
out="$(run "$(payload reviewer "Recall needs a held-back defect or a recall seed per SC-4.2c.")")"
[ -z "$out" ] || fail "case 17c: mid-sentence lower-case 'recall seed' was denied (false positive): $out"

# --- case 18 (RULE D positive): Lead, no agent_type, sublead spawn with no tag -> ask ----------------
out="$(run "$(payload sublead "work the assigned slice")")"
[ "$(decision "$out")" = "ask" ] || fail "case 18: an untagged Lead sublead spawn was not asked (got: ${out:-<silence>})"

# --- case 19 (RULE D escape): Lead, tagged -> allow, logged --------------------------------------------
out="$(run "$(payload sublead "[sublead-approved:plan row 4] work the assigned slice")")"
[ -z "$out" ] || fail "case 19: a tagged sublead spawn from the Lead was not allowed: $out"
grep -aq 'allow: sublead spawn, tag: plan row 4' "$LOG" 2>/dev/null \
  || fail "case 19: the sublead-approved allowance was not logged with its tag text"

# --- case 20 (RULE D unattended): untagged sublead spawn, session flagged unattended -> deny ----------
: > "$KIT/.state/unattended.sess1"
out="$(run "$(payload sublead "work the assigned slice")")"
[ "$(decision "$out")" = "deny" ] || fail "case 20: an unattended untagged sublead spawn was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -aq 'UNATTENDED MODE' || fail "case 20: the deny reason does not carry the unattended-mode prefix"
rm -f "$KIT/.state/unattended.sess1"

# --- case 21 (RULE D depth cap): agent_type=sublead spawning sublead, even tagged -> deny -------------
out="$(run "$(payload sublead "[sublead-approved:plan row 4] nested slice" "" sublead)")"
[ "$(decision "$out")" = "deny" ] || fail "case 21: a sublead-spawned sublead was not denied despite the tag (got: ${out:-<silence>})"

# --- case 22 (RULE D depth cap): agent_type=worker spawning sublead -> deny ----------------------------
out="$(run "$(payload sublead "[sublead-approved:plan row 4] do the slice" "" worker)")"
[ "$(decision "$out")" = "deny" ] || fail "case 22: a worker-spawned sublead was not denied (got: ${out:-<silence>})"

# --- case 23 (RULE D depth cap): agent_type=sublead spawning general-purpose -> deny -------------------
out="$(run "$(payload general-purpose "need broad tool access" "" sublead)")"
[ "$(decision "$out")" = "deny" ] || fail "case 23: a sublead-spawned general-purpose was not denied (got: ${out:-<silence>})"

# --- case 24 (RULE D negative control): Lead spawning general-purpose -> allow -------------------------
out="$(run "$(payload general-purpose "need broad tool access")")"
[ -z "$out" ] || fail "case 24: a Lead-spawned general-purpose was denied: $out"

# --- case 25 (RULE D sentinel): agent_type=main is the Lead's own sentinel, treated as no agent -------
out="$(run "$(payload sublead "work the assigned slice" "" main)")"
[ "$(decision "$out")" = "ask" ] || fail "case 25: agent_type=main sublead spawn was not asked like a plain Lead call (got: ${out:-<silence>})"

# --- case 26 (RULE D fail-open): guard-cmdpos.sh absent -> allow, logged fail-open --------------------
KIT2="$T/kit2"
mkdir -p "$KIT2/scripts" "$KIT2/.state"
cp "$SRC" "$KIT2/scripts/"
LOG2="$T/guards2.log"
out="$(printf '%s' "$(payload sublead "work the assigned slice")" \
  | AGENT_TIERS_GUARDS_LOG="$LOG2" AGENT_TIERS_STATE_DIR= "${GUARD_SH:-sh}" "$KIT2/scripts/task-spawn-guard.sh" 2>/dev/null)"
[ -z "$out" ] || fail "case 26: a sublead spawn with guard-cmdpos.sh absent was not allowed (fail-open): $out"
grep -aq 'fail-open' "$LOG2" 2>/dev/null || fail "case 26: the fail-open was not logged"

# --- case 27 (RULE D edge): tagged sublead spawn with an EMPTY reason -> still allowed, tag visible ---
out="$(run "$(payload sublead "[sublead-approved:] work the assigned slice")")"
[ -z "$out" ] || fail "case 27: a sublead spawn with an empty [sublead-approved:] tag was denied: $out"
grep -aq 'allow: sublead spawn, tag:' "$LOG" 2>/dev/null \
  || fail "case 27: the empty-reason allowance did not log the tag: marker, so the empty reason is invisible"

# --- case 28 (RULE D transcript-miner positive): Lead, untagged transcript-miner spawn -> ask -------
out="$(run "$(payload transcript-miner "mine the corpus")")"
[ "$(decision "$out")" = "ask" ] || fail "case 28: an untagged Lead transcript-miner spawn was not asked (got: ${out:-<silence>})"

# --- case 29 (RULE D transcript-miner escape): Lead, tagged -> allow, logged ------------------------
out="$(run "$(payload transcript-miner "[sublead-approved:plan row M1] mine the corpus")")"
[ -z "$out" ] || fail "case 29: a tagged transcript-miner spawn from the Lead was not allowed: $out"
grep -aq 'allow: transcript-miner spawn, tag: plan row M1' "$LOG" 2>/dev/null \
  || fail "case 29: the tagged transcript-miner allowance was not logged with its tag text"

# --- case 30 (RULE D transcript-miner depth cap): agent_type=sublead spawning transcript-miner -------
out="$(run "$(payload transcript-miner "[sublead-approved:plan row M1] mine the corpus" "" sublead)")"
[ "$(decision "$out")" = "deny" ] || fail "case 30: a sublead-spawned transcript-miner was not denied despite the tag (got: ${out:-<silence>})"

# --- case 31 (RULE D transcript-miner depth cap): agent_type=worker spawning transcript-miner --------
out="$(run "$(payload transcript-miner "[sublead-approved:plan row M1] mine the corpus" "" worker)")"
[ "$(decision "$out")" = "deny" ] || fail "case 31: a worker-spawned transcript-miner was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'only the top Lead spawns a transcript-miner' \
  || fail "case 31: the denial does not name transcript-miner in the depth-cap reason"

# --- case 32 (RULE D transcript-miner depth cap): agent_type=transcript-miner spawning general-purpose
out="$(run "$(payload general-purpose "need broad tool access" "" transcript-miner)")"
[ "$(decision "$out")" = "deny" ] || fail "case 32: a transcript-miner-spawned general-purpose was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'a transcript-miner does not spawn general-purpose' \
  || fail "case 32: the denial does not name transcript-miner in the general-purpose reason"

# --- case 33 (RULE D transcript-miner depth cap): agent_type=transcript-miner spawning another -------
# transcript-miner, even tagged -> deny (a miner spawning sublead was already denied before this rule).
out="$(run "$(payload transcript-miner "[sublead-approved:plan row M1] nested mining run" "" transcript-miner)")"
[ "$(decision "$out")" = "deny" ] || fail "case 33: a transcript-miner-spawned transcript-miner was not denied despite the tag (got: ${out:-<silence>})"

# --- case 34 (RULE D transcript-miner unattended): untagged transcript-miner spawn, session flagged ---
# unattended -> deny with UNATTENDED prefix (mirrors case 20)
: > "$KIT/.state/unattended.sess1"
out="$(run "$(payload transcript-miner "mine the corpus")")"
[ "$(decision "$out")" = "deny" ] || fail "case 34: an unattended untagged transcript-miner spawn was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -aq 'UNATTENDED MODE' || fail "case 34: the deny reason does not carry the unattended-mode prefix"
rm -f "$KIT/.state/unattended.sess1"

# --- case 35 (RULE D transcript-miner depth cap, mixed case): agent_type=Transcript-Miner spawning ---
# general-purpose -> deny (caller-type match must be case-insensitive)
out="$(run "$(payload general-purpose "need broad tool access" "" Transcript-Miner)")"
[ "$(decision "$out")" = "deny" ] || fail "case 35: a mixed-case Transcript-Miner-spawned general-purpose was not denied (got: ${out:-<silence>})"

# --- case 36 (RULE D transcript-miner negative control): agent_type=transcript-miner spawning -------
# worker, and spawning Explore -> allow both. Rule D's case arm never matches these types, so this
# catches a future caller-based deny that over-reaches; Explore carries a model so Rule A stays out.
out="$(run "$(payload worker "fix the bug" "" transcript-miner)")"
[ -z "$out" ] || fail "case 36: a transcript-miner-spawned worker was denied: $out"
out="$(run "$(payload Explore "find dead code" sonnet transcript-miner)")"
[ -z "$out" ] || fail "case 36: a transcript-miner-spawned Explore (with model) was denied: $out"

# --- cases 37-42 (RULE E): a brief naming a host-blocked write target ---------------------------------
# The host refuses a sub-agent Write to a basename matching ^(REPORT|SUMMARY|FINDINGS|ANALYSIS).*\.md$
# (case-insensitive). The guard denies when such a named path does not exist yet (a write target), and
# allows when it exists (a read). cwd resolves relative paths.
mkdir -p "$T/w/old"; : > "$T/w/old/findings.md"
epay() { jq -n --arg p "$1" --arg c "$T/w" '{tool_name: "Task", session_id: "sess1", cwd: $c,
  tool_input: {subagent_type: "reviewer", prompt: $p}}'; }
out="$(run "$(epay "Write your curated findings to $T/w/review/findings.md and return them")")"
[ "$(decision "$out")" = "deny" ] || fail "case 37: absolute new findings.md target was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'review-findings.md' || fail "case 37: the denial does not name the rename fix"
out="$(run "$(epay "write review/FINDINGS.md, then save report-loose-ends.md too")")"
[ "$(decision "$out")" = "deny" ] || fail "case 38: relative new FINDINGS.md / report-*.md targets were not denied"
printf '%s' "$out" | grep -q 'report-loose-ends.md' || fail "case 38: the denial does not list every blocked name"
# case 39 (negative control): the same blocked name, but the file exists (a read).
out="$(run "$(epay "Earlier passes, context only: $T/w/old/findings.md and old/findings.md")")"
[ -z "$out" ] || fail "case 39: an existing findings.md (a read) was denied: $out"
# case 40 (negative control): names the host does not block (prefix, mid-name, other extension, .bak).
out="$(run "$(epay "Write to $T/w/review/review-findings.md and $T/w/x/myfindings.md and /nope/findings.mdx and /nope/findings.md.bak")")"
[ -z "$out" ] || fail "case 40: names the host does not block were denied: $out"
out="$(run "$(epay "[report-name-ok: created first] write $T/w/x/SUMMARY.md")")"
[ -z "$out" ] || fail "case 41: the escape marker did not allow: $out"
out="$(run "$(epay "write $T/w/x/SUMMARY.md")")"
[ "$(decision "$out")" = "deny" ] || fail "case 41: the same prompt without the marker was not denied"
out="$(run "$(epay 'save it to ~/no-such-dir-for-selfcheck/ANALYSIS.md')")"
[ "$(decision "$out")" = "deny" ] || fail "case 42: a ~/ new ANALYSIS.md target was not denied"

# --- cases 43-47 (RULE E): resolution edges -----------------------------------------------------------
# 43: ~/ resolves against HOME - an existing ~/ANALYSIS.md is a read, so allow (a cwd-relative misread of
# "~/" would look missing and deny).
mkdir -p "$T/home"; : > "$T/home/ANALYSIS.md"
out="$(HOME="$T/home"; export HOME; run "$(epay 'context only: ~/ANALYSIS.md')")"
[ -z "$out" ] || fail "case 43: an existing ~/ANALYSIS.md was denied (~/ not resolved against HOME): $out"
# 44: Explore and Plan have no Write tool - never denied, even for a missing name.
out="$(run "$(jq -n '{tool_name: "Task", session_id: "sess1", cwd: "/",
  tool_input: {subagent_type: "Explore", model: "sonnet", prompt: "Find what generates SUMMARY.md"}}')")"
[ -z "$out" ] || fail "case 44: an Explore brief naming SUMMARY.md was denied: $out"
# 45: unresolvable tokens (glob, $VAR, URL, ~user/) are skipped, never denied.
out="$(run "$(epay 'read docs/REPORT-*.md, write $OUT/findings.md, see https://x.io/o/SUMMARY.md and ~alice/findings.md')")"
[ -z "$out" ] || fail "case 45: an unresolvable token was denied: $out"
# 46: no cwd in the payload - a relative name cannot be resolved, so skip, not deny.
out="$(run "$(jq -n '{tool_name: "Task", session_id: "sess1", tool_input: {subagent_type: "worker", prompt: "write review/FINDINGS.md"}}')")"
[ -z "$out" ] || fail "case 46: a relative name with no cwd was denied: $out"
# 47: key=/abs/path and a sentence-final period still resolve to the real path.
out="$(run "$(epay "--prior=$T/w/old/findings.md, then write $T/w/new/findings.md.")")"
printf '%s' "$out" | grep -q "$T/w/new/findings.md" || fail "case 47: the new target was not denied by its real path: ${out:-<silence>}"
printf '%s' "$out" | grep -q 'prior=' && fail "case 47: the key= prefix was swallowed into the path"

if [ "$fails" -eq 0 ]; then
  echo "PASS task-spawn-guard: 47/47 cases"
  exit 0
fi
printf 'task-spawn-guard: %s case(s) failed\n' "$fails"
exit 1

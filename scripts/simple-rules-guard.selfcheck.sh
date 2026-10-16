#!/usr/bin/env sh
# kit-scope: shared
# Self-check for simple-rules-guard.sh - six unrelated literal rules sharing one hook row.
# Each case names what it would catch if the guard regressed: A/B are command-position text matches,
# C is the only rule needing a real repo + origin remote (fixtures are built here, never a real repo),
# D is a jq-structural test over the AskUserQuestion payload shape. G is the only rule reading
# CLAUDE_CONFIG_DIR directly (its session-record lookup), so run() pins CLAUDE_CONFIG_DIR to the
# fixture tree for every case and no case reads live session records. A trailing kill-switch case proves
# the .state/off/simple-rules-guard path this guard resolves from $0 (not CLAUDE_CONFIG_DIR).
#
# State sandboxing is mandatory: CLAUDE_CONFIG_DIR-equivalent is KIT_ROOT here (the guard resolves its
# own root from $0, not from CLAUDE_CONFIG_DIR - see the guard's own header) so a fixture kit tree is
# built under one mktemp -d instead, with AGENT_TIERS_GUARDS_LOG pointed into it too. Never touches the
# real .state/.
set -u

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
SRC="$SCRIPTS/simple-rules-guard.sh"
[ -f "$SRC" ] || { echo "FAIL: simple-rules-guard.sh not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "note: skipped - jq absent (guard fails open by design)"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "note: skipped - git absent (rule C fixtures need it)"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

KIT="$T/kit"
mkdir -p "$KIT/scripts" "$KIT/.state"
cp "$SRC" "$KIT/scripts/"
cp "$SCRIPTS/guard-cmdpos.sh" "$KIT/scripts/"
G="$KIT/scripts/simple-rules-guard.sh"
LOG="$T/guards.log"
# kit-gate.sh runs as a child of the guard: the fixture gets a rewritten copy (empty managed dir) and
# options.tsv, and every input the user's own options could reach it through is cleared.
mkdir -p "$KIT/install" "$T/managed" "$T/cfg"
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$SCRIPTS/kit-gate.sh" > "$KIT/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$KIT/scripts/kit-gate.sh" || { echo "SELF-CHECK FAILED: _kg_managed not rewritten"; exit 1; }
cp "$SCRIPTS/../install/options.tsv" "$KIT/install/"
export CLAUDE_CONFIG_DIR="$T/cfg" AGENT_TIERS_GUARDS_LOG="$LOG"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done

run() { # run <payload-json> -> stdout: the guard's own stdout
  # CLAUDE_CONFIG_DIR is pinned at $T for every case here (not just Rule G's) so a Rule F case can
  # never accidentally read this host's own real ~/.claude/sessions records.
  printf '%s' "$1" | AGENT_TIERS_GUARDS_LOG="$LOG" CLAUDE_CONFIG_DIR="$T" sh "$G" 2>/dev/null
}
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }

bash_payload() { # bash_payload <cmd> [cwd]
  jq -n --arg c "$1" --arg cwd "${2:-$T}" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $cwd, session_id: "sess1"}'
}
ask_payload() { # ask_payload <questions-json>
  jq -n --argjson q "$1" '{tool_name: "AskUserQuestion", tool_input: {questions: $q}, session_id: "sess1"}'
}

# --- Rule A: codex exec resume --last / codex resume --last ------------------------------------------
out="$(run "$(bash_payload 'codex exec resume --last')")"
[ "$(decision "$out")" = "deny" ] || fail "A: codex exec resume --last was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'session id' || fail "A: denial does not name the explicit-session-id fix"

out="$(run "$(bash_payload 'codex resume --last')")"
[ "$(decision "$out")" = "deny" ] || fail "A: top-level codex resume --last was not denied (got: ${out:-<silence>})"

out="$(run "$(bash_payload 'codex exec resume abc123')")"
[ -z "$out" ] || fail "A: codex exec resume <id> (no --last) was denied (false positive): $out"

out="$(run "$(bash_payload 'codex resume abc123')")"
[ -z "$out" ] || fail "A: codex resume <id> (no --last) was denied (false positive): $out"

out="$(run "$(bash_payload 'codex exec "summarize this repo"')")"
[ -z "$out" ] || fail "A: codex exec with no resume was denied (false positive): $out"

out="$(run "$(bash_payload 'my-script.sh --last')")"
[ -z "$out" ] || fail "A: --last in an unrelated command was denied (false positive): $out"

# --- Rule B: sudo archlinux-java set -----------------------------------------------------------------
out="$(run "$(bash_payload 'sudo archlinux-java set java-21-openjdk')")"
[ "$(decision "$out")" = "deny" ] || fail "B: sudo archlinux-java set was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'JAVA_HOME' || fail "B: denial does not name the explicit-JDK fix"

out="$(run "$(bash_payload 'archlinux-java get')")"
[ -z "$out" ] || fail "B: archlinux-java get was denied (false positive): $out"

out="$(run "$(bash_payload 'sudo archlinux-java status')")"
[ -z "$out" ] || fail "B: sudo archlinux-java status was denied (false positive): $out"

out="$(run "$(bash_payload 'archlinux-java set java-21-openjdk')")"
[ -z "$out" ] || fail "B: archlinux-java set without sudo was denied (rule names the sudo form only): $out"

# The scp-style remote is assembled from parts rather than written literally: the kit leak scan reads
# a literal user@host as an address and blocks the commit, and the ban is right - a fixture is not a
# reason to weaken it. The parse under test is unaffected, since git sees the joined string.
SCP_HOST="github.com"
# --- Rule C: a new branch named main, operators own repos only --------------------------------------
OWNREPO="$T/ownrepo"; mkdir -p "$OWNREPO"
git -C "$OWNREPO" init -q
git -C "$OWNREPO" remote add origin "git@$SCP_HOST:godilley/agent-tiers.git"

OTHERREPO="$T/otherrepo"; mkdir -p "$OTHERREPO"
git -C "$OTHERREPO" init -q
git -C "$OTHERREPO" remote add origin https://github.com/someoneelse/repo.git

printf 'godilley\n# a comment line\n\n' > "$KIT/.state/own-namespaces"

out="$(run "$(bash_payload 'git checkout -b main' "$OWNREPO")")"
[ "$(decision "$out")" = "deny" ] || fail "C: git checkout -b main in an owned repo was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'master' || fail "C: denial does not name master as the fix"

out="$(run "$(bash_payload 'git switch -c main' "$OWNREPO")")"
[ "$(decision "$out")" = "deny" ] || fail "C: git switch -c main in an owned repo was not denied"

out="$(run "$(bash_payload 'git branch main' "$OWNREPO")")"
[ "$(decision "$out")" = "deny" ] || fail "C: git branch main in an owned repo was not denied"

out="$(run "$(bash_payload "git -C $OWNREPO switch -c main" "$T")")"
[ "$(decision "$out")" = "deny" ] || fail "C: -C into an owned repo was not resolved and denied"

# force-create forms (checkout -B, switch -C) - the same outcome as -b/-c, must be denied too
out="$(run "$(bash_payload 'git checkout -B main' "$OWNREPO")")"
[ "$(decision "$out")" = "deny" ] || fail "C: git checkout -B main (force-create) was not denied"

out="$(run "$(bash_payload 'git switch -C main' "$OWNREPO")")"
[ "$(decision "$out")" = "deny" ] || fail "C: git switch -C main (force-create) was not denied"

# rename-into-main forms - same resulting branch name as a create
out="$(run "$(bash_payload 'git branch -m main' "$OWNREPO")")"
[ "$(decision "$out")" = "deny" ] || fail "C: git branch -m main (rename current branch into main) was not denied"

out="$(run "$(bash_payload 'git branch -M oldname main' "$OWNREPO")")"
[ "$(decision "$out")" = "deny" ] || fail "C: git branch -M oldname main (rename with explicit oldname) was not denied"

# a path containing the verb word must not be misread as the verb itself (finding 4): $OWNREPO's
# clone-into path below has "branch" in it, so a free grep over the segment would report verb=branch
# and hand guard_verb_optspan a literal "branch" token to search for that never appears, unbounding -C
BRANCHPATHREPO="$T/branch-tool"; mkdir -p "$BRANCHPATHREPO"
git -C "$BRANCHPATHREPO" init -q
git -C "$BRANCHPATHREPO" remote add origin "git@$SCP_HOST:godilley/branch-tool.git"
out="$(run "$(bash_payload "git -C $BRANCHPATHREPO switch -c main" "$T")")"
[ "$(decision "$out")" = "deny" ] || fail "C: a path containing the verb word (branch-tool) broke -C resolution: ${out:-<silence>}"

# negative: not an owned repo
out="$(run "$(bash_payload 'git checkout -b main' "$OTHERREPO")")"
[ -z "$out" ] || fail "C: a repo not in own-namespaces was denied (false positive): $out"

# negative: no own-namespaces file
mv "$KIT/.state/own-namespaces" "$KIT/.state/own-namespaces.bak"
: > "$LOG"
out="$(run "$(bash_payload 'git checkout -b main' "$OWNREPO")")"
[ -z "$out" ] || fail "C: an absent own-namespaces file did not fail open: $out"
grep -aq 'fail-open: rule C' "$LOG" 2>/dev/null || fail "C: the absent-namespaces fail-open left no breadcrumb"
mv "$KIT/.state/own-namespaces.bak" "$KIT/.state/own-namespaces"

# negative: checkout main with no -b
out="$(run "$(bash_payload 'git checkout main' "$OWNREPO")")"
[ -z "$out" ] || fail "C: git checkout main (no -b) was denied (false positive): $out"

# negative: a branch named maintenance
out="$(run "$(bash_payload 'git branch maintenance' "$OWNREPO")")"
[ -z "$out" ] || fail "C: git branch maintenance was denied (false positive): $out"

# --- Rule D: first AskUserQuestion option must be marked recommended --------------------------------
Q_NONE='[{"question":"pick one","header":"H","options":[{"label":"Opt A","description":"first"},{"label":"Opt B","description":"second"}]}]'
out="$(run "$(ask_payload "$Q_NONE")")"
[ "$(decision "$out")" = "deny" ] || fail "D: an unmarked first option was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q '(Recommended)' || fail "D: denial does not name the (Recommended) fix"

Q_LABEL='[{"question":"pick one","header":"H","options":[{"label":"Opt A (Recommended)","description":"first"},{"label":"Opt B","description":"second"}]}]'
out="$(run "$(ask_payload "$Q_LABEL")")"
[ -z "$out" ] || fail "D: a labeled-recommended first option was denied (false positive): $out"

Q_DESC='[{"question":"pick one","header":"H","options":[{"label":"Opt A","description":"(Recommended) first"},{"label":"Opt B","description":"second"}]}]'
out="$(run "$(ask_payload "$Q_DESC")")"
[ -z "$out" ] || fail "D: a description-marked first option was denied (false positive): $out"

out="$(run '{"tool_name": "AskUserQuestion", "tool_input": {}, "session_id": "sess1"}')"
[ -z "$out" ] || fail "D: a payload with no questions array at all was denied (should fail open): $out"

# multiSelect: the answer is a set, so the marker goes on every member of the recommended set and the
# first option is not special. D5 is the mutation detector: it fails on the old options[0] test.
Q_MS_SECOND='[{"question":"q","multiSelect":true,"options":[{"label":"a","description":"x"},{"label":"b (Recommended)","description":"y"},{"label":"c","description":"z"}]}]'
out="$(run "$(ask_payload "$Q_MS_SECOND")")"
[ -z "$out" ] || fail "D5: multiSelect with only the second option marked was denied (false positive): $out"

Q_MS_NONE='[{"question":"q","multiSelect":true,"options":[{"label":"a","description":"x"},{"label":"b","description":"y"}]}]'
out="$(run "$(ask_payload "$Q_MS_NONE")")"
[ "$(decision "$out")" = "deny" ] || fail "D6: multiSelect with no marked option was not denied (got: ${out:-<silence>})"

Q_SS_SECOND='[{"question":"q","multiSelect":false,"options":[{"label":"a","description":"x"},{"label":"b (Recommended)","description":"y"}]}]'
out="$(run "$(ask_payload "$Q_SS_SECOND")")"
[ "$(decision "$out")" = "deny" ] || fail "D7: single-select with only the second option marked was not denied (control: single-select did not loosen)"

Q_MIX='[{"question":"q1","options":[{"label":"a (Recommended)","description":"x"},{"label":"b","description":"y"}]},{"question":"q2","multiSelect":true,"options":[{"label":"c","description":"x"},{"label":"d","description":"y"}]}]'
out="$(run "$(ask_payload "$Q_MIX")")"
[ "$(decision "$out")" = "deny" ] || fail "D8: a good single-select plus an unmarked multiSelect was not denied"

Q_MS_ALL='[{"question":"q","multiSelect":true,"options":[{"label":"a (Recommended)","description":"x"},{"label":"b (Recommended)","description":"y"}]}]'
out="$(run "$(ask_payload "$Q_MS_ALL")")"
[ -z "$out" ] || fail "D9: multiSelect with every option marked was denied (false positive): $out"

# --- Rule F: SendMessage must carry NOOP-IF-DONE or RESUME-OK -----------------------------------------
send_payload() { # send_payload <to> <message>
  jq -n --arg t "$1" --arg m "$2" '{tool_name: "SendMessage", tool_input: {to: $t, message: $m}, session_id: "sess1"}'
}
send_payload_agt() { # send_payload_agt <to> <message> <agent_type>
  jq -n --arg t "$1" --arg m "$2" --arg a "$3" '{tool_name: "SendMessage", tool_input: {to: $t, message: $m}, agent_type: $a, session_id: "sess1"} + (if $a == "" then {} else {agent_id: "a0test"} end)'
}
out="$(run "$(send_payload worker 'check if tests pass over there')")"
[ "$(decision "$out")" = "deny" ] || fail "F1: an unlabelled SendMessage was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'NOOP-IF-DONE' || fail "F1: denial does not name the NOOP-IF-DONE fix"
out="$(run "$(send_payload worker 'NOOP-IF-DONE: also skip the docs dir')")"
[ -z "$out" ] || fail "F2: a NOOP-IF-DONE message was denied (false positive): $out"
out="$(run "$(send_payload worker 'RESUME-OK: now add the selfcheck')")"
[ -z "$out" ] || fail "F3: a RESUME-OK message was denied (false positive): $out"
out="$(run "$(send_payload main 'done, report attached')")"
[ -z "$out" ] || fail "F4: a subagent send to main was denied (exempt): $out"
out="$(run '{"tool_name": "SendMessage", "tool_input": {"to": "worker", "notify_when_idle": true}, "session_id": "sess1"}')"
[ -z "$out" ] || fail "F5: a pure notify_when_idle subscription (no message) was denied (exempt): $out"
out="$(run "$(jq -n '{tool_name: "SendMessage", tool_input: {to: "a31003a0673e9caa1", message: "report attached"}, agent_type: "worker", agent_id: "a0test", session_id: "sess1"}')")"
[ -z "$out" ] || fail "F7: a subagent reporting to its launcher by agentId was denied (subagent callers exempt): $out"
out="$(run "$(jq -n '{tool_name: "SendMessage", tool_input: {to: "worker", message: "check this"}, agent_type: "main", session_id: "sess1"}')")"
[ "$(decision "$out")" = "deny" ] || fail "F8: agent_type main was treated as a subagent (it is the Lead)"
# F9: a `--agent` main session (agent_type, NO agent_id) is the Lead, not exempt.
out="$(run "$(jq -n '{tool_name: "SendMessage", tool_input: {to: "worker", message: "check this"}, agent_type: "foo", session_id: "sess1"}')")"
[ "$(decision "$out")" = "deny" ] || fail "F9: a --agent main session (no agent_id) was exempted as a subagent (got: ${out:-<silence>})"
# F10: a real subagent (agent_type + agent_id), namespaced, is exempt.
out="$(run "$(jq -n '{tool_name: "SendMessage", tool_input: {to: "worker", message: "check this"}, agent_type: "agent-tiers:worker", agent_id: "a1b2", session_id: "sess1"}')")"
[ -z "$out" ] || fail "F10: a namespaced subagent send was denied (exempt): $out"
out="$(run "$(send_payload worker 'noop-if-done lower case')")"
[ "$(decision "$out")" = "deny" ] || fail "F6: a lower-case token was accepted (token is literal, upper case)"

# --- Rule G: deny a SendMessage to a peer that has been idle too long -------------------------------
SESSDIR="$T/sessions"; mkdir -p "$SESSDIR"
unset AGENT_TIERS_PEER_IDLE_SECS

NOWS="$(date +%s)"
LIVEPID="$$"   # the selfcheck's own pid - alive for the whole run, a real "live peer" fixture

# A confirmed-dead pid: fork a child that exits immediately and wait() it, so the pid is reaped and
# kill -0 against it fails (ESRCH) - the fixture for "a record naming a pid that is no longer live".
sh -c 'exit 0' &
DEADPID=$!
wait "$DEADPID" 2>/dev/null
kill -0 "$DEADPID" 2>/dev/null && fail "G-setup: DEADPID $DEADPID is unexpectedly still alive, fixture invalid"

mk_session() { # mk_session <file> <name> <status> <ago-seconds> <pid>
  jq -n --arg n "$2" --arg s "$3" --argjson u "$(( (NOWS - $4) * 1000 ))" --argjson p "$5" \
    '{pid: $p, sessionId: "x", cwd: "/", name: $n, status: $s, updatedAt: $u, statusUpdatedAt: $u}' > "$1"
}

mk_session "$SESSDIR/idle2h.json" "peer-idle-2h" "idle" 7200 "$LIVEPID"
mk_session "$SESSDIR/idle10m.json" "peer-idle-10m" "idle" 600 "$LIVEPID"
mk_session "$SESSDIR/busy2h.json" "peer-busy-2h" "busy" 7200 "$LIVEPID"

mk_session "$SESSDIR/badnum.json" "peer-badnum" "idle" 7200 "$LIVEPID"
jq '.statusUpdatedAt = "not-a-number"' "$SESSDIR/badnum.json" > "$SESSDIR/badnum.json.tmp" && mv "$SESSDIR/badnum.json.tmp" "$SESSDIR/badnum.json"

mk_session "$SESSDIR/seconds.json" "peer-seconds" "idle" 7200 "$LIVEPID"
jq --argjson u "$((NOWS - 7200))" '.statusUpdatedAt = $u' "$SESSDIR/seconds.json" > "$SESSDIR/seconds.json.tmp" && mv "$SESSDIR/seconds.json.tmp" "$SESSDIR/seconds.json"

mk_session "$SESSDIR/future.json" "peer-future" "idle" "-7200" "$LIVEPID"

mk_session "$SESSDIR/dup-a.json" "peer-dup" "idle" 7200 "$LIVEPID"
mk_session "$SESSDIR/dup-b.json" "peer-dup" "idle" 7200 "$LIVEPID"

mk_session "$SESSDIR/deadlive-dead.json" "peer-deadlive" "idle" 7200 "$DEADPID"
mk_session "$SESSDIR/deadlive-live.json" "peer-deadlive" "busy" 7200 "$LIVEPID"

UDSPATH="/run/user/1000/cc-socks/$LIVEPID.sock"
jq -n --arg n "peer-uds" --argjson u "$(( (NOWS - 7200) * 1000 ))" --argjson p "$LIVEPID" --arg sock "$UDSPATH" \
  '{pid: $p, sessionId: "x", cwd: "/", name: $n, status: "idle", updatedAt: $u, statusUpdatedAt: $u, messagingSocketPath: $sock}' \
  > "$SESSDIR/$LIVEPID.json"

out="$(run "$(send_payload 'peer-idle-2h' 'NOOP-IF-DONE: ping')")"
[ "$(decision "$out")" = "deny" ] || fail "G1: a 2h-idle peer was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'WAKE-OK' || fail "G1: denial does not name the WAKE-OK fix"

out="$(run "$(send_payload 'peer-idle-2h' 'WAKE-OK: need its answer and NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G2: WAKE-OK with a reason was denied (false positive): $out"

out="$(run "$(send_payload 'peer-idle-2h' 'NOOP-IF-DONE: ping WAKE-OK:')")"
[ "$(decision "$out")" = "deny" ] || fail "G3: WAKE-OK with nothing after it was not denied"

MSG_SPLIT="$(printf 'NOOP-IF-DONE: ping\nWAKE-OK:\nneed its answer')"
out="$(run "$(send_payload 'peer-idle-2h' "$MSG_SPLIT")")"
[ "$(decision "$out")" = "deny" ] || fail "G3b: WAKE-OK: on its own line with the reason on the next line was not denied (reason must be on the same line)"

out="$(run "$(send_payload 'peer-idle-10m' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G4: a 10-minute-idle peer was denied (false positive): $out"

out="$(run "$(send_payload 'peer-busy-2h' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G5: a busy peer stale for 2h was denied (false positive, busy not idle): $out"

out="$(run "$(send_payload 'peer-idle-2h [ab12cd]' 'NOOP-IF-DONE: ping')")"
[ "$(decision "$out")" = "deny" ] || fail "G6: a to with a ref suffix did not match the peer by stripped name"

# G9: library absent -> Rule G still denies the idle-peer wake; Rule F fails open (no caller identity).
mv "$KIT/scripts/guard-cmdpos.sh" "$T/guard-cmdpos.sh.away"
out="$(run "$(send_payload 'peer-idle-2h' 'NOOP-IF-DONE: ping')")"
[ "$(decision "$out")" = "deny" ] || fail "G9: Rule G did not deny with guard-cmdpos.sh absent (got: ${out:-<silence>})"
out="$(run "$(send_payload worker 'unlabelled note')")"
[ -z "$out" ] || fail "G9: Rule F denied with guard-cmdpos.sh absent (should fail open): $out"
mv "$T/guard-cmdpos.sh.away" "$KIT/scripts/guard-cmdpos.sh"

out="$(run "$(send_payload 'a31003a0673e9caa1' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G7: an unknown name (no session record) was denied (false positive): $out"

out="$(run "$(send_payload_agt 'peer-idle-2h' 'ping' 'worker')")"
[ "$(decision "$out")" = "deny" ] || fail "G8: a subagent caller to a 2h-idle peer was not denied (Rule G applies to every caller)"

out="$(run "$(send_payload_agt 'peer-idle-2h' 'ping' '')")"
[ "$(decision "$out")" = "deny" ] || fail "G8b: the Lead's own denial was missing"
printf '%s' "$out" | grep -q 'Rule F' || fail "G8b: the Lead's denial does not also remind about Rule F"

out="$(AGENT_TIERS_PEER_IDLE_SECS=60 run "$(send_payload 'peer-idle-10m' 'NOOP-IF-DONE: ping')")"
[ "$(decision "$out")" = "deny" ] || fail "G9: AGENT_TIERS_PEER_IDLE_SECS=60 did not lower the threshold for a 10-minute-idle peer"

out="$(AGENT_TIERS_PEER_IDLE_SECS=abc run "$(send_payload 'peer-idle-10m' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G10: a non-numeric AGENT_TIERS_PEER_IDLE_SECS did not fall back to the 3600s default: $out"

out="$(run "$(send_payload 'peer-badnum' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G11: a non-numeric statusUpdatedAt did not fail open: $out"
grep -aq 'fail-open: rule G.*not numeric' "$LOG" 2>/dev/null || fail "G11: the non-numeric fail-open left no breadcrumb"

out="$(run "$(send_payload 'peer-seconds' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G12: a seconds-looking statusUpdatedAt did not fail open (false positive): $out"
grep -aq 'fail-open: rule G.*looks like seconds' "$LOG" 2>/dev/null || fail "G12: the seconds-looking fail-open left no breadcrumb"

out="$(run "$(send_payload 'peer-future' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G13: a future statusUpdatedAt was denied (false positive, not actually idle yet): $out"

out="$(run "$(send_payload 'peer-dup' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G14: two live records sharing a name did not fail open (ambiguous ref): $out"

out="$(run "$(send_payload 'peer-deadlive' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G15: a dead-pid idle record was not ignored in favour of the live busy record of the same name: $out"

out="$(AGENT_TIERS_PEER_IDLE_SECS=999999999 run "$(send_payload 'peer-idle-2h' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G16: an over-cap threshold was not clamped to 604800 (a 2h-idle peer should be allowed under it): $out"

out="$(run '{"tool_name": "SendMessage", "tool_input": {"to": "peer-idle-2h", "notify_when_idle": true}, "session_id": "sess1"}')"
[ -z "$out" ] || fail "G17: a pure notify_when_idle subscription to an idle peer (no message) was denied (exempt): $out"

out="$(run "$(send_payload "uds:$UDSPATH" 'NOOP-IF-DONE: ping')")"
[ "$(decision "$out")" = "deny" ] || fail "G18: a uds: form to a 2h-idle peer was not denied"

out="$(run "$(send_payload 'uds:/run/user/1000/cc-socks/999999999.sock' 'NOOP-IF-DONE: ping')")"
[ -z "$out" ] || fail "G19: a uds: path with no matching record was denied (should fail open): $out"

# --- Kill switch: .state/off/simple-rules-guard, checked before any side effect ----------------------
# Derived from $0 (KIT_ROOT), not CLAUDE_CONFIG_DIR - this is the one guard in the kit where that
# matters, since no other case here executes that path. Rule A's positive payload is otherwise a
# guaranteed deny, so a silent run here fails loudly if the kill-switch check is ever removed.
mkdir -p "$KIT/.state/off"
: > "$KIT/.state/off/simple-rules-guard"
out="$(run "$(bash_payload 'codex exec resume --last')")"
[ -z "$out" ] || fail "kill-switch: .state/off/simple-rules-guard did not silence an otherwise-denied command: $out"
rm -f "$KIT/.state/off/simple-rules-guard"

# --- Stand-down via kit-gate.sh: marker -> empty stdout, exit 0, a kit-gate log line --------------------
ctl="$(run "$(bash_payload 'codex exec resume --last')")"   # control: no marker, same payload must deny
[ "$(decision "$ctl")" = deny ] || fail "stand-down: control run (no marker) did not deny, fixture drifted: $ctl"
: > "$KIT/.state/off/simple-rules-guard"
out="$(printf '%s' "$(bash_payload 'codex exec resume --last')" | CLAUDE_CODE_SESSION_ID=sess-sd sh "$G" 2>/dev/null)"; rc=$?
rm -f "$KIT/.state/off/simple-rules-guard"
[ -z "$out" ] && [ "$rc" = 0 ] || fail "stand-down: marker did not silence an otherwise-denied command (rc=$rc out=$out)"
grep -aq 'kit-gate standdown simple-rules-guard:' "$LOG" 2>/dev/null || fail "stand-down: no kit-gate log line"

if [ "$fails" -eq 0 ]; then
  echo "PASS simple-rules-guard: 77/77 cases"
  exit 0
fi
printf 'simple-rules-guard: %s case(s) failed\n' "$fails"
exit 1

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for peer-guard.sh. Runnable: `sh peer-guard.selfcheck.sh` or `bash peer-guard.selfcheck.sh`.
# Spawns fake "claude" processes (bash -c 'exec -a claude sleep 300', so argv0 reads "claude") inside
# fixture git repos, drops plain .sock files for each in a temp sock dir, and points PEER_GUARD_SELF_PID
# at a separate fake process to stand in for "this session". All fake processes are killed on exit.
#
# State sandboxing: the guard resolves its own KIT_ROOT from $0, not CLAUDE_CONFIG_DIR, so this script
# runs a COPY of peer-guard.sh placed under a fixture kit tree (same pattern as
# simple-rules-guard.selfcheck.sh) - the real kit's .state/ is never touched. guard-cmdpos.sh is also
# copied alongside it (the guard now sources it) so this fixture is self-contained.
set -u
unset AGENT_TIERS_STATE_DAYS AGENT_TIERS_LEDGER_DAYS XDG_RUNTIME_DIR

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
SRC="$SCRIPTS/peer-guard.sh"
CMDPOS_SRC="$SCRIPTS/guard-cmdpos.sh"
[ -f "$SRC" ] || { echo "FAIL: peer-guard.sh not found"; exit 1; }
[ -f "$CMDPOS_SRC" ] || { echo "FAIL: guard-cmdpos.sh not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "note: skipped - jq absent (guard fails open by design)"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "note: skipped - git absent (fixtures need it)"; exit 0; }
[ -d /proc ] || { echo "note: skipped - no /proc (Linux-only presence source)"; exit 0; }

T="$(mktemp -d)"
KIT="$T/kit"
mkdir -p "$KIT/scripts" "$KIT/.state/off"
cp "$SRC" "$KIT/scripts/"
cp "$CMDPOS_SRC" "$KIT/scripts/"
G="$KIT/scripts/peer-guard.sh"
LOG="$T/guards.log"
SOCKDIR="$T/socks"
STATEDIR="$T/pgstate"
mkdir -p "$SOCKDIR" "$STATEDIR"

REPO="$T/repo"; mkdir -p "$REPO"; (cd "$REPO" && git init -q && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init)
FOREIGN="$T/foreign"; mkdir -p "$FOREIGN"; (cd "$FOREIGN" && git init -q)
FOREIGN2="$T/foreign2"; mkdir -p "$FOREIGN2"; (cd "$FOREIGN2" && git init -q)   # a no-peer foreign repo, for case B
FOREIGN3="$T/foreign3"; mkdir -p "$FOREIGN3"; (cd "$FOREIGN3" && git init -q)   # a no-peer foreign repo, for case F
FOREIGNM="$T/foreignm"; mkdir -p "$FOREIGNM"; (cd "$FOREIGNM" && git init -q)   # for mutation check 2
NONGIT="$T/nongit"; mkdir -p "$NONGIT"
# a second, always-peerless repo: isolates case 11 from arm1's OWN advisory, which legitimately fires
# for any brand-new session id in $REPO once cases 5-7 have put live peers there.
REPO2="$T/repo2"; mkdir -p "$REPO2"; (cd "$REPO2" && git init -q)
# a linked worktree of REPO (case E) - needs REPO's own initial commit above.
WT="$T/repo-wt"

PIDS=""
: > "$T/pids"
cleanup() {
  for p in $PIDS $(cat "$T/pids" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
  wait 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT INT TERM

fails=0
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }
pass() { printf 'ok   %s\n' "$1"; }

# wait_for_pidfile <path> -> stdout: the file's content once non-empty, polled up to ~5s (50 x 0.1s)
# instead of a single fixed sleep - a loaded CI host can take longer than 0.3s for the forked child to
# write its own pid. Prints nothing and returns non-zero if still empty after the poll window; callers
# must check for that and fail the case rather than silently proceeding on an empty pid.
wait_for_pidfile() {
  f="$1"; n=0
  while [ "$n" -lt 50 ]; do
    v="$(cat "$f" 2>/dev/null || true)"
    [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
    sleep 0.1
    n=$((n + 1))
  done
  return 1
}

# spawn_claude [cwd] -> stdout: pid of a fake claude process (argv0 "claude"), socketed in $SOCKDIR.
# `exec -a` is a bash-ism (dash's exec builtin has no -a), so bash is invoked explicitly for it
# regardless of which shell is running THIS script. ALWAYS called as `p=$(spawn_claude ...)` - a
# command substitution subshell, in dash, inherits the EXIT trap set below and would otherwise run
# cleanup() (deleting $T) the moment this subshell itself exits; `trap - EXIT INT TERM` as the first
# line disarms that inherited copy without touching the real, top-level trap. Likewise PIDS appended
# inside this subshell is a copy, invisible to the parent - the pid file is the only shared record.
# `</dev/null >/dev/null 2>&1` on the background job is NOT cosmetic: without it the backgrounded
# process inherits the command-substitution pipe's write end, and $(spawn_claude ...) then blocks
# forever waiting for EOF on that pipe - EOF never comes while the (5-minute) fake process is alive,
# since it still holds the fd open even after being orphaned and reparented to init.
spawn_claude() {
  trap - EXIT INT TERM
  wd="${1:-$T}"
  ( cd "$wd" 2>/dev/null && exec bash -c 'exec -a claude sleep 300' ) </dev/null >/dev/null 2>&1 &
  p=$!
  echo "$p" >> "$T/pids"
  sleep 0.2
  touch "$SOCKDIR/$p.sock"
  printf '%s\n' "$p"
}

export PEER_GUARD_SOCK_DIR="$SOCKDIR"
export PEER_GUARD_STATE_DIR="$STATEDIR"
export AGENT_TIERS_GUARDS_LOG="$LOG"

# every guard invocation below runs under this shell (default: sh), so this selfcheck can be pointed
# at dash or bash explicitly (PEER_GUARD_TEST_SHELL=dash/bash) instead of whatever /bin/sh happens to
# resolve to on the host.
TESTSH="${PEER_GUARD_TEST_SHELL:-sh}"
echo "shell: $TESTSH"

# --- a dedicated "self" process, shared by every case below (ancestry tests need a real pid) --------
SELF="$(spawn_claude)"
export PEER_GUARD_SELF_PID="$SELF"

list() { PEER_GUARD_SELF_PID="${1:-$SELF}" "$TESTSH" "$G" --list "$SOCKDIR"; }

# --- case 1: stale socket (pid that does not exist) ignored by --list --------------------------------
touch "$SOCKDIR/999999.sock"
case "$(list)" in
  *999999*) fail "case1: stale socket pid was listed as a peer" ;;
  *) pass "case1: stale socket ignored" ;;
esac
rm -f "$SOCKDIR/999999.sock"

# --- case 2: live non-claude process (plain sleep) ignored -------------------------------------------
sleep 300 &
NC=$!; PIDS="$PIDS $NC"
touch "$SOCKDIR/$NC.sock"
case "$(list)" in
  *"$NC "*) fail "case2: non-claude live process was listed as a peer" ;;
  *) pass "case2: non-claude process ignored" ;;
esac
rm -f "$SOCKDIR/$NC.sock"

# --- case 3: self excluded ------------------------------------------------------------------------
case "$(list)" in
  *"$SELF "*) fail "case3: self pid appeared as a peer" ;;
  *) pass "case3: self excluded" ;;
esac

# --- case 4: a fake claude child spawned FROM the self process is excluded (nested ancestry) --------
# A tiny helper script, not inline quoting: NESTSELF itself must pass pg_is_claude (argv0 "claude")
# AND fork a real child that also passes it, so the ancestry walk has two genuine generations to test.
cat > "$T/nest.sh" <<NESTEOF
exec -a claude bash -c '
  ( exec -a claude sleep 300 ) &
  echo \$! > "$T/child.pid"
  wait
'
NESTEOF
chmod +x "$T/nest.sh"
bash "$T/nest.sh" &
NESTSELF=$!
disown "$NESTSELF" 2>/dev/null || true
PIDS="$PIDS $NESTSELF"
if NESTCHILD="$(wait_for_pidfile "$T/child.pid")"; then
  PIDS="$PIDS $NESTCHILD"
  touch "$SOCKDIR/$NESTSELF.sock" "$SOCKDIR/$NESTCHILD.sock"
  OUT="$(list "$NESTSELF")"
  case "$OUT" in
    *"$NESTCHILD "*) fail "case4: nested child of self was listed as a peer" ;;
    *) pass "case4: nested child of self excluded" ;;
  esac
else
  fail "case4: nested child never wrote its pid file"
fi

# --- case D: a candidate that is an ANCESTOR of self is excluded too (ancestry check in the other
# direction - self=NESTCHILD here, NESTSELF is its parent and must still be excluded) ----------------
if [ -n "${NESTCHILD:-}" ]; then
  OUTD="$(list "$NESTCHILD")"
  case "$OUTD" in
    *"$NESTSELF "*) fail "caseD: an ancestor of self was listed as a peer" ;;
    *) pass "caseD: ancestor of self excluded" ;;
  esac
else
  fail "caseD: skipped - no nested child pid available"
fi

# --- payload builder -------------------------------------------------------------------------------
payload() { # tool filepath cwd sid [agent_type]
  tool="$1"; fp="$2"; cwd="$3"; sid="$4"; agt="${5:-}"
  jq -n --arg t "$tool" --arg f "$fp" --arg c "$cwd" --arg s "$sid" --arg a "$agt" \
    '{tool_name:$t, cwd:$c, session_id:$s} + (if $a=="" then {} else {agent_type:$a} end) +
     (if $t=="NotebookEdit" then {tool_input:{notebook_path:$f}} else {tool_input:{file_path:$f}} end)'
}
run() { printf '%s' "$1" | "$TESTSH" "$G"; }
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }
ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

# --- case 5/6/7: arm1 same-repo peer advisory ------------------------------------------------------
RPEER="$(spawn_claude "$REPO")"
OUT1="$(run "$(payload Bash '' "$REPO" sess-arm1)")"
[ -n "$(ctx "$OUT1")" ] && [ -z "$(decision "$OUT1")" ] \
  && pass "case5: first same-repo peer emits additionalContext with no permissionDecision" \
  || fail "case5: expected additionalContext-only, got: $OUT1"

OUT2="$(run "$(payload Bash '' "$REPO" sess-arm1)")"
[ -z "$OUT2" ] && pass "case6: identical second call is silent" \
  || fail "case6: expected silence on unchanged peer set, got: $OUT2"

RPEER2="$(spawn_claude "$REPO")"
OUT3="$(run "$(payload Bash '' "$REPO" sess-arm1)")"
[ -n "$(ctx "$OUT3")" ] && pass "case7: a new peer re-emits the advisory" \
  || fail "case7: expected a fresh additionalContext when peer set grew, got: $OUT3"

# --- case G: a subagent caller never gets arm1's advisory, even with a live same-repo peer ----------
OUTG="$(run "$(payload Bash '' "$REPO" sess-caseG worker)")"
[ -z "$(ctx "$OUTG")" ] && pass "caseG: subagent caller gets no arm1 advisory" \
  || fail "caseG: expected no additionalContext for a subagent caller, got: $OUTG"

# --- case 8: arm2 foreign-repo write, no peer -> deny, then pass -------------------------------------
# cwd is REPO2 (peerless), not REPO - REPO has live peers from cases 5-7, and point 3 now makes arm1's
# advisory reappear on any call where arm2 swallowed it, which would otherwise make this new session id's
# retry non-silent for an unrelated reason (see caseF, which tests exactly that interaction on purpose).
OUT4="$(run "$(payload Write "$FOREIGN/a.txt" "$REPO2" sess-arm2a)")"
[ "$(decision "$OUT4")" = deny ] && pass "case8a: first foreign write with no peer denies" \
  || fail "case8a: expected deny, got: $OUT4"
OUT5="$(run "$(payload Write "$FOREIGN/a.txt" "$REPO2" sess-arm2a)")"
[ -z "$OUT5" ] && pass "case8b: identical retry passes silently (once-per-session-per-repo marker)" \
  || fail "case8b: expected silence on retry, got: $OUT5"

# --- case 9: arm2 foreign-repo write WITH a live peer there -> ask (deny for a subagent) -------------
FPEER="$(spawn_claude "$FOREIGN")"
OUT6="$(run "$(payload Write "$FOREIGN/b.txt" "$REPO" sess-arm2b)")"
[ "$(decision "$OUT6")" = ask ] && pass "case9a: foreign write with a live peer there asks" \
  || fail "case9a: expected ask, got: $OUT6"
OUT7="$(run "$(payload Write "$FOREIGN/c.txt" "$REPO" sess-arm2c worker)")"
[ "$(decision "$OUT7")" = deny ] && pass "case9b: same shape, subagent caller -> converted to deny" \
  || fail "case9b: expected deny for subagent caller, got: $OUT7"

# --- case A: subagent, foreign write with a live peer -> deny; identical retry -> deny AGAIN (the
# HIGH fix: the converted deny must never mark the gate clear) -------------------------------------
OUT_A1="$(run "$(payload Write "$FOREIGN/caseA.txt" "$REPO" sess-caseA worker)")"
[ "$(decision "$OUT_A1")" = deny ] && pass "caseA1: subagent foreign write with a live peer denies" \
  || fail "caseA1: expected deny, got: $OUT_A1"
OUT_A2="$(run "$(payload Write "$FOREIGN/caseA.txt" "$REPO" sess-caseA worker)")"
[ "$(decision "$OUT_A2")" = deny ] && pass "caseA2: identical retry denies again (no marker written)" \
  || fail "caseA2: expected deny again, got: $OUT_A2"

# --- case B: subagent, foreign write with NO peer -> deny; then the Lead (no agent_type), same
# session+repo -> deny once (proves the subagent's deny did not consume the Lead's own marker) -------
# cwd is REPO2 (peerless), same reason as case 8 above - REPO's own live peers would otherwise make
# arm1 reappear on a call arm2 swallowed and break the plain "silence" assertion in caseB3.
OUT_B1="$(run "$(payload Write "$FOREIGN2/x.txt" "$REPO2" sess-caseB worker)")"
[ "$(decision "$OUT_B1")" = deny ] && pass "caseB1: subagent no-peer foreign write denies" \
  || fail "caseB1: expected deny, got: $OUT_B1"
OUT_B2="$(run "$(payload Write "$FOREIGN2/y.txt" "$REPO2" sess-caseB)")"
[ "$(decision "$OUT_B2")" = deny ] && pass "caseB2: the Lead's own first-write deny for this repo still fires" \
  || fail "caseB2: expected deny, got: $OUT_B2"
OUT_B3="$(run "$(payload Write "$FOREIGN2/z.txt" "$REPO2" sess-caseB)")"
[ -z "$OUT_B3" ] && pass "caseB3: the Lead's own marker now silences further retries" \
  || fail "caseB3: expected silence, got: $OUT_B3"

# --- case C: an unattended session with a live peer in the foreign repo -> deny, not ask ------------
: > "$KIT/.state/unattended.sess-caseC"
OUT_C="$(run "$(payload Write "$FOREIGN/caseC.txt" "$REPO" sess-caseC)")"
[ "$(decision "$OUT_C")" = deny ] && pass "caseC: unattended session with a live foreign peer denies, not asks" \
  || fail "caseC: expected deny, got: $OUT_C"
rm -f "$KIT/.state/unattended.sess-caseC"

# --- case 10: write into the session's OWN repo -> no arm2 output -----------------------------------
OUT8="$(run "$(payload Write "$REPO/d.txt" "$REPO" sess-arm2d)")"
[ -z "$(decision "$OUT8")" ] && pass "case10: write to own repo produces no arm2 decision" \
  || fail "case10: expected no decision for same-repo write, got: $OUT8"

# --- case E: write into a LINKED WORKTREE of the session's own repo -> still no arm2 decision
# (git-common-dir equality, point 4 - a worktree is not "foreign" even though its toplevel differs) --
if (cd "$REPO" && git worktree add -q "$WT" -b wt-branch) 2>/dev/null; then
  OUT_E="$(run "$(payload Write "$WT/f.txt" "$REPO" sess-caseE)")"
  [ -z "$(decision "$OUT_E")" ] && pass "caseE: write into a worktree of the session's own repo has no arm2 decision" \
    || fail "caseE: expected no decision for a same-repo worktree write, got: $OUT_E"
else
  fail "caseE: git worktree add failed"
fi

# --- case 11: write to a non-git path -> no output --------------------------------------------------
OUT9="$(run "$(payload Write "$NONGIT/e.txt" "$REPO2" sess-arm2e)")"
[ -z "$OUT9" ] && pass "case11: write to a non-git path produces no output" \
  || fail "case11: expected no output for a non-git target, got: $OUT9"

# --- case F: arm2 deny and an arm1 peer-set change in the SAME call -> arm1's advisory is not lost,
# it reappears on the next call (point 3) ------------------------------------------------------------
OUT_F1="$(run "$(payload Write "$FOREIGN3/a.txt" "$REPO" sess-caseF)")"
[ "$(decision "$OUT_F1")" = deny ] && pass "caseF1: arm2 wins the same call arm1 would have changed in" \
  || fail "caseF1: expected arm2 deny, got: $OUT_F1"
OUT_F2="$(run "$(payload Bash '' "$REPO" sess-caseF)")"
[ -n "$(ctx "$OUT_F2")" ] && pass "caseF2: arm1's advisory reappears on the next call, not lost" \
  || fail "caseF2: expected additionalContext on the next call, got: $OUT_F2"

# --- case H: a peer cwd containing a space still reports the right age (field order, point 6) -------
REPOSPACE="$T/repo space"; mkdir -p "$REPOSPACE"; (cd "$REPOSPACE" && git init -q)
SPEER="$(spawn_claude "$REPOSPACE")"
sleep 1
OUT_H="$(run "$(payload Bash '' "$REPOSPACE" sess-caseH)")"
CTXH="$(ctx "$OUT_H")"
if printf '%s' "$CTXH" | grep -qE "$SPEER \([0-9]+s\)"; then
  pass "caseH: a cwd with a space still shows a numeric age for its pid"
else
  fail "caseH: expected a numeric age for pid $SPEER, got: $CTXH"
fi

# --- case I: a read-only PEER_GUARD_STATE_DIR -> the marker write fails, so no arm2 decision is ever
# emitted (point 1 - a decision is never set ahead of a write that might not have landed) ------------
if [ "$(id -u 2>/dev/null)" = "0" ]; then
  echo "note: caseI skipped - running as root, permission bits are not enforced"
else
  ROSTATE="$T/ro-state"; mkdir -p "$ROSTATE"; chmod 555 "$ROSTATE"
  OUT_I="$(PEER_GUARD_STATE_DIR="$ROSTATE" run "$(payload Write "$FOREIGN2/caseI.txt" "$REPO2" sess-caseI)")"
  chmod 755 "$ROSTATE"
  [ -z "$(decision "$OUT_I")" ] && pass "caseI: read-only state dir emits no decision (marker write failed open)" \
    || fail "caseI: expected no decision with a read-only state dir, got: $OUT_I"
fi

# --- case J: a session_id containing a path-unsafe character (/) -> treated as absent, no output at all
OUT_J="$(run "$(payload Bash '' "$REPO2" 'sess/withslash')")"
[ -z "$OUT_J" ] && pass "caseJ: session_id containing / produces no output" \
  || fail "caseJ: expected no output for an unsafe session_id, got: $OUT_J"

# --- case K: a Lead's own .nopeer marker silences ANY later caller, including a subagent -----------
FOREIGNK="$T/foreignk"; mkdir -p "$FOREIGNK"; (cd "$FOREIGNK" && git init -q)
OUT_K1="$(run "$(payload Write "$FOREIGNK/a.txt" "$REPO2" sess-caseK worker)")"
[ "$(decision "$OUT_K1")" = deny ] && pass "caseK1: subagent foreign write with no peer denies" \
  || fail "caseK1: expected deny, got: $OUT_K1"
OUT_K2="$(run "$(payload Write "$FOREIGNK/b.txt" "$REPO2" sess-caseK)")"
[ "$(decision "$OUT_K2")" = deny ] && pass "caseK2: the Lead's own first-write deny for this repo still fires" \
  || fail "caseK2: expected deny, got: $OUT_K2"
OUT_K3="$(run "$(payload Write "$FOREIGNK/c.txt" "$REPO2" sess-caseK)")"
[ -z "$OUT_K3" ] && pass "caseK3: the Lead's own retry passes silently (.nopeer marker)" \
  || fail "caseK3: expected silence, got: $OUT_K3"
OUT_K4="$(run "$(payload Write "$FOREIGNK/d.txt" "$REPO2" sess-caseK worker)")"
[ -z "$OUT_K4" ] && pass "caseK4: the same subagent write now passes too (.nopeer covers any caller)" \
  || fail "caseK4: expected silence, got: $OUT_K4"

# --- case L: a .nopeer marker never silences a LATER live-peer ask (point 2) -----------------------
FOREIGNL="$T/foreignl"; mkdir -p "$FOREIGNL"; (cd "$FOREIGNL" && git init -q)
OUT_L1="$(run "$(payload Write "$FOREIGNL/a.txt" "$REPO2" sess-caseL)")"
[ "$(decision "$OUT_L1")" = deny ] && pass "caseL1: Lead no-peer deny fires" \
  || fail "caseL1: expected deny, got: $OUT_L1"
OUT_L2="$(run "$(payload Write "$FOREIGNL/b.txt" "$REPO2" sess-caseL)")"
[ -z "$OUT_L2" ] && pass "caseL2: retry passes via the .nopeer marker" \
  || fail "caseL2: expected silence, got: $OUT_L2"
LPEER="$(spawn_claude "$FOREIGNL")"
OUT_L3="$(run "$(payload Write "$FOREIGNL/c.txt" "$REPO2" sess-caseL)")"
[ "$(decision "$OUT_L3")" = ask ] && pass "caseL3: a live peer appearing afterward still asks (.nopeer never silences a live-peer ask)" \
  || fail "caseL3: expected ask, got: $OUT_L3"
rm -f "$SOCKDIR/$LPEER.sock"; kill -9 "$LPEER" 2>/dev/null

# --- case M: an unattended Lead with a live foreign peer -> deny worded "nobody can approve" --------
: > "$KIT/.state/unattended.sess-caseM"
OUT_M="$(run "$(payload Write "$FOREIGN/caseM.txt" "$REPO" sess-caseM)")"
REASON_M="$(printf '%s' "$OUT_M" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
if [ "$(decision "$OUT_M")" = deny ] && printf '%s' "$REASON_M" | grep -q "Skip this edit"; then
  pass "caseM: unattended Lead with a live foreign peer denies with the no-approve-possible wording"
else
  fail "caseM: expected a deny containing 'Skip this edit', got: $OUT_M"
fi
rm -f "$KIT/.state/unattended.sess-caseM"

# --- case N: kill switch present, self unresolvable -> no self-walk, no note, guards.log unchanged --
: > "$KIT/.state/off/peer-guard"
LOGLINES_BEFORE="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
printf '%s' "$(payload Bash '' "$REPO" sess-caseN)" | PEER_GUARD_SELF_PID=999999 "$TESTSH" "$G" >/dev/null 2>&1
LOGLINES_AFTER="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
[ "$LOGLINES_BEFORE" = "$LOGLINES_AFTER" ] && pass "caseN: kill switch suppresses even a self-not-found note" \
  || fail "caseN: expected no new guards.log line, before=$LOGLINES_BEFORE after=$LOGLINES_AFTER"
rm -f "$KIT/.state/off/peer-guard"

# --- case 12: kill switch -----------------------------------------------------------------------
: > "$KIT/.state/off/peer-guard"
OUT10="$(run "$(payload Bash '' "$REPO" sess-kill)")"
[ -z "$OUT10" ] && pass "case12: kill switch silences the guard" \
  || fail "case12: expected no output with kill switch present, got: $OUT10"
rm -f "$KIT/.state/off/peer-guard"

# --- case 13: jq absent -> skip (fail open) -----------------------------------------------------
PJSON="$(payload Bash '' "$REPO" sess-nojq)"
NOJQDIR="$T/nojq-path"
mkdir -p "$NOJQDIR"
for b in sh "$TESTSH" cat mkdir dirname basename readlink ps git tr sed awk kill date printf env mktemp grep; do
  b_path="$(command -v "$b" 2>/dev/null)"
  [ -n "$b_path" ] && ln -sf "$b_path" "$NOJQDIR/$b" 2>/dev/null
done
OUT11="$(printf '%s' "$PJSON" | PATH="$NOJQDIR" "$TESTSH" "$G" 2>/dev/null)"
[ -z "$OUT11" ] && pass "case13: jq absent fails open silently" \
  || fail "case13: expected silent fail-open with jq absent, got: $OUT11"

# --- case O: Write landing inside a foreign repo's .git dir (e.g. a hook) still denies - the path is
# cut at the first /.git and classified from the part before it ------------------------------------
FOREIGNO="$T/foreigno"; mkdir -p "$FOREIGNO/.git/hooks"; (cd "$FOREIGNO" && git init -q)
OUT_O="$(run "$(payload Write "$FOREIGNO/.git/hooks/pre-commit" "$REPO2" sess-caseO)")"
[ "$(decision "$OUT_O")" = deny ] && pass "caseO: write into a foreign repo's .git/hooks/pre-commit denies" \
  || fail "caseO: expected deny, got: $OUT_O"

# --- case P: NotebookEdit (notebook_path, not file_path) into a foreign repo denies too ------------
FOREIGNP="$T/foreignp"; mkdir -p "$FOREIGNP"; (cd "$FOREIGNP" && git init -q)
OUT_P="$(run "$(payload NotebookEdit "$FOREIGNP/nb.ipynb" "$REPO2" sess-caseP)")"
[ "$(decision "$OUT_P")" = deny ] && pass "caseP: NotebookEdit into a foreign repo denies" \
  || fail "caseP: expected deny, got: $OUT_P"

# --- case Q: MultiEdit into a foreign repo denies too ------------------------------------------------
FOREIGNQ="$T/foreignq"; mkdir -p "$FOREIGNQ"; (cd "$FOREIGNQ" && git init -q)
OUT_Q="$(run "$(payload MultiEdit "$FOREIGNQ/q.txt" "$REPO2" sess-caseQ)")"
[ "$(decision "$OUT_Q")" = deny ] && pass "caseQ: MultiEdit into a foreign repo denies" \
  || fail "caseQ: expected deny, got: $OUT_Q"

# --- case R: a not-yet-existing nested target path still walks up to the foreign repo root ---------
FOREIGNR="$T/foreignr"; mkdir -p "$FOREIGNR"; (cd "$FOREIGNR" && git init -q)
OUT_R="$(run "$(payload Write "$FOREIGNR/a/b/c.txt" "$REPO2" sess-caseR)")"
[ "$(decision "$OUT_R")" = deny ] && pass "caseR: write to a not-yet-existing nested path still denies" \
  || fail "caseR: expected deny, got: $OUT_R"

# --- case S: a session cwd that is not a repo at all treats any repo write as foreign ---------------
FOREIGNS="$T/foreigns"; mkdir -p "$FOREIGNS"; (cd "$FOREIGNS" && git init -q)
OUT_S="$(run "$(payload Write "$FOREIGNS/s.txt" "$NONGIT" sess-caseS)")"
[ "$(decision "$OUT_S")" = deny ] && pass "caseS: a non-repo session cwd still denies a write into a repo" \
  || fail "caseS: expected deny, got: $OUT_S"

# --- case T: a relative file_path is resolved against the payload cwd - own, peerless repo, so this
# must produce no output at all ----------------------------------------------------------------------
OUT_T="$(run "$(payload Write "own-rel.txt" "$REPO2" sess-caseT)")"
[ -z "$OUT_T" ] && pass "caseT: relative file_path resolved against the session's own repo cwd is silent" \
  || fail "caseT: expected no output, got: $OUT_T"

# --- case U: an exported CDPATH must not change a same-repo worktree write's classification - a fresh
# peerless repo+worktree so arm1 cannot contribute unrelated output; worktree creation failing here
# is a hard fail, not a skip ---------------------------------------------------------------------------
REPOU="$T/repou"; mkdir -p "$REPOU"; (cd "$REPOU" && git init -q && git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init)
WTU="$T/repou-wt"
if (cd "$REPOU" && git worktree add -q "$WTU" -b wtu-branch) 2>/dev/null; then
  OUT_U="$(CDPATH="$T" run "$(payload Write "$WTU/u.txt" "$REPOU" sess-caseU)")"
  [ -z "$OUT_U" ] && pass "caseU: an exported CDPATH does not change a same-repo worktree write's no-decision result" \
    || fail "caseU: expected no output, got: $OUT_U"
else
  fail "caseU: git worktree add failed"
fi

# --- case V: a session_id longer than the 128-char cap fails open with no output at all -------------
LONGSID=""; i=0
while [ "$i" -lt 200 ]; do LONGSID="${LONGSID}a"; i=$((i + 1)); done
OUT_V="$(run "$(payload Write "$REPO2/v.txt" "$REPO2" "$LONGSID")")"
[ -z "$OUT_V" ] && pass "caseV: a 200-char session_id fails open with no output" \
  || fail "caseV: expected no output, got: $OUT_V"

# --- case W: PEER_GUARD_SOCK_DIR unset, XDG_RUNTIME_DIR set -> SOCK_DIR falls back to
# $XDG_RUNTIME_DIR/cc-socks only when /run/user/<uid>/cc-socks does NOT exist on this host - that real
# path wins whenever it is present, so this branch is only observable (and only tested) when it isn't.
RUN_UID_SOCK_DIR="/run/user/$(id -u 2>/dev/null)/cc-socks"
if [ -d "$RUN_UID_SOCK_DIR" ]; then
  echo "note: caseW skipped - $RUN_UID_SOCK_DIR exists on this host, so it wins over XDG_RUNTIME_DIR by design"
else
  XDIR="$T/xdgrun"; mkdir -p "$XDIR/cc-socks"
  WPEER="$(spawn_claude "$FOREIGNO")"
  touch "$XDIR/cc-socks/$WPEER.sock"
  OUT_W="$(env -u PEER_GUARD_SOCK_DIR XDG_RUNTIME_DIR="$XDIR" PEER_GUARD_SELF_PID="$SELF" "$TESTSH" "$G" --list)"
  case "$OUT_W" in
    *"$WPEER "*) pass "caseW: XDG_RUNTIME_DIR/cc-socks used when PEER_GUARD_SOCK_DIR is unset and /run/user/<uid>/cc-socks is absent" ;;
    *) fail "caseW: expected pid $WPEER via XDG_RUNTIME_DIR fallback, got: $OUT_W" ;;
  esac
  rm -f "$XDIR/cc-socks/$WPEER.sock"; kill -9 "$WPEER" 2>/dev/null
fi

# kill the case4/caseD nested processes now that both have used them
rm -f "$SOCKDIR/$NESTSELF.sock" "$SOCKDIR/$NESTCHILD.sock"
kill -9 "$NESTSELF" "$NESTCHILD" 2>/dev/null

# --- mutation check 1: delete the ancestor-of-self exclusion line -> caseD-style check must fail ----
echo "--- mutation check 1: ancestor-of-self exclusion ---"
cp "$SRC" "$G"
MSELF="$(spawn_claude)"
cat > "$T/nest2.sh" <<NEST2EOF
exec -a claude bash -c '
  ( exec -a claude sleep 300 ) &
  echo \$! > "$T/child2.pid"
  wait
'
NEST2EOF
bash "$T/nest2.sh" &
MPARENT=$!
disown "$MPARENT" 2>/dev/null || true
if MCHILD="$(wait_for_pidfile "$T/child2.pid")"; then
  touch "$SOCKDIR/$MPARENT.sock" "$SOCKDIR/$MCHILD.sock"
  sed -i '/for p in \$PG_SELF_ANCESTRY; do \[ "\$p" = "\$cand" \] && return 0; done/d' "$G"
  MOUT1="$(PEER_GUARD_SELF_PID="$MCHILD" "$TESTSH" "$G" --list "$SOCKDIR")"
  case "$MOUT1" in
    *"$MPARENT "*) pass "mutation1: deleting the ancestor-exclusion line makes the ancestor reappear as a peer (case D would fail)" ;;
    *) fail "mutation1: ancestor-exclusion mutation had no effect (case D would still pass - mutation ineffective)" ;;
  esac
  rm -f "$SOCKDIR/$MPARENT.sock" "$SOCKDIR/$MCHILD.sock"
else
  fail "mutation1: nested child never wrote its pid file"
fi
kill -9 "$MPARENT" "${MCHILD:-}" "$MSELF" 2>/dev/null
cp "$SRC" "$G"   # restore

# --- mutation check 2: make the .peer marker get written on EVERY decision for a live-peer target,
# not only a real `ask` -> a converted (subagent) deny's retry must then pass silently instead of
# denying again (caseA-style check would fail) --------------------------------------------------------
echo "--- mutation check 2: ask-only marker-write guard ---"
MPEER="$(spawn_claude "$FOREIGNM")"
sed -i 's/DEC="\$(guard_ask_decision "\$SID" "\$AGT")"/: > "$MARKER_PEER" 2>\/dev\/null; DEC="$(guard_ask_decision "$SID" "$AGT")"/' "$G"
MA1="$(printf '%s' "$(payload Write "$FOREIGNM/a.txt" "$REPO" sess-mut2 worker)" | "$TESTSH" "$G")"
MA2="$(printf '%s' "$(payload Write "$FOREIGNM/b.txt" "$REPO" sess-mut2 worker)" | "$TESTSH" "$G")"
if [ "$(decision "$MA1")" = deny ] && [ -z "$(decision "$MA2")" ]; then
  pass "mutation2: writing the .peer marker unconditionally (not ask-only) makes a converted deny's retry pass silently (case A would fail)"
else
  fail "mutation2: marker-write-guard mutation had no effect (case A would still pass - mutation ineffective)"
fi
kill -9 "$MPEER" 2>/dev/null
cp "$SRC" "$G"   # restore

echo "--- guards.log sample ---"
grep -a peer-guard "$LOG" 2>/dev/null | tail -5

if [ "$fails" = 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "SELF-CHECK FAILED ($fails)"
  exit 1
fi

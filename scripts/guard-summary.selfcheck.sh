#!/usr/bin/env sh
# kit-scope: shared
# Self-check for guard-summary.sh (SessionEnd block summary). Runnable: `sh guard-summary.selfcheck.sh`.
# Runs an isolated COPY of the script (BASE resolves script-relative, so the copy reads a sandbox
# .state/guards.log, never the real one) against a planted log.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (summary counts all sessions without it; not asserted here)"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/.state" "$T/install" "$T/cfg"; cp "$DIR/guard-summary.sh" "$T/scripts/"
mkdir -p "$T/managed"; sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$DIR/kit-gate.sh" > "$T/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$T/scripts/kit-gate.sh" || { echo "SELF-CHECK FAILED: _kg_managed not rewritten"; exit 1; }
cp "$DIR/../install/options.tsv" "$T/install/"
export CLAUDE_CONFIG_DIR="$T/cfg" AGENT_TIERS_GUARDS_LOG="$T/.state/guards.log"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
G="$T/scripts/guard-summary.sh"
run() { jq -n --arg s "$1" '{session_id: $s}' | sh "$G" 2>&1 >/dev/null; }

# no log at all -> silent
rm -f "$T/.state/guards.log"
[ -z "$(run abc)" ] && ok 'no log -> silent' || bad 'no log -> silent'

cat > "$T/.state/guards.log" <<'EOF'
2026-08-16T20:00:00+0100 hygiene-commit-guard deny: output-hygiene glyph - x [sid=s1]
2026-08-16T20:01:00+0100 vcs-commit-guard declined: unresolvable cd/-C target (x) - not scanning [sid=s1]
2026-08-16T20:02:00+0100 kit-leak-guard ask: leak-scan staged found: warn [private-vocab] 1 hit(s) [sid=s1]
2026-08-16T20:03:00+0100 security-gate fail-open: jq missing - cannot parse payload
2026-08-16T20:04:00+0100 security-gate deny: Bash Content being written to /tmp/x contains a key [sid=s2]
2026-08-16T20:05:00+0100 hygiene-commit-guard deny: output-hygiene glyph - selfcheck fixture [sid=]
EOF
out="$(run s1)"
printf '%s' "$out" | grep -q '^agent-tiers: 2 guard block(s) this session (deny 1, ask 1); last: 2026-08-16T20:02:00+0100 kit-leak-guard ask:' \
  && ok 'session s1: deny+ask counted, declined/fail-open/other-session/selfcheck excluded, last line named' \
  || bad "session s1 summary wrong: $out"
printf '%s' "$out" | grep -q '\[sid=' && bad 'sid tag should be stripped from the last-line excerpt' || ok 'sid tag stripped from excerpt'
out="$(run s2)"
printf '%s' "$out" | grep -q '^agent-tiers: 1 guard block(s) this session (deny 1, ask 0)' && ok 'session s2: one deny' || bad "session s2 wrong: $out"
out="$(run s3)"
printf '%s' "$out" | grep -q '^agent-tiers: 0 guard blocks this session' && ok 'unknown session: zero, still prints' || bad "session s3 wrong: $out"
# no session_id -> all-time count of REAL sessions (the [sid=] selfcheck line is excluded), said plainly
out="$(printf '{}' | sh "$G" 2>&1 >/dev/null)"
printf '%s' "$out" | grep -q '^agent-tiers: 3 guard block(s) all sessions (no session_id in payload)' && ok 'no session_id -> all-time count of real sessions, labelled' || bad "no-sid wrong: $out"
# a reason that itself contains " ask: " must not double-count (decision token is field 3)
printf '2026-08-16T20:06:00+0100 hygiene-commit-guard deny: message text mentions ask: nothing [sid=s4]\n' >> "$T/.state/guards.log"
out="$(run s4)"
printf '%s' "$out" | grep -q '(deny 1, ask 0)' && ok 'embedded " ask: " in a reason is not counted as an ask' || bad "double-count: $out"
# `.` in a session id is literal, not any-char
printf '2026-08-16T20:07:00+0100 hygiene-commit-guard deny: x [sid=a.b]\n2026-08-16T20:07:01+0100 hygiene-commit-guard deny: y [sid=axb]\n' >> "$T/.state/guards.log"
out="$(run a.b)"
printf '%s' "$out" | grep -q '^agent-tiers: 1 guard block(s)' && ok 'dot in session id matched literally' || bad "dot-in-sid: $out"
# 2026-10-14: the `[sid=<id> agent=<type>]` tag (five writers) and the `agent=<type> [sid=<id>]` form
# are both this session's lines; the selfcheck form `[sid= agent=...]` is excluded from all-time.
printf '2026-08-16T20:08:00+0100 vcs-commit-guard deny: x [sid=s5 agent=worker]\n' >> "$T/.state/guards.log"
out="$(run s5)"
printf '%s' "$out" | grep -q '^agent-tiers: 1 guard block(s) this session (deny 1, ask 0)' && ok '[sid=s5 agent=worker] deny counted for s5' || bad "bracketed agent form not counted: $out"
printf '%s' "$out" | grep -q 'sid=\|agent=worker' && bad "bracketed agent tag not stripped from excerpt: $out" || ok 'bracketed agent tag stripped from excerpt'
printf '2026-08-16T20:09:00+0100 reach-guard deny: x agent=worker [sid=s6]\n' >> "$T/.state/guards.log"
out="$(run s6)"
printf '%s' "$out" | grep -q '^agent-tiers: 1 guard block(s) this session (deny 1, ask 0)' && ok 'agent=worker [sid=s6] deny counted for s6' || bad "trailing sid form not counted: $out"
printf '2026-08-16T20:10:00+0100 vcs-commit-guard deny: real [sid=s7]\n2026-08-16T20:10:01+0100 vcs-commit-guard deny: fixture [sid= agent=lead]\n' > "$T/.state/g2.log"
out="$(printf '{}' | AGENT_TIERS_GUARDS_LOG="$T/.state/g2.log" sh "$G" 2>&1 >/dev/null)"
printf '%s' "$out" | grep -q '^agent-tiers: 1 guard block(s) all sessions' && ok '[sid= agent=lead] selfcheck line excluded from all-time' || bad "selfcheck agent form counted all-time: $out"
# stdout stays empty (a SessionEnd hook's stdout is not a channel either; stderr is the candidate)
[ -z "$(jq -n '{session_id:"s1"}' | sh "$G" 2>/dev/null)" ] && ok 'nothing on stdout' || bad 'stdout must stay empty'
# a hostile session id is neutralised, not interpolated into the regex
out="$(run 'a.*|x')"
printf '%s' "$out" | grep -q 'all sessions (session_id in payload was not id-shaped)' && ok 'non-alnum session id falls back to all-time, labelled as such (never a regex)' || bad "hostile sid: $out"

# rotation: an oversized log gets archived (dated), never truncated - and this session's own
# summary line still reports correctly even though rotation runs in the same invocation.
printf '2026-08-16T21:00:00+0100 hygiene-commit-guard deny: x [sid=srot]\n' >> "$T/.state/guards.log"
BEFORE_BYTES="$(wc -c < "$T/.state/guards.log")"
out="$(AGENT_TIERS_LOG_ROTATE_BYTES=$((BEFORE_BYTES - 1)) run srot)"
printf '%s' "$out" | grep -q '^agent-tiers: 1 guard block(s) this session' \
  && ok 'rotation: this session summary still correct when rotation fires in the same run' \
  || bad "rotation broke same-run summary: $out"
ARCHIVE="$(ls "$T/.state/"guards.log.[0-9]* 2>/dev/null | head -1)"
[ -n "$ARCHIVE" ] && [ -s "$ARCHIVE" ] && ok 'rotation: oversized log archived to a dated file, not deleted' \
  || bad 'rotation: no non-empty dated archive found after exceeding the threshold'
[ ! -f "$T/.state/guards.log" ] || bad 'rotation: original path should be moved away (mv), not left in place'
grep -aq 'sid=srot' "$ARCHIVE" 2>/dev/null && ok 'rotation: archived file still holds the original lines' \
  || bad 'rotation: archived file lost content'

# framing.log rotation must not depend on guards.log existing (H-2): remove guards.log entirely,
# plant an oversized framing.log, confirm it still rotates via the early-exit path.
rm -f "$T/.state/guards.log"
printf 'x\n' > "$T/.state/framing.log"
FBEFORE_BYTES="$(wc -c < "$T/.state/framing.log")"
jq -n --arg s "sfram" '{session_id:$s}' | AGENT_TIERS_LOG_ROTATE_BYTES=$((FBEFORE_BYTES - 1)) sh "$G" >/dev/null 2>&1
FARCHIVE="$(ls "$T/.state/"framing.log.[0-9]* 2>/dev/null | head -1)"
[ -n "$FARCHIVE" ] && [ -s "$FARCHIVE" ] && ok 'rotation: framing.log rotates even when guards.log is absent' \
  || bad 'rotation: framing.log did not rotate with no guards.log present (H-2)'

# reach-guard browser state is cleared at session end, guards.log absent; another session's state stays
rm -f "$T/.state/guards.log"; mkdir -p "$T/.state/reach-guard/pending"
for f in grant.srg pages.srg pending/srg.tu1 pending/srg.tu2 grant.other pending/other.tu1; do : > "$T/.state/reach-guard/$f"; done
run srg >/dev/null
[ ! -e "$T/.state/reach-guard/grant.srg" ] && [ ! -e "$T/.state/reach-guard/pages.srg" ] \
  && [ ! -e "$T/.state/reach-guard/pending/srg.tu1" ] && [ ! -e "$T/.state/reach-guard/pending/srg.tu2" ] \
  && ok 'reach-guard grant, pages and pending state cleared for this session with no guards.log' \
  || bad "reach-guard state survived session end: $(ls "$T/.state/reach-guard" "$T/.state/reach-guard/pending")"
[ -e "$T/.state/reach-guard/grant.other" ] && [ -e "$T/.state/reach-guard/pending/other.tu1" ] \
  && ok "reach-guard state of another session is kept" || bad "another session's reach-guard state was removed"
# the cleanup dir follows guard_state_dir: the kit .state when only the log is moved elsewhere ...
mkdir -p "$T/elsewhere"; : > "$T/.state/reach-guard/grant.srg2"
jq -n '{session_id:"srg2"}' | AGENT_TIERS_GUARDS_LOG="$T/elsewhere/g.log" sh "$G" >/dev/null 2>&1
[ ! -e "$T/.state/reach-guard/grant.srg2" ] && ok "reach-guard cleanup uses the kit .state when only the log is moved" \
  || bad "reach-guard cleanup missed the kit .state with the log moved elsewhere"
# ... and <dir>/.state when AGENT_TIERS_STATE_DIR does not end in /.state
mkdir -p "$T/sd/.state/reach-guard"; : > "$T/sd/.state/reach-guard/pages.srg3"
jq -n '{session_id:"srg3"}' | AGENT_TIERS_STATE_DIR="$T/sd" sh "$G" >/dev/null 2>&1
[ ! -e "$T/sd/.state/reach-guard/pages.srg3" ] && ok "reach-guard cleanup appends /.state to AGENT_TIERS_STATE_DIR" \
  || bad "reach-guard cleanup did not append /.state to AGENT_TIERS_STATE_DIR"

# --- timeout/kill tracing (2026-09-17): a start/end breadcrumb pair, joined on pid (no [sid=] on
# these lines - see each guard's own instrumentation comment). Three planted-log cases first, then a
# real kill proof.
rm -f "$T/.state/guards.log"
printf '2026-09-17T10:00:00+0100 fixture-guard start [pid=9001]\n' > "$T/.state/guards.log"
out="$(run tsid1)"
printf '%s' "$out" | grep -q '^agent-tiers: 1 guard run(s) did not complete (timeout/kill); see ' \
  && ok 'start with no matching end -> reported (count 1)' \
  || bad "unmatched start not reported: $out"

printf '2026-09-17T10:00:00+0100 fixture-guard start [pid=9002]\n2026-09-17T10:00:02+0100 fixture-guard end [pid=9002] done=1\n' > "$T/.state/guards.log"
out="$(run tsid2)"
printf '%s' "$out" | grep -q 'did not complete' \
  && bad "control case (done=1) must NOT report did-not-complete: $out" \
  || ok 'control: start + end done=1 -> no did-not-complete line'

printf '2026-09-17T10:00:00+0100 fixture-guard start [pid=9003]\n2026-09-17T10:00:02+0100 fixture-guard end [pid=9003] done=0\n' > "$T/.state/guards.log"
out="$(run tsid3)"
printf '%s' "$out" | grep -q '^agent-tiers: 1 guard run(s) did not complete (timeout/kill); see ' \
  && ok 'start + end done=0 -> reported (count 1)' \
  || bad "done=0 not reported: $out"

# Multiple unresolved runs count together in one line.
printf '2026-09-17T10:00:00+0100 fixture-guard start [pid=9004]\n2026-09-17T10:00:02+0100 fixture-guard end [pid=9004] done=0\n2026-09-17T10:00:03+0100 fixture-guard start [pid=9005]\n' > "$T/.state/guards.log"
out="$(run tsid4)"
printf '%s' "$out" | grep -q '^agent-tiers: 2 guard run(s) did not complete' \
  && ok 'two unresolved runs (one done=0, one unmatched start) -> count 2' \
  || bad "multi-count wrong: $out"

# --- real end-to-end kill proof: a minimal fixture script carrying the SAME window-tracing shape the
# 4 real guards now carry (GUARD_TRACE_OPEN + trap, start on window entry, end done=1 on window exit),
# killed with SIGTERM and SIGKILL, PLUS the control the corrected design exists to prove: a fast exit
# BEFORE the window ever opens logs nothing and is never counted. A real guard was not used here -
# forcing one of the four to block mid-scan for a controlled window without editing its own logic was
# impractical in this pass; this is disclosed as a weaker proof than an actual guard kill would be.
FIXLOG="$T/.state/fixture-kill.log"
cat > "$T/scripts/fixture-guard.sh" <<'FIXEOF'
#!/usr/bin/env sh
set -u
LOG="${AGENT_TIERS_GUARDS_LOG:?}"
note() { { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s fixture-guard %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true; }
GUARD_TRACE_OPEN=0
trap 'if [ "$GUARD_TRACE_OPEN" = 1 ]; then note "end [pid=$$] done=0"; fi' EXIT
trap 'exit 143' TERM
# $2 = "fast" simulates a run that exits before ever reaching the expensive window (a normal fail-open
# path in a real guard) - must exit without ever opening the window.
[ "${2:-}" = fast ] && exit 0
GUARD_TRACE_OPEN=1; note "start [pid=$$]"
sleep "${1:-5}"
GUARD_TRACE_OPEN=0; note "end [pid=$$] done=1"
exit 0
FIXEOF
chmod +x "$T/scripts/fixture-guard.sh"

# Control: a fast exit before the window opens logs NOTHING - this is the case the OLD (pre-correction)
# design would have logged as a start/end pair (or an unmatched start) on every ordinary invocation.
: > "$FIXLOG"
AGENT_TIERS_GUARDS_LOG="$FIXLOG" sh "$T/scripts/fixture-guard.sh" 0 fast
[ ! -s "$FIXLOG" ] \
  && ok 'control: a fast exit before the window opens logs nothing (not counted, not even a pair)' \
  || bad "fast pre-window exit wrote to the log: $(cat "$FIXLOG" 2>/dev/null)"

# SIGTERM mid-sleep -> end ... done=0
: > "$FIXLOG"
AGENT_TIERS_GUARDS_LOG="$FIXLOG" sh "$T/scripts/fixture-guard.sh" 5 &
fpid=$!
sleep 1
kill -TERM "$fpid" 2>/dev/null
wait "$fpid" 2>/dev/null
grep -aq "end \[pid=${fpid}\] done=0\$" "$FIXLOG" 2>/dev/null \
  && ok 'real SIGTERM: fixture guard logs end ... done=0 (EXIT trap fires, window never closed to done=1)' \
  || bad "real SIGTERM did not produce a done=0 end line: $(cat "$FIXLOG" 2>/dev/null)"

# SIGKILL mid-sleep -> start with no end at all
: > "$FIXLOG"
AGENT_TIERS_GUARDS_LOG="$FIXLOG" sh "$T/scripts/fixture-guard.sh" 5 &
fpid=$!
sleep 1
kill -KILL "$fpid" 2>/dev/null
wait "$fpid" 2>/dev/null
grep -aq "start \[pid=${fpid}\]\$" "$FIXLOG" 2>/dev/null && ! grep -aq "end \[pid=${fpid}\]" "$FIXLOG" 2>/dev/null \
  && ok 'real SIGKILL: fixture guard logs a start with no matching end at all (no trap runs)' \
  || bad "real SIGKILL did not leave an unmatched start: $(cat "$FIXLOG" 2>/dev/null)"

# kit-gate line is live: AGENT_TIERS_OFF=1 -> rc 0, NO summary on stderr, standdown logged, BUT housekeeping
# still runs (the unattended flag for that sid is cleared).
GL="$T/.state/gate.log"; : > "$GL"; : > "$T/.state/unattended.gate-4"
out="$(jq -n '{session_id: "gate-4"}' | AGENT_TIERS_OFF=1 CLAUDE_CODE_SESSION_ID=gate-4 AGENT_TIERS_GUARDS_LOG="$GL" sh "$G" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'guard block' && grep -q 'kit-gate standdown guard-summary: AGENT_TIERS_OFF=1 \[sid=gate-4\]' "$GL" 2>/dev/null \
  && ok "kit-gate: AGENT_TIERS_OFF=1 stands the report down (rc 0, no summary, logged)" || bad "kit-gate line not live: rc=$rc out=$out"
[ ! -e "$T/.state/unattended.gate-4" ] && ok "kit-gate: housekeeping still clears the unattended flag when off" || bad "unattended flag survived a stood-down run"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

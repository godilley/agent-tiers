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
mkdir -p "$T/scripts" "$T/.state"; cp "$DIR/guard-summary.sh" "$T/scripts/"
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
# stdout stays empty (a SessionEnd hook's stdout is not a channel either; stderr is the candidate)
[ -z "$(jq -n '{session_id:"s1"}' | sh "$G" 2>/dev/null)" ] && ok 'nothing on stdout' || bad 'stdout must stay empty'
# a hostile session id is neutralised, not interpolated into the regex
out="$(run 'a.*|x')"
printf '%s' "$out" | grep -q 'all sessions (session_id in payload was not id-shaped)' && ok 'non-alnum session id falls back to all-time, labelled as such (never a regex)' || bad "hostile sid: $out"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for authorship-record.sh: feed synthetic PostToolUse payloads and assert (a) the nudge fires
# exactly ONCE per session and only for a non-trivial edit to a trust-class path, (b) the ledger records
# every edit either way, (c) it NEVER blocks, and (d) a traversal session_id writes nothing outside the
# state dir. Runs the recorder inside a throwaway kit copy so the real .state is never touched.
# Exits non-zero on first failure.
set -u
SRC="$(dirname "$0")/authorship-record.sh"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (recorder fails open by design)"; exit 0; }

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"   # macOS TMPDIR ends in "/" - a "//" in T breaks every pwd comparison (CI, 2026-08-16)
T="${TMPBASE}/at-authorship-selfcheck.$$"
rm -rf "$T"; mkdir -p "$T/kit/scripts" || fail "cannot build sandbox"
cp "$SRC" "$T/kit/scripts/" || fail "cannot copy recorder"
REC="$T/kit/scripts/authorship-record.sh"
STATE="$T/kit/.state/authorship"
trap 'rm -rf "$T"' EXIT

# Emitted payload for one edit. $1=session $2=path $3=new_string $4=old_string
pay() {
  jq -n --arg s "$1" --arg p "$2" --arg n "$3" --arg o "$4" \
    '{session_id:$s, hook_event_name:"PostToolUse", tool_name:"Edit",
      tool_input:{file_path:$p, new_string:$n, old_string:$o}}'
}
run() { printf '%s' "$1" | sh "$REC" 2>/dev/null || true; }
nudged() { printf '%s' "$1" | grep -q 'additionalContext' && echo YES || echo NO; }

BIG="$(awk 'BEGIN{for(i=0;i<12;i++) printf "line %d\n", i}')"     # multi-line => non-trivial
TRUSTPATH="/home/x/.claude/agent-tiers/scripts/codex-guard.sh"
PLAINPATH="/home/x/project/src/widget.js"

# Fixture validity FIRST - each case must actually be the thing it claims, or the assertion is vacuous
# (three of the previous wave's new tests passed for the wrong reason; this is the cheap guard against it).
printf '%s' "$BIG" | grep -q 'line 11' || fail "fixture invalid: BIG is not multi-line"
printf '%s' "$TRUSTPATH" | grep -Eqi '/agent-tiers/|guard\.sh$' || fail "fixture invalid: TRUSTPATH is not trust-class"
printf '%s' "$PLAINPATH" | grep -Eqi '(settings\.json|/hooks?/|/\.claude/|/agent-tiers/|guard\.sh$)' && fail "fixture invalid: PLAINPATH is trust-class"

# 1. First non-trivial trust-class edit -> nudge, and the ledger records it FLAGged.
S1=sess-aaaa-1111
out="$(run "$(pay "$S1" "$TRUSTPATH" "$BIG" "")")"
[ "$(nudged "$out")" = YES ] || fail "first non-trivial trust-class edit must nudge"
[ -f "$STATE/$S1.tsv" ] || fail "ledger not written for $S1"
grep -q "	FLAG	" "$STATE/$S1.tsv" || fail "trust-class edit not FLAGged in ledger"

# 2. Second such edit in the SAME session -> recorded, but silent. This is the once-per-session contract.
out="$(run "$(pay "$S1" "$TRUSTPATH" "$BIG" "")")"
[ "$(nudged "$out")" = NO ] || fail "nudge must fire once per session, not on every flagged edit"
[ "$(grep -c "	FLAG	" "$STATE/$S1.tsv")" -eq 2 ] || fail "second flagged edit must still be recorded"

# 3. Trivial (one-line) edit to a trust path -> no nudge. The SC-1.4 whitelist floor must hold.
S2=sess-bbbb-2222
out="$(run "$(pay "$S2" "$TRUSTPATH" "one line" "old line")")"
[ "$(nudged "$out")" = NO ] || fail "a one-line trust-path edit is SC-1.4 trivial and must not nudge"
grep -q "	ok	" "$STATE/$S2.tsv" || fail "trivial edit should still be recorded, unflagged"

# 4. Non-trivial edit to an ordinary path -> no nudge, still recorded.
S3=sess-cccc-3333
out="$(run "$(pay "$S3" "$PLAINPATH" "$BIG" "")")"
[ "$(nudged "$out")" = NO ] || fail "ordinary-path edit must not nudge"
grep -q "	ok	" "$STATE/$S3.tsv" || fail "ordinary-path edit should be recorded, unflagged"

# 4b. Ordinary edit FIRST, flagged edit second -> the nudge must still fire (cold-review F2: the ledger
# exists with zero FLAG rows at read time, the state every earlier fixture skipped via the init path).
S3b=sess-cc2c-3332
run "$(pay "$S3b" "$PLAINPATH" "$BIG" "")" >/dev/null
out="$(run "$(pay "$S3b" "$TRUSTPATH" "$BIG" "")")"
[ "$(nudged "$out")" = YES ] || fail "first flagged edit after an ordinary edit must nudge (F2 regression)"

# 5. A MultiEdit is never trivial, however small its parts.
S4=sess-dddd-4444
out="$(printf '%s' "$(jq -n --arg s "$S4" --arg p "$TRUSTPATH" \
  '{session_id:$s, tool_name:"MultiEdit", tool_input:{file_path:$p, edits:[{old_string:"a",new_string:"b"}]}}')" \
  | sh "$REC" 2>/dev/null || true)"
[ "$(nudged "$out")" = YES ] || fail "MultiEdit to a trust path must nudge (never trivial)"

# 6. It must NEVER block. No payload may produce a deny/block decision on any event.
for o in "$(run "$(pay sess-eeee-5555 "$TRUSTPATH" "$BIG" "")")" "$(run 'not json at all')"; do
  printf '%s' "$o" | grep -Eq '"(permissionDecision|decision)"[[:space:]]*:[[:space:]]*"(deny|block)"' \
    && fail "recorder must never block - it is a record, not a gate"
done

# 7. Traversal / unusable session ids write nothing outside the state dir and do not crash.
CANARY="$T/kit/canary"; echo "CANARY-MUST-NOT-LEAK" > "$CANARY"
before="$(find "$T/kit" -type f | sort)"
for bad in "../../canary" "." ".." "a/b" '$(id)' ""; do
  out="$(printf '%s' "$(jq -n --arg s "$bad" --arg p "$TRUSTPATH" --arg n "$BIG" \
    '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$p, new_string:$n}}')" \
    | sh "$REC" 2>/dev/null || true)"
  [ "$(nudged "$out")" = NO ] || fail "unsafe session_id '$bad' must not be used as a path component"
done
after="$(find "$T/kit" -type f | sort)"
[ "$before" = "$after" ] || fail "an unsafe session_id created files: $(printf '%s\n' "$after" | comm -13 - /dev/null | head -3)"
grep -q CANARY-MUST-NOT-LEAK "$CANARY" || fail "canary was clobbered"

# 8. Unparseable payload is a silent fail-open, not a crash and not a nudge.
out="$(run 'garbage {{{')"
[ -z "$out" ] || fail "unparseable payload must produce no output"

echo "OK authorship-record: nudges once per session on non-trivial trust-class authorship, records the rest, never blocks"

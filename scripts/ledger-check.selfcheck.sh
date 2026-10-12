#!/usr/bin/env sh
# kit-scope: shared
# Self-check for ledger-check.sh. Runnable: `sh ledger-check.selfcheck.sh`.
# Builds a throwaway git repo with a LIVE plan (status table) and a LIVE ledger planting one case
# per check, plus controls that must stay silent. Each planted case names the mutation that kills it.
#
# State sandboxing: the guard resolves its own kit root from $0 (not CLAUDE_CONFIG_DIR), so the
# script is copied into a fixture kit tree under one mktemp -d, same pattern as
# simple-rules-guard.selfcheck.sh. Never touches the real .state/.
set -u
HERE="$(CDPATH= cd "$(dirname "$0")" && pwd)"
SRC="$HERE/ledger-check.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git absent"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM

KIT="$T/kit"
mkdir -p "$KIT/scripts" "$KIT/.state"
cp "$SRC" "$KIT/scripts/"
HOOK="$KIT/scripts/ledger-check.sh"

FX="$T/fx"
mkdir -p "$FX/docs/_local"
export GIT_CONFIG_NOSYSTEM=1
git -C "$FX" init -q
git -C "$FX" config user.name selfcheck
git -C "$FX" config user.email t@t.local
echo seed > "$FX/seed.txt"
git -C "$FX" add seed.txt
git -C "$FX" commit -q -m seed
HEADSHA="$(git -C "$FX" rev-parse HEAD)"
GOODSHA7="$(printf '%s' "$HEADSHA" | cut -c1-7)"
BADSHA="0123456789abcdef0123456789abcdef01234567"
echo marker > "$FX/present-file.txt"
printf 'foo one\nbar\n' > "$FX/some-file.txt"

# Header row is capitalised ("Session") and the table carries extra header-ish ids (ID, Phase,
# Step) that must be skipped, never treated as real plan rows - otherwise CTRL-F5-HEADERWORDS
# below would spuriously fire F5 on those words.
cat > "$FX/docs/_local/2026-01-01-plan.md" <<'EOF'
STATUS: LIVE
# Plan
## Status table
| Session | state | proof |
|---|---|---|
| S1 | DONE 2026-01-02 | `x` |
| S10 | DONE 2026-01-03 | `y` |
| S2 | not started | |
| ID | not started | |
| Phase | not started | |
| Step | not started | |
EOF

cat > "$FX/docs/_local/2026-01-01-outstanding-work-ledger.md" <<EOF
STATUS: LIVE
# Ledger

## Typed

- **PLANT-L1-SESSION title**
  Deferred: thing.
  Forced by: [session: S1]
- **PLANT-L1-EXISTS title**
  Deferred: thing.
  Forced by: [exists: present-file.txt]
- **PLANT-L1-DATE title**
  Deferred: thing.
  Forced by: [date: 2000-01-01]
- **PLANT-L1-GREP title**
  Deferred: thing.
  Forced by: [grep>=1: foo @ some-file.txt]
- **CTRL-TYPED-UNFIRED title**
  Deferred: thing.
  Forced by: [session: S2] [date: 2999-01-01] [exists: nope]

## Untyped

- **PLANT-L1B title**
  Deferred: thing.
  Forced by: after S1 lands.
- **CTRL-S100 title**
  Deferred: thing.
  Forced by: after S100 lands.
- **CTRL-NOTHING title**
  Deferred: thing.
  Forced by: nothing named.
- **CTRL-NOTRIG title**
  Deferred: thing.
- **CTRL-LEGACY title** prose with no labels and no trigger.
- **PLANT-MIDLINE-OPEN title**
  Deferred: thing.
  Forced by: a report. DONE S1 by construction.

## Trigger

- **PLANT-TRIGGER-OVERRIDE title**
  Probe: would force this if we're unsure.
  Forced by: [session: S1]
- **CTRL-TRIGGER-ENFORCING-ONLY title**
  Cost: enforcing this manually, nothing else here.

## Closed

- **CTRL-CLOSED-FIRED title**
  Forced by: [session: S1]
  DONE 2026-01-02: checked with a real command.
- **PLANT-L3-UNCOMMITTED-NOCOLON title**
  DONE S9m7 (uncommitted at the time)
- **PLANT-L3-BARE-NOCOLON title**
  DONE S9m7
- **CTRL-L3-AFTERCOLON-NOFLAG title**
  DONE 2026-01-02: inspected the uncommitted tail of the run.
- **CTRL-L3-EXCEPTION-NOFLAG title**
  DONE 2026-01-02: exception handling of the edge case.
- **CTRL-F5-HEADERWORDS title**
  DONE 2026-01-02: the ID and Phase and Step were all fine.
- **CTRL-F5-DONE-ROW title**
  DONE 2026-01-02: unrelated note, S1 is already finished.
- **PLANT-L4-BAD title**
  DONE 2026-01-02 (\`$BADSHA\`): landed.
- **CTRL-L4-GOOD title**
  DONE 2026-01-02 (\`$HEADSHA\`): landed on HEAD.
- **CTRL-L4-GOOD-ABBREV title**
  DONE 2026-01-02 (\`$GOODSHA7\`): landed on HEAD, abbreviated.
- **PLANT-F5 title**
  DONE S2 (abc): check
- **CTRL-BOLD-CLOSED title**
  Forced by: [session: S1]
  **DONE 2026-01-02**: checked.
- **CTRL-L3-WRAPPED title**
  DONE 2026-01-02:
  wrapped check text on the next line.
- **CTRL-BOLD-TITLE-DONE title** **DONE S1 by construction**
  Forced by: [session: S1]
- **CTRL-L3-COL0 title**
  DONE 2026-01-02:
column-0 wrapped check paragraph.
- **CTRL-L3-SUBBULLET title**
  DONE 2026-01-02:
  - first check as a sub-bullet.
- **PLANT-L3-COLON-BLANK title**
  DONE 2026-01-02:

EOF

cat > "$FX/docs/_local/2026-01-01-old-outstanding-work-ledger.md" <<'EOF'
STATUS: ARCHIVE
- **CTRL-ARCHIVE title**
  Forced by: [session: S1]
EOF

run() { # $1 project dir; stdin = payload
  CLAUDE_PROJECT_DIR="$1" AGENT_TIERS_GUARDS_LOG="$T/guards.log" sh "$HOOK"
}
PAYLOAD='{"hook_event_name":"SessionStart","session_id":"selfcheck","source":"startup"}'
out="$(printf '%s' "$PAYLOAD" | run "$FX")"; rc=$?
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
has() { printf '%s\n' "$ctx" | grep -qF -- "$1"; }
L=2026-01-01-outstanding-work-ledger.md
# finding <ctx> <code> <substring>: a finding line of that code, any line number, carrying the
# literal substring (grep -F throughout, so a paren or colon in the substring needs no escaping).
finding() { printf '%s\n' "$1" | grep -E -- "^agent-tiers ledger: $2 $L:[0-9]+: " | grep -qF -- "$3"; }

[ "$rc" -eq 0 ] && ok "exits 0" || bad "exit $rc"
[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" = SessionStart ] \
  && ok "valid SessionStart JSON" || bad "not a SessionStart payload: $out"
dec=0
for field in '.decision' '.permissionDecision' '.hookSpecificOutput.permissionDecision' '.continue'; do
  [ "$(printf '%s' "$out" | jq -r "$field // \"null\"" 2>/dev/null)" = null ] || dec=1
done
[ "$dec" = 0 ] && ok "no decision fields" || bad "decision field present: $out"

[ "$(printf '%s\n' "$ctx" | grep -c '^agent-tiers ledger: L[0-9F]')" -le 6 ] 2>/dev/null && ok "at most 6 detail lines" \
  || bad "more than 6 detail lines: $ctx"
printf '%s\n' "$ctx" | grep -qE '^agent-tiers ledger: \+[0-9]+ more$' && ok "+N more line present when over cap" \
  || bad "no +N more line: $ctx"
has "agent-tiers ledger: $L open 16, labelled 11, no trigger 6, nothing-named 1, legacy 5, closed 14" \
  && ok "counts line correct" || bad "counts line wrong: $ctx"
has "2026-01-01-old-outstanding-work-ledger.md" && bad "STATUS: ARCHIVE ledger was read" || ok "non-LIVE ledger ignored"

# Per-case runs: one ledger holding only the entries of one section, so the cap cannot hide a case.
section() { # $1 = section heading; prints a LIVE ledger with only that section
  printf 'STATUS: LIVE\n'
  awk -v h="## $1" '$0 == h { on = 1; print; next } /^## / { on = 0 } on' "$FX/docs/_local/$L"
}
for sec in Typed Untyped Trigger Closed; do
  mkdir -p "$T/$sec/docs/_local" && cp "$FX/docs/_local/2026-01-01-plan.md" "$T/$sec/docs/_local/"
  section "$sec" > "$T/$sec/docs/_local/$L"
  cp "$FX/present-file.txt" "$FX/some-file.txt" "$T/$sec/"
  rm -rf "$T/$sec/.git"; cp -r "$FX/.git" "$T/$sec/.git"
done
sctx() { printf '%s' "$PAYLOAD" | run "$T/$1" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }
ty="$(sctx Typed)"; un="$(sctx Untyped)"; tr="$(sctx Trigger)"; cl="$(sctx Closed)"
in_() { printf '%s\n' "$1" | grep -qF -- "$2"; }

# Mutation: drop the session branch of the token loop -> L1 session missing.
in_ "$ty" "L1 $L:4: PLANT-L1-SESSION" && ok "L1 session token fires" || bad "L1 session: $ty"
# Mutation: test the path without the project-dir prefix -> exists never fires.
in_ "$ty" "L1 $L:7: PLANT-L1-EXISTS" && ok "L1 exists token fires" || bad "L1 exists: $ty"
# Mutation: compare dates the wrong way (>=) -> 2000-01-01 stops firing.
in_ "$ty" "L1 $L:10: PLANT-L1-DATE" && ok "L1 date token fires" || bad "L1 date: $ty"
# Mutation: split on the first space instead of " @ " -> path wrong, grep never fires.
in_ "$ty" "L1 $L:13: PLANT-L1-GREP" && ok "L1 grep token fires" || bad "L1 grep: $ty"
# Control: S2 not DONE, 2999 in the future, nope absent -> nothing for that entry.
in_ "$ty" "CTRL-TYPED-UNFIRED" && bad "unfired typed tokens reported: $ty" || ok "unfired typed tokens silent"
# Mutation: drop the word boundary in hasword -> S1 matches inside S100 and CTRL-S100 fires.
in_ "$un" "L1b $L:4: PLANT-L1B" && ok "L1b untyped trigger fires on S1" || bad "L1b: $un"
in_ "$un" "CTRL-S100" && bad "L1b over-matched S1 inside S100: $un" || ok "L1b whole-word boundary holds (S100 silent)"
in_ "$un" "CTRL-NOTHING" && bad "nothing-named entry listed: $un" || ok "nothing-named entry not listed"
in_ "$un" "CTRL-LEGACY" && bad "legacy entry listed: $un" || ok "legacy entry with no trigger not listed"
# Control: a DONE sitting mid-line after prose does not close the entry (it stays open, L1b on S1).
in_ "$un" "L1b $L:16: PLANT-MIDLINE-OPEN" && ok "mid-line DONE leaves the entry open" || bad "mid-line DONE: $un"

# --- Trigger-selection (review finding 2): "Forced by:" always wins over an earlier loose match,
# and the loose fallback only matches forced by/would force/forcing on a word boundary. ---
# Mutation: drop the "t ~ /^Forced by:/" override -> trig stays stuck on the earlier "Probe:"
# loose match, which names no session, so neither L1 nor any finding fires for this entry.
printf '%s\n' "$tr" | grep -qE '^agent-tiers ledger: L1 .*PLANT-TRIGGER-OVERRIDE' \
  && ok "a real Forced by: line always wins as the trigger, even after an earlier loose match" \
  || bad "trigger override: $tr"
# Mutation: drop the word boundary in the loose fallback -> "enforcing" inside "Cost: enforcing"
# is read as a trigger (it is not one), and/or this legacy no-trigger entry stops counting as such.
in_ "$tr" "CTRL-TRIGGER-ENFORCING-ONLY" && bad "enforcing (inside a Cost: line) was read as a trigger: $tr" \
  || ok "loose fallback does not match 'enforcing' inside 'Cost: enforcing' (word boundary holds)"
in_ "$tr" "open 2, labelled 1, no trigger 1, nothing-named 0, legacy 1, closed 0" \
  && ok "trigger-section counts correct" || bad "trigger-section counts wrong: $tr"

# --- L3 (review finding 3): qualifier tested only in the DONE line's head; no colon is its own
# empty check; any L3 flag leaves the entry open (not a retirement). ---
# Mutation: test the qualifier words against the whole line instead of the head -> the real check
# text ("inspected the uncommitted tail") after the colon would wrongly flag this entry.
finding "$cl" L3 'inspected the uncommitted tail' && bad "qualifier matched after the colon: $cl" \
  || ok "qualifier word after the colon does not flag L3"
# Mutation: drop the whole-word boundary on "except" -> "exception" matches and this flags too.
finding "$cl" L3 'exception handling of the edge case' && bad "'exception' matched as the qualifier 'except': $cl" \
  || ok "'exception' does not match the whole-word qualifier 'except'"
# Mutation: require a colon before testing for emptiness -> a bare DONE line with no colon at all
# (and no qualifier word) is never flagged, and "DONE plus an id" silently passes again.
finding "$cl" L3 'no check after DONE' && ok "a DONE line with no colon is its own empty check" \
  || bad "L3 missing on a DONE line with no colon: $cl"
# Mutation: skip the qualifier test when there is no colon -> the qualifier itself, with no colon
# at all, must still flag (this is the exact brief example: "DONE S9m7 (uncommitted at the time)").
finding "$cl" L3 'uncommitted at the time' && ok "qualifier in the head still flags with no colon" \
  || bad "L3 missing on qualifier + no colon: $cl"
# Mutation: treat an L3 flag as closing the entry (as the doc says it must not) -> the 3 flagged
# entries (qualifier-no-colon, bare-no-colon, colon-then-blank) would count as closed instead of
# open, and their (absent) triggers would never be the thing evaluated.
in_ "$cl" "open 3, labelled 0, no trigger 3, nothing-named 0, legacy 3, closed 14" \
  && ok "an L3-flagged entry stays open, not closed" || bad "L3-flagged entries miscounted: $cl"
# Mutation: treat ID/Phase/Step/a capitalised header row as real plan rows -> F5 fires on this
# entry's prose naming all three header words.
finding "$cl" F5 'the ID and Phase and Step were all fine' && bad "a header-row word (id/phase/step) was read as a plan row: $cl" \
  || ok "header row and id/session/phase/step rows are skipped case-insensitively"
# Mutation: drop the **DONE form from the closed test -> the bold entry is open and its S1 trigger is listed.
in_ "$cl" "CTRL-BOLD-CLOSED" && bad "bold **DONE entry not treated as closed: $cl" || ok "bold **DONE line closes the entry"
# Mutation: drop the next-line lookahead -> a check wrapped onto the next line is reported as empty.
finding "$cl" L3 'wrapped check text on the next line' && bad "L3 fired on a wrapped check: $cl" || ok "L3 silent when the check wraps to the next line"
# Mutation: drop the bold-title-then-bold-DONE bullet rule -> that entry is open and its S1 trigger listed.
in_ "$cl" "CTRL-BOLD-TITLE-DONE" && bad "bold title + bold DONE bullet not closed: $cl" || ok "bold title + bold DONE bullet closes the entry"
# Mutation: treat a column-0 non-bullet line as ending the check -> wrapped paragraph reported empty.
finding "$cl" L3 'column-0 wrapped check paragraph' && bad "L3 fired on a column-0 continuation: $cl" || ok "L3 silent on a column-0 continuation"
# Mutation: treat an indented "- " line as ending the check -> sub-bullet check reported empty.
finding "$cl" L3 'first check as a sub-bullet' && bad "L3 fired on a sub-bullet continuation: $cl" || ok "L3 silent on a sub-bullet continuation"
# Mutation: treat a blank line as check text -> colon-then-blank stops firing.
finding "$cl" L3 'DONE 2026-01-02:' && ok "L3 fires on colon then blank line" || bad "L3 colon-blank: $cl"
# Control: a closed entry is never evaluated for triggers.
in_ "$cl" "CTRL-CLOSED-FIRED" && bad "closed entry trigger reported: $cl" || ok "closed entry with fired trigger silent"
# Mutation: drop "uncommitted" from the qualifier list -> L3 qualifier missing.
finding "$cl" L3 'uncommitted at the time' && ok "L3 qualifier fires" || bad "L3 qualifier: $cl"

# --- L4 (review finding 4): one `git rev-list HEAD` membership test, no 60-sha cap. ---
# Mutation: skip the rev-list membership check entirely -> an unknown sha is never reported.
finding "$cl" L4 "$BADSHA not in HEAD history" && ok "L4 unknown sha fires" || bad "L4 bad sha: $cl"
# Mutation: compare against a truncated or stale rev-list -> the real HEAD sha is reported.
in_ "$cl" "$HEADSHA" && bad "L4 reported the real HEAD sha: $cl" || ok "L4 HEAD sha silent"
# Mutation: require an exact-length match instead of a prefix (grep -q "^$sha") -> an abbreviated
# 7-char real sha is reported as missing even though it is a real ancestor.
in_ "$cl" "$GOODSHA7" && bad "L4 reported an abbreviated real sha as missing: $cl" || ok "L4 abbreviated real sha silent"
# Mutation: compare against DONE rows instead of non-DONE rows -> F5 missing.
finding "$cl" F5 'DONE S2 (abc): check' && ok "F5 DONE line naming a not-DONE row fires" || bad "F5: $cl"
# Mutation: compare against non-DONE rows the wrong way round (DONE rows instead) -> F5 fires on
# S1, which the plan already marks DONE.
finding "$cl" F5 'unrelated note, S1 is already finished' && bad "F5 fired on a DONE row id: $cl" || ok "F5 silent on a DONE row id"

# No ledger -> empty stdout.
mkdir -p "$T/empty/docs/_local"
out="$(printf '%s' "$PAYLOAD" | run "$T/empty")"
[ -z "$out" ] && ok "no ledger -> empty stdout" || bad "no-ledger run printed: $out"

# Kill switch -> empty stdout, even with planted cases present. Resolved from $0 (KIT), not
# CLAUDE_CONFIG_DIR: proves the fix moved the kill switch off the per-profile config dir.
mkdir -p "$KIT/.state/off" && touch "$KIT/.state/off/ledger-check"
out="$(printf '%s' "$PAYLOAD" | run "$FX")"
[ -z "$out" ] && ok "kill switch (resolved from \$0) -> empty stdout" || bad "kill switch ignored: $out"
rm -f "$KIT/.state/off/ledger-check"

# Mutation: compare line count with -ge 15000 or drop the cap -> L5 missing on a 1501-line ledger.
mkdir -p "$T/big/docs/_local"
{ echo 'STATUS: LIVE'; i=1; while [ "$i" -le 1500 ]; do echo "line $i"; i=$((i + 1)); done; } > "$T/big/docs/_local/2026-01-01-big-outstanding-work-ledger.md"
big="$(printf '%s' "$PAYLOAD" | run "$T/big" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
in_ "$big" "L5 2026-01-01-big-outstanding-work-ledger.md:1: over cap (1501 lines" && ok "L5 over-cap fires at 1501 lines" || bad "L5: $big"

# cwd from the payload is used when CLAUDE_PROJECT_DIR is unset.
out="$(unset CLAUDE_PROJECT_DIR; printf '{"session_id":"selfcheck","cwd":"%s"}' "$T/Untyped" | AGENT_TIERS_GUARDS_LOG="$T/guards.log" sh "$HOOK" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
in_ "$out" "PLANT-L1B" && ok "payload cwd used when CLAUDE_PROJECT_DIR unset" || bad "payload cwd ignored: $out"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

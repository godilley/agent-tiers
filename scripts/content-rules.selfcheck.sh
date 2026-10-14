#!/usr/bin/env sh
# kit-scope: shared
# Self-check for scripts/lib/content-rules.sh, covering what memory-content-lint.selfcheck.sh cannot see
# from outside the hook (library hygiene, and the mktemp-failure fail-open path). Id-shaped-token
# exclusion, frontmatter id-line-only blanking and description-sha detection are ALSO exercised end to
# end through memory-content-lint.selfcheck.sh; the fixtures here are the library-level versions of the
# same cases, run directly against the functions rather than through the hook's payload/scope wrapper.
# Exits non-zero on first failure.
set -u
LIB="$(cd "$(dirname "$0")" && pwd)/lib/content-rules.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"
T="${TMPBASE}/at-content-rules-selfcheck.$$"
rm -rf "$T"; mkdir -p "$T" || fail "cannot build sandbox"
trap 'rm -rf "$T"' EXIT

# --- 1. Library hygiene: sourcing must not touch the caller's `set -u`, and every function runs in a
#         SUBSHELL so its internal variables (f, tmp, line, ln, tok, name, names_file, mem, resume, rtmp,
#         neutral) never clobber same-named variables already set in the sourcing shell.
FIXTURE="$T/hygiene.md"
printf 'kit shipped at 205731d after review\n' > "$FIXTURE"
# Genuinely FRESH shells (sh -c), not a parenthesised subshell of this already-`set -u` script - a
# subshell inherits its parent's option state regardless of what the sourced library does, which would
# make the "set -u must not turn on" half of this check pass for the wrong reason (vacuously, since the
# parent already has it on).
HYG_OUT="$(sh -c '
  f=PRESERVE_F; line=PRESERVE_LINE; name=PRESERVE_NAME; tmp=PRESERVE_TMP; mem=PRESERVE_MEM; resume=PRESERVE_RESUME
  set -u
  . "$1"
  content_rules_shas "$2" >/dev/null
  content_rules_derivable_counts "$2" >/dev/null
  content_rules_pr_number "$2" >/dev/null
  content_rules_attribution "$2" >/dev/null
  content_rules_resume_duplication "$2" "$2" >/dev/null
  if [ "$f" = PRESERVE_F ] && [ "$line" = PRESERVE_LINE ] && [ "$name" = PRESERVE_NAME ] \
     && [ "$tmp" = PRESERVE_TMP ] && [ "$mem" = PRESERVE_MEM ] && [ "$resume" = PRESERVE_RESUME ]; then
    echo VARS_UNCHANGED
  else
    echo "VARS_CLOBBERED f=$f line=$line name=$name tmp=$tmp mem=$mem resume=$resume"
  fi
  case $- in *u*) echo SET_U_ON ;; *) echo SET_U_OFF ;; esac
' sh "$LIB" "$FIXTURE")"
printf '%s' "$HYG_OUT" | grep -q '^VARS_UNCHANGED$' || fail "sourcing/calling content-rules.sh clobbered a pre-set caller variable: $HYG_OUT"
printf '%s' "$HYG_OUT" | grep -q '^SET_U_ON$' || fail "content-rules.sh disturbed the caller's own set -u state: $HYG_OUT"

# A caller that has NOT set -u must not have it switched ON by sourcing either (the library must add
# nothing, in either direction) - a genuinely fresh shell again, same reason as above.
NOU_OUT="$(sh -c '
  . "$1"
  content_rules_shas "$2" >/dev/null
  case $- in *u*) echo SET_U_ON ;; *) echo SET_U_OFF ;; esac
' sh "$LIB" "$FIXTURE")"
printf '%s' "$NOU_OUT" | grep -q '^SET_U_OFF$' || fail "content-rules.sh turned on set -u for a caller that never asked for it: $NOU_OUT"

# --- 2. Id-shaped tokens: a full UUID and an agent-<hex> id are excluded outright from the sha rule; a
#         bare ambiguous hex token is still reported (library-level: it only emits the raw finding line,
#         the hedged wording lives in memory-content-lint.sh, checked there).
UUID_F="$T/uuid.md"
printf 'session 11111111-2222-4333-8444-5555aaaa5555 reviewed the plan\n' > "$UUID_F"
AGENTID_F="$T/agentid.md"
printf 'agent id agent-a1b2c3d4e5f60718a handled it\nagent-b2c3d4e5f6 agent-c3d4e5f6a7 agent-d4e5f6a7b8\n' > "$AGENTID_F"
BAREHEX_F="$T/barehex.md"
printf 'bare token: session 5c7e9a1b started\n' > "$BAREHEX_F"

( . "$LIB"
  [ -z "$(content_rules_shas "$UUID_F")" ] || { echo FAIL_UUID; exit 1; }
  [ -z "$(content_rules_shas "$AGENTID_F")" ] || { echo FAIL_AGENTID; exit 1; }
  [ -n "$(content_rules_shas "$BAREHEX_F")" ] || { echo FAIL_BAREHEX; exit 1; }
) || fail "id-shaped-token exclusion regressed (see FAIL_* marker above)"

# --- 3. Frontmatter: an id-bearing key (originSessionId:) is blanked; description: stays scannable, so a
#         sha hiding inside it is still caught.
DESC_SHA_F="$T/desc-sha.md"
cat > "$DESC_SHA_F" <<'EOF'
---
name: desc-sha-fixture
description: "fixed via commit e3af7d1, a real find"
metadata:
  originSessionId: 4444bbbb4444
---

Nothing else of note here.
EOF
( . "$LIB"
  out="$(content_rules_shas "$DESC_SHA_F")"
  printf '%s' "$out" | grep -q 'e3af7d1' || { echo FAIL_NO_DESC_SHA; exit 1; }
  printf '%s' "$out" | grep -q '4444bbbb4444' && { echo FAIL_ID_LEAKED; exit 1; }
  exit 0
) || fail "frontmatter id-line-only blanking regressed (see FAIL_* marker above)"

# --- 4. mktemp failure: the affected rule is SKIPPED (empty stdout, no crash) rather than falling back to
#         scanning the raw, un-prepped file. Simulated by shadowing `mktemp` on PATH with one that always
#         fails, inside a fixture whose frontmatter WOULD produce a false positive if the raw file were
#         ever scanned instead (an id line that is itself sha-shaped).
FAKEBIN="$T/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/mktemp" <<'EOF'
#!/usr/bin/env sh
exit 1
EOF
chmod +x "$FAKEBIN/mktemp"
RAW_WOULD_LEAK_F="$T/raw-would-leak.md"
cat > "$RAW_WOULD_LEAK_F" <<'EOF'
---
name: raw-would-leak-fixture
metadata:
  originSessionId: aabbccd1234
---

plain content, no violation
EOF
# Fixture validity: the frontmatter id VALUE alone must be sha-shaped, or a "raw file scanned" regression
# would not actually produce a finding and this case would pass for the wrong reason.
printf '%s' "$(sed -n '4p' "$RAW_WOULD_LEAK_F")" | grep -qE '\b[0-9a-f]{7,40}\b' \
  || fail "fixture invalid: RAW_WOULD_LEAK_F's id line is not sha-shaped"

MT_OUT="$(
  PATH="$FAKEBIN:$PATH"
  . "$LIB"
  command -v mktemp | grep -q "$FAKEBIN/mktemp" || { echo FAIL_SHADOW_NOT_ACTIVE; exit 1; }
  out="$(content_rules_shas "$RAW_WOULD_LEAK_F" 2>"$T/stderr.txt")"
  if [ -n "$out" ]; then echo "FAIL_SCANNED_RAW_FILE: $out"; exit 1; fi
  grep -qi 'mktemp unavailable' "$T/stderr.txt" || echo NOTE_MISSING
  echo OK_SKIPPED
)"
printf '%s' "$MT_OUT" | grep -q '^OK_SKIPPED$' || fail "mktemp-failure path did not skip cleanly: $MT_OUT"
printf '%s' "$MT_OUT" | grep -q 'NOTE_MISSING' && fail "mktemp-failure path skipped silently with no stderr note: $MT_OUT"

# --- 5. content_rules_repo_state: a derivable-count/ahead-behind/sha-as-current-tip claim fires, a
#         lookup-command citation, dated history, a bare count, or a mere mention does not, and an
#         originSessionId-shaped sha hiding in frontmatter stays blanked.
RS_HIT_1="$T/rs-hit-1.md"; printf 'committed (e2cc7d7 09-25), 3 commits unpushed, tree clean.\n' > "$RS_HIT_1"
RS_HIT_2="$T/rs-hit-2.md"
cat > "$RS_HIT_2" <<'EOF'
HEAD: `4837ecc` (local, NOT pushed, branch ahead of origin). Working tree clean.
EOF
RS_HIT_3="$T/rs-hit-3.md"; printf 'local/main is 44 behind and 82 ahead of upstream/main\n' > "$RS_HIT_3"
RS_HIT_4="$T/rs-hit-4.md"; printf '17 files uncommitted since 09-28\n' > "$RS_HIT_4"
RS_HIT_5="$T/rs-hit-5.md"; printf 'State at start: kit, docs repo, app repo all clean, nothing unpushed.\n' > "$RS_HIT_5"
RS_HIT_6="$T/rs-hit-6.md"; printf 'branch ahead of origin by 3\n' > "$RS_HIT_6"
RS_HIT_7="$T/rs-hit-7.md"; printf 'HEAD is at 4837ecc\n' > "$RS_HIT_7"

RS_MISS_8="$T/rs-miss-8.md"
cat > "$RS_MISS_8" <<'EOF'
- Kit HEAD / what is unpushed: `git -C ~/.claude/agent-tiers log --oneline origin/master..HEAD`
EOF
RS_MISS_9="$T/rs-miss-9.md"; printf 'agent-tiers: kit has N unpushed commit(s) here - push before ending\n' > "$RS_MISS_9"
RS_MISS_10="$T/rs-miss-10.md"
cat > "$RS_MISS_10" <<'EOF'
Independent `codex review --uncommitted` found one P2
EOF
RS_MISS_11="$T/rs-miss-11.md"; printf 'Manifest build is queued ahead of the SC-5.2 hook.\n' > "$RS_MISS_11"
RS_MISS_12="$T/rs-miss-12.md"
cat > "$RS_MISS_12" <<'EOF'
LANDED 2026-08-20 - kit commit `63776bd`
EOF
RS_MISS_13="$T/rs-miss-13.md"
cat > "$RS_MISS_13" <<'EOF'
fixed in `abc1234` last week
EOF
RS_MISS_14="$T/rs-miss-14.md"
cat > "$RS_MISS_14" <<'EOF'
Capturing the PID before launch (`1696315`, 09:51:46)
EOF
RS_HIT_16="$T/rs-hit-16.md"; printf 'tip `4837ecc` not pushed yet\n' > "$RS_HIT_16"
RS_MISS_15="$T/rs-miss-15.md"; printf 'works behind a reverse proxy\n' > "$RS_MISS_15"

# The id line below WOULD fire (HEAD + sha) if frontmatter id-blanking were lost, so a silent result
# proves the blanking, not just the absence of a pattern.
RS_FM="$T/rs-frontmatter.md"
cat > "$RS_FM" <<'EOF'
---
name: rs-frontmatter-fixture
metadata:
  headId: HEAD 4837ecc1
---

Nothing else of note here.
EOF

(
  . "$LIB"
  i=1
  for f in "$RS_HIT_1" "$RS_HIT_2" "$RS_HIT_3" "$RS_HIT_4" "$RS_HIT_5" "$RS_HIT_6" "$RS_HIT_7" "$RS_HIT_16"; do
    [ -n "$(content_rules_repo_state "$f")" ] || { echo "FAIL_HIT_$i"; exit 1; }
    i=$((i + 1))
  done
  i=8
  for f in "$RS_MISS_8" "$RS_MISS_9" "$RS_MISS_10" "$RS_MISS_11" "$RS_MISS_12" "$RS_MISS_13" "$RS_MISS_14" "$RS_MISS_15" "$RS_FM"; do
    [ -z "$(content_rules_repo_state "$f")" ] || { echo "FAIL_MISS_$i"; exit 1; }
    i=$((i + 1))
  done
  # Validity: with blanking bypassed (raw grep), the frontmatter id line must match the HEAD-sha shape.
  grep -qE 'HEAD[^A-Za-z0-9]{0,3}[0-9a-f]{7,40}' "$RS_FM" || { echo FAIL_FM_FIXTURE_INVALID; exit 1; }
  exit 0
) || fail "content_rules_repo_state regressed (see FAIL_* marker above)"

echo "OK content-rules: library hygiene holds (no clobbered vars, no set -u side effect), UUID/agent-id tokens excluded, description: shas still caught, mktemp failure skips the rule with a note rather than scanning the raw file, repo-state fires on live claims and stays silent on lookup commands/dated history/mere mentions/frontmatter ids"

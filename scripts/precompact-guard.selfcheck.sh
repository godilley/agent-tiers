#!/usr/bin/env sh
# kit-scope: shared
# Self-check for precompact-guard.sh: kill switch, auto trigger, no-RESUME, `force` escape, an
# actual mtime block, an mtime pass, RESUME's own ledger row excluded from the scan, a missing/
# unreadable ledger (fail-open, skipped under root), an unusable session_id (fail-open, with a
# traversal canary that would actually change the outcome if the guard read it), a ledger produced
# by the REAL authorship-record.sh landing exactly where this guard reads it, and the OLD
# (CLAUDE_CONFIG_DIR-rooted) ledger path genuinely NOT being read any more.
#
# Fully sandboxed: the guard (and, for case 11, the real recorder) run from a THROWAWAY kit copy -
# same shape as authorship-record.selfcheck.sh's own sandbox - so BASE, and therefore the ledger
# path both scripts share, never touches the real kit's .state, and AGENT_TIERS_GUARDS_LOG points at
# a temp file so no fail-open note ever reaches the live guards.log.
set -u
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP precompact-guard: jq absent (guard fails open by design)"; exit 0; }

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
fail() { printf 'FAIL: %s\n' "$1"; rm -rf "$T"; exit 1; }
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/kit/scripts"
cp "$SRC_DIR/precompact-guard.sh" "$T/kit/scripts/" || fail "cannot copy guard into sandbox"
cp "$SRC_DIR/authorship-record.sh" "$T/kit/scripts/" 2>/dev/null || true   # only case 11 needs it
H="$T/kit/scripts/precompact-guard.sh"
AR="$T/kit/scripts/authorship-record.sh"
LEDGER_DIR="$T/kit/.state/authorship"     # BASE-relative: exactly where authorship-record.sh writes
export AGENT_TIERS_GUARDS_LOG="$T/guards.log"   # never the real/live guards.log

export CLAUDE_CONFIG_DIR="$T/cfg"          # kill switch + the "old wrong path" fixture live here
PROJ="$T/proj"
mkdir -p "$PROJ" "$LEDGER_DIR"

# `touch -d` is GNU-only - stamp mtimes portably via `touch -t` (same helper shape as
# resume-inject.selfcheck.sh, this kit's other mtime-comparing hook).
touch_ago() { # $1=path $2=minutes-ago
  ts="$(date -v-"$2"M +%Y%m%d%H%M 2>/dev/null || date -d "$2 minutes ago" +%Y%m%d%H%M)"
  [ -n "$ts" ] || fail "touch_ago: no usable date(1)"
  touch -t "$ts" "$1" || fail "touch_ago: touch -t $ts failed"
}
# ISO-8601-with-numeric-offset, same format authorship-record.sh stamps its own rows with, built
# from an arbitrary epoch (portable GNU/BSD date, same fallback shape used throughout this kit).
iso_from_epoch() { # $1=epoch seconds
  date -d "@$1" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -j -f '%s' "$1" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null
}

run() { # $1=session_id $2=trigger $3=custom_instructions
  ( cd "$PROJ" && printf '%s' "$(jq -cn --arg s "$1" --arg tr "$2" --arg ci "$3" \
      '{session_id:$s, trigger:$tr, custom_instructions:$ci}')" \
      | CLAUDE_PROJECT_DIR="$PROJ" sh "$H" 2>"$T/stderr" )
  echo "$?"
}

S1=session-aaaa
RESUME="$PROJ/RESUME_SESSION.md"

# 1. Kill switch: even a real block-shaped setup passes when the sentinel exists.
echo "old resume" > "$RESUME"; touch_ago "$RESUME" 30
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" MAIN FLAG "$PROJ/src/x.js" > "$LEDGER_DIR/$S1.tsv"
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off"
touch "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/precompact-guard"
rc="$(run "$S1" manual "")"
[ "$rc" = 0 ] || fail "kill switch must exit 0 even with a would-block setup"
rm -f "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/precompact-guard"

# 2. Auto trigger: never blocks, regardless of ledger state.
rc="$(run "$S1" auto "")"
[ "$rc" = 0 ] || fail "trigger=auto must always pass"

# 3. No RESUME_SESSION.md at all: pass.
rm -f "$RESUME"
rc="$(run "$S1" manual "")"
[ "$rc" = 0 ] || fail "a project with no RESUME_SESSION.md must pass"
echo "old resume" > "$RESUME"; touch_ago "$RESUME" 30

# 4. force escape: passes even though the ledger is newer than RESUME.
rc="$(run "$S1" manual "force skip the check")"
[ "$rc" = 0 ] || fail "custom_instructions starting with 'force' must pass"

# 4b. force escape is case-insensitive and tolerates leading whitespace.
rc="$(run "$S1" manual "Force skip the check")"
[ "$rc" = 0 ] || fail "'Force' (capitalised) must pass, same as 'force'"
rc="$(run "$S1" manual "  FORCE skip the check")"
[ "$rc" = 0 ] || fail "leading whitespace before 'FORCE' must still pass"

# 4c. force is STILL a prefix match: the word appearing mid-string must NOT pass.
rc="$(run "$S1" manual "please force it")"
[ "$rc" = 2 ] || fail "'force' appearing mid-string (not as the first word) must still block (got rc=$rc)"

# 5. THE REAL BLOCK: a NON-RESUME ledger line is newer than RESUME_SESSION.md's mtime.
rc="$(run "$S1" manual "")"
[ "$rc" = 2 ] || fail "a stale RESUME_SESSION.md against a fresher in-project authorship line must block (got rc=$rc)"
grep -q '/compact force' "$T/stderr" || fail "block stderr must name the /compact force escape"
grep -q 'off/precompact-guard' "$T/stderr" || fail "block stderr must name the kill-switch path"

# 6. THE PASS: touch RESUME_SESSION.md fresh - now it postdates the ledger line.
touch "$RESUME"
rc="$(run "$S1" manual "")"
[ "$rc" = 0 ] || fail "a RESUME_SESSION.md newer than the ledger line must pass"
touch_ago "$RESUME" 30

# 6b. RESUME's OWN row is excluded from the scan: a ledger whose ONLY row is for RESUME_SESSION.md
#     itself, stamped 1-2s AFTER RESUME's own mtime (the exact race the fix targets - the recorder's
#     `date` call runs strictly after the write it is recording), must still PASS.
S7=session-gggg
touch_ago "$RESUME" 1
resume_epoch="$(date -r "$RESUME" +%s 2>/dev/null || stat -c %Y "$RESUME" 2>/dev/null)"
[ -n "$resume_epoch" ] || fail "fixture invalid: could not read RESUME's own mtime"
row_ts="$(iso_from_epoch "$((resume_epoch + 2))")"
[ -n "$row_ts" ] || fail "fixture invalid: could not compute a +2s timestamp for the RESUME row"
printf '%s\t%s\t%s\t%s\n' "$row_ts" MAIN ok "$RESUME" > "$LEDGER_DIR/$S7.tsv"
rc="$(run "$S7" manual "")"
[ "$rc" = 0 ] || fail "a ledger whose only row is RESUME's own, stamped just after RESUME's mtime, must PASS - RESUME's own row must be excluded from the scan (got rc=$rc)"
touch_ago "$RESUME" 30

# 6c. Only a WORKER row (in-project, including under a .claude/worktrees/agent-<id>/ path) is newer
#     than RESUME: must PASS. Compaction only ever discards the Lead's conversation, and a subagent's
#     edits stay on disk with its return arriving after the compact - so a background worker must
#     never be able to block the Lead's own /compact.
S8=session-hhhh
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" worker FLAG \
  "$PROJ/.claude/worktrees/agent-x/src/y.js" > "$LEDGER_DIR/$S8.tsv"
rc="$(run "$S8" manual "")"
[ "$rc" = 0 ] || fail "a newer WORKER row (even under .claude/worktrees/agent-x/) must not block - only MAIN rows count (got rc=$rc)"

# 6d. A MAIN row newer than RESUME still blocks, unchanged.
S9=session-iiii
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" MAIN FLAG "$PROJ/src/z.js" > "$LEDGER_DIR/$S9.tsv"
rc="$(run "$S9" manual "")"
[ "$rc" = 2 ] || fail "a newer MAIN row must still block (got rc=$rc)"

# 6e. A newer WORKER row plus an OLDER-than-RESUME MAIN row: the worker row must not resurrect a
#     block that the (stale, but older) MAIN row alone would not cause.
S10=session-jjjj
old_ts="$(iso_from_epoch "$(($(date +%s) - 3600))")"
printf '%s\t%s\t%s\t%s\n' "$old_ts" MAIN FLAG "$PROJ/src/old.js" > "$LEDGER_DIR/$S10.tsv"
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" worker FLAG \
  "$PROJ/.claude/worktrees/agent-x/src/y.js" >> "$LEDGER_DIR/$S10.tsv"
rc="$(run "$S10" manual "")"
[ "$rc" = 0 ] || fail "a newer worker row plus an older-than-RESUME MAIN row must PASS (got rc=$rc)"

# 6f. A newer MAIN row AND a newer WORKER row present together: must still BLOCK on the MAIN row.
S11=session-kkkk
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" MAIN FLAG "$PROJ/src/z2.js" > "$LEDGER_DIR/$S11.tsv"
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" worker FLAG \
  "$PROJ/.claude/worktrees/agent-x/src/y2.js" >> "$LEDGER_DIR/$S11.tsv"
rc="$(run "$S11" manual "")"
[ "$rc" = 2 ] || fail "a newer MAIN row plus a newer worker row must still BLOCK (got rc=$rc)"

# 7. A ledger line OUTSIDE the project must not count as evidence of an in-project authorship.
S2=session-bbbb
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" MAIN FLAG "/somewhere/else/y.js" > "$LEDGER_DIR/$S2.tsv"
rc="$(run "$S2" manual "")"
[ "$rc" = 0 ] || fail "an out-of-project ledger line must not trigger a block"

# 8. Missing ledger for this session: fail open.
S3=session-cccc
rc="$(run "$S3" manual "")"
[ "$rc" = 0 ] || fail "a missing authorship ledger must fail open (pass)"

# 9. Unreadable ledger: fail open, not a crash. Skipped under root - chmod 000 does not restrict a
#    root reader, so this assertion is meaningless (and would false-FAIL) in a root CI container.
if [ "$(id -u 2>/dev/null || echo 1)" = 0 ]; then
  # Not "SKIP...": the CI matrix (.github/workflows/selfcheck.yml) treats any line starting with
  # that word as a hard FAIL, right for a real gap but wrong for "this run happens to be root" -
  # same convention notify.selfcheck.sh already uses for its own platform-structural skips.
  echo "note: skipped case 9: running as root, chmod 000 does not restrict root reads"
else
  S4=session-dddd
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" MAIN FLAG "$PROJ/z.js" > "$LEDGER_DIR/$S4.tsv"
  chmod 000 "$LEDGER_DIR/$S4.tsv"
  rc="$(run "$S4" manual "")"
  chmod 644 "$LEDGER_DIR/$S4.tsv"
  [ "$rc" = 0 ] || fail "an unreadable ledger must fail open (pass)"
fi

# 10. Unusable/traversal session_id: fail open, and never reads outside the ledger dir. The canary is
#     a REAL, well-formed ledger row (in-project path, timestamped newer than RESUME) - not an inert
#     string - so if session-id validation were ever removed and the traversal path got read as the
#     ledger, this assertion would actually FLIP to a block (rc=2) instead of passing vacuously.
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/etc"
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" MAIN FLAG "$PROJ/canary-must-not-be-read.js" \
  > "$CLAUDE_CONFIG_DIR/agent-tiers/etc/secret.tsv"
for bad in "../../../cfg/agent-tiers/etc/secret" "." ".." "a/b" ""; do
  rc="$(run "$bad" manual "")"
  [ "$rc" = 0 ] || fail "unusable session_id '$bad' must fail open, not block or crash (rc=$rc; a real block here would mean the traversal canary got read)"
done

# 11. The ledger PRODUCED BY THE REAL authorship-record.sh (not hand-written) lands exactly where
#     this guard reads it - proves the two scripts' path resolution actually agrees, not just that a
#     hand-placed fixture matches this test's own assumption about the path.
if [ -f "$AR" ]; then
  S5=session-eeee
  AR_PAYLOAD="$(jq -cn --arg s "$S5" --arg p "$PROJ/src/real.js" \
    '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$p, new_string:"x", old_string:"y"}}')"
  printf '%s' "$AR_PAYLOAD" | sh "$AR" >/dev/null 2>&1
  [ -f "$LEDGER_DIR/$S5.tsv" ] || fail "fixture invalid: the real authorship-record.sh did not write to $LEDGER_DIR - the two scripts' BASE resolution has diverged again"
  rc="$(run "$S5" manual "")"
  [ "$rc" = 2 ] || fail "a ledger row written by the REAL authorship-record.sh must be read by this guard from the same BASE-relative path (got rc=$rc)"
else
  echo "SKIP case 11: authorship-record.sh not present in this kit copy"
fi

# 11b. Prove the OLD (CLAUDE_CONFIG_DIR-rooted) path is genuinely NOT read any more: a ledger planted
#      only there, for a session with no BASE-relative ledger at all, must not block.
S6=session-ffff
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state/authorship"
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" MAIN FLAG "$PROJ/src/x.js" \
  > "$CLAUDE_CONFIG_DIR/agent-tiers/.state/authorship/$S6.tsv"
rc="$(run "$S6" manual "")"
[ "$rc" = 0 ] || fail "a ledger at the OLD CLAUDE_CONFIG_DIR-rooted path must NOT be read (rc=$rc)"

# 12. --probe: unsupported when jq is missing.
NOJQ="$T/nojq"; mkdir -p "$NOJQ"
for t in sh; do ln -sf "$(command -v "$t")" "$NOJQ/$t"; done
probe_out="$(printf '%s' | PATH="$NOJQ" sh "$H" --probe 2>&1)"; probe_rc=$?
[ "$probe_rc" = 3 ] || fail "--probe with no jq on PATH should exit 3 (got rc=$probe_rc: $probe_out)"
[ -n "$probe_out" ] || fail "--probe unsupported (no jq) must print a one-line reason"

# 12b. --probe: unsupported when jq is present but authorship-record is not wired anywhere.
probe_out="$(printf '%s' | sh "$H" --probe 2>&1)"; probe_rc=$?
[ "$probe_rc" = 3 ] || fail "--probe with jq present but authorship-record unwired should exit 3 (got rc=$probe_rc: $probe_out)"
case "$probe_out" in *authorship-record*) ;; *) fail "--probe unsupported reason should name authorship-record (got: $probe_out)" ;; esac

# 12c. --probe: supported when authorship-record is in this same install's KIT_PROBE_WITH.
probe_out="$(printf '%s' | KIT_PROBE_WITH="precompact-guard authorship-record" sh "$H" --probe 2>&1)"; probe_rc=$?
[ "$probe_rc" = 0 ] || fail "--probe with authorship-record in KIT_PROBE_WITH should exit 0 (got rc=$probe_rc: $probe_out)"
[ -z "$probe_out" ] || fail "--probe supported must print nothing (got: $probe_out)"

# 12d. --probe: supported when authorship-record's command already appears in KIT_PROBE_SETTINGS.
FAKESET="$T/fake-settings.json"
printf '{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"sh \\"/x/scripts/authorship-record.sh\\""}]}]}}' > "$FAKESET"
probe_out="$(printf '%s' | KIT_PROBE_SETTINGS="$FAKESET" sh "$H" --probe 2>&1)"; probe_rc=$?
[ "$probe_rc" = 0 ] || fail "--probe with authorship-record already in settings.json should exit 0 (got rc=$probe_rc: $probe_out)"

# 12d-bis. --probe: UNSUPPORTED even though authorship-record's command already appears in
#          KIT_PROBE_SETTINGS, when this SAME install also carries --without-authorship-record -
#          a plain settings.json grep cannot see that removal coming (it has not happened yet at
#          probe time), so KIT_PROBE_WITHOUT is the only signal that catches it.
probe_out="$(printf '%s' | KIT_PROBE_SETTINGS="$FAKESET" KIT_PROBE_WITHOUT="authorship-record" sh "$H" --probe 2>&1)"; probe_rc=$?
[ "$probe_rc" = 3 ] || fail "--probe must be UNSUPPORTED when authorship-record is being removed in this same run, even if it is still in settings.json (got rc=$probe_rc: $probe_out)"
case "$probe_out" in *authorship-record*) ;; *) fail "the KIT_PROBE_WITHOUT refusal reason should name authorship-record (got: $probe_out)" ;; esac

# 12e. --probe reads no stdin and has no side effects: a would-block setup + kill switch present
#      must not matter, and it must never write to the ledger dir.
before_files="$(find "$LEDGER_DIR" -type f | sort)"
printf 'not read anyway' | KIT_PROBE_WITH="authorship-record" sh "$H" --probe >/dev/null 2>&1
after_files="$(find "$LEDGER_DIR" -type f | sort)"
[ "$before_files" = "$after_files" ] || fail "--probe must not write to the ledger dir"

echo "OK precompact-guard: kill switch, manual-only, force escape, RESUME-vs-authorship mtime block/pass (RESUME's own row excluded), the BASE-relative ledger path shared with the real recorder, and every tooling gap failing open all hold"

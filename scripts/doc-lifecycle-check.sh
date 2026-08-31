#!/usr/bin/env sh
# kit-scope: shared
# doc-lifecycle-check.sh - advisory-only scan for the doc-lifecycle seam (docs/_local/2026-08-29
# doc-skill-lifecycle plan, Part 3.2; the ritual it checks against lives in the `doc-lifecycle` skill).
#
# Two passes, gated differently:
#   1. Private-notes pass - only if the resolved notes dir exists: a dated (YYYY-MM-DD-*.md) doc
#      directly inside it with no STATUS line; a terminal-status (SHIPPED/SUPERSEDED/RECORD) doc
#      still outside archive/; a LIVE doc whose mtime exceeds stale_days. Scope is exactly the
#      dated-filename pattern - a named state file (e.g. state-ledger.md) is out of scope by
#      construction, not a violation.
#   2. Tracked-docs noise pass - ALWAYS runs, even with no notes dir at all: flags tracked markdown
#      outside the notes dir that looks plan/investigation-shaped rather than reference
#      documentation. This is evidence for the user's own disposition call, never an instruction -
#      this script contains no code path that writes, deletes, or untracks anything, anywhere.
#
# Always exits 0 - advisory only, never a guard, in either direction.
#
# Two output modes:
#   (default)   full, uncapped finding list - for standalone use and `/agent-tiers:doctor` step 4e.
#   --summary   a count line plus at most 5 example names per pass, each charset/length-filtered -
#               the ONLY form resume-inject.sh's block E (3.4) may embed in a SessionStart
#               additionalContext payload, per that file's own "a project-controlled filename lands
#               verbatim in model context" rule for its globbed blocks.
#
# Runs under POSIX sh (install-flat.sh invokes every wired selfcheck as `sh`, not `bash`) - no
# arrays, no `local`, no `[[ ]]`.
#
# Self-check: doc-lifecycle-check.selfcheck.sh
set -u

SUMMARY=0
[ "${1:-}" = "--summary" ] && SUMMARY=1

# A bail-out below is a machine/environment hiccup (git absent, dubious ownership, a stale
# worktree pointer), never a finding - it must not become a PERMANENT SessionStart advisory just
# because block E saw non-empty output (opus reviewer, R2). Silent in --summary mode; still
# printed in full/standalone mode so a human running this by hand can see why nothing ran.
bail() { [ "$SUMMARY" = 1 ] || echo "doc-lifecycle: $1"; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || bail "not in a git repo"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT" ] || bail "cannot resolve repo root"
cd "$ROOT" 2>/dev/null || bail "cannot cd to repo root $ROOT"

# Same resolution as notes-sync.sh: git-config first, literal default second. archive_subdir/
# stale_days share the notes-sync.* namespace as siblings of dir/ref/push (kit-config.md 3.1),
# never a separate namespace.
DIR="$(git config --get notes-sync.dir 2>/dev/null || true)";        DIR="${DIR:-docs/_local}"
ARCHIVE_SUBDIR="$(git config --get notes-sync.archive-subdir 2>/dev/null || true)"
ARCHIVE_SUBDIR="${ARCHIVE_SUBDIR:-archive}"
STALE_DAYS="$(git config --get notes-sync.stale-days 2>/dev/null || true)"
case "$STALE_DAYS" in ''|*[!0-9]*) STALE_DAYS=21 ;; esac
DIR="${DIR%/}"

# A name is only ever surfaced charset+length-filtered - mirrors resume-inject.sh's globbed-name
# discipline (a project-shipped filename lands verbatim in model context).
safe_name() { awk 'length($0) <= 64 && $0 !~ /[^A-Za-z0-9_.\/-]/'; }

cap5() {
  # stdin: one name per line -> "a, b, c" of at most 5 safe names, or empty
  safe_name | head -n 5 | tr '\n' ',' | sed 's/,$//; s/,/, /g'
}

report_pass() {
  # $1 = finding label (plural-ready noun phrase)   $2 = count   $3 = newline-separated paths
  if [ "$SUMMARY" = 1 ]; then
    ex="$(printf '%s\n' "$3" | cap5)"
    printf 'doc-lifecycle: %s %s(s)%s\n' "$2" "$1" "${ex:+ - e.g. $ex}"
  else
    printf 'doc-lifecycle: %s %s(s)\n' "$2" "$1"
    if [ "$2" -gt 0 ] 2>/dev/null; then
      # Full mode is otherwise UNCAPPED by design (standalone/doctor get the real list) - but a
      # project-controlled filename still lands verbatim in whatever read this output, so a
      # pathological repo (thousands of matching names) gets a bound too, just a much wider one
      # than --summary's 5.
      printf '%s\n' "$3" | sed 's/^/  /' | head -n 40
      [ "$2" -gt 40 ] && printf '  ... and %d more (truncated)\n' "$(($2 - 40))"
    fi
  fi
}

# --- pass 1: private notes (only if the resolved dir exists) --------------------------------------
NO_STATUS="" NOT_ARCHIVED="" STALE="" TRACKED_INSIDE=""
n_no_status=0 n_not_archived=0 n_stale=0 n_tracked_inside=0

if [ -d "$DIR" ]; then
  # The exclude seam itself can be broken (never ran `setup`, or a file was tracked before the
  # seam existed) - pass 2 explicitly skips everything under $DIR on the assumption pass 1 covers
  # it, so this is the ONE check that actually verifies that assumption. Highest-value finding
  # this script can produce: a tracked file inside the "private" notes dir at all (opus reviewer, R2).
  TRACKED_INSIDE="$(git ls-files -- "$DIR" 2>/dev/null)"
  [ -n "$TRACKED_INSIDE" ] && n_tracked_inside=$(printf '%s\n' "$TRACKED_INSIDE" | grep -c .)

  for f in "$DIR"/[0-9]*-*.md; do
    [ -f "$f" ] || continue
    first_line="$(head -n1 "$f" 2>/dev/null || true)"
    case "$first_line" in
      STATUS:*)
        # A spacing near-miss (STATUS:LIVE, STATUS:  LIVE) must still be READ, not vanish from
        # every check by falling through `${first_line#STATUS: }`'s single-space assumption.
        status="$(printf '%s' "$first_line" | sed 's/^STATUS:[[:space:]]*//')"
        case "$status" in
          SHIPPED*|SUPERSEDED*|RECORD*)
            n_not_archived=$((n_not_archived + 1))
            NOT_ARCHIVED="${NOT_ARCHIVED:+$NOT_ARCHIVED
}$f"
            ;;
          LIVE*)
            if [ -n "$(find "$f" -mtime "+$STALE_DAYS" -print -quit 2>/dev/null)" ]; then
              n_stale=$((n_stale + 1))
              STALE="${STALE:+$STALE
}$f"
            fi
            ;;
        esac
        ;;
      *)
        n_no_status=$((n_no_status + 1))
        NO_STATUS="${NO_STATUS:+$NO_STATUS
}$f"
        ;;
    esac
  done
fi

if [ -d "$DIR" ]; then
  report_pass "file TRACKED by git inside the private notes dir - the exclude seam is broken" "$n_tracked_inside" "$TRACKED_INSIDE"
  report_pass "dated doc with no STATUS line" "$n_no_status" "$NO_STATUS"
  report_pass "terminal-status doc still outside $ARCHIVE_SUBDIR/" "$n_not_archived" "$NOT_ARCHIVED"
  report_pass "LIVE doc untouched past ${STALE_DAYS}d (advisory only)" "$n_stale" "$STALE"
else
  printf 'doc-lifecycle: no notes dir at %s yet - private-notes pass skipped (not a violation)\n' "$DIR"
fi

# --- pass 2: tracked-docs noise (always runs, even with no notes dir) ------------------------------
TRACKED="" n_tracked=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in "$DIR"/*) continue ;; esac   # already covered by pass 1's own scope
  base="${p##*/}"
  hit=0
  case "$base" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) hit=1 ;; esac
  if [ "$hit" = 0 ]; then
    first_line="$(head -n1 "$p" 2>/dev/null || true)"
    lower="$(printf '%s' "$first_line" | tr 'A-Z' 'a-z')"
    case "$lower" in *status:*) hit=1 ;; esac
  fi
  if [ "$hit" = 0 ]; then
    case "$p" in
      plans/*|*/plans/*|investigations/*|*/investigations/*|reviews/*|*/reviews/*) hit=1 ;;
    esac
  fi
  if [ "$hit" = 1 ]; then
    n_tracked=$((n_tracked + 1))
    TRACKED="${TRACKED:+$TRACKED
}$p"
  fi
done <<TRACKED_EOF
$(git ls-files '*.md' 2>/dev/null | head -n 500)
TRACKED_EOF
# Capped at 500 tracked .md paths scanned: this runs from a live global SessionStart hook (block E)
# with its own timeout, and each iteration forks a few processes - a monorepo with thousands of
# tracked markdown files must not be able to time out the ENTIRE resume-inject.sh injection
# (stamp/manifest/RESUME handoff) over a pass whose own findings are advisory-only anyway.

report_pass "tracked working-doc-shaped file outside $DIR/" "$n_tracked" "$TRACKED"
if [ "$n_tracked" -gt 0 ]; then
  printf 'doc-lifecycle: tracked, looks like a closed working doc - this is a disposition decision for the user, never an automated untrack. Do not run `notes-sync.sh migrate` or `git rm --cached` off the back of this report.\n'
fi

exit 0

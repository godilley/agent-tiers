#!/usr/bin/env sh
# kit-scope: shared
# Self-check for portable-citation-advisory.sh.
#
# Case 1: a skill file citing an untracked-but-existing path is reported.
# Case 2: the same citation with an exempting phrase on the line is not.
# Case 3: a tracked path is not reported.
# Case 4: a non-portable file (a plain docs/notes.md) is not examined at all.
# Case 5: a portable-shaped path that is not inside ANY git repo exits quietly, no breadcrumb.
# Case 6: within one session, a second out-of-repo write logs no second breadcrumb (rate-limited).
# Case 7: the kill switch is honoured before anything else.
#
# State sandboxing: the guard is copied into a temp scripts/ dir so KIT_ROOT-derived kill-switch and
# rate-limit-marker resolution never touch the real kit's .state/. CLAUDE_CONFIG_DIR and
# AGENT_TIERS_GUARDS_LOG both point into the same mktemp -d. The fixture repo is its own `git init`
# repo, never the real repo.
set -u

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
SRC="$SCRIPTS/portable-citation-advisory.sh"
[ -f "$SRC" ] || { echo "FAIL: portable-citation-advisory.sh not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git absent (guard fails open by design)"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

KIT="$T/kit"
mkdir -p "$KIT/scripts" "$KIT/.state"
cp "$SRC" "$KIT/scripts/"
GUARD="$KIT/scripts/portable-citation-advisory.sh"
LOG="$T/guards.log"

REPO="$T/repo"
mkdir -p "$REPO/.claude/skills/demo"
(
  cd "$REPO" || exit 1
  git init -q
  git config user.email a@b.c
  git config user.name test
  printf 'tracked\n' > tracked.md
  git add tracked.md
  git commit -qm init
) >/dev/null 2>&1

mkdir -p "$REPO/docs/_local"
printf 'untracked\n' > "$REPO/docs/_local/plan.md"   # exists on disk, never committed

run() {  # run <file-path> [session-id]
  jq -n --arg p "$1" --arg s "${2:-sess1}" '{tool_name: "Write", tool_input: {file_path: $p}, session_id: $s}' \
    | AGENT_TIERS_GUARDS_LOG="$LOG" sh "$GUARD" 2>/dev/null
}
ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

# --- case 1: an untracked-but-existing citation in a portable skill file is reported ----------------
SKILL="$REPO/.claude/skills/demo/SKILL.md"
cat > "$SKILL" <<'EOF'
# Demo skill

See `docs/_local/plan.md` for the detail.
EOF
out="$(run "$SKILL")"
c="$(ctx "$out")"
[ -n "$c" ] || fail "case 1: an untracked cited path was not flagged (got: ${out:-<silence>})"
printf '%s' "$c" | grep -q 'docs/_local/plan.md' || fail "case 1: the finding does not name the offending path"

# --- case 2: the same citation with an exempting phrase on the line is not reported ------------------
cat > "$SKILL" <<'EOF'
# Demo skill

See `docs/_local/plan.md` for the detail (this is a kit-local doc, not bundled to recipients).
EOF
out="$(run "$SKILL")"
[ -z "$(ctx "$out")" ] || fail "case 2: an exempted line was still flagged: $out"

# --- case 3: a tracked path is not reported -----------------------------------------------------------
cat > "$SKILL" <<'EOF'
# Demo skill

See `tracked.md` for the detail.
EOF
out="$(run "$SKILL")"
[ -z "$(ctx "$out")" ] || fail "case 3: a tracked path was flagged: $out"

# --- case 4: a non-portable file is never examined ----------------------------------------------------
NOTES="$REPO/docs/notes.md"
mkdir -p "$(dirname "$NOTES")"
cat > "$NOTES" <<'EOF'
See `docs/_local/plan.md` for the detail.
EOF
out="$(run "$NOTES")"
[ -z "$out" ] || fail "case 4: a non-portable file was examined: $out"

# --- case 5: a portable-shaped path outside ANY git repo exits quietly -------------------------------
OUTSIDE="$T/outside/.claude/skills/demo/SKILL.md"
mkdir -p "$(dirname "$OUTSIDE")"
cat > "$OUTSIDE" <<'EOF'
# Demo skill

See `docs/_local/plan.md` for the detail.
EOF
: > "$LOG"
out="$(run "$OUTSIDE" sessA)"
[ -z "$out" ] || fail "case 5: an out-of-repo portable artifact was examined instead of exiting quietly: $out"
grep -aq 'fail-open:.*not inside a git repo' "$LOG" 2>/dev/null \
  || fail "case 5: the out-of-repo fail-open left no breadcrumb at all"

# --- case 6: a second out-of-repo write in the SAME session logs no second breadcrumb ----------------
BEFORE="$(grep -ac 'fail-open:.*not inside a git repo' "$LOG" 2>/dev/null || echo 0)"
out="$(run "$OUTSIDE" sessA)"
AFTER="$(grep -ac 'fail-open:.*not inside a git repo' "$LOG" 2>/dev/null || echo 0)"
[ -z "$out" ] || fail "case 6: a repeat out-of-repo write was examined: $out"
[ "$AFTER" = "$BEFORE" ] || fail "case 6: a second out-of-repo write in the same session logged another breadcrumb ($BEFORE -> $AFTER)"

# --- case 7: the kill switch is honoured before anything else ----------------------------------------
mkdir -p "$KIT/.state/off"
touch "$KIT/.state/off/portable-citation-advisory"
cat > "$SKILL" <<'EOF'
# Demo skill

See `docs/_local/plan.md` for the detail.
EOF
out="$(run "$SKILL")"
[ -z "$out" ] || fail "case 7: the kill switch did not silence the guard: $out"
rm -f "$KIT/.state/off/portable-citation-advisory"

if [ "$fails" -eq 0 ]; then
  echo "PASS portable-citation-advisory: 7/7 cases"
  exit 0
fi
printf 'portable-citation-advisory: %s case(s) failed\n' "$fails"
exit 1

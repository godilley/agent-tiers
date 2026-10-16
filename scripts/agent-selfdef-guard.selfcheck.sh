#!/usr/bin/env sh
# kit-scope: shared
# Self-check for agent-selfdef-guard.sh.
#
# Cases: a sub-agent writing its OWN definition (direct path, through a symlink standing in for the
# flat install, and through a REAL-FILE flat copy - install-flat.sh's cp -R fallback where symlinks
# are unsupported) is denied; a sub-agent writing a DIFFERENT tier's definition, or any other file, is
# allowed; a project-scope definition at <repo>/.claude/agents/<type>.md is denied the same way; the
# Lead (no caller agent) writing any definition file is allowed; the kill switch and every fail-open
# path (missing agents dir, stale library) are honoured, each with a breadcrumb.
#
# State sandboxing is mandatory: CLAUDE_CONFIG_DIR, AGENT_TIERS_GUARDS_LOG and AGENT_TIERS_KIT_ROOT all
# point into one mktemp -d - this never reads or writes the real kit's agents/ directory. The kill
# switch is resolved from the guard's own copied location (KIT_ROOT), so the fixture kit tree is what
# gets the .state/off/ marker, never the real kit's.
set -u

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD="$SCRIPTS/agent-selfdef-guard.sh"
[ -f "$GUARD" ] || { echo "FAIL: agent-selfdef-guard.sh not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

# --- fixture kit tree: agents/ with two tiers, plus a flat-install-style symlink -------------------
KIT="$T/kit"
mkdir -p "$KIT/agents" "$KIT/.state" "$KIT/scripts" "$KIT/install" "$T/managed"
cp "$GUARD" "$KIT/scripts/"
# kit-gate.sh enforces the kit-root kill switch and runs from this fixture kit: managed dir pointed at an
# empty temp dir, every kit-gate input cleared so the user's own options cannot stand the guard down.
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$SCRIPTS/kit-gate.sh" > "$KIT/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$KIT/scripts/kit-gate.sh" || { echo "FAIL: _kg_managed not rewritten"; exit 1; }
cp "$SCRIPTS/../install/options.tsv" "$KIT/install/"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
cp "$SCRIPTS/guard-cmdpos.sh" "$KIT/scripts/"
printf '# worker definition\n' > "$KIT/agents/worker.md"
printf '# advisor definition\n' > "$KIT/agents/advisor.md"

FLAT="$T/flat"
mkdir -p "$FLAT/agents"
ln -s "$KIT/agents/worker.md" "$FLAT/agents/worker.md"

# A REAL-FILE flat copy: install-flat.sh's link_or_copy falls back to `cp -R` on a host without
# symlink support, so this is NOT the same real file as the kit copy - only readlink -f resolution
# would miss it; the basename-matched candidate path is what catches this.
FLATCOPY="$T/flatcopy"
mkdir -p "$FLATCOPY/agents"
cp "$KIT/agents/worker.md" "$FLATCOPY/agents/worker.md"

# A project-scope definition, never a candidate under the old (agents-dir-only) design.
PROJECT="$T/project"
mkdir -p "$PROJECT/.claude/agents"
printf '# project-scope worker definition\n' > "$PROJECT/.claude/agents/worker.md"

CDIR="$T/.claude"
mkdir -p "$CDIR"
LOG="$T/guards.log"
G="$KIT/scripts/agent-selfdef-guard.sh"

run() {  # run <payload-json> [config_dir] [project_dir]
  printf '%s' "$1" \
    | CLAUDE_CONFIG_DIR="${2:-$CDIR}" CLAUDE_PROJECT_DIR="${3:-}" \
      AGENT_TIERS_GUARDS_LOG="$LOG" AGENT_TIERS_KIT_ROOT="$KIT" sh "$G" 2>/dev/null
}
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }

payload() {  # payload <file_path> [agent_type]
  jq -n --arg p "$1" --arg a "${2:-}" \
    '{tool_name: "Write", tool_input: {file_path: $p}, session_id: "sess1"}
     + (if $a == "" then {} else {agent_type: $a} end) + (if $a == "" or $a == "main" or $a == "MAIN" then {} else {agent_id: "a0test"} end)'
}

# --- case 1: the Lead (no agent_type) writing a definition file -> allow ---------------------------
out="$(run "$(payload "$KIT/agents/worker.md")")"
[ -z "$out" ] || fail "case 1: the Lead was denied writing a definition file: $out"

# --- case 2: a sub-agent writing its OWN definition (direct path) -> deny ---------------------------
out="$(run "$(payload "$KIT/agents/worker.md" worker)")"
[ "$(decision "$out")" = "deny" ] || fail "case 2: worker writing its own definition was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -q 'own definition' || fail "case 2: the denial does not name the rule"

# --- case 3: a sub-agent writing its own definition THROUGH the flat-install symlink -> deny --------
# Proves readlink -f resolution: the symlink path is not textually equal to the kit path, only the
# same file after resolution.
out="$(run "$(payload "$FLAT/agents/worker.md" worker)")"
[ "$(decision "$out")" = "deny" ] || fail "case 3: worker writing its own definition through the symlink was not denied (got: ${out:-<silence>})"

# --- case 4: a sub-agent writing a DIFFERENT tier's definition -> allow ------------------------------
# Out of scope for this rule; the reason text must never claim otherwise (there is none, since a
# non-denial prints nothing).
out="$(run "$(payload "$KIT/agents/advisor.md" worker)")"
[ -z "$out" ] || fail "case 4: worker writing advisor's definition was denied (out of scope for this rule): $out"

# --- case 5: a sub-agent writing any other file -> allow --------------------------------------------
out="$(run "$(payload "$T/notes.md" worker)")"
[ -z "$out" ] || fail "case 5: worker writing an unrelated file was denied: $out"

# --- case 6: a sub-agent writing its own definition through a REAL-FILE flat copy -> deny -------------
out="$(run "$(payload "$FLATCOPY/agents/worker.md" worker)" "$FLATCOPY")"
[ "$(decision "$out")" = "deny" ] || fail "case 6: worker writing its own definition through a real-file flat copy was not denied (got: ${out:-<silence>})"

# --- case 7: a sub-agent writing its own PROJECT-SCOPE definition -> deny -----------------------------
out="$(run "$(payload "$PROJECT/.claude/agents/worker.md" worker)" "$CDIR" "$PROJECT")"
[ "$(decision "$out")" = "deny" ] || fail "case 7: worker writing its own project-scope definition was not denied (got: ${out:-<silence>})"

# --- case 8: a DIFFERENT tier's project-scope definition -> allow -------------------------------------
mkdir -p "$PROJECT/.claude/agents"
printf '# project-scope advisor definition\n' > "$PROJECT/.claude/agents/advisor.md"
out="$(run "$(payload "$PROJECT/.claude/agents/advisor.md" worker)" "$CDIR" "$PROJECT")"
[ -z "$out" ] || fail "case 8: worker writing a different tier's project-scope definition was denied: $out"

# --- case 9: the kill switch is honoured before anything else, resolved from KIT_ROOT -----------------
# control run, same payload, no marker: it must deny, or the silence below proves nothing
out="$(run "$(payload "$KIT/agents/worker.md" worker)")"
[ "$(decision "$out")" = "deny" ] || fail "case 9: control run without the marker did not deny (got: ${out:-<silence>})"
mkdir -p "$KIT/.state/off"
touch "$KIT/.state/off/agent-selfdef-guard"
out="$(run "$(payload "$KIT/agents/worker.md" worker)")"
[ -z "$out" ] || fail "case 9: the kill switch did not silence the guard: $out"
# kit-gate stand-down: exit 0 and logged in the sandbox guards log.
printf '%s' "$(payload "$KIT/agents/worker.md" worker)" | CLAUDE_CONFIG_DIR="$CDIR" AGENT_TIERS_GUARDS_LOG="$LOG" AGENT_TIERS_KIT_ROOT="$KIT" sh "$KIT/scripts/agent-selfdef-guard.sh" >/dev/null 2>&1 \
  || fail "case 9: stand-down exit status was not 0"
grep -aq 'kit-gate standdown agent-selfdef-guard:' "$LOG" 2>/dev/null || fail "case 9: kit-gate stand-down was not logged"
rm -rf "$KIT/.state/off"

# --- case 10: fail-open when the agents/ directory is missing, with a breadcrumb ---------------------
EMPTY_KIT="$T/empty-kit"
mkdir -p "$EMPTY_KIT/scripts"
cp "$GUARD" "$EMPTY_KIT/scripts/"
cp "$SCRIPTS/guard-cmdpos.sh" "$EMPTY_KIT/scripts/"
: > "$LOG"
out="$(printf '%s' "$(payload "$T/notes.md" worker)" | CLAUDE_CONFIG_DIR="$CDIR" AGENT_TIERS_GUARDS_LOG="$LOG" AGENT_TIERS_KIT_ROOT="$EMPTY_KIT" sh "$EMPTY_KIT/scripts/agent-selfdef-guard.sh" 2>/dev/null)"
[ -z "$out" ] || fail "case 10: a missing agents/ directory blocked the write instead of failing open: $out"
grep -aq 'fail-open:.*agents.*missing' "$LOG" 2>/dev/null || fail "case 10: the fail-open left no breadcrumb"

# --- case 11: fail-open when guard-cmdpos.sh is a stale library missing the needed helper -------------
STALE_KIT="$T/stale-kit"
mkdir -p "$STALE_KIT/scripts" "$STALE_KIT/agents"
cp "$GUARD" "$STALE_KIT/scripts/"
printf '#!/usr/bin/env sh\n# stale, no guard_caller_agent defined\n' > "$STALE_KIT/scripts/guard-cmdpos.sh"
: > "$LOG"
out="$(printf '%s' "$(payload "$T/notes.md" worker)" | CLAUDE_CONFIG_DIR="$CDIR" AGENT_TIERS_GUARDS_LOG="$LOG" AGENT_TIERS_KIT_ROOT="$STALE_KIT" sh "$STALE_KIT/scripts/agent-selfdef-guard.sh" 2>/dev/null)"
[ -z "$out" ] || fail "case 11: a stale guard-cmdpos.sh blocked the write instead of failing open: $out"
grep -aq 'fail-open:.*stale library' "$LOG" 2>/dev/null || fail "case 11: the stale-library fail-open left no breadcrumb"

if [ "$fails" -eq 0 ]; then
  echo "PASS agent-selfdef-guard: 11/11 cases"
  exit 0
fi
printf 'agent-selfdef-guard: %s case(s) failed\n' "$fails"
exit 1

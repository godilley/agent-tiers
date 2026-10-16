#!/usr/bin/env sh
# kit-scope: shared
# Self-check for demo-css-guard.sh.
#
# Case 1: !important paired with a red outline on the same declaration is denied.
# Case 2: ordinary CSS with !important alone (no demo hook) is allowed.
# Case 3: a red outline with no !important is allowed.
# Case 4: a file with neither is allowed.
# Case 5: !important paired with outline-offset is denied (the second branch, previously ungated).
# Case 6: outline-offset with no !important is allowed (that branch's own negative).
# Case 7: !important paired with a bare [data-...] attribute selector is denied (the third branch,
#         previously ungated, and the disclosed accepted false positive - see the guard's header).
# Case 8: the same shape but the attribute carries a value ([data-theme="dark"]) is allowed - the
#         naive bracket regex requires a bare `]` right after the name, so a valued attribute misses.
# Case 9: a non-CSS file (this selfcheck's own fixture shape) is never examined, even though its
#         content matches case 1's shape - proves the file-type scope gate added in this wave.
# Case 10: the kill switch is honoured before anything else.
# Case 11: jq missing fails open with a breadcrumb, simulated by a PATH shadow that has every
#          coreutil the guard needs except jq.
#
# State sandboxing: the guard is copied into a temp scripts/ dir so KIT_ROOT-derived kill-switch
# resolution never touches the real kit's .state/off/. AGENT_TIERS_GUARDS_LOG points into the same
# mktemp -d.
set -u

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
SRC="$SCRIPTS/demo-css-guard.sh"
[ -f "$SRC" ] || { echo "FAIL: demo-css-guard.sh not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

KIT="$T/kit"
mkdir -p "$KIT/scripts" "$KIT/.state"
cp "$SRC" "$KIT/scripts/"
GUARD="$KIT/scripts/demo-css-guard.sh"
LOG="$T/guards.log"
# kit-gate.sh runs as a child of the guard: the fixture gets a rewritten copy (empty managed dir) and
# options.tsv, and every input the user's own options could reach it through is cleared.
mkdir -p "$KIT/install" "$T/managed" "$T/cfg"
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$SCRIPTS/kit-gate.sh" > "$KIT/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$KIT/scripts/kit-gate.sh" || { echo "SELF-CHECK FAILED: _kg_managed not rewritten"; exit 1; }
cp "$SCRIPTS/../install/options.tsv" "$KIT/install/"
export CLAUDE_CONFIG_DIR="$T/cfg" AGENT_TIERS_GUARDS_LOG="$LOG"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done

run() {  # run <content> [file-path]
  jq -n --arg p "${2:-$T/style.css}" --arg c "$1" '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}' \
    | AGENT_TIERS_GUARDS_LOG="$LOG" sh "$GUARD" 2>/dev/null
}
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }

# --- case 1: !important + red outline on the same declaration -> DENY ------------------------------
out="$(run '.callout { outline: 2px solid red !important; }')"
[ "$(decision "$out")" = "deny" ] || fail "case 1: demo shape was not denied (got: ${out:-<silence>})"
printf '%s' "$out" | grep -qi 'demo' || fail "case 1: the denial does not name the demo-css problem"

# --- case 2: ordinary CSS with !important alone -> ALLOW -------------------------------------------
out="$(run '.callout { color: blue !important; }')"
[ -z "$out" ] || fail "case 2: a bare !important with no demo hook was denied (false positive): $out"

# --- case 3: a red outline with no !important -> ALLOW ----------------------------------------------
out="$(run '.callout { outline: 2px solid red; }')"
[ -z "$out" ] || fail "case 3: a red outline with no !important was denied (false positive): $out"

# --- case 4: neither -> ALLOW --------------------------------------------------------------------------
out="$(run '.callout { color: blue; }')"
[ -z "$out" ] || fail "case 4: ordinary CSS with neither hook was denied (false positive): $out"

# --- case 5: !important + outline-offset -> DENY (previously ungated) ------------------------------
out="$(run '.callout { outline: 2px solid blue !important; outline-offset: 8px !important; }')"
[ "$(decision "$out")" = "deny" ] || fail "case 5: outline-offset + !important was not denied (got: ${out:-<silence>})"

# --- case 6: outline-offset with no !important -> ALLOW ---------------------------------------------
out="$(run '.callout { outline-offset: 8px; }')"
[ -z "$out" ] || fail "case 6: outline-offset with no !important was denied (false positive): $out"

# --- case 7: !important + a bare [data-...] attribute selector -> DENY (previously ungated) ---------
# Disclosed accepted false positive: this is ordinary modern CSS with no demo intent at all.
out="$(run '[data-state] { display: none !important; }')"
[ "$(decision "$out")" = "deny" ] || fail "case 7: a bare [data-...] selector + !important was not denied (got: ${out:-<silence>})"

# --- case 8: the same shape but the attribute carries a value -> ALLOW -----------------------------
out="$(run '[data-theme="dark"] .btn { color: red !important; }')"
[ -z "$out" ] || fail "case 8: a valued [data-theme=\"dark\"] selector was denied (false positive): $out"

# --- case 9: a non-CSS file with the exact case-1 shape is never examined ---------------------------
out="$(run '.callout { outline: 2px solid red !important; }' "$T/demo-css-guard.selfcheck.sh")"
[ -z "$out" ] || fail "case 9: a non-CSS file was examined despite the file-type scope gate: $out"

# --- case 10: the kill switch is honoured before anything else --------------------------------------
mkdir -p "$KIT/.state/off"
touch "$KIT/.state/off/demo-css-guard"
out="$(run '.callout { outline: 2px solid red !important; }')"
[ -z "$out" ] || fail "case 10: kill switch did not silence the guard: $out"
rm -f "$KIT/.state/off/demo-css-guard"

# --- case 10b: stand-down via kit-gate.sh: exit 0, empty stdout, kit-gate log line --------------------
ctl="$(run '.callout { outline: 2px solid red !important; }')"   # control: no marker, same payload must deny
[ "$(decision "$ctl")" = deny ] || fail "case 10b: control run (no marker) did not deny, fixture drifted: $ctl"
touch "$KIT/.state/off/demo-css-guard"
out="$(jq -n --arg p "$T/style.css" --arg c '.callout { outline: 2px solid red !important; }' \
  '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}' | sh "$GUARD" 2>/dev/null)"; rc=$?
rm -f "$KIT/.state/off/demo-css-guard"
[ -z "$out" ] && [ "$rc" = 0 ] || fail "case 10b: stand-down did not silence the guard (rc=$rc out=$out)"
grep -aq 'kit-gate standdown demo-css-guard:' "$LOG" 2>/dev/null || fail "case 10b: no kit-gate log line"

# --- case 11: jq missing fails open, with a breadcrumb ----------------------------------------------
FAKEBIN="$T/fakebin"
mkdir -p "$FAKEBIN"
for tool in sh cat mkdir date awk dirname env sed; do
  p="$(command -v "$tool" 2>/dev/null || true)"
  [ -n "$p" ] && ln -s "$p" "$FAKEBIN/$tool" 2>/dev/null
done
: > "$LOG"
out="$(jq -n --arg p "$T/style.css" --arg c '.callout { outline: 2px solid red !important; }' \
  '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}' \
  | PATH="$FAKEBIN" AGENT_TIERS_GUARDS_LOG="$LOG" sh "$GUARD" 2>/dev/null)"
[ -z "$out" ] || fail "case 11: a jq-less environment blocked the write instead of failing open: $out"
grep -aq 'fail-open: jq missing' "$LOG" 2>/dev/null || fail "case 11: the jq-missing fail-open left no breadcrumb"

if [ "$fails" -eq 0 ]; then
  echo "PASS demo-css-guard: 12/12 cases"
  exit 0
fi
printf 'demo-css-guard: %s case(s) failed\n' "$fails"
exit 1

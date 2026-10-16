#!/usr/bin/env sh
# kit-scope: shared
# Self-check for kit-gate.sh, run in a sandbox kit copy (temp CLAUDE_CONFIG_DIR, guards log and managed
# dir; plugin env cleared). A second sandbox kit sits in a plugin cache layout
# ($T/plugins/cache/mkt/agent-tiers/1.0 beside $T/plugins/installed_plugins.json) for the plugin route.
# Drives the gate through a real hook (grep-footgun-guard) and directly: every decision step on both
# routes, env ignored on both, fail-open cases, logging, --summary, and a lint over the REAL
# install/options.tsv and scripts. Shell under test: KIT_GATE_SH (default sh); with KIT_GATE_SH unset
# and dash present the whole check runs once more under dash. A `sh` shim on PATH points at that shell,
# so the hook's own `sh .../kit-gate.sh` call runs under it too.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP kit-gate: jq absent (gate fails open by design)"; exit 0; }
SH="${KIT_GATE_SH:-sh}"
SHPATH="$(command -v "$SH")" || { echo "FAIL kit-gate: shell $SH not found"; exit 1; }

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$T"' EXIT
K="$T/kit"; CFG="$T/cfg"; MD="$T/managed"; LOGF="$T/guards.log"
mkdir -p "$K/scripts" "$K/install" "$K/.state/off" "$CFG" "$MD/managed-settings.d" "$T/bin" "$T/nojq"
cp "$DIR/grep-footgun-guard.sh" "$DIR/guard-cmdpos.sh" "$K/scripts/"
cp "$DIR/../install/options.tsv" "$K/install/"
sed "s|^_kg_managed=.*|_kg_managed='$MD'|" "$DIR/kit-gate.sh" > "$K/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$MD'" "$K/scripts/kit-gate.sh" || { echo "FAIL kit-gate: _kg_managed line not rewritten in the sandbox copy"; exit 1; }
cp "$K/scripts/kit-gate.sh" "$T/kit-gate.sh.good"; cp "$K/install/options.tsv" "$T/options.tsv.good"
# mkkit dir: a copy of the sandbox kit (hook, library, gate, options.tsv, marker dir) at dir.
mkkit() { mkdir -p "$1/scripts" "$1/install" "$1/.state/off"; cp "$K/scripts/"*.sh "$1/scripts/"; cp "$K/install/options.tsv" "$1/install/"; }
PK="$T/plugins/cache/mkt/agent-tiers/1.0"; mkkit "$PK"; : > "$T/plugins/installed_plugins.json"
mkkit "$T/noidx/cache/mkt/agent-tiers/1.0"        # plugin layout, no installed_plugins.json: flat
mkkit "$T/plugins/cache/mkt2/agent-tiers"          # under the plugin root at the wrong depth: flat
mkkit "$T/plugins/cache/x/mkt/agent-tiers/1.0"     # four levels under cache: flat
mkkit "$T/plugins/cache/mkt/-f/1.0"                # plugin name with a leading dash: key -f@mkt
mkkit "$T/dirp/cache/mkt/agent-tiers/1.0"; mkdir -p "$T/dirp/installed_plugins.json"   # index is a dir: flat
ln -s "$K" "$T/plugroot"
ln -s "$SHPATH" "$T/bin/sh"
for t in grep sed cat date mkdir tr; do ln -s "$(command -v "$t")" "$T/nojq/$t"; done
ln -s "$SHPATH" "$T/nojq/sh"
PATH="$T/bin:$PATH"
export PATH AGENT_TIERS_GUARDS_LOG="$LOGF" CLAUDE_CONFIG_DIR="$CFG"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
KR="$K"   # kit under test for hk/gt/sm; plugin-route cases set KR="$PK"
GATE="$K/scripts/kit-gate.sh"
PR="CLAUDE_PLUGIN_ROOT=$T/plugroot"
PAY='{"session_id":"sc","tool_input":{"command":"grep -rn foo ."}}'
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# hk want why [VAR=val ...]: the pilot hook; runs = it still denies the recursive grep, silent = no
# output (stood down). Exit status must be 0 either way.
hk() {
  want="$1"; why="$2"; shift 2
  out="$(printf '%s' "$PAY" | env "$@" "$SHPATH" "$KR/scripts/grep-footgun-guard.sh" 2>/dev/null)"; rc=$?
  if printf '%s' "$out" | grep -q '"deny"'; then got=runs; elif [ -z "$out" ]; then got=silent; else got=other; fi
  if [ "$got" = "$want" ] && [ "$rc" = 0 ]; then ok "[hook $got] $why"; else bad "hook want=$want got=$got rc=$rc : $why"; fi
}
# gt want id why [VAR=val ...]: the gate called directly. stand = rc 0 and stdout exactly `standdown`;
# run = rc 1 and empty stdout; anything else is a failure.
gt() {
  want="$1"; id="$2"; why="$3"; shift 3
  out="$(env "$@" "$SHPATH" "$KR/scripts/kit-gate.sh" "$id" </dev/null 2>/dev/null)"; rc=$?
  if [ "$rc" = 0 ] && [ "$out" = standdown ]; then got=stand
  elif [ "$rc" = 1 ] && [ -z "$out" ]; then got=run
  else got="other(rc=$rc out=[$out])"; fi
  if [ "$got" = "$want" ]; then ok "[gate $got] $why"; else bad "gate want=$want got=$got : $why"; fi
}
# sm want why [VAR=val ...]: --summary prints exactly $want (empty = nothing) and exits 0.
sm() {
  want="$1"; why="$2"; shift 2
  out="$(env "$@" "$SHPATH" "$KR/scripts/kit-gate.sh" --summary </dev/null 2>/dev/null)"; rc=$?
  if [ "$out" = "$want" ] && [ "$rc" = 0 ]; then ok "[summary] $why"; else bad "summary rc=$rc want=[$want] got=[$out] : $why"; fi
}
reset() {
  rm -f "$CFG/settings.json" "$MD/managed-settings.json" "$MD"/managed-settings.d/*.json "$K"/.state/off/* "$PK"/.state/off/*
  cp "$T/kit-gate.sh.good" "$GATE"; cp "$T/options.tsv.good" "$K/install/options.tsv"
  cp "$T/kit-gate.sh.good" "$PK/scripts/kit-gate.sh"; cp "$T/options.tsv.good" "$PK/install/options.tsv"
  KR="$K"
}
settings() { printf '%s\n' "$1" > "$CFG/settings.json"; }
managed() { printf '%s\n' "$1" > "$MD/managed-settings.json"; }
managed_d() { printf '%s\n' "$2" > "$MD/managed-settings.d/$1.json"; }
opts() { printf '{"pluginConfigs":{"agent-tiers@m":{"options":%s}}}' "$1"; }
popts() { printf '{"pluginConfigs":{"agent-tiers@%s":{"options":%s}}}' "${2:-mkt}" "$1"; }   # plugin route key

echo "-- shell under test: $SH"
echo "-- a missing, empty or broken gate never blocks the hook"
reset; settings "$(opts '{"enabled":false}')"
rm -f "$GATE"; hk runs "kit-gate.sh missing"
printf 'if\n' > "$GATE"; hk runs "kit-gate.sh is a syntax error (content: if)"
: > "$GATE"; hk runs "kit-gate.sh empty"
head -n 70 "$T/kit-gate.sh.good" > "$GATE"; hk runs "kit-gate.sh truncated to its first 70 lines"
reset

echo "-- baseline"
hk runs "no settings file"
settings '{}'; hk runs "settings with no pluginConfigs"
settings "$(opts '{"enabled":true,"group_shell_footguns":true}')"; hk runs "every option on"
gt run 'x y' "id with a space"
gt run '' "empty id"

echo "-- 1. AGENT_TIERS_OFF"
reset
hk silent "AGENT_TIERS_OFF=1" AGENT_TIERS_OFF=1
hk runs "AGENT_TIERS_OFF=0" AGENT_TIERS_OFF=0
hk runs "AGENT_TIERS_OFF empty" AGENT_TIERS_OFF=
gt stand resume-inject "AGENT_TIERS_OFF=1 stands a core hook down" AGENT_TIERS_OFF=1

echo "-- 2. markers"
touch "$K/.state/off/grep-footgun-guard"; hk silent "marker .state/off/<id>"; reset
touch "$K/.state/off/other-guard"; hk runs "a marker for another hook"; reset
touch "$K/.state/off/x y"; gt run 'x y' "marker named 'x y', id 'x y' is invalid"; reset
touch "$K/.state/off/resume-inject"; gt stand resume-inject "marker stands a core hook down"; reset

echo "-- flat route (settings.json and managed)"
settings "$(opts '{"enabled":false}')"; hk silent "enabled=false"
gt stand resume-inject "enabled=false stands a core hook down"
settings "$(opts '{"enabled":0}')"; hk silent "enabled=0"
settings "$(opts '{"enabled":"false"}')"; hk silent "enabled=\"false\""
settings "$(opts '{"group_shell_footguns":false}')"; hk silent "own group false"
settings "$(opts '{"group_shell_footguns":0}')"; hk silent "own group 0"
settings "$(opts '{"group_safety":false}')"; hk runs "another group off"
settings "$(opts '{"group_core":false}')"; gt run resume-inject "group_core=false never stands a core hook down"
settings "$(opts '{"disabled_hooks":["peer-guard","grep-footgun-guard"]}')"; hk silent "disabled_hooks JSON array"
settings "$(opts '{"disabled_hooks":"peer-guard,grep-footgun-guard"}')"; hk silent "disabled_hooks comma string"
settings "$(opts '{"disabled_hooks":["grep-footgun-guard-x","x-grep-footgun-guard"]}')"; hk runs "disabled_hooks only longer ids"
settings '{"pluginConfigs":{"other@m":{"options":{"enabled":false}}}}'; hk runs "another plugin's options"
settings '{"pluginConfigs":{"agent-tiers-extra@m":{"options":{"enabled":false}}}}'; hk runs "agent-tiers-extra@m is not this kit"
# agent-tiers@ also appears in the file here, so the jq key filter is reached (not the grep early return).
settings '{"enabledPlugins":{"agent-tiers@m":true},"pluginConfigs":{"agent-tiers-extra@m":{"options":{"enabled":false}}}}'
hk runs "agent-tiers-extra@m is not this kit (file also names agent-tiers@)"
settings '{"pluginConfigs":{"agent-tiers-extra@m":{"options":{"enabled":false}},"agent-tiers@m":{"options":{"enabled":true}}}}'
hk runs "agent-tiers-extra@m listed first is skipped"
settings '{"pluginConfigs":{"agent-tiers@a":{"options":{"enabled":false}},"agent-tiers@b":{"options":{"enabled":true}}}}'
hk silent "two keys, none enabled: the first (off) wins"
settings '{"pluginConfigs":{"agent-tiers@a":{"options":{"enabled":true}},"agent-tiers@b":{"options":{"enabled":false}}}}'
hk runs "two keys, none enabled: the first (on) wins"
settings '{"enabledPlugins":{"agent-tiers@b":true},"pluginConfigs":{"agent-tiers@a":{"options":{"enabled":true}},"agent-tiers@b":{"options":{"enabled":false}}}}'
hk silent "enabledPlugins picks the second key (off)"
settings '{"enabledPlugins":{"agent-tiers@a":false,"agent-tiers@b":true},"pluginConfigs":{"agent-tiers@a":{"options":{"enabled":false}},"agent-tiers@b":{"options":{"enabled":true}}}}'
hk runs "enabledPlugins picks the second key (on)"
reset
settings "$(opts '{"enabled":true}')"; managed "$(opts '{"enabled":false}')"; hk silent "managed false beats user true"
settings "$(opts '{"enabled":false}')"; managed "$(opts '{"enabled":true}')"; hk runs "managed true beats user false"
reset
managed "$(opts '{"group_shell_footguns":false}')"; hk silent "managed only, no user file"
managed "$(opts '{"enabled":false}')"; managed_d 10 "$(opts '{"enabled":true}')"; hk runs "managed-settings.d beats managed-settings.json"
reset
managed_d 10 "$(opts '{"enabled":true}')"; managed_d 20 "$(opts '{"enabled":false}')"; hk silent "managed-settings.d: later file wins (20 off)"
reset
managed_d 10 "$(opts '{"enabled":false}')"; managed_d 20 "$(opts '{"enabled":true}')"; hk runs "managed-settings.d: later file wins (20 on)"
reset
settings "$(opts '{"disabled_hooks":["grep-footgun-guard"]}')"; managed "$(opts '{"disabled_hooks":["peer-guard"]}')"
hk silent "disabled_hooks union: listed by user only"
settings "$(opts '{"disabled_hooks":["peer-guard"]}')"; managed "$(opts '{"disabled_hooks":["grep-footgun-guard"]}')"
hk silent "disabled_hooks union: listed by managed only"
reset
settings "$(opts '{"enabled":false}')"; managed "$(opts '{"enabled":null}')"; hk silent "a managed null does not erase a user value"
reset

echo "-- fail open"
settings 'not json { agent-tiers@m'; hk runs "invalid settings JSON"
settings "$(opts '{"enabled":false}')"; managed 'not json'; hk runs "one invalid store file: whole flat lookup skipped"
reset
settings '{"pluginConfigs":"agent-tiers@m"}'; hk runs "pluginConfigs not an object"
settings "$(opts '{"enabled":false}')"
gt run grep-footgun-guard "no jq on PATH" PATH="$T/nojq"
rm -f "$K/install/options.tsv"
hk silent "no options.tsv: enabled=false still applies"
settings "$(opts '{"group_shell_footguns":false}')"; hk runs "no options.tsv: group unknown, hook runs"
rm -f "$PK/install/options.tsv"; KR="$PK"
hk runs "plugin route, no options.tsv: no group, no default, hook runs"
KR="$K"
printf 'hook\tgrep-footgun-guard\tbad;name\tPreToolUse\tBash\t5\n' > "$K/install/options.tsv"
cp "$K/install/options.tsv" "$PK/install/options.tsv"
hk runs "group name not an identifier (flat)"
settings "$(popts '{"enabled":true}')"; KR="$PK"; hk runs "group name not an identifier (plugin)"; KR="$K"
awk -F'\t' -v OFS='\t' '$1 == "hook" && $2 == "grep-footgun-guard" { $3 = "Shell_footguns" } 1' "$T/options.tsv.good" > "$PK/install/options.tsv"
settings "$(popts '{"group_shell_footguns":false}')"; KR="$PK"
hk runs "hook row group Shell_footguns is not an identifier: group_shell_footguns=false ignored (plugin)"
reset
settings "$(popts '{"enabled":false}')"; KR="$PK"
gt run grep-footgun-guard "plugin route, no jq on PATH: runs" PATH="$T/nojq"
settings 'not json { agent-tiers@mkt'; hk runs "plugin route, invalid settings JSON: runs"
reset

echo "-- plugin route (kit root in a plugin cache layout)"
KR="$PK"
hk silent "plugin, no settings: tsv default group_shell_footguns=false applies"
gt run resume-inject "plugin, no settings: a core hook runs"
grep -qF ' kit-gate standdown grep-footgun-guard: option group_shell_footguns=false (plugin default) [sid=]' "$LOGF" \
  && ok "plugin default reason logged" || bad "plugin default reason not logged: $(tail -1 "$LOGF")"
settings '{}'; hk silent "plugin, settings with no pluginConfigs: tsv default"
settings "$(popts '{"group_shell_footguns":true}')"; hk runs "plugin, own group true"
settings "$(popts '{"group_shell_footguns":true}' other)"; hk silent "plugin, group true under agent-tiers@other only: key comes from the path"
settings "$(popts '{"group_shell_footguns":false}')"; hk silent "plugin, own group false"
grep -qF ' kit-gate standdown grep-footgun-guard: option group_shell_footguns=false (plugin) [sid=]' "$LOGF" \
  && ok "explicit plugin value reason logged" || bad "explicit plugin reason not logged: $(tail -1 "$LOGF")"
settings "$(popts '{"enabled":false,"group_shell_footguns":true}')"; hk silent "plugin, enabled=false"
settings "$(popts '{"enabled":0,"group_shell_footguns":true}')"; hk silent "plugin, enabled=0"
settings "$(popts '{"group_shell_footguns":true,"disabled_hooks":["peer-guard","grep-footgun-guard"]}')"; hk silent "plugin, disabled_hooks JSON array"
settings "$(popts '{"group_shell_footguns":true,"disabled_hooks":"p,q r,grep-footgun-guard"}')"; hk silent "plugin, disabled_hooks string with a space"
settings "$(popts '{"group_shell_footguns":true,"disabled_hooks":"p,q r"}')"; hk runs "plugin, disabled_hooks lists others only"
settings "$(popts '{"group_shell_footguns":true,"group_safety":false}')"; hk runs "plugin, another group off"
settings "$(popts '{"group_core":false}')"; gt run resume-inject "plugin, group_core=false never stands a core hook down"
settings "$(popts '{"enabled":false}')"; gt stand resume-inject "plugin, enabled=false stands a core hook down"
settings "$(popts '{"group_shell_footguns":true}')"; managed "$(popts '{"group_shell_footguns":false}')"; hk silent "plugin, managed false beats user true"
reset; KR="$PK"
settings "$(opts '{"group_shell_footguns":true}')"; hk silent "plugin, a flat-style key (agent-tiers@m) is not this plugin's key"
reset; KR="$PK"
managed 'not json'; hk silent "plugin, invalid managed JSON not naming the key: plugin defaults"
managed "$(popts '{"group_shell_footguns":true}')"; hk runs "plugin, key only in a managed file: that value applies"
reset; KR="$T/plugins/cache/mkt/-f/1.0"
hk silent "plugin name -f, no settings: plugin defaults"
settings "$(popts '{"group_shell_footguns":true}')"; hk silent "plugin name -f: agent-tiers@mkt is not its key"
settings '{"pluginConfigs":{"-f@mkt":{"options":{"group_shell_footguns":true}}}}'; hk runs "plugin name -f: key -f@mkt read (not parsed as a grep option)"
reset; KR="$PK"
touch "$PK/.state/off/resume-inject"; gt stand resume-inject "plugin, marker stands a core hook down"
reset
echo "-- route from the path, not env"
KR="$T/noidx/cache/mkt/agent-tiers/1.0"; hk runs "cache layout without installed_plugins.json: flat (runs, no settings)"
KR="$T/plugins/cache/mkt2/agent-tiers"; hk runs "cache dir at the wrong depth: flat (runs, no settings)"
KR="$T/plugins/cache/x/mkt/agent-tiers/1.0"; hk runs "root four levels under cache: flat (runs, no settings)"
KR="$T/dirp/cache/mkt/agent-tiers/1.0"; hk runs "installed_plugins.json is a directory: flat (runs, no settings)"
KR="$K"
hk runs "flat, CLAUDE_PLUGIN_OPTION_ENABLED=false ignored" CLAUDE_PLUGIN_OPTION_ENABLED=false
hk runs "flat, CLAUDE_PLUGIN_OPTION_GROUP_SHELL_FOOTGUNS=false ignored" CLAUDE_PLUGIN_OPTION_GROUP_SHELL_FOOTGUNS=false
hk runs "flat, CLAUDE_PLUGIN_OPTION_DISABLED_HOOKS ignored" CLAUDE_PLUGIN_OPTION_DISABLED_HOOKS=grep-footgun-guard
hk runs "flat, empty CLAUDE_PLUGIN_ROOT + option env ignored" CLAUDE_PLUGIN_ROOT= CLAUDE_PLUGIN_OPTION_ENABLED=false
hk runs "flat, CLAUDE_PLUGIN_ROOT at a missing dir + option env ignored" "CLAUDE_PLUGIN_ROOT=$T/nope" CLAUDE_PLUGIN_OPTION_ENABLED=false
hk runs "flat, forged CLAUDE_PLUGIN_ROOT at the flat kit (via symlink): route stays flat" "$PR"
hk runs "flat, forged CLAUDE_PLUGIN_ROOT at the plugin kit: route stays flat" "CLAUDE_PLUGIN_ROOT=$PK"
# A store file naming agent-tiers@ so the flat route reaches its values (no store file runs at once).
settings "$(opts '{"enabled":true}')"
hk runs "flat, forged CLAUDE_PLUGIN_ROOT at the flat kit + CLAUDE_PLUGIN_OPTION_ENABLED=false: runs" "$PR" CLAUDE_PLUGIN_OPTION_ENABLED=false
rm -f "$CFG/settings.json"
KR="$PK"
hk silent "plugin, CLAUDE_PLUGIN_OPTION_GROUP_SHELL_FOOTGUNS=true does not turn the defaulted-off group on" CLAUDE_PLUGIN_OPTION_GROUP_SHELL_FOOTGUNS=true
hk silent "plugin, forged CLAUDE_PLUGIN_ROOT at the flat kit: route stays plugin" "$PR" CLAUDE_PLUGIN_OPTION_GROUP_SHELL_FOOTGUNS=true
hk silent "plugin, forged CLAUDE_PLUGIN_ROOT at the plugin kit + option env: still defaults" "CLAUDE_PLUGIN_ROOT=$PK" CLAUDE_PLUGIN_OPTION_GROUP_SHELL_FOOTGUNS=true
settings "$(popts '{"group_shell_footguns":true}')"
hk runs "plugin, CLAUDE_PLUGIN_OPTION_ENABLED=false ignored" CLAUDE_PLUGIN_OPTION_ENABLED=false
hk runs "plugin, CLAUDE_PLUGIN_OPTION_DISABLED_HOOKS ignored" CLAUDE_PLUGIN_OPTION_DISABLED_HOOKS=grep-footgun-guard
reset

echo "-- logging"
reset; rm -f "$LOGF"
nlines() { if [ -f "$LOGF" ]; then grep -c ' kit-gate standdown ' "$LOGF"; else echo 0; fi; }
g() { env "$@" "$SHPATH" "$GATE" grep-footgun-guard </dev/null >/dev/null 2>&1; }
settings "$(opts '{"enabled":false}')"
g CLAUDE_CODE_SESSION_ID=s1; g CLAUDE_CODE_SESSION_ID=s1
[ "$(nlines)" = 1 ] && ok "two identical stand-downs log one line" || bad "two identical stand-downs: $(nlines) lines"
grep -qE '^[^ ]+ kit-gate standdown grep-footgun-guard: option enabled=false \(flat\) \[sid=s1\]$' "$LOGF" \
  && ok "line format, sid from CLAUDE_CODE_SESSION_ID" || bad "line format: $(cat "$LOGF")"
g CLAUDE_CODE_SESSION_ID=s2
[ "$(nlines)" = 2 ] && ok "a second sid adds a line" || bad "second sid: $(nlines) lines"
touch "$K/.state/off/grep-footgun-guard"
g CLAUDE_CODE_SESSION_ID=s1
[ "$(nlines)" = 3 ] && ok "a different reason adds a line" || bad "different reason: $(nlines) lines"
g; g
[ "$(grep -c '\[sid=\]$' "$LOGF")" = 1 ] && ok "no sid logs once as [sid=]" || bad "no sid: $(grep -c '\[sid=\]$' "$LOGF") lines"
g 'CLAUDE_CODE_SESSION_ID=s5;rm -rf x'
grep -q '\[sid=s5\]$' "$LOGF" && ok "sid cut at the first character outside [A-Za-z0-9._-]" || bad "sid not filtered: $(tail -1 "$LOGF")"
reset
g CLAUDE_CODE_SESSION_ID=s3
[ "$(nlines)" = 5 ] && ok "no line on the run path" || bad "run path logged: $(nlines) lines"
grep -qE '^[^ ]+ [^ ]+ (deny|ask): ' "$LOGF" && bad "a standdown line counts as a block" || ok "standdown lines are not counted as blocks"
# Dedupe looks only at the last 64 KiB: push the s1 line out of that window, the same stand-down logs again.
settings "$(opts '{"enabled":false}')"
awk 'BEGIN { for (i = 0; i < 1100; i++) printf "%064d\n", i }' >> "$LOGF"
g CLAUDE_CODE_SESSION_ID=s1
[ "$(nlines)" = 6 ] && ok "dedupe window is the last 64 KiB" || bad "64 KiB window: $(nlines) lines"
out="$(AGENT_TIERS_GUARDS_LOG=/dev/null/x "$SHPATH" "$GATE" grep-footgun-guard </dev/null 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = standdown ] && ok "unwritable log: still stands down" || bad "unwritable log changed the result: rc=$rc out=[$out]"
got="$(printf 'PAYLOAD' | { "$SHPATH" "$GATE" grep-footgun-guard >/dev/null 2>&1; cat; })"
[ "$got" = PAYLOAD ] && ok "stand-down path leaves stdin unread" || bad "stand-down path consumed stdin: [$got]"
reset
got="$(printf 'PAYLOAD' | { "$SHPATH" "$GATE" grep-footgun-guard >/dev/null 2>&1; cat; })"
[ "$got" = PAYLOAD ] && ok "run path leaves stdin unread" || bad "run path consumed stdin: [$got]"

echo "-- --summary"
reset; cp "$LOGF" "$T/log.before"
sm "" "nothing off"
sm "" "AGENT_TIERS_OFF=0" AGENT_TIERS_OFF=0
sm "agent-tiers: every kit hook is off (AGENT_TIERS_OFF=1)" "AGENT_TIERS_OFF=1" AGENT_TIERS_OFF=1
touch "$K/.state/off/notify"
sm "agent-tiers: hooks off: notify (marker)" "marker with no store file at all"
reset
settings "$(opts '{"enabled":false}')"
sm "agent-tiers: every kit hook is off (option enabled=false (flat))" "enabled=false"
settings "$(opts '{"group_safety":false,"group_core":false,"group_bogus":false}')"
sm "agent-tiers: groups off (flat): safety" "one group off; core and unknown groups not listed"
settings "$(opts '{"disabled_hooks":["notify","not-a-hook","peer-guard"]}')"
touch "$K/.state/off/notify" "$K/.state/off/legacy-x"
sm "agent-tiers: hooks off: peer-guard (disabled_hooks), notify (marker)" "marker + disabled_hooks: known ids only, each once"
reset
settings "$(opts "{\"disabled_hooks\":[$(awk -F'\t' '$1 == "hook" { printf "%s\"%s\"", (n++ ? "," : ""), $2 }' "$K/install/options.tsv")]}")"
out="$("$SHPATH" "$GATE" --summary </dev/null 2>/dev/null)"
[ "${#out}" = 300 ] && [ "${out% ...}" != "$out" ] && ok "summary capped at 300 bytes with ' ...'" || bad "cap: ${#out} bytes [$out]"
reset
KR="$PK"
sm "" "plugin defaults alone print nothing (no settings)"
settings "$(popts '{"group_safety":false}')"
sm "agent-tiers: groups off (plugin): safety" "plugin: explicit group_safety=false listed"
settings "$(popts '{"group_memory":false,"group_safety":true}')"
sm "agent-tiers: groups off (plugin): memory" "plugin: one explicit off, one explicit on"
sm "agent-tiers: groups off (plugin): memory" "plugin: option env ignored" CLAUDE_PLUGIN_OPTION_GROUP_SAFETY=false
{ printf 'option\tgroup_Bad;x\tboolean\tfalse\tBad\tBad\n'; cat "$T/options.tsv.good"; } > "$PK/install/options.tsv"
sm "agent-tiers: groups off (plugin): memory" "an option row group that is not an identifier is skipped"
reset
got="$(printf 'PAYLOAD' | { "$SHPATH" "$GATE" --summary >/dev/null 2>&1; cat; })"
[ "$got" = PAYLOAD ] && ok "--summary leaves stdin unread" || bad "--summary consumed stdin"
cmp -s "$LOGF" "$T/log.before" && ok "--summary never logs" || bad "--summary wrote to the log"

echo "-- lint: real install/options.tsv and scripts"
TSV="$DIR/../install/options.tsv"
# A kit export drops export-ignored scripts and .gitattributes itself, so script existence is only
# checked in a checkout that still has .gitattributes.
chk=0; [ -f "$DIR/../.gitattributes" ] && chk=1
lint_tsv() { awk -F'\t' -v sd="$DIR" -v chk="$chk" '
  function err(m) { print "options.tsv:" NR ": " m }
  $1 == "hook" {
    if (NF != 7) err("hook row needs 7 fields")
    if ($7 !~ /^(-|[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*)$/) err("bad requires " $7)
    rq[NR] = $7; rid[NR] = $2
    if ($2 in hid) err("duplicate hook id " $2); hid[$2] = 1
    if ($2 !~ /^[a-z0-9][a-z0-9-]*$/) err("bad hook id " $2)
    if ($3 !~ /^[a-z][a-z0-9_]*$/) err("bad group " $3)
    hg[$3] = 1
    if (chk) { f = sd "/" $2 ".sh"; if ((getline l < f) < 0) err("no script " f); close(f) }
  }
  $1 == "option" {
    if (NF != 6) err("option row needs 6 fields")
    if ($2 !~ /^[a-z][a-z0-9_]*$/) err("bad option key " $2)
    if ($2 in ok_) err("duplicate option " $2); ok_[$2] = 1
    if ($3 != "boolean" && $3 != "string[]") err("bad type " $3)
    if ($3 == "boolean" && $4 != "true" && $4 != "false") err("bad boolean default " $4)
    if ($2 ~ /^group_/) og[substr($2, 7)] = 1
  }
  $1 == "extra" {
    if (NF != 5) err("extra row needs 5 fields")
    if ($2 !~ /^[a-z][a-z0-9-]*$/) err("bad extra id " $2)
    if ($2 in eid) err("duplicate extra id " $2); eid[$2] = 1
    if ($3 != "settings" && $3 != "pointer") err("bad extra action " $3)
  }
  $1 == "level" { lv[NR] = $3 }
  END {
    for (r in rq) { n = split(rq[r], a, ","); for (i = 1; i <= n; i++) {
      if (a[i] == "-") continue
      if (a[i] == rid[r]) print "options.tsv:" r ": hook " rid[r] " requires itself"
      else if (!(a[i] in hid)) print "options.tsv:" r ": requires unknown hook id " a[i] } }
    for (x in eid) if (x in hid) print "options.tsv: extra id " x " is also a hook id"
    if (!("enabled" in ok_)) print "options.tsv: no enabled option"
    if (!("disabled_hooks" in ok_)) print "options.tsv: no disabled_hooks option"
    if ("core" in og) print "options.tsv: core must not have a group option"
    for (g in hg) if (g != "core" && !(g in og)) print "options.tsv: group " g " has no group_" g " option"
    for (g in og) if (!(g in hg)) print "options.tsv: group_" g " has no hook"
    for (r in lv) { n = split(lv[r], a, ","); for (i = 1; i <= n; i++) if (a[i] != "*" && !(a[i] in hg)) print "options.tsv:" r ": level group " a[i] " unknown" }
  }' "$1"; }
lint="$(lint_tsv "$TSV")"
[ -z "$lint" ] && ok "options.tsv rows" || { printf '%s\n' "$lint" | sed 's/^/FAIL /'; fail=1; }
# planted rows: the same lint must flag an unknown, a self and a malformed requires value
awk -F'\t' -v OFS='\t' '$1 == "hook" { n++; if (n == 1) $7 = "no-such-hook"; if (n == 2) $7 = $2; if (n == 3) $7 = "a b" } 1' "$TSV" > "$T/planted.tsv"
plint="$(lint_tsv "$T/planted.tsv")"
for m in 'requires unknown hook id no-such-hook' ' requires itself' 'bad requires a b'; do
  printf '%s\n' "$plint" | grep -q -- "$m" && ok "lint flags planted: $m" || { echo "FAIL lint missed planted: $m"; fail=1; }
done
FRAG='"$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ]'
for f in "$DIR"/*.sh; do
  b="${f##*/}"
  case "$b" in *.selfcheck.sh | kit-gate.sh) continue ;; esac
  # A script that names kit-gate.sh only in comments (a doc reference) is not a caller.
  awk 'index($0, "kit-gate.sh") && $0 !~ /^[[:space:]]*#/ { f = 1 } END { exit !f }' "$f" || continue
  awk -F'\t' -v id="${b%.sh}" '$1 == "hook" && $2 == id { f = 1 } END { exit !f }' "$TSV" \
    && ok "$b has a hook row" || bad "$b calls kit-gate.sh but has no hook row"
  awk -v fr="$FRAG" 'index($0, fr) && $0 !~ /^[[:space:]]*#/ { f = 1 } END { exit !f }' "$f" \
    && ok "$b has the standard call line, uncommented" || bad "$b lacks an uncommented standard call line: $FRAG"
done
# Every hook row in options.tsv must call the gate, uncommented. The loop above skips *.selfcheck.sh and
# kit-gate.sh, and neither is ever a hook row. Same row rule as gen-plugin-manifests.sh: a kit-local
# (export-ignored) script is absent from a shipped copy, which also has no .gitattributes, so an absent
# script is skipped there; in the source repo (.gitattributes present) it is checked and fails.
for id in $(awk -F'\t' '$1 == "hook" { print $2 }' "$TSV"); do
  [ ! -f "$DIR/$id.sh" ] && [ ! -f "$DIR/../.gitattributes" ] && { ok "hook $id: script not in this shipped copy, skipped"; continue; }
  awk -v fr="$FRAG" 'index($0, fr) && $0 !~ /^[[:space:]]*#/ { f = 1 } END { exit !f }' "$DIR/$id.sh" 2>/dev/null \
    && ok "hook $id has the standard call line, uncommented" || bad "hook $id lacks an uncommented standard call line"
done

if [ -z "${KIT_GATE_SH:-}" ] && command -v dash >/dev/null 2>&1; then
  echo "-- re-run under dash"
  KIT_GATE_SH=dash dash "$DIR/kit-gate.selfcheck.sh" || fail=1
fi

[ "$fail" = 0 ] && echo "PASS kit-gate.sh ($SH)" || { echo "FAIL kit-gate.sh ($SH)"; exit 1; }

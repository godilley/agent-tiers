#!/usr/bin/env sh
# kit-scope: shared
# Self-check for gen-plugin-manifests.sh. Real kit: --check is clean and hooks.json matches an independent
# awk+jq expectation. Fixture kits (git init, own options.tsv/.gitattributes/plugin.json) in a temp dir
# cover drift detection, --write, the export-ignore rule, userConfig shapes and plugin.json preservation.
# Shell under test: GENPM_SH (default sh); with it unset and dash present the whole check re-runs under dash.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP gen-plugin-manifests: jq absent"; exit 0; }
SH="${GENPM_SH:-sh}"
command -v "$SH" >/dev/null 2>&1 || { echo "FAIL gen-plugin-manifests: shell $SH not found"; exit 1; }
GEN="$DIR/gen-plugin-manifests.sh"
REAL="$(CDPATH= cd "$DIR/.." && pwd)"
T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$T"' EXIT
export CLAUDE_CONFIG_DIR="$T/cfg" AGENT_TIERS_GUARDS_LOG="$T/guards.log"
pass=0; failn=0
ok() { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; failn=$((failn + 1)); }
# rc want label cmd...: run cmd, compare exit status
rc() { want="$1"; label="$2"; shift 2; "$@" >"$T/out" 2>&1; got=$?; [ "$got" = "$want" ] && ok "$label" || { bad "$label (rc=$got want=$want)"; sed 's/^/    /' "$T/out"; }; }
gen() { "$SH" "$GEN" "$@"; }

# a. real kit. SIMULATION: until every hook script calls the kit gate, the real-kit cases run against a temp
# COPY of the kit in which the gate line is inserted after line 1 of every hook script that lacks it.
GL='[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0'
FRAGT='"$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ]'
RK="$T/realcopy"; mkdir -p "$RK"; cp -R "$REAL/install" "$REAL/scripts" "$REAL/.claude-plugin" "$REAL/hooks" "$RK/"
[ -f "$REAL/.gitattributes" ] && cp "$REAL/.gitattributes" "$RK/"
for id in $(awk -F'\t' '$1 == "hook" { print $2 }' "$RK/install/options.tsv"); do
  f="$RK/scripts/$id.sh"; [ -f "$f" ] || continue
  awk -v fr="$FRAGT" 'index($0, fr) && $0 !~ /^[[:space:]]*#/ { f = 1 } END { exit !f }' "$f" && continue
  awk -v gl="$GL" 'NR == 1 { print; print gl; next } { print }' "$f" > "$T/g" && cat "$T/g" > "$f"
done
REAL="$RK"
rc 0 "real kit (gate-simulated copy) --check clean" gen --check "$REAL"
rc 0 "real kit (gate-simulated copy) default mode clean" gen "$REAL"
HJ="$REAL/hooks/hooks.json"
grep -q kit-leak-guard "$HJ" && bad "real hooks.json lists kit-leak-guard" || ok "real hooks.json omits kit-leak-guard"
# expect_rows KIT: wired-row expectation computed independently of the generator (awk + git/grep + jq).
expect_rows() {
  K="$1"; ing=0; git -C "$K" rev-parse --is-inside-work-tree >/dev/null 2>&1 && ing=1
  awk -F'\t' '$1 == "hook" { print $2 "\t" $4 "\t" $5 "\t" $6 }' "$K/install/options.tsv" | while IFS= read -r l; do
    id="${l%%	*}"; ig=0
    if [ "$ing" = 1 ]; then
      case "$(git -C "$K" check-attr export-ignore -- "scripts/$id.sh" 2>/dev/null)" in *": set") ig=1 ;; esac
    elif [ -f "$K/.gitattributes" ] && grep -qxF "scripts/$id.sh export-ignore" "$K/.gitattributes"; then ig=1; fi
    [ "$ig" = 1 ] && continue
    [ -f "$K/scripts/$id.sh" ] || [ -f "$K/.gitattributes" ] || continue
    printf '%s\n' "$l"
  done | sort
}
actual_rows() {
  jq -r '.hooks | to_entries[] | .key as $e | .value[] | (.matcher // "") as $m | .hooks[] | (.command | capture("scripts/(?<i>[^.]+)\\.sh").i) + "\t" + $e + "\t" + $m + "\t" + (.timeout | tostring)' "$1/hooks/hooks.json" | sort
}
exp="$(expect_rows "$REAL")"; got="$(actual_rows "$REAL")"
[ "$exp" = "$got" ] && ok "real hooks.json rows == independent expectation ($(printf '%s\n' "$exp" | wc -l | tr -d ' '))" || bad "real hooks.json rows differ from expectation"
# shipped-copy shape: no git, no .gitattributes, export-ignored scripts stripped
SC="$T/shipped"; mkdir -p "$SC"; cp -R "$REAL/install" "$REAL/scripts" "$REAL/.claude-plugin" "$REAL/hooks" "$SC/"
rm -f "$SC"/scripts/kit-leak-guard*.sh "$SC"/scripts/leak-scan*.sh "$SC"/scripts/maint2-arrival-guard*.sh "$SC"/scripts/guard-outcome-tag*.sh
rc 0 "shipped copy (no git, no .gitattributes) --check clean" gen --check "$SC"
[ "$(expect_rows "$SC")" = "$(actual_rows "$SC")" ] && ok "shipped copy rows == independent expectation" || bad "shipped copy rows differ from expectation"

# fixture kit
mkfix() {
  F="$1"; rm -rf "$F"; mkdir -p "$F/install" "$F/scripts" "$F/.claude-plugin" "$F/hooks"
  printf '# c\nhook\talpha\tcore\tSessionStart\t\t10\t-\nhook\tbeta\tsafety\tPreToolUse\tBash\t5\t-\nhook\tgamma\tsafety\tPreToolUse\tBash|Edit\t7\t-\nhook\tsecret\tsafety\tPreToolUse\tBash\t5\t-\nlevel\tcore\tcore\tx\noption\tenabled\tboolean\ttrue\tEnabled\tOn "quoted" off.\noption\tgroup_x\tboolean\tfalse\tGroup X\tGroup x.\noption\tgroup_safety\tboolean\tfalse\tSafety\tSafety group.\noption\tlist\tstring[]\t\tList\tA list.\n' > "$F/install/options.tsv"
  for s in alpha beta gamma secret; do printf '%s\n%s\n' ': stub' "$GL" > "$F/scripts/$s.sh"; done
  for s in x y; do printf '%s\n%s\n' ': stub' "$GL" > "$F/scripts/$s.sh"; done
  echo 'scripts/secret.sh export-ignore' > "$F/.gitattributes"
  printf '{"name":"fx","version":"1","author":{"name":"a"},"userConfig":{"old":1}}\n' > "$F/.claude-plugin/plugin.json"
  git -C "$F" init -q 2>/dev/null
}
F="$T/fx"; mkfix "$F"
rc 1 "fixture before first write: drift" gen --check "$F"
rc 0 "fixture --write" gen --write "$F"
rc 0 "fixture --check after write" gen --check "$F"
jq -e '.hooks.PreToolUse | length == 2 and (map(.hooks[0].command) | all(test("secret") | not))' "$F/hooks/hooks.json" >/dev/null && ok "export-ignored script not wired" || bad "export-ignored script wired"
jq -e '.hooks.SessionStart[0] | has("matcher") | not' "$F/hooks/hooks.json" >/dev/null && ok "empty matcher omitted" || bad "empty matcher kept"
jq -e '.hooks.PreToolUse[0].hooks[0].command == "sh \"${CLAUDE_PLUGIN_ROOT}/scripts/beta.sh\""' "$F/hooks/hooks.json" >/dev/null && ok "CLAUDE_PLUGIN_ROOT literal" || bad "command text wrong"
# d. shapes
jq -e '.userConfig.enabled.default == true and .userConfig.group_x.default == false and .userConfig.enabled.type == "boolean"' "$F/.claude-plugin/plugin.json" >/dev/null && ok "boolean defaults are JSON booleans" || bad "boolean default shape"
jq -e '.userConfig.list == {"type":"string","multiple":true,"title":"List","description":"A list."}' "$F/.claude-plugin/plugin.json" >/dev/null && ok "string[] multiple, no default" || bad "string[] shape"
jq -e '.userConfig.enabled.description == "On \"quoted\" off."' "$F/.claude-plugin/plugin.json" >/dev/null && ok "double quote survives" || bad "double quote lost"
# e. preservation
jq -S 'del(.userConfig)' "$F/.claude-plugin/plugin.json" > "$T/after"; printf '{"name":"fx","version":"1","author":{"name":"a"}}' | jq -S . > "$T/before"
cmp -s "$T/before" "$T/after" && ok "non-userConfig fields preserved" || bad "non-userConfig fields changed"
# b. drift
awk -F'\t' -v OFS='\t' '$1 == "option" && $2 == "group_x" && $4 == "false" { $4 = "true" } 1' "$F/install/options.tsv" > "$T/o" && cp "$T/o" "$F/install/options.tsv"
rc 1 "changed default: --check exits 1" gen --check "$F"
grep -q plugin.json "$T/out" && ok "drift names plugin.json" || bad "drift output lacks plugin.json"
rc 0 "write then check" sh -c "$SH '$GEN' --write '$F' && $SH '$GEN' --check '$F'"
awk -F'\t' -v OFS='\t' '$1 == "hook" && $2 == "beta" { $6 = 9 } 1' "$F/install/options.tsv" > "$T/o" && cp "$T/o" "$F/install/options.tsv"
rc 1 "changed timeout: --check exits 1" gen --check "$F"
grep -q hooks.json "$T/out" && ok "drift names hooks.json" || bad "drift output lacks hooks.json"
# c. absent script
mkfix "$F"; rm "$F/scripts/beta.sh"
rc 2 "absent non-ignored script with .gitattributes: exit 2" gen --write "$F"
rm -rf "$F/.gitattributes" "$F/.git"
rc 0 "absent script, no .gitattributes, no git: skipped" gen --write "$F"
jq -e '[.hooks[][]|.hooks[].command|select(test("beta"))]|length == 0' "$F/hooks/hooks.json" >/dev/null && ok "absent script not wired" || bad "absent script wired"
# d. bad input: scripts x and y exist (gated), so exit 2 can only come from the validator; assert its text
while IFS='@' read -r row msg; do
  [ -n "$row" ] || continue
  mkfix "$F"; printf "$row\n" >> "$F/install/options.tsv"
  rc 2 "bad row exits 2: $msg" gen --check "$F"
  grep -q "$msg" "$T/out" && ok "message names: $msg" || bad "message lacks: $msg"
done <<'EOC'
option\tbad-key\tboolean\ttrue\tT\tD@bad key
option\tk\tnumber\t1\tT\tD@unknown type
option\tk\tboolean\ttrue\t\tD@empty title
hook\tx y\tcore\tStop\t\t5\t-@invalid
hook\tx\tcore\tStop\t\t0\t-@invalid
hook\tx\tcore\tStop\t\t5\t-\textra@more than 7 fields
option\tk\tboolean\ttrue\tT\tD\textra@more than 6 fields
hook\tx\tcore\tStop\t\t5\t-\nhook\tx\tcore\tStop\t\t5\t-@duplicate hook id x
hook\tx\tnogrp\tStop\t\t5\t-@no option group_nogrp
hook\tx\tcore\tStop\t\t5@needs 7 fields
hook\tx\tcore\tStop\t\t5\ta b@requires must be
hook\tx\tcore\tStop\t\t5\tx,,y@requires must be
hook\tx\tcore\tStop\t\t5\t,x@requires must be
hook\tx\tcore\tStop\t\t5\tnope@requires unknown hook id nope
hook\tx\tcore\tStop\t\t5\tx@requires itself
EOC
# requires column: a valid list changes nothing in the generated hooks.json
mkfix "$F"; rc 0 "baseline write" gen --write "$F"; cp "$F/hooks/hooks.json" "$T/hj0"
awk -F'\t' -v OFS='\t' '$1 == "hook" && $2 == "beta" { $7 = "alpha,gamma" } 1' "$F/install/options.tsv" > "$T/o" && cp "$T/o" "$F/install/options.tsv"
rc 0 "valid requires list accepted" gen --write "$F"
cmp -s "$T/hj0" "$F/hooks/hooks.json" && ok "requires column not emitted in hooks.json" || bad "requires column changed hooks.json"
# f. kit gate call required for every wired row
mkfix "$F"; printf 'hook\tdelta\tsafety\tPreToolUse\tBash\t5\t-\nhook\tepsilon\tsafety\tPreToolUse\tBash\t5\t-\n' >> "$F/install/options.tsv"
echo ': stub' > "$F/scripts/delta.sh"; printf '%s\n# %s\n' ': stub' "$GL" > "$F/scripts/epsilon.sh"
rc 2 "ungated and commented-out gate lines: exit 2" gen --check "$F"
grep -q 'does not call the kit gate: delta epsilon' "$T/out" && ok "refusal names every ungated id" || bad "refusal text wrong"
rc 2 "ungated: --write also exits 2" gen --write "$F"
printf '%s\n%s\n' ': stub' "$GL" > "$F/scripts/delta.sh"; printf '%s\n%s\n' ': stub' "$GL" > "$F/scripts/epsilon.sh"
rc 0 "gate lines present: --write" gen --write "$F"
jq -e '[.hooks[][]|.hooks[].command|select(test("delta|epsilon"))]|length == 2' "$F/hooks/hooks.json" >/dev/null && ok "gated rows wired" || bad "gated rows not wired"

echo "-- $pass passed, $failn failed ($SH)"
if [ -z "${GENPM_SH:-}" ] && command -v dash >/dev/null 2>&1; then
  echo "-- re-run under dash"
  GENPM_SH=dash dash "$DIR/gen-plugin-manifests.selfcheck.sh" || failn=1
fi
[ "$failn" = 0 ] && { echo "PASS gen-plugin-manifests ($SH)"; exit 0; } || { echo "FAIL gen-plugin-manifests ($SH)"; exit 1; }

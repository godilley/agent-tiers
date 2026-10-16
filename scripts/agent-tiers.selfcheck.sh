#!/usr/bin/env sh
# kit-scope: shared
# Self-check for scripts/agent-tiers (the install/configure/remove/status CLI). Runnable:
#   sh scripts/agent-tiers.selfcheck.sh        CLI_SH=dash dash scripts/agent-tiers.selfcheck.sh
# Every case runs in a sandbox: a temp HOME and CLAUDE_CONFIG_DIR, a kit copy made from scripts,
# install, skills, agents, commands (+ .claude-plugin), kit-gate.sh pointed at an empty managed dir.
# Most cases stub install-flat.sh (logs its args) and detect-env.sh (fixed proposals); some run the
# real engine, and a few write their own install-flat.sh stub variant into the sandbox kit copy.
# Expected values are derived from install/options.tsv, never hardcoded.
set -u
LC_ALL=C; export LC_ALL
# Real-engine cases skip install-flat.sh's post-wire hook proof loop (slow, re-run per install);
# install-flat.selfcheck.sh case H1 is the case that proves the loop still runs.
AGENT_TIERS_TEST_SKIP_HOOK_PROOF=1; export AGENT_TIERS_TEST_SKIP_HOOK_PROOF
ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)"
command -v jq >/dev/null 2>&1 || { echo "SKIP agent-tiers: jq absent"; exit 0; }
CLI_SH="${CLI_SH:-sh}"
TSV="$ROOT/install/options.tsv"
CLI_SRC="$ROOT/scripts/agent-tiers"
pass=0; nfail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { nfail=$((nfail + 1)); printf 'FAIL %s\n' "$1"; }

# lint_effects FILE: fails on a raw effect outside the four effect functions. Strings, comments and
# heredoc bodies are blanked first (a command substitution inside double quotes stays code).
lint_effects() {
  awk '
  BEGIN {
    split("rm ln cp mv mkdir rmdir chmod chown touch tee curl wget dd truncate mktemp sh bash dash eval exec install command env xargs nohup unlink find perl python python3 trap source .", a, " ")
    for (k in a) forb[a[k]] = 1
    split("if then do else elif while until", b, " ")
    for (k in b) kw[b[k]] = 1
    sq = 0; sp = 0; hd = ""; np = 0; skip = 0; cont = 0; bad = 0; endpos = 1; endcmd = ""
  }
  function nexthd(   j) {
    if (np > 0) { hd = pend[1]; hdtab = ptab[1]; for (j = 1; j < np; j++) { pend[j] = pend[j + 1]; ptab[j] = ptab[j + 1] }; np-- }
  }
  function report(msg) { printf "lint: line %d: %s\n", NR, msg; bad = 1 }
  function check(L, first,   s, i, r, t, n, toks, j, cmdpos, cmd) {
    s = L
    while ((i = index(s, ">")) > 0) {
      r = substr(s, i + 1)
      if (substr(r, 1, 1) == ">" || substr(r, 1, 1) == "|") r = substr(r, 2)
      sub(/^[ \t]+/, "", r)
      if (!(r ~ /^\/dev\/null([^A-Za-z0-9_\/.-]|$)/ || r ~ /^&[0-9]/)) report("output redirection")
      s = r
    }
    t = L
    gsub(/\$\(/, " ( ", t)
    gsub(/[;&|`{}!()]/, " ; ", t)
    n = split(t, toks, /[ \t]+/)
    cmdpos = first; cmd = (first ? "" : endcmd)
    for (j = 1; j <= n; j++) {
      if (toks[j] == "") continue
      if (toks[j] == ";") { cmdpos = 1; cmd = ""; continue }
      if (cmdpos && (toks[j] in kw)) continue
      if (cmdpos && toks[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
      if (cmdpos) {
        # `command -v X` / `command -V X` is a lookup, not an effect
        if (toks[j] == "command" && j < n && toks[j + 1] ~ /^-[vV]$/) { cmd = "command"; cmdpos = 0; continue }
        if (toks[j] in forb) report("raw effect command: " toks[j])
        cmd = toks[j]; cmdpos = 0; continue
      }
      if (cmd == "sed" && (toks[j] ~ /^-[A-Za-z]*i/ || toks[j] ~ /^--in-place/)) report("sed -i")
    }
    endpos = cmdpos; endcmd = cmd
  }
  {
    line = $0
    if (hd != "") { t = line; if (hdtab) sub(/^\t+/, "", t); if (t == hd) { hd = ""; nexthd() }; next }
    if (skip) { if (line == "}") skip = 0; next }
    if (!sq && sp == 0 && !cont && line ~ /^(edit_settings|remove_path|run_engine|run_reader)\(\) *\{/) {
      fn = line; sub(/\(.*/, "", fn)
      if (fn in seenfn) report("duplicate effect function definition: " fn)
      else { seenfn[fn] = 1; skip = 1; next }
    }
    out = ""; n = length(line); i = 1; first = (cont ? endpos : 1); cnext = 0
    while (i <= n) {
      c = substr(line, i, 1)
      if (sq) { if (c == "\047") sq = 0; out = out "_"; i++; continue }
      top = (sp > 0 ? st[sp] : "C")
      if (top == "D") {
        if (c == "\\") { out = out "__"; i += 2; continue }
        if (c == "\"") { sp--; out = out "_"; i++; continue }
        if (c == "$" && substr(line, i + 1, 1) == "(") { sp++; st[sp] = "C"; dep[sp] = 0; out = out "$("; i += 2; continue }
        if (c == "`") { sp++; st[sp] = "B"; dep[sp] = 0; out = out "`"; i++; continue }
        out = out "_"; i++; continue
      }
      if (c == "\\") { if (i == n) { cnext = 1; i++; continue }; out = out "__"; i += 2; continue }
      if (c == "\047") { sq = 1; out = out "_"; i++; continue }
      if (c == "\"") { sp++; st[sp] = "D"; out = out "_"; i++; continue }
      if (c == "`") { if (sp > 0 && st[sp] == "B") sp--; else { sp++; st[sp] = "B"; dep[sp] = 0 }; out = out "`"; i++; continue }
      if (c == "#") { p = (i == 1 ? " " : substr(line, i - 1, 1)); if (p ~ /[ \t;&|()`]/) break }
      if (c == "<" && substr(line, i + 1, 1) == "<" && substr(line, i + 2, 1) != "<") {
        r = substr(line, i + 2); used = 2; tb = 0
        if (substr(r, 1, 1) == "-") { tb = 1; r = substr(r, 2); used++ }
        if (match(r, /^[ \t]+/)) { used += RLENGTH; r = substr(r, RLENGTH + 1) }
        q = substr(r, 1, 1); w = ""
        if (q == "\047" || q == "\"") { e = index(substr(r, 2), q); if (e > 0) { w = substr(r, 2, e - 1); used += e + 1 } }
        else if (match(r, /^[A-Za-z0-9_]+/)) { w = substr(r, 1, RLENGTH); used += RLENGTH }
        if (w != "") { np++; pend[np] = w; ptab[np] = tb }
        for (k = 0; k < used; k++) out = out " "
        i += used; continue
      }
      if (c == "(" && sp > 0) dep[sp]++
      if (c == ")" && sp > 0 && st[sp] == "C") { if (dep[sp] > 0) dep[sp]--; else { sp--; out = out ")"; i++; continue } }
      out = out c; i++
    }
    cont = cnext
    check(out, first)
    if (np > 0 && hd == "") nexthd()
  }
  END { exit bad }
  ' "$1"
}

# options.tsv readers (the expected values come from here)
groups=$(awk -F'\t' '$1 == "option" && $2 ~ /^group_/ { sub(/^group_/, "", $2); print $2 }' "$TSV" | tr '\n' ' ')
levels=$(awk -F'\t' '$1 == "level" { print $2 }' "$TSV" | tr '\n' ' ')
all_ids=$(awk -F'\t' '$1 == "hook" { print $2 }' "$TSV" | tr '\n' ' ')
hooks_of() { awk -F'\t' -v g="$1" '$1 == "hook" && $3 == g { print $2 }' "$TSV" | tr '\n' ' '; }
level_groups() {
  lr=$(awk -F'\t' -v l="$1" '$1 == "level" && $2 == l { print $3; exit }' "$TSV")
  case ",$lr," in *,\*,*) printf '%s' "$groups"; return ;; esac
  lo=""; for x in $(printf '%s' "$lr" | tr ',' ' '); do case " $groups " in *" $x "*) lo="$lo $x" ;; esac; done
  printf '%s' "$lo"
}
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
with_flags_for() { # group list -> sorted --with-<id> lines (scripts present only)
  for g in $1; do for id in $(hooks_of "$g"); do
    in_list "$id" "${2:-}" && continue
    [ -f "$ROOT/scripts/$id.sh" ] && printf -- '--with-%s\n' "$id"
  done; done | sort
}

W=""
T=""
cleanup() { [ -n "$T" ] && [ -d "$T" ] && rm -rf "$T"; T=""; [ -n "$W" ] && rm -rf "$W"; W=""; }
trap 'cleanup' EXIT
trap 'cleanup; exit 1' INT TERM

# new_sandbox stub|real
new_sandbox() {
  cleanup
  T=$(mktemp -d) || { echo "FAIL: mktemp"; exit 1; }
  HOME="$T"; CLAUDE_CONFIG_DIR="$T/.claude"; AGENT_TIERS_GUARDS_LOG="$T/guards.log"
  export HOME CLAUDE_CONFIG_DIR AGENT_TIERS_GUARDS_LOG
  unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID AGENT_TIERS_NOTIFY_TERMINAL AGENT_TIERS_NOTIFY_FOCUS_CMD
  K="$T/.claude/agent-tiers"; S="$T/.claude/settings.json"; LOG="$T/engine.log"
  mkdir -p "$K" "$T/managed"
  for d in scripts install skills agents commands .claude-plugin; do
    [ -e "$ROOT/$d" ] && cp -R "$ROOT/$d" "$K/"
  done
  sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$ROOT/scripts/kit-gate.sh" > "$K/scripts/kit-gate.sh"
  grep -qxF "_kg_managed='$T/managed'" "$K/scripts/kit-gate.sh" || { echo "FAIL: _kg_managed not rewritten"; exit 1; }
  if [ "$1" = real ]; then
    sed "s|^IF_MANAGED=.*|IF_MANAGED='$T/managed'|" "$ROOT/scripts/install-flat.sh" > "$T/if.tmp" && cat "$T/if.tmp" > "$K/scripts/install-flat.sh"
    grep -qxF "IF_MANAGED='$T/managed'" "$K/scripts/install-flat.sh" || { echo "FAIL: IF_MANAGED not rewritten"; exit 1; }
  fi
  if [ "$1" = stub ]; then
    printf '%s\n' '#!/bin/sh' \
      'printf "call:%s\n" "$*" >> "$HOME/engine.log"' \
      'mkdir -p "$CLAUDE_CONFIG_DIR/commands" && : > "$CLAUDE_CONFIG_DIR/commands/agent-tiers-stub.md"' \
      'exit 0' > "$K/scripts/install-flat.sh"
    printf '%s\n' '#!/bin/sh' "printf '%s\\n' os=linux \\" \
      "  'reason.AGENT_TIERS_NOTIFY_FOCUS_CMD=no focus tool found' \\" \
      "  'propose.AGENT_TIERS_NOTIFY_TERMINAL=kitty' 'reason.AGENT_TIERS_NOTIFY_TERMINAL=parent process is kitty' \\" \
      "  'propose.AGENT_TIERS_BADGE_GLYPHS=nerd' 'reason.AGENT_TIERS_BADGE_GLYPHS=a nerd font is installed'" \
      > "$K/scripts/detect-env.sh"
  fi
}
cli() { "$CLI_SH" "$K/scripts/agent-tiers" "$@"; }
opts() { [ -f "$S" ] || { printf '{}'; return; }; jq -c '[.pluginConfigs // {} | to_entries[] | select(.key | startswith("agent-tiers@")) | .value.options][0] // {}' "$S"; }
optv() { opts | jq -r --arg k "$1" 'if has($k) then .[$k] | tojson else "absent" end'; }
withs() { grep -o -- '--with-[A-Za-z0-9_-]*' "$LOG" 2>/dev/null | sort; }

# 1. lint
r=$(lint_effects "$CLI_SRC" 2>&1); rc=$?
if [ "$rc" = 0 ]; then ok "1 lint passes on the CLI"; else bad "1 lint passes on the CLI: $r"; fi
W=$(mktemp -d) || exit 1
BT='`'
for planted in 'rm -f "$HOME/x"' 'echo x > "$HOME/y"' 'curl -s https://example.invalid/x' \
  '[ -L "$p" ] && \
  rm -f "$p"' \
  "x=\"${BT}rm -f /tmp/x${BT}\"" 'command rm -f x' "printf '%s\\n' \"\$p\" | xargs rm" 'unlink "$p"' \
  'find "$cfg" -name x -delete' '. "$root/scripts/x.sh"' 'source x' "trap 'rm -f \"\$settings\"' EXIT"; do
  { cat "$CLI_SRC"; printf 'planted() {\n  %s\n}\n' "$planted"; } > "$W/p"
  if lint_effects "$W/p" >/dev/null 2>&1; then bad "1 lint flags planted: $planted"; else ok "1 lint flags planted: $planted"; fi
done
{ cat "$CLI_SRC"; printf 'edit_settings() {\n  :\n}\n'; } > "$W/p"
if lint_effects "$W/p" >/dev/null 2>&1; then bad "1 lint flags a duplicate effect function"; else ok "1 lint flags a duplicate effect function"; fi
{ cat "$CLI_SRC"; printf 'planted() {\n  echo "rm -rf now > x"\n}\n'; } > "$W/p"
if lint_effects "$W/p" >/dev/null 2>&1; then ok "1 lint passes a string-only planted line"; else bad "1 lint passes a string-only planted line"; fi
rm -rf "$W"

# 2. install --yes, no level: core fallback (every absent group stored as its effective state, false here)
new_sandbox stub
cli install --yes >/dev/null 2>&1; rc=$?
good=1; for g in $groups; do [ "$(optv "group_$g")" = false ] || good=0; done
if [ "$rc" = 0 ] && [ "$good" = 1 ] && [ -f "$LOG" ] && ! grep -q -- '--with' "$LOG" \
   && ! { [ -f "$S" ] && grep -q 'AGENT_TIERS_' "$S"; }; then
  ok "2 install --yes (no level): engine without --with, every group stored false, no env"
else bad "2 install --yes (no level) rc=$rc"; fi

# 3. each level
for L in $levels; do
  new_sandbox stub
  cli install --yes --level "$L" >/dev/null 2>&1; rc=$?
  lg=$(level_groups "$L"); good=1
  for g in $groups; do
    v=$(optv "group_$g")
    if in_list "$g" "$lg"; then [ "$v" = true ] || good=0; else [ "$v" = false ] || good=0; fi
  done
  [ "$(withs)" = "$(with_flags_for "$lg")" ] || good=0
  grep -q -- '--without-' "$LOG" && good=0
  if [ "$rc" = 0 ] && [ "$good" = 1 ]; then ok "3 install --yes --level $L: groups and --with set"; else bad "3 install --yes --level $L rc=$rc opts=$(opts)"; fi
done

# 4. --set over a level; bad key
new_sandbox stub
cli install --yes --level recommended --set group_memory=true --set disabled_hooks=memory-write-gate >/dev/null 2>&1; rc=$?
lg="$(level_groups recommended) memory"
if [ "$rc" = 0 ] && [ "$(optv group_memory)" = true ] && [ "$(optv disabled_hooks)" = '["memory-write-gate"]' ] \
   && ! grep -q -- '--with-memory-write-gate' "$LOG" && [ "$(withs)" = "$(with_flags_for "$lg" memory-write-gate)" ]; then
  ok "4 --set group_memory + disabled_hooks"
else bad "4 --set group_memory + disabled_hooks rc=$rc opts=$(opts)"; fi
cp "$S" "$T/before"; rm -f "$LOG"
cli install --yes --level core --set bogus=1 >/dev/null 2>&1; rc=$?
if [ "$rc" != 0 ] && cmp -s "$S" "$T/before" && [ ! -f "$LOG" ]; then ok "4 --set bogus=1 refused, nothing run or written"; else bad "4 --set bogus=1 rc=$rc"; fi

# 5. configure after install
new_sandbox stub
cli install --yes --level core >/dev/null 2>&1
rm -f "$LOG"
cli configure --yes --set group_safety=true >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ "$(optv group_safety)" = true ] && [ "$(withs)" = "$(with_flags_for safety)" ]; then
  ok "5 configure group_safety=true runs the engine with the safety ids"
else bad "5 configure group_safety=true rc=$rc"; fi
rm -f "$LOG"
cli configure --yes --set group_safety=false >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ "$(optv group_safety)" = false ] && [ ! -f "$LOG" ]; then
  ok "5 configure group_safety=false does not run the engine"
else bad "5 configure group_safety=false rc=$rc"; fi

# 6. loosening rule
new_sandbox stub
mkdir -p "$T/.claude/commands"; : > "$T/.claude/commands/agent-tiers-x.md"
jq -n '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "sh \"/x/scripts/worktree-guard.sh\""}]}]}}' > "$S"
cli install --yes --level core >/dev/null 2>&1; rc=$?
wg=$(awk -F'\t' '$1 == "hook" && $2 == "worktree-guard" { print $3 }' "$TSV")
good=1; [ -n "$wg" ] || good=0
for g in $groups; do [ "$(optv "group_$g")" = false ] || good=0; done
if [ "$rc" = 0 ] && [ "$good" = 1 ]; then ok "6 wired guard group set false, every other group false too"; else bad "6 loosening rc=$rc opts=$(opts)"; fi

# 7. status after 6
out=$(cli status 2>&1); rc=$?
good=1
for g in $groups; do printf '%s\n' "$out" | grep -q "^  $g " || good=0; done
printf '%s\n' "$out" | grep -q '^agent-tiers: ' || good=0
if [ "$rc" = 0 ] && [ "$good" = 1 ]; then ok "7 status lists groups and the kit-gate summary"; else bad "7 status rc=$rc: $out"; fi

# 8. backup cap
new_sandbox stub
i=1
while [ "$i" -le 7 ]; do
  [ "$i" = 7 ] && cp "$S" "$T/before-last"
  cli configure --yes --set "AGENT_TIERS_NOTIFY_TERMINAL=t$i" >/dev/null 2>&1
  i=$((i + 1))
done
nb=$(ls -1 "$S".bak-* 2>/dev/null | wc -l | tr -d ' ')
newest=$(ls -1 "$S".bak-* 2>/dev/null | sort -r | head -n 1)
modes_ok=1
for b in "$S".bak-*; do
  case "$(ls -l "$b" | cut -c1-10)" in -rw-------) ;; *) modes_ok=0 ;; esac
  printf '%s\n' "${b##*/}" | grep -Eqx 'settings\.json\.bak-[0-9]{8}-[0-9]{6}(-[2-9])?' || modes_ok=0
done
if [ "$nb" -le 5 ] && [ "$modes_ok" = 1 ] && [ -n "$newest" ] && cmp -s "$newest" "$T/before-last" \
   && [ "$(jq -r '.env.AGENT_TIERS_NOTIFY_TERMINAL' "$S")" = t7 ]; then
  ok "8 backups capped at 5, mode 600, named bak-YYYYmmdd-HHMMSS[-N], newest = settings before the last run"
else bad "8 backup cap nb=$nb newest=$newest"; fi

# 9. detected env
new_sandbox stub
cli install --level core >/dev/null 2>&1 <<'EOF'
y
n
n
y
EOF
rc=$?
if [ "$rc" = 0 ] && [ "$(jq -c '.env' "$S")" = '{"AGENT_TIERS_NOTIFY_TERMINAL":"kitty"}' ]; then
  ok "9 interactive: accepted proposal written, declined one not"
else bad "9 interactive env rc=$rc"; fi
new_sandbox stub
out=$(cli install --yes --level core 2>&1); rc=$?
if [ "$rc" = 0 ] && ! { [ -f "$S" ] && grep -q AGENT_TIERS_ "$S"; } && printf '%s\n' "$out" | grep -q 'to accept: --set AGENT_TIERS_NOTIFY_TERMINAL=kitty'; then
  ok "9 --yes writes no proposal, prints the hint"
else bad "9 --yes proposals rc=$rc"; fi
cli install --yes --level core --set 'AGENT_TIERS_BADGE_GLYPHS=a b' >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ "$(jq -r '.env.AGENT_TIERS_BADGE_GLYPHS' "$S")" = 'a b' ]; then ok "9 --set env key writes"; else bad "9 --set env key rc=$rc"; fi

# 10. level step first; EOF aborts
new_sandbox stub
ncust=$(( $(printf '%s' "$levels" | wc -w) + 1 ))
out=$(printf '%s\nd\nn\nn\nn\nn\n' "$ncust" | cli install 2>&1)
good=1; last=0
for L in $levels; do
  sm=$(awk -F'\t' -v l="$L" '$1 == "level" && $2 == l { print $4; exit }' "$TSV")
  ln_=$(printf '%s\n' "$out" | grep -nF -- "$sm" | head -n 1 | cut -d: -f1)
  [ -n "$ln_" ] || { good=0; continue; }
  [ "$ln_" -gt "$last" ] && last=$ln_
done
gt=$(awk -F'\t' '$1 == "option" && $2 ~ /^group_/ { print $5; exit }' "$TSV")
gl=$(printf '%s\n' "$out" | grep -nF -- "$gt" | head -n 1 | cut -d: -f1)
if [ "$good" = 1 ] && [ -n "$gl" ] && [ "$last" -lt "$gl" ] && [ ! -f "$LOG" ]; then ok "10 level step (all summaries) before the group menu"; else bad "10 level step order last=$last group=$gl"; fi
printf '{"keep": 1}\n' > "$S"; cp "$S" "$T/before"
printf '%s\n' "$ncust" | cli install >/dev/null 2>&1; rc=$?
if [ "$rc" != 0 ] && cmp -s "$S" "$T/before" && [ ! -f "$LOG" ]; then ok "10 EOF mid-run aborts, nothing written or run"; else bad "10 EOF rc=$rc"; fi

# 11. byte preservation
new_sandbox stub
jq . > "$S" <<'EOF'
{"permissions": {"allow": ["Bash(ls:*)"], "deny": []},
 "env": {"OTHER_VAR": "keep me"},
 "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo hi", "timeout": 5}]}]},
 "pluginConfigs": {"other@market": {"options": {"x": true}}},
 "note": "caf\u00e9 \u2603",
 "ratio": 1.25}
EOF
cp "$S" "$T/fixture"
cli install --yes --level recommended --set AGENT_TIERS_NOTIFY_TERMINAL=x >/dev/null 2>&1; rc=$?
jq 'del(.pluginConfigs["agent-tiers@agent-tiers"]) | del(.env.AGENT_TIERS_NOTIFY_TERMINAL)' "$S" > "$T/stripped"
if [ "$rc" = 0 ] && grep -q '"agent-tiers@agent-tiers"' "$S" && cmp -s "$T/stripped" "$T/fixture"; then
  ok "11 unrelated settings bytes preserved"
else bad "11 byte preservation rc=$rc"; fi

# 12. remove, flat, real engine
new_sandbox real
mkdir -p "$T/bin" "$T/.claude/skills/other"
jq -n '{permissions: {allow: ["Bash(ls:*)"]}, env: {OTHER_VAR: "keep"}}' > "$S"
cli install --yes --level core --set enabled=true --set AGENT_TIERS_NOTIFY_TERMINAL=x >"$T/out12a" 2>&1; rc1=$?
pre=0; [ -L "$T/.claude/skills/agent-tiers" ] && [ -L "$T/bin/agent-tiers-share" ] && grep -q 'agent-tiers@' "$S" && pre=1
cli remove --yes >"$T/out12b" 2>&1; rc2=$?
good=1
for d in "$K"/skills/*/; do [ -L "$T/.claude/skills/$(basename "$d")" ] && good=0; done
for a in "$K"/agents/*.md; do [ -L "$T/.claude/agents/$(basename "$a")" ] && good=0; done
for c in "$T"/.claude/commands/agent-tiers-*.md; do [ -e "$c" ] && good=0; done
[ -e "$T/bin/agent-tiers-share" ] && good=0
for id in $all_ids; do
  [ "$(jq --arg n "/scripts/$id.sh" '[.. | objects | .command? | strings | select(contains($n))] | length' "$S")" = 0 ] || good=0
done
grep -q 'agent-tiers@' "$S" && good=0
for k in AGENT_TIERS_NOTIFY_FOCUS_CMD AGENT_TIERS_NOTIFY_TERMINAL AGENT_TIERS_BADGE_GLYPHS; do
  [ "$(jq --arg k "$k" '.env // {} | has($k)' "$S")" = false ] || good=0
done
[ -d "$T/.claude/skills/other" ] || good=0
[ "$(jq -c '.permissions' "$S")" = '{"allow":["Bash(ls:*)"]}' ] && [ "$(jq -r '.env.OTHER_VAR' "$S")" = keep ] || good=0
if [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ "$pre" = 1 ] && [ "$good" = 1 ]; then
  ok "12 remove (flat, real engine) leaves no kit artifact, keeps unrelated ones"
else bad "12 remove flat rc=$rc1/$rc2 pre=$pre good=$good"; sed 's/^/    /' "$T/out12b" | tail -n 20; fi

# 13. remove, plugin only
new_sandbox stub
jq -n '{enabledPlugins: {"agent-tiers@m": true}, pluginConfigs: {"agent-tiers@m": {options: {enabled: true}}, "other@x": {options: {}}}}' > "$S"
out=$(cli remove --yes 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '/plugin uninstall agent-tiers@m' \
   && [ "$(jq -c '.pluginConfigs' "$S")" = '{"other@x":{"options":{}}}' ] && [ ! -f "$LOG" ]; then
  ok "13 remove (plugin only): prints /plugin uninstall, drops the entry, no engine"
else bad "13 remove plugin rc=$rc"; fi

# 14. no fzf without a terminal
new_sandbox stub
mkdir -p "$T/fakebin"
printf '#!/bin/sh\n: > "%s/fzf-ran"\nexit 1\n' "$T" > "$T/fakebin/fzf"; chmod +x "$T/fakebin/fzf"
printf '1\nn\nn\nn\nn\n' | PATH="$T/fakebin:$PATH" cli install >/dev/null 2>&1
if [ ! -e "$T/fzf-ran" ]; then ok "14 fzf never invoked without a terminal"; else bad "14 fzf invoked"; fi

# 15. invalid JSON settings
new_sandbox stub
printf '{"bad": ' > "$S"; cp "$S" "$T/before"
cli install --yes --level recommended >/dev/null 2>&1; rc=$?
if [ "$rc" != 0 ] && [ ! -f "$LOG" ] && cmp -s "$S" "$T/before"; then ok "15 invalid settings.json refused, unchanged"; else bad "15 invalid JSON rc=$rc"; fi
mkdir -p "$T/.claude/commands"; : > "$T/.claude/commands/agent-tiers-x.md"
for c in "configure --yes --set group_safety=true" "remove --yes"; do
  # shellcheck disable=SC2086
  cli $c >/dev/null 2>&1; rc=$?
  if [ "$rc" != 0 ] && [ ! -f "$LOG" ] && cmp -s "$S" "$T/before" && [ -e "$T/.claude/commands/agent-tiers-x.md" ]; then
    ok "15 invalid settings.json refused by ${c%% *}"; else bad "15 invalid JSON ${c%% *} rc=$rc"; fi
done

# 16. a stored false outside the chosen level stays false (flat: absent would mean on)
new_sandbox stub
cli install --yes --level recommended >/dev/null 2>&1
cli configure --yes --set group_safety=false >/dev/null 2>&1
cli configure --yes --level core >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ "$(optv group_safety)" = false ]; then ok "16 configure --level core keeps a stored group_safety=false"; else bad "16 stored false rc=$rc opts=$(opts)"; fi

# 17. configure wires hooks of groups already true (re-enabling a disabled hook)
new_sandbox stub
cli install --yes --level recommended --set disabled_hooks=worktree-guard >/dev/null 2>&1
rm -f "$LOG"
cli configure --yes --set disabled_hooks= >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q -- '--with-worktree-guard' "$LOG" 2>/dev/null \
   && [ "$(withs)" = "$(with_flags_for "$(level_groups recommended)")" ] && [ "$(optv disabled_hooks)" = '[]' ]; then
  ok "17 configure runs the engine for unwired hooks of groups already true"
else bad "17 configure re-enable rc=$rc"; fi

# 18. remove stops when a kit hook stays wired (a foreign row install-flat.sh does not own)
new_sandbox real
cli install --yes --level core --set enabled=true >/dev/null 2>&1
jq '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{matcher: "Bash", hooks: [{type: "command", command: "sh \"/elsewhere/scripts/worktree-guard.sh\""}]}])' "$S" > "$T/s2" && cat "$T/s2" > "$S"
o1=$(opts)
cli remove --yes >"$T/out18" 2>&1; rc=$?
if [ "$rc" != 0 ] && [ -L "$T/.claude/skills/agent-tiers" ] && [ "$(opts)" = "$o1" ] && [ "$o1" != '{}' ] \
   && grep -q 'still wired.*worktree-guard' "$T/out18"; then
  ok "18 remove stops on a still-wired foreign kit row, links and options untouched"
else bad "18 remove foreign row rc=$rc"; tail -n 5 "$T/out18" | sed 's/^/    /'; fi

# 19. control byte in an env value
new_sandbox stub
printf '{}\n' > "$S"; cp "$S" "$T/before"
cli install --yes --level core --set "AGENT_TIERS_BADGE_GLYPHS=$(printf 'a\tb')" >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ] && cmp -s "$S" "$T/before" && [ ! -f "$LOG" ]; then ok "19 control byte in a --set value rejected"; else bad "19 control byte rc=$rc"; fi

# 20. EOF at the Apply prompt (two env proposals and the statusline extra answered, then no answer to Apply)
new_sandbox stub
printf '{"keep": 1}\n' > "$S"; cp "$S" "$T/before"
out=$(printf 'n\nn\nn\n' | cli install --level recommended 2>&1); rc=$?
if [ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'Apply?' && cmp -s "$S" "$T/before" && [ ! -f "$LOG" ]; then
  ok "20 EOF at Apply aborts, nothing written or run"; else bad "20 EOF at Apply rc=$rc"; fi

# 21. a foreign ~/bin/agent-tiers-share (install-flat.sh would replace it): remove and install refuse, real engine
new_sandbox real
mkdir -p "$T/bin"
cli install --yes --level core >/dev/null 2>&1; rc0=$?
rm -f "$T/bin/agent-tiers-share"; printf 'mine\n' > "$T/bin/agent-tiers-share"
cp "$S" "$T/before"
cli remove --yes >"$T/out21" 2>&1; rc=$?
good=1
[ "$(cat "$T/bin/agent-tiers-share")" = mine ] && [ ! -L "$T/bin/agent-tiers-share" ] || good=0
[ ! -L "$T/.claude/skills/agent-tiers" ] || good=0
[ -z "$(jq -r '[.hooks[]?[]?.hooks[]?.command] | map(select(test("/scripts/[a-z0-9-]+[.]sh"))) | .[]' "$S")" ] || good=0
if [ "$rc0" = 0 ] && [ "$rc" = 0 ] && [ "$good" = 1 ]; then
  ok "21 remove succeeds past a foreign ~/bin/agent-tiers-share, file intact, links and hook rows gone"
else bad "21 foreign share remove rc=$rc0/$rc good=$good"; tail -n 5 "$T/out21" | sed 's/^/    /'; fi
cli install --yes --level core >"$T/out21b" 2>&1; rc=$?
if [ "$rc" != 0 ] && [ "$(cat "$T/bin/agent-tiers-share")" = mine ] && grep -q 'would replace .*agent-tiers-share' "$T/out21b"; then
  ok "21 install refuses on a foreign ~/bin/agent-tiers-share, file intact"
else bad "21 foreign share install rc=$rc"; fi

# 22. plugin key: an enabled plugin wins over a leftover, non-enabled pluginConfigs key (no flat install)
new_sandbox stub
jq -n '{enabledPlugins: {"agent-tiers@new": true}, pluginConfigs: {"agent-tiers@old": {options: {enabled: false}}}}' > "$S"
if cli status 2>/dev/null | grep -q '^plugin key: *agent-tiers@new$'; then ok "22 enabled plugin key wins over a leftover entry"; else bad "22 plugin key order"; fi

# 23. malformed tokens and multi-line values rejected before anything runs
new_sandbox stub
printf '{}\n' > "$S"; cp "$S" "$T/before"; good=1
cli install --yes --level '' >/dev/null 2>&1; [ $? = 2 ] || good=0
cli install --yes --level core --set group_=true >/dev/null 2>&1; [ $? = 2 ] || good=0
cli install --yes --level core --set "AGENT_TIERS_NOTIFY_TERMINAL=a
group_safety=true" >/dev/null 2>&1; [ $? = 2 ] || good=0
if [ "$good" = 1 ] && cmp -s "$S" "$T/before" && [ ! -f "$LOG" ]; then ok "23 empty level, empty group, multi-line --set rejected"; else bad "23 malformed input"; fi

# 24. remove, plugin only, with a kit hook row still wired: stops before the options go
new_sandbox stub
jq -n '{enabledPlugins: {"agent-tiers@m": true}, pluginConfigs: {"agent-tiers@m": {options: {enabled: true}}},
  hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "sh \"/x/scripts/worktree-guard.sh\""}]}]}}' > "$S"
cp "$S" "$T/before"
out=$(cli remove --yes 2>&1); rc=$?
if [ "$rc" != 0 ] && cmp -s "$S" "$T/before" && printf '%s\n' "$out" | grep -q 'still wired.*worktree-guard' \
   && [ "$(jq -r '.pluginConfigs["agent-tiers@m"].options.enabled' "$S")" = true ]; then
  ok "24 remove (plugin only) stops on a still-wired kit row, pluginConfigs kept"
else bad "24 plugin-only wired row rc=$rc"; fi

# 25. a symlinked settings.json survives a real install and a real remove
new_sandbox real
printf '{}\n' > "$T/real-settings.json"; ln -s "$T/real-settings.json" "$S"
cli install --yes --level core >/dev/null 2>&1; rc1=$?
l1=0; [ -L "$S" ] && l1=1
cli remove --yes >"$T/out25" 2>&1; rc2=$?
l2=0; [ -L "$S" ] && l2=1
left=0; for id in $all_ids; do grep -q "/scripts/$id[.]sh" "$T/real-settings.json" && left=1; done
if [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ "$l1" = 1 ] && [ "$l2" = 1 ] && [ "$left" = 0 ]; then
  ok "25 symlinked settings.json stays a symlink through install and remove, no kit rows left"
else bad "25 symlinked settings rc=$rc1/$rc2 link=$l1/$l2 left=$left"; tail -n 5 "$T/out25" | sed 's/^/    /'; fi

# 26. remove does not relink, rename or recreate anything
new_sandbox real
cli install --yes --level core >/dev/null 2>&1; rc0=$?
rm -f "$T/.claude/skills/agent-tiers"; mkdir "$T/.claude/skills/agent-tiers"; : > "$T/.claude/skills/agent-tiers/mine"
rm -f "$K/kit-config.md"
cli remove --yes >"$T/out26" 2>&1; rc=$?
left=0; for id in $all_ids; do grep -q "/scripts/$id[.]sh" "$S" && left=1; done
bk=$(ls -d "$T"/.claude/skills/*.bak-* 2>/dev/null | wc -l | tr -d ' ')
if [ "$rc0" = 0 ] && [ "$rc" = 0 ] && [ -f "$T/.claude/skills/agent-tiers/mine" ] && [ "$bk" = 0 ] \
   && [ ! -e "$K/kit-config.md" ] && [ "$left" = 0 ]; then
  ok "26 remove leaves a real skill dir alone, makes no .bak, does not recreate kit-config.md"
else bad "26 remove side effects rc=$rc0/$rc bak=$bk left=$left"; tail -n 5 "$T/out26" | sed 's/^/    /'; fi

# 27. remove with the plugin also enabled (flat + plugin)
new_sandbox real
cli install --yes --level core >/dev/null 2>&1; rc0=$?
jq '.enabledPlugins = {"agent-tiers@m": true}' "$S" > "$T/s2" && cat "$T/s2" > "$S"
cli remove --yes >"$T/out27" 2>&1; rc=$?
left=0; for id in $all_ids; do grep -q "/scripts/$id[.]sh" "$S" && left=1; done
if [ "$rc0" = 0 ] && [ "$rc" = 0 ] && [ "$left" = 0 ] && grep -q '/plugin uninstall' "$T/out27"; then
  ok "27 remove unwires a flat install even with the plugin enabled, points at /plugin uninstall"
else bad "27 remove flat+plugin rc=$rc0/$rc left=$left"; tail -n 5 "$T/out27" | sed 's/^/    /'; fi

# 28. configure with the plugin enabled on a flat install writes options only, never runs the engine
new_sandbox real
cli install --yes --level core >/dev/null 2>&1; rc0=$?
jq '.enabledPlugins = {"agent-tiers@m": true}' "$S" > "$T/s2" && cat "$T/s2" > "$S"
cli configure --yes --set group_safety=true >"$T/out28" 2>&1; rc=$?
left=0; for id in $(hooks_of safety); do grep -q "/scripts/$id[.]sh" "$S" && left=1; done
if [ "$rc0" = 0 ] && [ "$rc" = 0 ] && [ "$(jq -r '.pluginConfigs["agent-tiers@m"].options.group_safety' "$S")" = true ] && [ "$left" = 0 ] \
   && grep -q 'engine: not run (agent-tiers plugin enabled' "$T/out28" && grep -q 'unwire-only' "$T/out28"; then
  ok "28 configure with the plugin enabled on a flat install writes options, wires nothing"
else bad "28 configure flat+plugin rc=$rc0/$rc left=$left"; tail -n 5 "$T/out28" | sed 's/^/    /'; fi

# 29. --dry-run: the --yes plan, nothing written or run; a blocked engine still exits 1
new_sandbox stub
printf '{"keep": 1}\n' > "$S"; c0=$(cksum < "$S")
out=$(cli install --dry-run --level recommended 2>&1); rc=$?
fl=$(printf '%s\n' "$out" | grep '^  engine: install-flat.sh' | grep -o -- '--with-[A-Za-z0-9_-]*' | sort)
nb=$(ls -1 "$S".bak-* 2>/dev/null | wc -l | tr -d ' ')
if [ "$rc" = 0 ] && [ "$(cksum < "$S")" = "$c0" ] && [ "$nb" = 0 ] && [ ! -f "$LOG" ] \
   && printf '%s\n' "$out" | grep -q '^Plan (' && printf '%s\n' "$out" | grep -q 'options.group_safety: absent -> true' \
   && [ "$fl" = "$(with_flags_for "$(level_groups recommended)")" ] \
   && [ "$(printf '%s\n' "$out" | tail -n 1)" = 'dry run: nothing written' ]; then
  ok "29 install --dry-run prints the plan and flags, writes and runs nothing"
else bad "29 dry run rc=$rc nb=$nb"; fi
mkdir -p "$T/bin"; printf 'mine\n' > "$T/bin/agent-tiers-share"
out=$(cli install --dry-run --level core 2>&1); rc=$?
if [ "$rc" = 1 ] && [ "$(cksum < "$S")" = "$c0" ] && [ ! -f "$LOG" ] && printf '%s\n' "$out" | grep -q 'would replace .*agent-tiers-share'; then
  ok "29 --dry-run with a foreign ~/bin/agent-tiers-share exits 1, writes nothing"
else bad "29 dry run foreign share rc=$rc"; fi
good=1
for c in remove status; do
  e=$(cli "$c" --dry-run 2>&1); [ $? = 2 ] || good=0
  printf '%s\n' "$e" | grep -q -- '--dry-run apply to install and configure only' || good=0
done
if [ "$good" = 1 ] && [ "$(cksum < "$S")" = "$c0" ]; then ok "29 remove and status reject --dry-run"; else bad "29 remove/status --dry-run"; fi

# 30. hook dependency: precompact-guard needs authorship-record
dep=precompact-guard; req=authorship-record
dg=$(awk -F'\t' -v i="$dep" '$1 == "hook" && $2 == i { print $3 }' "$TSV")
rqg=$(awk -F'\t' -v i="$req" '$1 == "hook" && $2 == i { print $3 }' "$TSV")
new_sandbox stub
out=$(cli install --yes --level core --set "group_$dg=true" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ -n "$dg" ] && [ -n "$rqg" ] && ! grep -q -- "--with-$dep" "$LOG" \
   && [ "$(withs)" = "$(with_flags_for "$dg" "$dep")" ] \
   && printf '%s\n' "$out" | grep -q "^  not wired: $dep needs $req (group $rqg).*--set group_$rqg=true"; then
  ok "30 $dg without $rqg: $dep not flagged, plan line printed, other $dg hooks flagged"
else bad "30 dependency drop rc=$rc"; fi
new_sandbox stub
cli install --yes --level core --set "group_$dg=true" --set "group_$rqg=true" >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q -- "--with-$dep" "$LOG" && grep -q -- "--with-$req" "$LOG"; then
  ok "30 $dg with $rqg: both flagged"
else bad "30 dependency both rc=$rc"; fi
new_sandbox stub
jq -n '{enabledPlugins: {"agent-tiers@agent-tiers": true}}' > "$S"
out=$(cli configure --yes --set "group_$dg=true" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ ! -f "$LOG" ] && printf '%s\n' "$out" | grep -q "inert: $dep is wired but needs $req"; then
  ok "30 plugin enabled: $dep inert note instead"
else bad "30 dependency plugin note rc=$rc"; fi

new_sandbox stub
out=$(cli install --yes --level core --set "group_$dg=true" --set "disabled_hooks=$req" 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "^  not wired: $dep needs $req (group $rqg), which disabled_hooks lists; take it out of disabled_hooks and add --set group_$rqg=true"; then
  ok "30 $req disabled and $rqg off: advice names both fixes"
else bad "30 disabled plus group off advice rc=$rc"; fi
if ! grep -q hook_requires "$CLI_SRC"; then ok "30 CLI source has no hook_requires table"; else bad "30 hook_requires still in the CLI"; fi

# 31. explicit group values
new_sandbox stub
cli install --yes --level recommended >/dev/null 2>&1; rc=$?
lg=$(level_groups recommended); good=1
for g in $groups; do in_list "$g" "$lg" || { [ "$(optv "group_$g")" = false ] || good=0; }; done
if [ "$rc" = 0 ] && [ "$good" = 1 ]; then ok "31 --level recommended stores false for every group outside it"; else bad "31 level explicit rc=$rc opts=$(opts)"; fi
new_sandbox stub
mkdir -p "$T/.claude/commands"; : > "$T/.claude/commands/agent-tiers-x.md"
sg=$(for g in $groups; do [ "$g" = "$wg" ] || echo "$g"; done | tail -n 1)
jq -n --arg k "group_$sg" '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "sh \"/x/scripts/worktree-guard.sh\""}]}]},
  pluginConfigs: {"agent-tiers@agent-tiers": {options: {($k): true}}}}' > "$S"
cli install --yes >/dev/null 2>&1; rc=$?
good=1
for g in $groups; do
  v=$(optv "group_$g")
  if [ "$g" = "$wg" ] || [ "$g" = "$sg" ]; then [ "$v" = true ] || good=0; else [ "$v" = false ] || good=0; fi
done
if [ "$rc" = 0 ] && [ "$good" = 1 ] && [ "$(withs)" = "$(with_flags_for "$wg $sg" "$dep")" ]; then
  ok "31 core fallback: absent groups stored as their effective state, stored values kept, engine from them"
else bad "31 core fallback rc=$rc opts=$(opts)"; fi

# 32. hint: only options.tsv hook ids
new_sandbox stub
rid=$(printf '%s\n' $(hooks_of safety) | head -n 1)
printf '%s\n' '#!/bin/sh' "echo 'install-flat: refusing --with-$rid: x'" 'exit 1' > "$K/scripts/install-flat.sh"
jq -n '{pluginConfigs: {"agent-tiers@agent-tiers": {options: {disabled_hooks: ["bogus-id"]}}}}' > "$S"
out=$(cli install --yes --level recommended 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q "hint: re-run with --set disabled_hooks=$rid\$"; then
  ok "32 hint drops a stored id that is not a hook row"
else bad "32 hint filter rc=$rc: $(printf '%s\n' "$out" | grep hint)"; fi
printf '%s\n' '#!/bin/sh' "echo 'install-flat: refusing --with-nope: x'" 'exit 1' > "$K/scripts/install-flat.sh"
out=$(cli install --yes --level recommended 2>&1); rc=$?
if [ "$rc" = 1 ] && ! printf '%s\n' "$out" | grep -q 'hint:'; then
  ok "32 no hint line when no id is left"
else bad "32 empty hint rc=$rc"; fi

# 33. status with the plugin enabled
new_sandbox stub
jq -n '{enabledPlugins: {"agent-tiers@agent-tiers": true}, pluginConfigs: {"agent-tiers@agent-tiers": {options: {group_safety: true}}}}' > "$S"
ns=$(printf '%s\n' $(hooks_of safety) | grep -c .)
out=$(cli status 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "^  safety .*; wired by plugin ($ns hooks)\$"; then
  ok "33 status, plugin only: wired by plugin"
else bad "33 status plugin: $(printf '%s\n' "$out" | grep '^  safety')"; fi
mkdir -p "$T/.claude/commands"; : > "$T/.claude/commands/agent-tiers-x.md"
out=$(cli status 2>&1)
if printf '%s\n' "$out" | grep -q "^  safety .*0 of $ns hooks wired; plugin also wires them\$"; then
  ok "33 status, flat + plugin: count plus plugin also wires them"
else bad "33 status flat+plugin: $(printf '%s\n' "$out" | grep '^  safety')"; fi

# 34. plugin enabled: install and configure write options only, never run the engine
new_sandbox stub
mkdir -p "$T/.claude/commands"; : > "$T/.claude/commands/agent-tiers-x.md"
jq -n '{enabledPlugins: {"agent-tiers@agent-tiers": true}}' > "$S"
out=$(cli install --yes --level recommended 2>&1); rc=$?
if [ "$rc" = 0 ] && [ ! -f "$LOG" ] && [ "$(optv group_safety)" = true ] \
   && printf '%s\n' "$out" | grep -q 'engine: not run (agent-tiers plugin enabled.*run twice.*--unwire-only'; then
  ok "34 flat + plugin enabled: install writes options, engine not run"
else bad "34 flat+plugin install rc=$rc"; fi
new_sandbox stub
jq -n '{enabledPlugins: {"agent-tiers@agent-tiers": true}}' > "$S"
out=$(cli install --yes --level recommended 2>&1); rc=$?
if [ "$rc" = 0 ] && [ ! -f "$LOG" ] && [ "$(optv group_safety)" = true ] \
   && printf '%s\n' "$out" | grep -q 'engine: not run (agent-tiers plugin enabled: its hooks wire themselves' \
   && ! printf '%s\n' "$out" | grep -q 'run twice'; then
  ok "34 plugin only enabled: install writes options, engine not run"
else bad "34 plugin only install rc=$rc"; fi

# 35. status level line
lvl() { cli status 2>/dev/null | sed -n 's/^level: *//p'; }
new_sandbox stub
case "$(lvl)" in 'never configured'*) ok "35 level: never configured on a fresh profile" ;; *) bad "35 level fresh: $(lvl)" ;; esac
for L in $levels; do
  new_sandbox stub
  cli install --yes --level "$L" >/dev/null 2>&1
  if [ "$(lvl)" = "$L" ]; then ok "35 level: $L after --level $L"; else bad "35 level $L: $(lvl)"; fi
done
new_sandbox stub
cli install --yes --level core --set "group_$dg=true" >/dev/null 2>&1
if [ "$(lvl)" = custom ]; then ok "35 level: custom"; else bad "35 level custom: $(lvl)"; fi
new_sandbox stub
jq -n '{pluginConfigs: {"agent-tiers@agent-tiers": {options: {group_safety: true}}}}' > "$S"
ng=$(printf '%s' "$groups" | wc -w | tr -d ' ')
if [ "$(lvl)" = "partial (1 of $ng groups stored)" ]; then ok "35 level: partial"; else bad "35 level partial: $(lvl)"; fi

# 36. install-flat exit 0 after a partial failure
new_sandbox stub
printf '%s\n' '#!/bin/sh' "echo '  hook    x foo wire FAILED (jq write error) - settings.json unchanged'" 'exit 0' > "$K/scripts/install-flat.sh"
out=$(cli install --yes --level recommended 2>&1); rc=$?
if [ "$rc" = 1 ] && [ "$(opts)" = '{}' ] && printf '%s\n' "$out" | grep -q 'exited 0 but reported a failure' \
   && printf '%s\n' "$out" | grep -q '^agent-tiers:   .*foo wire FAILED'; then
  ok "36 wire FAILED with exit 0: CLI exits 1, options not written"
else bad "36 wire FAILED rc=$rc opts=$(opts)"; fi
printf '%s\n' '#!/bin/sh' "echo '  hook    ! foo selfcheck FAILED - run: sh x'" 'exit 0' > "$K/scripts/install-flat.sh"
out=$(cli install --yes --level recommended 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(optv group_safety)" = true ] \
   && [ "$(printf '%s\n' "$out" | tail -n 2 | head -n 1)" = 'warning: 1 wired hook selfcheck(s) failed (see above)' ]; then
  ok "36 selfcheck FAILED with exit 0: CLI finishes with a warning"
else bad "36 selfcheck FAILED rc=$rc"; fi
printf '%s\n' '#!/bin/sh' "echo '  hook    x foo removal FAILED - settings.json unchanged'" 'exit 0' > "$K/scripts/install-flat.sh"
mkdir -p "$T/.claude/commands"; : > "$T/.claude/commands/agent-tiers-x.md"
o1=$(opts)
out=$(cli remove --yes 2>&1); rc=$?
if [ "$rc" = 1 ] && [ "$(opts)" = "$o1" ] && [ -e "$T/.claude/commands/agent-tiers-x.md" ] \
   && printf '%s\n' "$out" | grep -q 'exited 0 but reported a failure'; then
  ok "36 remove: removal FAILED with exit 0 stops, options and files kept"
else bad "36 remove removal FAILED rc=$rc"; fi

# 37. flat + plugin enabled with a leftover pluginConfigs key: options land under the enabled key
new_sandbox stub
mkdir -p "$T/.claude/commands"; : > "$T/.claude/commands/agent-tiers-x.md"
jq -n '{enabledPlugins: {"agent-tiers@m": true}, pluginConfigs: {"agent-tiers@agent-tiers": {options: {group_safety: false}}}}' > "$S"
out=$(cli configure --yes --set group_safety=true 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(jq -r '.pluginConfigs["agent-tiers@m"].options.group_safety' "$S")" = true ] \
   && [ "$(jq -r '.pluginConfigs["agent-tiers@agent-tiers"].options.group_safety' "$S")" = false ] \
   && printf '%s\n' "$out" | grep -q '^Plan (.*, plugin key agent-tiers@m):$'; then
  ok "37 flat + plugin enabled: options written under the enabled key, plan names it"
else bad "37 enabled key rc=$rc: $(printf '%s\n' "$out" | grep '^Plan')"; fi

# 38. configure without a level stores never-stored groups at their effective state (flat, real engine)
new_sandbox real
h38=""; for id in $(hooks_of safety); do [ -f "$ROOT/scripts/$id.sh" ] && { h38=$id; break; }; done
CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" sh "$K/scripts/install-flat.sh" "--with-$h38" >/dev/null 2>&1
pre38=$(opts)
cli configure --yes >"$T/out38" 2>&1; rc=$?
good=1
[ -n "$h38" ] && [ "$pre38" = '{}' ] && [ "$rc" = 0 ] && [ "$(optv group_safety)" = true ] || good=0
for id in $(hooks_of safety); do
  [ -f "$ROOT/scripts/$id.sh" ] || continue
  grep -q "/scripts/$id[.]sh" "$S" || good=0
done
for g in $groups; do [ "$g" = safety ] && continue; [ "$(optv "group_$g")" = false ] || good=0; done
if [ "$good" = 1 ]; then ok "38 configure --yes without a level stores never-stored groups at effective state and wires the group"
else bad "38 configure keep rc=$rc pre=$pre38 opts=$(opts)"; fi

# 39. plugin enabled, no flat install, no stored groups: keep stores no group key and prints the note
for c39 in "configure --yes" "install --yes"; do
  new_sandbox stub
  jq -n '{enabledPlugins: {"agent-tiers@agent-tiers": true}}' > "$S"
  out=$(cli $c39 2>&1); rc=$?
  ng39=$(opts | jq '[keys[] | select(startswith("group_"))] | length')
  if [ "$rc" = 0 ] && [ "$ng39" = 0 ] && printf '%s\n' "$out" | grep -q '^  note: groups never stored stay unset (plugin enabled'; then
    ok "39 plugin enabled, $c39 without a level: no group stored, note printed"
  else bad "39 plugin keep ($c39) rc=$rc groups=$ng39 opts=$(opts)"; fi
done

# 40. status, plugin only, with a kit row still wired in settings.json: the count shows
wg40=$(awk -F'\t' '$1 == "hook" && $2 == "worktree-guard" { print $3 }' "$TSV")
new_sandbox stub
jq -n '{enabledPlugins: {"agent-tiers@m": true},
  hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "sh \"/x/scripts/worktree-guard.sh\""}]}]}}' > "$S"
out=$(cli status 2>&1)
nt40=$(printf '%s\n' $(hooks_of "$wg40") | grep -c .)
if [ -n "$wg40" ] && printf '%s\n' "$out" | grep -q "^  $wg40 .*; wired by plugin ($nt40 hooks); 1 also wired in settings.json\$"; then
  ok "40 status, plugin only: kit rows still in settings.json are counted"
else bad "40 status plugin wired rows: $(printf '%s\n' "$out" | grep "^  $wg40")"; fi

# 41. no dependency line when planning is off or when planning and memory are both on
new_sandbox stub
good=1
for lv in recommended full; do
  out=$(cli install --yes --level "$lv" --dry-run 2>&1) || good=0
  printf '%s\n' "$out" | grep -q -e '^  not wired:' -e '^  inert:' && good=0
done
if [ "$good" = 1 ]; then ok "41 no not-wired/inert line at level recommended or full"; else bad "41 stray dependency line"; fi

# 42. plugin only with a kit row still wired: the plan says it runs twice; a --set for every group
#     leaves nothing unset, so no keep note
new_sandbox stub
jq -n '{enabledPlugins: {"agent-tiers@m": true},
  hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "sh \"/x/scripts/worktree-guard.sh\""}]}]}}' > "$S"
out=$(cli configure --yes --dry-run 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'kit rows still in settings.json run twice'; then
  ok "42 plugin only, kit row wired: plan names the double run"
else bad "42 plugin only wired row rc=$rc: $(printf '%s\n' "$out" | grep 'engine:')"; fi
s42=""; for g in $groups; do s42="$s42 --set group_$g=false"; done
# shellcheck disable=SC2086
out=$(cli configure --yes --dry-run $s42 2>&1); rc=$?
if [ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q '^  note: groups never stored'; then
  ok "42 keep with every group --set: no unset-groups note"
else bad "42 keep note after full --set rc=$rc"; fi

# 43. notify-stop needs notify and notify-tag-guard (requires column): disabling the guard drops notify-stop only
ns=notify-stop; ng=notify-tag-guard; nn=notify
nsg=$(awk -F'\t' -v i="$ng" '$1 == "hook" && $2 == i { print $3 }' "$TSV")
new_sandbox stub
out=$(cli install --yes --level core --set "group_$nsg=true" --set "disabled_hooks=$ng" 2>&1); rc=$?
if [ "$rc" = 0 ] && ! withs | grep -qx -e "--with-$ns" && withs | grep -qx -e "--with-$nn" \
   && printf '%s\n' "$out" | grep -q "^  not wired: $ns needs $ng (group $nsg), which disabled_hooks lists"; then
  ok "43 $ng disabled: $ns not flagged, $nn flagged, plan line printed"
else bad "43 notify-stop dependency rc=$rc"; fi

# 44. the dependency comes from the requires column: rewrite the sandbox options.tsv, no hardcoded table
#     A (group G1) requires C (group G3, left off); chain: A requires B (G2), B requires C
first_of() { for x in $(hooks_of "$1"); do [ -f "$ROOT/scripts/$x.sh" ] && { printf '%s' "$x"; return; }; done; }
g1=$(printf '%s\n' $groups | sed -n 1p); g2=$(printf '%s\n' $groups | sed -n 2p); g3=$(printf '%s\n' $groups | sed -n 3p)
ha=$(first_of "$g1"); hb=$(first_of "$g2"); hc=$(first_of "$g3")
setreq() { # id value
  awk -F'\t' -v OFS='\t' -v a="$1" -v r="$2" '$1 == "hook" && $2 == a { $7 = r } 1' "$K/install/options.tsv" > "$T/o.tsv" && cat "$T/o.tsv" > "$K/install/options.tsv"
}
new_sandbox stub
setreq "$ha" "$hc"
out=$(cli install --yes --level core --set "group_$g1=true" --set "group_$g2=true" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ -n "$ha" ] && [ -n "$hc" ] && ! withs | grep -qx -e "--with-$ha" \
   && printf '%s\n' "$out" | grep -q "^  not wired: $ha needs $hc (group $g3)"; then
  ok "44 requires column: $ha ($g1) needs $hc ($g3, off): not flagged, plan line printed"
else bad "44 column dependency rc=$rc"; fi
new_sandbox stub
setreq "$ha" "$hb"; setreq "$hb" "$hc"
out=$(cli install --yes --level core --set "group_$g1=true" --set "group_$g2=true" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ -n "$hb" ] && ! withs | grep -qx -e "--with-$ha" && ! withs | grep -qx -e "--with-$hb" \
   && printf '%s\n' "$out" | grep -q "^  not wired: $hb needs $hc" \
   && [ "$(printf '%s\n' "$out" | grep -c "^  not wired: $ha needs ")" = 1 ] \
   && printf '%s\n' "$out" | grep -q "^  not wired: $ha needs $hb (group $g2), which is itself held back by its own requirement"; then
  ok "44 chain $ha needs $hb needs $hc (off): both dropped, one note each"
else bad "44 chain dependency rc=$rc"; fi
# chain in the other direction: each dependent lists only its own requirements, whatever the row order
new_sandbox stub
setreq "$hb" "$ha"; setreq "$ha" "$hc"
out=$(cli install --yes --level core --set "group_$g1=true" --set "group_$g2=true" 2>&1); rc=$?
if [ "$rc" = 0 ] && ! withs | grep -qx -e "--with-$ha" && ! withs | grep -qx -e "--with-$hb" \
   && printf '%s\n' "$out" | grep -q "^  not wired: $ha needs $hc" \
   && [ "$(printf '%s\n' "$out" | grep -c "^  not wired: $hb needs ")" = 1 ] \
   && ! printf '%s\n' "$out" | grep -q "^  not wired: $hb needs $hc"; then
  ok "44 reverse chain $hb needs $ha needs $hc (off): $hb notes only $ha"
else bad "44 reverse chain rc=$rc"; fi

# 45. a requires entry naming a core hook counts as present (the engine wires core rows regardless of the plan)
ch=$(first_of core)
new_sandbox stub
setreq "$ha" "$ch"
out=$(cli install --yes --level core --set "group_$g1=true" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ -n "$ch" ] && withs | grep -qx -e "--with-$ha" && ! printf '%s\n' "$out" | grep -q '^  not wired:'; then
  ok "45 $ha requires core hook $ch: flagged, no not-wired line"
else bad "45 core requirement rc=$rc"; fi
new_sandbox stub
setreq "$ha" "$ch"
out=$(cli install --yes --level core --set "group_$g1=true" --set "disabled_hooks=$ch" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ -n "$ch" ] && ! withs | grep -qx -e "--with-$ha" \
   && printf '%s\n' "$out" | grep -q "^  not wired: $ha needs $ch (group core), which disabled_hooks lists; take it out of disabled_hooks to turn both on\$" \
   && ! printf '%s\n' "$out" | grep -q 'group_core'; then
  ok "45 core hook $ch in disabled_hooks: $ha not flagged, advice names disabled_hooks only"
else bad "45 disabled core requirement rc=$rc"; fi

# 46. extras seam (options.tsv kind extra): statusline writes settings keys, agentsview is a pointer
sl_cmd_main() { printf 'sh "%s/scripts/statusline.sh"' "$K"; }
sl_cmd_sub() { printf 'sh "%s/scripts/statusline-subagent.sh"' "$K"; }
sl_obj() { jq -cn --arg c "$1" '{type: "command", command: $c}'; }
slkeys() { [ -f "$S" ] && jq -c '[.statusLine, .subagentStatusLine]' "$S"; }
nbak() { ls -1 "$S".bak-* 2>/dev/null | wc -l | tr -d ' '; }
ptr_desc=$(awk -F'\t' '$1 == "extra" && $3 == "pointer" { print $5; exit }' "$TSV")
ptr_id=$(awk -F'\t' '$1 == "extra" && $3 == "pointer" { print $2; exit }' "$TSV")
sl_title=$(awk -F'\t' '$1 == "extra" && $2 == "statusline" { print $4; exit }' "$TSV")
foreign='{"type":"command","command":"my-line"}'

# E1 --yes without --set: nothing written, hint printed
new_sandbox stub
out=$(cli install --yes --level core 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(jq -c '[has("statusLine"), has("subagentStatusLine")]' "$S")" = '[false,false]' ] \
   && printf '%s\n' "$out" | grep -q -- '^  to add extra statusline: --set extra_statusline=true$'; then
  ok "46 E1 install --yes: no statusline keys, hint printed"
else bad "46 E1 rc=$rc"; fi

# E2 --set extra_statusline=true: both keys written, plan shows it, one backup this run
new_sandbox stub
printf '{}\n' > "$S"
out=$(cli install --yes --level core --set extra_statusline=true 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(slkeys)" = "[$(sl_obj "$(sl_cmd_main)"),$(sl_obj "$(sl_cmd_sub)")]" ] \
   && printf '%s\n' "$out" | grep -q 'settings.statusLine: absent ->' && [ "$(nbak)" = 1 ]; then
  ok "46 E2 --set extra_statusline=true writes both keys, plan line, one backup"
else bad "46 E2 rc=$rc keys=$(slkeys) bak=$(nbak)"; fi
# idempotent: already ours, nothing to change
out=$(cli configure --yes --set extra_statusline=true 2>&1); rc=$?
if [ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'settings.statusLine:'; then ok "46 E2 second run plans no statusLine change"; else bad "46 E2 idempotent rc=$rc"; fi

# E3 foreign statusLine, no --set: unchanged
new_sandbox stub
jq -n --argjson f "$foreign" '{statusLine: $f}' > "$S"
cli install --yes --level core >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ "$(jq -c '.statusLine' "$S")" = "$foreign" ] && [ "$(jq 'has("subagentStatusLine")' "$S")" = false ]; then
  ok "46 E3 foreign statusLine untouched without --set"
else bad "46 E3 rc=$rc"; fi

# E4 foreign statusLine, --set true: replaced, newest backup keeps my-line
new_sandbox stub
jq -n --argjson f "$foreign" '{statusLine: $f}' > "$S"
cli install --yes --level core --set extra_statusline=true >/dev/null 2>&1; rc=$?
newest=$(ls -1 "$S".bak-* 2>/dev/null | sort -r | head -n 1)
if [ "$rc" = 0 ] && [ "$(jq -c '.statusLine' "$S")" = "$(sl_obj "$(sl_cmd_main)")" ] && [ -n "$newest" ] \
   && [ "$(jq -c '.statusLine' "$newest")" = "$foreign" ]; then
  ok "46 E4 foreign statusLine replaced on --set true, backup keeps the old one"
else bad "46 E4 rc=$rc"; fi

# E5 configure --set false: ours deleted, foreign left with a line
new_sandbox stub
cli install --yes --level core --set extra_statusline=true >/dev/null 2>&1
cli configure --yes --set extra_statusline=false >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ "$(jq -c '[has("statusLine"), has("subagentStatusLine")]' "$S")" = '[false,false]' ]; then
  ok "46 E5 configure --set extra_statusline=false deletes ours"
else bad "46 E5 ours rc=$rc"; fi
new_sandbox stub
jq -n --argjson f "$foreign" '{statusLine: $f, subagentStatusLine: $f}' > "$S"
out=$(cli configure --yes --set extra_statusline=false 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(jq -c '.statusLine' "$S")" = "$foreign" ] && printf '%s\n' "$out" | grep -q '^  left in place (not this kit.s): statusLine$'; then
  ok "46 E5 foreign left in place, line printed"
else bad "46 E5 foreign rc=$rc"; fi

# E6 remove: ours deleted without pluginConfigs/env keys, foreign untouched
new_sandbox stub
jq -n --arg m "$(sl_cmd_main)" --arg s "$(sl_cmd_sub)" '{keep: 1, statusLine: {type: "command", command: $m}, subagentStatusLine: {type: "command", command: $s}}' > "$S"
out=$(cli remove --yes 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(jq -c '.' "$S")" = '{"keep":1}' ] && printf '%s\n' "$out" | grep -q 'delete statusLine / subagentStatusLine'; then
  ok "46 E6 remove deletes ours with no other keys to remove"
else bad "46 E6 ours rc=$rc: $(cat "$S")"; fi
new_sandbox stub
jq -n --argjson f "$foreign" --arg s "$(sl_cmd_sub)" '{statusLine: $f, subagentStatusLine: {type: "command", command: $s}}' > "$S"
out=$(cli remove --yes 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(jq -c '.statusLine' "$S")" = "$foreign" ] && [ "$(jq 'has("subagentStatusLine")' "$S")" = false ] \
   && printf '%s\n' "$out" | grep -q 'delete subagentStatusLine (' && ! printf '%s\n' "$out" | grep -q 'delete statusLine'; then
  ok "46 E6 remove judges each key: foreign statusLine kept, ours subagent key deleted"
else bad "46 E6 mixed rc=$rc"; fi
new_sandbox stub
jq -n --argjson f "$foreign" '{statusLine: $f}' > "$S"; c0=$(cksum < "$S")
out=$(cli remove --yes 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(cksum < "$S")" = "$c0" ] && [ "$(nbak)" = 0 ] && printf '%s\n' "$out" | grep -q '^  left in place (not this kit copy.s): statusLine$' \
   && ! printf '%s\n' "$out" | grep -q 'left in place (not this kit copy.s): subagentStatusLine'; then ok "46 E6 remove with only a foreign statusLine writes nothing, prints left in place"; else bad "46 E6 foreign rc=$rc"; fi

# E7 dry run
new_sandbox stub
printf '{"keep": 1}\n' > "$S"; c0=$(cksum < "$S")
out=$(cli install --dry-run --level core --set extra_statusline=true 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(cksum < "$S")" = "$c0" ] && [ "$(nbak)" = 0 ] && printf '%s\n' "$out" | grep -q 'settings.statusLine: absent ->'; then
  ok "46 E7 --dry-run shows the statusLine plan, writes nothing"
else bad "46 E7 rc=$rc"; fi

# E8 bad --set values exit 2 and write nothing
new_sandbox stub
printf '{}\n' > "$S"; c0=$(cksum < "$S"); good=1
for a in extra_statusline=maybe "extra_$ptr_id=true" extra_nope=true; do
  e=$(cli install --yes --level core --set "$a" 2>&1); [ $? = 2 ] || good=0
done
e=$(cli install --yes --level core --set "extra_$ptr_id=true" 2>&1)
printf '%s\n' "$e" | grep -q "pointer only, nothing to set" || good=0
if [ "$good" = 1 ] && [ "$(cksum < "$S")" = "$c0" ] && [ ! -f "$LOG" ]; then
  ok "46 E8 extra_statusline=maybe, pointer id and unknown id exit 2, nothing written"
else bad "46 E8 good=$good"; fi

# E9 pointer description printed on install
new_sandbox stub
out=$(cli install --yes --level core 2>&1)
if [ -n "$ptr_desc" ] && printf '%s\n' "$out" | grep -qxF "  $ptr_desc"; then ok "46 E9 install prints the $ptr_id pointer description"; else bad "46 E9 pointer text"; fi

# E10 script missing from the kit copy
new_sandbox stub
printf '{}\n' > "$S"; c0=$(cksum < "$S")
rm -f "$K/scripts/statusline.sh"
out=$(cli install --yes --level core --set extra_statusline=true 2>&1); rc=$?
if [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q 'not in this kit copy' && [ "$(cksum < "$S")" = "$c0" ]; then
  ok "46 E10 --set extra_statusline=true with a script missing exits 2"
else bad "46 E10 rc=$rc"; fi
out=$(cli install --yes --level core 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'skipped extra statusline'; then ok "46 E10 plain install skips the extra"; else bad "46 E10 skip rc=$rc"; fi

# E11 status
new_sandbox stub
out=$(cli status 2>&1)
if printf '%s\n' "$out" | grep -q '^extra statusline: statusLine unset, subagentStatusLine unset$' \
   && printf '%s\n' "$out" | grep -q "^extra $ptr_id: pointer only; $ptr_id on PATH: "; then
  ok "46 E11 status on a fresh profile: unset, pointer line"
else bad "46 E11 fresh"; fi
cli install --yes --level core --set extra_statusline=true >/dev/null 2>&1
out=$(cli status 2>&1)
if printf '%s\n' "$out" | grep -q '^extra statusline: statusLine kit, subagentStatusLine kit$'; then ok "46 E11 status after install: kit"; else bad "46 E11 kit"; fi
jq -n --argjson f "$foreign" '{statusLine: $f}' > "$S"
if cli status 2>&1 | grep -q '^extra statusline: statusLine other, subagentStatusLine unset$'; then ok "46 E11 status: other"; else bad "46 E11 other"; fi

# E13 a stub engine flips statusLine to a foreign value mid-run: the write must not clobber it
new_sandbox stub
printf '%s\n' '#!/bin/sh' "jq -c '.statusLine = {type: \"command\", command: \"raced\"}' \"\$CLAUDE_CONFIG_DIR/settings.json\" > \"\$CLAUDE_CONFIG_DIR/s.tmp\" && cat \"\$CLAUDE_CONFIG_DIR/s.tmp\" > \"\$CLAUDE_CONFIG_DIR/settings.json\"" 'exit 0' > "$K/scripts/install-flat.sh"
printf '{}\n' > "$S"
out=$(cli install --yes --level core --set extra_statusline=true 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^  not changed (settings.json changed during the run): statusLine$' \
   && ! printf '%s\n' "$out" | grep -q 'changed during the run): subagentStatusLine' && [ "$(jq -r '.statusLine.command' "$S")" = raced ] && [ "$(jq -c '.subagentStatusLine' "$S")" = "$(sl_obj "$(sl_cmd_sub)")" ]; then
  ok "46 E13 statusLine changed during the run is not overwritten, the untouched key is still set"
else bad "46 E13 rc=$rc keys=$(slkeys)"; fi

# E12 interactive: answers n, n (env proposals), y (Add it?), y (Apply)
new_sandbox stub
out=$(printf 'n\nn\ny\ny\n' | cli install --level core 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$(slkeys)" = "[$(sl_obj "$(sl_cmd_main)"),$(sl_obj "$(sl_cmd_sub)")]" ] \
   && printf '%s\n' "$out" | grep -qF "Extra: $sl_title" && printf '%s\n' "$out" | grep -q 'Add it? ' && printf '%s\n' "$out" | grep -q '  current: statusLine unset, subagentStatusLine unset'; then
  ok "46 E12 interactive y to Add it? writes both keys"
else bad "46 E12 rc=$rc"; fi
out=$(printf 'n\nn\ny\n' | cli configure --level core 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qF 'Extra statusline: already set (this kit copy)'; then ok "46 E12 interactive: already set is kept"; else bad "46 E12 already rc=$rc"; fi

# 47. reach list: read-only view of the reach-guard user allowlist (needs no jq; the CLI never writes it)
reach_sb() { new_sandbox stub; [ -d "$ROOT/data" ] && cp -R "$ROOT/data" "$K/"; AL="$CLAUDE_CONFIG_DIR/reach-guard/allow.tsv"; TAB=$(printf '\t'); }
reach_sb
out=$(cli reach list 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^absent'; then ok "47 reach list on no file prints absent, exit 0"; else bad "47 reach list absent rc=$rc"; fi
mkdir -p "$CLAUDE_CONFIG_DIR/reach-guard" && chmod 700 "$CLAUDE_CONFIG_DIR/reach-guard"
printf 'remote_shell\tvps\tread\n' >> "$AL"
if cli reach list 2>&1 | grep -q "^remote_shell${TAB}vps${TAB}read$"; then ok "47 reach list shows a row written with the printf form"; else bad "47 reach list row"; fi

# writing subcommands are gone: bad usage, nothing written
reach_sb
cli reach allow remote_shell vps read >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ] && [ ! -e "$AL" ]; then ok "47 reach allow exits 2, writes nothing"; else bad "47 reach allow rc=$rc"; fi
cli reach remove remote_shell vps >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ] && [ ! -e "$AL" ]; then ok "47 reach remove exits 2, writes nothing"; else bad "47 reach remove rc=$rc"; fi

reach_sb
mkdir -p "$T/elsewhere"; ln -s "$T/elsewhere" "$CLAUDE_CONFIG_DIR/reach-guard"
cli reach list >/dev/null 2>&1; rc=$?
if [ "$rc" = 1 ]; then ok "47 reach list on a symlinked dir exits 1"; else bad "47 reach list symlinked dir rc=$rc"; fi

# the real guard reads a row the user appends with the printf form
reach_sb
ST="$T/.state"; mkdir -p "$ST"
rg_payload='{"tool_name":"Bash","session_id":"s1","tool_input":{"command":"ssh vps uptime"},"cwd":"/tmp"}'
rg_dec() { printf '%s' "$rg_payload" | AGENT_TIERS_STATE_DIR="$ST" "$CLI_SH" "$K/scripts/reach-guard.sh" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
d0=$(rg_dec)
mkdir -p "$CLAUDE_CONFIG_DIR/reach-guard" && chmod 700 "$CLAUDE_CONFIG_DIR/reach-guard"
printf 'remote_shell\tvps\tread\n' >> "$AL"
d1=$(rg_dec)
if [ "$d0" = ask ] && [ "$d1" = allow ]; then ok "47 reach: the guard asks without the row and allows with it"; else bad "47 reach guard cross-check: '$d0' then '$d1'"; fi

if lint_effects "$CLI_SRC" >/dev/null 2>&1; then ok "47 lint passes the real CLI"; else bad "47 lint passes the real CLI"; fi

# no jq on PATH: list still works
reach_sb
mkdir -p "$CLAUDE_CONFIG_DIR/reach-guard" && chmod 700 "$CLAUDE_CONFIG_DIR/reach-guard"
printf 'remote_shell\tvps\tread\n' >> "$AL"
nj="$T/nojq"; mkdir -p "$nj"
for b in sh dash cat awk sed tr ls cut grep dirname printf mktemp mkdir chmod mv rm; do
  bp=$(command -v "$b" 2>/dev/null); case "$bp" in /*) ln -s "$bp" "$nj/$b" ;; esac
done
out=$(PATH="$nj" "$CLI_SH" "$K/scripts/agent-tiers" reach list 2>&1); rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "remote_shell${TAB}vps${TAB}read"; then ok "47 reach list works without jq on PATH"; else bad "47 reach no-jq rc=$rc out=$out"; fi

# 48. the installer's "proof SKIPPED" line (test-only knob) reaches a CLI user: the CLI prints the engine
#     output as-is, so no extra CLI warning is needed. (No knob-unset control: it would run every core
#     hook's real selfcheck in the sandbox; install-flat.selfcheck.sh case H1 covers the unset side.)
new_sandbox real
cli install --yes --level core >"$T/out48" 2>&1; rc=$?
nk48=$(grep -c 'proof SKIPPED (AGENT_TIERS_TEST_SKIP_HOOK_PROOF=1' "$T/out48")
if [ "$rc" = 0 ] && [ "$nk48" = 1 ]; then ok "48 CLI install shows the engine's 'proof SKIPPED' warning when the test knob is set"
else bad "48 proof SKIPPED passthrough rc=$rc knob_set=$nk48"; fi

printf '%d passed, %d failed\n' "$pass" "$nfail"
[ "$nfail" = 0 ]

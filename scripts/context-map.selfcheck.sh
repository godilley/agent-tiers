#!/usr/bin/env sh
# kit-scope: shared
# Self-check for context-map.sh. Builds a sandboxed CLAUDE_CONFIG_DIR/CLAUDE_PROJECT_DIR (and a
# private TMPDIR) and asserts, each on a single table line where a row is named:
#   --unregistered: exact id set (sorted, deduped, registered ids excluded), project-settings ids
#   prefixed `project:`, a project `false` overriding a user `true`, not-installed plugins omitted,
#   stable across runs, silent exit 0 with no registry / an unparseable settings file / bad args,
#   an oversized project settings file skipped;
#   full map: base rows, CLAUDE.md chain (project, local, ancestor, nested + paths-scoped rules,
#   user rules, each file once incl. the global one reached as the project's .claude/CLAUDE.md),
#   memory 200 vs 201 lines, escaped piped matchers (column count), plugin hook shapes (no manifest,
#   array, scope choice, not installed), event classes, exact log-label attribution with sizes in
#   chars and firing counts, unattributed JSON and plain hits, stale plugin cache ignored, usage
#   errors, relative project dir, and no file left behind anywhere under the sandbox (cksum).
set -u
command -v jq >/dev/null 2>&1 || { echo "SKIP context-map: jq absent"; exit 0; }

H="$(cd "$(dirname "$0")" && pwd)/context-map.sh"
T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
T="$(cd "$T" && pwd)"
fail() { printf 'FAIL: %s\n' "$1"; rm -rf "$T"; exit 1; }
trap 'rm -rf "$T"' EXIT

CFG="$T/cfg"
PROJ="$T/proj"
mkdir -p "$CFG/plugins/cache" "$CFG/agent-tiers/.state" "$CFG/rules" "$PROJ/.claude/rules/sub" "$T/tmp" "$T/.claude"
export TMPDIR="$T/tmp"

run() { CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$PROJ" GIT_CEILING_DIRECTORIES="$T" sh "$H" "$@"; }
has_row() { printf '%s\n' "$1" | grep -qxF -- "$2"; }      # $1=output $2=exact table line
bsz() { printf '%sb' "$(wc -c < "$1" | tr -d ' ')"; }

slug="$(printf '%s' "$PROJ" | tr -c 'A-Za-z0-9' '-')"

# --- fixtures ------------------------------------------------------------------------------------
cat > "$CFG/settings.json" <<'JSON'
{
  "enabledPlugins": {"alpha@m": true, "beta@m": true, "off@m": false, "delta@m": true, "ghost@m": true,
                     "epsilon@m": true, "arr@m": true, "scoped@m": true, "scoped2@m": true},
  "hooks": {
    "SessionStart": [{"hooks":[{"type":"command","command":"sh \"$HOME/x/scripts/one.sh\""}]}],
    "PreToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"jq -n '{}'"}]}],
    "PostToolUse": [{"hooks":[{"type":"command","command":"python3 /p/two.py"}]}],
    "Stop": [{"hooks":[{"type":"command","command":"python3 /q/two.py"}]}],
    "Notification": [{"hooks":[{"type":"command","command":"jq -f /x/filter.json"}]}],
    "SubagentStop": [{"matcher":"Bash\\|Grep","hooks":[{"type":"command","command":"true"}]}],
    "SessionEnd": [{"hooks":[{"type":"command","command":"sh a.sh;echo x"}]}],
    "ContextCompact": [{"hooks":[{"type":"command","command":"sh b.sh&&true"}]}]
  }
}
JSON

cat > "$PROJ/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": {"beta@m": true, "delta@m": false},
  "hooks": {
    "SessionStart": [{"hooks":[{"type":"command","command":"sh \"$CLAUDE_PROJECT_DIR/.claude/hooks/proj-hook.sh\""}]}],
    "PreToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"echo hi"}]}]
  }
}
JSON

cat > "$PROJ/.claude/settings.local.json" <<'JSON'
{"enabledPlugins": {"gamma@m": true}}
JSON
cp "$PROJ/.claude/settings.local.json" "$T/local.good"

PR="$CFG/plugroots"
mkdir -p "$PR/alpha/.claude-plugin" "$PR/beta/.claude-plugin" "$PR/beta/hooks" "$PR/gamma/.claude-plugin" \
         "$PR/gamma/hooks" "$PR/delta/hooks" "$PR/epsilon/hooks" "$PR/arr/.claude-plugin" "$PR/arr/hooks" \
         "$PR/scopedA/hooks" "$PR/scopedB/hooks" "$PR/scoped2A/hooks" "$PR/scoped2B/hooks"

cat > "$PR/alpha/.claude-plugin/plugin.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [{"matcher":"startup|resume","hooks":[{"type":"command","command":"true","statusMessage":"Loading alpha..."}]}],
    "UserPromptSubmit": [{"hooks":[{"type":"command","command":"true"}]}]
  }
}
JSON
printf '%s\n' '{"hooks": "./hooks/h.json"}' > "$PR/beta/.claude-plugin/plugin.json"
printf '%s\n' '{"hooks": {"SubagentStart": [{"hooks":[{"type":"command","command":"true"}]}]}}' > "$PR/beta/hooks/h.json"
printf '%s\n' '{"name": "gamma"}' > "$PR/gamma/.claude-plugin/plugin.json"
printf '%s\n' '{"hooks": {"Stop": [{"hooks":[{"type":"command","command":"true"}]}]}}' > "$PR/gamma/hooks/hooks.json"
printf '%s\n' '{"hooks": {"PreCompact": [{"hooks":[{"type":"command","command":"true"}]}]}}' > "$PR/delta/hooks/hooks.json"
# epsilon: no manifest at all, default hooks/hooks.json still loads
printf '%s\n' '{"hooks": {"UserPromptExpansion": [{"hooks":[{"type":"command","command":"true"}]}]}}' > "$PR/epsilon/hooks/hooks.json"
# arr: manifest hooks given as an array of a path and an inline object
printf '%s\n' '{"hooks": ["./hooks/a.json", {"PostToolUseFailure": [{"hooks":[{"type":"command","command":"true"}]}]}]}' > "$PR/arr/.claude-plugin/plugin.json"
printf '%s\n' '{"hooks": {"InstructionsLoaded": [{"hooks":[{"type":"command","command":"true"}]}]}}' > "$PR/arr/hooks/a.json"
# scoped: project-scope entry for ANOTHER project first, user entry second -> user entry wins
printf '%s\n' '{"hooks": {"TeammateIdle": [{"hooks":[{"type":"command","command":"true"}]}]}}' > "$PR/scopedA/hooks/hooks.json"
printf '%s\n' '{"hooks": {"CwdChanged": [{"hooks":[{"type":"command","command":"true"}]}]}}' > "$PR/scopedB/hooks/hooks.json"
# scoped2: user entry first, project-scope entry for THIS project second -> project entry wins
printf '%s\n' '{"hooks": {"FileChanged": [{"hooks":[{"type":"command","command":"true"}]}]}}' > "$PR/scoped2A/hooks/hooks.json"
printf '%s\n' '{"hooks": {"DirectoryAdded": [{"hooks":[{"type":"command","command":"true"}]}]}}' > "$PR/scoped2B/hooks/hooks.json"

# stale sibling cache dir for alpha - must NEVER be read (roots come from installed_plugins.json only)
mkdir -p "$CFG/plugins/cache/alpha/alpha/9.9.9/.claude-plugin"
printf '%s\n' '{"hooks": {"WorktreeRemove": [{"hooks":[{"type":"command","command":"true"}]}]}}' \
  > "$CFG/plugins/cache/alpha/alpha/9.9.9/.claude-plugin/plugin.json"

cat > "$CFG/plugins/installed_plugins.json" <<JSON
{
  "plugins": {
    "alpha@m": [{"installPath": "$PR/alpha"}],
    "beta@m": [{"scope": "user", "installPath": "$PR/beta"}],
    "gamma@m": [{"scope": "user", "installPath": "$PR/gamma"}],
    "delta@m": [{"scope": "user", "installPath": "$PR/delta"}],
    "epsilon@m": [{"scope": "user", "installPath": "$PR/epsilon"}],
    "arr@m": [{"scope": "user", "installPath": "$PR/arr"}],
    "scoped@m": [{"scope": "project", "projectPath": "/elsewhere", "installPath": "$PR/scopedA"},
                 {"scope": "user", "projectPath": null, "installPath": "$PR/scopedB"}],
    "scoped2@m": [{"scope": "user", "installPath": "$PR/scoped2B"},
                  {"scope": "project", "projectPath": "$PROJ", "installPath": "$PR/scoped2A"}]
  }
}
JSON

# CLAUDE.md chain
echo "global" > "$CFG/CLAUDE.md"
echo "user rule" > "$CFG/rules/u.md"
echo "ancestor" > "$T/CLAUDE.md"
echo "ancestor .claude/CLAUDE.md is not loaded" > "$T/.claude/CLAUDE.md"
echo "project" > "$PROJ/CLAUDE.md"
echo "local" > "$PROJ/CLAUDE.local.md"
echo "nested rule" > "$PROJ/.claude/rules/sub/nested.md"
printf '%s\n' '---' 'paths:' '  - "src/**/*.ts"' '---' 'scoped rule' > "$PROJ/.claude/rules/scoped.md"

mkdir -p "$CFG/projects/$slug/memory"
MEM="$CFG/projects/$slug/memory/MEMORY.md"
i=1; while [ "$i" -le 200 ]; do echo "memory line $i" >> "$MEM"; i=$((i + 1)); done

cat > "$CFG/agent-tiers/.state/LAYERS.md" <<'MD'
| id | owner | notes |
|---|---|---|
| `alpha@m` | test | registered |
| `one.sh` | test | registered |
| `inline:PreToolUse` | test | user-settings inline id; must not register the project one |
| `proj-hook.sh` | test | unprefixed; must not register the project hook |
MD

LOG="$T/debug.log"
printf '%s\n' \
  '2026-01-01T00:00:00.000Z [DEBUG] "Hook SessionStart:startup (SessionStart) success:\n{\n  \"hookSpecificOutput\": {\n    \"hookEventName\": \"SessionStart\",\n    \"additionalContext\": \"one\"\n  }\n}"' \
  '2026-01-01T00:00:00.001Z [DEBUG] Hook SessionStart (sh "$HOME/x/scripts/one.sh") provided additionalContext (300 chars)' \
  '2026-01-01T00:00:00.100Z [DEBUG] Hook SessionStart (Loading alpha...) provided additionalContext (1234 chars)' \
  '2026-01-01T00:00:00.200Z [DEBUG] Hook SessionStart (sh "$CLAUDE_PROJECT_DIR/.claude/hooks/proj-hook.sh") provided additionalContext (98 chars)' \
  '2026-01-01T00:00:00.300Z [DEBUG] Hook SessionStart (sh "$HOME/x/scripts/phone.sh") provided additionalContext (77 chars)' \
  '2026-01-01T00:00:01.000Z [DEBUG] "Hook SessionStart:startup (SessionStart) success:\nhello world"' \
  '2026-01-01T00:00:05.000Z [DEBUG] Hook SessionStart (sh "$HOME/x/scripts/one.sh") provided additionalContext (300 chars)' \
  '2026-01-01T00:00:06.000Z [DEBUG] "Hook UserPromptSubmit (UserPromptSubmit) success:\nprompt text"' \
  '2026-01-01T00:00:07.000Z [DEBUG] "Hook PreToolUse:Bash (PreToolUse) success:\nnot context"' \
  '2026-01-01T00:00:08.000Z [DEBUG] Skill listing over budget: 9 skills, 40000 chars > 30000 budget' \
  '2026-01-01T00:00:09.000Z [DEBUG] "Hook SessionStart:startup (SessionStart) success:\nsee scripts/one.sh for details"' \
  > "$LOG"

snap() { find "$T" -type f -exec cksum {} \; 2>/dev/null | LC_ALL=C sort; find "$T" -type d 2>/dev/null | LC_ALL=C sort; }

# --- 1/2. --unregistered: exact set, byte-identical on a second run, no writes ------------------
BASE1="$(snap)"
out1="$(run --unregistered)"
out2="$(run --unregistered)"
[ "$BASE1" = "$(snap)" ] || fail "5: --unregistered left a file behind or rewrote one"

expected="$(printf '%s\n' a.sh arr@m b.sh beta@m epsilon@m gamma@m inline:Notification inline:SubagentStop \
  project:inline:PreToolUse project:proj-hook.sh scoped@m scoped2@m two.py | LC_ALL=C sort)"
[ "$out1" = "$expected" ] || fail "1: --unregistered set wrong, got: [$out1] want: [$expected]"
[ "$out1" = "$out2" ] || fail "2: --unregistered output not byte-identical across runs"
# (delta@m: project false overrides user true; ghost@m: no install entry; two.py: listed once
#  although two hooks produce it; filter.json must not become `filter.js`) - all covered by the
#  exact compare above.

# --- 3. silent exit 0: no registry, unparseable settings, bad args, oversized project file -----
mv "$CFG/agent-tiers/.state/LAYERS.md" "$T/LAYERS.md.bak"
out3="$(run --unregistered)"; rc3=$?
[ -z "$out3" ] && [ "$rc3" -eq 0 ] || fail "3: no registry should be silent exit 0, got rc=$rc3: $out3"
mv "$T/LAYERS.md.bak" "$CFG/agent-tiers/.state/LAYERS.md"

printf '{broken' > "$PROJ/.claude/settings.local.json"
out3="$(run --unregistered 2>&1)"; rc3=$?
[ -z "$out3" ] && [ "$rc3" -eq 0 ] || fail "3: unparseable settings should be silent exit 0, got rc=$rc3: $out3"

{ printf '{"enabledPlugins": {"gamma@m": true}, "hooks": {"Stop": [{"hooks":[{"type":"command","command":"sh big.sh"}]}]}, "pad": "'
  i=0; while [ "$i" -lt 700 ]; do printf '%0100d' 0; i=$((i + 1)); done
  printf '"}\n'; } > "$PROJ/.claude/settings.local.json"
out3="$(run --unregistered)"
printf '%s\n' "$out3" | grep -qx 'beta@m' || fail "3: oversized project file should be skipped, not abort: $out3"
printf '%s\n' "$out3" | grep -qx 'project:big.sh' && fail "3: oversized project settings file was parsed"
printf '%s\n' "$out3" | grep -qx 'gamma@m' && fail "3: oversized project settings file enabled a plugin"
printf '%s\n' "$out3" | grep -qx 'project:oversized-settings' \
  || fail "3: oversized project settings file must surface project:oversized-settings, not vanish silently: $out3"
cp "$T/local.good" "$PROJ/.claude/settings.local.json"

# a user settings file is never size-capped: pad it huge and confirm no oversized marker appears
cp "$CFG/settings.json" "$T/user.good"
pad="$(i=0; while [ "$i" -lt 700 ]; do printf '%0100d' 0; i=$((i + 1)); done)"
jq --arg pad "$pad" '. + {pad: $pad}' "$T/user.good" > "$CFG/settings.json"
out3="$(run --unregistered)"
printf '%s\n' "$out3" | grep -qx 'project:oversized-settings' \
  && fail "3: a user settings file must never be treated as oversized: $out3"
cp "$T/user.good" "$CFG/settings.json"

out3="$(run --unregistered --log 2>&1)"; rc3=$?
[ -z "$out3" ] && [ "$rc3" -eq 0 ] || fail "3: --unregistered with bad args should be silent exit 0, got rc=$rc3: $out3"
err="$(run --log 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && case "$err" in *usage*) true ;; *) false ;; esac || fail "14: --log without a value should print usage, exit 2 (rc=$rc)"
err="$(run --unregistred 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && case "$err" in *usage*) true ;; *) false ;; esac || fail "14: an unknown argument should print usage, exit 2 (rc=$rc)"

# --- 4. full map with --log ------------------------------------------------------------------
BASE4="$(snap)"
out4="$(run --log "$LOG")"
[ "$BASE4" = "$(snap)" ] || fail "5: full map with --log left a file behind or rewrote one"

chk() { has_row "$out4" "$1" || fail "4: missing row [$1], got:
$out4"; }
chk '| layer | id | event | class | size | registered | fires |'
chk '| base | claude-code-system-prompt | session-load | always | unmeasured | no | - |'
chk '| base | claude-code-harness | every tool call | always | unmeasured | no | - |'
# chain + rules
chk "| CLAUDE.md chain | ~/.claude/CLAUDE.md | session-load | always | $(bsz "$CFG/CLAUDE.md") | no | - |"
chk "| CLAUDE.md chain | ~/.claude/rules/u.md | session-load | always | $(bsz "$CFG/rules/u.md") | no | - |"
chk "| CLAUDE.md chain | ./CLAUDE.md | session-load | always | $(bsz "$PROJ/CLAUDE.md") | no | - |"
chk "| CLAUDE.md chain | ./CLAUDE.local.md | session-load | always | $(bsz "$PROJ/CLAUDE.local.md") | no | - |"
chk "| CLAUDE.md chain | ./.claude/rules/sub/nested.md | session-load | always | $(bsz "$PROJ/.claude/rules/sub/nested.md") | no | - |"
chk "| CLAUDE.md chain | ./.claude/rules/scoped.md | on-read | on-demand | $(bsz "$PROJ/.claude/rules/scoped.md") | no | - |"
chk "| CLAUDE.md chain | $T/CLAUDE.md | session-load | always | $(bsz "$T/CLAUDE.md") | no | - |"
case "$out4" in *"$T/.claude/CLAUDE.md"*) fail "1: an ancestor .claude/CLAUDE.md is not loaded, must not be listed" ;; esac
# memory: exactly 200 lines loads in full
chk "| auto-memory | auto-memory | session-load | always | $(bsz "$MEM") | no | - |"
# settings hooks: classes, project prefix, id boundary
chk '| settings hooks | inline:PreToolUse | PreToolUse:Bash | per-tool | - | yes | - |'
chk '| settings hooks | project:inline:PreToolUse | PreToolUse:Bash | per-tool | - | no | - |'
chk '| settings hooks | inline:Notification | Notification | other | - | no | - |'
# M6: a script id also ends at `;` or `&` (not only a quote, space or end of string)
chk '| settings hooks | a.sh | SessionEnd | other | - | no | - |'
chk '| settings hooks | b.sh | ContextCompact | other | - | no | - |'
# M3: a matcher containing a literal backslash immediately before a pipe must not break the row -
# the backslash is escaped first so the pipe stays an escaped, non-breaking cell separator. A raw
# `|`-byte count can't tell fixed from broken (both contain one raw pipe byte here), so unescape
# properly in order (escaped-backslash pairs, then escaped-pipe pairs) before counting live pipes.
chk '| settings hooks | inline:SubagentStop | SubagentStop:Bash\\\|Grep | other | - | no | - |'
printf '%s\n' "$out4" | grep 'inline:SubagentStop' \
  | awk '{ gsub(/\\\\/, "@@"); gsub(/\\\|/, "##"); n = gsub(/\|/, "|"); print n + 1 }' \
  | grep -qx 9 \
  || fail "4: the Bash\\|Grep matcher row does not have exactly 7 columns once properly unescaped"
# plugins: shapes, scopes, classes
chk '| enabled plugins | beta@m | SubagentStart | per-spawn | - | no | - |'
chk '| enabled plugins | gamma@m | Stop | other | - | no | - |'
chk '| enabled plugins | epsilon@m | UserPromptExpansion | per-prompt | - | no | - |'
chk '| enabled plugins | arr@m | InstructionsLoaded | always | - | no | - |'
chk '| enabled plugins | arr@m | PostToolUseFailure | per-tool | - | no | - |'
chk '| enabled plugins | scoped@m | CwdChanged | other | - | no | - |'
chk '| enabled plugins | scoped2@m | FileChanged | other | - | no | - |'
chk '| enabled plugins | ghost@m | - | not installed | - | no | - |'
for bad in TeammateIdle DirectoryAdded WorktreeRemove PreCompact 'delta@m' 'unattributed | PreToolUse'; do
  case "$out4" in *"$bad"*) fail "4: [$bad] must not appear in the full map" ;; esac
done
# log attribution: exact label (full command or statusMessage), chars, firings
chk '| settings hooks | one.sh | SessionStart | always | 600c | yes | 2 |'
chk '| enabled plugins | alpha@m | SessionStart:startup\|resume | always | 1234c | yes | 1 |'
chk '| settings hooks | project:proj-hook.sh | SessionStart | always | 98c | no | 1 |'
chk '| log | unattributed | SessionStart | always | 77c | - | 1 |'
chk '| log | unattributed | SessionStart | always | 11c | - | 1 |'
chk '| log | unattributed | UserPromptSubmit | per-prompt | 11c | - | 1 |'
# M4: a plain-text payload mentioning another row's script name ("...one.sh...") must not be
# credited to that row by substring - only an exact header/label match may attribute it. one.sh's
# own row must stay at exactly 600c/2 (its two real hits), and this line goes to unattributed.
chk '| settings hooks | one.sh | SessionStart | always | 600c | yes | 2 |'
chk '| log | unattributed | SessionStart | always | 30c | - | 1 |'
case "$out4" in *"note: Skill listing over budget:"*) ;; *) fail "4: missing the 'note: Skill listing over budget:' line" ;; esac
# every table line has exactly 7 cells once escaped pipes are removed
printf '%s\n' "$out4" | grep '^|' | sed 's/\\|//g' | awk -F'|' 'NF != 9 { bad = 1 } END { exit bad ? 1 : 0 }' \
  || fail "2: a table line has the wrong column count (unescaped |)"

# --- 6. memory index of 201 lines is OVER -------------------------------------------------------
echo "memory line 201" >> "$MEM"
loaded="$(head -n 200 "$MEM" | wc -c | tr -d ' ')"
out6="$(run)"
has_row "$out6" "| auto-memory | auto-memory (OVER: $(bsz "$MEM") total) | session-load | always | ${loaded}b | no | - |" \
  || fail "9: 201-line memory index should be OVER, got: $out6"

# --- 7. HOME-shaped: the global CLAUDE.md reached again as the project's .claude/CLAUDE.md -------
HOMEL="$T/home"
mkdir -p "$HOMEL/.claude"
echo "global" > "$HOMEL/.claude/CLAUDE.md"
out7="$(CLAUDE_CONFIG_DIR="$HOMEL/.claude" CLAUDE_PROJECT_DIR="$HOMEL" GIT_CEILING_DIRECTORIES="$T" sh "$H")"
n7="$(printf '%s\n' "$out7" | grep -cE '^\| CLAUDE\.md chain \| (~/\.claude/CLAUDE\.md|\./\.claude/CLAUDE\.md) \|')"
[ "$n7" -eq 1 ] || fail "1: global CLAUDE.md should be listed exactly once, got $n7 rows: $out7"

# --- 8. relative project dir terminates and resolves --------------------------------------------
out8="$(cd "$PROJ" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR=. GIT_CEILING_DIRECTORIES="$T" sh "$H")"
has_row "$out8" "| CLAUDE.md chain | ./CLAUDE.md | session-load | always | $(bsz "$PROJ/CLAUDE.md") | no | - |" \
  || fail "14: CLAUDE_PROJECT_DIR=. should resolve to the project dir, got: $out8"

echo "OK context-map: --unregistered exact/stable/prefixed/silent-on-trouble; full map chain, rules, memory boundary, plugin shapes and scopes, classes, escaped cells, exact log attribution with chars and firings, unattributed hits, usage errors; nothing left behind in the sandbox"

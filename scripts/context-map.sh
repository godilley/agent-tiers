#!/usr/bin/env sh
# kit-scope: shared
# context-map.sh - maps the injectors that land in THIS session's context: two fixed base layers
# (system prompt, tool harness), the CLAUDE.md chain (managed policy file, user file, project and
# ancestor files, user and project rules), the auto-memory index, settings.json/settings.local.json
# hook rows, enabled-plugin hook rows, outputStyle, and skills - each against the layer registry
# (.state/LAYERS.md) so an unregistered injector is visible. Never executes a hook. Reads only;
# writes private temp files (mktemp) that it removes.
#
# Documented layers still NOT mapped: claudeMdExcludes (excluded files still get a row), @imports
# (counted per file, their bytes are not added), managed settings claudeMd, the macOS/Windows
# managed CLAUDE.md paths, --add-dir CLAUDE.md loading, autoMemoryDirectory from policy or
# --settings, CLAUDE_CODE_PROJECT_DIR_NAME, and CLAUDE.md files in subdirectories (loaded on read).
#
# Modes:
#   context-map.sh --unregistered          one id per line, for a SessionStart nudge (fast, silent
#                                           on any missing/unparseable input - never blocks a session)
#   context-map.sh [--log <debug-file>]    full markdown table; --log fills in sizes and firing
#                                           counts from a `claude --debug-file <path>` run's DEBUG lines
#
# Run standalone: sh scripts/context-map.sh [--log /path/to/debug.log]
set -u

# Internal field separator for our own intermediate files/jq output: NOT a tab. POSIX `read`
# collapses runs of an IFS *whitespace* character (tab included), silently eating empty fields
# between two tabs. 0x1F (unit separator) is not whitespace, so empty fields survive. 0x1E joins
# several hook labels inside one field. Every string coming out of jq has control bytes replaced,
# so neither separator (nor a newline) can appear inside a field.
US="$(printf '\037')"
RS="$(printf '\036')"

MODE=full
LOG=""
ARGERR=0
while [ $# -gt 0 ]; do
  case "$1" in
    --unregistered) MODE=unregistered ;;
    --log) if [ $# -ge 2 ]; then shift; LOG="$1"; else ARGERR=1; fi ;;
    *) ARGERR=1 ;;
  esac
  shift
done
if [ "$ARGERR" = 1 ]; then
  [ "$MODE" = unregistered ] && exit 0
  echo "usage: context-map.sh [--unregistered] [--log <debug-file>]" >&2
  exit 2
fi

fail_out() { # $1=message; silent exit 0 in --unregistered, error exit 2 in the full map
  [ "$MODE" = unregistered ] && exit 0
  echo "context-map: $1" >&2
  exit 2
}

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$(CDPATH= cd -- "$DIR" 2>/dev/null && pwd)" || fail_out "cannot enter project dir"
REGISTRY="$CLAUDE_DIR/agent-tiers/.state/LAYERS.md"
INSTALLED="$CLAUDE_DIR/plugins/installed_plugins.json"

SETTINGS_1="$CLAUDE_DIR/settings.json"
SETTINGS_2="$DIR/.claude/settings.json"
SETTINGS_3="$DIR/.claude/settings.local.json"
[ "$SETTINGS_2" = "$SETTINGS_1" ] && SETTINGS_2=""

# ---------------------------------------------------------------------------------------------
# shared helpers
# ---------------------------------------------------------------------------------------------
have_jq() { command -v jq >/dev/null 2>&1; }

# id: first `path/to/name.ext` token (ext in sh|py|js|mjs, followed by a quote, space, shell
# separator `;&|)` or end) inside a command string, stripped to its basename. Hooks from
# project/local settings get a `project:` prefix so a cloned repo cannot borrow a registered
# user-settings id.
ID_RE='[^ "'\''$]+\.(sh|py|js|mjs)([ "'\'';&|)]|$)'
id_from_command() { # $1=event $2=command $3=prefix
  m="$(printf '%s\n' "$2" | grep -oE "$ID_RE" 2>/dev/null | head -1)"
  case "$m" in *[\"\'\ \;\&\|\)]) m="${m%?}" ;; esac
  if [ -n "$m" ]; then printf '%s%s\n' "$3" "${m##*/}"; else printf '%sinline:%s\n' "$3" "$1"; fi
}
settings_prefix() { [ "$1" = "$SETTINGS_1" ] || printf 'project:'; }

class_for_event() {
  case "$1" in
    SessionStart|InstructionsLoaded) echo always ;;
    UserPromptSubmit|UserPromptExpansion) echo per-prompt ;;
    SubagentStart) echo per-spawn ;;
    PreToolUse|PostToolUse|PostToolUseFailure|PostToolBatch|PermissionRequest|PermissionDenied) echo per-tool ;;
    *) echo other ;;
  esac
}

read_registry() {
  [ -f "$REGISTRY" ] || return 0
  grep -oE '^\|[[:space:]]*`[^`]+`' "$REGISTRY" 2>/dev/null | sed -E 's/^\|[[:space:]]*`//; s/`$//'
}

# enabled plugins across the given settings files: later file's key wins over an earlier value
enabled_plugins() {
  for f in ${1+"$@"}; do cat "$f"; done | jq -rs '
    map(.enabledPlugins // {} | if type == "object" then . else {} end)
    | reduce .[] as $m ({}; . * $m) | to_entries[] | select(.value == true)
    | .key | gsub("[[:cntrl:]]"; " ")' 2>/dev/null
}

# install root for a plugin id: a project/local-scope entry for THIS project wins, else the user
# entry (an entry with no scope field counts as user). Empty = not installed here.
plugin_root() {
  [ -f "$INSTALLED" ] || return 0
  jq -r --arg id "$1" --arg dir "$DIR" '
    (.plugins[$id] // []) as $e
    | ([$e[] | select((.scope == "project" or .scope == "local") and .projectPath == $dir)]
       + [$e[] | select((.scope // "user") == "user")])
    | .[0].installPath // empty' "$INSTALLED" 2>/dev/null
}

# one line per settings command hook: event US matcher US label US command. The label is what the
# debug log prints in `Hook <Event> (<label>)`: statusMessage when set, else the full command.
SETTINGS_HOOKS_JQ='
  def s: tostring | gsub("[[:cntrl:]]"; " ");
  .hooks // {} | objects | to_entries[] as $e
  | ($e.value | arrays | .[] | objects) as $grp
  | ($grp.hooks // [] | arrays | .[] | objects) as $h
  | select($h.type == "command")
  | [($e.key | s), (($grp.matcher // "") | s), (($h.statusMessage // $h.command // "") | s), (($h.command // "") | s)]
  | join([31] | implode)'

# one line per plugin matcher group: event US matcher US labels (RS-joined, one per command hook)
PLUGIN_ROWS_JQ='
  def s: tostring | gsub("[[:cntrl:]]"; " ");
  objects | (if (has("hooks") and (.hooks | type) == "object") then .hooks else . end)
  | to_entries[] as $e
  | ($e.value | arrays | .[] | objects) as $grp
  | [($e.key | s), (($grp.matcher // "") | s),
     ([$grp.hooks // [] | arrays | .[] | objects | select(.type == "command") | ((.statusMessage // .command // "") | s)] | join([30] | implode))]
  | join([31] | implode)'

# every hook map a plugin root declares, one compact JSON object per line. Manifest `hooks` may be
# an object, a path string, or an array of either; with no manifest `hooks` key (or no manifest at
# all) the default hooks/hooks.json is read.
plugin_hook_maps() { # $1=root
  pj="$1/.claude-plugin/plugin.json"
  if [ -f "$pj" ] && jq -e 'has("hooks")' "$pj" >/dev/null 2>&1; then
    jq -r '.hooks | if type == "array" then .[] else . end
      | if type == "string" then "F" + gsub("[[:cntrl:]]"; " ") else "J" + tojson end' "$pj" 2>/dev/null \
    | while IFS= read -r ent; do
        case "$ent" in
          F*) hf="${ent#F}"; hf="${hf#./}"; [ -f "$1/$hf" ] && jq -c '.hooks // {}' "$1/$hf" 2>/dev/null ;;
          J*) printf '%s\n' "${ent#J}" ;;
        esac
      done
  elif [ -f "$1/hooks/hooks.json" ]; then
    jq -c '.hooks // {}' "$1/hooks/hooks.json" 2>/dev/null
  fi
  return 0
}

# ---------------------------------------------------------------------------------------------
# --unregistered: fast, silent-on-any-trouble id dump for a SessionStart hook
# ---------------------------------------------------------------------------------------------
if [ "$MODE" = unregistered ]; then
  [ -f "$REGISTRY" ] || exit 0
  have_jq || exit 0
  set --
  oversized=0
  for f in "$SETTINGS_1" "$SETTINGS_2" "$SETTINGS_3"; do
    [ -f "$f" ] || continue
    if [ "$f" != "$SETTINGS_1" ]; then
      # project-controlled input: never parse a file big enough to push the hook past its timeout
      sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
      if ! [ "${sz:-0}" -le 65536 ] 2>/dev/null; then
        oversized=1
        continue
      fi
    fi
    jq -e . "$f" >/dev/null 2>&1 || exit 0
    set -- ${1+"$@"} "$f"
  done

  registry_ids="$(read_registry)"
  is_registered() { printf '%s\n' "$registry_ids" | grep -qxF -- "$1"; }

  WORK="$(mktemp -d 2>/dev/null)" || exit 0
  trap 'rm -rf "$WORK"' EXIT
  IDS="$WORK/ids"
  : > "$IDS" || exit 0

  enabled_plugins ${1+"$@"} | while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    [ -n "$(plugin_root "$pid")" ] && printf '%s\n' "$pid"
  done >> "$IDS"

  for f in ${1+"$@"}; do
    pfx="$(settings_prefix "$f")"
    jq -r "$SETTINGS_HOOKS_JQ" "$f" 2>/dev/null | while IFS="$US" read -r ev _matcher _label cmd; do
      id_from_command "$ev" "$cmd" "$pfx"
    done >> "$IDS"
  done

  [ "$oversized" = 1 ] && printf '%s\n' 'project:oversized-settings' >> "$IDS"

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    is_registered "$id" || printf '%s\n' "$id"
  done < "$IDS" | LC_ALL=C sort -u
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# full map
# ---------------------------------------------------------------------------------------------
have_jq || { echo "context-map: jq required" >&2; exit 2; }

registry_ids="$(read_registry)"
reg() { printf '%s\n' "$registry_ids" | grep -qxF -- "$1" && echo yes || echo no; }

WORK="$(mktemp -d)" || exit 2
trap 'rm -rf "$WORK"' EXIT
ROWS="$WORK/rows"; NOTES="$WORK/notes"; SEEN="$WORK/seen"
: > "$ROWS"; : > "$NOTES"; : > "$SEEN"

# columns: layer US id US event US class US size US registered US labels US fires
add_row() { printf '%s\n' "$1$US$2$US$3$US$4$US$5$US$6$US${7:-}$US${8:--}" >> "$ROWS"; }

set --
for f in "$SETTINGS_1" "$SETTINGS_2" "$SETTINGS_3"; do
  [ -f "$f" ] && jq -e . "$f" >/dev/null 2>&1 && set -- ${1+"$@"} "$f"
done

# --- base layers no file can show ------------------------------------------------------------------
add_row base claude-code-system-prompt session-load always unmeasured "$(reg claude-code-system-prompt)"
add_row base claude-code-harness 'every tool call' always unmeasured "$(reg claude-code-harness)"

# --- a. CLAUDE.md chain + rules (each resolved file once) -----------------------------------------
add_md_row() { # $1=abs path $2=id $3=event $4=class
  [ -f "$1" ] || return 0
  rp="$(CDPATH= cd -- "$(dirname "$1")" 2>/dev/null && pwd -P)/${1##*/}" || return 0
  grep -qxF -- "$rp" "$SEEN" && return 0
  printf '%s\n' "$rp" >> "$SEEN"
  bytes="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"
  imports="$(grep -c '^@' "$1" 2>/dev/null)" || imports=0
  idcell="$2"
  [ "${imports:-0}" -gt 0 ] 2>/dev/null && idcell="$2 (imports: $imports)"
  add_row 'CLAUDE.md chain' "$idcell" "$3" "$4" "${bytes}b" "$(reg "$2")"
}
chain_id() { case "$1" in "$DIR"/*) printf './%s\n' "${1#"$DIR"/}" ;; *) printf '%s\n' "$1" ;; esac; }
# a rule with `paths:` in its leading frontmatter loads only when matching files are read
add_rules() { # $1=rules dir $2=id prefix
  [ -d "$1" ] || return 0
  find -L "$1" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    if awk 'NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
            /^---[[:space:]]*$/ { exit }
            /^paths:/ { found = 1; exit }
            END { exit found ? 0 : 1 }' "$f" 2>/dev/null; then
      add_md_row "$f" "$2${f#"$1"/}" on-read on-demand
    else
      add_md_row "$f" "$2${f#"$1"/}" session-load always
    fi
  done
}

add_md_row /etc/claude-code/CLAUDE.md /etc/claude-code/CLAUDE.md session-load always
add_md_row "$CLAUDE_DIR/CLAUDE.md" '~/.claude/CLAUDE.md' session-load always
add_rules "$CLAUDE_DIR/rules" '~/.claude/rules/'

# walk from $DIR up to /: CLAUDE.md and CLAUDE.local.md everywhere, .claude/CLAUDE.md at project level
walk="$DIR"
while :; do
  names='CLAUDE.md CLAUDE.local.md'
  [ "$walk" = "$DIR" ] && names='CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md'
  for name in $names; do
    f="${walk%/}/$name"
    add_md_row "$f" "$(chain_id "$f")" session-load always
  done
  [ "$walk" = "/" ] && break
  walk="$(dirname "$walk")"
done

add_rules "$DIR/.claude/rules" './.claude/rules/'

# --- b. auto-memory index -----------------------------------------------------------------------
mem_dir=""
for f in ${1+"$@"}; do
  v="$(jq -r '.autoMemoryDirectory // empty | strings' "$f" 2>/dev/null)"
  [ -n "$v" ] && mem_dir="$v"
done
case "$mem_dir" in
  "~/"*) mem_dir="$HOME/${mem_dir#"~/"}" ;;
  /*) ;;
  *) mem_dir="" ;;
esac
if [ -z "$mem_dir" ]; then
  # one memory dir per git repo (worktrees and subdirs share it); outside git, the project dir
  mem_root="$DIR"
  gcd="$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -n "$gcd" ] \
    && mem_root="$(dirname "$gcd")"
  mem_dir="$CLAUDE_DIR/projects/$(printf '%s' "$mem_root" | tr -c 'A-Za-z0-9' '-')/memory"
fi
MEMFILE="$mem_dir/MEMORY.md"
if [ -f "$MEMFILE" ]; then
  total_bytes="$(wc -c < "$MEMFILE" | tr -d ' ')"
  loaded_bytes="$(head -n 200 "$MEMFILE" | wc -c | tr -d ' ')"
  [ "$loaded_bytes" -gt 25000 ] 2>/dev/null && loaded_bytes=25000
  idcell=auto-memory
  [ "$loaded_bytes" -lt "$total_bytes" ] 2>/dev/null && idcell="auto-memory (OVER: ${total_bytes}b total)"
  add_row 'auto-memory' "$idcell" 'session-load' 'always' "${loaded_bytes}b" "$(reg auto-memory)"
fi

# --- c/d. settings + plugin hook rows ------------------------------------------------------------
for f in ${1+"$@"}; do
  pfx="$(settings_prefix "$f")"
  jq -r "$SETTINGS_HOOKS_JQ" "$f" 2>/dev/null | while IFS="$US" read -r ev matcher label cmd; do
    id="$(id_from_command "$ev" "$cmd" "$pfx")"
    evcell="$ev"
    [ -n "$matcher" ] && evcell="$ev:$matcher"
    add_row 'settings hooks' "$id" "$evcell" "$(class_for_event "$ev")" '-' "$(reg "$id")" "$label"
  done
done

enabled="$(enabled_plugins ${1+"$@"})"
printf '%s\n' "$enabled" | while IFS= read -r pid; do
  [ -n "$pid" ] || continue
  root="$(plugin_root "$pid")"
  if [ -z "$root" ]; then
    add_row 'enabled plugins' "$pid" '-' 'not installed' '-' "$(reg "$pid")"
    continue
  fi
  plugin_hook_maps "$root" | jq -r "$PLUGIN_ROWS_JQ" 2>/dev/null | while IFS="$US" read -r ev matcher labels; do
    evcell="$ev"
    [ -n "$matcher" ] && evcell="$ev:$matcher"
    add_row 'enabled plugins' "$pid" "$evcell" "$(class_for_event "$ev")" '-' "$(reg "$pid")" "$labels"
  done
done

# --- e. outputStyle -------------------------------------------------------------------------------
outstyle=""
for f in ${1+"$@"}; do
  v="$(jq -r '.outputStyle // empty | strings | gsub("[[:cntrl:]]"; " ")' "$f" 2>/dev/null)"
  [ -n "$v" ] && outstyle="$v"
done
[ -z "$outstyle" ] && outstyle="default"
add_row 'outputStyle' "outputStyle:$outstyle" 'session-load' 'always' '-' "$(reg "outputStyle:$outstyle")"

# --- f. skills (size = skill count) ---------------------------------------------------------------
count_skills() { # $1=dir containing */SKILL.md
  n=0
  for s in "$1"/*/SKILL.md; do [ -f "$s" ] && n=$((n + 1)); done
  echo "$n"
}
n="$(count_skills "$CLAUDE_DIR/skills")"
[ "$n" -gt 0 ] && add_row 'skills' 'skills:user' 'on-demand' 'on-demand' "$n" "$(reg skills:user)"
n="$(count_skills "$DIR/.claude/skills")"
[ "$n" -gt 0 ] && add_row 'skills' 'skills:project' 'on-demand' 'on-demand' "$n" "$(reg skills:project)"
printf '%s\n' "$enabled" | while IFS= read -r pid; do
  [ -n "$pid" ] || continue
  root="$(plugin_root "$pid")"
  [ -n "$root" ] || continue
  n="$(count_skills "$root/skills")"
  [ "$n" -gt 0 ] && add_row 'skills' "skills:$pid" 'on-demand' 'on-demand' "$n" "$(reg "skills:$pid")"
done

# --- g. --log: sizes (chars) and firing counts for hook rows --------------------------------------
if [ -n "$LOG" ] && [ -f "$LOG" ]; then
  # JSON-output hooks: "Hook <Event> (<label>) provided additionalContext (<N> chars)"
  # -> lineno US timestamp US event US label US N
  JH="$WORK/jsonhits"
  grep -nE 'Hook [A-Za-z]+ \(.*\) provided additionalContext \([0-9]+ chars\)' "$LOG" 2>/dev/null \
    | sed -E "s/^([0-9]+):([^ ]+) .*Hook ([A-Za-z]+) \((.*)\) provided additionalContext \(([0-9]+) chars\).*/\1${US}\2${US}\3${US}\4${US}\5/" \
    > "$JH"

  # Plain-text hooks: [DEBUG] "Hook <Event>[:<source>] (<header>) success:\n<payload>". Plain stdout
  # reaches context only for SessionStart, UserPromptSubmit and UserPromptExpansion (hooks docs);
  # a payload starting with `{` is a JSON hook's own output, already counted above. <header> is
  # normally just the event name (no per-hook label reaches the log for plain stdout), so a plain
  # hit is credited to a row only on an exact match between <header> and that row's label - never
  # by scanning the payload text for a substring, which can mis-credit an unrelated row whose id or
  # label happens to appear inside another hook's payload.
  # -> lineno US timestamp US event US header US N US payload
  PH="$WORK/plainhits"
  : > "$PH"
  grep -nE '\[DEBUG\] "Hook ' "$LOG" 2>/dev/null | while IFS= read -r line; do
    ln="${line%%:*}"
    r="${line#*:}"
    ts="${r%% *}"
    rest="${r#*"[DEBUG] "}"
    out="$(printf '%s' "$rest" | jq -R -r '
      fromjson as $full
      | ($full | capture("^Hook (?<ev>[A-Za-z]+)[: ]")).ev as $ev
      | ($full | index("success:\n")) as $i
      | if $i == null then empty else
          ($full[0:$i]) as $header
          | ($full[($i + ("success:\n" | length)):]) as $payload
          | ( [$header | scan("^Hook [^ ]+ \\((.*)\\) success:$")] | .[0][0]? // "" ) as $label
          | [$ev, ($label | gsub("[[:cntrl:]]"; " ")), ($payload | length | tostring), ($payload | gsub("[[:cntrl:]]"; " "))] | join([31] | implode)
        end
    ' 2>/dev/null)"
    [ -n "$out" ] || continue
    ev="${out%%"$US"*}"
    rest2="${out#*"$US"}"
    hdr="${rest2%%"$US"*}"
    rest3="${rest2#*"$US"}"
    n="${rest3%%"$US"*}"
    payload="${rest3#*"$US"}"
    case "$ev" in SessionStart|UserPromptSubmit|UserPromptExpansion) ;; *) continue ;; esac
    case "$payload" in '{'*) continue ;; esac
    printf '%s\n' "$ln$US$ts$US$ev$US$hdr$US$n$US$payload" >> "$PH"
  done

  USED="$WORK/used"; : > "$USED"   # j<lineno> / p<lineno>: a log hit credited to a row already
  NEW="$WORK/rows.new"; : > "$NEW"
  while IFS="$US" read -r layer id evcell class size reg labels fires; do
    case "$layer" in
      'settings hooks'|'enabled plugins') ;;
      *) printf '%s\n' "$layer$US$id$US$evcell$US$class$US$size$US$reg$US$labels$US$fires" >> "$NEW"; continue ;;
    esac
    ev="${evcell%%:*}"
    total=0; matched=0; stamps=""
    # exact label match: the log label equals one of this row's labels
    while IFS="$US" read -r ln ts hev label n; do
      [ "$hev" = "$ev" ] || continue
      case "$RS$labels$RS" in *"$RS$label$RS"*) ;; *) continue ;; esac
      grep -qxF "j$ln" "$USED" && continue
      echo "j$ln" >> "$USED"
      total=$((total + n)); matched=1; stamps="$stamps$ts
"
    done < "$JH"
    # exact header match only: a plain hit's header normally just echoes the event, so this fires
    # only on the rare case where it carries a real per-hook label matching one of this row's labels
    while IFS="$US" read -r ln ts pev hdr n payload; do
      [ "$pev" = "$ev" ] || continue
      case "$RS$labels$RS" in *"$RS$hdr$RS"*) ;; *) continue ;; esac
      grep -qxF "p$ln" "$USED" && continue
      echo "p$ln" >> "$USED"
      total=$((total + n)); matched=1; stamps="$stamps$ts
"
    done < "$PH"
    if [ "$matched" = 1 ]; then
      size="${total}c"
      fires="$(printf '%s' "$stamps" | LC_ALL=C sort -u | grep -c .)"
    fi
    printf '%s\n' "$layer$US$id$US$evcell$US$class$US$size$US$reg$US$labels$US$fires" >> "$NEW"
  done < "$ROWS"
  mv "$NEW" "$ROWS"

  # anything no row claimed: one `log | unattributed` row per hit
  while IFS="$US" read -r ln ts ev _label n; do
    grep -qxF "j$ln" "$USED" && continue
    add_row log unattributed "$ev" "$(class_for_event "$ev")" "${n}c" '-' '' 1
  done < "$JH"
  while IFS="$US" read -r ln ts ev _hdr n _payload; do
    grep -qxF "p$ln" "$USED" && continue
    add_row log unattributed "$ev" "$(class_for_event "$ev")" "${n}c" '-' '' 1
  done < "$PH"

  grep -oE 'Skill listing over budget:.*' "$LOG" 2>/dev/null | while IFS= read -r l; do
    printf 'note: %s\n' "$l" >> "$NOTES"
  done
fi

# --- print: every cell escaped (`|` -> `\|`, control bytes -> space) ------------------------------
printf '| layer | id | event | class | size | registered | fires |\n'
printf '|---|---|---|---|---|---|---|\n'
LC_ALL=C awk -F "$US" '
  function cell(s,   o, i, c) {
    o = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c ~ /[[:cntrl:]]/) c = " "
      else if (c == "\\") c = "\\\\"
      else if (c == "|") c = "\\|"
      o = o c
    }
    return o
  }
  { print "| " cell($1) " | " cell($2) " | " cell($3) " | " cell($4) " | " cell($5) " | " cell($6) " | " cell($8) " |" }
' "$ROWS"

if [ -s "$NOTES" ]; then
  printf '\n'
  cat "$NOTES"
fi

if [ ! -f "$REGISTRY" ]; then
  printf '\nnote: no registry at %s; copy templates/LAYERS.md there to register layers\n' "$REGISTRY"
fi

exit 0

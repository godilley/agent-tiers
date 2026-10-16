#!/usr/bin/env sh
# kit-scope: shared
# kit-gate.sh - run as a CHILD process by every kit hook: decides whether the hook stands down.
#
# Call line, identical in every hook, after `set -u` (and any --probe branch); placement is free:
#   [ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0
# A child, not a dot-source: `. missing-or-broken-file` aborts the calling script (dash exits 2, which
# on PreToolUse blocks the tool call). The stand-down signal is a stdout TOKEN, not the exit status:
# an empty file, a file truncated after any complete command, a missing file or a syntax error all
# print no token, so each means "run".
#
#   sh kit-gate.sh <hook-path-or-id>   stand down: prints exactly `standdown`, exit 0. Run: prints
#                                      nothing, exit 1. The id is the basename minus .sh; an id that
#                                      is not [A-Za-z0-9_-]+ means run. Never reads stdin.
#   sh kit-gate.sh --summary           at most one `agent-tiers: ...` line (300 bytes max, cut with
#                                      ` ...`) naming groups off by an explicit option value and hooks
#                                      off by marker or disabled_hooks, only names options.tsv knows;
#                                      nothing when nothing is. Groups off only by plugin default are
#                                      not mentioned. Never reads stdin, never logs, exit 0.
#
# Kit root = the directory above this file (pwd -P). Stand down at the first that applies:
#   1. AGENT_TIERS_OFF is exactly 1 (0, empty or unset has no effect). Core hooks included.
#   2. <root>/.state/off/<id> exists. Core hooks included.
#   3. Route, from where the kit root sits on disk, never from env: `plugin` when the root is
#      <P>/cache/<marketplace>/<plugin>/<version> (exactly three components under a dir named `cache`)
#      and <P>/installed_plugins.json exists (Claude Code's plugin cache layout); else `flat`. Builtins
#      plus one test, no exec. In-place plugin loads (a local-directory marketplace, --plugin-dir) run
#      from their source dir and cannot be told from a flat install by path: they take the flat route
#      and its defaults (absent = on).
#   4. Option values come from FILES only, on both routes: pluginConfigs[<key>].options, read with ONE
#      jq call from, in precedence order, ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json, then per
#      managed dir (_kg_managed below) managed-settings.json and managed-settings.d/*.json sorted.
#      Later files win per single value (managed beats user); disabled_hooks lists are unioned; null
#      values are ignored. No CLAUDE_PLUGIN_OPTION_* or CLAUDE_PLUGIN_ROOT variable is read.
#      Key: plugin route, exactly <plugin>@<marketplace> from the root path (no entry = all absent);
#      flat route, the first agent-tiers@ key that user enabledPlugins marks true, else the first found.
#      When no store file mentions the key (flat: agent-tiers@) jq is skipped: the flat route runs the
#      hook at once, the plugin route goes straight to its defaults.
#      Defaults: flat, an absent option is on. Plugin, absent enabled = on, absent disabled_hooks =
#      empty, absent group_<g> = that group's `option` row default in install/options.tsv (false: a
#      plain plugin install is Core level).
#   5. enabled is false/0; the hook's group (options.tsv hook row; never `core`) is false/0; or
#      disabled_hooks lists the id as a whole item (JSON array, comma or space list).
# Each stand-down appends `<ts> kit-gate standdown <id>: <reason> [sid=<sid>]` to
# ${AGENT_TIERS_GUARDS_LOG:-<root>/.state/guards.log}, at most once per (id, reason, sid) within the
# log's last 64 KiB. sid = CLAUDE_CODE_SESSION_ID (set for hook subprocesses), filtered to
# [A-Za-z0-9._-]; unset means `[sid=]`, which logs once per 64 KiB window. guard-summary does not
# count these lines as blocks (it counts `deny:`/`ask:` only). A logging failure never changes the exit.
#
# Trust: a project settings env reaches hooks for any variable Claude Code does not set itself, so
# neither the route nor any option value comes from env. Residuals a project env still has:
#   - AGENT_TIERS_OFF=1 stands every kit hook down (logged);
#   - CLAUDE_CONFIG_DIR (and HOME when CLAUDE_CONFIG_DIR is unset) moves which user settings.json is
#     read, hiding the user's options: on the flat route that can re-enable hooks (not logged); on the
#     plugin route it can also stand down groups the user turned on (logged as plugin default);
#   - AGENT_TIERS_GUARDS_LOG redirects the log;
#   - PATH chooses which jq and sh run, as it already does for every hook.
# No kit-specific env var overrides a store path the gate reads. The gate reads managed FILES only:
# remote/server-managed and MDM (plist, registry) sources are not read, and Claude Code's own
# first-wins choice between managed sources is not modelled (every managed file found is merged).
# Link-mode `command`-source plugins and project-scoped plugin installs are not modelled either.
# Fails open: when a store file mentions the key but jq is missing or any store file is invalid JSON,
# the hook RUNS on both routes unless a marker or AGENT_TIERS_OFF already stood it down. On the plugin
# route that means a lookup error turns every wired non-core hook on, even with enabled=false. Invalid
# JSON in files none of which mention the key is never parsed: the plugin route takes its defaults.
# No options.tsv means no group and no default.
# Cost: on the flat route with no agent-tiers@ in any store file the run path execs one grep (none
# when no store file exists). Self-check: kit-gate.selfcheck.sh.
set -u
LC_ALL=C; export LC_ALL

_kg_managed='/etc/claude-code:/Library/Application Support/ClaudeCode'

_kg_tab="$(printf '\t')"
_kg_mode=gate
[ "${1:-}" = --summary ] && _kg_mode=summary
_kg_fail() { [ "$_kg_mode" = summary ] && exit 0; exit 1; }   # run (for --summary: say nothing)
case "$0" in */*) _kg_dir="${0%/*}" ;; *) _kg_dir=. ;; esac
_kg_root="$(CDPATH= cd -P -- "$_kg_dir/.." 2>/dev/null && pwd -P)" || _kg_fail
[ -n "$_kg_root" ] || _kg_fail
_kg_id= _kg_en= _kg_dis= _kg_gset= _kg_grp= _kg_glist= _kg_hlist= _kg_gv= _kg_gsrc= _kg_route=flat _kg_pkey=

_kg_isoff() { case "$1" in false | 0) return 0 ;; esac; return 1; }

# $1 = list of g=v words, $2 = g: prints v (empty when absent).
_kg_get() {
  _v=" $1 "
  case "$_v" in *" $2="*) _v="${_v#*" $2="}"; printf '%s' "${_v%% *}" ;; esac
}

# Whole-item match of id $2 in list $1 (any non-id character separates items).
_kg_listed() {
  case "$1" in
    "$2" | "$2"[!A-Za-z0-9_-]* | *[!A-Za-z0-9_-]"$2" | *[!A-Za-z0-9_-]"$2"[!A-Za-z0-9_-]*) return 0 ;;
  esac
  return 1
}

# options.tsv, pure shell: _kg_grp = group of $_kg_id, _kg_glist = "g=default ..." per group_<g> row,
# _kg_hlist = " id id ..." every hook row id.
_kg_tsv() {
  _f="$_kg_root/install/options.tsv"
  [ -r "$_f" ] || return 0
  _seen=0
  while IFS="$_kg_tab" read -r _k _a _b _c _rest || [ -n "${_k:-}" ]; do
    case "$_k" in
      hook)
        case "$_a" in '' | *[!A-Za-z0-9_-]*) continue ;; esac
        _kg_hlist="$_kg_hlist $_a"
        [ "$_seen" = 0 ] && [ "$_a" = "$_kg_id" ] && { _kg_grp="$_b"; _seen=1; } ;;
      option)
        case "$_a" in group_*) ;; *) continue ;; esac
        _g="${_a#group_}"
        case "$_g" in '' | [!a-z]* | *[!a-z0-9_]*) continue ;; esac
        _c="${_c:-on}"; case "$_c" in true | false) ;; *) _c=on ;; esac
        _kg_glist="$_kg_glist $_g=$_c" ;;
    esac
  done < "$_f"
  case "$_kg_grp" in '' | [!a-z]* | *[!a-z0-9_]*) _kg_grp= ;; esac
}

# Plugin value of group $1 into _kg_gv/_kg_gsrc: the stored option, else the options.tsv default.
_kg_pgroup() {
  _kg_gv="$(_kg_get "$_kg_gset" "$1")"; _kg_gsrc=plugin
  [ -n "$_kg_gv" ] || { _kg_gv="$(_kg_get "$_kg_glist" "$1")"; _kg_gsrc="plugin default"; }
}

# Values from the store files: _kg_en, _kg_dis, _kg_gset ("g=v ..." per stored group, v = false, 0
# or on). Returns 1 when no store file mentions the key, 2 on a lookup error (no jq, jq failed).
_kg_read() {
  _u="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  set --
  [ -f "$_u" ] && [ -r "$_u" ] && set -- "$_u"
  _ifs="$IFS"; IFS=:; set -f
  for _md in $_kg_managed; do
    IFS="$_ifs"; set +f
    [ -f "$_md/managed-settings.json" ] && [ -r "$_md/managed-settings.json" ] && set -- "$@" "$_md/managed-settings.json"
    for _mf in "$_md"/managed-settings.d/*.json; do
      [ -f "$_mf" ] && [ -r "$_mf" ] && set -- "$@" "$_mf"
    done
  done
  IFS="$_ifs"; set +f
  [ "$#" -gt 0 ] || return 1
  grep -qsF -e "${_kg_pkey:-agent-tiers@}" -- "$@" 2>/dev/null || return 1
  command -v jq >/dev/null 2>&1 || return 2
  _js="$(jq -rn --arg u "$_u" --arg pk "$_kg_pkey" '
    def s: if . == null then "" elif type == "array" then map(tostring) | join(" ") else tostring end;
    [inputs | {f: input_filename, v: .}] as $d
    | ([$d[] | select(.f == $u) | .v.enabledPlugins][0] // {}) as $ep
    | [$d[] | .v.pluginConfigs // {} | keys_unsorted[] | select(startswith("agent-tiers@"))] as $ks
    | (if $pk != "" then $pk else ([$ks[] | select($ep[.] == true)][0] // $ks[0]) end) as $k
    | if $k == null then "_kg_en=" else
        [$d[] | .v.pluginConfigs[$k].options // {} | objects] as $os
        | (reduce $os[] as $o ({}; . + ($o | with_entries(select(.value != null))))) as $m
        | "_kg_en=\($m.enabled | s | @sh)",
          "_kg_dis=\([$os[] | .disabled_hooks | s] | join(" ") | @sh)",
          "_kg_gset=\([$m | to_entries[] | select(.key | test("^group_[a-z][a-z0-9_]*$"))
                     | {g: (.key | ltrimstr("group_")), v: (.value | s)}
                     | "\(.g)=\(if .v == "false" or .v == "0" then .v else "on" end)"] | join(" ") | @sh)"
      end' "$@" 2>/dev/null)" && [ -n "$_js" ] || return 2
  eval "$_js"
  return 0
}

# Route plus values. Returns 1 (run) when there is nothing to read on the flat route, or on a lookup
# error on either route. Route: strip exactly three components (<m>/<p>/<v>); the rest must be <P>/cache.
_kg_values() {
  _r="${_kg_root%/*}"; _p="${_r##*/}"; _r="${_r%/*}"; _m="${_r##*/}"; _r="${_r%/*}"
  case "$_r" in
    */cache) [ -n "$_p" ] && [ -n "$_m" ] && [ -f "${_r%/cache}/installed_plugins.json" ] \
      && { _kg_route=plugin; _kg_pkey="$_p@$_m"; } ;;
  esac
  _kg_read; _rc=$?
  if [ "$_kg_route" = plugin ]; then
    [ "$_rc" = 2 ] && return 1
  else
    [ "$_rc" = 0 ] || return 1
  fi
  _kg_tsv
  return 0
}

_kg_down() { # $1 = reason; logs once per (id, reason, sid), then prints the stand-down token
  _sid="${CLAUDE_CODE_SESSION_ID:-}"
  _sid="${_sid%%[!A-Za-z0-9._-]*}"
  _log="${AGENT_TIERS_GUARDS_LOG:-$_kg_root/.state/guards.log}"
  _line=" kit-gate standdown $_kg_id: $1 [sid=$_sid]"
  {
    tail -c 65536 "$_log" 2>/dev/null | grep -qF -- "$_line" || {
      case "$_log" in */*) mkdir -p "${_log%/*}" ;; esac
      printf '%s%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$_line" >> "$_log"
    }
  } 2>/dev/null || true
  echo standdown
  exit 0
}

_kg_summary() {
  [ "${AGENT_TIERS_OFF:-}" = 1 ] && { echo "agent-tiers: every kit hook is off (AGENT_TIERS_OFF=1)"; exit 0; }
  _kg_values || _kg_tsv   # flat with nothing to read still needs the tsv names for markers
  _kg_isoff "$_kg_en" && { echo "agent-tiers: every kit hook is off (option enabled=$_kg_en ($_kg_route))"; exit 0; }
  _grps= _hooks= _seenh=" "
  # Only names options.tsv knows: groups with a group_<g> row, hooks with a hook row; each listed once.
  for _gd in $_kg_glist; do
    _g="${_gd%%=*}"; [ "$_g" = core ] && continue
    if [ "$_kg_route" = plugin ]; then
      _kg_pgroup "$_g"
      [ "$_kg_gsrc" = plugin ] && _kg_isoff "$_kg_gv" && _grps="${_grps:+$_grps, }$_g"
    else
      _kg_isoff "$(_kg_get "$_kg_gset" "$_g")" && _grps="${_grps:+$_grps, }$_g"
    fi
  done
  for _h in $_kg_hlist; do
    case "$_seenh" in *" $_h "*) continue ;; esac
    if [ -e "$_kg_root/.state/off/$_h" ]; then _hooks="${_hooks:+$_hooks, }$_h (marker)"
    elif _kg_listed "$_kg_dis" "$_h"; then _hooks="${_hooks:+$_hooks, }$_h (disabled_hooks)"
    else continue; fi
    _seenh="$_seenh$_h "
  done
  _out=
  [ -n "$_grps" ] && _out="groups off ($_kg_route): $_grps"
  [ -n "$_hooks" ] && _out="${_out:+$_out; }hooks off: $_hooks"
  [ -n "$_out" ] || exit 0
  _out="agent-tiers: $_out"
  if [ "${#_out}" -gt 300 ]; then printf '%.296s ...\n' "$_out"; else printf '%s\n' "$_out"; fi
  exit 0
}

[ "$_kg_mode" = summary ] && _kg_summary

_kg_id="${1:-}"; _kg_id="${_kg_id##*/}"; _kg_id="${_kg_id%.sh}"
case "$_kg_id" in '' | *[!A-Za-z0-9_-]*) exit 1 ;; esac
[ "${AGENT_TIERS_OFF:-}" = 1 ] && _kg_down "AGENT_TIERS_OFF=1"
[ -e "$_kg_root/.state/off/$_kg_id" ] && _kg_down "marker .state/off/$_kg_id"
_kg_values || exit 1
_kg_isoff "$_kg_en" && _kg_down "option enabled=$_kg_en ($_kg_route)"
if [ -n "$_kg_grp" ] && [ "$_kg_grp" != core ]; then
  if [ "$_kg_route" = plugin ]; then
    _kg_pgroup "$_kg_grp"
  else
    _kg_gv="$(_kg_get "$_kg_gset" "$_kg_grp")"; _kg_gsrc=flat
  fi
  _kg_isoff "$_kg_gv" && _kg_down "option group_$_kg_grp=$_kg_gv ($_kg_gsrc)"
fi
_kg_listed "$_kg_dis" "$_kg_id" && _kg_down "option disabled_hooks lists $_kg_id ($_kg_route)"
exit 1

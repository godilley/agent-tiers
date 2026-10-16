#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PostToolUse(Bash|mcp__chrome-devtools__*|mcp__claudecodebrowser__*) hook: the second half of
# reach-guard's browser arm and of its read-only Bash session grants. It runs only after a tool call ran,
# so a pending marker reach-guard wrote at PreToolUse for an ask means the ask was approved.
#
#   0. Bash (after step 1's id checks): no pending marker for this tool_use_id -> exit 0 (this hook
#      runs after every Bash call, so that path is the kit gate and one jq parse). With a marker, only
#      `rgrant <group> <target> <program>` lines count (re-checked: one shell-safe token each, no glob, quote, space, leading ~
#      or -); each adds `<group> <target>` to rgrant.<sid> once (logged `reach-guard grant:
#      <group>/<program> target=<t> level=ro`), and the marker is removed. reach-guard writes such a
#      line only for the attended Lead and honours rgrant.<sid> only for the attended Lead, as an exact
#      (group, target) match for read-only results; act, unsure and never-allowable results are never
#      covered. An mcp call ignores `rgrant` lines; a Bash call ignores every other kind.
#   1. session_id and tool_use_id must be id-shaped, else exit 0.
#   2. chrome-devtools only: a response holding `Page ids have changed.` wipes the page map first.
#   3. Pending marker <state>/reach-guard/pending/<sid>.<tool_use_id>, written by reach-guard: a `grant`
#      line adds `<host> <class>` to grant.<sid> (logged); a `map` line places a navigate_page url's
#      page id on the host reach-guard judged, only when the response holds a `## Pages` block from a
#      listing tool (a successful navigation; an error result leaves the page unknown); a `newpage` line
#      binds the highest page id in the response's `## Pages` block to the host. The marker is removed.
#   4. chrome-devtools only: in a navigate_page, new_page, list_pages, select_page or close_page response
#      (the page list is the server's own there, one line per page since a title holds no newline) a
#      `## Pages` line whose host differs from the page's last entry makes that page @unknown (an `obs`
#      entry), never the parsed host; every other tool's `## Pages` text is ignored. A `Page navigated
#      to <url>.` line (any tool) does the same for the input pageId, or with no pageId for every page
#      not already unknown. So a response can only ever make a page unknown: only reach-guard's own
#      judgement of an agent-supplied URL (navigate_page url, new_page) places a page on a host.
# Never prints on stdout. Fails open (logged) only for no jq and an unparseable payload; with no jq a
# Bash call exits silently (one log line per Bash call would be noise).
# Ceilings: a page that navigates itself without the call's response saying so (a meta refresh, a timer
# set by evaluate_script, a later script redirect) keeps its last entry, local included, until a listing
# response or a navigate_page re-places it, and sub-agents and unattended sessions can act on it
# meanwhile. A restart of the MCP server process reuses page ids without `Page ids have changed.`, so a
# stale entry holds until a listing re-observes the page. Page-controlled response text can forge a
# `Page navigated to` line or `Page ids have changed.`; either only makes pages unknown. A grant is
# written for any approved ask, whoever approved it: an auto-approving permission hook, a
# permission-prompt tool or an automatic approval mode leads to a grant as a person would; the same
# holds for a Bash grant. A Bash grant on an `@default` target (kubectl:@default and the like) trusts the
# exported environment the same way an @default allowlist row does.
# list_pages, select_page, close_page and emulate are local-role tools in reach-guard and run for
# sub-agents too (list_pages shows every open page's URL).
# Self-check: reach-guard-grant.selfcheck.sh
set -u
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0
LC_ALL=C; export LC_ALL

SELFDIR="$(CDPATH= cd -P "$(dirname "$0")" 2>/dev/null && pwd -P || true)"
[ -n "$SELFDIR" ] || SELFDIR="$(dirname "$0")"
KIT="${SELFDIR%/*}"
LOG="${AGENT_TIERS_GUARDS_LOG:-$KIT/.state/guards.log}"
TAB="$(printf '\t')"
INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
SID=""

glog() { # glog <text>: one line, [sid=] last
  { mkdir -p "${LOG%/*}" && printf '%s %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "$SID" >> "$LOG"; } 2>/dev/null || true
}
clean() { printf '%s' "$1" | tr -cd 'A-Za-z0-9._:@/*-' | cut -c1-80; }

if ! command -v jq >/dev/null 2>&1; then
  # this hook runs after every Bash call: no fail-open line per call (reach-guard logs its own)
  printf '%s' "$INPUT" | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"Bash"' && exit 0
  SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9._-]*\)".*/\1/p' | head -n 1)"
  glog "reach-guard-grant fail-open: jq not found"
  exit 0
fi
META="$(printf '%s' "$INPUT" | jq -r '[(.tool_name // ""), (.session_id // ""), (.tool_use_id // ""),
  (.tool_input.pageId | if type == "number" and . >= 0 and . == floor then tostring else "" end)]
  | .[] | tostring | gsub("[\n\r]"; " ")' 2>/dev/null)" && [ -n "$META" ] || {
  glog "reach-guard-grant fail-open: unparseable payload"
  exit 0
}
{ IFS= read -r TOOL; IFS= read -r SID; IFS= read -r TUID; IFS= read -r PID; } <<EOF
$META
EOF
case "$SID" in "" | *[!A-Za-z0-9._-]*) exit 0 ;; esac
case "$TUID" in "" | *[!A-Za-z0-9_-]*) exit 0 ;; esac
case "$PID" in "" | *[!0-9]*) PID="" ;; esac

STATE="${AGENT_TIERS_STATE_DIR:-$KIT/.state}"
case "$STATE" in */.state) ;; *) STATE="$STATE/.state" ;; esac
RD="$STATE/reach-guard"
PAGES="$RD/pages.$SID"
PF="$RD/pending/$SID.$TUID"
# Bash: this hook runs after every Bash call; only a call reach-guard left a pending marker for matters
if [ "$TOOL" = Bash ]; then
  [ -f "$PF" ] || exit 0
  while IFS= read -r line; do
    # split by hand: read with IFS=TAB would collapse an empty field
    case "$line" in "rgrant$TAB"*"$TAB"*"$TAB"*) ;; *) continue ;; esac
    r="${line#rgrant"$TAB"}"; a="${r%%"$TAB"*}"; r="${r#*"$TAB"}"; b="${r%%"$TAB"*}"; c="${r#*"$TAB"}"
    ok=1
    for w in "$a" "$b"; do case "$w" in "" | [~-]* | *[!A-Za-z0-9._:@%+,=~/-]*) ok=0 ;; esac; done
    [ "$ok" = 1 ] || continue
    gf="$RD/rgrant.$SID"
    grep -qxF "$a$TAB$b" "$gf" 2>/dev/null || { printf '%s\t%s\n' "$a" "$b" >> "$gf"; } 2>/dev/null
    glog "reach-guard grant: $(clean "$a")/$(clean "$c") target=$(clean "$b") level=ro"
  done < "$PF"
  rm -f "$PF" 2>/dev/null
  exit 0
fi

# chrome-devtools is the server whose response format (`## Pages`, `Page navigated to`) this parses
CDP=0; case "$TOOL" in mcp__chrome-devtools__*) CDP=1 ;; esac
# the tools whose `## Pages` block is the server's own page list
LIST=0; case "$TOOL" in mcp__chrome-devtools__navigate_page | mcp__chrome-devtools__new_page | mcp__chrome-devtools__list_pages | mcp__chrome-devtools__select_page | mcp__chrome-devtools__close_page) LIST=1 ;; esac
TEXT=""
if [ "$CDP" = 1 ] || [ -f "$PF" ]; then
  TEXT="$(printf '%s' "$INPUT" | jq -r '
    def texts: if type == "string" then .
      elif type == "array" then .[] | texts
      elif type == "object" then ((.text | select(type == "string")), (.content // empty | texts))
      else empty end;
    [.tool_response | texts] | join("\n")' 2>/dev/null)"
fi

PAWK='
# url2host: begin (reach-guard.sh and reach-guard-grant.sh carry identical copies; the selfchecks compare them)
# scheme marker `scheme:<name>` for a non-web scheme, the host for http(s)/ws(s), else @unknown; blob: is
# the host of its inner URL; file: only with an empty or localhost authority; devtools: with a query is unknown
function url2host(u,   i, sc, a, j) {
  i = index(u, ":")
  if (i < 2) return "@unknown"
  sc = tolower(substr(u, 1, i - 1))
  if (sc !~ /^[a-z][a-z0-9+.-]*$/) return "@unknown"
  a = substr(u, i + 1)
  if (sc == "blob") return url2host(a)
  if (sc == "file") return (!index(a, "\\") && (tolower(a) ~ /^\/\/(localhost)?\/([^\/]|$)/ || a ~ /^\/([^\/]|$)/)) ? "scheme:file" : "@unknown"
  if (sc == "devtools" && index(a, "?")) return "@unknown"
  if (sc != "http" && sc != "https" && sc != "ws" && sc != "wss") return "scheme:" sc
  if (substr(a, 1, 2) != "//") return "@unknown"
  a = substr(a, 3)
  if (match(a, /[\/?#\\]/)) a = substr(a, 1, RSTART - 1)
  while ((j = index(a, "@")) > 0) a = substr(a, j + 1)
  if (substr(a, 1, 1) == "[") { j = index(a, "]"); if (j < 3) return "@unknown"; a = substr(a, 2, j - 2) }
  else sub(/:.*/, "", a)
  a = tolower(a); sub(/\.$/, "", a)
  if (a == "" || a !~ /^[a-z0-9._%:-]+$/) return "@unknown"
  return a
}
# url2host: end
function lastidx(s, t,   i, k) { k = 0; while ((i = index(substr(s, k + 1), t)) > 0) k += i; return k }
function obs(id, h) { if (!(id in CUR) || CUR[id] != h) { CUR[id] = h; print id "\t" h "\tobs" } }
# seen(id, h): a response shows page id on host h; a change only ever makes the page unknown
function seen(id, h) { if (!(id in CUR) || CUR[id] != h) obs(id, "@unknown") }
BEGIN {
  mode = ENVIRON["RG_MODE"]; pid = ENVIRON["RG_PID"]; f = ENVIRON["RG_PAGES"]; list = (ENVIRON["RG_LIST"] == 1)
  if (mode == "obs") { while ((getline l < f) > 0) if (split(l, A, "\t") == 3) CUR[A[1]] = A[2]; close(f) }
}
{ sub(/\r$/, "") }
/^## / { inb = (list && $0 ~ /^## Pages[ \t]*$/); next }
inb && /^[0-9]+: / {
  id = $0; sub(/:.*/, "", id); rest = substr($0, length(id) + 3)
  if (mode == "maxid") { if (max == "" || id + 0 > max + 0) max = id; next }
  if ((i = lastidx(rest, " isolatedContext=")) > 0) rest = substr(rest, 1, i - 1)
  sub(/ \[selected\]$/, "", rest)
  if (rest ~ /\)$/ && (i = lastidx(rest, " (")) > 0) rest = substr(rest, i + 2, length(rest) - i - 2)
  seen(id, url2host(rest)); next
}
mode == "obs" && /^Page navigated to .*\.$/ {
  u = substr($0, 19); u = url2host(substr(u, 1, length(u) - 1))
  if (pid != "") seen(pid, u)
  else for (k in CUR) if (CUR[k] != "@unknown") obs(k, "@unknown")
}
END { if (mode == "maxid" && max != "") print max }'

append() { { mkdir -p "$RD" && printf '%s\n' "$1" >> "$PAGES"; } 2>/dev/null || true; }

if [ "$CDP" = 1 ]; then
  case "$TEXT" in *"Page ids have changed."*) rm -f "$PAGES" 2>/dev/null ;; esac
fi

if [ -f "$PF" ]; then
  while IFS="$TAB" read -r k a b c; do
    case "$k" in
      grant)
        case "$b" in observe | act) ;; *) continue ;; esac
        [ -n "$a" ] || continue
        gf="$RD/grant.$SID"
        grep -qxF "$a$TAB$b" "$gf" 2>/dev/null || { printf '%s\t%s\n' "$a" "$b" >> "$gf"; } 2>/dev/null
        glog "reach-guard grant: browser_auto/$(clean "${c:-$TOOL}") target=$(clean "$a") role=$b" ;;
      map) # only a successful navigation carries the listing; an error result leaves the page unknown
        case "$a" in "" | *[!0-9]*) continue ;; esac
        [ "$LIST" = 1 ] && printf '%s\n' "$TEXT" | grep -q '^## Pages[[:space:]]*$' || continue
        [ -n "$b" ] && append "$a$TAB$b${TAB}pre" ;;
      newpage)
        [ -n "$a" ] || continue
        id="$(printf '%s\n' "$TEXT" | RG_MODE=maxid RG_LIST="$LIST" awk "$PAWK" 2>/dev/null)"
        [ -n "$id" ] && append "$id$TAB$a${TAB}pre" ;;
    esac
  done < "$PF"
  rm -f "$PF" 2>/dev/null
fi

if [ "$CDP" = 1 ] && [ -n "$TEXT" ]; then
  NEW="$(printf '%s\n' "$TEXT" | RG_MODE=obs RG_LIST="$LIST" RG_PID="$PID" RG_PAGES="$PAGES" awk "$PAWK" 2>/dev/null)"
  [ -n "$NEW" ] && append "$NEW"
fi
exit 0

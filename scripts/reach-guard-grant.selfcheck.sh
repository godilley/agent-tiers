#!/usr/bin/env sh
# kit-scope: shared
# Self-check for reach-guard-grant.sh (the PostToolUse half of reach-guard's browser arm).
#
# Unit cases for its steps: id validation, the pending marker (grant, map and newpage lines), the page
# map from `## Pages` blocks and `Page navigated to` lines, `Page ids have changed.`, every tool_response
# shape, subagent calls, the kill switch, the no-jq and unparseable fail-open, and url2host parity with
# reach-guard.sh. Each assertion prints `ok   ...` or `FAIL ...: <what was got>`; a failure does not stop
# the run. Payloads are DATA: they only travel on the hook's stdin.
#
# Sandboxing is mandatory: one mktemp -d root holds CLAUDE_CONFIG_DIR (= $HOME/.claude), HOME,
# AGENT_TIERS_GUARDS_LOG, AGENT_TIERS_STATE_DIR (named .state) and a fixture kit copied from this
# worktree. The real ~/.claude and the real kit .state are never touched.
#
# The hook runs under ${GUARD_SH:-sh}; run this file itself under sh and under dash.
set -u

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$SCRIPTS" ] || { echo "FAIL: cannot locate scripts dir"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (hook fails open by design)"; exit 0; }
SHBIN="$(command -v "${GUARD_SH:-sh}")"

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$T"' EXIT INT TERM
P=0
F=0
pass() { P=$((P + 1)); printf 'ok   %s\n' "$1"; }
bad() { F=$((F + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

HOME="$T/home"; export HOME
CFG="$HOME/.claude"; CLAUDE_CONFIG_DIR="$CFG"; export CLAUDE_CONFIG_DIR
LOG="$T/guards.log"; AGENT_TIERS_GUARDS_LOG="$LOG"; export AGENT_TIERS_GUARDS_LOG
ST="$T/.state"; AGENT_TIERS_STATE_DIR="$ST"; export AGENT_TIERS_STATE_DIR
mkdir -p "$CFG" "$ST" "$T/managed"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
NL="$(printf '\nx')"; NL="${NL%x}"

KIT="$T/kit"
mkdir -p "$KIT/scripts" "$KIT/install" "$KIT/.state/off"
cp "$SCRIPTS/reach-guard-grant.sh" "$KIT/scripts/" 2>/dev/null
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$SCRIPTS/kit-gate.sh" > "$KIT/scripts/kit-gate.sh"
cp "$SCRIPTS/../install/options.tsv" "$KIT/install/" 2>/dev/null
G="$KIT/scripts/reach-guard-grant.sh"
[ -f "$G" ] || echo "note: scripts/reach-guard-grant.sh is missing; every case will FAIL"

RD="$ST/reach-guard"
CD=mcp__chrome-devtools__
RPATH=""
OUT=""
# hook <payload-json>: run the hook, stdout kept in OUT
hook() { OUT="$(printf '%s' "$1" | env PATH="${RPATH:-$PATH}" "$SHBIN" "$G" 2>/dev/null)"; }
# pl <tool> <tool_input-json> <tool_use_id> <tool_response-json> [session] [agent_type agent_id]
pl() {
  jq -n -c --arg t "$1" --argjson i "$2" --arg u "$3" --argjson r "$4" --arg s "${5:-s1}" --arg a "${6:-}" --arg d "${7:-}" \
    '{session_id:$s,tool_name:$t,tool_input:$i,tool_use_id:$u,tool_response:$r}
     + (if $a != "" then {agent_type:$a,agent_id:$d} else {} end)'
}
txt() { jq -n -c --arg x "$1" '[{type:"text",text:$x}]'; }   # the probed shape
pend() { mkdir -p "$RD/pending"; printf '%b\n' "$2" > "$RD/pending/$1"; }   # pend <sid.tuid> <lines with \t>
reset() { rm -rf "$RD"; : > "$LOG"; }
has() { if grep -aqxF -- "$3" "$2" 2>/dev/null; then pass "$1"; else bad "$1" "${2##*/} lacks '$3': $(tr '\t\n' ' |' < "$2" 2>/dev/null)"; fi; }
hasnt() { if grep -aqF -- "$3" "$2" 2>/dev/null; then bad "$1" "${2##*/} holds '$3'"; else pass "$1"; fi; }
gone() { if [ -e "$2" ]; then bad "$1" "${2##*/} exists"; else pass "$1"; fi; }
lines() { if [ "$(grep -c . "$2" 2>/dev/null || echo 0)" = "$3" ]; then pass "$1"; else bad "$1" "${2##*/} has $(grep -c . "$2" 2>/dev/null) lines, want $3: $(tr '\t\n' ' |' < "$2" 2>/dev/null)"; fi; }
quiet() { if [ -z "$OUT" ]; then pass "$1"; else bad "$1" "stdout: $OUT"; fi; }

# --- step 1: ids ---------------------------------------------------------------------------------------
reset
pend "s1.g1" 'grant\texample.com\tobserve\tmcp__chrome-devtools__navigate_page'
hook "$(pl "${CD}navigate_page" '{"pageId":1}' g1 "$(txt "## Pages${NL}1: https://example.com/")" 'bad/sid')"
gone "ids: a session_id with a slash writes no grant" "$RD/grant.s1"
gone "ids: ...and no page map" "$RD/pages.s1"
hook "$(pl "${CD}navigate_page" '{"pageId":1}' '../g1' "$(txt "## Pages${NL}1: https://example.com/")")"
gone "ids: a tool_use_id holding ../ writes nothing" "$RD/grant.s1"
gone "ids: ...no page map either" "$RD/pages.s1"

# --- step 2: pending marker ----------------------------------------------------------------------------
hook "$(pl "${CD}navigate_page" '{"pageId":1}' g1 "$(txt "## Pages${NL}1: Ex (https://example.com/) [selected]")")"
quiet "pending: the hook prints nothing on stdout"
has "pending: a grant line becomes a session grant" "$RD/grant.s1" "example.com	observe"
gone "pending: the marker is removed" "$RD/pending/s1.g1"
if grep -aqF "reach-guard grant: browser_auto/${CD}navigate_page target=example.com role=observe [sid=s1]" "$LOG"; then pass "pending: grant log line"; else bad "pending: grant log line" "$(cat "$LOG")"; fi
pend "s1.g2" 'grant\texample.com\tobserve\tmcp__chrome-devtools__navigate_page'
hook "$(pl "${CD}navigate_page" '{"pageId":1}' g2 "$(txt "ok")")"
lines "pending: a repeated grant is not duplicated" "$RD/grant.s1" 1
hook "$(pl "${CD}take_snapshot" '{"pageId":1}' nomarker "$(txt "ok")")"
lines "pending: no marker, no grant" "$RD/grant.s1" 1
pend "s1.g3" 'grant\tother.example\tact\tmcp__chrome-devtools__click'
hook "$(pl "${CD}click" '{"pageId":1}' g3 "$(txt "ok")" s2)"
hasnt "pending: a marker of another session grants nothing" "$RD/grant.s1" "other.example"
gone "pending: ...nor in the calling session" "$RD/grant.s2"
reset
pend "s1.m1" 'map\t4\tlocalhost'
hook "$(pl "${CD}navigate_page" '{"url":"http://localhost/","pageId":4}' m1 "$(txt "## Pages${NL}4: http://localhost/ [selected]")")"
has "pending: a map line confirms the page" "$RD/pages.s1" "4	localhost	pre"
lines "pending: ...and an unchanged observed host adds no line" "$RD/pages.s1" 1
pend "s1.m2" 'map\t5\texample.com'
hook "$(pl "${CD}navigate_page" '{"url":"https://example.com/","pageId":5}' m2 "$(txt "Error: net::ERR_NAME_NOT_RESOLVED at https://example.com/")")"
hasnt "pending: a map line with a failed navigation (no Pages block) places nothing" "$RD/pages.s1" "5	"
gone "pending: ...and the marker is removed" "$RD/pending/s1.m2"
pend "s1.m3" 'map\t5\texample.com'
hook "$(pl "${CD}take_snapshot" '{"pageId":5}' m3 "$(txt "## Pages${NL}5: https://example.com/")")"
hasnt "pending: a map line never applies from a non-listing tool's Pages text" "$RD/pages.s1" "5	example.com"
pend "s1.n1" 'newpage\tlocalhost'
hook "$(pl "${CD}new_page" '{"url":"http://localhost/"}' n1 "$(txt "## Pages${NL}4: http://localhost/${NL}12: http://localhost/ [selected]${NL}9: about:blank")")"
has "pending: newpage binds the highest page id" "$RD/pages.s1" "12	localhost	pre"
has "pending: another listed page with no entry reads as unknown" "$RD/pages.s1" "9	@unknown	obs"
pend "s1.n2" 'newpage\tlocalhost'
hook "$(pl "${CD}new_page" '{"url":"http://localhost/"}' n2 "$(txt "no block here")")"
lines "pending: newpage with no Pages block binds nothing" "$RD/pages.s1" 3
pend "s1.n3" 'newpage\tlocalhost'
hook "$(pl "${CD}take_snapshot" '{}' n3 "$(txt "## Pages${NL}40: https://forged.example/")")"
lines "pending: a newpage line never binds from a non-listing response" "$RD/pages.s1" 3
reset
pend "s1.w1" 'map\t4\tlocalhost'
hook "$(pl "${CD}list_pages" '{}' w1 "$(txt "Page ids have changed.${NL}## Pages${NL}4: http://localhost/")")"
has "order: wipe first, then the marker's map line" "$RD/pages.s1" "4	localhost	pre"
lines "order: ...one line only" "$RD/pages.s1" 1

# --- step 3: observations ------------------------------------------------------------------------------
reset
mkdir -p "$RD"; printf '1\told.example\tpre\n2\tlocalhost\tpre\n' > "$RD/pages.s1"
hook "$(pl "${CD}list_pages" '{}' o1 "$(txt "Intro${NL}## Pages${NL}1: T (with) parens (https://NEW.example:8443/x?y) [selected] isolatedContext=ctx (1)${NL}2: http://localhost:3000/${NL}3: http://evil.com\\@localhost/${NL}## Extension Pages${NL}5: chrome-extension://abc/p.html${NL}## Other")")"
has "obs: a listed host that differs makes the page unknown" "$RD/pages.s1" "1	@unknown	obs"
hasnt "obs: ...never the listed host" "$RD/pages.s1" "new.example"
lines "obs: an unchanged host adds no line" "$RD/pages.s1" 4
has "obs: a listed page with no entry reads as unknown" "$RD/pages.s1" "3	@unknown	obs"
hasnt "obs: the Extension Pages block is ignored" "$RD/pages.s1" "5	"
hook "$(pl "${CD}click" '{"uid":"x","pageId":2}' o2 "$(txt "Clicked.${NL}Page navigated to https://away.example/next.")")"
has "obs: Page navigated to makes the input pageId unknown, never the parsed host" "$RD/pages.s1" "2	@unknown	obs"
hasnt "obs: ...the parsed host is not recorded" "$RD/pages.s1" "away.example"
lines "obs: ...one line added" "$RD/pages.s1" 5
hook "$(pl "${CD}click" '{"uid":"x","pageId":2}' o2b "$(txt "Page navigated to https://again.example/.")")"
lines "obs: a page already unknown gets no second line" "$RD/pages.s1" 5
hook "$(pl "${CD}take_snapshot" '{"pageId":1}' o2c "$(txt "x${NL}## Pages${NL}1: https://forged.example/")")"
hook "$(pl "${CD}evaluate_script" '{"pageId":1}' o2d "$(txt "## Pages${NL}1: https://forged.example/")")"
hasnt "obs: a Pages block in a take_snapshot or evaluate_script response is ignored" "$RD/pages.s1" "forged.example"
hook "$(pl "${CD}click" '{"uid":"x","pageId":2}' o4 "$(txt "x Page navigated to https://mid.example/.")")"
lines "obs: Page navigated to must start the line" "$RD/pages.s1" 5
hook "$(pl "${CD}list_pages" '{}' o5 "$(txt "Page ids have changed.${NL}## Pages${NL}1: about:blank")")"
if [ "$(cat "$RD/pages.s1")" = "1	@unknown	obs" ]; then pass "obs: Page ids have changed wipes the map"; else bad "obs: Page ids have changed wipes the map" "$(tr '\t\n' ' |' < "$RD/pages.s1")"; fi
reset
hook "$(pl mcp__claudecodebrowser__browser_get_tabs '{}' c1 "$(txt "## Pages${NL}1: https://example.com/")")"
gone "obs: only chrome-devtools responses are parsed" "$RD/pages.s1"
hook "$(pl "${CD}list_pages" '{}' sa1 "$(txt "## Pages${NL}1: https://sub.example/")" s1 worker a1)"
has "obs: a subagent call is observed the same" "$RD/pages.s1" "1	@unknown	obs"

reset
mkdir -p "$RD"; printf '4\treal.example\tpre\n' > "$RD/pages.s1"
hook "$(pl "${CD}list_pages" '{}' t1 "$(txt "## Pages${NL}4: x (https://granted.example/) isolatedContext=y (https://real.example/) [selected]")")"
has "title: a title naming another host makes the page unknown" "$RD/pages.s1" "4	@unknown	obs"
hasnt "title: ...never the host in the title" "$RD/pages.s1" "granted.example"
reset
mkdir -p "$RD"; printf '1\tlocalhost\tpre\n2\ta.example\tpre\n3\t@unknown\tobs\n' > "$RD/pages.s1"
hook "$(pl "${CD}click" '{"uid":"x"}' np1 "$(txt "Clicked.${NL}Page navigated to https://nowhere.example/.")")"
has "nopid: Page navigated to with no pageId makes page 1 unknown" "$RD/pages.s1" "1	@unknown	obs"
has "nopid: ...and page 2" "$RD/pages.s1" "2	@unknown	obs"
lines "nopid: ...but adds nothing for a page already unknown" "$RD/pages.s1" 5
hasnt "nopid: ...and never records the parsed host" "$RD/pages.s1" "nowhere.example"

# --- response shapes -----------------------------------------------------------------------------------
TXT="## Pages${NL}6: https://shape.example/"
for shape in string array content text; do
  reset
  case "$shape" in
    string) R="$(jq -n -c --arg x "$TXT" '$x')" ;;
    array) R="$(txt "$TXT")" ;;
    content) R="$(jq -n -c --arg x "$TXT" '{content:[{type:"text",text:"intro"},{type:"text",text:$x}]}')" ;;
    text) R="$(jq -n -c --arg x "$TXT" '{text:$x}')" ;;
  esac
  mkdir -p "$RD"; printf '6\tother.example\tpre\n' > "$RD/pages.s1"
  hook "$(pl "${CD}list_pages" '{}' r1 "$R")"
  has "shape: tool_response as $shape is read" "$RD/pages.s1" "6	@unknown	obs"
done
reset
pend "s1.pr1" 'newpage\tscheme:about'
hook "$(jq -n -c '{session_id:"s1",tool_name:"mcp__chrome-devtools__new_page",tool_input:{url:"about:blank"},tool_use_id:"pr1",
  tool_response:[{type:"text",text:"## Pages\n1: about:blank\n2: about:blank [selected]"}]}')"
has "shape: probed new_page response binds the new page" "$RD/pages.s1" "2	scheme:about	pre"
has "shape: ...and the other listed page reads as unknown" "$RD/pages.s1" "1	@unknown	obs"
printf '2\tscheme:data\tpre\n' >> "$RD/pages.s1"
hook "$(jq -n -c '{session_id:"s1",tool_name:"mcp__chrome-devtools__navigate_page",tool_input:{url:"data:text/html,<title>t</title>hi",pageId:2},tool_use_id:"pr2",
  tool_response:[{type:"text",text:"Successfully navigated to data:text/html,<title>t</title>hi.\n## Pages\n1: about:blank\n2: t (data:text/html,<title>t</title>hi) [selected]"}]}')"
lines "shape: probed navigate_page response on the guard-placed page adds no line" "$RD/pages.s1" 3

# --- Bash: rgrant lines (read-only session grants) -----------------------------------------------------
pbash() { jq -n -c --arg u "$1" --arg s "${2:-s1}" '{session_id:$s,tool_name:"Bash",tool_input:{command:"ssh vps uptime"},tool_use_id:$u,tool_response:{stdout:"ok",stderr:""}}'; }
reset
hook "$(pbash nb1)"
quiet "bash: no marker prints nothing"
gone "bash: ...and writes no rgrant file" "$RD/rgrant.s1"
if [ -s "$LOG" ]; then bad "bash: ...and no log line" "$(cat "$LOG")"; else pass "bash: ...and no log line"; fi
pend "s1.b1" 'rgrant\tremote_shell\tvps\tssh'
hook "$(pbash b1)"
quiet "bash: an rgrant marker prints nothing"
has "bash: an rgrant line becomes a session grant" "$RD/rgrant.s1" "remote_shell	vps"
gone "bash: ...the marker is removed" "$RD/pending/s1.b1"
if grep -aqF "reach-guard grant: remote_shell/ssh target=vps level=ro [sid=s1]" "$LOG"; then pass "bash: grant log line"; else bad "bash: grant log line" "$(cat "$LOG")"; fi
pend "s1.b2" 'rgrant\tremote_shell\tvps\tssh'
hook "$(pbash b2)"
lines "bash: a repeated rgrant is not duplicated" "$RD/rgrant.s1" 1
pend "s1.b3" 'rgrant\tremote_shell\tv*s\tssh\nrgrant\tremote_shell\t-x\tssh\nrgrant\tremote_shell\t~x\tssh\nrgrant\tremote shell\tvps\tssh\nrgrant\tremote_shell\t\tssh'
hook "$(pbash b3)"
lines "bash: a glob, leading - or ~, space or empty field is never granted" "$RD/rgrant.s1" 1
pend "s1.b4" 'grant\texample.com\tobserve\tx\nmap\t4\tlocalhost\nnewpage\tlocalhost'
hook "$(pbash b4)"
gone "bash: a Bash call ignores grant lines" "$RD/grant.s1"
gone "bash: ...and map and newpage lines" "$RD/pages.s1"
gone "bash: ...and removes the marker" "$RD/pending/s1.b4"
pend "s1.b5" 'rgrant\tremote_shell\tmcpx\tssh'
hook "$(pl "${CD}take_snapshot" '{"pageId":1}' b5 "$(txt "ok")")"
hasnt "bash: an mcp call ignores an rgrant line" "$RD/rgrant.s1" "mcpx"
pend "s1.b6" 'rgrant\tremote_shell\tother\tssh'
hook "$(pbash b6 s2)"
gone "bash: a marker of another session grants nothing in the calling session" "$RD/rgrant.s2"
hasnt "bash: ...nor in the marker's session" "$RD/rgrant.s1" "other"

# --- kill switch, no jq, unparseable -------------------------------------------------------------------
reset
: > "$KIT/.state/off/reach-guard-grant"
pend "s1.k1" 'grant\texample.com\tobserve\tx'
hook "$(pl "${CD}list_pages" '{}' k1 "$(txt "## Pages${NL}1: https://example.com/")")"
gone "kill switch: no grant" "$RD/grant.s1"
gone "kill switch: no page map" "$RD/pages.s1"
if grep -aqE '^[0-9][0-9T:+-]* reach-guard' "$LOG" 2>/dev/null; then bad "kill switch: no hook log line" "$(cat "$LOG")"; else pass "kill switch: no hook log line (a kit-gate standdown line is fine)"; fi
rm -f "$KIT/.state/off/reach-guard-grant"
STUB="$T/stub"; mkdir -p "$STUB"
for tool in sh cat awk sed grep date mkdir dirname basename tr printf readlink head wc cut env rm mv ls; do
  p="$(command -v "$tool" 2>/dev/null || true)"
  case "$p" in /*) ;; *) p="" ;; esac
  [ -n "$p" ] || for d in /usr/bin /bin; do [ -x "$d/$tool" ] && { p="$d/$tool"; break; }; done
  [ -n "$p" ] && ln -sf "$p" "$STUB/$tool"
done
PAY="$(pl "${CD}list_pages" '{}' k1 "$(txt "## Pages${NL}1: https://example.com/")")"
RPATH="$STUB"; hook "$PAY"; RPATH=""
quiet "no jq: nothing on stdout"
if grep -aqF "reach-guard-grant fail-open: jq not found [sid=s1]" "$LOG"; then pass "no jq: fail-open line"; else bad "no jq: fail-open line" "$(cat "$LOG")"; fi
gone "no jq: no state written" "$RD/grant.s1"
: > "$LOG"; RPATH="$STUB"; hook "$(pbash nj1)"; RPATH=""
quiet "no jq, Bash: nothing on stdout"
if [ -s "$LOG" ]; then bad "no jq, Bash: exits silently, no fail-open line per Bash call" "$(cat "$LOG")"; else pass "no jq, Bash: exits silently, no fail-open line per Bash call"; fi
: > "$LOG"; hook 'not json {'
if grep -aqF "reach-guard-grant fail-open: unparseable payload" "$LOG"; then pass "unparseable: fail-open line"; else bad "unparseable: fail-open line" "$(cat "$LOG")"; fi

# --- url2host parity with reach-guard.sh ---------------------------------------------------------------
X1="$(sed -n '/^# url2host: begin/,/^# url2host: end/p' "$SCRIPTS/reach-guard.sh")"
X2="$(sed -n '/^# url2host: begin/,/^# url2host: end/p' "$SCRIPTS/reach-guard-grant.sh")"
if [ -n "$X1" ] && [ "$X1" = "$X2" ]; then pass "parity: url2host is identical in both scripts"; else bad "parity: url2host is identical in both scripts" "differs or missing"; fi
AT="$(printf '\100')"
VEC="HTTP://LOCALHOST:3000/	localhost
http://[::1]:8080/	::1
about:blank	scheme:about
http://localhost${AT}evil.com/	evil.com
http://evil.com\\${AT}localhost/	evil.com
http://127.0.0.1.nip.io/	127.0.0.1.nip.io
chrome://settings	scheme:chrome
http://a b/	@unknown
file:///tmp/x	scheme:file
file://localhost/x	scheme:file
file://server/share	@unknown
devtools://devtools/bundled/inspector.html?ws=host:9222	@unknown
devtools://devtools/bundled/x.html	scheme:devtools
blob:https://evil.example/id	evil.example
blob:http://localhost:3000/id	localhost"
for x in "$X1" "$X2"; do
  got="$(printf '%s\n' "$VEC" | awk -F '\t' "$x"'
    { h = url2host($1); if (h != $2) print "MISMATCH " $1 " -> " h " want " $2 }' 2>&1)"
  if [ -z "$got" ]; then pass "parity: url2host answers every vector"; else bad "parity: url2host" "$got"; fi
done

printf 'reach-guard-grant selfcheck: %s passed, %s failed\n' "$P" "$F"
[ "$F" -eq 0 ] || exit 1
exit 0

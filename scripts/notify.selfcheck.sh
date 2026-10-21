#!/usr/bin/env sh
# kit-scope: shared
# Self-check for notify.sh: kill switch, mode selection (explicit osc/notify-send/both and the
# PATH-dependent default), content composition (title/body carry cwd basename + notification_type),
# full control-byte sanitization (incl. TAB/LF/CR, and a planted ESC/BEL forgery attempt) with a
# byte-cap that repairs a UTF-8 sequence truncated at the boundary (correct under LC_ALL=C, not just
# a UTF-8 locale - see cap()'s own header), `;` replaced before it reaches the OSC 777 field
# separator, the alacritty-ancestor PPID walk, window-id validation (digits-only, and skipped when
# ambiguous - more than one window for the same pid), the setsid > nohup > plain-background
# detachment fallback, and that the hook itself always returns fast even though the notify-send/
# click-focus path is fully backgrounded.
#
# notify-send, xdotool and i3-msg are ALL STUBBED on PATH - this must never fire a real desktop
# notification and never call the real i3-msg/xdotool. PATH is built from a MINIMAL, explicitly
# whitelisted tool set (not a full /usr/bin mirror - that forked `basename` once per file in every
# bin dir, on the order of 10^4 forks per run), so a binary this selfcheck does not list is simply
# absent, which is also how the "tool missing" cases are built (no exclusion step needed).
#
# Portability (macOS / any host without /proc or GNU `date +%s%N`): cases that need the alacritty
# PPID walk or nanosecond timing are gated on HAVE_PROC / HAVE_NS and print a `note: skipped ...`
# line (never one starting `SKIP` - the CI matrix in .github/workflows/selfcheck.yml treats any
# `^SKIP` line as a hard FAIL, which is correct for "a tool that should exist here is missing" but
# wrong for "this platform structurally has no /proc" - macOS is a real, supported CI leg, not a
# gap) when the capability is absent; every other case still runs regardless.
#
# dash portability: this file is also run under `dash` (2 of 3 Linux CI legs use `sh` = dash) - no
# `\x` printf escapes (dash's printf builtin has none; UTF-8 test bytes use octal `\303\251`), no
# bash-only constructs ($'...', arrays, [[, process substitution).
set -u

# The AMBIENT terminal this selfcheck happens to run in must never leak into a case that expects a
# specific (or no) terminal: detect_osc_kind() reads exactly these vars, so an unpinned run on
# kitty/iTerm2/WezTerm/Windows Terminal/Ghostty would compose a DIFFERENT OSC form than every case
# below assumes (OSC 777) and fail in a way that has nothing to do with a real regression. Unset/
# reset ONCE, for this script's own environment, so every later `sh "$H"` call (via run() or
# direct) inherits the clean baseline with no per-call prefix needed. A case that wants a SPECIFIC
# terminal sets that one var back with a per-command prefix (e.g. `TERM=xterm-kitty sh "$H"`),
# which overrides only that one invocation.
unset TERM_PROGRAM WT_SESSION GHOSTTY_RESOURCES_DIR KITTY_WINDOW_ID 2>/dev/null || true
TERM=dumb; export TERM
# Same ambient-leak concern as the terminal vars above: this selfcheck's own caller may itself be
# running inside a Claude Code hook context where CLAUDE_PROJECT_DIR is exported. Cases 3/4 test the
# cwd FALLBACK, which only means something if it is genuinely absent here.
unset CLAUDE_PROJECT_DIR 2>/dev/null || true
# Same concern again: a real operator profile may export AGENT_TIERS_NOTIFY_TERMINAL/
# AGENT_TIERS_NOTIFY_FOCUS_CMD. Cases 7-10 test the UNSET-env defaults (today's exact behaviour),
# which only means something if these are genuinely unset here; cases that want a specific value
# set it back with a per-command prefix, same pattern as TERM above.
unset AGENT_TIERS_NOTIFY_TERMINAL AGENT_TIERS_NOTIFY_FOCUS_CMD 2>/dev/null || true

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP notify: jq absent (hook fails open by design)"; exit 0; }

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
fail() { printf 'FAIL: %s\n' "$1"; rm -rf "$T"; exit 1; }
CLEANUP_PIDS=""
cleanup() {
  for p in $CLEANUP_PIDS; do kill "$p" 2>/dev/null || true; done
  rm -rf "$T"
}
trap cleanup EXIT

# Run from a SANDBOX kit copy (hook, wrapper, assets, lib, plus a kit-gate.sh pointed at an empty managed
# dir and the real options.tsv) with every kit-gate input cleared, so the live kit's state and the user's
# real options can never stand the hook down or be touched. The notifier itself stays stubbed on PATH below.
mkdir -p "$T/kit/scripts" "$T/kit/install" "$T/managed"
cp "$SRC_DIR/notify.sh" "$SRC_DIR/notify-stop.sh" "$SRC_DIR/guard-cmdpos.sh" "$T/kit/scripts/" || fail "cannot copy hooks into sandbox"
cp -R "$SRC_DIR/assets" "$SRC_DIR/lib" "$T/kit/scripts/" || fail "cannot copy assets/lib into sandbox"
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$SRC_DIR/kit-gate.sh" > "$T/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$T/kit/scripts/kit-gate.sh" || fail "_kg_managed not rewritten"
cp "$SRC_DIR/../install/options.tsv" "$T/kit/install/"
H="$T/kit/scripts/notify.sh"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done

export CLAUDE_CONFIG_DIR="$T/cfg"
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state"
MODE_FILE="$CLAUDE_CONFIG_DIR/agent-tiers/.state/notify-mode"
export AGENT_TIERS_GUARDS_LOG="$T/guards.log"   # never the real/live guards.log

# Capability probes - gate the Linux/GNU-only fixtures below, never the whole file.
HAVE_PROC=0; [ -r /proc/self/comm ] && HAVE_PROC=1
HAVE_NS=0
case "$(date +%s%N 2>/dev/null)" in ''|*[!0-9]*) HAVE_NS=0 ;; *) HAVE_NS=1 ;; esac
ns_now() { [ "$HAVE_NS" = 1 ] && date +%s%N || printf ''; }
# $1=start_ns $2=end_ns $3=label - SKIPs (not FAILs) the timing half on a host with no %N, still
# lets the caller's own functional assertions (which ran regardless) stand on their own.
assert_fast() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    # Not "SKIP...": the CI matrix (.github/workflows/selfcheck.yml) treats any line starting with
    # that word as a hard FAIL, which is right for a missing-tool gap but wrong for "this platform's
    # date(1) has no %N" (BSD/macOS) - a structural difference, not something to fix here.
    echo "note: skipped timing check ($3): date +%s%N unavailable on this host"
    return 0
  fi
  [ "$(($2 - $1))" -lt 1000000000 ] || fail "hook must return in under 1s ($3)"
}

NOTIFY_SEND_CALLS="$T/notify-send-calls"; export NOTIFY_SEND_CALLS
I3MSG_CALLS="$T/i3msg-calls"; export I3MSG_CALLS
XDOTOOL_STUB_ID="94371840"
XDOTOOL_STUB_OUTPUT="$XDOTOOL_STUB_ID"; export XDOTOOL_STUB_OUTPUT   # override for the multi-window case

STUBDIR="$T/stubbin"
mkdir -p "$STUBDIR"
# notify-send stub: records every arg (one per line, "=====" record separator), sleeps 1s (a
# delayed click), then prints "default" on stdout - only the caller's action-detecting branch
# (HASACT=1) ever reads that stdout, but the stub itself has no way to know which branch called it.
cat > "$STUBDIR/notify-send" <<'EOF'
#!/usr/bin/env sh
{ for a in "$@"; do printf '%s\n' "$a"; done; printf '=====\n'; } >> "$NOTIFY_SEND_CALLS"
sleep 1
echo default
EOF
chmod +x "$STUBDIR/notify-send"

# xdotool stub: ignores its args, prints whatever $XDOTOOL_STUB_OUTPUT currently holds (one id, or
# several lines for the multi-window/ambiguous case).
cat > "$STUBDIR/xdotool" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$XDOTOOL_STUB_OUTPUT"
EOF
chmod +x "$STUBDIR/xdotool"

# i3-msg stub: records its args, never focuses anything real.
cat > "$STUBDIR/i3-msg" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$I3MSG_CALLS"
EOF
chmod +x "$STUBDIR/i3-msg"

# custom-focus stub: a stand-in for an AGENT_TIERS_NOTIFY_FOCUS_CMD other than i3-msg, records its
# args the same way, so a custom template's own tool (not a hardcoded i3-msg) can be proven called.
CUSTOM_FOCUS_CALLS="$T/custom-focus-calls"; export CUSTOM_FOCUS_CALLS
cat > "$STUBDIR/custom-focus" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$CUSTOM_FOCUS_CALLS"
EOF
chmod +x "$STUBDIR/custom-focus"

# setsid/nohup stubs: record that they ran, then exec straight through - the underlying notify-send
# stub still fires normally, so a case can assert BOTH "which detachment path was chosen" AND "the
# notification still went out" from the same invocation.
SETSID_MARKER="$T/setsid-called"; export SETSID_MARKER
SETSID_STUB_DIR="$T/setsid-stub"; mkdir -p "$SETSID_STUB_DIR"
cat > "$SETSID_STUB_DIR/setsid" <<'EOF'
#!/usr/bin/env sh
: > "$SETSID_MARKER"
exec "$@"
EOF
chmod +x "$SETSID_STUB_DIR/setsid"

NOHUP_MARKER="$T/nohup-called"; export NOHUP_MARKER
NOHUP_STUB_DIR="$T/nohup-stub"; mkdir -p "$NOHUP_STUB_DIR"
cat > "$NOHUP_STUB_DIR/nohup" <<'EOF'
#!/usr/bin/env sh
: > "$NOHUP_MARKER"
exec "$@"
EOF
chmod +x "$NOHUP_STUB_DIR/nohup"

# The ONLY interpreter/utility binaries notify.sh itself calls, resolved once from the real
# environment - not a mirror of every file in /usr/bin and /bin. Extend this list if notify.sh
# gains a new external dependency; anything not listed here is simply absent on every PATH built
# from it, which is how every "tool missing" case below is constructed (no exclusion step needed).
BASE_TOOLS="$T/base-tools"; mkdir -p "$BASE_TOOLS"
for tool in sh jq tr cat printf dirname basename mkdir date cut awk head tail wc grep timeout sleep iconv od sed cksum; do
  p="$(command -v "$tool" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$BASE_TOOLS/$tool" 2>/dev/null
done

FULL_PATH="$STUBDIR:$SETSID_STUB_DIR:$BASE_TOOLS"         # notify-send+xdotool+i3-msg+setsid
NOXDOTOOL_PATH="$T/notools"; mkdir -p "$NOXDOTOOL_PATH"
ln -sf "$STUBDIR/notify-send" "$NOXDOTOOL_PATH/notify-send"
ln -sf "$STUBDIR/i3-msg" "$NOXDOTOOL_PATH/i3-msg"
NOXDOTOOL_PATH="$NOXDOTOOL_PATH:$SETSID_STUB_DIR:$BASE_TOOLS"   # notify-send+i3-msg+setsid, NO xdotool
NOTOOLS_PATH="$T/notify-only"; mkdir -p "$NOTOOLS_PATH"
ln -sf "$STUBDIR/notify-send" "$NOTOOLS_PATH/notify-send"
NOTOOLS_PATH="$NOTOOLS_PATH:$BASE_TOOLS"                        # notify-send only, no xdotool/i3-msg/setsid

# A fake "alacritty" ancestor for the PPID-walk (Linux/proc only): any binary copied to a path
# literally named `alacritty` and exec'd directly gets that comm (Linux sets comm from the exec
# path's basename, independent of what the binary actually is) - so a renamed shell works without a
# real terminal. Only built when HAVE_PROC, since alacritty_pid_from() itself is a /proc walk.
CHILD_PID=""
if [ "$HAVE_PROC" = 1 ]; then
  mkdir -p "$T/bin"
  cp "$(command -v sh)" "$T/bin/alacritty" || fail "cannot build fake alacritty ancestor"
  chmod +x "$T/bin/alacritty"
  "$T/bin/alacritty" -c 'sleep 120 & echo $! > "$1"; wait' _ "$T/child.pid" &
  ALAC_PID=$!
  CLEANUP_PIDS="$CLEANUP_PIDS $ALAC_PID"
  for _try in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$T/child.pid" ] && { CHILD_PID="$(cat "$T/child.pid")"; break; }
    sleep 0.2
  done
  [ -n "$CHILD_PID" ] || fail "fake alacritty fixture never produced a child pid"
  CLEANUP_PIDS="$CLEANUP_PIDS $CHILD_PID"

  # A second fake ancestor under a NON-default comm, for the AGENT_TIERS_NOTIFY_TERMINAL cases below
  # (case 10d) - same construction as the alacritty fixture above, different name.
  CHILD_PID2=""
  mkdir -p "$T/bin2"
  cp "$(command -v sh)" "$T/bin2/customterm" || fail "cannot build fake customterm ancestor"
  chmod +x "$T/bin2/customterm"
  "$T/bin2/customterm" -c 'sleep 120 & echo $! > "$1"; wait' _ "$T/child2.pid" &
  ALAC_PID2=$!
  CLEANUP_PIDS="$CLEANUP_PIDS $ALAC_PID2"
  for _try in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$T/child2.pid" ] && { CHILD_PID2="$(cat "$T/child2.pid")"; break; }
    sleep 0.2
  done
  [ -n "$CHILD_PID2" ] || fail "fake customterm fixture never produced a child pid"
  CLEANUP_PIDS="$CLEANUP_PIDS $CHILD_PID2"
fi

run() { # $1=message $2=type $3=cwd(''=omit)
  payload="$(jq -cn --arg m "$1" --arg t "$2" --arg c "$3" \
    'if $c == "" then {message:$m, notification_type:$t} else {message:$m, notification_type:$t, cwd:$c} end')"
  printf '%s' "$payload" | PATH="$FULL_PATH" sh "$H" 2>"$T/stderr"
}

# 1. Kill switch: no output, no notify-send call, exit 0.
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off"
touch "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/notify"
rm -f "$NOTIFY_SEND_CALLS"
out="$(run "hello" permission_prompt "")"; rc=$?
[ "$rc" = 0 ] || fail "kill switch must still exit 0"
[ -z "$out" ] || fail "kill switch must produce no output"
sleep 0.2
[ ! -f "$NOTIFY_SEND_CALLS" ] || fail "kill switch must not call notify-send"
rm -f "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/notify"

# 2. Explicit osc mode: terminalSequence in output, notify-send never called, exactly one ESC + one
#    BEL byte in the sequence (both are notify.sh's own delimiters, not attacker-controlled).
printf 'osc' > "$MODE_FILE"
rm -f "$NOTIFY_SEND_CALLS"
out="$(run "plain message" idle_prompt "")"
printf '%s' "$out" | jq -e '.terminalSequence' >/dev/null 2>&1 || fail "osc mode must emit terminalSequence"
sleep 0.2
[ ! -f "$NOTIFY_SEND_CALLS" ] || fail "osc mode must not call notify-send"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
before="$(printf '%s' "$seq" | wc -c)"
after="$(printf '%s' "$seq" | tr -d '\033\007' | wc -c)"
[ "$((before - after))" = 2 ] || fail "osc sequence should carry exactly one ESC and one BEL (notify.sh's own delimiters)"

# 3. Content: with no cwd, title stays plain "Claude Code"; body carries the type prefix.
case "$seq" in *"Claude Code;idle_prompt: plain message"*) ;; *) fail "osc content should be 'Claude Code' title / '<type>: <message>' body without a cwd (got: $seq)" ;; esac

# 4. Content: with a cwd, title carries its sanitised basename.
out="$(run "plain message" idle_prompt "/home/user/projects/example-repo")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
case "$seq" in *"Claude Code: example-repo;idle_prompt: plain message"*) ;; *) fail "osc title should carry the cwd basename (got: $seq)" ;; esac

# 4b. Sanitisation strips TAB/LF/CR too (not just ESC/BEL), and the cap is over the WHOLE composed
#     string, not per line: a message with embedded newlines/tabs must come out single-line.
DIRTY_WS="$(printf 'line1\tA\nline2\rB')"
out="$(run "$DIRTY_WS" idle_prompt "")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
stripped="$(printf '%s' "$seq" | tr -d '\011\012\015')"
[ "$stripped" = "$seq" ] || fail "TAB/LF/CR in the message must be stripped before it reaches the OSC sequence (got: $seq)"
line_count="$(printf '%s' "$seq" | wc -l)"
[ "$line_count" -eq 0 ] || fail "the composed OSC sequence must be a single line (got $line_count newlines)"

# 4c. cap() never leaves an invalid/truncated UTF-8 sequence at the boundary. Octal escapes only -
#     dash's printf builtin has no \x. U+00E9 (e) is 2 bytes (0303 0251). MESSAGE is capped to 200
#     BYTES (notify.sh): a leading single ASCII byte shifts every following 2-byte char off an even
#     boundary, so cutting at byte 200 lands exactly mid-character on the last one - the case that
#     actually exercises cap()'s tail repair, not just a string nowhere near the cap.
UTF8_CHAR="$(printf '\303\251')"   # e-acute, 2 bytes
UTF8_MSG="x"; i=0
while [ "$i" -lt 101 ]; do UTF8_MSG="$UTF8_MSG$UTF8_CHAR"; i=$((i + 1)); done   # 1 + 101*2 = 203 bytes
[ "$(printf '%s' "$UTF8_MSG" | wc -c)" -eq 203 ] || fail "fixture invalid: UTF8_MSG should be 203 bytes"
out="$(run "$UTF8_MSG" idle_prompt "")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
# The message is inside the OSC body, after "notify;Claude Code;idle_prompt: " - extract just that
# tail to hand to iconv without the surrounding ASCII/escape bytes.
msg_out="$(printf '%s' "$seq" | sed 's/^.*idle_prompt: //' | tr -d '\007')"
msg_bytes="$(printf '%s' "$msg_out" | wc -c)"
printf '%s' "$msg_out" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 \
  || fail "a message straddling the byte cap must still be valid UTF-8 after capping (got $msg_bytes bytes: $(printf '%s' "$msg_out" | od -An -tx1 | tail -c 40))"
[ "$msg_bytes" -le 200 ] || fail "capped message must not exceed the 200-byte cap (got $msg_bytes)"
[ "$msg_bytes" -ge 198 ] || fail "capped message should be within 1-2 bytes of the 200-byte cap, not truncated further than necessary (got $msg_bytes)"

# 4c-i. Same fixture, forced LC_ALL=C: an earlier cap() (awk substr) counted bytes under C and
#       split the character anyway, so this locale is exactly what must be proven, not skipped.
payload4c="$(jq -cn --arg m "$UTF8_MSG" --arg t idle_prompt '{message:$m, notification_type:$t}')"
out_c="$(printf '%s' "$payload4c" | LC_ALL=C PATH="$FULL_PATH" sh "$H" 2>"$T/stderr")"
seq_c="$(printf '%s' "$out_c" | jq -r '.terminalSequence')"
msg_out_c="$(printf '%s' "$seq_c" | sed 's/^.*idle_prompt: //' | tr -d '\007')"
printf '%s' "$msg_out_c" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 \
  || fail "under LC_ALL=C, a message straddling the byte cap must still be valid UTF-8 after capping (got: $seq_c)"

# 4c-ii. Same fixture again, this time with iconv UNREACHABLE (od still present) - exercises
#        trim_incomplete_utf8(), the pure-POSIX fallback path, not just the iconv -c path.
NOICONV_PATH="$T/noiconv"; mkdir -p "$NOICONV_PATH"
for tool in sh jq tr cat printf dirname basename mkdir date cut awk head tail wc grep timeout sleep od; do
  p="$(command -v "$tool" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$NOICONV_PATH/$tool" 2>/dev/null
done
[ -e "$NOICONV_PATH/iconv" ] && fail "fixture invalid: NOICONV_PATH must not contain iconv"
out_ni="$(printf '%s' "$payload4c" | PATH="$NOICONV_PATH" sh "$H" 2>"$T/stderr")"
seq_ni="$(printf '%s' "$out_ni" | jq -r '.terminalSequence')"
msg_out_ni="$(printf '%s' "$seq_ni" | sed 's/^.*idle_prompt: //' | tr -d '\007')"
printf '%s' "$msg_out_ni" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 \
  || fail "with no iconv on PATH, the pure-shell tail-repair fallback must still produce valid UTF-8 (got: $seq_ni)"
msg_bytes_ni="$(printf '%s' "$msg_out_ni" | wc -c)"
[ "$msg_bytes_ni" -le 200 ] || fail "no-iconv fallback: capped message must not exceed the 200-byte cap (got $msg_bytes_ni)"

# 4d. ESC/BEL sanitisation - the security-relevant half - is exercised with an actual forgery
#     attempt, not just a clean message: a message containing an ESC/BEL-based OSC payload of its
#     own must still leave EXACTLY one ESC and one BEL in the final sequence (notify.sh's own
#     delimiters). A sanitize() regression that stopped stripping control bytes would pass case 2
#     (which never plants one) but must fail here.
FORGED="$(printf 'hi\033]0;evil-title\007bye')"
out="$(run "$FORGED" idle_prompt "")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
before="$(printf '%s' "$seq" | wc -c)"
after="$(printf '%s' "$seq" | tr -d '\033\007' | wc -c)"
[ "$((before - after))" = 2 ] || fail "a message carrying its own ESC/BEL-based OSC forgery must still leave exactly one ESC and one BEL (notify.sh's own) in the sequence (got: $seq)"
case "$seq" in *"evil-title"*) ;; *) fail "fixture invalid: the forged text should survive with its control bytes stripped, or this proves nothing" ;; esac

# 4e. `;` in the cwd basename or message must not shift the OSC 777 field split
#     (\033]777;notify;<title>;<body>\007 has exactly 3 structural semicolons - anything past that
#     came from unescaped content).
out="$(run "x;y" idle_prompt "/home/user/projects/a;b")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
semi_count="$(printf '%s' "$seq" | tr -cd ';' | wc -c)"
[ "$semi_count" -eq 3 ] || fail "a ';' in the cwd basename or message must be replaced before composing the OSC 777 sequence (got $semi_count semicolons, want 3: $seq)"
case "$seq" in *"a,b"*) ;; *) fail "the cwd basename's ';' should be replaced with ',' (got: $seq)" ;; esac
case "$seq" in *"x,y"*) ;; *) fail "the message's ';' should be replaced with ',' (got: $seq)" ;; esac

# 5. Explicit notify-send mode, no window resolvable: a PLAIN notification, no -A action, returns
#    fast. Uses a PATH with ONLY notify-send stubbed (no xdotool/i3-msg/setsid at all) - the
#    process running this selfcheck could itself have a real alacritty ancestor on a host that runs
#    one, so "no ancestor" is never assumed; only genuinely lacking xdotool/i3-msg on PATH forces
#    the no-window branch, independent of whatever the real ancestry happens to be. Also exercises
#    the "neither setsid nor nohup present" fallback (assertion in case 5b).
printf 'notify-send' > "$MODE_FILE"
rm -f "$NOTIFY_SEND_CALLS" "$I3MSG_CALLS" "$SETSID_MARKER" "$NOHUP_MARKER"
start_ns="$(ns_now)"
payload5="$(jq -cn '{message:"plain message", notification_type:"permission_prompt"}')"
out="$(printf '%s' "$payload5" | PATH="$NOTOOLS_PATH" sh "$H" 2>"$T/stderr")"
end_ns="$(ns_now)"
[ -z "$out" ] || fail "notify-send mode must not also emit terminalSequence JSON"
assert_fast "$start_ns" "$end_ns" "no-window notify-send"
sleep 0.3
[ -f "$NOTIFY_SEND_CALLS" ] || fail "notify-send mode must call notify-send"
grep -q 'permission_prompt: plain message' "$NOTIFY_SEND_CALLS" || fail "notify-send should receive the composed body"
grep -qx -- '-A' "$NOTIFY_SEND_CALLS" && fail "with no xdotool/i3-msg on PATH this must be a plain notification with no -A"
[ ! -f "$I3MSG_CALLS" ] || fail "i3-msg must never be called when there is no action to click"

# 5b. Neither setsid nor nohup on PATH: the notification must STILL be delivered (plain background),
#     and neither detachment stub fires.
[ ! -f "$SETSID_MARKER" ] || fail "setsid must not be reachable on the PATH used for case 5"
[ ! -f "$NOHUP_MARKER" ] || fail "nohup must not be reachable on the PATH used for case 5"

# 6. setsid MISSING but nohup present: the fallback must use nohup (marker set), and the
#    notification must still be delivered with the same content as the setsid path.
rm -f "$NOTIFY_SEND_CALLS" "$SETSID_MARKER" "$NOHUP_MARKER"
NOHUP_ONLY_PATH="$T/nohup-only"; mkdir -p "$NOHUP_ONLY_PATH"
ln -sf "$STUBDIR/notify-send" "$NOHUP_ONLY_PATH/notify-send"
NOHUP_ONLY_PATH="$NOHUP_ONLY_PATH:$NOHUP_STUB_DIR:$BASE_TOOLS"
out="$(printf '%s' "$payload5" | PATH="$NOHUP_ONLY_PATH" sh "$H" 2>"$T/stderr")"
sleep 0.3
[ -f "$NOHUP_MARKER" ] || fail "with setsid absent and nohup present, the fallback must use nohup"
[ ! -f "$SETSID_MARKER" ] || fail "setsid stub must not be reachable on the PATH used for case 6"
[ -f "$NOTIFY_SEND_CALLS" ] || fail "the nohup fallback must still deliver the notification"

if [ "$HAVE_PROC" != 1 ]; then
  # Range is 7-11 ONLY: case 12 (never-blocks) sits OUTSIDE this if-block and always runs regardless.
  # Not "SKIP...": see assert_fast's own comment on why that word is reserved for a real CI gap.
  echo "note: skipped cases 7-11 (alacritty-ancestor click-to-focus tests): /proc unavailable on this host"
else
  payload="$(jq -cn '{message:"plain message", notification_type:"idle_prompt"}')"

  # 7. Full path: xdotool + i3-msg present, alacritty ancestor injected via
  #    NOTIFY_SELFCHECK_START_PID -> notify-send gets -A default=Focus, and (after the stub's 1s
  #    "click" delay) i3-msg is called with the digits-only window id from the xdotool stub. setsid
  #    (stubbed) is the detachment path used here.
  rm -f "$NOTIFY_SEND_CALLS" "$I3MSG_CALLS" "$SETSID_MARKER"
  start_ns="$(ns_now)"
  out="$(printf '%s' "$payload" | PATH="$FULL_PATH" NOTIFY_SELFCHECK_START_PID="$CHILD_PID" sh "$H" 2>"$T/stderr")"
  end_ns="$(ns_now)"
  [ -z "$out" ] || fail "notify-send mode must not emit terminalSequence JSON"
  assert_fast "$start_ns" "$end_ns" "full action path"
  sleep 0.3
  [ -f "$NOTIFY_SEND_CALLS" ] || fail "full-action-path invocation must call notify-send"
  grep -qx -- '-A' "$NOTIFY_SEND_CALLS" || fail "with an alacritty ancestor + xdotool + i3-msg, notify-send must be called with an action"
  grep -qx 'default=Focus' "$NOTIFY_SEND_CALLS" || fail "the action must be default=Focus"
  [ -f "$SETSID_MARKER" ] || fail "the normal detachment path must use setsid when it is present"
  [ ! -f "$I3MSG_CALLS" ] || fail "i3-msg must not be called yet - the stub has not printed 'default' after only 0.3s"
  # Now wait past the stub's 1s sleep and confirm the click was acted on.
  found=0
  for _try in 1 2 3 4 5 6 7 8 9 10; do
    if [ -f "$I3MSG_CALLS" ]; then found=1; break; fi
    sleep 0.3
  done
  [ "$found" = 1 ] || fail "i3-msg was never called after the simulated click"
  grep -q "id=$XDOTOOL_STUB_ID" "$I3MSG_CALLS" || fail "i3-msg must be called with the digits-only window id from xdotool"

  # 8. MORE THAN ONE window for the same pid (alacritty's multi-window IPC): ambiguous, must be
  #    treated the same as no window - plain notification, no -A, i3-msg never called.
  XDOTOOL_STUB_OUTPUT="$(printf '%s\n%s' "$XDOTOOL_STUB_ID" "12345678")"
  rm -f "$NOTIFY_SEND_CALLS" "$I3MSG_CALLS"
  printf '%s' "$payload" | PATH="$FULL_PATH" NOTIFY_SELFCHECK_START_PID="$CHILD_PID" sh "$H" >/dev/null 2>"$T/stderr"
  sleep 0.3
  [ -f "$NOTIFY_SEND_CALLS" ] || fail "an ambiguous (multi-window) match should still deliver a plain notify-send"
  grep -qx -- '-A' "$NOTIFY_SEND_CALLS" && fail "more than one window for the same pid must not produce an action-carrying notification"
  sleep 1.5
  [ ! -f "$I3MSG_CALLS" ] || fail "an ambiguous window match must never reach i3-msg"
  XDOTOOL_STUB_OUTPUT="$XDOTOOL_STUB_ID"   # restore for later cases

  # 9. A NON-digit id from the xdotool stub must never reach i3-msg: resolve_window must reject it,
  #    which drops this to the plain-notification branch (no -A at all, so there is no click to act on).
  XDOTOOL_STUB_OUTPUT="not-a-window-id"
  rm -f "$NOTIFY_SEND_CALLS" "$I3MSG_CALLS"
  printf '%s' "$payload" | PATH="$FULL_PATH" NOTIFY_SELFCHECK_START_PID="$CHILD_PID" sh "$H" >/dev/null 2>"$T/stderr"
  sleep 0.3
  [ -f "$NOTIFY_SEND_CALLS" ] || fail "notify-send should still be called (plain, this time)"
  grep -qx -- '-A' "$NOTIFY_SEND_CALLS" && fail "a non-digit xdotool id must not produce an action-carrying notification"
  sleep 1.5   # past the stub's 1s sleep + click print, in case something wrongly wired it up anyway
  [ ! -f "$I3MSG_CALLS" ] || fail "a non-digit xdotool id must never reach i3-msg, even after the click delay"
  XDOTOOL_STUB_OUTPUT="$XDOTOOL_STUB_ID"   # restore

  # 10. Missing xdotool entirely (even with an alacritty ancestor and i3-msg present): plain
  #     notification, no -A, i3-msg never called.
  rm -f "$NOTIFY_SEND_CALLS" "$I3MSG_CALLS"
  printf '%s' "$payload" | PATH="$NOXDOTOOL_PATH" NOTIFY_SELFCHECK_START_PID="$CHILD_PID" sh "$H" >/dev/null 2>"$T/stderr"
  sleep 0.3
  [ -f "$NOTIFY_SEND_CALLS" ] || fail "missing xdotool should still deliver a plain notify-send"
  grep -qx -- '-A' "$NOTIFY_SEND_CALLS" && fail "missing xdotool must never produce an action-carrying notification"
  sleep 1.5
  [ ! -f "$I3MSG_CALLS" ] || fail "missing xdotool must never call i3-msg"

  # 10b. A custom AGENT_TIERS_NOTIFY_FOCUS_CMD (%s for the window id) is run with the id as its own
  #      argument - the required-tool check looks at its first word (custom-focus), never a
  #      hardcoded i3-msg - and i3-msg itself is never called.
  rm -f "$NOTIFY_SEND_CALLS" "$I3MSG_CALLS" "$CUSTOM_FOCUS_CALLS"
  printf '%s' "$payload" | AGENT_TIERS_NOTIFY_FOCUS_CMD='custom-focus id=%s' PATH="$FULL_PATH" NOTIFY_SELFCHECK_START_PID="$CHILD_PID" sh "$H" >/dev/null 2>"$T/stderr"
  sleep 1.5
  [ -f "$NOTIFY_SEND_CALLS" ] || fail "custom focus command: notify-send must still be called"
  grep -qx -- '-A' "$NOTIFY_SEND_CALLS" || fail "custom focus command: an action should still be offered when its tool is on PATH"
  [ -f "$CUSTOM_FOCUS_CALLS" ] || fail "the custom focus command must be called after the simulated click"
  grep -q "id=$XDOTOOL_STUB_ID" "$CUSTOM_FOCUS_CALLS" || fail "the custom focus command should receive the window id (got: $(cat "$CUSTOM_FOCUS_CALLS" 2>/dev/null))"
  [ ! -f "$I3MSG_CALLS" ] || fail "i3-msg must never be called when a custom focus command is configured"

  # 10b-ii. The natural settings.json spelling wraps %s in single quotes
  #         (`custom-focus 'id=%s'`) so the id survives as one argv word even through a shell
  #         re-parse. A top-level substitution of %s into a literal $1 would leave this %s sitting
  #         inside single quotes, where it never expands - the real id must still land in the
  #         stub's argument, not a literal "id=%s" or "id=$1".
  rm -f "$NOTIFY_SEND_CALLS" "$I3MSG_CALLS" "$CUSTOM_FOCUS_CALLS"
  printf '%s' "$payload" | AGENT_TIERS_NOTIFY_FOCUS_CMD="custom-focus 'id=%s'" PATH="$FULL_PATH" NOTIFY_SELFCHECK_START_PID="$CHILD_PID" sh "$H" >/dev/null 2>"$T/stderr"
  sleep 1.5
  [ -f "$CUSTOM_FOCUS_CALLS" ] || fail "quoted-%s focus command must still be called after the simulated click"
  grep -q "id=$XDOTOOL_STUB_ID" "$CUSTOM_FOCUS_CALLS" || fail "a %s wrapped in single quotes in the template must still receive the real window id, not a literal %s or \$1 (got: $(cat "$CUSTOM_FOCUS_CALLS" 2>/dev/null))"

  # 10c. AGENT_TIERS_NOTIFY_FOCUS_CMD explicitly set to empty: no click-to-focus action at all, even
  #      with a resolvable window and xdotool/i3-msg both on PATH - plain notification only.
  rm -f "$NOTIFY_SEND_CALLS" "$I3MSG_CALLS"
  printf '%s' "$payload" | AGENT_TIERS_NOTIFY_FOCUS_CMD='' PATH="$FULL_PATH" NOTIFY_SELFCHECK_START_PID="$CHILD_PID" sh "$H" >/dev/null 2>"$T/stderr"
  sleep 0.3
  [ -f "$NOTIFY_SEND_CALLS" ] || fail "empty focus command: notify-send must still be called (plain)"
  grep -qx -- '-A' "$NOTIFY_SEND_CALLS" && fail "an explicitly empty AGENT_TIERS_NOTIFY_FOCUS_CMD must disable the click action entirely"
  sleep 1.5
  [ ! -f "$I3MSG_CALLS" ] || fail "an empty focus command must never reach i3-msg"

  # 10d. AGENT_TIERS_NOTIFY_TERMINAL names a different ancestor comm (customterm, not alacritty) -
  #      proves the env var itself drives the search, not a hardcoded "alacritty" string. No
  #      negative control against the default name here: the process running this selfcheck could
  #      itself have a real alacritty ancestor on a host that runs one (same caveat as case 5's own
  #      comment), which would make a "must not match alacritty" assertion flaky by environment, not
  #      by a real regression.
  rm -f "$NOTIFY_SEND_CALLS" "$I3MSG_CALLS"
  printf '%s' "$payload" | AGENT_TIERS_NOTIFY_TERMINAL=customterm PATH="$FULL_PATH" NOTIFY_SELFCHECK_START_PID="$CHILD_PID2" sh "$H" >/dev/null 2>"$T/stderr"
  sleep 1.5
  [ -f "$NOTIFY_SEND_CALLS" ] || fail "custom terminal name: notify-send must still be called"
  grep -qx -- '-A' "$NOTIFY_SEND_CALLS" || fail "a matching AGENT_TIERS_NOTIFY_TERMINAL ancestor should still produce an action-carrying notification"
  [ -f "$I3MSG_CALLS" ] || fail "the default focus command (i3-msg) should still fire for a non-default terminal name"
  grep -q "id=$XDOTOOL_STUB_ID" "$I3MSG_CALLS" || fail "i3-msg should receive the window id"

  # 11. Fixture validity for cases 7-10: the injected CHILD_PID really is a descendant of a process
  #     whose comm is alacritty, or every "found" assertion above would be passing vacuously.
  [ "$(cat "/proc/$CHILD_PID/comm" 2>/dev/null || true)" != alacritty ] || fail "fixture invalid: CHILD_PID itself should not already read as alacritty (the walk would prove nothing)"
  ppid_of_child="$(awk '/^PPid:/{print $2}' "/proc/$CHILD_PID/status" 2>/dev/null || true)"
  [ "$ppid_of_child" = "$ALAC_PID" ] || fail "fixture invalid: CHILD_PID's parent should be the fake alacritty process"
  [ "$(cat "/proc/$ALAC_PID/comm" 2>/dev/null || true)" = alacritty ] || fail "fixture invalid: the fake ancestor's own comm must read as alacritty"
fi

# 12. Never blocks: exit 0 on an unparseable payload too. Forced to osc mode so this can never
#     reach notify-send/xdotool/i3-msg regardless of what is on the ambient PATH.
printf 'osc' > "$MODE_FILE"
printf '%s' 'not json' | sh "$H" >/dev/null 2>&1
[ $? -eq 0 ] || fail "unparseable payload must still exit 0"

# 13. Default mode, no mode file: notify-send preferred when it is on PATH.
rm -f "$MODE_FILE" "$NOTIFY_SEND_CALLS"
out="$(run "plain message" idle_prompt "")"
sleep 0.3
[ -f "$NOTIFY_SEND_CALLS" ] || fail "default with notify-send on PATH should prefer notify-send"

# 14. Default mode, no mode file, notify-send NOT reachable on PATH at all: falls back to osc.
#     BASE_TOOLS never includes notify-send, so this needs no PATH exclusion step.
rm -f "$MODE_FILE" "$NOTIFY_SEND_CALLS"
out="$(printf '%s' "$(jq -cn '{message:"plain message", notification_type:"idle_prompt"}')" | PATH="$BASE_TOOLS" sh "$H" 2>/dev/null)"
printf '%s' "$out" | jq -e '.terminalSequence' >/dev/null 2>&1 \
  || fail "default with no notify-send reachable on PATH should fall back to osc"

# 15. --probe: no side effects (no stdin read, kill switch ignored), and does no side effects even
#     when the kill switch sentinel exists.
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off"
touch "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/notify"
rm -f "$NOTIFY_SEND_CALLS"
probe_out="$(: | PATH="$NOTOOLS_PATH" sh "$H" --probe 2>&1)"; probe_rc=$?
[ "$probe_rc" = 0 ] || fail "--probe with notify-send on PATH should report supported (exit 0), got rc=$probe_rc: $probe_out"
[ -z "$probe_out" ] || fail "--probe supported must print nothing (got: $probe_out)"
[ ! -f "$NOTIFY_SEND_CALLS" ] || fail "--probe must never actually call notify-send"
rm -f "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/notify"

# 15b. --probe unsupported: no notify-send on PATH - exit 3 with a one-line reason naming the
#      --force-with-notify escape hatch. The probe is HOST-ONLY now (no terminal detection at
#      all - see notify.sh's own header for why), so TERM=xterm-kitty here must NOT flip it
#      supported, unlike an earlier version of this probe.
probe_out="$(printf '%s' | TERM=xterm-kitty PATH="$BASE_TOOLS" sh "$H" --probe 2>&1)"
probe_rc=$?
[ "$probe_rc" = 3 ] || fail "--probe with no notify-send should exit 3 regardless of TERM (got rc=$probe_rc: $probe_out)"
[ -n "$probe_out" ] || fail "--probe unsupported must print a one-line reason, got nothing"
[ "$(printf '%s' "$probe_out" | wc -l)" -le 1 ] || fail "--probe unsupported reason should be one line (got: $probe_out)"
case "$probe_out" in *force-with-notify*) ;; *) fail "--probe unsupported reason should name the --force-with-notify escape hatch (got: $probe_out)" ;; esac

# 15c. --probe is supported ONLY via notify-send on PATH - a recognised OSC terminal alone (no
#      notify-send) must NOT make it supported, since that is a per-session fact this probe no
#      longer judges.
probe_out="$(printf '%s' | TERM=xterm-kitty PATH="$BASE_TOOLS" sh "$H" --probe 2>&1)"; probe_rc=$?
[ "$probe_rc" = 3 ] || fail "--probe with TERM=xterm-kitty and no notify-send must still be UNSUPPORTED (probe no longer checks terminal) (got rc=$probe_rc: $probe_out)"

# 16. do_osc() composes OSC 99 (Kitty) when TERM=xterm-kitty at NOTIFICATION time - untested as a
#     string before this case (the probe never exercised do_osc, and every earlier osc-mode case
#     ran under the sanitised TERM=dumb baseline, i.e. always the OSC 777 default).
printf 'osc' > "$MODE_FILE"
out="$(TERM=xterm-kitty run "plain message" idle_prompt "")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
case "$seq" in *'99;i=1:d=0:p=title;Claude Code'*) ;; *) fail "OSC 99 title chunk missing/malformed (got: $seq)" ;; esac
case "$seq" in *'99;i=1:d=1:p=body;idle_prompt: plain message'*) ;; *) fail "OSC 99 body chunk missing/malformed (got: $seq)" ;; esac
esc_count="$(( $(printf '%s' "$seq" | tr -cd '\033' | wc -c) ))"
[ "$esc_count" = 4 ] || fail "OSC 99 (two chunks, each ESC...ST) should carry exactly 4 ESC bytes (2 open + 2 ST), got $esc_count: $seq"
bel_count="$(( $(printf '%s' "$seq" | tr -cd '\007' | wc -c) ))"
[ "$bel_count" = 0 ] || fail "OSC 99 is ST-terminated, not BEL - got $bel_count BEL byte(s): $seq"

# 17. do_osc() composes OSC 9 (iTerm2/WezTerm/Windows Terminal) when TERM_PROGRAM=WezTerm.
out="$(TERM_PROGRAM=WezTerm run "plain message" idle_prompt "")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
case "$seq" in *']9;Claude Code: idle_prompt: plain message'*) ;; *) fail "OSC 9 body missing/malformed (got: $seq)" ;; esac
esc_count="$(( $(printf '%s' "$seq" | tr -cd '\033' | wc -c) ))"
[ "$esc_count" = 1 ] || fail "OSC 9 should carry exactly one ESC, got $esc_count: $seq"
bel_count="$(( $(printf '%s' "$seq" | tr -cd '\007' | wc -c) ))"
[ "$bel_count" = 1 ] || fail "OSC 9 is BEL-terminated, got $bel_count BEL byte(s): $seq"

# 18. Ambient-leak proof: even if the CALLER of this selfcheck exported a real terminal's env vars,
#     the top-of-file reset must still make every DEFAULT (non-terminal-specific) case behave as if
#     on a plain terminal. Simulated here by re-asserting case 2's OSC-777 shape while TERM_PROGRAM
#     is deliberately left set from case 17 above (proves the reset is per-invocation via PATH/env
#     prefix at call sites that need it, not a one-shot global that a later case could accidentally
#     rely on staying clean) - unset it back explicitly, then confirm 777 again.
unset TERM_PROGRAM 2>/dev/null || true
out="$(run "plain message" idle_prompt "")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
case "$seq" in *"Claude Code;idle_prompt: plain message"*) ;; *) fail "after clearing a terminal override, the default case must return to OSC 777 (got: $seq)" ;; esac

# 19. Title prefers CLAUDE_PROJECT_DIR over the payload's own .cwd (the process cwd AT NOTIFICATION
#     TIME, which an agent's own `cd` can leave pointing at a subdirectory).
printf 'osc' > "$MODE_FILE"
out="$(CLAUDE_PROJECT_DIR=/home/user/projects/real-project run "plain message" idle_prompt "/home/user/projects/real-project/src")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
case "$seq" in *"Claude Code: real-project;"*) ;; *) fail "title should prefer CLAUDE_PROJECT_DIR's basename over the payload cwd's (got: $seq)" ;; esac
case "$seq" in *"Claude Code: src;"*) fail "title used the payload cwd basename instead of CLAUDE_PROJECT_DIR (got: $seq)" ;; esac

# 20. Icon: notify-send is called with -i <asset path> when the asset exists (it does, in this real
#     kit checkout), and with no -i at all when it's absent - never a hard failure either way.
REAL_ICON="$(cd "$(dirname "$H")/.." && pwd)/scripts/assets/notify-icon.png"
[ -f "$REAL_ICON" ] || fail "test setup: expected the real icon asset at $REAL_ICON"
printf 'notify-send' > "$MODE_FILE"
rm -f "$NOTIFY_SEND_CALLS"
printf '%s' "$payload5" | PATH="$NOTOOLS_PATH" sh "$H" >/dev/null 2>"$T/stderr"
sleep 0.3
grep -qx -- '-i' "$NOTIFY_SEND_CALLS" || fail "notify-send should be called with -i when the icon asset exists"
grep -qxF "$REAL_ICON" "$NOTIFY_SEND_CALLS" || fail "the -i argument should be the real icon asset path"

# Never mutate the real tracked asset (opus reviewer, 2026-09-17, MEDIUM: an earlier version
# `mv`'d it aside into $T, which the EXIT trap `rm -rf`s - a crash/timeout/interrupt between the
# move and the restore would permanently delete it from the canonical kit). Copy notify.sh itself
# into a sandbox with no assets/ sibling instead - BASE resolves relative to $0, so this exercises
# the genuine "asset absent" code path with zero risk to the real file.
NOICON_SANDBOX="$T/noicon/scripts"; mkdir -p "$NOICON_SANDBOX"
cp "$H" "$NOICON_SANDBOX/notify.sh" || fail "test setup: could not sandbox-copy notify.sh"
rm -f "$NOTIFY_SEND_CALLS"
printf '%s' "$payload5" | PATH="$NOTOOLS_PATH" sh "$NOICON_SANDBOX/notify.sh" >/dev/null 2>"$T/stderr"
sleep 0.3
[ -f "$NOTIFY_SEND_CALLS" ] || fail "a missing icon asset must never block the notification itself"
grep -qx -- '-i' "$NOTIFY_SEND_CALLS" && fail "with the icon asset absent, notify-send must be called with no -i at all"

# 21-24. Stop-event branch: notify-tag-guard.sh's required last line drives whether this fires at
# all, never Stop's own background_tasks (see notify-tag-guard.sh's header for why that field can't
# carry the distinction). want_input notifies with the tag stripped from the body, taking the TAIL
# of the message (the ask is usually right before the tag, not the opening line); no_input_required
# suppresses outright; an absent/unparseable tag ALSO stays silent (opus reviewer, 2026-09-17, HIGH:
# the sibling guard blocks and forces a retry moments later - notifying here too was a double-fire
# with premature content on every turn needing even one compliance retry). Gated on
# CLAUDE_CODE_ENTRYPOINT=cli throughout (opus reviewer, 2026-09-17, HIGH: a headless/claude -p
# caller must never be blocked or pinged - see notify.sh's own gate comment).
run_stop() { # $1=last_assistant_message
  jq -cn --arg m "$1" '{hook_event_name:"Stop", session_id:"sn", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=cli PATH="$FULL_PATH" sh "$H" 2>"$T/stderr"
}
printf 'osc' > "$MODE_FILE"

out="$(run_stop "$(printf 'The plan is ready.\noperator:want_input')")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
case "$seq" in *"The plan is ready."*) ;; *) fail "want_input should notify with the reply text in the body (got: $seq)" ;; esac
case "$seq" in *"operator:"*) fail "the operator: tag line must never leak into the notification body (got: $seq)" ;; esac

out="$(run_stop "$(printf 'Waiting on it.\noperator:no_input_required|reason:background build running')")"
[ -z "$out" ] || fail "no_input_required must suppress the notification entirely (got: $out)"
out="$(run_stop "$(printf 'Three options above.\noperator:ask_next')")"
[ -z "$out" ] || fail "ask_next must suppress the notification (a question box follows, not a finished turn) (got: $out)"

out="$(run_stop "Just some prose, no tag at all.")"
[ -z "$out" ] || fail "an absent/unparseable tag must stay SILENT (the sibling guard forces a retry) - got: $out"

# Hand-back tag guard (lib/handback-tag.sh): an untagged `!` command reply that ends want_input stays
# SILENT while handback-tag-guard is about to block it (no marker yet), pings once the guard has
# already blocked that reply (marker older than a few seconds), and a tagged one pings normally.
FENCE_HB='```'
HB_MSG="$(printf 'Run this:\n%s\n! sudo pacman -S x\n%s\noperator:want_input' "$FENCE_HB" "$FENCE_HB")"
out="$(run_stop "$HB_MSG")"
[ -z "$out" ] || fail "an untagged hand-back with no guard marker yet must stay silent (the guard is about to block) - got: $out"
. "$SRC_DIR/lib/handback-tag.sh"
HB_MARK="$(handback_tag_marker "$T/kit" sn "$(handback_tag_flagged "$HB_MSG")")"
mkdir -p "$(dirname "$HB_MARK")"; echo $(( $(date +%s) - 100 )) > "$HB_MARK"
out="$(run_stop "$HB_MSG")"
[ -n "$out" ] || fail "once the guard has blocked that reply (old marker) the retry must ping normally"
rm -f "$HB_MARK"
out="$(run_stop "$(printf 'Run this:\noperator:run|kind:oneoff\n%s\n! sudo pacman -S x\n%s\noperator:want_input' "$FENCE_HB" "$FENCE_HB")")"
[ -n "$out" ] || fail "a tagged hand-back ending want_input must ping normally"
case "$(printf '%s' "$out" | jq -r '.terminalSequence')" in *operator:run*) fail "the run tag line must not leak into the notification body" ;; esac
# A marker older than 10 minutes means the guard will block that reply again: stay silent.
echo $(( $(date +%s) - 700 )) > "$HB_MARK"
out="$(run_stop "$HB_MSG")"
[ -z "$out" ] || fail "a stale (over 10 minutes) guard marker means the guard blocks again: stay silent - got: $out"
rm -f "$HB_MARK"
# Unattended: the guard skips the session and writes no marker, so the hold must release and ping.
mkdir -p "$T/kit/.state"; : > "$T/kit/.state/unattended.sn"
out="$(run_stop "$HB_MSG")"
[ -n "$out" ] || fail "an unattended session must still ping on an untagged hand-back (the guard skips it, no marker ever comes)"
rm -f "$T/kit/.state/unattended.sn"
out="$(run_stop "$HB_MSG")"
[ -z "$out" ] || fail "attended again: an untagged hand-back with no marker must stay silent - got: $out"

# A mixed signal (an earlier stray operator: line plus a valid one at the end) must ALSO stay
# silent, not just an absent tag - live-demonstrated, 2026-09-17: this exact case used to fire a
# ping anyway, since this script's own tag-check only ever looked at the last line, while the
# sibling guard blocks the turn for showing two badges. Both now share lib/notify-tag.sh.
out="$(run_stop "$(printf 'operator:no_input_required|reason:earlier stray\nMore text.\noperator:want_input')")"
[ -z "$out" ] || fail "a mixed signal (an earlier tag plus a valid one at the end) must stay SILENT - got: $out"

# 24. Under a non-cli entrypoint (headless/claude -p/unproven third-party host), the Stop branch
#     must never notify even with a perfectly valid want_input tag.
out="$(jq -cn --arg m "$(printf 'Ready.\noperator:want_input')" '{hook_event_name:"Stop", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=sdk-cli PATH="$FULL_PATH" sh "$H" 2>"$T/stderr")"
[ -z "$out" ] || fail "a non-cli entrypoint must never notify on Stop, even with a valid tag (got: $out)"

# 25. A multi-line reply's newlines must be FOLDED, not deleted, so distinct lines never fuse into
#     one run-on word (opus reviewer, 2026-09-17, MEDIUM).
out="$(run_stop "$(printf 'Line one.\nLine two.\noperator:want_input')")"
seq="$(printf '%s' "$out" | jq -r '.terminalSequence')"
case "$seq" in *"Line one. Line two."*) ;; *) fail "multi-line body should have its newlines folded to spaces, not deleted (got: $seq)" ;; esac

# 26. notify-stop.sh's own `exec` wrapper (opus reviewer, 2026-09-17, LOW/Testing: its header claims
#     coverage via notify.sh's Stop branch, which is true for the branch but never exercised the
#     wrapper's own path resolution - a failed `cd` there would silently become `sh "/notify.sh"`).
STOP_WRAPPER="$(dirname "$H")/notify-stop.sh"
if [ -f "$STOP_WRAPPER" ]; then
  m="$(printf 'Ready.\noperator:want_input')"
  direct_out="$(jq -cn --arg m "$m" '{hook_event_name:"Stop", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=cli PATH="$FULL_PATH" sh "$H" 2>/dev/null)"
  wrapper_out="$(jq -cn --arg m "$m" '{hook_event_name:"Stop", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=cli PATH="$FULL_PATH" sh "$STOP_WRAPPER" 2>/dev/null)"
  [ "$direct_out" = "$wrapper_out" ] || fail "notify-stop.sh must produce identical output to notify.sh for the same Stop payload (direct: $direct_out / wrapper: $wrapper_out)"
else
  echo "note: skipped case 26 (notify-stop.sh wrapper) - file not present in this kit copy"
fi

# 26b. kit-gate stand-down, notify.sh: marker present -> no output, exit 0, no notify-send call, logged;
#      removed -> notifies again. --probe runs before the gate, so it answers the same with the marker.
printf 'osc' > "$MODE_FILE"
mkdir -p "$T/kit/.state/off"; : > "$T/kit/.state/off/notify"
rm -f "$NOTIFY_SEND_CALLS"
out="$(run "hello" permission_prompt "")"; rc=$?
probe_rc=0; PATH="$FULL_PATH" sh "$H" --probe </dev/null >/dev/null 2>&1 || probe_rc=$?
rm -f "$T/kit/.state/off/notify"
[ "$rc" = 0 ] && [ -z "$out" ] || fail "kit-gate stand-down (notify) must be silent exit 0 (rc=$rc out=$out)"
[ ! -f "$NOTIFY_SEND_CALLS" ] || fail "kit-gate stand-down (notify) must not call notify-send"
grep -qF 'kit-gate standdown notify:' "$T/guards.log" || fail "kit-gate stand-down (notify) must be logged"
[ "$probe_rc" = 0 ] || fail "--probe with notify-send on PATH must still exit 0 under the marker (rc=$probe_rc)"
probe_out="$(PATH="$BASE_TOOLS" sh "$H" --probe </dev/null 2>&1)"; probe_rc=$?
[ "$probe_rc" = 3 ] || fail "--probe with no notify-send must still exit 3 under the marker (rc=$probe_rc)"
[ -n "$(run "hello" permission_prompt "")" ] || fail "notify must emit again once the marker is removed"

# 26c. kit-gate stand-down, notify-stop.sh (its own id; it execs notify.sh, whose gate also runs): a Stop
#      payload that normally notifies produces nothing under the notify-stop marker, and logs the id.
m="$(printf 'Ready.\noperator:want_input')"
[ -n "$(jq -cn --arg m "$m" '{hook_event_name:"Stop", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=cli PATH="$FULL_PATH" sh "$T/kit/scripts/notify-stop.sh" 2>/dev/null)" ] \
  || fail "test setup: the Stop payload must notify without the notify-stop marker"
: > "$T/kit/.state/off/notify-stop"
rm -f "$NOTIFY_SEND_CALLS"
out="$(jq -cn --arg m "$m" '{hook_event_name:"Stop", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=cli PATH="$FULL_PATH" sh "$T/kit/scripts/notify-stop.sh" 2>/dev/null)"; rc=$?
rm -f "$T/kit/.state/off/notify-stop"
[ "$rc" = 0 ] && [ -z "$out" ] || fail "kit-gate stand-down (notify-stop) must be silent exit 0 (rc=$rc out=$out)"
[ ! -f "$NOTIFY_SEND_CALLS" ] || fail "kit-gate stand-down (notify-stop) must not call notify-send"
grep -qF 'kit-gate standdown notify-stop:' "$T/guards.log" || fail "kit-gate stand-down (notify-stop) must be logged"

# 27. Missing lib/notify-tag.sh (broken install) must still ping (fail toward notifying, never
#     total silence), and the fallback body must NOT contain the raw operator: tag text - opus
#     reviewer, 2026-09-17, MEDIUM: this exact gap (the fallback used to hand tail -c 200 the raw
#     tag line, since tail takes the END of the message by construction) shipped unnoticed because
#     no case exercised the missing-library branch at all. Sandbox layout mirrors notify.sh's own
#     BASE resolution ($BASE/scripts/lib/...): copy notify.sh to <sandbox>/scripts/, no lib/ sibling.
NOLIB_SANDBOX="$T/nolib/scripts"; mkdir -p "$NOLIB_SANDBOX"
cp "$H" "$NOLIB_SANDBOX/notify.sh" || fail "test setup: could not sandbox-copy notify.sh"
out="$(jq -cn --arg m "$(printf 'Ready.\noperator:want_input')" '{hook_event_name:"Stop", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=cli sh "$NOLIB_SANDBOX/notify.sh" 2>/dev/null)"
[ -n "$out" ] || fail "a missing library must still ping (fail toward notifying), got nothing"
case "$out" in *operator:*) fail "a missing library's fallback body must never leak the raw operator: tag text (got: $out)" ;; esac

echo "OK notify: kill switch, mode selection, cwd/type content, full sanitisation (control bytes + whole-string UTF-8-safe cap, newlines folded not deleted), the alacritty-ancestor click-to-focus path (with digits-only + non-ambiguous window validation), the setsid>nohup>plain detachment fallback, CLAUDE_PROJECT_DIR-preferred title, the icon flag, the Stop-event operator: tag gate (want_input notifies from the tail of the message, no_input_required, ask_next and an absent tag all suppress, a non-cli entrypoint always suppresses), and the notify-stop.sh wrapper's own path resolution all hold, hook always returns fast, never blocks"

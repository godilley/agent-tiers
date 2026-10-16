#!/usr/bin/env sh
# kit-scope: shared
# kit-probe: yes
# agent-tiers Notification hook: surface a permission_prompt/idle_prompt notification through
# whichever delivery this terminal actually supports, with enough content to say WHICH session
# needs you and (on notify-send, with the configured terminal + focus command - i3 + alacritty by
# default) a click-to-focus action on the notification.
# Consent row - install-flat.sh --with-notify.
#
# Content (both delivery paths):
#   title: "Claude Code: <basename of cwd>" - degrades to plain "Claude Code" with no cwd.
#   body:  "<notification_type>: <message>" - degrades to just the message (itself defaulted to a
#          generic line) with no notification_type.
# Every field is sanitised (control bytes stripped) and length-capped before it reaches either an
# escape sequence or a shell-invoked command's argument.
#
# Install-time support probe (`# kit-probe: yes` above): `sh notify.sh --probe` does no side
# effects, reads no stdin, ignores the kill switch. Supported (exit 0, no output) ONLY if
# notify-send is on PATH - a genuine HOST property, true (or not) for every future session on this
# profile. Otherwise exit 3 with a one-line reason naming the escape hatch. install-flat.sh runs
# this before writing settings.json for `--with-notify` and refuses the install on exit != 0.
#
# Deliberately NOT probed: which terminal a FUTURE session runs in. That is a PER-SESSION property,
# not a host one - the installing shell's TERM/TERM_PROGRAM says nothing about the terminal any
# later session (a different window, a different SSH client, kitty today and alacritty tomorrow)
# will actually run in. Probing it would produce a false accept (installed from kitty, then a
# session in alacritty over ssh with no notify-send gets a silently-dead OSC 777 default) or a
# false refuse (installed from Terminal.app while real sessions run in iTerm2). Section 4's own
# design note on this: "an install-time probe is a stale snapshot nothing re-runs" - true here.
# `detect_osc_kind()` below still runs at NOTIFICATION TIME, per session, in do_osc() - that is the
# one place this fact is actually current.
#
# Delivery:
#   - terminalSequence (hooks.md "Emit terminal notifications"): OSC 9, 99 or 777 depending on the
#     DETECTED terminal (detect_osc_kind(), evaluated fresh at NOTIFICATION time - the probe above
#     does not call it), defaulting to 777 when detection is inconclusive - restricted to OSC
#     0/1/2/9/99/777 and BEL, anything else is
#     silently dropped by Claude Code. Only takes effect in an interactive session with the
#     interface on screen; ignored under -p. No click action: OSC has no click-to-focus channel,
#     this is content-only. The OSC 9/99 forms are UNVERIFIED against a real iTerm2/WezTerm/Kitty
#     terminal (built and tested on i3 + alacritty) - probe before relying on them, same as this
#     kit's other host-specific claims.
#   - notify-send: a real desktop notification via the host's notification daemon. When the window
#     running this session can be identified UNAMBIGUOUSLY (the configured terminal's ancestor of
#     this hook process -> EXACTLY ONE X11 window id for that pid via xdotool) and both xdotool and
#     the configured focus command's own tool are present, the notification carries a "Focus" action
#     (-A default=Focus); clicking it runs the configured focus command. Two env knobs, both
#     defaulting to today's fixed behaviour: AGENT_TIERS_NOTIFY_TERMINAL (matched against
#     /proc/<pid>/comm, a kernel field truncated to 15 bytes - e.g. "gnome-terminal-server" will
#     never match, only its first 15 bytes would need to - default alacritty, which fits) and
#     AGENT_TIERS_NOTIFY_FOCUS_CMD (a command template with %s for the window id, default
#     `i3-msg "[id=%s] focus"`; an empty string disables click-to-focus entirely - plain notification
#     only). The template's FIRST WORD must be the command itself - that is literally what
#     `command -v` is run against to gate the click action, so a template starting with an alias,
#     an env assignment, or wrapper syntax will never pass the check. A multi-window terminal process
#     (its own `create-window` IPC) resolves to more than one window id and is treated the same as
#     no window: plain notification, no action - picking xdotool's first line would risk focusing the
#     wrong one. The notify-send
#     call (and the wait for a click) runs fully DETACHED (setsid, or nohup, or a plain background
#     job if neither tool exists - see detach() - stdin from /dev/null) so this hook still returns
#     immediately: PreCompact aside, every other event in this kit is meant to be cheap and
#     non-blocking, and a notification a human may not click for minutes must not hold a hook
#     process open that long.
#
# Mode is read from .state/notify-mode (osc | notify-send | both). Default when the file is absent:
# notify-send if it is on PATH (works regardless of terminal), else osc.
#
# Never blocks: Notification hooks have no decision control at all (hooks.md), and this always
# exits 0 even on a delivery failure or a missing xdotool/i3-msg/timeout/setsid/nohup.
# Self-check: notify.selfcheck.sh.
set -u

# Which OSC form (hooks.md "Emit terminal notifications") the CURRENT terminal is documented to
# render, detected from env vars a hook process inherits. Sets OSC_KIND to 9, 99 or 777 and returns
# 0 on a positive match; returns 1 with OSC_KIND empty when nothing matches (do_osc() then defaults
# to 777, and the probe treats "nothing matched, and no notify-send either" as unsupported).
# Mapping is exactly hooks.md's own list; the detection env vars are the ones each terminal is
# documented (by that terminal, not by this kit) to set - not independently verified here against
# a real iTerm2/WezTerm/Kitty session.
detect_osc_kind() {
  case "${TERM_PROGRAM:-}" in
    iTerm.app | WezTerm) OSC_KIND=9; return 0 ;;
    WarpTerminal) OSC_KIND=777; return 0 ;;
  esac
  [ -n "${WT_SESSION:-}" ] && { OSC_KIND=9; return 0; }        # Windows Terminal
  case "${TERM:-}" in
    xterm-kitty) OSC_KIND=99; return 0 ;;
    rxvt-unicode*) OSC_KIND=777; return 0 ;;                   # urxvt
  esac
  [ -n "${GHOSTTY_RESOURCES_DIR:-}" ] && { OSC_KIND=777; return 0; }   # Ghostty
  OSC_KIND=""
  return 1
}

if [ "${1:-}" = "--probe" ]; then
  command -v notify-send >/dev/null 2>&1 && exit 0
  echo "no notify-send found on PATH - OSC delivery depends on the terminal each session actually runs in, which this install-time probe cannot see; if your sessions run in an OSC-9/99/777-capable terminal (see notify.sh's own header), wire it anyway with: install-flat.sh --force-with-notify"
  exit 3
fi

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
# Kit-shared icon asset - BASE is the kit root (canonical, shared across every CLAUDE_CONFIG_DIR
# profile), so this resolves regardless of which profile's settings.json wired this hook. Missing
# file = no -i flag passed to notify-send later, never a hard failure (fail-open, same posture as
# the rest of this script).
ICON=""
[ -n "$BASE" ] && [ -f "$BASE/scripts/assets/notify-icon.png" ] && ICON="$BASE/scripts/assets/notify-icon.png"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s notify fail-open: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

# Folds newlines to a space FIRST (opus reviewer, 2026-09-17: a multi-line last_assistant_message -
# the normal shape of a reply, since this project's own house style mandates bullets/headings -
# jammed into one run-on string when LF was simply deleted rather than replaced, e.g. "## Findings"
# and the first bullet fusing into "## Findingsitem one"), then strips the rest of the FULL C0
# control range (0-31, incl. TAB/CR - an earlier version's range left TAB/LF/CR out, so those
# survived into the OSC payload/notify-send args) plus DEL. Guarantees the composed title/body is
# always a single line.
sanitize() { printf '%s' "$1" | tr '\n' ' ' | tr -d '\000-\037\177'; }
# Caps the WHOLE string to $2 BYTES under the C locale (`cut -c` treats each byte as one
# "character" in the C/POSIX locale, on every cut implementation this kit has checked - GNU, BSD and
# BusyBox alike - so this is a portable byte cut regardless of the CALLER's locale). A byte cut can
# still split a multi-byte UTF-8 character at the boundary, so the tail is repaired afterwards: an
# earlier version relied on awk's substr() being character-aware, but that only holds for gawk under
# a UTF-8 locale - under LC_ALL=C, or under mawk/BusyBox awk in ANY locale (both byte-count always),
# substr() still splits a character in half. There is no locale/awk-flavour-independent
# character-aware primitive in POSIX sh, so this caps by bytes and fixes up the tail instead.
cap() { # $1=text $2=max bytes
  n="$2"
  bytes="$(printf '%s' "$1" | LC_ALL=C cut -c1-"$n")"
  if command -v iconv >/dev/null 2>&1; then
    # -c drops invalid/incomplete characters from the output, which is exactly a truncated
    # trailing multi-byte sequence - the standard, correct way to repair a byte-cut UTF-8 string.
    printf '%s' "$bytes" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null
  else
    trim_incomplete_utf8 "$bytes"
  fi
}

# Fallback for a host with no iconv: drop a trailing UTF-8 sequence left incomplete by the byte cut
# above. Pure POSIX byte arithmetic - reads the last up-to-4 bytes as hex, counts trailing
# continuation bytes (0x80-0xBF), then checks whether the byte just before them is a multi-byte
# lead byte (0xC0+) whose declared length does not match how many continuation bytes actually
# follow it; if so, the whole truncated sequence (lead + its continuation bytes) is dropped.
trim_incomplete_utf8() { # $1 = byte string already cut to the byte cap
  s="$1"
  len="$(printf '%s' "$s" | LC_ALL=C wc -c)"
  [ "$len" -gt 0 ] || { printf '%s' "$s"; return; }
  tail_hex="$(printf '%s' "$s" | LC_ALL=C tail -c4 | LC_ALL=C od -An -tx1 | tr -d ' \n')"
  cont=0
  i=${#tail_hex}
  while [ "$i" -ge 2 ] && [ "$cont" -lt 3 ]; do
    byte_dec=$(( 0x$(printf '%s' "$tail_hex" | cut -c$((i - 1))-"$i") ))
    if [ "$byte_dec" -ge 128 ] && [ "$byte_dec" -le 191 ]; then
      cont=$((cont + 1)); i=$((i - 2))
    else
      break
    fi
  done
  if [ "$i" -ge 2 ]; then
    lead_dec=$(( 0x$(printf '%s' "$tail_hex" | cut -c$((i - 1))-"$i") ))
    need=0
    if   [ "$lead_dec" -ge 240 ]; then need=3
    elif [ "$lead_dec" -ge 224 ]; then need=2
    elif [ "$lead_dec" -ge 192 ]; then need=1
    fi
    if [ "$need" -gt 0 ] && [ "$need" -ne "$cont" ]; then
      keep=$((len - cont - 1)); [ "$keep" -lt 0 ] && keep=0
      printf '%s' "$s" | LC_ALL=C cut -c1-"$keep"; return
    fi
  elif [ "$cont" -gt 0 ]; then
    keep=$((len - cont)); [ "$keep" -lt 0 ] && keep=0
    printf '%s' "$s" | LC_ALL=C cut -c1-"$keep"; return
  fi
  printf '%s' "$s"
}

# Walk the PPID chain from a starting pid (default: this process, $$) up to the first ancestor
# whose /proc comm matches AGENT_TIERS_NOTIFY_TERMINAL (default "alacritty"). Linux-specific (/proc):
# this branch simply never finds an ancestor on a host with no /proc (macOS, BSD), which is a plain
# "no window resolvable" case handled the same as any other - there is no portable PPID-walk
# primitive in POSIX sh without it. Bounded at 50 hops so a /proc read failure or a pid-reuse cycle
# can never loop.
#
# Testable: the starting pid can be overridden with NOTIFY_SELFCHECK_START_PID (checked ONLY when
# no explicit $1 is given), so a selfcheck can inject a fake ancestor matching the target name (any
# binary copied to a path named after it and exec'd directly gets that comm, regardless of what it
# actually is) without needing this hook's own process to run inside a real terminal window.
terminal_pid_from() {
  p="${1:-${NOTIFY_SELFCHECK_START_PID:-$$}}"
  target="${AGENT_TIERS_NOTIFY_TERMINAL:-alacritty}"
  i=0
  while [ "$i" -lt 50 ]; do
    [ -r "/proc/$p/comm" ] || return 1
    c="$(cat "/proc/$p/comm" 2>/dev/null || true)"
    if [ "$c" = "$target" ]; then printf '%s\n' "$p"; return 0; fi
    ppid="$(awk '/^PPid:/{print $2}' "/proc/$p/status" 2>/dev/null || true)"
    case "${ppid:-}" in '' | *[!0-9]*) return 1 ;; esac
    [ "$ppid" -gt 1 ] 2>/dev/null || return 1
    p="$ppid"
    i=$((i + 1))
  done
  return 1
}

# Kill switch first, before any side effect or read.
[ -f "$CLAUDE_DIR/agent-tiers/.state/off/notify" ] && exit 0
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "jq missing - cannot parse payload"; exit 0; }

HOOK_EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"

# Title basename: CLAUDE_PROJECT_DIR (exported to every hook process, stable across an agent's own
# `cd` or a worktree) beats the payload's `.cwd` (the process cwd AT NOTIFICATION TIME - an agent
# that `cd`ed left this reading e.g. "src" instead of the project name). `.cwd` is kept only as a
# fallback for a harness version that doesn't export the var.
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"
if [ -n "$PROJECT_DIR" ]; then
  BASENAME="$(basename "$PROJECT_DIR" 2>/dev/null || true)"
  BASENAME="$(cap "$(sanitize "$BASENAME")" 60)"
  TITLE="Claude Code: $BASENAME"
else
  TITLE="Claude Code"
fi
TITLE="$(cap "$TITLE" 80)"

if [ "$HOOK_EVENT" = "Stop" ]; then
  # Headless/scripted runs (opus reviewer, 2026-09-17, HIGH): a desktop ping is meaningless with
  # nobody at a terminal to see it, and this kit's own `claude -p` callers (e.g. publish-public
  # drafting a commit message) would otherwise have the tag's sibling guard block on their
  # machine-consumed output. `CLAUDE_CODE_ENTRYPOINT` is this kit's own established detection
  # (HOST.md HOST-1): only the EXACT value `cli` is proven native-interactive; `sdk-cli` is `claude
  # -p`, and every other value is an unproven third-party host - skip for all of those too, since a
  # missed desktop ping is far cheaper than blocking or polluting a headless caller's output.
  [ "${CLAUDE_CODE_ENTRYPOINT:-}" = "cli" ] || exit 0

  # notify-tag-guard.sh (wired as a sibling Stop hook, same CLAUDE_CODE_ENTRYPOINT gate) blocks a
  # turn from ending until it is tag-compliant - see that script's own header for why
  # background_tasks alone can't carry this, and lib/notify-tag.sh's header for why the compliance
  # check itself is shared rather than kept as two separate copies (it drifted twice: first when
  # this script's own copy fired a premature ping on an untagged reply the guard was about to
  # retry, then again when the guard learned to reject a MIXED signal - an earlier stray tag plus a
  # valid one at the end - but this script's copy still only looked at the last line, so a reply
  # the guard blocked for showing two badges still fired a ping anyway). Anything the guard would
  # also reject (mixed or invalid) stays SILENT here: that relies on the guard actually being wired
  # alongside this script, both from the same install/options.tsv rows installed together - a non-compliant
  # Stop means "the guard is about to force a retry", not "nothing is enforcing this". Disclosed
  # ceiling (opus reviewer, 2026-09-17, LOW, not chased): that premise is false at Claude Code's
  # documented 8-consecutive-block ceiling - if the model is STILL non-compliant on the 8th attempt,
  # Claude Code lets the turn end anyway, and this script stays silent right when a stuck compliance
  # loop most needs a ping. Rare (8 failed retries in a row) and the fix is non-trivial (would need
  # to check guards.log for a recent-block streak); accepted rather than built.
  LAST_MSG="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
  TAG_LIB="$BASE/scripts/lib/notify-tag.sh"
  # `sh -n` before sourcing (opus reviewer, 2026-09-17, MEDIUM, same fix as notify-tag-guard.sh):
  # a corrupted lib file dot-sourced under dash aborts the WHOLE script with a parse-error exit,
  # not a graceful fail-open.
  if [ -n "$BASE" ] && [ -f "$TAG_LIB" ] && sh -n "$TAG_LIB" >/dev/null 2>&1; then
    . "$TAG_LIB"
  fi
  if command -v notify_tag_classify >/dev/null 2>&1; then
    case "$(notify_tag_classify "$LAST_MSG")" in
      want_input) BODY_SRC="$(printf '%s' "$LAST_MSG" | sed '$d')" ;;
      *) exit 0 ;;   # no_input_required, ask_next (a question box follows), mixed, or invalid
    esac
  else
    # Missing/stale library (broken install, not a normal runtime state) - fail toward pinging,
    # never toward total silence, same posture the tag-absent case took before the classifier was
    # extracted into a shared library. Still strip a trailing operator: line by pattern alone
    # (opus reviewer, 2026-09-17, MEDIUM: without the classifier this used to hand the RAW tag text
    # to `tail -c 200` below, which - by construction - takes the END of the message, guaranteeing
    # the one artifact the whole strip hook exists to hide showed up in the notification body).
    note "fail-open: lib/notify-tag.sh missing/stale/unparseable - pinging with a best-effort body"
    case "$(printf '%s' "$LAST_MSG" | tail -n 1)" in
      operator:*) BODY_SRC="$(printf '%s' "$LAST_MSG" | sed '$d')" ;;
      *) BODY_SRC="$LAST_MSG" ;;
    esac
  fi
  # Tail, not head (opus reviewer, 2026-09-17, LOW): the actual ask is usually the last thing said,
  # right before the tag line that was just stripped - a head-truncated body shows the opening line
  # instead. `tail -c` can split a leading multi-byte UTF-8 char; cosmetic only, same disclosed
  # class as this file's other byte-boundary ceilings.
  MESSAGE="$(sanitize "$BODY_SRC")"
  MESSAGE="$(printf '%s' "$MESSAGE" | tail -c 200)"
  [ -n "$MESSAGE" ] || MESSAGE="Claude Code needs your attention"
  BODY="$(cap "$MESSAGE" 240)"
else
  TYPE="$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null || true)"
  MESSAGE="$(printf '%s' "$INPUT" | jq -r '.message // "Claude Code needs your attention"' 2>/dev/null || echo "Claude Code needs your attention")"
  # --- content: sanitize every raw field BEFORE it is composed into title/body, then cap the
  # composed result too (a field at exactly the cap could still combine into an oversized string).
  MESSAGE="$(cap "$(sanitize "$MESSAGE")" 200)"
  if [ -n "$TYPE" ]; then
    TYPE="$(cap "$(sanitize "$TYPE")" 40)"
    BODY="$TYPE: $MESSAGE"
  else
    BODY="$MESSAGE"
  fi
  BODY="$(cap "$BODY" 240)"
fi

MODE_FILE="$CLAUDE_DIR/agent-tiers/.state/notify-mode"
if [ -f "$MODE_FILE" ]; then
  MODE="$(cat "$MODE_FILE" 2>/dev/null | tr -d '[:space:]')"
else
  MODE=""
fi
case "$MODE" in
  osc | notify-send | both) ;;
  *)
    if command -v notify-send >/dev/null 2>&1; then MODE=notify-send; else MODE=osc; fi
    ;;
esac

do_osc() {
  # `;` is a field separator in both OSC 777 (\033]777;notify;<title>;<body>\007) and OSC 99's
  # metadata/payload split - a title or body that still carried one (a cwd basename like "a;b", or
  # a message containing one) could shift the split in a terminal that parses the sequence
  # literally. Replaced, not stripped, so no information vanishes - notify-send is unaffected, it
  # takes title/body as separate arguments, never a composed string.
  t="$(printf '%s' "$TITLE" | tr ';' ',')"
  b="$(printf '%s' "$BODY" | tr ';' ',')"
  detect_osc_kind   # sets OSC_KIND; falls through to the 777 default on no match (return 1 ignored)
  case "${OSC_KIND:-}" in
    99)
      # Kitty desktop notifications: title and body as two chunks sharing one notification id
      # (i=1), the second marked done (d=1). UNVERIFIED against a real Kitty session - see header.
      seq="$(printf '\033]99;i=1:d=0:p=title;%s\033\\\033]99;i=1:d=1:p=body;%s\033\\' "$t" "$b")"
      ;;
    9)
      # iTerm2/WezTerm/Windows Terminal: one combined string, no separate title/body fields.
      seq="$(printf '\033]9;%s: %s\007' "$t" "$b")"
      ;;
    *)
      seq="$(printf '\033]777;notify;%s;%s\007' "$t" "$b")"
      ;;
  esac
  jq -nc --arg seq "$seq" '{terminalSequence: $seq}' 2>/dev/null || true
}

# The focus command template, env-configurable. AGENT_TIERS_NOTIFY_FOCUS_CMD unset keeps today's
# exact default (`i3-msg "[id=%s] focus"`, quoted exactly as before); set to the empty string it
# disables click-to-focus entirely - resolve_window() below never even looks for a window. %s, if
# present, is substituted with the actual window id LATER, inside do_notify_send's detached INNER
# script, AFTER that id has already been validated digits-only - never here. A naive top-level
# substitution into a literal "$1" would break the natural settings.json spelling
# `i3-msg '[id=%s] focus'`: %s sitting inside single quotes in the template never expands as a
# shell variable, so the raw template (not a pre-converted script) is what gets passed down.
if [ "${AGENT_TIERS_NOTIFY_FOCUS_CMD+set}" = set ]; then
  FOCUS_CMD="$AGENT_TIERS_NOTIFY_FOCUS_CMD"
else
  FOCUS_CMD='i3-msg "[id=%s] focus"'
fi

# Resolve the window to focus, ONLY when we are actually about to call notify-send (osc-only mode
# has no click channel, so this work would be wasted). Any of {empty FOCUS_CMD, no xdotool, no
# focus-command tool, no matching terminal ancestor, no window for that pid, MORE THAN ONE window
# for that pid} leaves WID empty - the caller then sends a plain notification. The "more than one"
# case matters because a terminal's own multi-window IPC (e.g. alacritty's `create-window`) can
# serve several windows from a single process: picking xdotool's first line would silently focus the
# wrong one, so an ambiguous match is treated the same as no match. The required-tool check tests the
# first word of FOCUS_CMD (not a hardcoded i3-msg) - that word must be the command itself, since
# that is exactly the string `command -v` is run against; a template starting with anything else
# (an alias, an env assignment, a shell builtin) will never pass this gate.
resolve_window() {
  WID=""
  [ -n "$FOCUS_CMD" ] || return 0
  command -v xdotool >/dev/null 2>&1 || return 0
  cmdname="${FOCUS_CMD%% *}"
  command -v "$cmdname" >/dev/null 2>&1 || return 0
  APID="$(terminal_pid_from 2>/dev/null || true)"
  [ -n "$APID" ] || return 0
  wlist="$(xdotool search --pid "$APID" 2>/dev/null || true)"
  wcount="$(printf '%s\n' "$wlist" | grep -c .)"
  [ "$wcount" -eq 1 ] 2>/dev/null || return 0   # zero -> no window; more than one -> ambiguous, skip
  w="$wlist"
  case "$w" in '' | *[!0-9]*) return 0 ;; esac   # digits-only or unused - never trust a raw xdotool line
  WID="$w"
}

# Runs $1 (a shell script BODY, referencing $1.. inside itself) fully detached and backgrounded,
# preferring setsid (its own session, immune to this hook's process exiting) > nohup (ignores
# SIGHUP, the next-best detachment) > a plain background job (still survives in practice: a
# non-interactive script's background children are not sent SIGHUP on exit unless the shell itself
# has job control enabled). Never skipped outright - "no detachment tool available" must still
# deliver the notification, just without the stronger guarantee.
detach() { # $1=script body; $2.. = its positional args
  scr="$1"; shift
  if command -v setsid >/dev/null 2>&1; then
    setsid sh -c "$scr" _ "$@" </dev/null >/dev/null 2>&1 &
  elif command -v nohup >/dev/null 2>&1; then
    nohup sh -c "$scr" _ "$@" </dev/null >/dev/null 2>&1 &
  else
    sh -c "$scr" _ "$@" </dev/null >/dev/null 2>&1 &
  fi
}

do_notify_send() {
  command -v notify-send >/dev/null 2>&1 || { note "notify-send not on PATH"; return 0; }
  resolve_window
  HASACT=0
  [ -n "${WID:-}" ] && HASACT=1
  TCMD=""
  command -v timeout >/dev/null 2>&1 && TCMD=timeout
  # stdin from /dev/null, stdout/stderr discarded EXCEPT the action-click line notify-send itself
  # prints on its own stdout, which this inner subshell captures and acts on - never surfaced to the
  # hook's own stdout (that fd is untouched here; the whole pipeline is backgrounded by detach()).
  INNER='
    t="$1"; b="$2"; w="$3"; hasact="$4"; tcmd="$5"; icon="$6"; tpl="$7"
    ns() { # notify-send with the shared -a app-name and, when set, -i icon; $@ = its own args
      if [ -n "$icon" ]; then
        if [ -n "$tcmd" ]; then "$tcmd" 600 notify-send -a "Claude Code" -i "$icon" "$@" </dev/null 2>/dev/null
        else notify-send -a "Claude Code" -i "$icon" "$@" </dev/null 2>/dev/null
        fi
      else
        if [ -n "$tcmd" ]; then "$tcmd" 600 notify-send -a "Claude Code" "$@" </dev/null 2>/dev/null
        else notify-send -a "Claude Code" "$@" </dev/null 2>/dev/null
        fi
      fi
    }
    if [ "$hasact" = 1 ]; then
      out="$(ns -A default=Focus "$t" "$b")"
      if [ "$out" = default ] && [ -n "$w" ]; then
        # w is validated digits-only HERE, then substituted straight into the template text (no
        # shell metacharacters possible in [0-9]+, so this is safe even though the result is run
        # through sh -c) - never handed to the caller as a raw script, and never relying on a
        # positional-param expansion that a single-quoted %s in the template (the natural
        # settings.json spelling, e.g. i3-msg with [id=%s] wrapped in single quotes) would defeat.
        case "$w" in
          *[!0-9]*) : ;;
          *)
            case "$tpl" in
              *"%s"*) cmd="${tpl%%%s*}$w${tpl#*%s}" ;;
              *) cmd="$tpl" ;;
            esac
            sh -c "$cmd" >/dev/null 2>&1
            ;;
        esac
      fi
    else
      ns "$t" "$b" >/dev/null 2>&1
    fi
  '
  detach "$INNER" "$TITLE" "$BODY" "${WID:-}" "$HASACT" "$TCMD" "$ICON" "$FOCUS_CMD"
}

case "$MODE" in
  osc) do_osc ;;
  notify-send) do_notify_send ;;
  both) do_notify_send; do_osc ;;
esac

exit 0

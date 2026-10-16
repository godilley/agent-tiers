#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers environment detection: describes the desktop this shell runs on and PROPOSES values
# for three kit env vars (AGENT_TIERS_NOTIFY_FOCUS_CMD, AGENT_TIERS_NOTIFY_TERMINAL,
# AGENT_TIERS_BADGE_GLYPHS). Read-only: writes no file or setting of its own (no temp files; fc-list may
# update fontconfig's cache as it normally does); an
# installer reads the output and asks the user to confirm each proposal. Takes no arguments (any
# argument: usage on stderr, exit 2). Always exits 0 otherwise. Fail soft: a missing tool degrades
# that one value to unknown/none, never an error. POSIX sh; dash, bash, Linux and macOS (BSD tools).
#
# OUTPUT INTERFACE (parsed by the installer). One `key=value` per line. The value is everything
# after the FIRST `=`, verbatim, NOT shell-quoted, never to be eval'd. Every value is a single line
# with control bytes (newline, CR, TAB, ...) stripped. Order:
#   os=linux|macos|<uname -s lowercased, [a-z0-9._-]>|unknown
#   desktop=gnome|kde|i3|sway|hyprland|macos|<other>|unknown
#   session=x11|wayland|tty|macos|unknown
#   terminal=<process name>|unknown
#   nerd_font=yes|no|unknown
#   notifier=notify-send|terminal-notifier|osascript|none
#   [propose.AGENT_TIERS_NOTIFY_FOCUS_CMD=<value>]
#   reason.AGENT_TIERS_NOTIFY_FOCUS_CMD=<one line>
#   [propose.AGENT_TIERS_NOTIFY_TERMINAL=<value>]
#   reason.AGENT_TIERS_NOTIFY_TERMINAL=<one line>
#   [propose.AGENT_TIERS_BADGE_GLYPHS=<value>]
#   reason.AGENT_TIERS_BADGE_GLYPHS=<one line>
# A `propose.` line appears ONLY when there is a proposal; its absence means "no proposal" (this
# version never proposes an empty value). Every `reason.` line is always printed.
#
# notifier is a fact: notify.sh itself delivers only through notify-send or a terminal escape
# sequence. terminal-notifier / osascript are reported but not something the kit wires.
#
# Test seams (safe defaults; exist only so the selfcheck is deterministic):
#   DETECT_ENV_START_PID  pid where the terminal ancestor walk starts (default: $PPID)
#   DETECT_ENV_PROC       proc filesystem root (default: /proc)
set -u

if [ $# -gt 0 ]; then echo "usage: detect-env.sh (takes no arguments)" >&2; exit 2; fi

# First line only, control bytes stripped.
san() { printf '%s\n' "$1" | head -n 1 | tr -d '\000-\037\177'; }
# Lowercased, reduced to [a-z0-9._-].
slug() { san "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9._-'; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- os
un="$(uname -s 2>/dev/null || true)"
case "$un" in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  *) os="$(slug "$un")"; [ -n "$os" ] || os=unknown ;;
esac

# ---- desktop
desktop=unknown
if [ "$os" = macos ]; then
  desktop=macos
elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then desktop=hyprland
elif [ -n "${SWAYSOCK:-}" ]; then desktop=sway
elif [ -n "${I3SOCK:-}" ]; then desktop=i3
else
  xcd="$(san "${XDG_CURRENT_DESKTOP:-}" | tr 'A-Z' 'a-z')"
  oldifs="$IFS"; IFS=:; set -f; set -- $xcd; set +f; IFS="$oldifs"
  first=""; found=""
  for f in "$@"; do
    [ -n "$first" ] || first="$f"
    [ -n "$found" ] && continue
    case "$f" in
      *gnome*) found=gnome ;;
      *kde*) found=kde ;;
      *hyprland*) found=hyprland ;;
      *sway*) found=sway ;;
      *i3*) found=i3 ;;
    esac
  done
  if [ -n "$found" ]; then desktop="$found"
  else
    first="$(slug "$first")"
    [ -n "$first" ] && desktop="$first"
  fi
fi

# ---- session
xst="$(slug "${XDG_SESSION_TYPE:-}")"
if [ "$os" = macos ]; then session=macos
elif [ "$xst" = x11 ] || [ "$xst" = wayland ]; then session="$xst"
elif [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${SWAYSOCK:-}" ] || [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then session=wayland
elif [ -n "${DISPLAY:-}" ] || [ -n "${I3SOCK:-}" ]; then session=x11
elif [ "$xst" = tty ]; then session=tty
else session=unknown
fi

# ---- terminal (walk the parent chain)
terminal=unknown
tpid=""
in_editor=""
proc="${DETECT_ENV_PROC:-/proc}"
p="${DETECT_ENV_START_PID:-$PPID}"
i=0
while [ "$i" -lt 50 ]; do
  case "$p" in '' | *[!0-9]*) break ;; esac
  [ "$p" -gt 1 ] 2>/dev/null || break
  if [ -r "$proc/$p/comm" ]; then
    name="$(head -n 1 "$proc/$p/comm" 2>/dev/null)"
    par="$(sed -n 's/^PPid:[[:space:]]*//p' "$proc/$p/status" 2>/dev/null | head -n 1)"
  elif have ps; then
    name="$(ps -o comm= -p "$p" 2>/dev/null | head -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$name" ] && name="$(basename -- "$name")"
    par="$(ps -o ppid= -p "$p" 2>/dev/null | head -n 1)"
  else
    break
  fi
  name="$(san "$name")"
  par="$(printf '%s' "$par" | tr -d ' \t\r')"
  [ -n "$name" ] || break
  case "$name" in
    alacritty | kitty | foot | footclient | wezterm-gui | wezterm | gnome-terminal- | kgx | konsole | xterm | uxterm | urxvt | urxvtd | rxvt | st | terminator | tilix | xfce4-terminal | lxterminal | mate-terminal | qterminal | ghostty | sakura | terminology | cool-retro-term | contour | rio | Terminal | iTerm2 | WezTerm | Hyper | ptyxis | x-terminal-emul)
      terminal="$name"; tpid="$p"; break ;;
    tmux* | screen | SCREEN | sshd | mosh-server) break ;;
    code | code-insiders | codium | cursor | idea | pycharm | phpstorm | webstorm | clion | goland | java) in_editor=1; break ;;
  esac
  case "$par" in '' | *[!0-9]*) break ;; esac
  p="$par"
  i=$((i + 1))
done

# ---- nerd_font
nerd_font=unknown
if have fc-list; then
  fl="$(fc-list : family 2>/dev/null)"
  if printf '%s\n' "$fl" | grep -qi 'nerd font' ||
     printf '%s\n' "$fl" | grep -qE '(^|[[:space:],])[A-Za-z0-9]+ NF[MP]?([[:space:],]|$)'; then
    nerd_font=yes
  else
    nerd_font=no
  fi
elif [ "$os" = macos ]; then
  seen=""
  for d in "${HOME:+$HOME/Library/Fonts}" /Library/Fonts; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    seen=1
    for f in "$d"/*Nerd* "$d"/*NF-*; do
      [ -e "$f" ] && nerd_font=yes
    done
  done
  [ "$nerd_font" = yes ] || { [ -n "$seen" ] && nerd_font=no; }
fi

# ---- notifier
notifier=none
if have notify-send; then notifier=notify-send
elif [ "$os" = macos ]; then
  if have terminal-notifier; then notifier=terminal-notifier
  elif have osascript; then notifier=osascript
  fi
fi

# ---- proposals
fcmd=""; fwhy=""
if [ "$os" = macos ]; then
  fwhy="notify.sh finds the window through /proc and xdotool, neither exists on macOS, so no click-to-focus."
elif [ "$session" = wayland ]; then
  fwhy="notify.sh finds the window with xdotool (X11 window ids) and Wayland windows have none, so no click-to-focus."
elif [ -n "$in_editor" ]; then
  fwhy="running inside an editor's integrated terminal; notify.sh would match the terminal that launched the editor and focus that window instead, so no click-to-focus."
elif [ "$session" = x11 ] && [ "$os" != linux ] && [ "$os" != unknown ]; then
  fwhy="notify.sh finds the terminal through /proc, which only Linux has."
elif [ "$session" = x11 ] && [ "$notifier" = none ]; then
  fwhy="notify-send is not installed and notify.sh's click action only exists on notify-send notifications."
elif [ "$session" = x11 ]; then
  nwin=""
  if have xdotool && [ -n "$tpid" ]; then
    nwin="$(xdotool search --pid "$tpid" 2>/dev/null | grep -c .)"
  fi
  if ! have xdotool; then
    fwhy="X11 session but xdotool is not installed; notify.sh needs it to find the window; install xdotool and re-run for a proposal."
  elif [ "${nwin:-1}" = 0 ]; then
    fwhy="no X11 window found for the terminal process (pid $tpid), so notify.sh would find nothing to focus."
  elif [ "${nwin:-1}" -gt 1 ] 2>/dev/null; then
    fwhy="this terminal process owns $nwin X11 windows right now and notify.sh skips the click when one process has more than one window (single-process terminals such as gnome-terminal or konsole hit this)."
  elif [ "$desktop" = i3 ]; then
    fcmd='i3-msg "[id=%s] focus"'
    fwhy="i3 focus by window id; this is also the built-in default."
  else
    fcmd='xdotool windowactivate %s'
    fwhy="activates the window through the window manager (EWMH, works on most X11 desktops) on $desktop, using xdotool which the window lookup already needs; if the terminal serves several windows from one process notify.sh skips the click action."
  fi
else
  fwhy="no graphical session detected (no DISPLAY or WAYLAND_DISPLAY)."
fi

tcmd=""; twhy=""
if [ -z "$fcmd" ]; then
  twhy="only used for click-to-focus, which has no proposal here."
elif [ "$terminal" != unknown ]; then
  tcmd="$terminal"
  twhy="the terminal this ran in, matched against the process name."
  [ "$terminal" = alacritty ] && twhy="$twhy Same as the default."
else
  twhy="terminal not identified (tmux, screen, ssh, or a terminal not on the known list); set it to your terminal's process name as shown in /proc/<pid>/comm."
fi

gcmd=""
case "$nerd_font" in
  yes) gcmd=nerd; gwhy="a Nerd Font is installed; glyphs only render if the terminal uses that font, otherwise they show as empty boxes." ;;
  no) gwhy="no Nerd Font found; the plain default is right." ;;
  *) gwhy="could not check for a Nerd Font (fc-list not found)." ;;
esac

# ---- output
printf '%s\n' "os=$os" "desktop=$desktop" "session=$session" "terminal=$terminal" \
  "nerd_font=$nerd_font" "notifier=$notifier"
[ -n "$fcmd" ] && printf '%s\n' "propose.AGENT_TIERS_NOTIFY_FOCUS_CMD=$fcmd"
printf '%s\n' "reason.AGENT_TIERS_NOTIFY_FOCUS_CMD=$fwhy"
[ -n "$tcmd" ] && printf '%s\n' "propose.AGENT_TIERS_NOTIFY_TERMINAL=$tcmd"
printf '%s\n' "reason.AGENT_TIERS_NOTIFY_TERMINAL=$twhy"
[ -n "$gcmd" ] && printf '%s\n' "propose.AGENT_TIERS_BADGE_GLYPHS=$gcmd"
printf '%s\n' "reason.AGENT_TIERS_BADGE_GLYPHS=$gwhy"
exit 0

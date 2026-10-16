#!/usr/bin/env sh
# kit-scope: shared
# Self-check for detect-env.sh: desktop/session/terminal/nerd-font/notifier detection and the three
# proposals across GNOME, KDE, i3, sway, Hyprland, macOS, a bare host, X11 without xdotool, a terminal
# process owning zero or two windows, no notify-send, an editor-hosted terminal, a non-Linux X11 host,
# a tmux ancestor, font-name variants, a missing uname, control-byte sanitisation, read-only
# behaviour, and the output shape. Deterministic: every case runs under `env -i` with a PATH holding only symlinks
# to the few real tools the script uses plus per-case stubs (uname, fc-list, ps, xdotool, ...), and
# a fake proc tree, so the real desktop, /proc and installed tools never matter.
# dash portability: no $'...', arrays, [[, process substitution, \x printf escapes.
set -u
SCRIPT="$(cd "$(dirname "$0")" && pwd)/detect-env.sh"
T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
fail() { printf 'FAIL: %s\n' "$1"; rm -rf "$T"; exit 1; }
trap 'rm -rf "$T"' EXIT
ENV="$(command -v env)"; SH="$(command -v sh)"

# Real tools detect-env.sh invokes (everything else, e.g. uname/ps/fc-list, is a stub or absent).
mkdir -p "$T/base"
for t in head tr sed grep basename; do
  p="$(command -v "$t")" || fail "need $t on the host"
  ln -s "$p" "$T/base/$t"
done

# mkc <case>: fresh case dirs
mkc() { mkdir -p "$T/$1/bin" "$T/$1/home" "$T/$1/proc" "$T/$1/cwd"; }
# stub <case> <name> <body>
stub() { printf '#!/bin/sh\n%s\n' "$3" > "$T/$1/bin/$2"; chmod +x "$T/$1/bin/$2"; }
# proc <case> <pid> <comm> <ppid>
proc() {
  mkdir -p "$T/$1/proc/$2"
  printf '%s\n' "$3" > "$T/$1/proc/$2/comm"
  printf 'Name:\t%s\nPPid:\t%s\n' "$3" "$4" > "$T/$1/proc/$2/status"
}
# run <case> [VAR=val ...]: output in $T/<case>/out; checks exit 0 and the line shape.
run() {
  c="$1"; shift
  ( cd "$T/$c/cwd" && "$ENV" -i PATH="$T/$c/bin:$T/base" HOME="$T/$c/home" \
      DETECT_ENV_PROC="$T/$c/proc" DETECT_ENV_START_PID=500 "$@" "$SH" "$SCRIPT" ) > "$T/$c/out" 2>"$T/$c/err"
  [ $? -eq 0 ] || fail "$c: nonzero exit"
  [ ! -s "$T/$c/err" ] || fail "$c: unexpected stderr"
  bad="$(grep -vE '^(os|desktop|session|terminal|nerd_font|notifier)=|^(propose|reason)\.AGENT_TIERS_(NOTIFY_FOCUS_CMD|NOTIFY_TERMINAL|BADGE_GLYPHS)=' "$T/$c/out")"
  [ -z "$bad" ] || fail "$c: malformed line: $bad"
  for k in os desktop session terminal nerd_font notifier; do
    [ "$(grep -c "^$k=" "$T/$c/out")" -eq 1 ] || fail "$c: key $k not exactly once"
  done
  for k in NOTIFY_FOCUS_CMD NOTIFY_TERMINAL BADGE_GLYPHS; do
    [ "$(grep -c "^reason\.AGENT_TIERS_$k=" "$T/$c/out")" -eq 1 ] || fail "$c: reason $k not exactly once"
  done
}
has() { grep -qxF -- "$2" "$T/$1/out" || fail "$1: missing line: $2"; }
nopre() { ! grep -q "^$2" "$T/$1/out" || fail "$1: unexpected line starting $2"; }
FOC=propose.AGENT_TIERS_NOTIFY_FOCUS_CMD
TRM=propose.AGENT_TIERS_NOTIFY_TERMINAL
BDG=propose.AGENT_TIERS_BADGE_GLYPHS

linux() { mkc "$1"; stub "$1" uname 'echo Linux'; }
# xd <case> [ids]: xdotool stub; `search --pid N` prints the ids (default one id, "" = none)
xd() { stub "$1" xdotool "[ \"\$1\" = search ] && printf '%s' '${2-12345}' | tr ' ' '\\n' | grep .; exit 0"; stub "$1" notify-send 'exit 0'; }
chain() { proc "$1" 500 bash 400; proc "$1" 400 "$2" 1; }
nerdfc() { stub "$1" fc-list "printf 'JetBrainsMono Nerd Font\nDejaVu Sans\n'"; }

# 1 GNOME/X11
linux gx; xd gx; stub gx notify-send 'exit 0'; nerdfc gx; chain gx gnome-terminal-
run gx XDG_CURRENT_DESKTOP=ubuntu:GNOME XDG_SESSION_TYPE=x11 DISPLAY=:0
for l in os=linux desktop=gnome session=x11 terminal=gnome-terminal- nerd_font=yes notifier=notify-send \
  "$FOC=xdotool windowactivate %s" "$TRM=gnome-terminal-" "$BDG=nerd"; do has gx "$l"; done

# 2 GNOME/Wayland
linux gw; xd gw; chain gw gnome-terminal-
run gw XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wayland-0
has gw session=wayland; nopre gw "$FOC"; nopre gw "$TRM"
grep -q '^reason.AGENT_TIERS_NOTIFY_FOCUS_CMD=.*Wayland' "$T/gw/out" || fail "gw: reason should mention Wayland"

# 3 KDE
linux kx; xd kx; chain kx konsole
run kx XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=x11 DISPLAY=:0
has kx desktop=kde; has kx terminal=konsole; has kx "$FOC=xdotool windowactivate %s"; has kx "$TRM=konsole"
linux kw; xd kw; chain kw konsole
run kw XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wayland-0
has kw desktop=kde; nopre kw "$FOC"

# 4 i3 (startx style: session type tty while running X11)
linux i3; xd i3; stub i3 i3-msg 'exit 0'; chain i3 alacritty
run i3 I3SOCK=/run/i3 XDG_SESSION_TYPE=tty DISPLAY=:0
has i3 desktop=i3; has i3 session=x11; has i3 "$FOC=i3-msg \"[id=%s] focus\""; has i3 "$TRM=alacritty"

# 5 sway (also sets I3SOCK)
linux sw; xd sw; chain sw foot
run sw SWAYSOCK=/run/sway I3SOCK=/run/sway XDG_SESSION_TYPE=wayland
has sw desktop=sway; has sw session=wayland; has sw terminal=foot; nopre sw "$FOC"

# 6 Hyprland
linux hl; xd hl; chain hl kitty
run hl HYPRLAND_INSTANCE_SIGNATURE=abc XDG_CURRENT_DESKTOP=Hyprland WAYLAND_DISPLAY=wayland-1
has hl desktop=hyprland; has hl session=wayland; nopre hl "$FOC"

# 7 macOS: ps-based walk, font dir fallback, osascript
mkc mac; stub mac uname 'echo Darwin'; stub mac osascript 'exit 0'
stub mac ps 'case "$2 $4" in
"comm= 500") echo "-zsh" ;;
"ppid= 500") echo "  400" ;;
"comm= 400") echo "/Applications/iTerm.app/Contents/MacOS/iTerm2" ;;
"ppid= 400") echo "    1" ;;
esac'
mkdir -p "$T/mac/home/Library/Fonts"; : > "$T/mac/home/Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf"
run mac DETECT_ENV_PROC="$T/mac/nonexistent"
for l in os=macos desktop=macos session=macos terminal=iTerm2 nerd_font=yes notifier=osascript "$BDG=nerd"; do has mac "$l"; done
nopre mac "$FOC"; nopre mac "$TRM"

# 8 bare host
linux bare
run bare
for l in desktop=unknown session=unknown terminal=unknown nerd_font=unknown notifier=none; do has bare "$l"; done
nopre bare propose.

# 9 X11 without xdotool
linux nx; stub nx notify-send 'exit 0'; chain nx alacritty
run nx XDG_SESSION_TYPE=x11 DISPLAY=:0
nopre nx "$FOC"; grep -q '^reason.AGENT_TIERS_NOTIFY_FOCUS_CMD=.*xdotool' "$T/nx/out" || fail "nx: reason should mention xdotool"

# 9b window count: two ids and zero ids both mean no proposal; no notify-send means no proposal
linux w2; xd w2 "111 222"; chain w2 alacritty
run w2 XDG_SESSION_TYPE=x11 DISPLAY=:0
nopre w2 "$FOC"; grep -q '^reason.AGENT_TIERS_NOTIFY_FOCUS_CMD=.*windows' "$T/w2/out" || fail "w2: reason should mention windows"
linux w0; xd w0 ""; chain w0 alacritty
run w0 XDG_SESSION_TYPE=x11 DISPLAY=:0
nopre w0 "$FOC"; nopre w0 "$TRM"
linux ns; xd ns; rm "$T/ns/bin/notify-send"; chain ns alacritty
run ns XDG_SESSION_TYPE=x11 DISPLAY=:0
has ns notifier=none; nopre ns "$FOC"; grep -q '^reason.AGENT_TIERS_NOTIFY_FOCUS_CMD=.*notify-send' "$T/ns/out" || fail "ns: reason should mention notify-send"

# 9c editor-hosted terminal: bash -> code -> alacritty must not resolve to alacritty
linux ed; xd ed; proc ed 500 bash 450; proc ed 450 code 400; proc ed 400 alacritty 1
run ed XDG_SESSION_TYPE=x11 DISPLAY=:0
has ed terminal=unknown; nopre ed "$FOC"; nopre ed "$TRM"
grep -q '^reason.AGENT_TIERS_NOTIFY_FOCUS_CMD=.*editor' "$T/ed/out" || fail "ed: reason should mention the editor"

# 9d non-Linux X11 (no /proc for notify.sh): no focus proposal; uname missing is not treated as non-Linux
mkc fb; stub fb uname 'echo FreeBSD'; xd fb; chain fb alacritty
run fb XDG_SESSION_TYPE=x11 DISPLAY=:0
has fb os=freebsd; nopre fb "$FOC"; grep -q '^reason.AGENT_TIERS_NOTIFY_FOCUS_CMD=.*only Linux' "$T/fb/out" || fail "fb: reason should say /proc is Linux-only"
mkc un; xd un; chain un alacritty
run un XDG_SESSION_TYPE=x11 DISPLAY=:0
has un os=unknown; has un "$FOC=xdotool windowactivate %s"

# 10 tmux ancestor: terminal not identifiable, focus still proposed
linux tm; xd tm; proc tm 500 bash 450; proc tm 450 "tmux: server" 400; proc tm 400 alacritty 1
run tm XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=x11 DISPLAY=:0
has tm terminal=unknown; has tm "$FOC=xdotool windowactivate %s"; nopre tm "$TRM"

# 11 fonts
linux fn; stub fn fc-list "printf 'DejaVu Sans\nLiberation Mono\n'"
run fn; has fn nerd_font=no; nopre fn "$BDG"
linux fh; stub fh fc-list "printf 'DejaVu Sans\nHack NFM\n'"
run fh; has fh nerd_font=yes; has fh "$BDG=nerd"

# 12 uname absent
mkc nu
run nu; has nu os=unknown

# 13 sanitisation: a newline in env must not forge a second os= line
linux sn
run sn "XDG_CURRENT_DESKTOP=$(printf 'foo\nos=evil')"
[ "$(grep -c '^os=' "$T/sn/out")" -eq 1 ] || fail "sn: forged os line"
! grep -q evil "$T/sn/out" || fail "sn: injected text leaked"

# 14 read-only: cwd and HOME stay empty
linux ro; xd ro; chain ro alacritty; nerdfc ro
run ro XDG_SESSION_TYPE=x11 DISPLAY=:0
[ -z "$(ls -A "$T/ro/cwd")$(ls -A "$T/ro/home")" ] || fail "ro: script wrote into cwd or HOME"

# argument handling
"$SH" "$SCRIPT" extra >/dev/null 2>&1; [ $? -eq 2 ] || fail "an argument should exit 2"

echo "PASS detect-env.sh"

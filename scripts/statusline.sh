#!/bin/sh
# kit-scope: shared
# Main status row for Claude Code's `statusLine` command: directory, model, git branch with
# dirty and ahead/behind markers (cached 5s per session), context bar, session duration,
# lines changed, short session id, transcript idle seconds. Segments are spread across
# $COLUMNS. Input: the statusLine JSON payload on stdin. Output: one line on stdout.
# Needs jq (absent: prints nothing, exits 0). Always exits 0, even on a malformed payload.
# Env knobs: COLUMNS (width, default 80); TMPDIR (git cache location, default /tmp);
# AGENT_TIERS_BADGE_GLYPHS=nerd (use Nerd Font icons; otherwise no icons, pure ASCII).
# Needs statusline-model.jq next to this script.
# Git cache: one file git-<session id> in a per-user dir $TMPDIR/agent-tiers-statusline-<uid>
# (mode 700; used only if it is a real directory owned by the current user, else git runs on
# every render). No session id: no cache. Cap: each render deletes cache files in that dir
# older than a day (find -mtime +0), so it cannot grow without bound.
# Payload strings (dir, model, branch) have control bytes stripped so they cannot inject
# terminal escapes; only this script's own SGR colour codes reach the terminal.
command -v jq >/dev/null 2>&1 || exit 0
input="$([ -t 0 ] || cat 2>/dev/null || true)"
J() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }
cdir=$(J '.workspace.current_dir // empty')
[ -z "$cdir" ] && cdir="$PWD"
# payload strings can carry terminal escapes (OSC/CSI): drop control bytes before rendering
nocc() { jq -Rr 'gsub("[\u0000-\u001f\u007f-\u009f]"; "")' 2>/dev/null; }
dir=$(basename "$cdir" | nocc)
model=$(J '.model.display_name // empty' | nocc)
session_id=$(J '.session_id // empty')
# only [A-Za-z0-9_-] survives, so the id can never steer the cache path elsewhere
sid=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9_-')

# width budget: scale the two unbounded fields off $COLUMNS; 20/24 is the floor so a
# long name still cannot wrap the whole line.
cols=${COLUMNS:-80}
case $cols in ''|*[!0-9]*) cols=80 ;; esac
DIR_MAX=$((cols / 4)); [ "$DIR_MAX" -lt 20 ] && DIR_MAX=20
BRANCH_MAX=$((cols / 3)); [ "$BRANCH_MAX" -lt 24 ] && BRANCH_MAX=24
trunc() {
  s="$1"; n="$2"
  if [ "${#s}" -gt "$n" ]; then
    printf '%s...' "$(printf '%s' "$s" | cut -c1-$((n - 3)))"
  else
    printf '%s' "$s"
  fi
}
dir=$(trunc "$dir" "$DIR_MAX")

# colors (escape bytes built at runtime)
ESC=$(printf '\033')
DIM="${ESC}[2m"; BLUE="${ESC}[34m"; MAGENTA="${ESC}[35m"
YELLOW="${ESC}[33m"; CYAN="${ESC}[36m"; GREEN="${ESC}[32m"
RED="${ESC}[31m"; RST="${ESC}[0m"
# NO_COLOR (no-color.org): set and non-empty means no colour escapes at all; text and layout stay.
if [ -n "${NO_COLOR:-}" ]; then
  DIM=""; BLUE=""; MAGENTA=""; YELLOW=""; CYAN=""; GREEN=""; RED=""; RST=""
fi

# Nerd Font icons (folder, branch, clock, chip, gauge, pencil, hash), each followed by a
# space, only when the user opted in; empty otherwise.
IF=""; IB=""; IC=""; IM=""; IG=""; IE=""; IH=""
if [ "${AGENT_TIERS_BADGE_GLYPHS:-}" = nerd ]; then
  IF=$(printf '\357\201\273 '); IB=$(printf '\356\234\245 '); IC=$(printf '\357\200\227 ')
  IM=$(printf '\357\213\233 '); IG=$(printf '\357\203\244 '); IE=$(printf '\357\201\200')
  IH=$(printf '\357\212\222 ')
fi

# k-format: round to nearest k
kfmt() { awk -v n="$1" 'BEGIN{printf "%dk", (n+500)/1000}'; }
# file mtime in epoch seconds (GNU stat, then BSD stat)
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# --- git --- (pinned to $cdir; cached so git runs at most once per CACHE_MAX_AGE seconds)
GITC="$MAGENTA"
GIT_CACHE=""
GIT_CACHE_MAX_AGE=5
if [ -n "$sid" ]; then
  gd="${TMPDIR:-/tmp}/agent-tiers-statusline-$(id -u)"
  { [ -e "$gd" ] || [ -L "$gd" ]; } || mkdir -m 700 "$gd" 2>/dev/null
  if [ -d "$gd" ] && [ ! -L "$gd" ] && [ -O "$gd" ]; then
    GIT_CACHE="$gd/git-$sid"
    find "$gd" -type f -name 'git-*' -mtime +0 -exec rm -f {} + 2>/dev/null
  fi
fi
git_cache_stale() {
  [ -n "$GIT_CACHE" ] && [ -f "$GIT_CACHE" ] || return 0
  cm=$(mtime_of "$GIT_CACHE"); [ -n "$cm" ] || cm=0
  [ $(($(date +%s) - cm)) -gt "$GIT_CACHE_MAX_AGE" ]
}
if git_cache_stale; then
  b=$(git -C "$cdir" --no-optional-locks branch --show-current 2>/dev/null | nocc)
  d=0; a=0; be=0
  if [ -n "$b" ]; then
    # -uno: tracked changes only; instant even on a huge untracked tree
    [ -n "$(git -C "$cdir" --no-optional-locks status --porcelain -uno 2>/dev/null)" ] && d=1
    ab=$(git -C "$cdir" --no-optional-locks rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
    be=$(echo "$ab" | awk '{print $1+0}')
    a=$(echo "$ab" | awk '{print $2+0}')
  fi
  [ -n "$GIT_CACHE" ] && printf '%s|%s|%s|%s\n' "$b" "$d" "$a" "$be" > "$GIT_CACHE" 2>/dev/null
  branch=$b; dirty_flag=$d; ahead=$a; behind=$be
else
  branch=""; dirty_flag=0; ahead=0; behind=0
  IFS='|' read -r branch dirty_flag ahead behind < "$GIT_CACHE"
fi
branch=$(trunc "$branch" "$BRANCH_MAX")
gitseg=""
if [ -n "$branch" ]; then
  dirty=""
  [ "$dirty_flag" = "1" ] && dirty="${YELLOW}*${GITC}"
  ahead_behind=""
  { [ "$ahead" != "0" ] || [ "$behind" != "0" ]; } && ahead_behind=" ${CYAN}^${ahead} v${behind}${GITC}"
  gitseg="${GITC}${IB}${branch}${dirty}${ahead_behind}${RST}"
fi

# --- context ---
used=$(J '.context_window.used_percentage // empty')
total_in=$(J '.context_window.total_input_tokens // empty')
win=$(J '.context_window.context_window_size // empty')
cread=$(J '.context_window.current_usage.cache_read_input_tokens // empty')
ctxseg=""
if [ -n "$used" ] && [ -n "$total_in" ] && [ -n "$win" ]; then
  pct=$(printf '%.0f' "$used" 2>/dev/null) || pct=0
  if [ "$pct" -ge 80 ]; then pcolor="$RED"
  elif [ "$pct" -ge 50 ]; then pcolor="$YELLOW"
  else pcolor="$GREEN"
  fi
  detail=$(printf '%s/%s' "$(kfmt "$total_in")" "$(kfmt "$win")")
  if [ -n "$cread" ]; then detail="$detail cache-read:$(kfmt "$cread")"
  else detail="$detail cache-read:?"; fi
  filled=$((pct / 10)); [ "$filled" -gt 10 ] && filled=10
  bar=$(awk -v f="$filled" 'BEGIN{for(i=0;i<f;i++)printf "#"}')
  gap=$(awk -v f="$filled" 'BEGIN{for(i=f;i<10;i++)printf "-"}')
  ctxseg="${DIM}${IG}[${RST}${pcolor}${bar}${RST}${DIM}${gap}]${RST} ${pcolor}${pct}%${RST} ${DIM}${detail}${RST}"
fi

# --- session (duration + lines changed) ---
dur_ms=$(J '.cost.total_duration_ms // empty | floor')
durseg=""
case $dur_ms in ''|*[!0-9]*) ;; *)
  mins=$((dur_ms / 60000))
  if [ "$mins" -ge 60 ]; then
    durtext=$(printf '%dh%dm' $((mins / 60)) $((mins % 60)))
  else
    durtext=$(printf '%dm' "$mins")
  fi
  # green under 1h, yellow to 3h, red beyond
  if [ "$mins" -ge 180 ]; then dcolor="$RED"
  elif [ "$mins" -ge 60 ]; then dcolor="$YELLOW"
  else dcolor="$GREEN"
  fi
  durseg="${dcolor}${IC}${durtext}${RST}"
;; esac

added=$(J '.cost.total_lines_added // 0')
removed=$(J '.cost.total_lines_removed // 0')
[ -n "$added" ] || added=0
[ -n "$removed" ] || removed=0
linesseg=""
if [ "$added" != "0" ] || [ "$removed" != "0" ]; then
  [ -n "$IE" ] && IE="${IE} "
  linesseg="${DIM}${IE}${RST}${GREEN}+${added}${RST}/${RED}-${removed}${RST}"
fi

# --- session id + transcript idle time (idle time is not proof of cache retention) ---
transcript=$(J '.transcript_path // empty')
sidseg=""
[ -n "$session_id" ] && sidseg="${DIM}${IH}${sid%%-*}${RST}"
idleseg=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  mt=$(mtime_of "$transcript")
  if [ -n "$mt" ]; then
    idleseg="${DIM}${IC}idle:$(($(date +%s) - mt))s${RST}"
  fi
fi

# shared display-colour mapping for the main and sub-agent rows
here=$(dirname "$0")
model_color=$(printf '%s' "$model" | jq -L "$here" -Rr 'include "statusline-model"; statusModelColor' 2>/dev/null)
model=$(printf '%s' "$model" | jq -L "$here" -Rr 'include "statusline-model"; statusModelDisplay' 2>/dev/null)
[ -n "$model_color" ] || model_color=2
MCOLOR="${ESC}[${model_color}m"
[ -n "${NO_COLOR:-}" ] && MCOLOR=""

dirseg="${BLUE}${IF}${dir}${RST}"
modelseg=""
[ -n "$model" ] && modelseg="${MCOLOR}${IM}${model}${RST}"

# spread the segments across the terminal width; $reserve leaves room for the harness's
# own right-aligned footer content.
US=$(printf '\037')
joined=""
for seg in "$dirseg" "$modelseg" "$gitseg" "$ctxseg" "$durseg" "$linesseg" "$sidseg" "$idleseg"; do
  [ -n "$seg" ] || continue
  if [ -z "$joined" ]; then joined="$seg"; else joined="${joined}${US}${seg}"; fi
done
OLDIFS=$IFS
IFS=$US
set -- $joined
IFS=$OLDIFS

total_vis=0
for seg in "$@"; do
  plain=$(printf '%s' "$seg" | sed "s/${ESC}\[[0-9;]*m//g")
  total_vis=$((total_vis + ${#plain}))
done
gaps=$(($# - 1))
[ "$gaps" -lt 0 ] && gaps=0

reserve=10
avail=$((cols - reserve))
[ "$avail" -lt "$((total_vis + gaps))" ] && avail=$((total_vis + gaps))
extra=$((avail - total_vis - gaps))
[ "$extra" -lt 0 ] && extra=0

gap_base=1; gap_rem=0
if [ "$gaps" -gt 0 ]; then
  gap_base=$((1 + extra / gaps))
  gap_rem=$((extra % gaps))
fi

i=0
line=""
while [ "$#" -gt 0 ]; do
  i=$((i + 1))
  line="${line}$1"
  shift
  if [ "$#" -gt 0 ]; then
    thisgap=$gap_base
    [ "$i" -le "$gap_rem" ] && thisgap=$((thisgap + 1))
    line="${line}$(awk -v n="$thisgap" 'BEGIN{for(j=0;j<n;j++)printf " "}')"
  fi
done
printf '%s\n' "$line"
exit 0

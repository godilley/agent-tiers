#!/bin/sh
# kit-scope: shared
# Per-sub-agent rows for Claude Code's `subagentStatusLine` command:
# <status> [model/effort] <ctx badge> > description -> live label, one JSON line per task.
# Input: the subagentStatusLine JSON payload on stdin ({columns, tasks:[...]}).
# Output: one {"id":..., "content":...} JSON object per task on stdout.
# Model, effort, description and label are fixed-width columns shared by every row of a
# batch, so the brackets and the arrow line up. Needs jq (absent: prints nothing, exits 0)
# and statusline-model.jq next to this script. Always exits 0, even on a malformed payload.
# Env knob: AGENT_TIERS_BADGE_GLYPHS=nerd uses Nerd Font icons; otherwise pure ASCII glyphs
# (completed +, failed x, running ~, other *, separator ->, task marker >).
command -v jq >/dev/null 2>&1 || exit 0
# escape bytes and glyphs are built at runtime, never pasted into the jq program text
ESC=$(printf '\033')
RST="${ESC}[0m"; DIM="${ESC}[2m"
GREEN="${ESC}[32m"; YELLOW="${ESC}[33m"
CYAN="${ESC}[36m"; RED="${ESC}[31m"; MAGENTA="${ESC}[35m"
BLUE="${ESC}[1;38;5;208m"        # bold orange: blue reads muddy on dark themes
DESC_COLOR="${ESC}[38;5;252m"    # soft light gray
BOLD_CYAN="${ESC}[1;36m"         # brighter, for the live label
# NO_COLOR (no-color.org): set and non-empty means no colour escapes at all; text and layout stay.
NOCOL=""
if [ -n "${NO_COLOR:-}" ]; then
  NOCOL=1
  RST=""; DIM=""; GREEN=""; YELLOW=""; CYAN=""; RED=""; MAGENTA=""; BLUE=""; DESC_COLOR=""; BOLD_CYAN=""
fi
ICON_OK="+"; ICON_ERR="x"; ICON_RUN="~"; ARROW="->"; TASK_ICON=">"
if [ "${AGENT_TIERS_BADGE_GLYPHS:-}" = nerd ]; then
  ICON_OK=$(printf '\357\200\214'); ICON_ERR=$(printf '\357\200\215')
  ICON_RUN=$(printf '\357\200\223'); ARROW=$(printf '\342\206\222')
  TASK_ICON=$(printf '\357\201\224')
fi

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
printf '%s' "$INPUT" | jq -L "$(dirname "$0")" -r \
  --arg RST "$RST" --arg DIM "$DIM" \
  --arg GREEN "$GREEN" --arg YELLOW "$YELLOW" --arg CYAN "$CYAN" \
  --arg RED "$RED" --arg MAGENTA "$MAGENTA" --arg BLUE "$BLUE" --arg ARROW "$ARROW" \
  --arg DESC_COLOR "$DESC_COLOR" --arg NOCOL "$NOCOL" \
  --arg TASK_ICON "$TASK_ICON" --arg BOLD_CYAN "$BOLD_CYAN" \
  --arg ICON_OK "$ICON_OK" --arg ICON_ERR "$ICON_ERR" --arg ICON_RUN "$ICON_RUN" \
  '
  include "statusline-model";
  # payload strings must not carry terminal escapes (OSC/CSI): drop all C0/C1 control chars
  def clean: if . == null then . else tostring | gsub("[\u0000-\u001f\u007f-\u009f]"; "") end;
  def trunc(s; n):
    if n <= 0 then ""
    elif (s | length) > n then (if n > 3 then s[0:n-3] + "..." else s[0:n] end)
    else s end;
  def padc(s; n):
    (s |
      if length >= n then .[0:n]
      else
        ((n - length) as $total | ($total / 2 | floor) as $left | ($total - $left) as $right |
         (" " * $left) + . + (" " * $right))
      end);
  def padr(s; n):
    (s | if length >= n then .[0:n] else . + (" " * (n - length)) end);

  def statusGlyph:
    if . == "completed" then ($GREEN + $ICON_OK + $RST)
    elif . == "failed" or . == "error" then ($RED + $ICON_ERR + $RST)
    elif . == "running" then ($CYAN + $ICON_RUN + $RST)
    else ($DIM + "*" + $RST) end;

  def effortColor:
    if type == "number" then $DIM
    elif . == "low" then $GREEN
    elif . == "medium" then $CYAN
    elif . == "high" then $YELLOW
    elif . == "xhigh" or . == "max" then $RED
    else $DIM end;

  def modelColor: if $NOCOL == "1" then "" else statusModelColor | "\u001b[" + . + "m" end;
  def ucfirst: (.[0:1] | ascii_upcase) + .[1:];
  # strip the "claude-" prefix and any trailing variant annotation like "[1m]" -
  # that annotation is a real thing (the 1M-context-window variant) but belongs
  # in the dedicated $ctxBadge below, driven by contextWindowSize, not parsed
  # out of the id string here.
  def normModel: (. // "-" | sub("^claude-"; "") | sub("\\[.*\\]$"; ""));
  # single definition shared by the width calc AND the render - a display-only
  # tweak here can never again desync from the width math (see the $modelRaw bug).
  def modelDisplay: normModel | statusModelDisplay | ucfirst;

  16 as $model_max | 8 as $effort_max | 2 as $badge_w | 45 as $desc_max |
  " [" as $open | "/" as $SEP | "]" as $close | " " as $GAP |
  ($DIM + $TASK_ICON + $RST + " ") as $task_mark | 2 as $task_mark_w |
  (" " + $BLUE + $ARROW + $RST + " ") as $sep2 | (($ARROW | length) + 2) as $wrapLen |

  (.columns // 80) as $cols |
  ((.tasks // []) | map((.description, .label, .model, .effort, .status) |= clean)) as $tasks |
  (([$tasks[] | (.model | modelDisplay | length)] | max // 0) as $m | [$m + 2, $model_max] | min) as $modelW |
  (([$tasks[] | (.effort // "-" | tostring | length)] | max // 0) as $e | [$e + 2, $effort_max] | min) as $effortW |
  (1 + ($open|length) + $modelW + ($SEP|length) + $effortW + ($close|length)
     + ($GAP|length) + $badge_w + ($GAP|length) + $task_mark_w) as $prefixVisibleLen |
  ([$cols - $prefixVisibleLen, 0] | max) as $avail |
  # desc/label are fixed columns too (same 40/60 split for every row in the batch) -
  # so the "(" always lands in the same screen column, matching the model/effort columns.
  ([$tasks[] | (.description // "" | length)] | max // 0) as $descNatural |
  ([$descNatural, ($avail * 0.4 | floor), $desc_max] | min) as $descW |
  ([$avail - $descW - $wrapLen, 0] | max) as $labelW |
  $tasks[] |
  (.model | normModel) as $modelKey |
  (.model | modelDisplay) as $modelName |
  (.effort // "-") as $effortRaw |
  (.description // "") as $desc |
  (.label // "") as $label |
  ((.contextWindowSize // 0) >= 1000000) as $extended |

  ((.status // "") | statusGlyph) as $icon |
  (trunc($modelName; $modelW - 2)) as $modelText |
  (padc($modelText; $modelW)) as $modelPadded |
  ($modelKey | modelColor) as $mc |
  ($mc + $modelPadded + $RST) as $modelCol |
  (trunc($effortRaw | tostring; $effortW - 2)) as $effortText |
  (padc($effortText; $effortW)) as $effortPadded |
  ($effortRaw | effortColor) as $ec |
  ($ec + $effortPadded + $RST) as $effortCol |

  (if $extended then $YELLOW + "1M" + $RST else (" " * $badge_w) end) as $ctxBadge |
  ($icon + $open + $modelCol + $SEP + $effortCol + $close + $GAP + $ctxBadge + $GAP + $task_mark) as $prefix |

  (if $label == "" or $label == $desc then
     $DESC_COLOR + trunc($desc; $avail) + $RST
   elif $desc == "" then
     trunc($label; $avail)
   else
     ($DESC_COLOR + padr(trunc($desc; $descW); $descW) + $RST) as $d |
     trunc($label; $labelW) as $l |
     (if $l == "" then $d else $d + $sep2 + $BOLD_CYAN + $l + $RST end)
   end) as $tail |
  (trunc($prefix + $tail; ($cols * 3))) as $content |
  {id: .id, content: $content} | tojson
  ' 2>/dev/null
exit 0

#!/usr/bin/env sh
# kit-scope: shared
# docs-nav.sh - print a markdown "tab bar" nav for the kit's docs, every cell padded to the same
# pixel width by transparent spacer images.
#
# Usage: docs-nav.sh [-w CELL_PX] [-s SPACER_SRC] [--] <current-label> <label>=<link> [<label>=<link> ...]
#   -w  target cell text width in px, positive integer (default 108: six tabs fit the repo home page README box; wrap the bar in <div align="center"> so it centres in the wider file view)
#   -s  spacer img src (default assets/spacer.svg, right from docs/*.md; README.md passes
#       -s docs/assets/spacer.svg)
#   Each pair splits on the FIRST '=' (links may contain '='). The link may be empty only for the
#   current label. Errors (message on stderr, exit 2, nothing on stdout): no args, unknown option,
#   bad -w, a pair with no '=', an empty label, a label containing '|', a non-current label with an
#   empty link, a label containing a newline, a current-label that matches no label. `--` ends the
#   options (a label may start with `-`). Labels with markdown metacharacters (`*`, `[`, `]`) and
#   links with spaces or `)` are passed through unchecked.
#
# Output, exactly 4 lines: the table row (current label bold and unlinked, others bold links, each
# cell wrapped in a left and right spacer <img>), the alignment row, an empty line, and <hr>.
#
# Why spacers: GitHub strips CSS but keeps img width/height, so a transparent image of a computed
# width is the only way to give table cells equal width.
#
# Widths: W = round(sum of per-character advance units * 16 / 1000); pad = CELL_PX - W, at least 2;
# left = floor(pad/2), right = pad - left. A label wider than CELL_PX-2 gets the 2px minimum and its
# cell is wider than the rest. Non-ASCII, byte-wise: UTF-8 continuation byte 0, 4-byte lead 1000,
# other lead byte 600. Kerning ignored.
#
# Calibration: advance widths are Noto Sans Bold at 16px (GitHub's markdown body size; Noto Sans is
# what GitHub's font stack resolves to on Linux), 1000 units per em. Checked against six widths
# measured in a rendered GitHub page: README 66, Why delegate 109, Work shapes 102, Choosing a level
# 129, After install 94, Glossary 68 px; the table reproduces them within 1px (Choosing a level
# computes 130). Limit: macOS (San Francisco) and Windows (Segoe UI) render a few px different;
# accepted, not a defect.
#
# Runs under POSIX sh and POSIX awk - no arrays, no `local`, no `[[ ]]`.
#
# Self-check: docs-nav.selfcheck.sh
set -u

die() { printf 'docs-nav: %s\n' "$1" >&2; exit 2; }

NLC='
'
CELL=108
SRC='assets/spacer.svg'
while [ $# -gt 0 ]; do
  case "$1" in
    -w) [ $# -ge 2 ] || die "-w needs a value"; CELL="$2"; shift 2 ;;
    -s) [ $# -ge 2 ] || die "-s needs a value"; SRC="$2"; shift 2 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
case "$CELL" in ''|*[!0-9]*|0*) die "bad -w (want a positive integer): $CELL" ;; esac
[ $# -ge 2 ] || die "usage: docs-nav.sh [-w PX] [-s SRC] <current-label> <label>=<link> ..."

CUR="$1"; shift
found=0
for p in "$@"; do
  case "$p" in *=*) ;; *) die "pair without '=': $p" ;; esac
  l="${p%%=*}"; k="${p#*=}"
  [ -n "$l" ] || die "empty label: $p"
  case "$l" in *'|'*) die "label contains '|': $l" ;; esac
  case "$l" in *"$NLC"*) die "label contains a newline" ;; esac
  case "$k" in *"$NLC"*) die "link contains a newline" ;; esac
  if [ "$l" = "$CUR" ]; then found=1
  else [ -n "$k" ] || die "empty link for non-current label: $l"; fi
done
[ "$found" -eq 1 ] || die "current label matches no label: $CUR"

# awk: one label per stdin line -> "left right" per line.
PADS="$(for p in "$@"; do printf '%s\n' "${p%%=*}"; done | LC_ALL=C awk -v cell="$CELL" '
BEGIN {
  n = split("260 282 479 646 572 902 750 266 339 339 542 572 285 320 281 415 " \
    "572 572 572 572 572 572 572 572 572 572 281 285 572 572 572 477 " \
    "898 692 665 642 732 560 549 724 765 389 331 664 559 943 813 791 " \
    "621 791 656 551 577 756 650 967 670 626 579 331 415 331 572 411 " \
    "365 599 632 516 632 597 387 632 650 299 298 620 298 975 650 625 " \
    "632 632 447 502 434 650 571 856 578 571 493 394 551 394 572", adv, " ")
  for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i
  for (i = 32; i <= 126; i++) w[sprintf("%c", i)] = adv[i - 31]
}
{
  s = 0
  for (i = 1; i <= length($0); i++) {
    c = substr($0, i, 1); o = ord[c] + 0
    if (o >= 32 && o <= 126) s += w[c]
    else if (o >= 240) s += 1000
    else if (o >= 192) s += 600
  }
  W = int(s * 16 / 1000 + 0.5)
  pad = cell - W; if (pad < 2) pad = 2
  l = int(pad / 2)
  print l, pad - l
}')"

row='|'; align='|'
# pair labels with pad lines positionally
i=0
for p in "$@"; do
  i=$((i + 1))
  l="${p%%=*}"; k="${p#*=}"
  pl="$(printf '%s\n' "$PADS" | sed -n "${i}p")"
  L="${pl% *}"; R="${pl#* }"
  if [ "$l" = "$CUR" ]; then cellt="**$l**"; else cellt="[**$l**]($k)"; fi
  row="$row <img src=\"$SRC\" width=\"$L\" height=\"1\">$cellt<img src=\"$SRC\" width=\"$R\" height=\"1\"> |"
  align="$align:-:|"
done
printf '%s\n%s\n\n<hr>\n' "$row" "$align"

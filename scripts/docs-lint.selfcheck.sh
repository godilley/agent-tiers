#!/usr/bin/env sh
# kit-scope: shared
# Self-check for docs-lint.sh. Runnable: `sh docs-lint.selfcheck.sh`.
# Fixtures live in a `mktemp -d`; nothing outside it is touched.
set -u
HERE="$(CDPATH= cd "$(dirname "$0")" && pwd)"
LINT="$HERE/docs-lint.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
NL='
'
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cd "$W" || exit 1

# has <name> <exact line>: OUT contains the full line
has()   { printf '%s\n' "$OUT" | grep -Fxq -- "$2" && ok "$1" || bad "$1 (missing: $2)"; }
# lacks <name> <fixed substring>: OUT does not contain it
lacks() { printf '%s\n' "$OUT" | grep -Fq -- "$2" && bad "$1 (unexpected: $2)" || ok "$1"; }
# eq <name> <want>: OUT is exactly want
eq()    { [ "$OUT" = "$2" ] && ok "$1" || bad "$1 (got: $OUT)"; }
run()   { OUT="$(sh "$LINT" "$@" 2>&1)"; RC=$?; }

# --- rule link ---------------------------------------------------------------------------------
mkdir sub
printf '# Other\n## Y\n' > other.md
printf '# Sub\n' > sub/s.md
{
  printf '# Title\n'                                           # 1
  printf '## Foo\n'                                           # 2
  printf '## Foo\n'                                           # 3
  printf '### \360\237\222\254 You stay\n'                    # 4
  printf '### Head <a href="#top"><img src="x.svg"></a>\n'   # 5
  printf '<a name="pinned"></a> <a name="top"></a>\n'         # 6
  printf '[g1](#title) [g2](#foo-1) [b1](#foo-2) [g3](#pinned) [g4](#-you-stay) [g5](#head-)\n'   # 7
  printf '[g6](other.md) [b2](missing.md) [g7](other.md#y) [b3](other.md#nope) [g8](sub/s.md)\n' # 8
  printf '<a href="#top">t</a> <a href="#nothere">x</a>\n'    # 9
  printf '[h](http://x.com/a.md) ![i](pic.png) ![j](missing.md) [m](mailto:a@b.c) [d](docs/)\n'  # 10
  printf '`[c](#incode)` and [k](#bad-after-code)\n'          # 11
  printf '```\n[f](#fenced)\n```\n'                           # 12-14
  printf '[badge](other.md#y) [![a](p.png)](other.md#q)\n'    # 15
} > a.md
run a.md
has   "link: same-file bad anchor (dup -2)"  'a.md:7: link: no anchor #foo-2 in a.md'
lacks "link: #title #foo-1 #pinned #-you-stay #head- resolve" 'a.md:7: link: no anchor #foo-1'
has   "link: missing file"                   'a.md:8: link: missing file missing.md'
has   "link: other.md#nope bad anchor"       'a.md:8: link: no anchor #nope in other.md'
has   "link: href to missing anchor"         'a.md:9: link: no anchor #nothere in a.md'
has   "link: bad link after code span"       'a.md:11: link: no anchor #bad-after-code in a.md'
has   "link: image-wrapped link checked"     'a.md:15: link: no anchor #q in other.md'
n="$(printf '%s\n' "$OUT" | grep -c ': link: ')"
[ "$n" = 6 ] && ok "link: exactly 6 findings (good, http, image, mailto, fenced, code skipped)" \
  || bad "link: want 6 link findings, got $n: $OUT"
printf '# Up\n[g](../other.md#y) [b](../other.md#zzz) [m](../gone.md) [s](./s.md#sub)\n' > sub/t.md
run sub/t.md
has "link: ../ resolves, bad anchor" 'sub/t.md:2: link: no anchor #zzz in other.md'
has "link: ../ missing file"         'sub/t.md:2: link: missing file gone.md'
lacks "link: ./s.md#sub good"        'no anchor #sub'
n="$(printf '%s\n' "$OUT" | grep -c ': link: ')"
[ "$n" = 2 ] && ok "link: subdir file has exactly 2 findings" || bad "link: subdir want 2, got $n: $OUT"
# heading before use and link before heading
printf '[late](#later)\n\n## Later\n' > late.md
run late.md; eq "link: anchor defined after the link resolves" "ok"
# setext heading id, closing hashes, link text in heading
printf 'Setext One\n==========\n\nSub Two\n=======\n\n## Closed ##\n\n## [Lnk](#setext-one) and `code`\n\n[a](#setext-one) [b](#sub-two) [c](#closed) [d](#lnk-and-code)\n' > h.md
run h.md; eq "link: setext, closing # and link/code heading ids" "ok"

# --- rule setext -------------------------------------------------------------------------------
{
  printf 'Text line\n---\n'                       # 1-2 flagged
  printf '\n---\n'                                # 3-4 ok
  printf '| a | b |\n---\n'                       # 5-6 ok
  printf -- '- item\n---\n'                       # 7-8 ok
  printf '```\ntext\n---\n```\n---\n'             # 9-13 fence ok, after fence ok
  printf 'Para\n---   \n'                         # 14-15 flagged
} > b.md
run b.md
has "setext: text + --- flagged (full line)" 'b.md:2: setext: --- under a text line makes it a heading; add a blank line above'
has "setext: trailing spaces still flagged"  'b.md:15: setext: --- under a text line makes it a heading; add a blank line above'
n="$(printf '%s\n' "$OUT" | grep -c ': setext: ')"
[ "$n" = 2 ] && ok "setext: blank, table, list, fence not flagged (2 total)" || bad "setext: want 2, got $n: $OUT"
printf -- '---\ntitle: x\n---\n\nbody\n' > fm.md
run fm.md; eq "setext: front matter not flagged" "ok"
printf '> quote\n---\n\n# H\n---\n\n***\n---\n\n1. one\n---\n' > b2.md
run b2.md; eq "setext: blockquote, ATX heading, rule, numbered list not flagged" "ok"

# --- rule summary-bold -------------------------------------------------------------------------
{
  printf '<summary>**x**</summary>\n'            # 1 flagged
  printf '<summary><b>x</b></summary>\n'         # 2
  printf '<summary class="k">\n'                 # 3
  printf 'plain **bold** here\n'                 # 4 flagged (multi-line)
  printf '</summary>\n'                          # 5
  printf 'after **not in summary**\n'            # 6
  printf '| <summary>**x**</summary> |\n'        # 7 table
  printf '```\n<summary>**x**</summary>\n```\n'  # 8-10 fence
  printf '`<summary>**x**</summary>`\n'          # 11 code span
  printf '<SUMMARY>**u**</SUMMARY>\n'            # 12 flagged
} > c.md
run c.md
D_SUM='summary-bold: markdown bold does not render inside <summary>; use <b>'
has "summary-bold: single line flagged (full line)" "c.md:1: $D_SUM"
has "summary-bold: multi-line flagged"              "c.md:4: $D_SUM"
has "summary-bold: case-insensitive tag"            "c.md:12: $D_SUM"
n="$(printf '%s\n' "$OUT" | grep -c ': summary-bold: ')"
[ "$n" = 3 ] && ok "summary-bold: <b>, after-close, table, fence, code not flagged (3 total)" || bad "summary-bold: want 3, got $n: $OUT"

# --- rule heading-icon -------------------------------------------------------------------------
{
  printf '### \360\237\222\254 No anchor\n'      # 1 flagged
  printf '\n<a name="x"></a>\n\n'                # 2-4
  printf '## \360\237\222\254 Pinned\n'          # 5 ok (anchor 2 lines above)
  printf '\n<a name="y"></a>\n\n\n'              # 6-9
  printf '## <img src="x.svg"> Img\n'            # 10 flagged (anchor 3 above)
  printf '## Plain\n'                            # 11
  printf '##### \360\237\222\254 deep\n'         # 12 level 5 ok
  printf '## \342\230\205 star\n'                # 13 flagged (3-byte)
} > d.md
run d.md
D_ICO='heading-icon: heading has an icon; pin its id with <a name="..."> within 2 lines above'
has "heading-icon: emoji without anchor (full line)" "d.md:1: $D_ICO"
has "heading-icon: <img with anchor 3 lines above"   "d.md:10: $D_ICO"
has "heading-icon: 3-byte U+2605"                    "d.md:13: $D_ICO"
n="$(printf '%s\n' "$OUT" | grep -c ': heading-icon: ')"
[ "$n" = 3 ] && ok "heading-icon: pinned, plain, level-5 not flagged (3 total)" || bad "heading-icon: want 3, got $n: $OUT"


# --- heading ids: trim raw text once, no re-trim after tag removal -------------------------------
{
  printf '## Foo <a href="#top"><img src="u.svg"></a>\n'
  printf '### <img src="i.svg"> Title\n'
  printf '## Why delegate at all<a href="#top"><img align="right" src="../assets/nav-up.svg" alt=""></a>\n'
  printf '### \360\237\222\254 You stay\n'
  printf '<a name="top"></a>\n'
  printf '[a](#foo-) [b](#-title) [c](#why-delegate-at-all) [d](#-you-stay)\n'
  printf '[e](#foo) [f](#title)\n'
} > id.md
run id.md
has "id: old trimmed #foo does not resolve"   'id.md:7: link: no anchor #foo in id.md'
has "id: old trimmed #title does not resolve" 'id.md:7: link: no anchor #title in id.md'
n="$(printf '%s\n' "$OUT" | grep -c ': link: ')"
[ "$n" = 2 ] && ok "id: foo- / -title / why-delegate-at-all / -you-stay all resolve" || bad "id: want 2 link findings, got $n: $OUT"

# --- heading-icon: attached trailing back-link exempt ------------------------------------------
{
  printf '## Why delegate<a href="#top"><img align="right" src="n.svg" alt=""></a>\n'   # 1 ok
  printf '## Foo <a href="#top"><img src="n.svg"></a>\n'                                # 2 flagged (space)
  printf '## <img src="i.svg"> Lead\n'                                                 # 3 flagged
  printf "## Single<A HREF='#top'><IMG src='n.svg'></A>  \\n"                            # 4 ok
  printf '## \360\237\222\254 Em<a href="#top"><img src="n.svg"></a>\n'                 # 5 flagged (emoji)
  printf '## A<img src="a.svg">B<a href="#top"><img src="n.svg"></a>\n'                 # 6 flagged (inner img)
} > e.md
run e.md
has "heading-icon: spaced back-link flagged"          "e.md:2: $D_ICO"
has "heading-icon: leading <img flagged"              "e.md:3: $D_ICO"
has "heading-icon: emoji with back-link still flagged" "e.md:5: $D_ICO"
has "heading-icon: inner <img still flagged"          "e.md:6: $D_ICO"
n="$(printf '%s\n' "$OUT" | grep -c ': heading-icon: ')"
[ "$n" = 4 ] && ok "heading-icon: attached back-links (lines 1, 4) not flagged (4 total)" || bad "heading-icon backlink: want 4, got $n: $OUT"

# --- code spans in heading text are literal; `<img` inside a code span is not an icon -----------
{
  printf '## The `<summary>` rule\n'
  printf '## The `<img>` spacer\n'
  printf '## Real <img src="a.svg"> icon\n'
  printf '[ok](#the-summary-rule) [bad](#the--rule)\n'
  printf '### `doctor`<a href="#top"><img src="n.svg"></a>\n'
} > cs.md
run cs.md
has   "id: code span keeps <summary> (the--rule does not resolve)" 'cs.md:4: link: no anchor #the--rule in cs.md'
lacks "id: #the-summary-rule resolves" 'no anchor #the-summary-rule'
lacks "heading-icon: <img inside code span not flagged" 'cs.md:2: heading-icon'
has   "heading-icon: <img outside code span still flagged" "cs.md:3: $D_ICO"
lacks "heading-icon: code span then attached back-link not flagged" 'cs.md:5: heading-icon'

# --- fence: a backtick run with a backtick in its info string is not an opener ------------------
printf '```x```\n[l](#nope)\n' > fo.md
run fo.md
has "fence: one-line triple-backtick span does not hide the file" 'fo.md:2: link: no anchor #nope in fo.md'
printf '~~~x```\n[l](#nope)\n~~~\n' > ft.md
run ft.md; eq "fence: tilde fence unaffected" "ok"

# --- leading -- and a file named -x.md ----------------------------------------------------------
printf '[l](#nope)\n' > ./-x.md
run -- -x.md
has "args: -- then -x.md reports findings" '-x.md:1: link: no anchor #nope in -x.md'
[ "$RC" = 1 ] && ok "args: -- exit 1" || bad "args: -- rc=$RC"

# --- output, exit codes, default file set ------------------------------------------------------
run b.md; [ "$RC" = 1 ] && ok "exit 1 with findings" || bad "exit with findings was $RC"
run late.md; [ "$RC" = 0 ] && [ "$OUT" = ok ] && ok "exit 0 and 'ok' when clean" || bad "clean run: rc=$RC out=$OUT"
run nosuch.md; [ "$RC" = 2 ] && ok "exit 2 on a missing explicit file" || bad "missing file rc=$RC"
printf '%s\n' "$OUT" | grep -q 'nosuch.md' && ok "missing-file message names the file" || bad "missing-file message: $OUT"
mkdir proj && mkdir proj/docs
printf '# R\n[ok](docs/x.md)\n' > proj/README.md
printf '# X\n[bad](#nope)\n' > proj/docs/x.md
printf 'notes\n' > proj/docs/y.txt
OUT="$(cd proj && sh "$LINT" 2>&1)"; RC=$?
eq "default set: README.md + docs/*.md, path as found" "docs/x.md:2: link: no anchor #nope in docs/x.md"
[ "$RC" = 1 ] && ok "default set exits 1" || bad "default set rc=$RC"
mkdir empty
OUT="$(cd empty && sh "$LINT" 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ "$OUT" = ok ] && ok "no README and no docs: ok, exit 0" || bad "empty dir: rc=$RC out=$OUT"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

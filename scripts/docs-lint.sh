#!/usr/bin/env sh
# kit-scope: shared
# docs-lint.sh - lint markdown for things GitHub renders differently from what the author meant.
#
# Usage: docs-lint.sh [--] [file.md ...]
#   No args: README.md and docs/*.md relative to the current dir (an unmatched glob or a missing
#   README is silently skipped). An explicit arg that is not a file: message on stderr, exit 2.
# Output: one line per finding on stdout, `file:line: <rule>: <detail>` (file = path as given),
#   then exit 1. No findings: prints `ok`, exit 0.
#
# Rules:
#   link          [t](#x), [t](p.md), [t](p.md#x) and href="..." must resolve: the .md file must
#                 exist (resolved relative to the linting file, `.`/`..` normalised) and the anchor
#                 must exist in the target. Images, URLs with a scheme, //x, /x, empty URLs and
#                 non-.md targets are skipped. Anchors = GitHub heading ids (ATX and setext, with
#                 -1/-2 suffixes for duplicates) plus <a name="x"> / <a id="x"> values.
#   setext        `---` directly under a text line is a heading underline, not a rule.
#   summary-bold  `**` between <summary> and </summary> (may span lines) does not render; use <b>.
#   heading-icon  ATX heading level 1-4 with an emoji or <img but no <a name=/<a id= on either of
#                 the 2 lines above: the id GitHub derives is fragile, so pin it.
# Pre-processing: fenced code blocks (``` or ~~~) and YAML front matter are skipped by every rule;
#   inline code spans are blanked before rules link and summary-bold look at a line.
#
# Heading ids: the raw heading text is trimmed once, then links/images/tags/entities are removed
#   WITHOUT trimming again (github-slugger): `## Foo <a href="#x"><img src="u"></a>` -> `foo-`,
#   `### <img src="i"> Title` -> `-title`.
# heading-icon exemption: ONE trailing back-link attached to the text with no whitespace, i.e.
#   `Text<a href="#top"><img ...></a>`, is ignored when looking for <img (it does not change the
#   id). With a space before `<a` the id gains a hyphen, so it still flags. Emoji are unaffected.
#
# Limits (not covered): reference-style links [t][ref]; indented code blocks; URL-encoded paths
#   (%20); root-absolute /path links; non-.md targets; non-ASCII letters in heading ids (all
#   non-ASCII bytes are dropped, so accented letters differ from GitHub); anchor case-insensitivity
#   (matching is exact); raw HTML block nuances. A setext heading's text is taken as the single
#   line above its underline: a pipe-less table row, a list item's continuation line or a lazy
#   blockquote line directly above `---` false-positives. A fence indented 4+ spaces (inside a
#   nested list) is not recognised. Links inside <!-- --> comments are still checked. `_emphasis_`
#   underscores in a heading are kept in its id (GitHub drops them). Emoji detection is an approximation: any 4-byte UTF-8 sequence
#   (lead byte 0xF0-0xF4) or a 3-byte one with lead 0xE2 and second byte 0x98-0x9E (U+2600-27BF)
#   or 0xAC-0xAF (U+2B00-2BFF); other emoji ranges are missed.
#
# POSIX sh + awk; main logic is one awk program run with LC_ALL=C (byte-oriented).
# Self-check: docs-lint.selfcheck.sh
set -u

if [ "$#" -gt 0 ] && [ "$1" = -- ]; then shift; fi
if [ "$#" -eq 0 ]; then
  for f in README.md docs/*.md; do
    [ -f "$f" ] && set -- "$@" "$f"
  done
  [ "$#" -eq 0 ] && { echo ok; exit 0; }
else
  for f in "$@"; do
    [ -f "$f" ] || { echo "docs-lint: not a file: $f" >&2; exit 2; }
  done
fi

T="$(mktemp -d)" || exit 2
trap 'rm -rf "$T"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM
cat > "$T/lint.awk" <<'AWKEOF'
function sp(n,  r) { r = ""; while (n-- > 0) r = r " "; return r }

# normalise a path: drop "" and ".", resolve ".."
function norm(p,  abs, n, a, i, top, st, r) {
  abs = (substr(p, 1, 1) == "/")
  n = split(p, a, "/"); top = 0
  for (i = 1; i <= n; i++) {
    if (a[i] == "" || a[i] == ".") continue
    if (a[i] == "..") {
      if (top > 0 && st[top] != "..") top--
      else if (!abs) st[++top] = ".."
    } else st[++top] = a[i]
  }
  r = ""
  for (i = 1; i <= top; i++) r = r (i > 1 ? "/" : "") st[i]
  if (abs) return "/" r
  return (r == "" ? "." : r)
}

# blank out inline code spans (equal-length backtick runs) with spaces
function blank(s,  out, i, n, j, k, m, run, found) {
  out = ""; n = length(s); i = 1
  while (i <= n) {
    if (substr(s, i, 1) != "`") { out = out substr(s, i, 1); i++; continue }
    j = i; while (j <= n && substr(s, j, 1) == "`") j++
    run = j - i; k = j; found = 0
    while (k <= n) {
      if (substr(s, k, 1) == "`") {
        m = k; while (m <= n && substr(s, m, 1) == "`") m++
        if (m - k == run) { found = 1; break }
        k = m
      } else k++
    }
    if (found) { out = out sp(m - i); i = m }
    else { out = out substr(s, i, run); i = j }
  }
  return out
}

# ATX heading level (0 = not a heading)
function atx(s,  t, n, c) {
  if (s !~ /^ ? ? ?#/) return 0
  t = s; sub(/^ */, "", t); n = 0
  while (substr(t, n + 1, 1) == "#") n++
  if (n > 6) return 0
  c = substr(t, n + 1, 1)
  if (c == "" || c == " " || c == "\t") return n
  return 0
}
function isdash(s) { return s ~ /^ ? ? ?---+[ \t]*$/ }
function isrule(s,  t) {
  if (s !~ /^ ? ? ?[^ ]/) return 0
  t = s; gsub(/[ \t]/, "", t)
  return t ~ /^(---+|\*\*\*+|___+)$/
}
# can line j be the text line above a `---` / `===` underline?
function textok(p, j,  s) {
  if (j < 1 || SK[p, j]) return 0
  s = LN[p, j]
  if (s ~ /^[ \t]*$/) return 0
  if (s ~ /^ ? ? ?\|/) return 0
  if (atx(s)) return 0
  if (s ~ /^ *([-*+]|[0-9]+[.)])[ \t]/) return 0
  if (s ~ /^ ? ? ?>/) return 0
  if (isrule(s)) return 0
  if (s ~ /^ ? ? ?=+[ \t]*$/) return 0
  return 1
}

function unlink(s,  st, ln, m, t2) {
  while (match(s, /!\[[^]]*\]\([^)]*\)/)) s = substr(s, 1, RSTART - 1) substr(s, RSTART + RLENGTH)
  while (match(s, /\[[^]]*\]\([^)]*\)/)) {
    st = RSTART; ln = RLENGTH; m = substr(s, st, ln)
    t2 = substr(m, 2, index(m, "](") - 2)
    s = substr(s, 1, st - 1) t2 substr(s, st + ln)
  }
  return s
}
# GitHub heading id of heading text t
function hid(t,  out, i, n, j, k, m, run, found, nc, cs, tok) {
  sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
  # code spans are literal: swap each for a placeholder (same matching as blank()), restore after
  out = ""; n = length(t); i = 1; nc = 0
  while (i <= n) {
    if (substr(t, i, 1) != "`") { out = out substr(t, i, 1); i++; continue }
    j = i; while (j <= n && substr(t, j, 1) == "`") j++
    run = j - i; k = j; found = 0
    while (k <= n) {
      if (substr(t, k, 1) == "`") {
        m = k; while (m <= n && substr(t, m, 1) == "`") m++
        if (m - k == run) { found = 1; break }
        k = m
      } else k++
    }
    if (found) { cs[++nc] = substr(t, j, k - j); out = out "\001" nc "\002"; i = m }
    else { out = out substr(t, i, run); i = j }
  }
  t = unlink(out)
  gsub(/<[^>]*>/, "", t)
  gsub(/&#?[A-Za-z0-9]+;/, "", t)
  for (i = 1; i <= nc; i++) {
    tok = "\001" i "\002"
    while ((j = index(t, tok)) > 0) t = substr(t, 1, j - 1) cs[i] substr(t, j + length(tok))
  }
  t = tolower(t)
  gsub(/[^a-z0-9 _-]/, "", t)
  gsub(/ /, "-", t)
  return t
}
function addhead(p, t,  id, c) {
  id = hid(t)
  if (!((p, id) in SEEN)) { SEEN[p, id] = 1; A[p, id] = 1 }
  else { c = SEEN[p, id]; SEEN[p, id] = c + 1; A[p, id "-" c] = 1 }
}
function addattr(p, tag, tl, nm,  r, q, v, e) {
  if (!match(tl, "[ \t]" nm "[ \t]*=[ \t]*[\"\047]")) return
  r = RSTART + RLENGTH; q = substr(tl, r - 1, 1)
  v = substr(tag, r); e = index(v, q)
  if (!e) return
  A[p, substr(v, 1, e - 1)] = 1
}
function atags(p, b,  lc, pos, st, len, tag, tl) {
  lc = tolower(b); pos = 1
  while (match(substr(lc, pos), /<a[ \t][^>]*>/)) {
    st = pos + RSTART - 1; len = RLENGTH
    tag = substr(b, st, len); tl = substr(lc, st, len)
    pos = st + len
    addattr(p, tag, tl, "name"); addattr(p, tag, tl, "id")
  }
}

# read file p, classify lines, collect anchors; returns 1 if readable
function load(p,  r, line, n, i, j, s, inf, fch, flen, t, c, k, lv) {
  if (p in LD) return LD[p]
  r = (getline line < p)
  if (r < 0) { LD[p] = 0; return 0 }
  n = 0
  while (r > 0) { n++; sub(/\r$/, "", line); LN[p, n] = line; r = (getline line < p) }
  close(p)
  NL[p] = n; LD[p] = 1
  if (n >= 1 && LN[p, 1] == "---") {
    for (j = 2; j <= n; j++) if (LN[p, j] == "---") break
    if (j <= n) for (i = 1; i <= j; i++) SK[p, i] = 1
  }
  inf = 0
  for (i = 1; i <= n; i++) {
    if (SK[p, i]) continue
    s = LN[p, i]
    t = s; sub(/^ ? ? ?/, "", t); c = substr(t, 1, 1)
    k = 0; while (c != "" && substr(t, k + 1, 1) == c) k++
    if (inf) {
      SK[p, i] = 1
      if (c == fch && k >= flen && substr(t, k + 1) ~ /^ *$/ && substr(s, 1, 4) != "    ") inf = 0
    } else if ((c == "`" || c == "~") && k >= 3 && s !~ /^    / && !(c == "`" && index(substr(t, k + 1), "`"))) {
      inf = 1; fch = c; flen = k; SK[p, i] = 1
    }
  }
  for (i = 1; i <= n; i++) {
    if (SK[p, i]) continue
    s = LN[p, i]; BL[p, i] = blank(s)
    atags(p, BL[p, i])
    lv = atx(s)
    if (lv) {
      t = s; sub(/^ */, "", t); t = substr(t, lv + 1)
      sub(/[ \t]+$/, "", t); sub(/[ \t]+#+$/, "", t)
      addhead(p, t)
    } else if (i > 1 && (isdash(s) || s ~ /^ ? ? ?=+[ \t]*$/) && textok(p, i - 1)) {
      addhead(p, LN[p, i - 1])
    }
  }
  return 1
}

function emit(f, i, r, d) { printf "%s:%d: %s: %s\n", f, i, r, d; found = 1 }

function chk(f, p, i, url,  h, path, frag, dir, rp) {
  if (substr(url, 1, 1) == "<") { url = substr(url, 2); sub(/>$/, "", url) }
  if (url == "") return
  if (url ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return
  if (substr(url, 1, 1) == "/") return
  h = index(url, "#")
  if (h == 1) {
    frag = substr(url, 2)
    if (frag != "" && !((p, frag) in A)) emit(f, i, "link", "no anchor #" frag " in " p)
    return
  }
  if (h) { path = substr(url, 1, h - 1); frag = substr(url, h + 1) } else { path = url; frag = "" }
  if (path !~ /\.md$/) return
  dir = p
  if (sub("/[^/]*$", "", dir) == 0) dir = ""
  else if (dir == "" && substr(p, 1, 1) == "/") dir = "/"
  rp = norm(dir == "" ? path : dir "/" path)
  if (!load(rp)) { emit(f, i, "link", "missing file " rp); return }
  if (frag != "" && !((rp, frag) in A)) emit(f, i, "link", "no anchor #" frag " in " rp)
}

function sumhit(b,  lc, pos, hit, rest, k, e, seg) {
  lc = tolower(b); pos = 1; hit = 0
  while (1) {
    if (!INS) {
      rest = substr(lc, pos)
      if (!match(rest, /<summary([ \t>]|$)/)) break
      pos = pos + RSTART - 1
      k = index(substr(lc, pos), ">")
      INS = 1
      if (!k) break
      pos = pos + k
    }
    rest = substr(lc, pos)
    e = index(rest, "</summary>")
    seg = e ? substr(rest, 1, e - 1) : rest
    if (index(seg, "**")) hit = 1
    if (!e) break
    INS = 0; pos = pos + e + 9
  }
  return hit
}

# lowercased heading line minus ONE attached trailing back-link: nonspace<a href="#.."><img ..></a>
function noback(s,  t) {
  t = tolower(s)
  if (match(t, "[^ \t]<a[ \t][^>]*href=[\"\047]#[^>]*>[ \t]*<img[^>]*>[ \t]*</a>[ \t]*$")) t = substr(t, 1, RSTART)
  return t
}
function anch(p, j) { return j >= 1 && tolower(LN[p, j]) ~ /<a[ \t]+(name|id)[ \t]*=/ }

function lint(f,  p, n, i, s, b, lc, pos, k, q, d, ch, img, rest, url, v, rs, lv) {
  p = norm(f); load(p); n = NL[p]; INS = 0
  for (i = 1; i <= n; i++) {
    if (SK[p, i]) continue
    s = LN[p, i]; b = BL[p, i]
    # rule link: markdown links
    pos = 1
    while ((k = index(substr(b, pos), "](")) > 0) {
      k += pos - 1
      q = k - 1; d = 0
      while (q >= 1) {
        ch = substr(b, q, 1)
        if (ch == "]") d++
        else if (ch == "[") { if (d == 0) break; d-- }
        q--
      }
      if (q >= 1) {
        img = (q > 1 && substr(b, q - 1, 1) == "!")
        rest = substr(b, k + 2)
        if (match(rest, /[ )]/)) url = substr(rest, 1, RSTART - 1); else url = rest
        if (!img) chk(f, p, i, url)
      }
      pos = k + 2
    }
    # rule link: href="..."
    lc = tolower(b); pos = 1
    while (match(substr(lc, pos), HREF)) {
      rs = pos + RSTART - 1 + RLENGTH
      q = substr(b, rs - 1, 1)
      v = substr(b, rs)
      k = index(v, q)
      pos = rs
      if (!k) continue
      url = substr(v, 1, k - 1)
      sub(/ .*/, "", url)
      chk(f, p, i, url)
    }
    # rule setext
    if (isdash(s) && textok(p, i - 1))
      emit(f, i, "setext", "--- under a text line makes it a heading; add a blank line above")
    # rule summary-bold
    if (s !~ /^ ? ? ?\|/ && sumhit(b))
      emit(f, i, "summary-bold", "markdown bold does not render inside <summary>; use <b>")
    # rule heading-icon
    lv = atx(s)
    if (lv >= 1 && lv <= 4 && (s ~ EMOJI || blank(noback(s)) ~ /<img/) && !anch(p, i - 1) && !anch(p, i - 2))
      emit(f, i, "heading-icon", "heading has an icon; pin its id with <a name=\"...\"> within 2 lines above")
  }
}

BEGIN {
  HREF = "href=[\"\047]"
  EMOJI = "[\360-\364]|\342[\230-\236]|\342[\254-\257]"
  found = 0
  for (a = 1; a < ARGC; a++) lint(ARGV[a])
  exit(found ? 1 : 0)
}
AWKEOF
LC_ALL=C awk -f "$T/lint.awk" -- "$@"
rc=$?
[ "$rc" -eq 0 ] && echo ok
exit "$rc"

#!/bin/sh
# kit-scope: shared
# review.sh: a reading aid for a POSIX sh install script, before running it.
#   review.sh [--view auto|plain|less|fzf] FILE
# Trust model: download the installer to a file, review that file, run that same file. The viewer
# copies FILE to a private temp file first and reads and hashes only that copy, so the bytes shown and
# the sha256 printed are the same bytes. It decides from the raw text alone which lines are benign
# shapes and folds those (an allow-list: unknown means shown); lines with effects are shown and listed
# in an effects index; constructs it cannot see through are shown and flagged. Nothing in the file
# (markers, comments) influences folding. It runs nothing from the file.
# Effect functions are derived, not named: a function whose body holds an effect is itself an effect,
# and so is every call to it (fixed point over the whole file, calls may precede definitions).
# Exit: 0 shown; 1 shown but no sha256 tool found; 2 usage error or FILE not a readable regular file.
set -u
LC_ALL=C; export LC_ALL

usage() { printf '%s\n' 'usage: review.sh [--view auto|plain|less|fzf] FILE'; }
view=auto
while [ $# -gt 0 ]; do
  case "$1" in
    --view) [ $# -ge 2 ] || { usage >&2; exit 2; }; view=$2; shift 2 ;;
    --view=*) view=${1#--view=}; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -?*) usage >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -eq 1 ] || { usage >&2; exit 2; }
case "$view" in auto|plain|less|fzf) ;; *) usage >&2; exit 2 ;; esac
src=$1
if [ ! -f "$src" ] || [ ! -r "$src" ]; then
  printf 'review.sh: not a readable regular file: %s\n' "$src" >&2
  exit 2
fi

review_dir=$(mktemp -d "${TMPDIR:-/tmp}/review.XXXXXX") || { printf 'review.sh: mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$review_dir"' EXIT
trap 'exit 130' HUP INT TERM
export review_dir
copy="$review_dir/copy"
cat < "$src" > "$copy" || { printf 'review.sh: cannot copy %s\n' "$src" >&2; exit 2; }

# sha256 of the copy, normalised to bare hex
hex=""
if command -v sha256sum >/dev/null 2>&1; then hex=$(sha256sum < "$copy" | awk '{ print $1 }')
elif command -v shasum >/dev/null 2>&1; then hex=$(shasum -a 256 < "$copy" | awk '{ print $1 }')
elif command -v openssl >/dev/null 2>&1; then hex=$(openssl dgst -sha256 < "$copy" | awk '{ print $NF }')
fi
case "$hex" in *[!0-9a-f]*) hex="" ;; esac
[ ${#hex} -eq 64 ] || hex=""
review_hex=$hex; export review_hex
review_pathhex=$(printf '%s' "$src" | od -A n -t x1 -v); export review_pathhex

# The analyser reads the copy as hex bytes from od, so NUL, CR, ESC and every other byte reach it
# exactly, under any awk (gawk, busybox, BSD), and are rendered as \xNN.
od -A n -t x1 -v "$copy" | awk '
function isC(t) { return (t == "T" || t == "C" || t == "K") }
function topc(d) { return substr(cst[d], length(cst[d]), 1) }
function addix(l, c, why,   k) {
  k = l SUBSEP c SUBSEP why
  if (k in ixseen) return
  ixseen[k] = 1; nix++; ixl[nix] = l; ixc[nix] = c; ixr[nix] = why
}
function flagline(l, c, why) { if (dc[l] < c) dc[l] = c; addix(l, c, why) }
function setlost(l) { if (!lostl || l < lostl) lostl = l }
function addbyte(v) {
  if (v == 10) { endl(); return }
  if (v == 9 || (v >= 32 && v <= 126)) { cur = cur chr[v]; esc = esc chr[v] }
  else { cur = cur "\001"; esc = esc sprintf("\\x%02x", v); na = 1 }
  open_ = 1
}
function endl() { N++; L[N] = cur; E[N] = esc; NA[N] = na; cur = ""; esc = ""; na = 0; open_ = 0 }

# ---- records (one per simple command, case subject, for list, case pattern, function header) ----
function newrec(d, kind,   r) {
  r = ++nrec; rk[r] = kind; rsl[r] = ln; rel[r] = 0; rpar[r] = fpar[d]
  rfn[r] = (fsp > 0 ? fstack[fsp] : 0); rnw[r] = 0; rnr[r] = 0; rb[r] = 0; rc[r] = 0; rcal[r] = ""; rfid[r] = 0
  rec[d] = r
  return r
}
function ensure_rec(d) { if (rec[d]) return rec[d]; return newrec(d, (topc(d) == "p" ? "pat" : "cmd")) }
function term(d,   r) {
  if (pred[d] != "") { flagline(ln, 3, "unrecognized syntax"); pred[d] = "" }
  r = rec[d]
  if (r) { rel[r] = ln; rec[d] = 0 }
}
function app(c, kind,   j) {
  j = fwo[sp]; if (!j) return
  if (!wopen[j]) { wopen[j] = 1; wlit[j] = ""; wpl[j] = 0; wnp[j] = 0; wq[j] = 0; wd[j] = 0; wb[j] = 0; warith[j] = 0; wl[j] = ln }
  if (kind == "L") { if (!wnp[j]) wpl[j] += length(c) }
  else { wnp[j] = 1; if (kind == "Q") wq[j] = 1; else if (kind == "X") wd[j] = 1; else wb[j] = 1 }
  wlit[j] = wlit[j] c
}
function arithvar(   j) { j = fwo[sp]; if (j) warith[j] = 1; else minc[ln] = 1 }
function push(type) { sp++; ft[sp] = type; fl[sp] = ln; fwo[sp] = fwo[sp - 1]; fpq[sp] = 0; fdep[sp] = 0; fptx[sp] = "" }
function ctx_parent(   j) {
  for (j = sp; j >= 1; j--) { if (isC(ft[j])) return ensure_rec(j); if (ft[j] == "H" || ft[j] == "Q") return fop[j] }
  return 0
}
function pushC(type,   p) {
  p = ctx_parent()
  sp++; ft[sp] = type; fl[sp] = ln; fwo[sp] = sp; fpar[sp] = p
  rec[sp] = 0; wopen[sp] = 0; pred[sp] = ""; cst[sp] = ""; gst[sp] = ""; pfn[sp] = 0; funckw[sp] = 0; lop[sp] = 0
}
function topK(   j) { for (j = sp; j >= 1; j--) if (ft[j] == "K") return j; return 0 }
function closeC(d) {
  endword(d); term(d)
  if (gst[d] != "" || cst[d] != "" || pfn[d] || funckw[d]) {
    flagline(ln, 3, "unrecognized syntax")
    while (gst[d] != "") popgroup(d)
  }
  sp = d - 1
}
function closeK(k,   j) {
  if (k != sp) flagline(ln, 3, "unrecognized syntax")
  for (j = sp; j > k; j--) if (isC(ft[j])) { endword(j); term(j) }
  sp = k; closeC(k)
}
function closeP(   nm, rest) {
  if (match(fptx[sp], /^[A-Za-z_][A-Za-z0-9_]*/)) {
    nm = substr(fptx[sp], 1, RLENGTH); rest = substr(fptx[sp], RLENGTH + 1)
    if (rest ~ /^:?=/ && risky(nm)) flagline(ln, 3, "changes how later commands resolve")
    if (rest ~ /^:[^-=?+]/) arithvar()
  }
  if (index(fptx[sp], "[")) arithvar()
  sp--
}
function pushgroup(d, type, f,   k) {
  gst[d] = gst[d] type; k = length(gst[d]); gfn[d, k] = f; gpl[d, k] = ln
  if (f) fstack[++fsp] = f
}
function popgroup(d,   k, f) {
  k = length(gst[d]); if (!k) { flagline(ln, 3, "unrecognized syntax"); return }
  f = gfn[d, k]; gst[d] = substr(gst[d], 1, k - 1)
  if (f) { fend[f] = ln; if (fsp > 0) fsp-- }
}
function popcase(d) {
  if (cst[d] == "") { flagline(ln, 3, "unrecognized syntax"); return }
  cst[d] = substr(cst[d], 1, length(cst[d]) - 1)
}
function mkfunc(d, r, name, l,   f) {
  f = ++nf; fname[f] = name; fhdr[f] = l; fend[f] = 0; fesc[f] = 0
  ndef[name]++; if (!(name in firstdef)) firstdef[name] = f
  fnames[name] = 1
  if (!r) r = newrec(d, "fdef")
  rk[r] = "fdef"; rnw[r] = 0; rfid[r] = f; rsl[r] = l
  term(d); pfn[d] = f
}
function badbody(d,   f) {
  f = pfn[d]; pfn[d] = 0
  fesc[f] = 1; addix(fhdr[f], 3, "unusual function body"); fend[f] = ln
}
function endword(d) { if (!wopen[d]) return; wopen[d] = 0; handle_word(d) }
function handle_word(d,   lit, plain, r, top, op, k) {
  lit = wlit[d]; plain = !wnp[d]; lop[d] = 0
  if (pred[d] != "") {
    r = ensure_rec(d); op = pred[d]; pred[d] = ""
    k = ++rnr[r]; rro[r, k] = op; rrt[r, k] = lit; rrp[r, k] = plain; rrln[r, k] = predl[d]
    if (op == "<<" || op == "<<-") { pn++; phd[pn] = lit; ptab[pn] = (op == "<<-"); pquo[pn] = !plain; pop_[pn] = r; phl[pn] = ln }
    return
  }
  r = rec[d]; top = topc(d)
  if (funckw[d]) {
    funckw[d] = 0
    if (plain && lit ~ /^[A-Za-z_][A-Za-z0-9_.:-]*$/) mkfunc(d, 0, lit, wl[d]); else flagline(ln, 3, "unrecognized syntax")
    return
  }
  if (pfn[d]) {
    if (!r && plain && lit == "{") { pushgroup(d, "B", pfn[d]); pfn[d] = 0; return }
    badbody(d)
  }
  if (plain && !r) {
    if (top == "p") { if (lit == "esac") { popcase(d); return } }
    else if (lit in kwpass) return
    else if (lit == "{") { pushgroup(d, "B", 0); return }
    else if (lit == "}") {
      if (substr(gst[d], length(gst[d]), 1) != "B") flagline(ln, 3, "unrecognized syntax")
      if (gst[d] != "") popgroup(d)
      return
    }
    else if (lit == "esac") { popcase(d); return }
    else if (lit == "case") { newrec(d, "case"); return }
    else if (lit == "for" || lit == "select") { newrec(d, "for"); return }
    else if (lit == "function") { funckw[d] = 1; return }
  }
  if (r && rk[r] == "case" && rnw[r] >= 1 && plain && lit == "in") { term(d); cst[d] = cst[d] "p"; cpl[d, length(cst[d])] = ln; return }
  if (r && rk[r] == "for" && rnw[r] == 1 && plain && lit == "do") { term(d); return }
  r = ensure_rec(d)
  k = ++rnw[r]; rwl[r, k] = lit; rwp[r, k] = plain; rwpl[r, k] = wpl[d]; rwd[r, k] = wd[d]; rwln[r, k] = wl[d]; rwa[r, k] = warith[d]
}
function nl_event(d,   r) {
  endword(d)
  r = rec[d]
  if (r && (rk[r] == "case" || rk[r] == "pat") && pred[d] == "") return
  term(d)
}
function starthd(   j) {
  sp++; ft[sp] = (pquo[1] ? "Q" : "H"); fl[sp] = phl[1]; fwo[sp] = 0
  fhd[sp] = phd[1]; ftab[sp] = ptab[1]; fop[sp] = pop_[1]
  for (j = 1; j < pn; j++) { phd[j] = phd[j + 1]; ptab[j] = ptab[j + 1]; pquo[j] = pquo[j + 1]; pop_[j] = pop_[j + 1]; phl[j] = phl[j + 1] }
  pn--
}
function isarith(s, j,   n, dep, c, q) {
  n = length(s); dep = 0
  for (; j <= n; j++) {
    c = substr(s, j, 1)
    if (c == "\\") { j++; continue }
    if (c == "\047" || c == "\"") { q = index(substr(s, j + 1), c); if (!q) return 0; j += q; continue }
    if (c == "(") dep++
    else if (c == ")") { if (dep > 0) dep--; else return (substr(s, j + 1, 1) == ")") }
  }
  return 0
}
# $ at s[i] in a frame of type t: returns the next index when it opened a frame, else 0
function dollar(s, i, t,   c2) {
  c2 = substr(s, i + 1, 1)
  if (c2 == "(") {
    if (substr(s, i + 2, 1) == "(" && isarith(s, i + 3)) { app("", "X"); push("R"); return i + 3 }
    app("", "X"); if (t == "H") minc[ln] = 1
    pushC("C"); return i + 2
  }
  if (c2 == "{") { app("", "X"); push("P"); fpq[sp] = (t == "D" || t == "H" || (t == "P" && fpq[sp - 1])); return i + 2 }
  if (c2 == "\047" && (isC(t) || t == "R" || (t == "P" && !fpq[sp]))) { app("", "Q"); push("A"); return i + 2 }
  if (c2 == "\"" && isC(t)) { app("", "Q"); push("D"); return i + 2 }
  return 0
}
function lparen(s, i, d, top,   r) {
  r = rec[d]
  if (top == "p" && (!r || rk[r] == "pat")) return i + 1
  if (r && rk[r] == "cmd" && rnw[r] == 1 && rnr[r] == 0 && rwp[r, 1] && rwl[r, 1] ~ /^[A-Za-z_][A-Za-z0-9_.:-]*$/ && match(substr(s, i + 1), /^[ \t]*\)/)) {
    mkfunc(d, r, rwl[r, 1], rwln[r, 1]); return i + 1 + RLENGTH
  }
  if (!r && pfn[d]) {
    if (match(substr(s, i + 1), /^[ \t]*\)/)) return i + 1 + RLENGTH
    pushgroup(d, "P", pfn[d]); pfn[d] = 0; return i + 1
  }
  if (r) { flagline(ln, 3, "unrecognized syntax"); term(d) }
  pushgroup(d, "P", 0); return i + 1
}
function rparen(s, i, d, top) {
  if (top == "p") { term(d); cst[d] = substr(cst[d], 1, length(cst[d]) - 1) "b"; return i + 1 }
  if (substr(gst[d], length(gst[d]), 1) == "P") { term(d); popgroup(d); return i + 1 }
  if (ft[d] == "C") { closeC(d); return i + 1 }
  flagline(ln, 3, "unrecognized syntax"); term(d); return i + 1
}
function oper(s, i,   d, c, c2, c3, op, top) {
  d = sp; c = substr(s, i, 1); c2 = substr(s, i + 1, 1); c3 = substr(s, i + 2, 1)
  if ((c == "<" || c == ">") && c2 == "(") { app("", "X"); pushC("C"); return i + 2 }
  if (c == "<" || c == ">" || (c == "&" && c2 == ">")) {
    if (wopen[d] && !wnp[d] && wlit[d] ~ /^[0-9]+$/) wopen[d] = 0; else endword(d)
    if (c == "<") op = (c2 == "<") ? (c3 == "-" ? "<<-" : (c3 == "<" ? "<<<" : "<<")) : (c2 == ">" ? "<>" : (c2 == "&" ? "<&" : "<"))
    else if (c == ">") op = (c2 == ">") ? ">>" : (c2 == "|" ? ">|" : (c2 == "&" ? ">&" : ">"))
    else op = (c3 == ">") ? "&>>" : "&>"
    if (pred[d] != "") flagline(ln, 3, "unrecognized syntax")
    if (pfn[d]) badbody(d)
    ensure_rec(d); pred[d] = op; predl[d] = ln; lop[d] = 0
    return i + length(op)
  }
  endword(d)
  top = topc(d); lop[d] = 0
  if (c == ";") {
    if (c2 == ";" || c2 == "&") {
      term(d)
      if (top == "b") cst[d] = substr(cst[d], 1, length(cst[d]) - 1) "p"; else flagline(ln, 3, "unrecognized syntax")
      return i + ((c2 == ";" && c3 == "&") ? 3 : 2)
    }
    term(d); return i + 1
  }
  # a trailing | && || continues the command list on the next line (see lop in lexall)
  if (c == "&") { term(d); if (c2 == "&") { lop[d] = 1; return i + 2 } return i + 1 }
  if (c == "|") {
    if (c2 == "|") { term(d); lop[d] = 1; return i + 2 }
    if (top == "p") return i + 1
    term(d); lop[d] = 1; return i + (c2 == "&" ? 2 : 1)
  }
  if (c == "(") return lparen(s, i, d, top)
  return rparen(s, i, d, top)
}
function lexline(   s, n, i, c, t, x, k, q, h, j) {
  s = L[ln]; n = length(s)
  # the shell reads a here-doc body as raw lines first: its terminator ends it even inside an open $(
  for (h = sp; h >= 1 && ft[h] != "H" && ft[h] != "Q"; h--) ;
  if (h >= 1 && !(ft[h] == "H" && pcont)) {
    x = s; if (ftab[h]) sub(/^\t+/, "", x)
    if (x == fhd[h]) {
      if (h != sp) { flagline(ln, 3, "unrecognized syntax"); for (j = sp; j > h; j--) if (isC(ft[j])) { endword(j); term(j) } }
      sp = h - 1; if (pn > 0) starthd(); return
    }
    sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x)
    if (x == fhd[h] || (index(x, fhd[h]) == 1 && length(x) > length(fhd[h]) && index(");&|", substr(x, length(fhd[h]) + 1, 1)))) flagline(ln, 3, "here-doc terminator lookalike")
  }
  t = ft[sp]
  if (t == "Q") return
  i = 1
  while (i <= n) {
    c = substr(s, i, 1); t = ft[sp]
    if (c == "`") {
      k = topK()
      if (k) { closeK(k); i++; continue }
      if (t == "S" || t == "A") { app(c, "Q"); i++; continue }
      app("", "X"); if (t == "H") minc[ln] = 1
      pushC("K"); i++; continue
    }
    if (c == "\\" && substr(s, i + 1, 1) == "`" && topK()) { flagline(ln, 3, "nested backtick quoting"); i += 2; continue }
    if (t == "S") { if (c == "\047") sp--; else app(c, "Q"); i++; continue }
    if (t == "A") {
      if (c == "\\") {
        # dash reads $\047...\047 as $ plus a plain single-quoted string, so an escaped quote inside
        # ends the string there for dash but not for bash: the two shells now disagree on the rest
        if (substr(s, i + 1, 1) == "\047") { setlost(ln); return }
        app(substr(s, i, 2), "Q"); i += 2; continue
      }
      if (c == "\047") sp--; else app(c, "Q")
      i++; continue
    }
    if (t == "D") {
      if (c == "\\") { if (i < n) app(substr(s, i + 1, 1), "Q"); i += 2; continue }
      if (c == "\"") { sp--; i++; continue }
      if (c == "$") { k = dollar(s, i, t); if (k) { i = k; continue } }
      app(c, "Q"); i++; continue
    }
    if (t == "P") {
      if (c == "}") { closeP(); i++; continue }
      fptx[sp] = fptx[sp] c
      if (c == "\\") { app(substr(s, i, 2), "X"); i += 2; continue }
      if (c == "\047") {
        if (!fpq[sp]) { push("S"); i++; continue }
        # inside "${...}" shells disagree on single quotes; accept only a span both read the same way
        q = index(substr(s, i + 1), "\047")
        if (!q || substr(s, i + 1, q - 1) ~ /[}"`$\\]/) { setlost(ln); return }
        app(substr(s, i, q + 1), "X"); i += q + 1; continue
      }
      if (c == "\"") { push("D"); i++; continue }
      if (c == "$") { k = dollar(s, i, t); if (k) { i = k; continue } }
      app(c, "X"); i++; continue
    }
    if (t == "R") {
      if (c == "(") { fdep[sp]++; app(c, "X"); i++; continue }
      if (c == ")") {
        if (fdep[sp] > 0) { fdep[sp]--; app(c, "X"); i++; continue }
        sp--; i += (substr(s, i + 1, 1) == ")" ? 2 : 1); continue
      }
      if (c ~ /[A-Za-z_$]/) arithvar()
      if (c == "\"") { push("D"); i++; continue }
      if (c == "\047") { push("S"); i++; continue }
      if (c == "\\") { app(substr(s, i, 2), "X"); i += 2; continue }
      if (c == "$") { k = dollar(s, i, t); if (k) { i = k; continue } }
      app(c, "X"); i++; continue
    }
    if (t == "H") {
      if (c == "\\") { if (i == n) { cont = 1; flagline(ln, 3, "here-doc line continuation") } i += 2; continue }
      if (c == "$") { k = dollar(s, i, t); if (k) { minc[ln] = 1; i = k; continue } }
      i++; continue
    }
    # code frames: T (top), C ($( ... )), K (backticks)
    if (c == " " || c == "\t") { endword(sp); i++; continue }
    if (c == "\\") {
      if (i == n) { cont = 1; i++; continue }
      app(substr(s, i + 1, 1), "B"); i += 2; continue
    }
    if (c == "\047") { app("", "Q"); push("S"); i++; continue }
    if (c == "\"") { app("", "Q"); push("D"); i++; continue }
    if (c == "$") { k = dollar(s, i, t); if (k) { i = k; continue } app(c, "X"); i++; continue }
    if (c == "#" && !wopen[sp]) {
      # a comment inside backticks ends at the closing backtick, which the shell finds first
      if (topK()) { x = index(substr(s, i), "`"); if (x) { i += x - 1; continue } }
      break
    }
    if (index(";&|()<>", c)) { i = oper(s, i); continue }
    app(c, "L"); i++
  }
  if (lostl) return
  t = ft[sp]
  if (isC(t)) { if (!cont) nl_event(sp) }
  else if (t == "S" || t == "A" || t == "D") app("\n", "Q")
  if (pn > 0 && isC(ft[sp]) && !cont) starthd()
}

# ---- classification ----
function risky(n) { return ((n in riskset) || n ~ /^LD_/ || n ~ /^DYLD_/) }
function isassign(r, i) {
  if (match(rwl[r, i], /^[A-Za-z_][A-Za-z0-9_]*\+?=/)) return (RLENGTH <= rwpl[r, i])
  return 0
}
function aname(r, i,   n) { n = substr(rwl[r, i], 1, index(rwl[r, i], "=") - 1); sub(/\+$/, "", n); return n }
function mark(r, c, l, why) { if (rb[r] < c) rb[r] = c; addix(l, c, why) }
function show(r) { if (rb[r] < 1) rb[r] = 1 }
function takesarg(w, al,   k, ch) {
  for (k = 2; k <= length(w); k++) { ch = substr(w, k, 1); if (index(al, ch)) return (k == length(w)) }
  return 0
}
function skipopts(r, j, nm,   nw, w, al, la, dur, n) {
  nw = rnw[r]; al = optl[nm]; la = optlong[nm]; dur = (nm == "timeout")
  while (j <= nw) {
    w = rwl[r, j]
    if (w == "--") { j++; break }
    if (substr(w, 1, 1) == "-" && w != "-") {
      if (nm == "env" && (w ~ /^-[A-Za-z0-9]*S/ || w ~ /^--split-string/)) mark(r, 3, rwln[r, j], "command from a variable or quoted word")
      if (nm == "env" && w ~ /^-[A-Za-z0-9]*P/) mark(r, 3, rwln[r, j], "changes how later commands resolve")
      if (nm == "time" && (w ~ /^-[A-Za-z0-9]*o/ || w ~ /^--(output|append)/)) mark(r, 2, rwln[r, j], "writes a file")
      if (substr(w, 2, 1) == "-") { if (index(la, " " w " ")) j++; j++; continue }
      if (takesarg(w, al)) j++
      j++; continue
    }
    if (w == "-" && nm == "env") { j++; continue }
    if ((nm == "env" || nm == "sudo" || nm == "doas") && isassign(r, j)) {
      n = aname(r, j); if (risky(n) && n != "IFS") mark(r, 3, rwln[r, j], "changes how later commands resolve")
      j++; continue
    }
    if (dur) { dur = 0; j++; continue }
    break
  }
  return j
}
function varck(r, i, nm,   j, w, n) {
  for (j = i + 1; j <= rnw[r]; j++) {
    w = rwl[r, j]
    if (substr(w, 1, 1) == "-") { if (nm == "unset" && w ~ /f/) show(r); continue }
    n = w; if (index(n, "=")) n = substr(n, 1, index(n, "=") - 1)
    sub(/\+$/, "", n)
    if (risky(n)) mark(r, 3, rwln[r, j], "changes how later commands resolve")
    else if (nm != "printf" && n !~ /^[A-Za-z_][A-Za-z0-9_]*$/) show(r)
  }
}
function cmdat(r, i, resolve,   nm, l, nw, j, a, k, n) {
  nw = rnw[r]; nm = rwl[r, i]; l = rwln[r, i]
  if (!rwp[r, i]) { mark(r, 3, l, "command from a variable or quoted word"); return }
  if (index(nm, "/")) { mark(r, 3, l, "runs a file by path"); return }
  if (nm != "[" && nm != "[[" && nm !~ /^[A-Za-z0-9_.:+%@,-]+$/) { mark(r, 3, l, "command from a variable or quoted word"); return }
  if (resolve && (nm in fnames)) { rcal[r] = nm; rcalln[r] = l; return }
  if (nm in interp) { mark(r, 3, l, "runs other code"); return }
  if (nm == "eval") { mark(r, 3, l, "eval runs a string as code"); return }
  if (nm == "." || nm == "source") { mark(r, 3, l, "sources another file"); return }
  if (nm == "alias") { mark(r, 3, l, "redefines a command"); return }
  if (nm == "enable" || (nm == "hash" && i < nw)) { mark(r, 3, l, "changes how later commands resolve"); return }
  if (nm == "trap") {
    j = i + 1; if (j <= nw && rwl[r, j] == "--") j++
    if (j > nw) { show(r); return }
    a = rwl[r, j]
    if (rwp[r, j] && (a == "-" || a ~ /^-[lp]$/ || a ~ /^[0-9]+$/)) { show(r); return }
    if (a == "" && !rwd[r, j]) { show(r); return }
    mark(r, 3, l, "deferred code in a string"); return
  }
  if (nm == "sudo" || nm == "doas") {
    mark(r, 2, l, "runs as root")
    j = skipopts(r, i + 1, nm); if (j <= nw) cmdat(r, j, 0)
    return
  }
  if (nm == "command") {
    for (j = i + 1; j <= nw && rwl[r, j] ~ /^-[pvV]+$/; j++) if (rwl[r, j] ~ /[vV]/) return
  }
  if (nm in wrap) {
    j = skipopts(r, i + 1, nm)
    if (j <= nw) { show(r); cmdat(r, j, nm == "time") }
    else if (nm != "exec") show(r)
    return
  }
  if (nm in safe) {
    if (nm == "sort") { for (j = i + 1; j <= nw; j++) if (rwl[r, j] ~ /^-[A-Za-z]*o/ || rwl[r, j] ~ /^--output/) { mark(r, 2, l, "effect command sort -o"); return } }
    else if (nm == "uniq") {
      k = 0; n = 0
      for (j = i + 1; j <= nw; j++) { if (!n && rwl[r, j] == "--") { n = 1; continue } if (n || substr(rwl[r, j], 1, 1) != "-" || rwl[r, j] == "-") k++ }
      if (k >= 2) { mark(r, 2, l, "effect command uniq (writes its output file)"); return }
    }
    else if (nm == "date") { for (j = i + 1; j <= nw; j++) if (rwl[r, j] ~ /^-[A-Za-z]*s/ || rwl[r, j] ~ /^--set/) show(r) }
    else if (nm == "test" || nm == "[") { for (j = i + 1; j <= nw; j++) if (rwl[r, j] == "-v" || rwl[r, j] == "-R") show(r) }
    else if (nm == "printf") { if (i < nw && rwl[r, i + 1] == "-v") { show(r); varck(r, i + 1, nm) } }
    else if (nm in namecmd) varck(r, i, nm)
    return
  }
  if (nm == "set") {
    for (j = i + 1; j <= nw; j++) {
      a = rwl[r, j]
      if (!rwp[r, j]) { show(r); return }
      if (a == "--" && j == nw) continue
      if ((a == "-o" || a == "+o") && j < nw && rwl[r, j + 1] ~ /^[a-z]+$/) { j++; continue }
      if (a !~ /^[-+][A-Za-z]+$/) { show(r); return }
    }
    return
  }
  if (nm in effcmd) { mark(r, 2, l, "effect command " nm); return }
  show(r)
  if (nm == "declare" || nm == "typeset") { varck(r, i, nm); return }
  if (nm == "git") {
    for (j = i + 1; j <= nw && substr(rwl[r, j], 1, 1) == "-"; j++) if (rwl[r, j] in gitarg) j++
    if (j <= nw && rwp[r, j] && (rwl[r, j] in gitsub)) mark(r, 2, l, "effect command git " rwl[r, j])
    return
  }
  if (nm == "sed") { for (j = i + 1; j <= nw; j++) if (rwl[r, j] ~ /^-[A-Za-z]*i/ || rwl[r, j] ~ /^--in-place/) { mark(r, 2, l, "effect command sed -i"); return } return }
  if (nm == "find") { for (j = i + 1; j <= nw; j++) if (rwl[r, j] in findact) { mark(r, 2, l, "effect command find " rwl[r, j]); return } return }
  if (nm == "base64") { for (j = i + 1; j <= nw; j++) if (rwl[r, j] ~ /^-[A-Za-z]*[dD]/ || rwl[r, j] == "--decode") { mark(r, 3, l, "decodes hidden data"); return } return }
  if (nm == "xxd") { for (j = i + 1; j <= nw; j++) if (rwl[r, j] ~ /^-[A-Za-z]*r/) { mark(r, 3, l, "decodes hidden data"); return } return }
  if (nm == "uudecode") { mark(r, 3, l, "decodes hidden data"); return }
  if (nm == "openssl") {
    a = 0; k = 0
    for (j = i + 1; j <= nw; j++) { if (rwl[r, j] == "enc" || rwl[r, j] == "base64") a = 1; if (rwl[r, j] == "-d") k = 1 }
    if (a && k) mark(r, 3, l, "decodes hidden data")
    return
  }
}
function classify(r,   i, nw, j, nm, alone) {
  if (rk[r] == "for") {
    if (rnw[r] >= 1 && rwp[r, 1] && risky(rwl[r, 1])) mark(r, 3, rwln[r, 1], "changes how later commands resolve")
    return
  }
  if (rk[r] != "cmd") return
  nw = rnw[r]
  for (j = 1; j <= nw; j++) if (rwa[r, j] || index(rwl[r, j], "$(") || index(rwl[r, j], "`") || index(rwl[r, j], "$[")) show(r)
  for (i = 1; i <= nw && isassign(r, i); i++) ;
  alone = (i > nw)
  for (j = 1; j < i; j++) { nm = aname(r, j); if (risky(nm) && (alone || nm != "IFS")) mark(r, 3, rwln[r, j], "changes how later commands resolve") }
  if (!alone) cmdat(r, i, 1)
  for (j = 1; j <= rnr[r]; j++) {
    if (!(rro[r, j] in outop)) continue
    if (rrp[r, j] && (rrt[r, j] in safetarget)) continue
    if (rro[r, j] == ">&" && rrp[r, j] && rrt[r, j] ~ /^([0-9]+|-)$/) continue
    mark(r, 2, rrln[r, j], "writes a file")
  }
}
function lexall(   j, join) {
  sp = 1; ft[1] = "T"; fl[1] = 1; fwo[1] = 1; fpar[1] = 0; rec[1] = 0; pred[1] = ""; cst[1] = ""; gst[1] = ""
  join = 0
  for (ln = 1; ln <= N; ln++) {
    grp[ln] = (join ? grp[ln - 1] : ln)
    pcont = cont; cont = 0
    lexline()
    if (lostl) break
    join = (sp > 1 || cont || (isC(ft[sp]) && lop[sp]))
  }
  if (lostl) return
  ln = N
  for (j = sp; j >= 1; j--) if (isC(ft[j])) { endword(j); term(j) }
  if (sp > 1) setlost(fl[2])
  if (pn > 0) setlost(phl[1])
  if (gst[1] != "") setlost(gpl[1, 1])
  if (cst[1] != "") setlost(cpl[1, 1])
  if (pfn[1]) setlost(fhdr[pfn[1]])
  if (funckw[1]) setlost(N)
}
function clsname(c) { return (c == 3 ? "ESCAPE" : (c == 2 ? "EFFECT" : (c == 1 ? "SHOW" : "FOLD"))) }
function trunc(s) { return (length(s) > 100 ? substr(s, 1, 100) "..." : s) }
function words(s, arr, v,   n, k, a) { n = split(s, a, " "); for (k = 1; k <= n; k++) arr[a[k]] = v }
BEGIN {
  pr = " !\"#$%&\047()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
  for (i = 1; i <= length(pr); i++) chr[31 + i] = substr(pr, i, 1)
  chr[9] = "\t"
  for (i = 0; i < 256; i++) hv[sprintf("%02x", i)] = i
  words("echo printf test [ true false : shift unset return exit break continue local readonly export read getopts pwd basename dirname uname id whoami printenv sleep wait cat head tail wc cut tr expr cksum sha256sum shasum md5sum grep jq sort uniq date type", safe, 1)
  words("unset local readonly export read getopts", namecmd, 1)
  words("rm rmdir mv cp ln mkdir chmod chown chgrp touch tee dd truncate install mktemp unlink curl wget fetch scp rsync sftp kill pkill killall systemctl launchctl crontab shutdown reboot useradd usermod chsh apt apt-get yum dnf pacman zypper apk brew port pip pip3 npm gem cargo defaults osascript", effcmd, 1)
  words("sh bash dash zsh ksh fish busybox python python2 python3 perl ruby node php", interp, 1)
  words("env nohup nice time command exec xargs timeout builtin", wrap, 1)
  words("clone init checkout switch reset commit push pull fetch config apply am merge rebase rm mv add stash clean worktree tag branch restore", gitsub, 1)
  words("-C -c --git-dir --work-tree --namespace --config-env --super-prefix", gitarg, 1)
  words("PATH IFS ENV BASH_ENV CDPATH PS4 PROMPT_COMMAND SHELLOPTS BASHOPTS", riskset, 1)
  words("-delete -exec -execdir -ok -okdir -fprint -fprint0 -fprintf -fls", findact, 1)
  words("if then else elif while until do fi done !", kwpass, 1)
  words("> >> >| <> &> &>> >&", outop, 1)
  words("/dev/null /dev/stdout /dev/stderr /dev/tty", safetarget, 1)
  for (k in safe) known[k] = 1
  for (k in effcmd) known[k] = 1
  for (k in interp) known[k] = 1
  for (k in wrap) known[k] = 1
  words("eval . source alias unalias trap set cd sudo doas git sed find base64 xxd uudecode openssl awk hash enable umask ulimit declare typeset let jobs fg bg times command_not_found_handle", known, 1)
  optl["env"] = "uCSP"; optlong["env"] = " --unset --chdir --split-string "
  optl["nice"] = "n"; optlong["nice"] = " --adjustment "
  optl["time"] = "fo"; optlong["time"] = " --format --output "
  optl["timeout"] = "sk"; optlong["timeout"] = " --signal --kill-after "
  optl["exec"] = "a"
  optl["xargs"] = "IdELnPsa"; optlong["xargs"] = " --arg-file --delimiter --max-args --max-lines --max-procs --max-chars --process-slot-var --eof "
  optl["sudo"] = "ugCDhprtTUR"; optlong["sudo"] = " --user --group --close-from --chdir --host --prompt --role --type --command-timeout --other-user --chroot "
  optl["doas"] = "uC"
  N = 0; cur = ""; esc = ""; na = 0; open_ = 0
}
{ for (f = 1; f <= NF; f++) { odf = tolower($f); if (!(odf in hv)) { badod = 1; exit }; addbyte(hv[odf]) } }
END {
  # an od field that is not two hex digits would mis-render bytes while the hash stays right: refuse
  if (badod) exit 3
  if (open_) endl()
  dir = ENVIRON["review_dir"]
  lexall()
  for (r = 1; r <= nrec; r++) if (!rel[r]) rel[r] = N
  for (f = 1; f <= nf; f++) {
    if (!fend[f]) fend[f] = N
    if (ndef[fname[f]] > 1) { fesc[f] = 1; addix(fhdr[f], 3, "defined twice") }
    if (fname[f] in known) { fesc[f] = 1; addix(fhdr[f], 3, "function shadows " fname[f]) }
    fcls[f] = (fesc[f] ? 3 : 0)
  }
  for (r = 1; r <= nrec; r++) { classify(r); rc[r] = rb[r] }
  # fixed point: classes only rise; children raise parents, bodies raise functions, functions raise calls
  do {
    ch = 0
    for (r = nrec; r >= 1; r--) {
      c = rc[r]
      if (rcal[r] != "" && ncls[rcal[r]] > c) c = ncls[rcal[r]]
      if (rk[r] == "fdef" && fcls[rfid[r]] > c) c = fcls[rfid[r]]
      if (c > rc[r]) { rc[r] = c; ch = 1 }
      p = rpar[r]; if (p && rc[p] < c) { rc[p] = c; ch = 1 }
      f = rfn[r]; if (f && fcls[f] < c) { fcls[f] = c; ch = 1 }
    }
    for (f = 1; f <= nf; f++) if (ncls[fname[f]] < fcls[f]) { ncls[fname[f]] = fcls[f]; ch = 1 }
  } while (ch)
  for (r = 1; r <= nrec; r++) {
    if (rcal[r] == "") continue
    nm = rcal[r]; c = ncls[nm]
    if (!((nm SUBSEP rcalln[r]) in callseen)) { callseen[nm, rcalln[r]] = 1; calls[nm] = calls[nm] " L" rcalln[r] }
    if (c >= 2) addix(rcalln[r], c, (c == 3 ? "calls escape function " : "calls effect function ") nm " (L" fhdr[firstdef[nm]] ")")
  }
  # line classes
  for (l = 1; l <= N; l++) { lc[l] = dc[l] + 0; if (minc[l] && lc[l] < 1) lc[l] = 1 }
  for (r = 1; r <= nrec; r++) for (l = rsl[r]; l <= rel[r]; l++) if (lc[l] < rc[r]) lc[l] = rc[r]
  for (f = 1; f <= nf; f++) { if (lc[fhdr[f]] < fcls[f]) lc[fhdr[f]] = fcls[f]; if (lc[fend[f]] < fcls[f]) lc[fend[f]] = fcls[f] }
  for (l = 1; l <= N; l++) if (NA[l]) { lc[l] = 3; addix(l, 3, "non-ASCII or control bytes") }
  if (lostl) { for (l = lostl; l <= N; l++) lc[l] = 3; addix(lostl, 3, "lexer lost track here; rest shown unfolded") }
  # a logical line (continuation, multi-line quote, open $( or here-doc) takes the max of its lines
  l = 1
  while (l <= N) {
    e = l; m = lc[l]
    while (e < N && grp[e + 1] != "" && grp[e + 1] == grp[l]) { e++; if (lc[e] > m) m = lc[e] }
    for (k = l; k <= e; k++) lc[k] = m
    l = e + 1
  }
  # folding: runs of 3+ FOLD lines
  F = 0; K = 0
  l = 1
  while (l <= N) {
    if (lc[l] != 0) { l++; continue }
    e = l; while (e < N && lc[e + 1] == 0) e++
    if (e - l + 1 >= 3) { for (k = l; k <= e; k++) fold[k] = 1; F += e - l + 1; K++ }
    l = e + 1
  }
  # path, escaped
  n = split(ENVIRON["review_pathhex"], ph, " "); path = ""
  for (k = 1; k <= n; k++) { v = hv[tolower(ph[k])]; path = path ((v == 9 || (v >= 32 && v <= 126)) ? chr[v] : sprintf("\\x%02x", v)) }
  hex = ENVIRON["review_hex"]
  shaline = (hex != "" ? hex "  " path : "sha256: unavailable (no sha256sum, shasum or openssl)")
  # effects index, sorted by line (stable)
  for (a = 2; a <= nix; a++) {
    tl = ixl[a]; tc = ixc[a]; tr = ixr[a]
    for (b = a - 1; b >= 1 && ixl[b] > tl; b--) { ixl[b + 1] = ixl[b]; ixc[b + 1] = ixc[b]; ixr[b + 1] = ixr[b] }
    ixl[b + 1] = tl; ixc[b + 1] = tc; ixr[b + 1] = tr
  }
  ne = 0; nx = 0; for (k = 1; k <= nix; k++) { if (ixc[k] == 3) nx++; else ne++ }
  nfx = 0; for (f = 1; f <= nf; f++) if (fcls[f] >= 2) nfx++
  vf = dir "/view"; hf = dir "/hdr"; itf = dir "/items"; ff = dir "/full"; sf = dir "/sha"
  intro = "review.sh: a reading aid, not a sandbox. It folds only lines it can show are benign shapes and never folds a line it cannot; it does not run, emulate or contain the file. Flagged lines are ones it could not see through."
  counts = sprintf("lines: %d  shown: %d  folded: %d in %d blocks", N, N - F, F, K)
  print intro > vf; print "file: " path > vf; print counts > vf
  print intro > hf; print "file: " path > hf; print counts > hf
  printf "effects index: %d EFFECT, %d ESCAPE; effect functions: %d\n", ne, nx, nfx > hf
  print "== Effects index ==" > vf
  if (!nix) print "(none)" > vf
  for (k = 1; k <= nix; k++) printf "L%d  %s  %s  | %s\n", ixl[k], clsname(ixc[k]), ixr[k], trunc(E[ixl[k]]) > vf
  print "== Effect functions ==" > vf
  if (!nfx) print "(none)" > vf
  for (f = 1; f <= nf; f++) if (fcls[f] >= 2) printf "%s  L%d-L%d  %s  called at%s\n", fname[f], fhdr[f], fend[f], clsname(fcls[f]), (calls[fname[f]] != "" ? calls[fname[f]] : " (none)") > vf
  print "== Script ==" > vf
  l = 1
  while (l <= N) {
    if (fold[l]) {
      e = l; while (e < N && fold[e + 1]) e++
      printf "      ... folded L%d-L%d (%d lines)\n", l, e, e - l + 1 > vf
      printf "L%d-%d ... folded (%d lines)\n", l, e, e - l + 1 > itf
      l = e + 1; continue
    }
    tag = (lc[l] == 3 ? "!" : (lc[l] == 2 ? "E" : " "))
    printf "%5d %s %s\n", l, tag, E[l] > vf
    printf "L%d-%d %s %s\n", l, l, tag, E[l] > itf
    l++
  }
  if (!N) printf "" > itf
  print "== sha256 ==" > vf; print shaline > vf
  print shaline > sf
  for (l = 1; l <= N; l++) printf "%5d %s %s\n", l, (lc[l] == 3 ? "!" : (lc[l] == 2 ? "E" : " ")), E[l] > ff
  if (!N) printf "" > ff
  close(vf); close(hf); close(itf); close(ff); close(sf)
}' || { printf 'review.sh: analysis failed\n' >&2; exit 2; }

if [ "$view" = auto ]; then
  if [ -t 1 ]; then
    if command -v fzf >/dev/null 2>&1; then view=fzf
    elif command -v less >/dev/null 2>&1; then view=less
    else view=plain
    fi
  else
    view=plain
  fi
fi

case "$view" in
  plain)
    cat "$review_dir/view" ;;
  less)
    { cat "$review_dir/view"; printf '== Full text (escaped, numbered) ==\n'; cat "$review_dir/full"; } | less
    cat "$review_dir/sha" ;;
  fzf)
    # fzf runs the preview with $SHELL -c; the temp path reaches it through the environment only
    review_esc="$review_dir/full"; export review_esc
    prev='r={1}; r=${r#L}; a=${r%%-*}; b=${r#*-}; case "$a$b" in ""|*[!0-9]*) exit 0 ;; esac; sed -n "${a},${b}p" "$review_esc"'
    hdr=$(cat "$review_dir/hdr")
    SHELL=/bin/sh fzf --no-sort --header "$hdr" --preview "$prev" < "$review_dir/items"
    cat "$review_dir/sha" ;;
esac
[ -n "$hex" ] || exit 1
exit 0

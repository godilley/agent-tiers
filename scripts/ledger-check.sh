#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers SessionStart advisory: reads the project's outstanding-work ledger(s) and reports
# triggers that have fired, DONE lines that do not prove anything, and a ledger past its cap.
#
# Why (observed 2026-10-01): nothing read the "Forced by" line of an open ledger entry, so fired
# triggers sat unnoticed (3 open entries in one ledger named a session already DONE), and the one
# existing reader accepted any line holding DONE plus an id ("DONE S9m7 (uncommitted" passed).
#
# Schema, in five lines:
#   ledger = docs/_local/*outstanding-work-ledger*.md, line 1 "STATUS: LIVE"; entry = column-0 "- " bullet up to the
#   next column-0 "- " or "#" line. Closed = a line starting (after spaces, "- ") DONE or **DONE,
#   or a bullet line "- **title** **DONE ...". (Count-only: that bullet is not a DONE line for L3/L4/F5.)
#   Labelled = a "Deferred:" or "Forced by:" line. Trigger = the line whose text (after leading spaces)
#   starts with "Forced by:", or else the first line matching forced by/would force/forcing (whole word).
#   Typed tokens on the trigger line: [session: ID] [exists: path] [date: YYYY-MM-DD] [grep>=N: RE @ path].
#   DONE line form: DONE <date> [<id|sha>]: <check>. Plan = LIVE docs/_local/*.md with "## Status table".
#
# Checks: L1 typed token fired; L1b untyped trigger names a DONE plan row id (whole word); L3 DONE line
# whose head (text up to the first colon, or the whole line) holds a whole-word qualifier
# (uncommitted|PARTIAL|except|pending) - flagged but the entry stays open - or whose check (text after
# the colon plus following lines, up to a blank line, EOF, column-0 "- ", "#", or a DONE/label line, or
# "no check after DONE" when there is no colon at all) is empty - flagged and closed; L4 sha not found
# in `git rev-list HEAD` (prefix match, shas may be abbreviated 7+ chars); F5 DONE line names a plan row
# not DONE; L5 ledger over 1500 lines or 150000 bytes. At most 6 detail lines, then one counts line per
# ledger.
#
# Disclosed ceilings: prose triggers are counted, never judged; legacy entries are listed only when
# their trigger line names a finished session (L1b); L1b and F5 need a plan; a "]" inside a grep token
# regex ends the token early.
#
# Advisory only: never exits non-zero, never sets a decision field. Fail-open with a breadcrumb.
# Kill switch: .state/off/ledger-check (enforced by kit-gate.sh), resolved from the script's own location (not
# CLAUDE_CONFIG_DIR) - the kill switch and the default log live in the kit's own .state, shared
# across every profile pointed at this kit, same as guard-summary.sh/portable-citation-advisory.sh.
# Self-check: ledger-check.selfcheck.sh
set -u
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"

[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9._-]*\)".*/\1/p' | head -1)"
note() {
  { mkdir -p "$(dirname "$LOG")" && printf '%s ledger-check fail-open: %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "$SID" >> "$LOG"; } 2>/dev/null || true
}
command -v jq >/dev/null 2>&1 || { note "no jq"; exit 0; }

D="${CLAUDE_PROJECT_DIR:-}"
[ -n "$D" ] || D="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$D" ] || D="$PWD"
[ -d "$D/docs/_local" ] || exit 0

LEDGERS=""
PLAN=""
for f in "$D"/docs/_local/*.md; do
  [ -f "$f" ] || continue
  head -1 "$f" 2>/dev/null | grep -q '^STATUS: LIVE' || continue
  case "$(basename "$f")" in *outstanding-work-ledger*) LEDGERS="$LEDGERS$f
" ;; esac
  [ -z "$PLAN" ] && grep -q '^## Status table' "$f" 2>/dev/null && PLAN="$f"
done
[ -n "$LEDGERS" ] || exit 0

TODAY="$(date +%Y%m%d)"
TAB="$(printf '\t')"

# One awk pass per ledger. Records out (tab-separated, in line order):
#   F code line text      a finding decided inside awk (L1 session/date, L1b, L3, F5)
#   X line path text      L1 exists token, tested by the shell
#   G line N path RE text L1 grep token, counted by the shell
#   S line sha text       L4 sha candidate, checked by the shell
#   C open lab notrig nothing legacy closed
AWK_PROG='
function trim(x) { sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x); return x }
function clean(x) { gsub(/\t/, " ", x); x = substr(x, 1, 90); if (x == "") x = "(untitled)"; return x }
function hasword(line, w,   i, off, b, a) {
  off = 0
  while ((i = index(substr(line, off + 1), w)) > 0) {
    b = (off + i > 1) ? substr(line, off + i - 1, 1) : ""
    a = substr(line, off + i + length(w), 1)
    if (b !~ /[A-Za-z0-9_]/ && a !~ /[A-Za-z0-9_]/) return 1
    off += i
  }
  return 0
}
BEGIN {
  plan = ENVIRON["plan"]; today = ENVIRON["today"]
  ndone = 0; nrow = 0
  if (plan != "") {
    intab = 0
    while ((getline l < plan) > 0) {
      if (l ~ /^## Status table/) { intab = 1; continue }
      if (intab && l ~ /^#/) break
      if (!intab || l !~ /^\|/) continue
      split(l, c, "|")
      id = trim(c[2]); st = trim(c[3])
      lid = tolower(id)
      if (id == "" || lid == "id" || lid == "session" || lid == "phase" || lid == "step" || id ~ /^[-: ]+$/) continue
      rowst[id] = st; rowid[++nrow] = id
      if (st ~ /^DONE/) { isdone[id] = 1; doneid[++ndone] = id }
    }
    close(plan)
  }
  nopen = nlab = notrig = nnoth = nleg = nclosed = 0
}
function emit_trigger(   line, untyped, tok, cp, kind, val, p, q, re, path, i) {
  line = trig; untyped = trig
  gsub(/\[(session|exists|date|grep>=[0-9]+): [^]]*\]/, " ", untyped)
  while (match(line, /\[(session|exists|date|grep>=[0-9]+): [^]]*\]/)) {
    tok = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
    cp = index(tok, ":"); kind = substr(tok, 1, cp - 1); val = trim(substr(tok, cp + 1))
    if (kind == "session") { if (val in isdone) print "F\tL1\t" eline "\t" title }
    else if (kind == "date") {
      if (val ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { gsub(/-/, "", val); if (val + 0 <= today + 0) print "F\tL1\t" eline "\t" title }
    }
    else if (kind == "exists") { if (val != "") print "X\t" eline "\t" val "\t" title }
    else {
      p = 0; q = val
      while ((i = index(q, " @ ")) > 0) { p += i; q = substr(q, i + 1) }
      if (p > 0) {
        re = trim(substr(val, 1, p - 1)); path = trim(substr(val, p + 3))
        if (re != "" && path != "") print "G\t" eline "\t" substr(kind, 7) "\t" path "\t" re "\t" title
      }
    }
  }
  if (plan != "") for (i = 1; i <= ndone; i++) if (hasword(untyped, doneid[i])) { print "F\tL1b\t" eline "\t" title; break }
}
function flush() {
  if (!inent) return
  if (closed) nclosed++
  else {
    nopen++
    if (lab) nlab++; else nleg++
    if (trig == "") notrig++
    else { if (tolower(trig) ~ /nothing named/) nnoth++; emit_trigger() }
  }
  inent = 0
}
function done_line(s,   p, r, tok, i, head, chk) {
  p = index(s, ":")
  head = (p > 0) ? substr(s, 1, p - 1) : s
  if (hasword(head, "uncommitted") || hasword(head, "PARTIAL") || hasword(head, "except") || hasword(head, "pending")) {
    print "F\tL3\t" FNR "\t" clean(s)
  } else if (p == 0) {
    print "F\tL3\t" FNR "\tno check after DONE"
  } else {
    chk = substr(s, p + 1)
    if (chk ~ /^[ \t]*$/) { pend = 1; pline = FNR; ptext = clean(s) }
    else closed = 1
  }
  r = $0
  while (match(r, /`[0-9a-f]+`/)) {
    tok = substr(r, RSTART + 1, RLENGTH - 2); r = substr(r, RSTART + RLENGTH)
    if (length(tok) >= 7 && length(tok) <= 40) print "S\t" FNR "\t" tok "\t" clean(s)
  }
  for (i = 1; i <= nrow; i++)
    if (rowst[rowid[i]] !~ /^DONE/ && hasword($0, rowid[i])) { print "F\tF5\t" FNR "\t" clean(s); break }
}
pend {
  pend = 0; u = $0; sub(/^[ \t]+/, "", u); sub(/^- /, "", u); sub(/^\*\*/, "", u)
  if ($0 ~ /^[ \t]*$/ || $0 ~ /^(- |#)/ || u ~ /^(DONE|Deferred:|Cost:|Forced by:|Probe:|Source:)/) print "F\tL3\t" pline "\t" ptext
  else closed = 1
}
/^#/ { flush(); next }
/^- / {
  flush(); inent = 1; eline = FNR; closed = 0; lab = 0; trig = ""
  title = substr($0, 3); gsub(/\*\*/, "", title); title = clean(trim(title))
}
inent {
  s = $0; sub(/^[ \t]+/, "", s); sub(/^- /, "", s); sub(/^\*\*/, "", s)
  if (s ~ /^DONE/) done_line(s)
  else if ($0 ~ /^- \*\*[^*]+\*\*[[:space:]]+\*\*DONE/) closed = 1
  t = $0; sub(/^[ \t]+/, "", t)
  if (t ~ /^Deferred:/ || t ~ /^Forced by:/) lab = 1
  if (t ~ /^Forced by:/) trig = $0
  else if (trig == "") {
    lw = tolower($0)
    if (hasword(lw, "forced by") || hasword(lw, "would force") || hasword(lw, "forcing")) trig = $0
  }
}
END { if (pend) print "F\tL3\t" pline "\t" ptext; flush(); print "C\t" nopen "\t" nlab "\t" notrig "\t" nnoth "\t" nleg "\t" nclosed }
'

IS_GIT=0
git -C "$D" rev-parse --git-dir >/dev/null 2>&1 && IS_GIT=1
REVLIST=""
if [ "$IS_GIT" = 1 ]; then
  REVLIST="$(mktemp 2>/dev/null)" || REVLIST=""
  if [ -n "$REVLIST" ]; then
    git -C "$D" rev-list HEAD > "$REVLIST" 2>/dev/null || { rm -f "$REVLIST"; REVLIST=""; IS_GIT=0; }
  else
    IS_GIT=0
  fi
fi
trap '[ -n "$REVLIST" ] && rm -f "$REVLIST"' EXIT
DETAILS=""
NDET=0
COUNTS=""
add() {
  NDET=$((NDET + 1))
  [ "$NDET" -le 6 ] && DETAILS="${DETAILS}agent-tiers ledger: $1 $NAME:$2: $3
"
}

while IFS= read -r L; do
  [ -n "$L" ] || continue
  if [ ! -r "$L" ]; then note "unreadable $L"; continue; fi
  NAME="$(basename "$L")"
  nl="$(wc -l < "$L" | tr -d ' ')"; nb="$(wc -c < "$L" | tr -d ' ')"
  if [ "$nl" -gt 1500 ] || [ "$nb" -gt 150000 ]; then
    add L5 1 "over cap ($nl lines, $nb bytes): move closed entries older than 14 days to ${NAME%.md}-archive.md (STATUS: ARCHIVE), DONE lines verbatim"
  fi
  RECS="$(plan="$PLAN" today="$TODAY" awk "$AWK_PROG" "$L" 2>/dev/null)" || { note "awk failed on $NAME"; continue; }
  while IFS="$TAB" read -r kind a b c d e f; do
    case "$kind" in
      F) add "$a" "$b" "$c" ;;
      X) [ -e "$D/$b" ] && add L1 "$a" "$c" ;;
      G) n="$(grep -cE -- "$d" "$D/$c" 2>/dev/null)" || true
         [ "${n:-0}" -ge "$b" ] 2>/dev/null && add L1 "$a" "$e" ;;
      S) [ "$IS_GIT" = 1 ] || continue
         grep -q "^$b" "$REVLIST" 2>/dev/null || add L4 "$a" "$b not in HEAD history: $c" ;;
      C) COUNTS="${COUNTS}agent-tiers ledger: $NAME open $a, labelled $b, no trigger $c, nothing-named $d, legacy $e, closed $f
" ;;
    esac
  done <<EOF
$RECS
EOF
done <<EOF
$LEDGERS
EOF

CTX="$DETAILS"
[ "$NDET" -gt 6 ] && CTX="${CTX}agent-tiers ledger: +$((NDET - 6)) more
"
CTX="$CTX$COUNTS"
CTX="$(printf '%s' "$CTX" | sed '/^$/d')"
[ -n "$CTX" ] || exit 0
jq -n --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null || note "jq emit failed"
exit 0

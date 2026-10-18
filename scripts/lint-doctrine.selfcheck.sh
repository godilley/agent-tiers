#!/usr/bin/env sh
# kit-scope: shared
# Self-check for lint-doctrine.sh check 9 (the M1 meta-gate) and check 12 (case pattern without its
# leading ( inside a $( ), run through `lint-doctrine.sh --case-parens`).
#
# Scoped to checks 9 and 12 deliberately: the others predate this file and are exercised by the doctrine
# they run against on every commit, while these are new and their whole claim is that they CAN fail. A check
# that only ever passes on the real tree gates nothing (the wave's P6), so each case below mutates a
# fixture and asserts the exact line changes.
#
# The lint takes the doctrine file as $1 and derives cards/ from it, so a fixture tree is all that is
# needed. KIT_ROOT still resolves from the script location, which is what case 1 relies on: the
# phantom name it plants is absent from the real scripts/ and scripts/lib/.
# State sandboxing: one mktemp -d, no --stamp, nothing writes the real kit.
set -u

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
LINT="$SCRIPTS/lint-doctrine.sh"
[ -f "$LINT" ] || { echo "FAIL: lint-doctrine.sh not found"; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

# The fixture needs the COLD marker (the lint exits 2 without it) and a cards dir.
FIX="$T/skills/agent-tiers"
mkdir -p "$FIX/cards"
build() { # $1 = extra line appended to the fixture doctrine body
  cat > "$FIX/SKILL.md" <<EOF
# fixture doctrine
*doctrine-v1 c=0-0*

### SC-1.1 - a rule
Body. Enforced by \`lint-doctrine.sh\`.
$1

Everything below is COLD REFERENCE
cold body.
EOF
  printf '# fixture card\n*card-v1 c=0-0*\n\n## MAINT-1 - a card rule\nBody.\n' > "$FIX/cards/MAINT.md"
}
# grep only the check-9 lines: a fixture legitimately fails the stamp and version-bump checks.
ghost_line() { printf '%s\n' "$1" | grep -a 'named in doctrine exists\|names a script that is absent'; }
gap_line()   { printf '%s\n' "$1" | grep -a 'enforcement gap\|states a rule is unenforced'; }

run() { bash "$LINT" "$FIX/SKILL.md" 2>&1; }

# --- case 1: a doctrine-named script that does not exist is caught ---------------------------------
# Fails if a renamed or deleted guard can be left named in doctrine, which asserts enforcement that
# is gone - the exact claim nothing else in the kit compares.
build 'See \`phantom-guard.sh\` for the mechanism.'
out="$(run)"
ghost_line "$out" | grep -q '^FAIL' || fail "case 1: absent script name not caught"
# the finding detail is the line AFTER the header, so assert against the whole output
printf '%s\n' "$out" | grep -qa 'phantom-guard.sh' || fail "case 1: finding does not name the script"

# --- case 2: control - the same shape with a real script passes ------------------------------------
# Fails if case 1 passes for any reason other than the name being absent.
build 'See \`lint-doctrine.sh\` for the mechanism.'
out="$(run)"
ghost_line "$out" | grep -q '^ok' || fail "case 2: a real script name was reported absent"

# --- case 3: an unmarked enforcement gap is caught -------------------------------------------------
# This is MEMORY-5's original shape: doctrine admitting in prose that nothing enforces it.
build 'Stated ceiling: nothing enforces this at write time.'
out="$(run)"
gap_line "$out" | grep -q '^FAIL' || fail "case 3: unmarked enforcement gap not caught"

# --- case 4: the marker satisfies it ---------------------------------------------------------------
# Fails if the marker is not actually the escape, which would make the check unfixable and get it
# deleted rather than obeyed.
build 'Stated ceiling, no-hook: a read leaves no tool call to gate.'
out="$(run)"
gap_line "$out" | grep -q '^ok' || fail "case 4: no-hook: marker did not satisfy the check"

# --- case 5: a quoted phrase is reporting, not claiming --------------------------------------------
# MEMORY-5's status paragraph quotes its own historical wording; treating that as a live claim would
# force a marker onto a rule that IS hooked. Disclosed ceiling: quoting the phrase evades check 9.
build 'It shipped with an explicit "nothing enforces this" and a falsifier.'
out="$(run)"
gap_line "$out" | grep -q '^ok' || fail "case 5: a quoted historical phrase was treated as a live claim"

# --- case 6: both halves report on a clean fixture -------------------------------------------------
# Fails if check 9 can silently produce no line at all, which is indistinguishable from a pass.
build 'Body only.'
out="$(run)"
[ -n "$(ghost_line "$out")" ] || fail "case 6: check 9a printed nothing"
[ -n "$(gap_line "$out")" ] || fail "case 6: check 9b printed nothing"
# the fixture's c=0-0 stamp fails check 5, so the full run must exit non-zero: a lint that prints FAIL
# and exits 0 gates nothing (a dropped final `exit $rc` did exactly that once)
bash "$LINT" "$FIX/SKILL.md" >/dev/null 2>&1 && fail "case 6: full run printed findings but exited 0"

# ===== check 12: case pattern without its leading ( inside a $( ) ==================================
# Fixtures are written by a quoted heredoc (FIXEND, since a fixture may itself hold a line "EOF"), then
# scanned with `--case-parens`, which runs only check 12 and never reads the doctrine.
W() { cat > "$T/$1.sh"; }
# finding lines are "<file>:<n>: <text>"; print the n values, space separated
lines_of() { bash "$LINT" --case-parens "$1" 2>&1 | sed -n 's/^[^:]*:\([0-9][0-9]*\): .*/\1/p' | tr '\n' ' '; }
flags() { # $1 = case name, $2 = fixture, $3 = exact expected line numbers (space separated)
  got="$(lines_of "$2")"
  [ "$got" = "$3 " ] || fail "$1: expected flags at line(s) [$3], got [$got]"
  bash "$LINT" --case-parens "$2" >/dev/null 2>&1 && fail "$1: flagged fixture exited 0"
  bash "$LINT" --case-parens "$2" 2>&1 | grep -q '^FAIL case pattern without' || fail "$1: no FAIL line"
}
passes() { # $1 = case name, $2 = fixture
  out="$(bash "$LINT" --case-parens "$2" 2>&1)" && rc12=0 || rc12=$?
  [ "$rc12" -eq 0 ] || fail "$1: clean fixture exited $rc12"
  printf '%s\n' "$out" | grep -q '^ok  every case pattern inside a command substitution' || fail "$1: no ok line"
}

# --- case 7 (a): a top-level bare pattern is legal and must not be flagged -------------------------
# Fails if the scanner flags every bare pattern, which would make the check unusable.
W a <<'FIXEND'
case "$x" in
  R) echo a ;;
esac
FIXEND
passes "case 7 (a)" "$T/a.sh"

# --- case 8 (b): multi-line bare pattern inside $( ) is flagged at the pattern line ----------------
# Fails if the original reach-guard shape (bare R) in a multi-line substitution) goes unnoticed.
W b <<'FIXEND'
out="$(case "$x" in
  R)
    echo a ;;
esac)"
FIXEND
flags "case 8 (b)" "$T/b.sh" "2"

# --- case 9 (c): the same with parenthesised patterns passes ---------------------------------------
# Fails if the fix the FAIL line recommends is not accepted.
W c <<'FIXEND'
out="$(case "$x" in
  (R)
    echo a ;;
  (*)
    echo b ;;
esac)"
FIXEND
passes "case 9 (c)" "$T/c.sh"

# --- case 10 (d): the one-line form is flagged ----------------------------------------------------
# Fails if the scanner only looks at patterns that start a line.
W d <<'FIXEND'
out="$(case "$x" in R) echo a ;; *) echo b ;; esac)"
FIXEND
flags "case 10 (d)" "$T/d.sh" "1"

# --- case 11 (e): a case nested in a substitution nested in double quotes is flagged ----------------
# Fails if a $( inside double quotes is not read as opening a frame.
W e <<'FIXEND'
out="$(echo "$(case "$x" in
  R) echo a ;;
esac)")"
FIXEND
flags "case 11 (e)" "$T/e.sh" "2"

# --- case 12 (f): frame depth is restored after an inner substitution closes -----------------------
# Fails if closing the inner "$(case ... (a) ...)" resets the depth to 0 (the later bare pattern is
# still inside the outer $( ) and must be flagged, and only it).
W f <<'FIXEND'
x="$(
  echo "$(case "$y" in (a) echo 1 ;; esac)"
  case "$z" in
    R) echo 2 ;;
  esac
)"
FIXEND
flags "case 12 (f)" "$T/f.sh" "4"

# --- case 13 (g): a ) in single quotes, double quotes and a comment does not close the frame -------
# Fails if the scanner counts those parens (it would close the substitution early and miss line 3).
W g <<'FIXEND'
x="$(echo ')' ")" # )
  case "$z" in
    R) echo 2 ;;
  esac
)"
FIXEND
flags "case 13 (g)" "$T/g.sh" "3"

# --- case 14 (h): a ( in single quotes, double quotes and a comment does not keep the frame open ---
# Fails if the scanner counts those parens (the frame never closes and the top-level case is over-flagged).
W h <<'FIXEND'
x="$(echo '(' "(" # (
)"
case "$z" in
  R) echo 2 ;;
esac
FIXEND
passes "case 14 (h)" "$T/h.sh"

# --- case 15 (i): a substitution inside an arm body, then a bare next pattern -----------------------
# Fails if the body's own $( ) or its ;; confuses the arm state (flag must be line 3 only).
W i <<'FIXEND'
x="$(case "$z" in
  (a) y="$(echo hi)" ;;
  R) echo 2 ;;
esac)"
FIXEND
flags "case 15 (i)" "$T/i.sh" "3"

# --- case 16 (j): heredoc content is not scanned ----------------------------------------------------
# Fails if an unbalanced $( or an R) line inside a heredoc body leaks into the parse.
W j <<'FIXEND'
cat <<'EOF'
R)
echo $(
EOF
case "$z" in
  R) echo 2 ;;
esac
FIXEND
passes "case 16 (j)" "$T/j.sh"

# --- case 17 (k): exit codes -------------------------------------------------------------------------
# Fails if --case-parens does not signal findings through its exit status (1 flagged, 0 clean).
bash "$LINT" --case-parens "$T/b.sh" >/dev/null 2>&1; r1=$?
bash "$LINT" --case-parens "$T/c.sh" >/dev/null 2>&1; r0=$?
[ "$r1" -eq 1 ] || fail "case 17 (k): flagged fixture exit $r1, want 1"
[ "$r0" -eq 0 ] || fail "case 17 (k): clean fixture exit $r0, want 0"

# --- case 18 (l): the full normal run scans real files and says so ---------------------------------
# Fails if the full-run path can silently scan zero files (an unanchored grep would pass on that). The
# line must be the ok line with a positive file count, or a FAIL line (which also proves files were read).
build 'Body only.'
out="$(run)"
n18="$(printf '%s\n' "$out" | sed -n 's/^ok  every case pattern.*(\([0-9][0-9]*\) files)$/\1/p')"
if [ -z "$n18" ]; then
  printf '%s\n' "$out" | grep -q '^FAIL case pattern without' || fail "case 18 (l): normal run printed no check-12 ok/FAIL line"
else
  [ "$n18" -gt 0 ] || fail "case 18 (l): normal run scanned 0 files"
fi

# --- case 19 (m): a shift-left inside $(( )) is not a heredoc ---------------------------------------
# Fails if the "<<" guard for arithmetic frames is removed: the misread heredoc would swallow the
# lines after it and the bare pattern on line 3 would go unflagged.
W m <<'FIXEND'
x=$(( 1 << 2 ))
y="$(case "$z" in
R) ;;
esac)"
FIXEND
flags "case 19 (m)" "$T/m.sh" "3"

# --- case 20 (n): the incident shape: bare patterns in a while loop inside $( ) --------------------
# Fails if the original reach-guard shape (R) and *) inside a pipeline substitution) is not flagged.
W n <<'FIXEND'
out="$(printf 'R a\n' | while read -r k id; do
  case "$k" in
    R)
      printf 'R %s\n' "$id" ;;
    *) printf 'x\n' ;;
  esac
done)"
FIXEND
flags "case 20 (n)" "$T/n.sh" "3 5"

# --- case 21 (o): a <<- heredoc with a tab-indented delimiter ends at that line --------------------
# Fails if leading tabs are not stripped for <<-: the body never ends and the bare pattern is swallowed.
printf 'x="$(cat <<-EOF\n\ttext\n\tEOF\ncase "$z" in\n  R) echo 2 ;;\nesac\n)"\n' > "$T/o.sh"
flags "case 21 (o)" "$T/o.sh" "5"

# --- case 22 (p): a heredoc inside $( ) whose closing ) comes after the delimiter line -------------
# Fails if the delimiter line is missed at the heredoc's own depth, or the ) after it does not close
# the frame (line 5 is still inside the substitution and must be flagged).
W p <<'FIXEND'
x="$(cat <<EOF
body
EOF
case "$z" in
  R) echo 2 ;;
esac
)"
FIXEND
flags "case 22 (p)" "$T/p.sh" "5"

# --- case 23 (q): process substitution opens a frame -------------------------------------------------
# Fails if "<(" is not treated like "$(" (bash 3.2 dies on this file).
W q <<'FIXEND'
while read x; do echo "got=$x"; done < <(case a in
  a) echo A ;;
esac)
FIXEND
flags "case 23 (q)" "$T/q.sh" "2"

# --- case 24 (r): an unquoted heredoc body is scanned for $( ) ---------------------------------------
# Fails if every heredoc body is skipped: bash 3.2 does parse the $( ) in an unquoted body.
W r <<'FIXEND'
cat <<END
v=$(case a in
  a) echo A ;;
esac)
END
FIXEND
flags "case 24 (r)" "$T/r.sh" "3"

# --- case 25 (s): a quoted heredoc body with the same text is not scanned ---------------------------
# Control for case 24: only the delimiter quoting differs.
W s <<'FIXEND'
cat <<'END'
v=$(case a in
  a) echo A ;;
esac)
END
FIXEND
passes "case 25 (s)" "$T/s.sh"

# --- case 26 (t): an apostrophe in an unquoted body does not desync later lines ----------------------
# Fails if quotes are honoured inside an unquoted body (the apostrophe would swallow line 5).
W t <<'FIXEND'
cat <<EOF
it's fine
EOF
x="$(case "$z" in
  R) echo 2 ;;
esac)"
FIXEND
flags "case 26 (t)" "$T/t.sh" "5"

# --- case 27 (u): an unreadable file is an error, not an ok -----------------------------------------
# Fails if --case-parens on a missing file reports ok / exit 0 (it must be exit 2 plus a message).
err="$(bash "$LINT" --case-parens "$T/nope.sh" 2>&1 >/dev/null)"; r2=$?
[ "$r2" -eq 2 ] || fail "case 27 (u): missing file exit $r2, want 2"
printf '%s\n' "$err" | grep -q '^lint: cannot read ' || fail "case 27 (u): no 'cannot read' message"

if [ "$fails" -eq 0 ]; then echo "PASS lint-doctrine checks 9+12: 27/27 cases"; exit 0; fi
printf '%d case(s) failed\n' "$fails"; exit 1

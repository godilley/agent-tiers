#!/usr/bin/env sh
# kit-scope: shared
# Self-check for lint-doctrine.sh check 9 (the M1 meta-gate).
#
# Scoped to check 9 deliberately: checks 1-8 predate this file and are exercised by the doctrine they
# run against on every commit, while check 9 is new and its whole claim is that it CAN fail. A check
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

if [ "$fails" -eq 0 ]; then echo "PASS lint-doctrine check 9: 6/6 cases"; exit 0; fi
printf '%d case(s) failed\n' "$fails"; exit 1

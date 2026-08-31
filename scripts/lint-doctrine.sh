#!/usr/bin/env bash
# kit-scope: shared
# lint-doctrine.sh - agent-tiers v4.1 drift lint (single-owner + self-sufficiency enforcement).
# Splits the SKILL at the COLD REFERENCE marker, and treats each cards/*.md as a single-owner POLICY CARD.
# Checks:
#   1. duplicate rule-id DEFINITIONS across the hot Spawn Contract (`SC-x.y`) AND the policy cards
#      (`## XLAB-n` / `## BOSS-n` / `## MAINT-n` / `## HOST-n` headers) - each rule owned in exactly one place
#   2. broken anchors: a "see <ID>" reference (SC- or card-id) whose id is not defined anywhere
#   3. modal verbs (MUST/NEVER/ALWAYS/REQUIRES/ONLY/GATED/STOP) in COLD SKILL prose NOT carrying an id pointer
#      (a normative sentence living in cold rationale = a rule that should move to its owner or become a pointer)
#   6. no guard deny/ask reason (any non-comment line of scripts/*.sh, selfchecks/fixtures excluded) contains
#      one of cc-gui's ten permission-signal substrings - a match makes cc-gui rewrite the row into a generic
#      "mode policy" card and DROP the hook's reason (RENDER-MAP 2026-08-16); a miss at least stays honest.
#      Was a recorded "0 hits, 2026-08-16"; a recorded number is not a check (MASTER B5).
#   7. agents/*.md: every `def-v<M>` quoted in prose (the check-in line) equals the file's `def-version: N` -
#      the cksum stamp catches edit-without-bump; this catches bump-without-updating-the-check-in (MASTER B6).
#      Deliberately strict: an agent file may quote NO def-v number but its own (keep examples version-free).
# Exit 0 = clean; exit 1 = findings. Checks 1-2 are hard (block); check 3 is a shrinking baseline during v4.1.
#
# Deliberately bash (arrays/pipefail); everything else in scripts/ is POSIX sh. `sh scripts/lint-doctrine.sh`
# previously died rc 2 "Illegal option -o pipefail" - the same rc as file-not-found (cold-review F6). Re-exec
# under bash so the doc-quoted bare invocation works from any shell.
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail
# The KIT is shared across Claude profiles; only the flattened view follows CLAUDE_CONFIG_DIR. So resolve
# the kit from THIS script's location, never from the profile config dir - under a second profile the
# latter points at a directory with no kit in it and every invocation dies "file not found".
KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# `--stamp` REWRITES every provenance cksum instead of checking them; it is the one-command fix for a
# check-5 finding, so the drift is machine-repaired rather than hand-computed.
STAMP_MODE=0
if [ "${1:-}" = "--stamp" ]; then STAMP_MODE=1; shift; fi
FILE="${1:-$KIT_ROOT/skills/agent-tiers/SKILL.md}"
CARDS_DIR="$(dirname "$FILE")/cards"
MARKER="Everything below is COLD REFERENCE"
[ -f "$FILE" ] || { echo "lint: file not found: $FILE" >&2; exit 2; }
CUT=$(grep -n "$MARKER" "$FILE" | head -1 | cut -d: -f1 || true)
[ -n "$CUT" ] || { echo "lint: COLD marker not found" >&2; exit 2; }

HOT=$(sed -n "1,${CUT}p" "$FILE")
COLD=$(sed -n "$((CUT+1)),\$p" "$FILE")
CARDS=""
[ -d "$CARDS_DIR" ] && CARDS=$(cat "$CARDS_DIR"/*.md 2>/dev/null || true)
rc=0

# --- id definitions ---------------------------------------------------------
# hot: `SC-N.N` in backticks at LINE START (optionally as a bullet) = a definition; a mid-line
# backticked id is a REFERENCE, not a definition (e.g. SC-4.2's "instrument for `SC-6.1`").
# The trailing [a-z]? matters: sub-rules like SC-5.3a/SC-6.1a were INVISIBLE to this lint, so they got
# no duplicate-definition enforcement, and a `see SC-5.3a` reference prefix-matched SC-5.3 and passed.
sc_defs=$(printf '%s\n' "$HOT" | grep -oE '^[[:space:]]*(- )?`SC-[0-9]+\.[0-9]+[a-z]?`' | grep -oE 'SC-[0-9]+\.[0-9]+[a-z]?' | sort || true)
card_defs=$(printf '%s\n' "$CARDS" | grep -oE '^#{1,6} (XLAB|BOSS|MAINT|HOST|ROUTE)-[0-9]+' | grep -oE '(XLAB|BOSS|MAINT|HOST|ROUTE)-[0-9]+' | sort || true)
all_defs=$(printf '%s\n%s\n' "$sc_defs" "$card_defs" | grep -E '.' | sort || true)

# 1. duplicate definitions (across hot + cards)
dups=$(printf '%s\n' "$all_defs" | uniq -d || true)
if [ -n "$dups" ]; then echo "FAIL dup rule-id definitions:"; printf '  %s\n' $dups; rc=1
else echo "ok  no duplicate rule-id definitions"; fi

# 2. broken anchors. Every "see <ID>" referenced anywhere must be defined.
defined=$(printf '%s\n' "$all_defs" | sort -u || true)
referenced=$(printf '%s\n' "$HOT" "$COLD" "$CARDS" \
  | grep -oE 'see (SC-[0-9]+\.[0-9]+[a-z]?|(XLAB|BOSS|MAINT|HOST|ROUTE)-[0-9]+)' \
  | grep -oE '(SC-[0-9]+\.[0-9]+[a-z]?|(XLAB|BOSS|MAINT|HOST|ROUTE)-[0-9]+)' | sort -u || true)
broken=""
for r in $referenced; do printf '%s\n' "$defined" | grep -qx "$r" || broken="$broken $r"; done
if [ -n "$broken" ]; then echo "FAIL broken anchors (referenced, never defined):"; printf '  %s\n' $broken; rc=1
else echo "ok  no broken anchors"; fi

# 4. Skill description budget. Anthropic documents a 1024-char max for a skill `description:`; over it
#    the description can be rejected or truncated, i.e. the skill silently stops triggering - the worst
#    kind of failure, because nothing errors. F-3 shipped at 1052 chars because nothing measured it.
#    The description is a TRIGGER GATE, not a table of contents; if it needs 1024 chars, it is a TOC.
DESC_MAX=1024
SKILLS_DIR="$(dirname "$(dirname "$FILE")")"
desc_bad=""
for sk in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$sk" ] || continue
  n=$(awk '
    /^description:/ { f=1; sub(/^description:[[:space:]]*/,""); sub(/^>-?[[:space:]]*/,"");
                      if (length($0)) buf=$0; next }
    f && /^[^[:space:]]/ { f=0 }
    f { sub(/^[[:space:]]+/,""); sub(/[[:space:]]+$/,"");
        if (length($0)) { buf = (length(buf) ? buf " " $0 : $0) } }
    END { print length(buf) }' "$sk")
  [ "${n:-0}" -gt "$DESC_MAX" ] && desc_bad="$desc_bad $(basename "$(dirname "$sk")"):${n}"
done
if [ -n "$desc_bad" ]; then
  echo "FAIL skill description over ${DESC_MAX} chars (may stop the skill triggering):"; printf '  %s\n' $desc_bad; rc=1
else echo "ok  all skill descriptions within ${DESC_MAX} chars"; fi

# 3. modal verbs in COLD SKILL prose without an id pointer (baseline -> 0 as cards land).
# A line carrying any SC-/card-id token is a pointer or a quoted rule title (exempt).
modal=$(printf '%s\n' "$COLD" | grep -nE '\b(MUST|NEVER|ALWAYS|REQUIRES|ONLY|GATED|STOP)\b' \
  | grep -vE '(SC|XLAB|BOSS|MAINT|HOST|ROUTE)-[0-9]' || true)
count=$(printf '%s' "$modal" | grep -c . || true)
echo "info cold-prose modal-verb lines (target: 0 as cards land): $count"
[ -n "$modal" ] && printf '%s\n' "$modal" | sed 's/^/  cold:/'

# 5. Provenance-stamp drift. MAINT-2 says bump `card-v` / `def-version` on every normative edit, and the
# doctrine now carries `doctrine-v` too. Measured 2026-08-04: every kit obligation discharged by a program
# was current and every one discharged by an agent remembering was stale (def-v4/v7/v11; MAINT-6 shipped
# without its bump). So the bump is no longer a memory test - the stamp line CARRIES the cksum of its own
# file (that line excluded), and this check recomputes it. Edit without bumping and the mismatch is
# mechanical, not a matter of anyone noticing. `--stamp` rewrites them all.
STAMP_RE='(card-v[0-9]+|def-version: [0-9]+|doctrine-v[0-9]+)'
stamp_hash() { grep -vE "$STAMP_RE c=" "$1" 2>/dev/null | cksum | awk '{print $1"-"$2}'; }
stamp_write() { # $1=file $2=value  (inserts c= if absent, replaces it if present)
  awk -v val="$2" -v re="$STAMP_RE" '
    !seen && match($0, re) {
      head = substr($0, 1, RSTART + RLENGTH - 1); tail = substr($0, RSTART + RLENGTH)
      sub(/^ c=[0-9]+-[0-9]+/, "", tail)
      $0 = head " c=" val tail; seen = 1
    } { print }' "$1" > "$1.lintmp" && mv -f "$1.lintmp" "$1"
}
STAMPED="$FILE"
[ -d "$CARDS_DIR" ] && STAMPED="$STAMPED $(ls "$CARDS_DIR"/*.md 2>/dev/null || true)"
[ -d "$KIT_ROOT/agents" ] && STAMPED="$STAMPED $(ls "$KIT_ROOT"/agents/*.md 2>/dev/null || true)"
if [ "$STAMP_MODE" = 1 ]; then
  for f in $STAMPED; do
    [ -f "$f" ] || continue
    stamp_write "$f" "0-0"; stamp_write "$f" "$(stamp_hash "$f")"
    echo "  stamped $(basename "$f")"
  done
  echo "ok  provenance cksums rewritten - re-run without --stamp to verify"
else
  drift=""
  for f in $STAMPED; do
    [ -f "$f" ] || continue
    have=$(grep -oE "$STAMP_RE c=[0-9]+-[0-9]+" "$f" 2>/dev/null | head -1 | sed 's/.* c=//' || true)
    [ -n "$have" ] || { drift="$drift $(basename "$f"):no-stamp"; continue; }
    [ "$have" = "$(stamp_hash "$f")" ] || drift="$drift $(basename "$f"):changed-since-stamp"
  done
  if [ -n "$drift" ]; then
    echo "FAIL provenance stamp drift (bump the version, then: lint-doctrine.sh --stamp):"
    printf '  %s\n' $drift; rc=1
  else echo "ok  provenance stamps match file contents"; fi
fi

# --- 6. cc-gui permission-signal substrings in guard reasons ------------------------------------
CCGUI_SIGNALS="requires approval|requested permissions|haven't granted it yet|have not granted it yet|permission denied|requires permission|blocked for security|blocked\. for security|allowed working directories|may only write to files"
sig_hits=""
for f in "$KIT_ROOT"/scripts/*.sh; do
  case "$f" in *.selfcheck.sh|*/lint-doctrine.sh) continue ;; esac   # self: declares the patterns (glob is non-recursive, fixtures/ never listed)
  # number on the FILE, then drop comment lines - numbering a comment-stripped stream pointed at the wrong line
  h=$(grep -aniE "$CCGUI_SIGNALS" "$f" | grep -avE '^[0-9]+:[[:space:]]*#' | cut -c1-120 | sed "s|^|  $(basename "$f"):|" || true)
  [ -n "$h" ] && sig_hits="$sig_hits
$h"
done
if [ -n "$sig_hits" ]; then
  echo "FAIL guard reason text contains a cc-gui permission-signal substring (the host would drop the reason and show a generic card):"
  printf '%s\n' "$sig_hits" | grep -av '^$'; rc=1
else echo "ok  no guard reason carries a cc-gui permission-signal substring"; fi

# --- 7. def-version <-> check-in def-v<N> ---------------------------------------------------------
defv_drift=""
for f in "$KIT_ROOT"/agents/*.md; do
  [ -f "$f" ] || continue
  n=$(grep -oE 'def-version: [0-9]+' "$f" | head -1 | grep -oE '[0-9]+' || true)
  [ -n "$n" ] || continue   # unstamped files are check 5's business
  quoted=$(grep -oE 'def-v[0-9]+' "$f" | sort -u | tr '\n' ' ')
  [ "$quoted" = "def-v$n " ] || defv_drift="$defv_drift $(basename "$f"):def-version=$n,quoted=[${quoted% }]"
done
if [ -n "$defv_drift" ]; then
  echo "FAIL def-version and the check-in's quoted def-v<N> disagree (bump both in the same edit):"
  printf '  %s\n' $defv_drift; rc=1
else echo "ok  every agent check-in quotes its own def-version"
fi

# --- 8. bash-3.2 parse hazard: an apostrophe in a `#` comment INSIDE a multi-line $( ) -------------
# macOS /bin/sh is bash 3.2, which pre-scans a command-substitution body for its closing paren with a
# scanner that mis-tokenises comments: an apostrophe there reads as an opening quote and the script
# fails to PARSE. A PreToolUse exit 2 is a BLOCKING error, so on a Mac the guard fail-CLOSES the whole
# session rather than missing a deny (measured 2026-08-16, dangerous-actions-blocker.sh). The rule has
# been prose plus origin-only CI ever since; this is its arrival event. It tracks `$(` nesting by
# counting parens per line, so an over-flag is possible and costs one deleted apostrophe, while the
# failure it prevents costs a whole session on the other host.
# DISCLOSED MISSES (opus reviewer 2026-08-23 - accurate, not aspirational): any `)` in the body zeroes
# the depth, so a `case` pattern, a `()` in a function definition, or a `)` inside a quoted awk/sed
# program closes a body that is still open and every comment after it goes unchecked. That is not
# hypothetical in this kit - guard_norm_add_paths exists BECAUSE people write a `case` inside a `$( )`.
# Backtick substitutions are not tracked at all. So a clean run here is evidence, not proof; the macOS
# CI leg remains the real backstop.
hz=0
for f in "$KIT_ROOT"/scripts/*.sh; do
  case "$f" in *.selfcheck.sh|*/lint-doctrine.sh) continue ;; esac
  # the apostrophe arrives as a VARIABLE: `\x27` in an ERE is a GNU extension (mawk/BSD awk read it
  # literally and the check silently never fires), and the program itself is single-quoted here.
  out="$(awk -v q='\047' '
    { line = $0
      # depth BEFORE this line decides whether a comment here sits inside a $( ) body
      # `[ \t]`, not [[:space:]]: the POSIX class in an awk ERE is not universal (older mawk and BWK awk
      # read it as a literal character set, and this check then silently matches nothing - the same
      # silent-no-op failure the q-as-a-variable note above avoids). A trailing comment is the same
      # bash 3.2 hazard as a whole-line one, so both are examined.
      if (depth > 0 && index(line, q) > 0) {
        hashpos = index(line, "#")
        if (hashpos > 0 && index(substr(line, hashpos), q) > 0) { printf "%s:%d: %s\n", FILENAME, NR, substr(line, 1, 90) }
      }
      n = gsub(/\$\(/, "$(", line); c = gsub(/\)/, ")", line)
      depth += n - c; if (depth < 0) depth = 0
    }
  ' "$f")"
  [ -n "$out" ] && { hz=1; printf '%s\n' "$out"; }
done
if [ "$hz" = 1 ]; then
  echo "FAIL apostrophe in a comment inside a multi-line \$( ) - bash 3.2 (macOS /bin/sh) cannot parse this file; drop the apostrophe"
  rc=1
else
  echo "ok  no apostrophe in a comment inside a command substitution (bash 3.2 parse hazard)"
fi

exit $rc

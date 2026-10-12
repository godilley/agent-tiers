#!/usr/bin/env sh
# kit-scope: shared
# Tiny CLI: prints the `review_gate` value review-gate-guard.sh would enforce for <dir>, and where
# that value came from, so /agent-tiers:doctor (or a human) can see exactly what the guard is
# currently doing without re-deriving its resolution logic a second time. Built on guard_main_top and
# guard_local_scalar - the SAME two functions the guard itself calls - so this can never drift from
# what the guard actually enforces; it is a read-only report, not a parallel implementation.
#
# Usage: review-gate-mode.sh [dir]   (default: .)
# Output: two lines - the resolved value, then "source: <path, or 'built-in default'>".
set -u

DIR="${1:-.}"
SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -z "$SELFDIR" ] || [ ! -f "$SELFDIR/guard-cmdpos.sh" ]; then
  echo "review-gate-mode: cannot find guard-cmdpos.sh next to this script" >&2
  exit 1
fi
BASE="$(cd "$SELFDIR/.." 2>/dev/null && pwd || true)"
. "$SELFDIR/guard-cmdpos.sh"

MAIN_TOP="$(guard_main_top "$DIR" 2>/dev/null || true)"
[ -n "$MAIN_TOP" ] || MAIN_TOP="$DIR"

OUT="$(guard_local_scalar "$MAIN_TOP" review_gate "commit push" commit)"
VAL="$(printf '%s\n' "$OUT" | sed -n 1p)"
REASON="$(printf '%s\n' "$OUT" | sed -n 2p)"

if [ -n "$REASON" ]; then
  SRC="$REASON"
else
  SRC="built-in default"
  for s in "$MAIN_TOP/.claude/agent-tiers.local.md" "${BASE:-/dev/null}/kit-config.md"; do
    [ -f "$s" ] && grep -aq '^review_gate:' "$s" 2>/dev/null && { SRC="$s"; break; }
  done
fi

printf '%s\n' "$VAL"
printf 'source: %s\n' "$SRC"

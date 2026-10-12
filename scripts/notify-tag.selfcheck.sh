#!/usr/bin/env sh
# kit-scope: shared
# Self-check for scripts/lib/notify-tag.sh: every classification (want_input, no_input_required, ask_next,
# mixed, invalid - including "one valid tag but not on the last line" and "the same tag repeated
# twice"), and library hygiene (sourcing must not disturb the caller's own `set -u`, and the
# function body runs in a subshell so its internals never leak into the caller).
set -u
LIB="$(cd "$(dirname "$0")" && pwd)/lib/notify-tag.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

. "$LIB"
command -v notify_tag_classify >/dev/null 2>&1 || fail "sourcing the library did not define notify_tag_classify"

[ "$(notify_tag_classify '')" = "invalid" ] || fail "empty text should classify as invalid"
[ "$(notify_tag_classify "$(printf 'All done.\noperator:want_input')")" = "want_input" ] || fail "a valid want_input tag should classify as want_input"
[ "$(notify_tag_classify "$(printf 'All done.\noperator:no_input_required|reason:waiting on build')")" = "no_input_required" ] || fail "a valid no_input_required tag should classify as no_input_required"
[ "$(notify_tag_classify "$(printf 'Three options.\noperator:ask_next')")" = "ask_next" ] || fail "a valid ask_next tag should classify as ask_next"
[ "$(notify_tag_classify "$(printf 'operator:ask_next\nMore.\noperator:want_input')")" = "mixed" ] || fail "ask_next plus another tag should classify as mixed"
[ "$(notify_tag_classify 'Just some prose, no tag at all.')" = "invalid" ] || fail "no tag at all should classify as invalid"
[ "$(notify_tag_classify "$(printf 'operator:want_input\none more line after it')")" = "invalid" ] || fail "a tag present but not on the actual last line should classify as invalid"
[ "$(notify_tag_classify "$(printf 'operator:no_input_required|reason:earlier stray\nMore text.\noperator:want_input')")" = "mixed" ] || fail "an earlier tag plus a valid one at the end should classify as mixed"
[ "$(notify_tag_classify "$(printf 'operator:want_input\nMore text.\noperator:want_input')")" = "mixed" ] || fail "the same tag repeated twice should still classify as mixed"

# Library hygiene, in a genuinely FRESH `sh -c` each time (opus reviewer, 2026-09-17, LOW: a plain
# `( set -u; ... )` subshell inherits this selfcheck's OWN already-on `set -u` regardless of what
# the library does, so it cannot prove either direction - it would pass even if sourcing the
# library turned `set -u` on itself). Caller-owned vars must survive sourcing + calling, and the
# caller's OWN set -u state must survive unchanged in both directions.
HYG_OUT="$(sh -c '
  re=PRESERVE_RE; count=PRESERVE_COUNT; last=PRESERVE_LAST
  set -u
  . "$1"
  notify_tag_classify "$2" >/dev/null
  if [ "$re" = PRESERVE_RE ] && [ "$count" = PRESERVE_COUNT ] && [ "$last" = PRESERVE_LAST ]; then
    echo VARS_UNCHANGED
  else
    echo "VARS_CLOBBERED re=$re count=$count last=$last"
  fi
  case $- in *u*) echo SET_U_ON ;; *) echo SET_U_OFF ;; esac
' sh "$LIB" "$(printf 'x\noperator:want_input')")"
printf '%s' "$HYG_OUT" | grep -q '^VARS_UNCHANGED$' || fail "sourcing/calling notify-tag.sh clobbered a pre-set caller variable: $HYG_OUT"
printf '%s' "$HYG_OUT" | grep -q '^SET_U_ON$' || fail "notify-tag.sh disturbed the caller's own set -u state: $HYG_OUT"

# A caller that has NOT set -u must not have it switched ON by sourcing either - a genuinely fresh
# shell again, same reason as above.
NOU_OUT="$(sh -c '
  . "$1"
  notify_tag_classify "$2" >/dev/null
  case $- in *u*) echo SET_U_ON ;; *) echo SET_U_OFF ;; esac
' sh "$LIB" "$(printf 'x\noperator:want_input')")"
printf '%s' "$NOU_OUT" | grep -q '^SET_U_OFF$' || fail "notify-tag.sh turned on set -u for a caller that never asked for it: $NOU_OUT"

echo "PASS notify-tag.sh"

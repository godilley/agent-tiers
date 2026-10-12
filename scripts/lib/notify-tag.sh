#!/usr/bin/env sh
# kit-scope: shared
# notify-tag.sh - the ONE place that decides whether a reply's `operator:want_input` /
# `operator:no_input_required|reason:...` / `operator:ask_next` tag is compliant, sourced by both
# notify-tag-guard.sh (which BLOCKS on a non-compliant reply) and notify.sh's Stop branch (which
# decides whether to ping). Extracted after this exact split caused a real live bug, twice: the
# guard and notify.sh each kept their OWN copy of "is this reply tagged correctly", and the two
# copies drifted - first when the guard's fail-open-to-notify case doubled up with the guard's
# forced retry, then again when the guard learned to reject a MIXED signal (an earlier stray tag
# plus a valid one at the end) but notify.sh's copy still only ever looked at the last line, so a
# reply the guard blocked for showing two tags still fired a desktop ping anyway. Two consumers,
# same decision, diverged twice - past the point where keeping two copies in sync by hand is
# credible.
#
# notify_tag_classify TEXT -> stdout: exactly one word.
#   want_input          - TEXT's last line is `operator:want_input`, and no other operator: line
#                          exists anywhere else in TEXT.
#   no_input_required   - same, for `operator:no_input_required|reason:<something>`.
#   ask_next             - same, for `operator:ask_next`: the reply ended on the context for a
#                          decision and the question comes next, via AskUserQuestion, after the
#                          guard sends the turn back. Not a finished turn, so it never pings.
#   mixed                - more than one line anywhere in TEXT matches any tag pattern - a
#                          reply cannot show two badges (or the same one twice) and still mean one
#                          thing.
#   invalid              - anything else: no matching line at all, or exactly one match that is
#                          NOT the actual last line.
#
# notify_tag_regex -> stdout: the one regex both notify_tag_classify and a caller that needs its
# own raw count (notify-tag-guard.sh's block message) should use - opus reviewer, 2026-09-17, LOW:
# the count-only use had re-typed the pattern inline, reopening the exact duplication this file
# exists to end, just for a cosmetic count rather than the decision itself. A FUNCTION, not a
# top-level variable: selfcontainment-check.sh's RULE 2 scans for bare `$VAR` reads and cannot see
# that one comes from this sourced library rather than an external env var - a function call never
# trips that scan, matching how `notify_tag_classify` itself already doesn't.
notify_tag_regex() { printf '%s' '^operator:(want_input|ask_next|no_input_required\|reason:.+)$'; }

# Library hygiene (sourced into a caller's shell): NO top-level `set -u`, and the function body is
# a SUBSHELL so `re`/`count`/`last` never leak into or clobber a same-named caller variable.
# Self-check: notify-tag.selfcheck.sh.
notify_tag_classify() ( # $1 = text to classify
  re="$(notify_tag_regex)"
  count="$(printf '%s' "$1" | grep -acE "$re" 2>/dev/null || true)"
  case "${count:-0}" in
    0) printf 'invalid\n'; exit 0 ;;
    1) ;;
    *) printf 'mixed\n'; exit 0 ;;
  esac
  last="$(printf '%s' "$1" | tail -n 1)"
  if printf '%s' "$last" | grep -aqx 'operator:want_input'; then
    printf 'want_input\n'
  elif printf '%s' "$last" | grep -aqx 'operator:ask_next'; then
    printf 'ask_next\n'
  elif printf '%s' "$last" | grep -aqE '^operator:no_input_required\|reason:.+$'; then
    printf 'no_input_required\n'
  else
    printf 'invalid\n'   # the one match exists but is not the actual last line
  fi
)

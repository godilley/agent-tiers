#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers SHARED library: the one model-id to capability-band map. SOURCED, not executed - a
# consumer sources it with `command .` behind a `-r` test (a plain `.` of a broken copy would end the
# calling hook; see resume-inject.sh's band block) and then calls the functions. Shared by
# resume-inject.sh (SessionStart band line) and a future act-time hook, so the two cannot drift.
# HOST-2 in skills/agent-tiers/cards/HOST.md is the rule this implements.
#
# Every function body is a SUBSHELL (`name() ( ... )`), the same structural choice guard-mempath.sh
# makes: no variable leaks into the calling hook's shell. Consequence: bodies `exit`, not `return`.
#
# Functions:
#   model_band <model-id>        prints one of: absent top reasoning interface unranked
#   model_band_shown <model-id>  prints the id for display; `none` if empty, `unprintable` if it has a
#                                char outside [A-Za-z0-9._:@/[]-] or is over 64 chars (the id comes from
#                                a payload and lands in model context)
#   model_band_line <key> <default-file> [<override-file>]
#                                prints the text for a band: override file first, then the default file,
#                                first VALID `key=text` line wins. Valid: key is a known band, text
#                                non-empty, printable ASCII only, at most 240 chars. Invalid, blank and
#                                `#` lines are skipped silently. No valid line: prints nothing.

model_band() (
  id="${1:-}"
  case "$id" in
    '') echo absent ;;
    *[Ff][Aa][Bb][Ll][Ee]*) echo top ;;
    *[Oo][Pp][Uu][Ss]*) echo reasoning ;;
    *[Ss][Oo][Nn][Nn][Ee][Tt]*|*[Hh][Aa][Ii][Kk][Uu]*) echo interface ;;
    *) echo unranked ;;
  esac
)

model_band_shown() (
  LC_ALL=C
  id="${1:-}"
  [ -n "$id" ] || { echo none; exit 0; }
  case "$id" in
    *[!]A-Za-z0-9._:@/[-]*) echo unprintable; exit 0 ;;
  esac
  [ "${#id}" -le 64 ] || { echo unprintable; exit 0; }
  printf '%s\n' "$id"
)

model_band_line() (
  key="${1:-}"
  for f in "${3:-}" "${2:-}"; do
    [ -n "$f" ] && [ -r "$f" ] || continue
    out="$(LC_ALL=C awk -v k="$key" '
      { sub(/\r$/, "") }
      /^[ \t]*(#|$)/ { next }
      {
        i = index($0, "=")
        if (i < 2) next
        if (substr($0, 1, i - 1) != k) next
        t = substr($0, i + 1)
        if (k !~ /^(reasoning|top|interface|unranked|absent)$/) next
        if (t == "" || length(t) > 240 || t !~ /^[ -~]+$/) next
        print t
        exit
      }' "$f" 2>/dev/null)"
    if [ -n "$out" ]; then printf '%s\n' "$out"; exit 0; fi
  done
  exit 0
)

#!/usr/bin/env sh
# kit-scope: shared
# handback-tag.sh - the ONE place that decides whether a reply hands the operator a `!` command
# without an `operator:run|kind:policy|oneoff` tag above it. Sourced by handback-tag-guard.sh (which
# BLOCKS once per offending reply) and notify.sh's Stop branch (which stays silent while the guard is
# about to block, so an untagged reply does not ping, get sent back, and ping again). Same split and
# same reason as lib/notify-tag.sh: two copies of one decision drift.
#
# handback_tag_scan TEXT -> stdout, one line per hand-back found: `F<line cut to 80>` for an untagged
#   one, `O` for a tagged one. handback_tag_flagged TEXT -> only the untagged lines (empty = clean).
#   handback_tag_count TEXT -> number of hand-backs found (tagged or not).
#
# Detection, line by line, inside and outside code fences (``` and ~~~; a fence closes only on a run
# of the same character at least as long as the opener, so an inner ```lang line in a longer fence is
# content; a line that opens a fence and repeats the fence character later, like ```! ls```, is
# inline code, not a fence):
#   - a command line: optional list marker, optional backtick, `!`, then either a space and a token
#     starting with [A-Za-z0-9_./~$"'(] (so git's `! [rejected]` output never counts) or, with no
#     space, a lowercase letter or one of ./~ (so `!Important:` or `!$` in prose do not count);
#   - inside a fence it counts only when it is the first content line of the fence or follows a counted
#     one (so a POSIX `! grep -q x f` pipeline negation in a shell script, or a heredoc body line, does
#     not). Blank lines and `#` comment lines inside the fence do not break that chain; any other line
#     does, a `#!` shebang included. A tag line inside the fence is transparent too. A fence whose info
#     string is python, py, ipython or jupyter is never scanned (notebook `!pip` escapes);
#   - an inline span: a backtick, `!`, an optional space and a token, on a line that also holds the
#     whole word `run` or `yourself`.
# OK = the nearest previous line (blank lines are not skipped) is exactly an operator:run tag; a tag
# directly above an OPENING fence covers the whole fence (even when its first content lines are blank),
# and so does a tag directly above the first counted line inside it. Outside a fence each `!` line needs
# its own tag. Never flagged: table rows, the placeholder `! <`, and lines naming "the `!` prefix" /
# "`!` command(s)". Footer tags never satisfy it.
# Known limits: an UNCLOSED fence is scanned as if it ran to the end of the reply (later commands may
# hide inside it); a warning such as "Don't run `! git reset --hard`" is flagged as a hand-back (the
# send-back tells the model to say it is only an example), and so is prose like "run with `!important`".
#
# Once-per-reply marker: handback_tag_marker BASE SID FLAGGED -> path
#   (.state/handback-tag-guard/<sid>-<cksum of the flagged lines>; no session id keys on nosid-<PPID>).
#   The file holds the epoch seconds of the block. A marker younger than 10 minutes suppresses a repeat
#   block (handback_tag_seen); an older one does not, the same text blocks again.
#   handback_tag_pending MARKER -> exit 0 when the guard will block this reply or has just blocked it:
#   no marker, an empty one (a write caught mid-way), one older than 10 minutes (the guard blocks
#   again), or one under 5 seconds old (the Stop hooks run in parallel, so the guard's own marker can
#   already exist when notify.sh looks). Disclosed ceiling: a retry that repeats the identical untagged
#   command within 5 seconds is read as "still being blocked" and does not ping.
#
# Library hygiene: no top-level set -u; function bodies are subshells so nothing leaks into the caller.
handback_tag_scan() ( # $1 = text
  printf '%s\n' "$1" | awk '
    BEGIN {
      tag = "^[[:space:]]*operator:run[|]kind:(policy|oneoff)[[:space:]]*$"
      tok = "[A-Za-z0-9_./~$\"\047(]"
      bang = "!( " tok "|[a-z./~])"
      cmd = "^[[:space:]]*([-*>][[:space:]]+|[0-9]+[.)][[:space:]]+)?`?" bang
      inl = "`" bang
      cue = "(^|[^[:alnum:]_])(run|yourself)([^[:alnum:]_]|$)"
    }
    {
      line = $0; low = tolower(line)
      istag = (line ~ tag)
      t = line; sub(/^[[:space:]]*/, "", t); c = substr(t, 1, 1)
      if (c == "`" || c == "~") {
        n = 0; while (substr(t, n + 1, 1) == c) n++
        if (n >= 3) {
          rest = substr(t, n + 1)
          if (!infence) {
            if (index(rest, c) == 0) {
              nb = (tolower(rest) ~ /^[[:space:]]*(python|py|ipython|jupyter)([^[:alnum:]]|$)/)
              infence = 1; fc = c; fl = n; chain = 1; fok = prev; seen = 0; next
            }
          } else if (c == fc && n >= fl && rest ~ /^[[:space:]]*$/) { infence = 0; prev = 0; next }
        }
      }
      skip = (line ~ /^[[:space:]]*[|]/) || index(line, "`! <") || index(line, "the `!` prefix") \
          || index(line, "`!` command")
      kind = ""
      if (!skip && line ~ cmd) {
        if (!infence || (chain && !nb)) kind = "cmd"
      } else if (!skip && line ~ inl && low ~ cue) kind = "inl"
      if (infence && !istag && line !~ /^[[:space:]]*$/ && line !~ /^[[:space:]]*#([^!]|$)/) chain = (kind == "cmd")
      if (kind == "cmd") {
        ok = prev
        if (infence) { if (prev && !seen) fok = 1; seen = 1; ok = prev || fok }
        if (ok) print "O"; else print "F" substr(line, 1, 80)
      } else if (kind == "inl") {
        if (prev) print "O"; else print "F" substr(line, 1, 80)
      }
      prev = istag
    }'
)
handback_tag_flagged() ( handback_tag_scan "$1" | sed -n 's/^F//p' )
handback_tag_count() ( handback_tag_scan "$1" | grep -c '^[FO]' || true )

handback_tag_marker() ( # $1 = kit base, $2 = session id, $3 = flagged lines
  sid="$(printf '%s' "${2:-}" | tr -c 'A-Za-z0-9_-' '_')"
  [ -n "$sid" ] || sid="nosid-${PPID:-0}"
  sum="$(printf '%s' "$3" | cksum | awk '{print $1}')"
  printf '%s/.state/handback-tag-guard/%s-%s\n' "$1" "$sid" "$sum"
)
# handback_tag_age MARKER -> stdout: seconds since the block, empty when unknown (no/empty/odd marker).
handback_tag_age() (
  [ -f "$1" ] || exit 0
  then_ts="$(cat "$1" 2>/dev/null || true)"
  now_ts="$(date +%s 2>/dev/null || true)"
  case "$then_ts" in '' | *[!0-9]*) exit 0 ;; esac
  case "$now_ts" in '' | *[!0-9]*) exit 0 ;; esac
  printf '%s\n' $((now_ts - then_ts))
)
# handback_tag_seen MARKER -> exit 0 when a block younger than 10 minutes is on record.
handback_tag_seen() (
  age="$(handback_tag_age "$1")"
  [ -n "$age" ] && [ "$age" -lt 600 ]
)
handback_tag_pending() (
  age="$(handback_tag_age "$1")"
  [ -n "$age" ] || exit 0
  [ "$age" -lt 5 ] || [ "$age" -ge 600 ]
)

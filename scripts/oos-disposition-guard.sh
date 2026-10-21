#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers Stop hook: send a turn back while a sub-agent hand-back in this session carries
# numbered `OOS-<n>: <one line>` items (out-of-slice finds, things not fixed, proposed definition
# changes) that the Lead has not given a disposition line yet.
#
# Why a hook: an audit of real sessions found 28% of handed-back OOS items were never acted on or
# recorded by the receiving Lead. A prose rule did not hold; a send-back at the Stop arrival event
# does (same reasoning as notify-tag-guard.sh and handback-tag-guard.sh).
#
# Scope: native CLI only (non-cli entrypoints skip), the delegation group, the main session only.
# Items come ONLY from (a) a `<agent-message from="ID">` frame with `[Subagent hand-back]` in it
# (key ID, qualifier q = first 8 chars of ID), found in a user line's text or in the prompt of an
# attachment line of type queued_command (how a hand-back delivered mid-turn is recorded), and (b) a
# user line's tool_result for a known Agent/Task tool_use id (key the tool_use id, q = its last 8
# chars); an "Async agent launched" result is skipped. queue-operation lines (duplicates of
# hand-backs), plain user text and the Lead's own text are never item sources. A frame opens only at
# the start of the text or right after a newline, and ends only at a newline plus the closing tag:
# the harness indents every report line, so a tag quoted mid-line or indented inside a report is
# body text. An item line is `OOS-<digits>` then `:`, `.` or `)` and text, after stripping leading
# whitespace, `>`, `-`, `*`, a numbered-list prefix (`1. `, `1) `), a heading prefix (`#`..`######`
# and a space) and `**`/backticks around the id. Lines inside a fenced code block (``` or ~~~,
# tracked per frame or tool_result body) are not items, nor is a line whose text starts with a
# disposition verb as a whole word (a child reporting its own disposition of a grandchild's id); each
# such dropped line is logged once (the scan is incremental) as `dropped: verb-start item
# OOS-<n>@<q>: <first 60 chars of text>`, so drops are countable. The
# same key and n seen again (a resumed child restating its list, or one hand-back seen both as an
# attachment and as a user line) is the same item: its text is updated, its status kept.
# A disposition is an assistant text block line that, after `*` and backticks are stripped, starts
# (after optional whitespace, a `-`/`*`/`+` bullet or a numbered prefix, never `>`: a quoted line,
# such as a Lead quoting a child's report, closes nothing) with `OOS-<n>`,
# optionally `@<q>`, then `:`, whitespace and one of fixed|ledgered|routed|inbox|wontfix
# (case-insensitive). One per line: prose mentioning a disposition mid-sentence, or a second one on
# the same line, closes nothing. It closes only an item already open at that point in the transcript
# whose own text does not start with that same verb word (a Lead relaying the item verbatim): the
# one with that n and q when qualified, else the most recently opened such item with that n. `inbox`
# also appends one line to the kit inbox, ${AGENT_TIERS_OOS_INBOX:-<plugin root or
# ~/.claude/agent-tiers>/.state/oos-inbox.log}: date, repo, session id, OOS-<n>@<q>, item text,
# tab-separated, never twice for the same session id and OOS-<n>@<q>. The check and the append run
# under an atomic mkdir lock (<inbox>.lock, 20 tries 0.05 s apart, about 1 s in all, or one 1 s
# try where sleep takes no fraction; on timeout the append is skipped and logged), so two concurrent
# Stops cannot both append. A lock older than a minute (left by a killed run) is removed and logged
# first. The name ends `.log`, never `.tsv`: it is an append log.
# Payload fallback: whether the final reply is in the transcript when Stop fires is not verified in this
# kit (advisory-ack-guard.sh carries the same open TODO), so the payload's last_assistant_message is
# also read for disposition lines, after the transcript chunk. Its 120-char key (first 120 chars, tabs,
# CR and LF as spaces) is compared with the key of EVERY assistant text block in this run's chunk and
# with <sid>.lasta (the last such key of an earlier run): equal means the reply is already in the
# transcript and was applied, so the payload is skipped. A payload that is applied has its key saved
# in <sid>.lastpayload; a payload whose key equals that saved key is not applied again, and the first
# later transcript text block with that key (the reply's own transcript copy) is skipped once, so one
# reply never closes two items that share a number. A reply tagged operator:ask_next is not sent
# back (notify-tag-guard already sends it back to ask; lib/notify-tag.sh missing: no skip).
# Send-back once per open set: a block writes <sid>.sent (atomically, temp + mv) holding the cksum
# of the sorted open qualified ids (`OOS-<n>@<q>`, one per line). A later Stop whose open set has the
# same cksum while the marker is younger than 10 minutes passes (`allow: already sent back for this
# open set`); a changed set (an item closed, a new one opened) or an older marker blocks again.
# Deliberately NOT keyed off stop_hook_active: that flag is harness-global, so after another Stop
# hook's send-back every later Stop carries it and this guard would be blind most turns.
#
# State, per session, under <kit root>/.state/oos-disposition-guard/: <sid>.offset (transcript bytes
# already processed, always at a line boundary), <sid>.items (TSV: key, n, open|closed, verb, text,
# in the order items were first opened), <sid>.spawns (Agent/Task tool_use ids seen),
# <sid>.lastpayload (the 120-char key of the last applied payload reply) and <sid>.lasta (the key of
# the last transcript text block seen), see above, and <sid>.sent (the send-back marker). Each run reads only complete lines after the
# offset (a partial last line waits for its newline). A transcript shorter than the offset resets the
# state. An unread chunk over the cap (OOS_GUARD_CAP bytes, digits only, default 8388608 = 8 MiB) is
# cut to its last cap bytes, from the first line boundary inside them, and logged as skipped. Files
# older than a day are deleted on each run (find -mtime +1 rounds down, so in practice 2 days).
#
# Known limits: Stop does not fire for sub-agents, so a sublead receiving a worker's items is not
# checked; a resumed child that reuses a number for a different item collides with its earlier item
# (the return contract tells children to continue numbering); an ignored send-back for the same open
# set repeats only after 10 minutes; items older than the cap window on the first scan of a long session are not seen; a later reply
# whose first 120 chars equal the previous one and that only reaches the payload is not applied; an
# item whose text starts with a disposition verb is never opened; a frame or fence that a report
# never closes runs to the end of its text; for up to a minute after a run is killed holding the
# lock, inbox appends time out (logged) and those items are closed with no inbox line.
# Fail-open: no jq/awk, no session id, missing/unreadable/empty transcript, non-cli entrypoint, kill
# switch, kit-gate stand-down.
# Self-check: oos-disposition-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s oos-disposition-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}

# Kill switch first, before any side effect.
[ -f "$CLAUDE_DIR/agent-tiers/.state/off/oos-disposition-guard" ] && exit 0
# Headless/scripted runs never enforce (see notify-tag-guard.sh); only `cli` is proven interactive.
[ "${CLAUDE_CODE_ENTRYPOINT:-}" = "cli" ] || exit 0
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v awk >/dev/null 2>&1 || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
NTLIB="$SELFDIR/lib/notify-tag.sh"
if [ -n "$SELFDIR" ] && [ -f "$NTLIB" ] && sh -n "$NTLIB" >/dev/null 2>&1; then
  . "$NTLIB"
fi

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
TP="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$TP" ] && [ -f "$TP" ] && [ -r "$TP" ] && [ -s "$TP" ] || exit 0
SKEY="$(printf '%s' "$SID" | tr -c 'A-Za-z0-9._-' '_')"
[ -n "$SKEY" ] || exit 0

SD="${BASE:-${TMPDIR:-/tmp}}/.state/oos-disposition-guard"
mkdir -p "$SD" 2>/dev/null || exit 0
{ find "$SD" -type f -mtime +1 -delete; } 2>/dev/null || true
OFF_F="$SD/$SKEY.offset"; ITEMS_F="$SD/$SKEY.items"; SPAWNS_F="$SD/$SKEY.spawns"; LP_F="$SD/$SKEY.lastpayload"
LA_F="$SD/$SKEY.lasta"
TMP="$SD/.tmp.$$"
trap 'rm -f "$TMP".*' EXIT
CAP="$(printf '%s' "${OOS_GUARD_CAP:-}" | sed 's/^0*//')"
case "$CAP" in '' | *[!0-9]*) CAP=8388608 ;; esac

SIZE="$(wc -c < "$TP" 2>/dev/null | tr -d ' ')"
case "$SIZE" in '' | *[!0-9]*) exit 0 ;; esac
OFF="$(cat "$OFF_F" 2>/dev/null || true)"
case "$OFF" in '' | *[!0-9]*) OFF=0 ;; esac
if [ "$SIZE" -lt "$OFF" ]; then
  OFF=0; : > "$ITEMS_F" 2>/dev/null; : > "$SPAWNS_F" 2>/dev/null; : > "$LP_F" 2>/dev/null; : > "$LA_F" 2>/dev/null
  rm -f "$SD/$SKEY.sent" 2>/dev/null
fi

# Unread chunk: bytes after OFF. Over the cap, start one byte before the last CAP bytes and drop
# through the first newline, which lands on the first line boundary inside the window.
START="$OFF"; DROP=0
if [ $((SIZE - OFF)) -gt "$CAP" ]; then
  START=$((SIZE - CAP - 1))
  tail -c +$((START + 1)) "$TP" > "$TMP.raw" 2>/dev/null || exit 0
  DROP="$(head -n 1 "$TMP.raw" | wc -c | tr -d ' ')"
  note "skipped: $((START + DROP - OFF)) older bytes not scanned"
else
  tail -c +$((START + 1)) "$TP" > "$TMP.raw" 2>/dev/null || exit 0
fi
LEN="$(wc -c < "$TMP.raw" | tr -d ' ')"
# Bytes after the last newline (a partial line still being written) are left for the next run.
PART=0
if [ "$LEN" -gt 0 ] && [ -n "$(tail -c 1 "$TMP.raw")" ]; then
  PART="$(tail -n 1 "$TMP.raw" | wc -c | tr -d ' ')"
fi
USE=$((LEN - DROP - PART))
# No newline anywhere in the capped window: nothing complete to consume yet.
if [ "$USE" -lt 0 ]; then USE=0; NEWOFF="$OFF"; else NEWOFF=$((START + DROP + USE)); fi
[ "$NEWOFF" -lt "$OFF" ] && NEWOFF="$OFF"

# Shared by the transcript pass and the payload pass: key120 (the reply key) and disp (D rows).
JQDEF='
  def clean: gsub("[\t\r\n]"; " ");
  def key120: .[0:120] | clean;
  def disp: select(test("OOS-"; "i")) | split("\n")[] | gsub("[*`]"; "")
    | capture("^(?:[\\s+-]|[0-9]+[.)]\\s)*OOS-(?<n>[0-9]+)(?:@(?<q>[A-Za-z0-9_-]{8}))?:\\s+(?<v>fixed|ledgered|routed|inbox|wontfix)\\b"; "i")
    | ["D", .n, (.q // ""), (.v | ascii_downcase)]
    | join("\t");'
# One jq pass, one event row per find, in transcript order:
#   S <spawn id> | H <agent id> <n> <text> | R <tool_use id> <n> <text> | A <key120> | D <n> <q> <verb>
#   | VH / VR: as H / R, for a dropped verb-start item line
# (each assistant text block emits its A row, then its D rows)
{ [ "$USE" -gt 0 ] && tail -c +$((DROP + 1)) "$TMP.raw" | head -c "$USE"; true; } | jq -rR "$JQDEF"'

  def txt: if type == "string" then .
    elif type == "array" then map(select(type == "object" and .type == "text") | .text // "") | join("\n")
    else "" end;
  def items: select(test("OOS-")) | split("\n")
    | foreach .[] as $l ({f: "", e: null};
        .f as $f
        | if ($l | contains("```") or contains("~~~")) | not then {f: $f, e: (if $f == "" then $l else null end)}
          else ($l | sub("^\\s+"; "")) as $s
          | if $f == "" then (if ($s | test("^(```|~~~)")) then {f: $s[0:3], e: null} else {f: "", e: $l} end)
            elif ($s | startswith($f)) then {f: "", e: null}
            else {f: $f, e: null} end end;
        .e | select(. != null and contains("OOS-")))
    | sub("^(?:[\\s>*-]|[0-9]+[.)]\\s|#{1,6}\\s)+"; "")
    | capture("^[`*]*OOS-(?<n>[0-9]+)[`*]*\\s*[:.)][`*]*\\s*(?<t>.*)$")
    | (if .t | sub("^[`*\\s]+"; "") | test("^(fixed|ledgered|routed|inbox|wontfix)\\b"; "i") then "V" else "" end) as $v
    | [$v, .n, (.t | clean | sub("^\\s+"; "") | sub("\\s+$"; "") | .[0:200])];
  def frames: select(contains("<agent-message from=\""))
    | ("\n" + .) | split("\n<agent-message from=\"")[1:][] | split("\n</agent-message>")[0]
    | select(contains("[Subagent hand-back]"))
    | (capture("^(?<id>[^\"\\s]+)\"").id | clean) as $id
    | items | [.[0] + "H", $id] + .[1:] | join("\t");
  fromjson? | select(type == "object") |
  if .type == "attachment" then
    (.attachment // null) | select(type == "object" and .type == "queued_command")
    | (.prompt // "" | txt) | frames
  elif .type == "user" then
    (.message.content // "") as $c
    | (($c | txt) | frames),
      (if ($c | type) == "array" then
         $c[] | select(type == "object" and .type == "tool_result")
         | (.tool_use_id // "" | tostring | clean) as $id | select($id != "")
         | (.content | txt) | select(startswith("Async agent launched") | not)
         | items | [.[0] + "R", $id] + .[1:] | join("\t")
       else empty end)
  elif .type == "assistant" then
    (.message.content // []) | if type == "array" then .[] else empty end | select(type == "object")
    | if .type == "tool_use" and (.name == "Agent" or .name == "Task") then
        ["S", (.id // "" | tostring | clean)] | select(.[1] != "") | join("\t")
      elif .type == "text" then
        (.text // "" | tostring) as $t | ("A\t" + ($t | key120)), ($t | disp)
      else empty end
  else empty end' > "$TMP.ev" 2>/dev/null || true

touch "$ITEMS_F" "$SPAWNS_F" "$LP_F" "$LA_F" 2>/dev/null || exit 0
# Payload fallback (see header): P <key120> then the payload's D rows, after the chunk's rows.
PKEY="$(printf '%s' "$INPUT" | jq -r "$JQDEF"' .last_assistant_message // "" | tostring | key120' 2>/dev/null || true)"
NEWLA="$(awk -F'\t' '$1 == "A" { k = $2 } END { print k }' "$TMP.ev")"
if [ -n "$PKEY" ]; then
  OLDLP="$(sed -n 1p "$LP_F" 2>/dev/null)"
  OLDLA="$(sed -n 1p "$LA_F" 2>/dev/null)"
  if [ "$PKEY" != "$OLDLP" ] && [ "$PKEY" != "$OLDLA" ] \
    && ! PK="$PKEY" awk -F'\t' '$1 == "A" && $2 == ENVIRON["PK"] { f = 1 } END { exit !f }' "$TMP.ev"; then
    { printf 'P\t%s\n' "$PKEY"
      printf '%s' "$INPUT" | jq -r "$JQDEF"' .last_assistant_message // "" | tostring | disp' 2>/dev/null || true
    } >> "$TMP.ev"
  fi
fi
# Apply the events to the state; stdout: X (inbox) rows, O (open item) rows, then `C <total items>`.
awk -F'\t' -v IF="$ITEMS_F" -v SF="$SPAWNS_F" -v LF="$LP_F" -v OI="$TMP.items" -v OS="$TMP.spawns" -v OL="$TMP.lp" '
  # vstart: item text t starts with the verb word v (a relayed item, not a disposition of it).
  function vstart(t, v,  s) {
    s = tolower(t); sub(/^[`* \t]+/, "", s)
    return substr(s, 1, length(v)) == v && substr(s, length(v) + 1, 1) !~ /[a-z0-9_]/
  }
  function qof(i,  k) { k = K[i]; if (k in SP) return (length(k) > 8 ? substr(k, length(k) - 7) : k); return substr(k, 1, 8) }
  function openit(k, n, t,  id) {
    id = k SUBSEP n
    if (id in IDX) { T[IDX[id]] = t; return }
    ni++; K[ni] = k; N[ni] = n; ST[ni] = "open"; V[ni] = ""; T[ni] = t; IDX[id] = ni
  }
  BEGIN {
    while ((getline l < IF) > 0) {
      if (split(l, a, "\t") < 3) continue
      ni++; K[ni] = a[1]; N[ni] = a[2]; ST[ni] = a[3]; V[ni] = a[4]; T[ni] = a[5]; IDX[a[1] SUBSEP a[2]] = ni
    }
    while ((getline l < SF) > 0) if (l != "" && !(l in SP)) { SP[l] = 1; ns++; SO[ns] = l }
    LP = ""; if ((getline l < LF) > 0) LP = l
  }
  # A: a transcript text block; skip its D rows once when it is the copy of an applied payload reply.
  $1 == "A" { skip = (LP != "" && $2 == LP); if (skip) LP = ""; next }
  $1 == "P" { LP = $2; skip = 0; next }
  $1 != "D" { skip = 0 }
  $1 == "S" { if (!($2 in SP)) { SP[$2] = 1; ns++; SO[ns] = $2 }; next }
  $1 == "H" { openit($2, $3, $4); next }
  $1 == "R" { if ($2 in SP) openit($2, $3, $4); next }
  $1 == "VH" { printf "V\t%s\t%s\t%s\n", $3, substr($2, 1, 8), substr($4, 1, 60); next }
  $1 == "VR" { if ($2 in SP) printf "V\t%s\t%s\t%s\n", $3, (length($2) > 8 ? substr($2, length($2) - 7) : $2), substr($4, 1, 60); next }
  $1 == "D" {
    if (skip) next
    b = 0
    for (i = ni; i >= 1; i--) if (N[i] == $2 && ST[i] == "open" && ($3 == "" || qof(i) == $3) && !vstart(T[i], $4)) { b = i; break }
    if (b) { ST[b] = "closed"; V[b] = $4; if ($4 == "inbox") printf "X\t%s\t%s\t%s\n", N[b], qof(b), T[b] }
    next
  }
  END {
    for (i = 1; i <= ni; i++) {
      printf "%s\t%s\t%s\t%s\t%s\n", K[i], N[i], ST[i], V[i], T[i] > OI
      if (ST[i] == "open") printf "O\t%s\t%s\t%s\n", N[i], qof(i), T[i]
    }
    for (i = 1; i <= ns; i++) print SO[i] > OS
    printf "" > OI; printf "" > OS
    printf "%s\n", LP > OL
    printf "C\t%d\n", ni
  }' "$TMP.ev" > "$TMP.out" 2>/dev/null || exit 0
mv -f "$TMP.items" "$ITEMS_F" 2>/dev/null && mv -f "$TMP.spawns" "$SPAWNS_F" 2>/dev/null \
  && mv -f "$TMP.lp" "$LP_F" 2>/dev/null \
  && { [ -z "$NEWLA" ] || { printf '%s\n' "$NEWLA" > "$TMP.la" && mv -f "$TMP.la" "$LA_F"; }; } 2>/dev/null \
  && printf '%s\n' "$NEWOFF" > "$TMP.off" && mv -f "$TMP.off" "$OFF_F" 2>/dev/null || exit 0
# Dropped verb-start item lines, logged once each (the chunk is never scanned again).
grep '^V' "$TMP.out" | while IFS="$(printf '\t')" read -r _v n q t; do
  note "dropped: verb-start item OOS-$n@$q: $t"
done

# inbox: append each newly closed inbox item once per (session id, OOS-<n>@<q>).
if grep -q '^X' "$TMP.out"; then
  INBOX="${AGENT_TIERS_OOS_INBOX:-${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/.state/oos-inbox.log}"
  REPO="$(git -C "${CWD:-.}" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$REPO" ] || REPO="$CWD"
  REPO="$(basename "$REPO" 2>/dev/null || true)"
  [ -n "$REPO" ] || REPO=unknown
  mkdir -p "$(dirname "$INBOX")" 2>/dev/null || true
  DAY="$(date '+%Y-%m-%d')"
  # Check-then-append under an atomic mkdir lock, so two concurrent Stops cannot both append.
  LK="$INBOX.lock"; GOT=0; TRY=0
  # A lock older than a minute was left by a killed run (a live holder keeps it well under 1 s).
  # Rename before removing, so two runs that both see the stale lock cannot each remove one: only one
  # mv wins, and the loser never touches a lock taken by the winner in between.
  if [ -d "$LK" ] && [ -n "$(find "$LK" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    mv "$LK" "$LK.stale.$$" 2>/dev/null && rmdir "$LK.stale.$$" 2>/dev/null && note "inbox: removed stale lock"
  fi
  # Total wait about 1 s: 20 sleeps of 0.05 s, or one 1 s sleep where sleep takes no fraction.
  while :; do
    mkdir "$LK" 2>/dev/null && { GOT=1; break; }
    [ "$TRY" -ge 20 ] && break
    TRY=$((TRY + 1)); sleep 0.05 2>/dev/null || { sleep 1; TRY=20; }
  done
  if [ "$GOT" = 1 ]; then
    trap 'rm -f "$TMP".*; rmdir "$LK" 2>/dev/null' EXIT
    grep '^X' "$TMP.out" | while IFS="$(printf '\t')" read -r _x n q t; do
      tag="OOS-$n@$q"
      [ -f "$INBOX" ] && awk -F'\t' -v s="$SID" -v g="$tag" '$3 == s && $4 == g { f = 1 } END { exit !f }' "$INBOX" && continue
      printf '%s\t%s\t%s\t%s\t%s\n' "$DAY" "$REPO" "$SID" "$tag" "$t" >> "$INBOX" 2>/dev/null || note "inbox: append failed"
    done
    rmdir "$LK" 2>/dev/null
    trap 'rm -f "$TMP".*' EXIT
  else
    note "inbox: lock busy, append skipped"
  fi
fi

TOTAL="$(awk -F'\t' '$1 == "C" { print $2 }' "$TMP.out")"
OPEN="$(grep -c '^O' "$TMP.out" 2>/dev/null || true)"
case "$OPEN" in '' | *[!0-9]*) OPEN=0 ;; esac
if [ "$OPEN" -eq 0 ]; then
  [ "${TOTAL:-0}" -gt 0 ] 2>/dev/null && note "allow: all OOS items disposed"
  exit 0
fi
CLASS=""
command -v notify_tag_classify >/dev/null 2>&1 \
  && CLASS="$(notify_tag_classify "$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)")"
if [ "$CLASS" = ask_next ]; then
  note "allow: ask_next reply, not checked"
  exit 0
fi
# Once per open set (see header): same cksum and a marker younger than 10 minutes passes.
SENT_F="$SD/$SKEY.sent"
SUM="$(grep '^O' "$TMP.out" | awk -F'\t' '{ print "OOS-" $2 "@" $3 }' | sort | cksum | awk '{ print $1 }')"
if [ -f "$SENT_F" ] && [ "$(sed -n 1p "$SENT_F" 2>/dev/null)" = "$SUM" ] \
  && [ -z "$(find "$SENT_F" -mmin +9 2>/dev/null)" ]; then
  note "allow: already sent back for this open set"
  exit 0
fi
{ printf '%s\n' "$SUM" > "$TMP.sent" && mv -f "$TMP.sent" "$SENT_F"; } 2>/dev/null || true

note "blocked: $OPEN undisposed OOS item(s)"
{
  printf 'agent-tiers: sub-agent hand-backs carry OOS items with no disposition line:\n'
  grep '^O' "$TMP.out" | sed -n '1,10p' | awk -F'\t' '{ printf "  OOS-%s@%s: %s\n", $2, $3, substr($4, 1, 90) }'
  [ "$OPEN" -gt 10 ] && printf '  ... and %s more\n' "$((OPEN - 10))"
  printf 'Write one line per item, each starting its own line: OOS-<n>: fixed|ledgered|routed|inbox|wontfix <why or where>.'
  printf ' Add @<q> when two hand-backs share a number (an unqualified line closes the most recent one).'
  printf ' inbox files it in the kit inbox for a later kit session.'
  printf ' Your previous reply was ALREADY DELIVERED: send only the disposition lines AND end the reply'
  printf ' with its normal operator: footer line.\n'
} >&2
exit 2

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for oos-disposition-guard.sh: OOS items in a hand-back frame (indented, as the harness
# writes them) block until each has a disposition line; wontfix/inbox close them; inbox writes one
# 5-field line, never twice; a second Stop with nothing new passes; OOS lines in the Lead's own text or
# in a plain user message open nothing; a disposition only in last_assistant_message closes its item,
# and a reply seen in the payload and in the transcript (same run or a later one) is applied once;
# two hand-backs sharing a number collide as specified and a qualified line closes the right one; a foreground Agent tool_result opens items and a non-spawn
# tool_result does not; a send-back repeats only for a changed open set or a marker over 10
# minutes old (stop_hook_active ignored); a verb-start item line is logged once as dropped; a
# disposition inside a `>` quote closes nothing; the scan is incremental (offset grows, a disposition
# before a hand-back does not close it); a partial last line waits; and non-cli entrypoint, kill
# switch, kit-gate group stand-down, missing transcript_path and an empty transcript fail open.
# Review-round cases R1-R8: a queued_command attachment hand-back opens items (merged with its
# user-line copy); frame tags quoted inside a report neither split nor end the frame; the send-back
# asks for the operator: footer and an ask_next reply passes (not with lib/notify-tag.sh missing);
# numbered/heading prefixes open, fenced lines and a child's own dispositions do not; a disposition
# must start its line, one per line, and a verbatim relay of an item does not close it; a payload
# matching any chunk text block, or the last text block of an earlier run, is not applied again;
# two concurrent Stops append one inbox line (10 rounds), a stale lock is removed, a busy one skips
# the append within 2 s; OOS_GUARD_CAP windows the scan.
set -u
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP oos-disposition-guard: jq absent (guard fails open by design)"; exit 0; }

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
fail() { printf 'FAIL: %s\n' "$1"; rm -rf "$T"; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/kit/scripts/lib" "$T/kit/install" "$T/managed"
cp "$SRC_DIR/oos-disposition-guard.sh" "$T/kit/scripts/" || fail "cannot copy guard into sandbox"
cp "$SRC_DIR/lib/notify-tag.sh" "$T/kit/scripts/lib/" || fail "cannot copy lib/notify-tag.sh into sandbox"
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$SRC_DIR/kit-gate.sh" > "$T/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$T/kit/scripts/kit-gate.sh" || fail "_kg_managed not rewritten"
cp "$SRC_DIR/../install/options.tsv" "$T/kit/install/"
H="$T/kit/scripts/oos-disposition-guard.sh"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export AGENT_TIERS_GUARDS_LOG="$T/guards.log"
export CLAUDE_CONFIG_DIR="$T/cfg"
export AGENT_TIERS_OOS_INBOX="$T/inbox/oos-inbox.log"
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state"
SD="$T/kit/.state/oos-disposition-guard"

# Transcript line builders: each appends one JSON object line to file $1.
handback() { # $1=file $2=agent id $3=report body (each line gets the harness's two-space indent)
  body="$(printf '%s\n' "$3" | sed 's/^/  /')"
  jq -cn --arg id "$2" --arg b "$body" \
    '{type:"user", message:{role:"user", content:("Another Claude session sent a message:\n<agent-message from=\"" + $id + "\">\n[Subagent hand-back] The text below is the final report of a subagent. The report follows:\n" + $b + "\n</agent-message>")}}' >> "$1"
}
queued() { # $1=file $2=agent id $3=report body: a hand-back delivered mid-turn (attachment line)
  body="$(printf '%s\n' "$3" | sed 's/^/  /')"
  jq -cn --arg id "$2" --arg b "$body" \
    '{type:"attachment", attachment:{type:"queued_command", commandMode:"task-notification", prompt:("<agent-message from=\"" + $id + "\">\n[Subagent hand-back] The report follows:\n" + $b + "\n</agent-message>")}}' >> "$1"
}
lead() { jq -cn --arg t "$2" '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}' >> "$1"; }
plain() { jq -cn --arg t "$2" '{type:"user", message:{role:"user", content:$t}}' >> "$1"; }
spawn() { jq -cn --arg id "$2" --arg n "$3" '{type:"assistant", message:{role:"assistant", content:[{type:"tool_use", id:$id, name:$n, input:{}}]}}' >> "$1"; }
result() { jq -cn --arg id "$2" --arg t "$3" '{type:"user", message:{role:"user", content:[{type:"tool_result", tool_use_id:$id, content:[{type:"text", text:$t}]}]}}' >> "$1"; }
run() { # $1=session id $2=transcript $3=stop_hook_active (default false) $4=entrypoint (default cli)
  # $5=last_assistant_message (default absent)
  # The send-back marker is cleared first so each case sees a fresh block; KEEP_SENT=1 keeps it.
  [ -n "${KEEP_SENT:-}" ] || rm -f "$SD/$1.sent"
  jq -cn --arg s "$1" --arg tp "$2" --arg c "$T" --argjson a "${3:-false}" --arg m "${5:-}" \
    '{hook_event_name:"Stop", session_id:$s, transcript_path:$tp, cwd:$c, stop_hook_active:$a}
     + (if $m == "" then {} else {last_assistant_message:$m} end)' \
    | CLAUDE_CODE_ENTRYPOINT="${4:-cli}" sh "$H" >"$T/stdout" 2>"$T/stderr"
  echo "$?"
}
REPORT="$(printf 'Hi, I am worker.\nOutcome: done\nOOS-1: first find\nOOS-2: second find\nOOS-3: third find\nDeviations from the brief: none')"

# 1. three items, two disposed -> block naming only OOS-3
F1="$T/t1.jsonl"; : > "$F1"
handback "$F1" a1111111aaaa "$REPORT"
lead "$F1" "$(printf 'Done.\n- OOS-1: fixed in this diff\n**OOS-2**: ledgered as a Deferred line')"
[ "$(run s1 "$F1")" = 2 ] || fail "1: one undisposed item must block"
grep -q 'OOS-3@a1111111: third find' "$T/stderr" || fail "1: stderr must name OOS-3 qualified"
grep -q 'OOS-1@\|OOS-2@' "$T/stderr" && fail "1: stderr must not name disposed OOS-1/OOS-2"
grep -q 'ALREADY DELIVERED' "$T/stderr" || fail "1: stderr must carry the send-only instruction"
grep -q 'oos-disposition-guard blocked: 1 undisposed OOS item(s) \[sid=s1\]' "$AGENT_TIERS_GUARDS_LOG" || fail "1: block must be logged"

# 2. wontfix closes the last one
lead "$F1" "OOS-3: wontfix not worth it"
[ "$(run s1 "$F1")" = 0 ] || fail "2: all disposed must pass"
grep -q 'allow: all OOS items disposed' "$AGENT_TIERS_GUARDS_LOG" || fail "2: allow line must be logged"

# 4. second Stop, nothing new
[ "$(run s1 "$F1")" = 0 ] || fail "4: second Stop after all disposed must pass"
[ -s "$T/stderr" ] && fail "4: no re-send expected"
# a resumed child restating its list: same key + n is the same item, text updated, status kept
handback "$F1" a1111111aaaa "$(printf 'OOS-3: third find, restated\nOOS-4: new find')"
[ "$(run s1 "$F1")" = 2 ] || fail "restate: the new OOS-4 must block"
grep -q 'OOS-3@' "$T/stderr" && fail "restate: a closed item restated must stay closed"
[ "$(awk -F'\t' '$2 == 3 { c++; t = $5 } END { print c ":" t }' "$SD/s1.items")" = "1:third find, restated" ] || fail "restate: one row, text updated"
lead "$F1" "OOS-4: fixed"
[ "$(run s1 "$F1")" = 0 ] || fail "restate: OOS-4 disposed must pass"

# 3. inbox: one 5-field line, idempotent
F3="$T/t3.jsonl"; : > "$F3"
handback "$F3" b2222222bbbb "$REPORT"
lead "$F3" "$(printf 'OOS-1: fixed\nOOS-2: routed to row X\nOOS-3: INBOX for a kit session')"
[ "$(run s3 "$F3")" = 0 ] || fail "3: inbox disposition must pass"
[ "$(wc -l < "$AGENT_TIERS_OOS_INBOX" | tr -d ' ')" = 1 ] || fail "3: exactly one inbox line expected"
awk -F'\t' 'NF != 5 || $3 != "s3" || $4 != "OOS-3@b2222222" || $5 != "third find" || $1 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ { exit 1 }' "$AGENT_TIERS_OOS_INBOX" \
  || fail "3: inbox line must be date, repo, sid, OOS-3@q, text"
[ "$(run s3 "$F3")" = 0 ] || fail "3: rerun must pass"
rm -rf "$SD"
[ "$(run s3 "$F3")" = 0 ] || fail "3: full rescan must pass"
[ "$(wc -l < "$AGENT_TIERS_OOS_INBOX" | tr -d ' ')" = 1 ] || fail "3: rerun (even a full rescan) must not append a second inbox line"

# 5. OOS line only in the Lead's own text
F5="$T/t5.jsonl"; : > "$F5"
lead "$F5" "OOS-1: something"
[ "$(run s5 "$F5")" = 0 ] || fail "5: Lead text must not open an item"
[ -s "$SD/s5.items" ] && fail "5: no item may be recorded"

# 6. OOS line in a plain user message
F6="$T/t6.jsonl"; : > "$F6"
plain "$F6" "OOS-1: something"
[ "$(run s6 "$F6")" = 0 ] || fail "6: plain user text must not open an item"

# 7. collision: two hand-backs both carry OOS-1
F7="$T/t7.jsonl"; : > "$F7"
handback "$F7" c3333333cccc "OOS-1: from the first child"
handback "$F7" d4444444dddd "OOS-1: from the second child"
lead "$F7" "OOS-1: fixed"
[ "$(run s7 "$F7")" = 2 ] || fail "7: unqualified line closes only one of two"
grep -q 'OOS-1@c3333333: from the first child' "$T/stderr" || fail "7: the first child's item must stay open"
grep -q 'd4444444' "$T/stderr" && fail "7: the later item must be the one closed"
lead "$F7" "OOS-1@c3333333: routed x"
[ "$(run s7 "$F7")" = 0 ] || fail "7: qualified line must close the first child's item"

# 8. foreground Agent tool_result opens; a non-spawn tool_result does not
F8="$T/t8.jsonl"; : > "$F8"
spawn "$F8" toolu_01AAAAAAAAAAAAXyzw1234 Agent
result "$F8" toolu_01AAAAAAAAAAAAXyzw1234 "$(printf 'report\nOOS-1: foreground find')"
[ "$(run s8 "$F8")" = 2 ] || fail "8: a foreground Agent result with OOS-1 must block"
grep -q 'OOS-1@Xyzw1234: foreground find' "$T/stderr" || fail "8: q must be the last 8 chars of the tool_use id"
F8b="$T/t8b.jsonl"; : > "$F8b"
spawn "$F8b" toolu_01BBBBBBBBBBBBBBBBBBBB Bash
result "$F8b" toolu_01BBBBBBBBBBBBBBBBBBBB "OOS-1: not from a spawn"
spawn "$F8b" toolu_01CCCCCCCCCCCCCCCCCCCC Task
result "$F8b" toolu_01CCCCCCCCCCCCCCCCCCCC "$(printf 'Async agent launched successfully.\nOOS-1: launch notice')"
[ "$(run s8b "$F8b")" = 0 ] || fail "8: a non-spawn result or an async launch notice must not open an item"

# 9. once per open set: a repeat Stop with the same open set passes (stop_hook_active ignored); a
# changed set or a marker over 10 minutes old blocks again
F9="$T/t9.jsonl"; : > "$F9"
handback "$F9" a9a9a9a9ffff "$(printf 'OOS-1: nine one\nOOS-2: nine two')"
[ "$(run s9 "$F9")" = 2 ] || fail "9: first Stop with open items must block"
[ "$(KEEP_SENT=1 run s9 "$F9" true)" = 0 ] || fail "9: same open set again must pass, stop_hook_active or not"
grep -q 'allow: already sent back for this open set \[sid=s9\]' "$AGENT_TIERS_GUARDS_LOG" || fail "9: the repeat allow must be logged"
lead "$F9" "OOS-1: fixed"
[ "$(KEEP_SENT=1 run s9 "$F9" true)" = 2 ] || fail "9: a changed open set must block again"
grep -q 'OOS-2@a9a9a9a9' "$T/stderr" || fail "9: the changed-set send-back must name OOS-2"
touch -t "$(date -d '-11 minutes' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-11M '+%Y%m%d%H%M.%S')" "$SD/s9.sent"
[ "$(KEEP_SENT=1 run s9 "$F9")" = 2 ] || fail "9: a marker over 10 minutes old must not suppress"

# 10. incremental: new hand-back after a run; a disposition before it does not close it
F10="$T/t10.jsonl"; : > "$F10"
plain "$F10" "hello"
[ "$(run s10 "$F10")" = 0 ] || fail "10: nothing to dispose must pass"
O1="$(cat "$SD/s10.offset")"
[ "$O1" = "$(wc -c < "$F10" | tr -d ' ')" ] || fail "10: offset must equal the bytes scanned"
lead "$F10" "OOS-1: fixed early"
handback "$F10" e5555555eeee "OOS-1: late find"
[ "$(run s10 "$F10")" = 2 ] || fail "10: a disposition before the hand-back must not close it"
O2="$(cat "$SD/s10.offset")"
[ "$O2" -gt "$O1" ] || fail "10: offset must grow"
# a shorter transcript resets the state
: > "$F10"; plain "$F10" "x"
[ "$(run s10 "$F10")" = 0 ] || fail "10: a truncated (rewritten) transcript must reset state"

# P. payload fallback (last_assistant_message)
# (a) disposition only in the payload, not in the transcript -> closed
FPa="$T/tpa.jsonl"; : > "$FPa"
handback "$FPa" a7777777aaaa "OOS-1: payload-only find"
[ "$(run spa "$FPa" false cli "OOS-1: fixed in the final reply")" = 0 ] || fail "Pa: a payload-only disposition must close the item"
# (b) collision: the payload closes the later item; its later transcript copy must not close the earlier
FPb="$T/tpb.jsonl"; : > "$FPb"
handback "$FPb" b8888888bbbb "OOS-1: earlier child"
handback "$FPb" c9999999cccc "OOS-1: later child"
[ "$(run spb "$FPb" false cli "OOS-1: fixed")" = 2 ] || fail "Pb: payload closes only the later item"
grep -q 'OOS-1@b8888888: earlier child' "$T/stderr" || fail "Pb: the earlier item must stay open"
grep -q 'c9999999' "$T/stderr" && fail "Pb: the later item must be the one closed"
[ "$(run spb "$FPb" false cli "OOS-1: fixed")" = 2 ] || fail "Pb: the same payload again (still unflushed) must not close a second item"
lead "$FPb" "OOS-1: fixed"
[ "$(run spb "$FPb" false cli "OOS-1: fixed")" = 2 ] || fail "Pb: the reply's transcript copy must not close the earlier item"
grep -q 'OOS-1@b8888888: earlier child' "$T/stderr" || fail "Pb: the earlier item must still be open"
lead "$FPb" "OOS-1: fixed"
[ "$(run spb "$FPb")" = 0 ] || fail "Pb: a NEW transcript reply with the same text is applied normally"
# (b2) same, but the next run has no payload at all
FPd="$T/tpd.jsonl"; : > "$FPd"
handback "$FPd" d1212121dddd "OOS-1: earlier child"
handback "$FPd" e3434343eeee "OOS-1: later child"
[ "$(run spd "$FPd" false cli "OOS-1: fixed")" = 2 ] || fail "Pb2: payload closes only the later item"
lead "$FPd" "OOS-1: fixed"
[ "$(run spd "$FPd")" = 2 ] || fail "Pb2: the transcript copy without a payload must not close the earlier item"
# (c) same reply in transcript and payload in one run -> applied once
FPc="$T/tpc.jsonl"; : > "$FPc"
handback "$FPc" f5656565ffff "OOS-1: earlier child"
handback "$FPc" a6767676aaaa "OOS-1: later child"
lead "$FPc" "OOS-1: fixed"
[ "$(run spc "$FPc" false cli "OOS-1: fixed")" = 2 ] || fail "Pc: a reply in both transcript and payload must apply once"
grep -q 'OOS-1@f5656565: earlier child' "$T/stderr" || fail "Pc: the earlier item must stay open"

# 12. a partial last line is not consumed until complete
F12="$T/t12.jsonl"; : > "$F12"
handback "$F12" f6666666ffff "OOS-1: partial find"
FULL="$(cat "$F12")"; : > "$F12"; printf '%s' "$FULL" > "$F12"
[ "$(run s12 "$F12")" = 0 ] || fail "12: a line without its newline must not be read"
[ "$(cat "$SD/s12.offset")" = 0 ] || fail "12: offset must stay before the partial line"
printf '\n' >> "$F12"
[ "$(run s12 "$F12")" = 2 ] || fail "12: once complete the line must be read"

# 11. fail-open paths, each against a payload that blocks without them (s8 still has OOS-1 open)
rm -rf "$SD"
[ "$(run s8 "$F8")" = 2 ] || fail "11: control payload must block"
rm -rf "$SD"
[ "$(run s8 "$F8" false sdk-cli)" = 0 ] || fail "11: non-cli entrypoint must fail open"
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off"; : > "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/oos-disposition-guard"
[ "$(run s8 "$F8")" = 0 ] || fail "11: kill switch must fail open"
rm -f "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/oos-disposition-guard"
jq -cn '{pluginConfigs:{"agent-tiers@local":{options:{group_delegation:false}}}}' > "$T/managed/managed-settings.json"
[ "$(run s8 "$F8")" = 0 ] || fail "11: delegation group stood down must fail open"
grep -q 'kit-gate standdown oos-disposition-guard: option group_delegation=false' "$AGENT_TIERS_GUARDS_LOG" || fail "11: stand-down must be logged by kit-gate"
rm -f "$T/managed/managed-settings.json"
[ "$(run s8 "$F8")" = 2 ] || fail "11: control after stand-down removal must block again"
rm -rf "$SD"
rc="$(jq -cn '{session_id:"s8", stop_hook_active:false}' | CLAUDE_CODE_ENTRYPOINT=cli sh "$H" >/dev/null 2>&1; echo $?)"
[ "$rc" = 0 ] || fail "11: missing transcript_path must fail open (rc=$rc)"
: > "$T/empty.jsonl"
[ "$(run s8 "$T/empty.jsonl")" = 0 ] || fail "11: empty transcript must fail open"

# R1. a hand-back delivered mid-turn (queued_command attachment) opens items; its later user-line copy
# is the same item
FR1="$T/tr1.jsonl"; : > "$FR1"
queued "$FR1" a1a1a1a1ffff "OOS-1: queued find"
[ "$(run sr1 "$FR1")" = 2 ] || fail "R1: a queued_command hand-back must open its items"
grep -q 'OOS-1@a1a1a1a1: queued find' "$T/stderr" || fail "R1: stderr must name the queued item"
lead "$FR1" "OOS-1: fixed"
handback "$FR1" a1a1a1a1ffff "OOS-1: queued find"
[ "$(run sr1 "$FR1")" = 0 ] || fail "R1: the user-line copy of a disposed hand-back must not reopen it"
[ "$(wc -l < "$SD/sr1.items" | tr -d ' ')" = 1 ] || fail "R1: both sightings must merge into one item"

# R2. anchored frame split: tags quoted inside a report (always indented) neither split nor end it
FR2="$T/tr2.jsonl"; : > "$FR2"
handback "$FR2" b2b2b2b2ffff "$(printf 'OOS-1: before\nquoting <agent-message from="zz99zz99"> mid-line\n[Subagent hand-back] quoted too\nOOS-2: after open tag\n</agent-message>\nOOS-3: after close tag')"
[ "$(run sr2 "$FR2")" = 2 ] || fail "R2: must block"
for k in 1 2 3; do grep -q "OOS-$k@b2b2b2b2" "$T/stderr" || fail "R2: OOS-$k must stay keyed to the real frame"; done
grep -q 'zz99zz99' "$T/stderr" && fail "R2: a quoted opening tag must not start a frame"
FR2b="$T/tr2b.jsonl"; : > "$FR2b"
jq -cn '{type:"user", message:{role:"user", content:"<agent-message from=\"c2c2c2c2ffff\">\n[Subagent hand-back] x\n  OOS-1: frame at start of text\n</agent-message>"}}' >> "$FR2b"
[ "$(run sr2b "$FR2b")" = 2 ] || fail "R2: a frame at the very start of the text must open"

# R3. send-back text asks for the footer; an ask_next reply is not sent back; lib missing -> no skip
[ "$(run sr2b "$FR2b")" = 2 ] || fail "R3: control must block"
grep -q 'AND end the reply with its normal operator: footer line' "$T/stderr" || fail "R3: send-back must ask for the footer line"
[ "$(run sr2b "$FR2b" false cli "$(printf 'Context here.\noperator:ask_next')")" = 0 ] || fail "R3: an ask_next reply must pass"
grep -q 'allow: ask_next reply, not checked \[sid=sr2b\]' "$AGENT_TIERS_GUARDS_LOG" || fail "R3: ask_next skip must be logged"
mv "$T/kit/scripts/lib/notify-tag.sh" "$T/notify-tag.sh.off"
[ "$(run sr2b "$FR2b" false cli "$(printf 'Context here.\noperator:ask_next')")" = 2 ] || fail "R3: lib missing must carry on without the skip"
mv "$T/notify-tag.sh.off" "$T/kit/scripts/lib/notify-tag.sh"

# R4. item parser: numbered and heading prefixes open; fenced lines and a child's own dispositions do not
FR4="$T/tr4.jsonl"; : > "$FR4"
handback "$FR4" d4d4d4d4ffff "$(printf '1. OOS-1: numbered dot\n2) OOS-2: numbered paren\n## OOS-3: heading\n```\nOOS-4: in a backtick fence\n~~~\nOOS-5: still in it\n```\n~~~sh\nOOS-6: in a tilde fence\n```\nOOS-7: still in the tilde fence\n~~~\nOOS-8: fixed in my own diff\nOOS-9: **Routed** to row X\nOOS-10: fixedpoint bug')"
[ "$(run sr4 "$FR4")" = 2 ] || fail "R4: must block"
[ "$(cut -f2 "$SD/sr4.items" | tr '\n' ' ')" = "1 2 3 10 " ] || fail "R4: items must be 1 2 3 10, got $(cut -f2 "$SD/sr4.items" | tr '\n' ' ')"

# R5. a disposition must start its line; one per line; a relayed item text is not its disposition
FR5="$T/tr5.jsonl"; : > "$FR5"
handback "$FR5" e5e5e5e5ffff "$(printf 'OOS-1: one\nOOS-2: two\nOOS-3: three\nOOS-4: four')"
lead "$FR5" "$(printf 'I think OOS-1: fixed would be wrong here.\n- OOS-2: fixed; OOS-3: fixed\n 1. **OOS-4**: routed to X')"
[ "$(run sr5 "$FR5")" = 2 ] || fail "R5: must block"
[ "$(awk -F'\t' '{ printf "%s%s ", $2, $3 }' "$SD/sr5.items")" = "1open 2closed 3open 4closed " ] || fail "R5: only line-start dispositions, one per line, may close"
FR5b="$T/tr5b.jsonl"; : > "$FR5b"
lead "$FR5b" "OOS-1: inbox path ignores X"
mkdir -p "$SD"; printf 'f5f5f5f5ffff\t1\topen\t\tinbox path ignores X\n' > "$SD/sr5b.items"
[ "$(run sr5b "$FR5b")" = 2 ] || fail "R5: a Lead relaying an item verbatim must not close it"
# a disposition inside a `>` quote (a Lead quoting a child's report) closes nothing
FR5q="$T/tr5q.jsonl"; : > "$FR5q"
handback "$FR5q" a5a5a5a5ffff "OOS-8: quoted case"
lead "$FR5q" "> OOS-8: fixed quoted"
[ "$(run sr5q "$FR5q")" = 2 ] || fail "R5: a quoted disposition must not close the item"
lead "$FR5q" "- OOS-8: fixed real"
[ "$(run sr5q "$FR5q")" = 0 ] || fail "R5: a bullet disposition must close the item"

# R9. a verb-start item line is dropped and logged once
FR9="$T/tr9.jsonl"; : > "$FR9"
handback "$FR9" a9b9c9d9ffff "$(printf 'OOS-1: keep me\nOOS-3: fixed something\nOOS-4: keep me too')"
[ "$(run sr9 "$FR9")" = 2 ] || fail "R9: the other items must block"
[ "$(grep -c 'dropped: verb-start item OOS-3@a9b9c9d9: fixed something \[sid=sr9\]' "$AGENT_TIERS_GUARDS_LOG")" = 1 ] || fail "R9: one dropped line must be logged"
run sr9 "$FR9" >/dev/null
[ "$(grep -c 'dropped: verb-start item OOS-3@' "$AGENT_TIERS_GUARDS_LOG")" = 1 ] || fail "R9: a run with no new lines must not log the drop again"

# R6. payload dedup against every A key of the chunk, and against the last A key of an earlier run
FR6="$T/tr6.jsonl"; : > "$FR6"
handback "$FR6" a6a6a6a6ffff "OOS-1: earlier child"
handback "$FR6" b6b6b6b6ffff "OOS-1: later child"
lead "$FR6" "OOS-1: fixed"
[ "$(run sr6 "$FR6" false cli "OOS-1: fixed")" = 2 ] || fail "R6: run 1 applies the reply once"
grep -q 'OOS-1@a6a6a6a6: earlier child' "$T/stderr" || fail "R6: run 1 must name the earlier item"
[ "$(run sr6 "$FR6" false cli "OOS-1: fixed")" = 2 ] || fail "R6: run 2, same payload, no new lines: not applied again"
grep -q 'OOS-1@a6a6a6a6: earlier child' "$T/stderr" || fail "R6: run 2 must still name the earlier item"
FR6b="$T/tr6b.jsonl"; : > "$FR6b"
handback "$FR6b" c6c6c6c6ffff "OOS-1: earlier child"
handback "$FR6b" d6d6d6d6ffff "OOS-1: later child"
lead "$FR6b" "OOS-1: fixed"
lead "$FR6b" "a later text block"
[ "$(run sr6b "$FR6b" false cli "OOS-1: fixed")" = 2 ] || fail "R6: a payload equal to a non-last A key of the chunk must not apply"

# R7. two concurrent Stops append exactly one inbox line (10 rounds)
runbg() { jq -cn --arg s "$1" --arg tp "$2" --arg c "$T" '{hook_event_name:"Stop", session_id:$s, transcript_path:$tp, cwd:$c, stop_hook_active:false}' \
  | CLAUDE_CODE_ENTRYPOINT=cli sh "$H" >/dev/null 2>&1; }
k=0
while [ "$k" -lt 10 ]; do
  k=$((k + 1)); F="$T/tc$k.jsonl"; : > "$F"
  handback "$F" f7f7f7f7ffff "OOS-1: concurrent find"
  lead "$F" "OOS-1: inbox for a kit session"
  runbg "sc$k" "$F" & runbg "sc$k" "$F" & wait
  [ "$(awk -F'\t' -v s="sc$k" '$3 == s' "$AGENT_TIERS_OOS_INBOX" | wc -l | tr -d ' ')" = 1 ] || fail "R7: round $k must append exactly one inbox line"
done
[ ! -d "$AGENT_TIERS_OOS_INBOX.lock" ] || fail "R7: the lock must be released"
# a stale lock (older than a minute) is removed and the append goes through
FR7s="$T/tr7s.jsonl"; : > "$FR7s"
handback "$FR7s" a7a7a7a7ffff "OOS-1: stale-lock find"
lead "$FR7s" "OOS-1: inbox for a kit session"
mkdir "$AGENT_TIERS_OOS_INBOX.lock"; touch -t 202001010000 "$AGENT_TIERS_OOS_INBOX.lock"
[ "$(run sr7s "$FR7s")" = 0 ] || fail "R7: stale lock run must pass"
[ "$(awk -F'\t' '$3 == "sr7s"' "$AGENT_TIERS_OOS_INBOX" | wc -l | tr -d ' ')" = 1 ] || fail "R7: a stale lock must be removed and the line appended"
grep -q 'inbox: removed stale lock \[sid=sr7s\]' "$AGENT_TIERS_GUARDS_LOG" || fail "R7: stale lock removal must be logged"
[ ! -d "$AGENT_TIERS_OOS_INBOX.lock" ] || fail "R7: the lock must be released after a stale removal"
# a fresh lock (a live holder) makes the append skip, within about 1 s
FR7f="$T/tr7f.jsonl"; : > "$FR7f"
handback "$FR7f" b7b7b7b7ffff "OOS-1: busy-lock find"
lead "$FR7f" "OOS-1: inbox for a kit session"
mkdir "$AGENT_TIERS_OOS_INBOX.lock"
t0="$(date +%s)"
[ "$(run sr7f "$FR7f")" = 0 ] || fail "R7: busy lock run must still pass"
t1="$(date +%s)"
rmdir "$AGENT_TIERS_OOS_INBOX.lock"
# Bound is 3 s: the wait is about 1 s nominal, date +%s has 1 s granularity, and a slow runner (the macOS CI
# leg, 2026-10-21) adds fork cost per try; 2 s read as 3 there.
[ $((t1 - t0)) -le 3 ] || fail "R7: a busy lock must not hold the run past 3 s (took $((t1 - t0)) s)"
[ "$(awk -F'\t' '$3 == "sr7f"' "$AGENT_TIERS_OOS_INBOX" | wc -l | tr -d ' ')" = 0 ] || fail "R7: a busy lock must skip the append"
grep -q 'inbox: lock busy, append skipped \[sid=sr7f\]' "$AGENT_TIERS_GUARDS_LOG" || fail "R7: lock busy must be logged"

# R8. OOS_GUARD_CAP: an item before the window is not seen, one inside it is, the skip is logged
FR8="$T/tr8.jsonl"; : > "$FR8"
handback "$FR8" a8a8a8a8ffff "OOS-1: before the window"
k=0; while [ "$k" -lt 40 ]; do k=$((k + 1)); plain "$FR8" "filler line $k padding padding padding padding padding padding"; done
handback "$FR8" b8b8b8b8ffff "OOS-2: inside the window"
export OOS_GUARD_CAP=1500
[ "$(run sr8 "$FR8")" = 2 ] || fail "R8: the item inside the window must block"
unset OOS_GUARD_CAP
grep -q 'OOS-2@b8b8b8b8' "$T/stderr" || fail "R8: the item inside the window must be named"
grep -q 'OOS-1@a8a8a8a8' "$T/stderr" && fail "R8: the item before the window must not be seen"
grep -q 'oos-disposition-guard skipped: [0-9]* older bytes not scanned \[sid=sr8\]' "$AGENT_TIERS_GUARDS_LOG" || fail "R8: the skip must be logged"

# state cleanup: files older than the window are deleted
mkdir -p "$SD"; : > "$SD/old.offset"; touch -t 202001010000 "$SD/old.offset"
run s5 "$F5" >/dev/null
[ ! -e "$SD/old.offset" ] || fail "old state must be cleaned up"

echo "PASS oos-disposition-guard.sh"

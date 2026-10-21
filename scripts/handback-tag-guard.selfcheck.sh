#!/usr/bin/env sh
# kit-scope: shared
# Self-check for handback-tag-guard.sh: untagged `!` command forms block (fenced, list-indented,
# two in one fence, heredoc, inline), tagged and exempt forms pass (tag in fence, tag above the
# opening fence, tag + inline, one tag covering a fence, placeholder, table row, no `!`), a footer
# tag never satisfies the check, a git `! [rejected]` line / a shell-script negation / a heredoc body
# line / a cue word inside another word never block, ~~~ and longer fences are tracked, the guard
# blocks a reply once (marker) and then lets the identical one through, and empty message / non-cli
# entrypoint / absent jq / absent lib fail open, and a block (or a tagged allow) is logged.
set -u
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP handback-tag-guard: jq absent (guard fails open by design)"; exit 0; }

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
fail() { printf 'FAIL: %s\n' "$1"; rm -rf "$T"; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/kit/scripts" "$T/kit/install" "$T/managed"
cp "$SRC_DIR/handback-tag-guard.sh" "$T/kit/scripts/" || fail "cannot copy guard into sandbox"
cp -R "$SRC_DIR/lib" "$SRC_DIR/guard-cmdpos.sh" "$T/kit/scripts/" || fail "cannot copy lib into sandbox"
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$SRC_DIR/kit-gate.sh" > "$T/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$T/kit/scripts/kit-gate.sh" || fail "_kg_managed not rewritten"
cp "$SRC_DIR/../install/options.tsv" "$T/kit/install/"
H="$T/kit/scripts/handback-tag-guard.sh"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export AGENT_TIERS_GUARDS_LOG="$T/guards.log"
export CLAUDE_CONFIG_DIR="$T/cfg"
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state"
MK="$T/kit/.state/handback-tag-guard"

run_keep() { # $1=message, $2=session id (default s1): keeps the once-per-reply markers
  jq -cn --arg m "$1" --arg s "${2:-s1}" '{hook_event_name:"Stop", session_id:$s, last_assistant_message:$m}' \
    | CLAUDE_CODE_ENTRYPOINT=cli sh "$H" >"$T/stdout" 2>"$T/stderr"
  echo "$?"
}
run() { rm -rf "$MK"; run_keep "$@"; }
BT='`'; FENCE='```'
block() { [ "$(run "$2")" = 2 ] || fail "should block: $1"; }
pass() { [ "$(run "$2")" = 0 ] || fail "should pass: $1"; }

# HIT
block "fenced untagged" "$(printf 'Run:\n%s\n! sudo pacman -S x\n%s\n' "$FENCE" "$FENCE")"
grep -q 'sudo pacman' "$T/stderr" || fail "block message should list the flagged line"
grep -q 'operator:run|kind:policy' "$T/stderr" || fail "block message should name the tags"
grep -q 'operator: footer' "$T/stderr" || fail "block message should tell the model to end on its footer line"
grep -q 'handback-tag-guard' "$AGENT_TIERS_GUARDS_LOG" || fail "a block should be logged"
block "list-indented fence" "$(printf '1. Do this:\n   %s\n   ! cmd\n   %s\n' "$FENCE" "$FENCE")"
block "two untagged in one fence" "$(printf '%s\n! one\n! two\n%s\n' "$FENCE" "$FENCE")"
block "heredoc untagged" "$(printf '%s\n! python3 - <<'"'"'EOF'"'"'\nprint(1)\nEOF\n%s\n' "$FENCE" "$FENCE")"
block "inline untagged" "$(printf 'run this yourself: %s! mkdir -p x%s\n' "$BT" "$BT")"
block "footer tag directly above does not count" "$(printf 'operator:want_input\n%s\n! cmd\n%s\n' "$FENCE" "$FENCE")"
block "tag, blank line, command" "$(printf 'operator:run|kind:oneoff\n\n! cmd\n')"
block "tag, blank line, fence, command" "$(printf 'operator:run|kind:oneoff\n\n%s\n! cmd\n%s\n' "$FENCE" "$FENCE")"
block "run as a whole word" "then run: ${BT}! mkdir x${BT}"
block "comment line before the first ! line" "$(printf 'Install it:\n%ssh\n# needs root\n! sudo pacman -S x\n%s\n' "$FENCE" "$FENCE")"
block "blank and comment lines between ! lines, untagged" "$(printf '%s\n! one\n\n# c\n! two\n%s\n' "$FENCE" "$FENCE")"
block "inline no space after the bang" "Run ${BT}!ls -la${BT} yourself."
block "fence with a no-space bang line" "$(printf '%s\n!sudo pacman -S x\n%s\n' "$FENCE" "$FENCE")"
block "triple-backtick inline is not a fence" "$(printf '%s! ls%s\nLater prose\n! sudo reboot\nmore\n' "$FENCE" "$FENCE")"
pass "shebang then comment then a pipeline negation" "$(printf '%ssh\n#!/bin/sh\n# fail if x present\n! grep -q x f\necho ok\n%s\n' "$FENCE" "$FENCE")"
pass "notebook ! escape in a python fence" "$(printf '%spython\n#!/usr/bin/env python3\n# x\n!pip install foo\n%s\n' "$FENCE" "$FENCE")"
pass "no-space bang before a capital in prose" "$(printf '!Important: back up first.\n')"
pass "no-space bang before a dollar" "If you run it, ${BT}!\$${BT} reuses the last arg."
block "a warning is flagged (known false positive)" "Don't run ${BT}! git reset --hard${BT} - it is destructive."
pass "unclosed fence: a later command hides (known limit, not rebuilt)" "$(printf '%s\nunclosed\n! sudo reboot\n' "$FENCE")"
block "tilde fence" "$(printf '~~~\n! cmd\n~~~\n')"
block "longer fence, shorter inner line does not close it" "$(printf '````\n! cmd\n```\n````\n')"

# PASS
pass "tag inside the fence" "$(printf '%s\noperator:run|kind:oneoff\n! sudo pacman -S x\n%s\n' "$FENCE" "$FENCE")"
pass "tag, opening fence, command" "$(printf 'operator:run|kind:oneoff\n%s\n! cmd\n%s\n' "$FENCE" "$FENCE")"
pass "tag then inline" "$(printf 'run it:\noperator:run|kind:oneoff\nrun %s! git status%s\n' "$BT" "$BT")"
pass "one tag covers a fence" "$(printf '%s\noperator:run|kind:policy\n! one\n! two\n%s\n' "$FENCE" "$FENCE")"
pass "placeholder form" "deny, with the exact command for you to run as ${BT}! <cmd>${BT}"
pass "table row" "| fix | ${BT}! sudo chown x${BT} |"
pass "the prefix phrase" "$(printf 'Use the %s!%s prefix like this: %s! ls%s\n' "$BT" "$BT" "$BT" "$BT")"
pass "no ! lines" "Nothing to run here. Hello!"
pass "footer plus tagged command" "$(printf '%s\noperator:run|kind:oneoff\n! cmd\n%s\noperator:want_input\n' "$FENCE" "$FENCE")"
pass "empty message" ""
# lines that look like `! x` but are not hand-backs
pass "git rejected output" "$(printf '%s\n ! [rejected]        master -> master (fetch first)\n%s\n' "$FENCE" "$FENCE")"
pass "git rejected output, first line of fence" "$(printf '%s\n! [rejected]        master -> master (fetch first)\n%s\n' "$FENCE" "$FENCE")"
pass "shell negation after other content" "$(printf '%s\nset -e\n! grep -q x file\n%s\n' "$FENCE" "$FENCE")"
pass "heredoc body line" "$(printf '%s\ncat <<EOF\n! grep body\nEOF\n%s\n' "$FENCE" "$FENCE")"
pass "rerun is not run" "rerun later: ${BT}! mkdir x${BT}"
pass "runtime is not run" "the runtime does ${BT}! mkdir x${BT} itself"
pass "tag above a fence whose first content line is blank" "$(printf 'operator:run|kind:oneoff\n%s\n\n! sudo pacman -S x\n%s\n' "$FENCE" "$FENCE")"
pass "comment line first, tagged above the fence" "$(printf 'operator:run|kind:oneoff\n%ssh\n# needs root\n! sudo pacman -S x\n%s\n' "$FENCE" "$FENCE")"
pass "blank and comment lines between ! lines, tagged above the fence" "$(printf 'operator:run|kind:oneoff\n%s\n! one\n\n# c\n! two\n%s\n' "$FENCE" "$FENCE")"
pass "bang-bracket output without a space" "$(printf '%s\n![rejected] master -> master\n%s\n' "$FENCE" "$FENCE")"
pass "tag above a longer fence" "$(printf 'operator:run|kind:oneoff\n````\n! cmd\n```\n````\n')"
block "a ! line after the fence closed is outside it and counts" "$(printf '%s\nls\n%s\n! grep x\n' "$FENCE" "$FENCE")"
pass "tag above the opening fence of a tilde fence" "$(printf 'operator:run|kind:policy\n~~~\n! cmd\n~~~\n')"
rc="$(jq -cn --arg m "$(printf '%s\n! cmd\n%s\n' "$FENCE" "$FENCE")" '{last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=sdk-cli sh "$H" >/dev/null 2>&1; echo $?)"
[ "$rc" = 0 ] || fail "non-cli entrypoint must not block (rc=$rc)"

# H1: a reply ending operator:ask_next is not checked (notify-tag-guard owns that send-back)
X1="$(printf 'Two options. A keeps the cache; B wipes it. If you pick B, run this first:\n%s\n! rm -rf ~/.cache/foo\n%s\noperator:ask_next\n' "$FENCE" "$FENCE")"
[ "$(run "$X1")" = 0 ] || fail "an ask_next reply must not be blocked by this guard"
grep -q 'allow: ask_next reply' "$AGENT_TIERS_GUARDS_LOG" || fail "an ask_next reply must log its allow line"
[ "$(run "$(printf '%s\n! rm -rf x\n%s\noperator:want_input\n' "$FENCE" "$FENCE")")" = 2 ] || fail "untagged command in a want_input reply must block"
grep -q 'operator: footer' "$T/stderr" || fail "want_input reply keeps the generic wording"
grep -q 'operator:ask_next again' "$T/stderr" && fail "want_input reply must not get the ask_next wording"

# block ONCE per offending reply (marker), not keyed off stop_hook_active
R1="$(printf '%s\n! sudo once\n%s\n' "$FENCE" "$FENCE")"
R2="$(printf '%s\n! sudo other\n%s\n' "$FENCE" "$FENCE")"
rm -rf "$MK"
[ "$(run_keep "$R1")" = 2 ] || fail "first sight of an untagged reply must block"
[ "$(run_keep "$R1")" = 0 ] || fail "the identical reply a second time must pass (blocked once)"
grep -q 'already blocked once' "$AGENT_TIERS_GUARDS_LOG" || fail "the once-only pass should be logged"
[ "$(run_keep "$R2")" = 2 ] || fail "a DIFFERENT untagged reply after that must block again"
[ "$(run_keep "$R1" other-session)" = 2 ] || fail "the marker is per session: the same reply in another session blocks"
# M1: a marker older than 10 minutes no longer suppresses; a younger one does. L1: no temp file is left behind
. "$T/kit/scripts/lib/handback-tag.sh"
rm -rf "$MK"; run_keep "$R1" >/dev/null
HBM="$(handback_tag_marker "$T/kit" s1 "$(handback_tag_flagged "$R1")")"
[ -f "$HBM" ] || fail "test setup: the marker path should match the guard's"
ls "$MK" | grep -q '^[.]tmp' && fail "the atomic write must not leave its temp file behind"
echo $(( $(date +%s) - 660 )) > "$HBM"
[ "$(run_keep "$R1")" = 2 ] || fail "the same reply with a marker aged 11 minutes must block again"
echo $(( $(date +%s) - 540 )) > "$HBM"
[ "$(run_keep "$R1")" = 0 ] || fail "the same reply with a marker aged 9 minutes must pass"
: > "$HBM"
[ "$(run_keep "$R1")" = 2 ] || fail "an empty marker does not suppress"
handback_tag_pending "$HBM" || fail "an empty marker counts as pending for the notifier"
echo $(( $(date +%s) - 660 )) > "$HBM"
handback_tag_pending "$HBM" || fail "a stale marker counts as pending (the guard blocks again)"
echo $(( $(date +%s) - 60 )) > "$HBM"
handback_tag_pending "$HBM" && fail "a marker between 5 s and 10 min old is not pending"
# L6a: without a session id the marker is keyed nosid-<pid>
rm -rf "$MK"
jq -cn --arg m "$R1" '{hook_event_name:"Stop", last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=cli sh "$H" >/dev/null 2>&1
ls "$MK" | grep -q '^nosid-[0-9]*-' || fail "no session id: the marker should be keyed nosid-<ppid>"
# L6b: an unattended session is never blocked
: > "$T/kit/.state/unattended.s1"
: > "$AGENT_TIERS_GUARDS_LOG"
[ "$(run "$R1")" = 0 ] || fail "an unattended session must not be blocked"
grep -q 'allow: unattended' "$AGENT_TIERS_GUARDS_LOG" || fail "the unattended pass should be logged"
rm -f "$T/kit/.state/unattended.s1"
[ "$(run "$R1")" = 2 ] || fail "once the unattended flag is gone the guard blocks again"
rm -rf "$MK"
rc="$(jq -cn --arg m "$R1" '{stop_hook_active:true, last_assistant_message:$m}' | CLAUDE_CODE_ENTRYPOINT=cli sh "$H" >/dev/null 2>&1; echo $?)"
[ "$rc" = 2 ] || fail "stop_hook_active true must not make the guard blind (rc=$rc)"
# markers older than 7 days are deleted on each run
mkdir -p "$MK"; : > "$MK/stale"; touch -t 202001010000 "$MK/stale"
run_keep "$R2" >/dev/null
[ ! -e "$MK/stale" ] || fail "a marker older than 7 days should be cleaned up"
# a tagged reply logs the allow line; a reply with no hand-back logs nothing
: > "$AGENT_TIERS_GUARDS_LOG"
pass "tagged logs allow" "$(printf 'operator:run|kind:oneoff\n%s\n! cmd\n%s\n' "$FENCE" "$FENCE")"
grep -q 'allow: tagged hand-back' "$AGENT_TIERS_GUARDS_LOG" || fail "an all-tagged hand-back should log 'allow: tagged hand-back'"
: > "$AGENT_TIERS_GUARDS_LOG"
pass "no hand-back logs nothing" "plain text"
[ ! -s "$AGENT_TIERS_GUARDS_LOG" ] || fail "a reply with no hand-back should log nothing"

# absent jq, for real: the SAME payload blocks with jq on PATH and exits 0 with a PATH lacking jq
PAYLOAD="$T/payload.json"
rm -rf "$MK"
jq -cn --arg m "$R1" '{hook_event_name:"Stop", session_id:"s9", last_assistant_message:$m}' > "$PAYLOAD"
rc="$(CLAUDE_CODE_ENTRYPOINT=cli sh "$H" < "$PAYLOAD" >/dev/null 2>&1; echo $?)"
[ "$rc" = 2 ] || fail "test setup: the payload must block with jq present (rc=$rc)"
rm -rf "$MK"
NOJQ="$T/nojq"; mkdir -p "$NOJQ"
for b in sh cat dirname date mkdir awk sed find cksum tr grep; do p="$(command -v $b)" && ln -s "$p" "$NOJQ/$b"; done
rc="$(PATH="$NOJQ" CLAUDE_CODE_ENTRYPOINT=cli "$NOJQ/sh" "$H" < "$PAYLOAD" >/dev/null 2>&1; echo $?)"
[ "$rc" = 0 ] || fail "absent jq must fail open (rc=$rc)"

# absent lib fails open and logs
NOLIB="$T/nolib/scripts"; mkdir -p "$NOLIB" "$T/nolib/install"
cp "$T/kit/scripts/handback-tag-guard.sh" "$T/kit/scripts/kit-gate.sh" "$NOLIB/"; cp "$T/kit/install/options.tsv" "$T/nolib/install/"
rc="$(CLAUDE_CODE_ENTRYPOINT=cli sh "$NOLIB/handback-tag-guard.sh" < "$PAYLOAD" >/dev/null 2>&1; echo $?)"
[ "$rc" = 0 ] || fail "an absent lib must fail open (rc=$rc)"
grep -q 'fail-open: lib/handback-tag.sh' "$AGENT_TIERS_GUARDS_LOG" || fail "the absent-lib fail-open should be logged"

# kill switch
mkdir -p "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off"; : > "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/handback-tag-guard"
pass "kill switch" "$(printf '%s\n! cmd\n%s\n' "$FENCE" "$FENCE")"
rm -f "$CLAUDE_CONFIG_DIR/agent-tiers/.state/off/handback-tag-guard"

echo "PASS handback-tag-guard.sh"

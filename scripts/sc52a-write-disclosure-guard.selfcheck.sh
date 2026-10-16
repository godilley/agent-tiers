#!/usr/bin/env sh
# kit-scope: shared
# Self-check for sc52a-write-disclosure-guard.sh. Runnable: `sh sc52a-write-disclosure-guard.selfcheck.sh`.
# Builds a sandboxed kit copy (script + guard-cmdpos.sh) AND a real throwaway git repo for the WORK tree
# (the guard reads git state off the payload's .cwd), same two-tree idiom as
# vcs-commit-guard.selfcheck.sh. Exits non-zero on first failure.
set -u
SRC_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

# 0. Host regex probe (same shape as dangerous-actions-blocker.selfcheck.sh's) - the guard's sed/tee
# match is anchored on `\b`, a GNU ERE extension. A grep whose engine treats it as a literal `b` makes
# the guard wired-but-never-fires; this asserts the HOST'S grep honours it rather than passing vacuously.
if [ "$(printf 'sed x\n' | grep -cE 'sed\b' 2>/dev/null)" != 1 ] || [ "$(printf 'sedx\n' | grep -cE 'sed\b' 2>/dev/null)" != 0 ]; then
  fail "this host's grep does not honour the \\b word boundary (uname: $(uname -s)) - the guard would silently never match sed/tee"
fi
printf 'ok   host grep honours \\b (%s)\n' "$(uname -s)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"   # macOS TMPDIR ends in "/" - a "//" breaks pwd comparisons
T="${TMPBASE}/at-sc52a-selfcheck.$$"
rm -rf "$T"; mkdir -p "$T/kit/scripts" "$T/work" || fail "cannot build sandbox"
cp "$SRC_DIR/sc52a-write-disclosure-guard.sh" "$T/kit/scripts/" || fail "cannot copy guard"
cp "$SRC_DIR/guard-cmdpos.sh" "$T/kit/scripts/" || fail "cannot copy guard-cmdpos.sh"
GUARD="$T/kit/scripts/sc52a-write-disclosure-guard.sh"
WORK="$T/work"
trap 'rm -rf "$T"' EXIT
# kit-gate sandbox: the guard now reads live kit state and the user's settings through kit-gate.sh, so the
# sandbox kit gets a rewritten gate (managed dir -> an empty temp dir) + options table, and every
# kit-gate input is cleared. Guards log stays the sandbox kit's own .state/guards.log.
mkdir -p "$T/kit/install" "$T/cfg" "$T/managed"
sed "s|^_kg_managed=.*|_kg_managed='$T/managed'|" "$SRC_DIR/kit-gate.sh" > "$T/kit/scripts/kit-gate.sh"
grep -qxF "_kg_managed='$T/managed'" "$T/kit/scripts/kit-gate.sh" || fail "_kg_managed not rewritten"
cp "$SRC_DIR/../install/options.tsv" "$T/kit/install/"
export CLAUDE_CONFIG_DIR="$T/cfg"
unset AGENT_TIERS_OFF CLAUDE_PLUGIN_ROOT CLAUDE_CODE_SESSION_ID AGENT_TIERS_GUARDS_LOG
for v in $(env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done

git -C "$WORK" init -q
git -C "$WORK" config user.email test@test.local
git -C "$WORK" config user.name test
printf 'a\n' > "$WORK/tracked.txt"
git -C "$WORK" add tracked.txt
git -C "$WORK" commit -q -m init
printf 'scratch\n' > "$WORK/untracked.txt"

run() { # $1=cmd $2=extra jq (optional, e.g. --arg agent worker '.agent_type=$agent') -> raw guard stdout
  cmd="$1"
  jq -n --arg x "$cmd" --arg c "$WORK" '{cwd: $c, tool_input: {command: $x}, session_id: "sc52a-test"}' | sh "$GUARD" 2>/dev/null || true
}
decision() { printf '%s' "$1" | grep -aoE '"permissionDecision": *"[a-z]+"' | grep -aoE '"[a-z]+"$' | tr -d '"'; }

# 1. sed -i on a tracked file, no marker -> deny (guard-ask-deny rule: this is a FORM problem, the
# agent can fix it itself), reason names the [bash-write:] escape hatch.
out="$(run "sed -i 's/a/b/' tracked.txt")"
[ "$(decision "$out")" = "deny" ] || fail "1: expected deny on sed -i tracked.txt, got: $out"
case "$out" in *"tracked.txt"*"SC-5.2a"*) ;; *) fail "1: reason must name the file and SC-5.2a, got: $out" ;; esac
case "$out" in *"[bash-write:"*) ;; *) fail "1: reason must name the [bash-write:] escape hatch, got: $out" ;; esac

# 2. sed -i on an UNTRACKED file -> silent (nothing to protect).
out="$(run "sed -i 's/a/b/' untracked.txt")"
[ -z "$out" ] || fail "2: expected silence on an untracked target, got: $out"

# 3. sed -i on tracked WITH the escape-hatch marker, as a trailing shell COMMENT (2026-09-14,
#    adversarial review, MEDIUM: a bare trailing word is a live footgun - on `sed` it is read as an
#    extra file argument to edit, on `tee` it creates a stray file literally named `[bash-write:...]`) ->
#    silent, and the skip is logged.
LOGDIR="$T/kit/.state"; rm -rf "$LOGDIR"
out="$(AGENT_TIERS_GUARDS_LOG="$LOGDIR/guards.log" run "sed -i 's/a/b/' tracked.txt  # [bash-write:bulk rename]")"
[ -z "$out" ] || fail "3: expected silence with the [bash-write:] marker as a trailing comment, got: $out"
grep -aq 'skip: \[bash-write:bulk rename\]' "$LOGDIR/guards.log" || fail "3: skip was not logged with the marker text"

# 3b. Real-world proof (not just the hook decision): the SAME sed command, marker as a trailing
#     comment, actually EDITS the real target and touches no other file - a bare trailing word here
#     would have made sed treat it as a SECOND file argument to edit.
#     `-i.bak` (attached suffix) because BSD sed reads a bare `-i` as taking the script as its suffix.
printf 'a\n' > "$WORK/proof.txt"
(cd "$WORK" && sed -i.bak 's/a/b/' proof.txt  # [bash-write:bulk rename proof]
)
rm -f "$WORK/proof.txt.bak"
[ "$(cat "$WORK/proof.txt")" = "b" ] || fail "3b: the trailing-comment marker interfered with the real sed edit"
[ ! -e "$WORK/[bash-write:bulk rename proof]" ] || fail "3b: sed treated the marker as a second file argument"
rm -f "$WORK/proof.txt"

# 3c. Same proof for `tee`: a bare trailing word after `tee target` becomes a SECOND target tee writes
#     to (a stray file literally named `[bash-write:...]`); a trailing comment does not.
(cd "$WORK" && echo hi | tee proof2.txt  # [bash-write:bulk rename proof]
) >/dev/null
[ "$(cat "$WORK/proof2.txt" 2>/dev/null)" = "hi" ] || fail "3c: the trailing-comment marker interfered with the real tee write"
[ ! -e "$WORK/[bash-write:bulk rename proof]" ] || fail "3c: tee wrote a stray file named after the marker"
rm -f "$WORK/proof2.txt"

# 4. tee writing a tracked file -> deny.
out="$(run "echo hi | tee tracked.txt")"
[ "$(decision "$out")" = "deny" ] || fail "4: expected deny on tee tracked.txt, got: $out"
case "$out" in *"[bash-write:"*) ;; *) fail "4: reason must name the [bash-write:] escape hatch, got: $out" ;; esac

# 4a. A redirect after the target (`tee tracked.txt >/dev/null`, the standard write-without-echo
# idiom) must not let `>/dev/null` win the last-arg heuristic over the real target.
out="$(run "tee tracked.txt >/dev/null")"
[ "$(decision "$out")" = "deny" ] || fail "4a: a trailing redirect must not hide the real target, got: $out"
case "$out" in *"'tracked.txt'"*) ;; *) fail "4a: reason must name tracked.txt, not the redirect, got: $out" ;; esac
case "$out" in *"[bash-write:"*) ;; *) fail "4a: reason must name the [bash-write:] escape hatch, got: $out" ;; esac

# 4b. Same, for sed -i with a suppressed stderr redirect.
out="$(run "sed -i 's/a/b/' tracked.txt 2>/dev/null")"
[ "$(decision "$out")" = "deny" ] || fail "4b: a trailing stderr redirect must not hide the real target, got: $out"
case "$out" in *"[bash-write:"*) ;; *) fail "4b: reason must name the [bash-write:] escape hatch, got: $out" ;; esac

# 5. An unrelated command -> silent.
out="$(run "ls -la")"
[ -z "$out" ] || fail "5: expected silence on an unrelated command, got: $out"

# 6. A subagent caller denies (this guard has no ask state - it always denies, for every caller).
cmd="sed -i 's/a/b/' tracked.txt"
out="$(jq -n --arg x "$cmd" --arg c "$WORK" --arg a "worker" '{cwd: $c, tool_input: {command: $x}, session_id: "sc52a-test", agent_type: $a, agent_id: "a0test"}' | sh "$GUARD" 2>/dev/null || true)"
[ "$(decision "$out")" = "deny" ] || fail "6: expected deny for a subagent caller, got: $out"
case "$out" in *"You cannot judge whether this exception is warranted"*) ;; *) fail "6: subagent deny must carry the subagent-specific closing sentence, got: $out" ;; esac
case "$out" in *"UNATTENDED MODE"*|*"DELEGATED AGENT"*) fail "6: this deny is unconditional for every caller - it must not carry the misleading ask-was-converted framing text, got: $out" ;; esac

# 6b. LOW (adversarial review): a subagent cannot self-clear this gate with its OWN [bash-write:]
#     marker either - the marker check runs AFTER AGENT_TYPE is known now, and only a Lead's marker
#     allows. A subagent's marker is logged as ignored and the command still denies.
cmd="sed -i 's/a/b/' tracked.txt  # [bash-write:worker self-declared, should not clear]"
out="$(AGENT_TIERS_GUARDS_LOG="$LOGDIR/guards.log" jq -n --arg x "$cmd" --arg c "$WORK" --arg a "worker" '{cwd: $c, tool_input: {command: $x}, session_id: "sc52a-test", agent_type: $a, agent_id: "a0test"}' | sh "$GUARD" 2>/dev/null || true)"
[ "$(decision "$out")" = "deny" ] || fail "6b: a subagent's own [bash-write:] marker must not clear the gate, got: $out"
grep -aq 'ignored: \[bash-write:worker self-declared' "$LOGDIR/guards.log" || fail "6b: the ignored-subagent-marker breadcrumb was not logged"

# 7. Fail-open: not a git repo at all -> silent, never a false ask.
NOGIT="$T/nogit"; mkdir -p "$NOGIT"
out="$(jq -n --arg x "sed -i 's/a/b/' f.txt" --arg c "$NOGIT" '{cwd: $c, tool_input: {command: $x}, session_id: "sc52a-test"}' | sh "$GUARD" 2>/dev/null || true)"
[ -z "$out" ] || fail "7: expected silence outside a git repo, got: $out"

# 8. Edit/Write-shaped commands (the normal path) never trip this guard - only sed -i / tee do.
out="$(run "cat tracked.txt")"
[ -z "$out" ] || fail "8: a plain read must never trip this guard, got: $out"

# kit-gate stand-down: marker <kit>/.state/off/sc52a-write-disclosure-guard -> silent exit 0 + a kit-gate log line.

sd_in() { jq -n --arg x "sed -i 's/a/b/' tracked.txt" --arg c "$WORK" '{cwd: $c, tool_input: {command: $x}, session_id: "sc52a-test"}'; }
sd_out="$(sd_in | sh "$GUARD" 2>/dev/null)"
case "$sd_out" in *'"permissionDecision"'*) ;; *) fail "standdown control: expected a decision without the marker, got: $sd_out" ;; esac
mkdir -p "$T/kit/.state/off"; : > "$T/kit/.state/off/sc52a-write-disclosure-guard"; rm -f "$T/kit/.state/guards.log"
sd_out="$(sd_in | sh "$GUARD" 2>/dev/null)"; sd_rc=$?
[ -z "$sd_out" ] && [ "$sd_rc" = 0 ] || fail "standdown: expected empty stdout + exit 0, got rc=$sd_rc out=$sd_out"
grep -aq 'kit-gate standdown sc52a-write-disclosure-guard:' "$T/kit/.state/guards.log" || fail "standdown: no kit-gate log line"
rm -f "$T/kit/.state/off/sc52a-write-disclosure-guard"
printf 'ok   [standdown] marker present -> silent exit 0 + log line\n'

echo "OK sc52a-write-disclosure-guard: deny with the [bash-write:] escape hatch (a trailing shell comment, proven to not interfere with the real sed/tee write) on a tracked sed-i/tee write, silent on untracked/marked/unrelated, a subagent cannot self-clear with its own marker, fails open outside a repo"

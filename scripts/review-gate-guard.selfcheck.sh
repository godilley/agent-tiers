#!/usr/bin/env sh
# kit-scope: shared
# Self-check for review-gate-guard.sh. Runnable: `sh review-gate-guard.selfcheck.sh`. Sandboxed kit copy
# (script + guard-cmdpos.sh, so BASE and the .state marker dir resolve inside the sandbox) + synthetic
# transcripts. Exits non-zero on first failure.
set -u
SRC_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"   # macOS TMPDIR ends in "/" - a "//" in T breaks every pwd comparison (CI, 2026-08-16)
T="${TMPBASE}/at-reviewgate-selfcheck.$$"
rm -rf "$T"; mkdir -p "$T/kit/scripts" || fail "cannot build sandbox"
cp "$SRC_DIR/review-gate-guard.sh" "$T/kit/scripts/" || fail "cannot copy guard"
cp "$SRC_DIR/guard-cmdpos.sh" "$T/kit/scripts/" || fail "cannot copy guard-cmdpos.sh"
GUARD="$T/kit/scripts/review-gate-guard.sh"
trap 'rm -rf "$T"' EXIT

# Every fixture starts with the agent-listing attachment the CLI writes into REAL transcripts (it quotes
# agent descriptions, including one that names reviewer/advisor/codex-read and "/codex:review"), plus a
# corrupt line and a Bash tool_use whose command TEXT contains the field - the first draft of this guard
# text-grepped and matched all of these, so it could never fire on a real transcript.
LISTING='{"attachment":{"type":"agent_listing_delta","agents":[{"name":"codex-write","description":"Not a reviewer - a codex REVIEW routes to codex-read or the /codex:review plugin. subagent_type: reviewer advisor codex-read"}]}}
not json at all {"subagent_type":"reviewer"
{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"printf {\"subagent_type\":\"reviewer\"} > f"}}]}}
{"message":{"content":[{"type":"tool_result","content":"file says \"subagent_type\":\"advisor\""}]}}'
NOREV="$T/norev.jsonl"      # worker spawn only (+ the noise above)
REV="$T/rev.jsonl"          # reviewer spawn via Agent (compact JSON, as the CLI writes it)
ADV="$T/adv.jsonl"          # advisor spawn via Task, jq-style spaced JSON
CDX="$T/cdx.jsonl"          # codex-read spawn
{ printf '%s\n' "$LISTING"; printf '{"message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"worker","prompt":"x"}}]}}\n'; } > "$NOREV"
{ printf '%s\n' "$LISTING"; printf '{"message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"reviewer","prompt":"x"}}]}}\n'; } > "$REV"
{ printf '%s\n' "$LISTING"; printf '{"message": {"content": [{"type": "tool_use", "name": "Task", "input": {"subagent_type": "advisor"}}]}}\n'; } > "$ADV"
{ printf '%s\n' "$LISTING"; printf '{"message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"codex-read"}}]}}\n'; } > "$CDX"

# Two throwaway git repos so the per-repo marker can be exercised.
mkdir -p "$T/repoA" "$T/repoB"
for r in repoA repoB; do (cd "$T/$r" && git init -q && git config user.email t@t && git config user.name t && printf x > f && git add f && git commit -qm i); done
CWD="$T/repoA"
run() { # $1=cmd $2=transcript $3=session_id $4=agent_type(optional, 2026-08-27) -> ask|allow|deny ; cwd = $CWD
  out="$(jq -n --arg x "$1" --arg t "$2" --arg s "$3" --arg c "$CWD" --arg a "${4:-}" \
         '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}} + (if $a != "" then {agent_type: $a} else {} end)' \
         | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then echo deny
  elif printf '%s' "$out" | grep -aq '"permissionDecision": *"ask"'; then echo ask
  else echo allow; fi
}
check() { want="$1"; shift; got="$(run "$@")"
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s\n' "$got" "$1"; else fail "want=$want got=$got : $1 ($2)"; fi
}

# 1. Non-commit commands never ask, whatever the transcript.
check allow "git status" "$NOREV" s1
check allow "git add -A" "$NOREV" s1
check allow "echo git commit" "$NOREV" s1

# 2. A commit in a session with no independent pass asks - across every commit spelling the sibling
#    guards recognise (chained segment, flags).
check ask "git commit -m x" "$NOREV" s2
check ask "git add a && git commit -m x" "$NOREV" s3
check ask "git commit -am 'x'" "$NOREV" s4

# 3. Any real review-class spawn silences it - Agent or Task, both JSON spacings - while the listing
#    attachment, the corrupt line, the Bash command text and the tool_result mention (all in NOREV) never do.
check allow "git commit -m x" "$REV" s5
check allow "git commit -m x" "$ADV" s6
check allow "git commit -m x" "$CDX" s7

# 4. Once per session PER REPO: the second commit in the same session+repo does not ask again; the same
#    session in a DIFFERENT repo still does; a different session still does; an unusable session id
#    (traversal shape) asks every time and writes no marker outside the dir.
check ask "git commit -m x" "$NOREV" s8
ls "$T/kit/.state/review-gate-asked/" | grep -q '^s8__' || fail "marker not written under the sandbox kit .state"
check allow "git commit -m y" "$NOREV" s8
CWD="$T/repoB"; check ask "git commit -m x" "$NOREV" s8; CWD="$T/repoA"
check ask "git commit -m x" "$NOREV" s9
check ask "git commit -m x" "$NOREV" "../../evil"
check ask "git commit -m x" "$NOREV" "../../evil"
[ ! -e "$T/kit/.state/review-gate-asked/../../evil" ] || fail "traversal session id escaped the marker dir"
[ ! -e "$T/evil" ] || fail "traversal session id escaped the marker dir (sandbox root)"

# 4b. A `cd` before the commit segment changes the EFFECTIVE repo the marker keys on - guard must not
#     trust the raw payload cwd alone (F-cwd-bypass 2026-08-16: this shape silently reused a marker
#     scoped to the WRONG repo before the fix, making a `cd otherrepo && git commit` look pre-cleared).
check ask "cd $T/repoB && git commit -m x" "$NOREV" s13
ls "$T/kit/.state/review-gate-asked/" | grep -q '^s13__.*repoB' || fail "marker was not keyed to the cd-resolved repo (repoB)"
check allow "cd $T/repoB && git commit -m y" "$NOREV" s13   # same session, same EFFECTIVE repo -> silenced
check ask "git commit -m z" "$NOREV" s13                    # same session, payload cwd repoA -> different repo, still asks

# 4c. `git -C <path> commit` used to bypass this guard OUTRIGHT (COMMIT_SEG never matched it at all) -
#     CMDPOS_COMMIT_FRAG follow-up, 2026-08-16. Same marker-keying proof as 4b, via -C instead of cd.
check ask "git -C $T/repoB commit -m x" "$NOREV" s14
ls "$T/kit/.state/review-gate-asked/" | grep -q '^s14__.*repoB' || fail "marker was not keyed to the -C-resolved repo (repoB)"
check allow "git -C $T/repoB commit -m y" "$NOREV" s14

# 4c2. Wrapper shapes (Tier 1 review T1.2, 2026-08-16): sudo / nohup / path / paren / brace / if-then
#      used to bypass this guard OUTRIGHT (the hand-copied `^[[:space:]]*` anchor saw no wrapper).
#      Payload-level pin, one shape per session id so the once-per-session marker cannot mask a result.
check ask "sudo git commit -m x" "$NOREV" s17
check ask "nohup git commit -m x" "$NOREV" s18
check ask "/usr/bin/git commit -m x" "$NOREV" s19
check ask "( git commit -m x )" "$NOREV" s20
check ask "{ git commit -m x; }" "$NOREV" s21
check ask "if true; then git commit -m x; fi" "$NOREV" s22
check allow "echo git commit is a thing" "$NOREV" s23   # over-broad-fix control: must NOT ask on echo

# 4d. `--git-dir=`/`--work-tree=` (gap-closure wave 4, 2026-08-16): the marker's REPO component would
#     be wrong (only -C is resolved into CWD), so this guard skips reading/writing the marker entirely
#     and asks EVERY time this shape appears - proven by running the SAME session+shape TWICE: a
#     normal repo would silence the second ask (see 4b/4c above), this must NOT.
check ask "git --git-dir=$T/repoB/.git commit -m x" "$NOREV" s15
check ask "git --git-dir=$T/repoB/.git commit -m y" "$NOREV" s15   # NOT silenced, unlike 4b/4c's second call
ls "$T/kit/.state/review-gate-asked/" | grep -q '^s15__' && fail "a marker was written for the unresolved-repo-flag shape (should never write one)"
grep -aq "unresolved repo-selecting flag.*marker read/write skipped" "$T/kit/.state/guards.log" || fail "the marker-skip breadcrumb was not logged"
# control: the underlying criterion (was a reviewer spawned) still works normally under this shape -
# a real reviewer spawn still silences it, same as any other commit.
check allow "git --git-dir=$T/repoB/.git commit -m x" "$REV" s16

# 4e. T1.10 (2026-08-16): an UNRESOLVABLE `cd`/`-C` target (`mkdir X && cd X && git commit` - X does
#     not exist at PreToolUse time) is the same wrong-repo-marker class as 4d: no marker read/write,
#     asks every time, never keys the marker to the payload cwd (the pre-fix fallback). Same twice-in-
#     one-session proof; a marker keyed to repoA (the payload cwd) here is exactly the bug.
check ask "mkdir $T/fresh-$$ && cd $T/fresh-$$ && git commit -m x" "$NOREV" s24
check ask "mkdir $T/fresh-$$ && cd $T/fresh-$$ && git commit -m y" "$NOREV" s24   # NOT silenced
ls "$T/kit/.state/review-gate-asked/" | grep -q '^s24__' && fail "T1.10: a marker was written for an unresolvable-cd shape (should never write one)"
grep -aq "unresolvable cd/-C target.*marker read/write skipped" "$T/kit/.state/guards.log" || fail "T1.10 marker-skip breadcrumb was not logged"
check allow "mkdir $T/fresh-$$ && cd $T/fresh-$$ && git commit -m x" "$REV" s25   # criterion itself still works

# 5. Fail-open: no transcript path, unreadable transcript, missing jq input.
out="$(jq -n '{session_id: "s10", tool_input: {command: "git commit -m x"}}' | sh "$GUARD" 2>/dev/null || true)"
[ -z "$out" ] || fail "no transcript_path must fail open, got: $out"
check allow "git commit -m x" "$T/does-not-exist.jsonl" s11
out="$(printf 'not json' | sh "$GUARD" 2>/dev/null || true)"
[ -z "$out" ] || fail "garbage stdin must fail open, got: $out"

# 5b. Unattended mode (2026-08-23): the SC-5.2 gate is ENFORCED either way - what changes is that a
#     question nobody is present to answer comes back as an actionable deny instead of a halt. The
#     flag is per session, so another session's flag must not convert this one.
STATE_DIR="$T/kit/.state"; mkdir -p "$STATE_DIR"
: > "$STATE_DIR/unattended.s-unatt"
[ "$(run 'git commit -m x' "$NOREV" s-unatt)" = deny ] || fail "unattended session did not convert the ask to a deny"
printf 'ok   [deny] unattended session converts the ask\n'
[ "$(run 'git commit -m x' "$NOREV" s-attended)" = ask ] || fail "an unflagged session stopped asking"
printf 'ok   [ask]  an unflagged session is unaffected by a flag set for another session\n'
# the deny must NOT bank the once-per-session marker, or an identical retry would sail through with
# nobody having made the judgement the gate exists to collect
[ "$(run 'git commit -m x' "$NOREV" s-unatt)" = deny ] || fail "the converted deny banked its marker - a retry bypassed the gate"
printf 'ok   [deny] a converted deny repeats instead of banking the marker\n'
# the gate itself still passes when the evidence exists - unattended is not a bypass
[ "$(run 'git commit -m x' "$REV" s-unatt2)" = allow ] || fail "unattended broke the reviewer-seen path"
printf 'ok   [allow] unattended does not fire when a reviewer spawn exists\n'
# a traversal-shaped session id cannot select a flag file
: > "$STATE_DIR/unattended...."
[ "$(run 'git commit -m x' "$NOREV" '..')" = ask ] || fail "a dot-dot session id selected a flag file"
printf 'ok   [ask]  a traversal-shaped session id is treated as unflagged\n'
rm -f "$STATE_DIR/unattended.s-unatt" "$STATE_DIR/unattended...."

# 5c. Subagent caller (2026-08-27): the same "no human behind this ask" case as unattended, converted
#     the same way - deny, worded at the delegated agent, and (like unattended) never banks the marker,
#     which is what stops a worker's commit from silently burning the Lead's own later real ask.
[ "$(run 'git commit -m x' "$NOREV" s-sub "worker")" = deny ] || fail "a subagent caller did not convert the ask to a deny"
printf 'ok   [deny] a subagent caller (agent_type=worker) converts the ask\n'
ls "$T/kit/.state/review-gate-asked/" | grep -q '^s-sub__' && fail "a marker was written for a subagent-converted deny"
[ "$(run 'git commit -m x' "$NOREV" s-sub2)" = ask ] || fail "a plain (Lead-originated) call in a fresh session should still ask"
printf 'ok   [ask]  a Lead-originated call (no agent_type) is unaffected\n'
# the deny is worded at the worker, never the unattended-mode text - the two must not collide.
OUT="$(jq -n --arg x 'git commit -m x' --arg t "$NOREV" --arg s s-sub3 --arg c "$CWD" --arg a worker \
       '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}, agent_type: $a}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$OUT" | grep -aq 'DELEGATED AGENT' || fail "subagent deny reason missing the delegated-agent prefix"
printf '%s' "$OUT" | grep -aq 'cannot judge triviality here or spawn a reviewer' || fail "subagent deny reason missing the worker-specific remedy"
printf '%s' "$OUT" | grep -aq 'UNATTENDED MODE' && fail "subagent deny reason wrongly carries the unattended prefix"
printf 'ok   [deny] subagent deny reason is worded for the delegated agent, not the unattended-mode text\n'
# both true at once: subagent wording wins (guard_ask_prefix's own precedence, pinned end-to-end here too).
: > "$STATE_DIR/unattended.s-sub-both"
OUT="$(jq -n --arg x 'git commit -m x' --arg t "$NOREV" --arg s s-sub-both --arg c "$CWD" --arg a worker \
       '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}, agent_type: $a}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$OUT" | grep -aq 'DELEGATED AGENT' || fail "subagent+unattended: subagent prefix should still win"
printf '%s' "$OUT" | grep -aq 'UNATTENDED MODE' && fail "subagent+unattended: unattended prefix should not also appear"
rm -f "$STATE_DIR/unattended.s-sub-both"
printf 'ok   [deny] subagent wording wins even when the session is ALSO unattended\n'
# a real reviewer spawn still silences it, same as any other commit - a subagent caller is not a bypass.
# NOTE (opus reviewer, 2026-08-27, LOW): this proves the CODE PATH (an agent_type payload against a
# transcript that already carries a reviewer spawn), not a live property of what transcript_path a real
# subagent's payload actually carries - that was never separately probed. If a subagent's payload turns
# out to carry its own sidechain transcript rather than the parent's, this fixture would not catch it;
# the deny is still the safe posture either way (the Lead's own answer still clears future worker
# commits via the shared marker).
[ "$(run 'git commit -m x' "$REV" s-sub4 "worker")" = allow ] || fail "subagent caller broke the reviewer-seen path (fixture-level, not a live transcript_path probe)"
printf 'ok   [allow] a subagent caller is unaffected once a reviewer spawn exists in the transcript it reads\n'

# 6. Never deny (ATTENDED, Lead-originated sessions - see 5b/5c for the unattended/subagent conversions).
for c in "git commit -m x" "git add . && git commit -m x"; do
  [ "$(run "$c" "$NOREV" s12)" != deny ] || fail "guard emitted deny for: $c"
done

# 7. Log line written under the sandbox, not the real kit.
grep -aq 'review-gate-guard ask:' "$T/kit/.state/guards.log" || fail "ask was not logged to the sandbox guards.log"

echo "OK review-gate-guard: commit detection, independent-pass evidence, once-per-session marker, fail-open, never-deny-when-attended, and the unattended AND subagent ask->deny conversions (with correct precedence and never banking the marker) all hold"

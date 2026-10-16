#!/usr/bin/env sh
# kit-scope: shared
# Self-check for review-gate-guard.sh. Runnable: `sh review-gate-guard.selfcheck.sh`. Sandboxed kit copy
# (script + guard-cmdpos.sh, so BASE and the .state marker dir resolve inside the sandbox) + synthetic
# transcripts. Exits non-zero on first failure.
set -u
unset AGENT_TIERS_STATE_DAYS AGENT_TIERS_LEDGER_DAYS
SRC_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"   # macOS TMPDIR ends in "/" - a "//" in T breaks every pwd comparison (CI, 2026-08-16)
T="${TMPBASE}/at-reviewgate-selfcheck.$$"
rm -rf "$T"; mkdir -p "$T/kit/scripts" || fail "cannot build sandbox"
cp "$SRC_DIR/review-gate-guard.sh" "$T/kit/scripts/" || fail "cannot copy guard"
cp "$SRC_DIR/guard-cmdpos.sh" "$T/kit/scripts/" || fail "cannot copy guard-cmdpos.sh"
cp "$SRC_DIR/review-gate-mode.sh" "$T/kit/scripts/" || fail "cannot copy review-gate-mode.sh"
GUARD="$T/kit/scripts/review-gate-guard.sh"
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
         '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}} + (if $a != "" then {agent_type: $a} else {} end) + (if $a == "" or $a == "main" or $a == "MAIN" then {} else {agent_id: "a0test"} end)' \
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

# 4d. `--git-dir=`/`--work-tree=` (2026-09-14, guard-ask-deny rule, CORRECTED same day - adversarial
#     review, LOW): a same-day draft denied this shape outright as a "mechanical fix". It is not one - a
#     bare-repo dotfiles checkout genuinely cannot be re-spelled with `-C`, so a human still has to
#     decide (re-spell it, or "yes this really is detached, use a real terminal"). Kept as `ask`,
#     carrying the shared unresolved-repo reason, marker read/write skipped (asks every time this shape
#     appears - proven by running the SAME session+shape TWICE, unlike 4b/4c's second-call silence).
check ask "git --git-dir=$T/repoB/.git commit -m x" "$NOREV" s15
check ask "git --git-dir=$T/repoB/.git commit -m y" "$NOREV" s15   # NOT silenced, unlike 4b/4c's second call
ls "$T/kit/.state/review-gate-asked/" | grep -q '^s15__' && fail "a marker was written for the unresolved-repo-flag shape (should never write one)"
grep -aq 'review-gate-guard ask: unresolved repo-selecting flag' "$T/kit/.state/guards.log" || fail "the ask breadcrumb was not logged"
RAWOUT="$(jq -n --arg x "git --git-dir=$T/repoB/.git commit -m x" --arg t "$NOREV" --arg s s15-reason --arg c "$CWD" \
          '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$RAWOUT" | grep -aq 'review-gate-guard: commit BLOCKED' || fail "git-dir ask reason must carry the shared unresolved-repo text, got: $RAWOUT"
# control: the underlying criterion (was a reviewer spawned) still works normally under this shape -
# a real reviewer spawn still silences it, same as any other commit (restored to pre-2026-09-14
# behaviour by the same-day correction).
check allow "git --git-dir=$T/repoB/.git commit -m x" "$REV" s16
# subagent/unattended still convert this ask the same way as the normal no-reviewer ask.
check deny "git --git-dir=$T/repoB/.git commit -m x" "$NOREV" "s15-sub" "worker"
mkdir -p "$T/kit/.state"; : > "$T/kit/.state/unattended.s15-unatt"
check deny "git --git-dir=$T/repoB/.git commit -m x" "$NOREV" "s15-unatt"
rm -f "$T/kit/.state/unattended.s15-unatt"

# 4e. T1.10 (2026-08-16): an UNRESOLVABLE `cd`/`-C` target (`mkdir X && cd X && git commit` - X does
#     not exist at PreToolUse time) is DIFFERENT from 4d's --git-dir/--work-tree case (2026-09-14
#     correction): this one always has a mechanical fix (spell the path literally, or split the mkdir
#     into a separate tool call), so it keeps the 2026-09-14 deny, unlike 4d's restored ask. Same
#     twice-in-one-session proof; a marker keyed to repoA (the payload cwd) here is exactly the bug
#     this class exists to avoid, so no marker at all is ever written.
check deny "mkdir $T/fresh-$$ && cd $T/fresh-$$ && git commit -m x" "$NOREV" s24
check deny "mkdir $T/fresh-$$ && cd $T/fresh-$$ && git commit -m y" "$NOREV" s24   # repeats, not silenced
ls "$T/kit/.state/review-gate-asked/" | grep -q '^s24__' && fail "T1.10: a marker was written for an unresolvable-cd shape (should never write one)"
grep -aq 'review-gate-guard deny: unresolvable cd/-C target' "$T/kit/.state/guards.log" || fail "T1.10 deny breadcrumb was not logged"
RAWOUT="$(jq -n --arg x "mkdir $T/fresh-$$ && cd $T/fresh-$$ && git commit -m z" --arg t "$NOREV" --arg s s24-reason --arg c "$CWD" \
          '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$RAWOUT" | grep -aq 'review-gate-guard: cd/-C target' || fail "cd/-C deny reason must name the target, got: $RAWOUT"
check deny "mkdir $T/fresh-$$ && cd $T/fresh-$$ && git commit -m x" "$REV" s25   # deny fires regardless of review evidence

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
       '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}, agent_type: $a, agent_id: "a0test"}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$OUT" | grep -aq 'DELEGATED AGENT' || fail "subagent deny reason missing the delegated-agent prefix"
printf '%s' "$OUT" | grep -aq 'cannot judge triviality here or spawn a reviewer' || fail "subagent deny reason missing the worker-specific remedy"
printf '%s' "$OUT" | grep -aq 'UNATTENDED MODE' && fail "subagent deny reason wrongly carries the unattended prefix"
printf 'ok   [deny] subagent deny reason is worded for the delegated agent, not the unattended-mode text\n'
# both true at once: subagent wording wins (guard_ask_prefix's own precedence, pinned end-to-end here too).
: > "$STATE_DIR/unattended.s-sub-both"
OUT="$(jq -n --arg x 'git commit -m x' --arg t "$NOREV" --arg s s-sub-both --arg c "$CWD" --arg a worker \
       '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}, agent_type: $a, agent_id: "a0test"}' | sh "$GUARD" 2>/dev/null || true)"
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

# 6. The no-reviewer-spawned ASK never becomes a deny for an ATTENDED, Lead-originated session on an
#    ordinary (resolvable-target) commit - see 5b/5c for the unattended/subagent conversions, and 4e
#    above for the one deny that DOES fire regardless of attendance (an unresolvable cd/-C target; 4d's
#    --git-dir/--work-tree case is an ask like this one, not a deny - 2026-09-14 correction).
for c in "git commit -m x" "git add . && git commit -m x"; do
  [ "$(run "$c" "$NOREV" s12)" != deny ] || fail "guard emitted deny for: $c"
done

# 7. Log line written under the sandbox, not the real kit.
grep -aq 'review-gate-guard ask:' "$T/kit/.state/guards.log" || fail "ask was not logged to the sandbox guards.log"

# --- ship-guards wave (2026-10-06, REPAIRED 2026-10-06 after independent review) --------------------
# The merge/cherry-pick arm and the linked-worktree carve-out are GONE from the design (dropped after
# review, see review-gate-guard.sh's own header) - no selfcheck coverage for either below.

# 8. The push/PR act detector shares the same evidence/marker machinery as commit.
check ask "git push" "$NOREV" s32
check ask "gh pr create" "$NOREV" s33
check ask "gh pr merge 1" "$NOREV" s34
check allow "git push" "$REV" s36

# 9. Both arms share the ONE once-per-session-per-repo marker: a commit ask also silences a later
#    push in the same repo, and vice versa.
check ask "git commit -m x" "$NOREV" s37
check allow "git push" "$NOREV" s37
check ask "git push" "$NOREV" s38
check allow "git commit -m y" "$NOREV" s38

# 10. review_gate mode (guard_local_scalar, read from <main-top>/.claude/agent-tiers.local.md): `push`
#     makes a plain `git commit` pass unconditionally, for ANY caller including a subagent - but a
#     PUBLISH act (push/PR) still goes through the normal ask/deny logic in either mode, and its
#     reason names the mode so the quiet local commits aren't misread.
mkdir -p "$T/repoA/.claude"
printf 'review_gate: push\n' > "$T/repoA/.claude/agent-tiers.local.md"
check allow "git commit -m x" "$NOREV" s40
check allow "git commit -m x" "$NOREV" "s40-sub" "worker"
check ask "git push" "$NOREV" s41
check deny "git push" "$NOREV" "s41-sub" "worker"
OUT="$(jq -n --arg x 'git push' --arg t "$NOREV" --arg s s41-reason --arg c "$CWD" \
       '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$OUT" | grep -aq 'commit-first' || fail "push-mode ship reason should say the repo is commit-first, got: $OUT"
printf 'ok   review_gate: push mode passes a plain commit (any caller) and still gates a publish act (reason names the mode)\n'

# 11. Fix 3 (repair wave): the push-mode commit-pass must NOT apply when the commit carries an
#     unresolved --git-dir/--work-tree flag - that shape might target an entirely different repo, so
#     it still asks (and converts to deny for a subagent) in push mode exactly like it does in commit
#     mode, never a silent pass. (review_gate: push is still set from test 10, above.)
check ask "git --git-dir=$T/repoB/.git commit -m x" "$NOREV" s42
check deny "git --git-dir=$T/repoB/.git commit -m x" "$NOREV" "s42-sub" "worker"
printf 'ok   review_gate: push mode does NOT pass a commit carrying an unresolved --git-dir/--work-tree flag\n'
rm -f "$T/repoA/.claude/agent-tiers.local.md"

# 12. Fix 1 (repair wave, HIGH): a compound command carrying BOTH a commit and a push is a SHIP act,
#     full stop - the push-mode commit-pass must never let it ride through quietly behind the earlier
#     commit segment. Same command, three callers/modes, all correctly still gated.
printf 'review_gate: push\n' > "$T/repoA/.claude/agent-tiers.local.md"
check ask "git commit -am x && git push" "$NOREV" s43
check deny "git commit -am x && git push" "$NOREV" "s43-sub" "worker"
rm -f "$T/repoA/.claude/agent-tiers.local.md"
check ask "git commit -am x && git push" "$NOREV" s44
printf 'ok   fix 1: a compound commit+push command is classified ship (never passed as a quiet local commit) in push mode (Lead ask, subagent deny) and in commit mode (Lead ask)\n'

# 12b. The same escape, via a heredoc body line that merely STARTS WITH `git commit` inside a real
#      `gh pr create --body` - the real act is still a publish (a gh pr create segment really is
#      present), so in push mode this must ask, never pass as if it were a quiet local commit.
printf 'review_gate: push\n' > "$T/repoA/.claude/agent-tiers.local.md"
HEREDOC_CMD='gh pr create --title x --body "$(cat <<'"'"'EOF'"'"'
git commit -m fake
EOF
)"'
check ask "$HEREDOC_CMD" "$NOREV" s45
rm -f "$T/repoA/.claude/agent-tiers.local.md"
printf 'ok   fix 1: a gh pr create whose heredoc BODY merely starts with "git commit" still asks in push mode, never passes\n'

# 12c. The REVERSE decoy (2026-10-06): a commit-message heredoc BODY line that merely STARTS WITH
#      `git push` inside a REAL `git commit`. Before the heredoc-strip fix, plain grep's `^` anchor
#      (guard-cmdpos.sh's own header) matched that body line as a real ship act at command position,
#      so the whole command classified as ship and a push-mode local commit was denied as a push. The
#      real act is a plain commit - push mode must pass it unconditionally (Lead and subagent alike),
#      exactly like any other local commit.
HEREDOC_DECOY='git commit -m "$(cat <<'"'"'EOF'"'"'
git push origin is now gated
EOF
)"'
printf 'review_gate: push\n' > "$T/repoA/.claude/agent-tiers.local.md"
check allow "$HEREDOC_DECOY" "$NOREV" s48
check allow "$HEREDOC_DECOY" "$NOREV" "s48-sub" "worker"
rm -f "$T/repoA/.claude/agent-tiers.local.md"
printf 'ok   fix: a commit-message heredoc body merely starting with "git push" is classified commit, not ship - push mode passes it (Lead and subagent alike)\n'

# 12d. Same decoy in commit mode (the default): a plain commit always asks regardless of mode, but the
#      reason text must name it a commit, never a push - proves the heredoc body text never leaked
#      into ACT/ACT_WORD classification.
check ask "$HEREDOC_DECOY" "$NOREV" s49
OUT="$(jq -n --arg x "$HEREDOC_DECOY" --arg t "$NOREV" --arg s s49-reason --arg c "$CWD" \
       '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$OUT" | grep -aq 'about to commit in' || fail "heredoc decoy in commit mode should read as a commit, got: $OUT"
printf '%s' "$OUT" | grep -aqE 'about to push in' && fail "heredoc decoy in commit mode misread as a push, got: $OUT"
printf 'ok   fix: the same decoy in commit mode asks as a commit, and the reason names commit, not push\n'

# 13. Fix 4 (repair wave): a gh pr segment is resolved with verb=pr, bounding the -C fold to `gh pr` -
#     a PR title/body containing a literal "-C <word>" substring must NOT be read as an unresolvable
#     cd target (it was, before the fix: denied instead of asked).
check ask 'gh pr create --title "Fold -C targets in guards"' "$NOREV" s46
printf 'ok   fix 4: a gh pr segment whose title contains a literal -C substring still asks, never denies as an unresolvable cd target\n'

# 13b. ACT_WORD for a gh pr segment is derived STRUCTURALLY (which GUARD_SHIP_FRAG alternative
#      matched), never a substring test on the segment text - a title containing the word "push"
#      must still read as "pull request" in the reason, not "push".
OUT="$(jq -n --arg x 'gh pr create --title "push docs"' --arg t "$NOREV" --arg s s47 --arg c "$CWD" \
       '{session_id: $s, cwd: $c, transcript_path: $t, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
printf '%s' "$OUT" | grep -aq 'pull request' || fail "ACT_WORD for a gh pr segment should read 'pull request' even when the title contains the word push, got: $OUT"
printf '%s' "$OUT" | grep -aqE 'about to push in' && fail "ACT_WORD misclassified a gh pr segment as a push because its title text contains the word, got: $OUT"
printf 'ok   fix 4: ACT_WORD for a gh pr segment reads "pull request" even when its title text contains the word push\n'

# 14. A typo'd or duplicated review_gate line resolves to the strict default (`commit`), same as
#     hygiene_scope's own precedent - never a silent widen to `push`.
printf 'review_gate: pushpush\n' > "$T/repoA/.claude/agent-tiers.local.md"
check ask "git commit -m x" "$NOREV" s80
rm -f "$T/repoA/.claude/agent-tiers.local.md"
printf 'review_gate: push\nreview_gate: commit\n' > "$T/repoA/.claude/agent-tiers.local.md"
check ask "git commit -m x" "$NOREV" s81
rm -f "$T/repoA/.claude/agent-tiers.local.md"
printf 'ok   review_gate: a typo or a duplicated line falls back to commit (the stricter default), never push\n'

# 15. review-gate-mode.sh (fix 9, repair wave): prints the effective review_gate value and its source
#     for the SAME directory the guard itself would resolve - built on guard_main_top/guard_local_scalar
#     directly, so it can never drift from what the guard actually enforces.
#     Run against the SANDBOXED copy ($T/kit/scripts/), not $SRC_DIR's real one - the real one resolves
#     its own BASE as $SRC_DIR/.., so it would read the REAL kit's own kit-config.md's review_gate line
#     (if the operator has one set) and this case's "built-in default" assertion would depend on
#     machine config, same off-instrument-config class hygiene-commit-guard.selfcheck.sh's own
#     hygiene_scope isolation (T3) already guards against.
MODE_SH="$T/kit/scripts/review-gate-mode.sh"
[ -f "$MODE_SH" ] || fail "scripts/review-gate-mode.sh does not exist"
MOUT="$(sh "$MODE_SH" "$T/repoA" 2>&1)"
printf '%s' "$MOUT" | grep -aq '^commit' || fail "review-gate-mode.sh should print 'commit' with no local config, got: $MOUT"
printf 'review_gate: push\n' > "$T/repoA/.claude/agent-tiers.local.md"
MOUT="$(sh "$MODE_SH" "$T/repoA" 2>&1)"
printf '%s' "$MOUT" | grep -aq '^push' || fail "review-gate-mode.sh should print 'push' once configured, got: $MOUT"
printf '%s' "$MOUT" | grep -aq "agent-tiers.local.md" || fail "review-gate-mode.sh should name the source file, got: $MOUT"
rm -f "$T/repoA/.claude/agent-tiers.local.md"
printf 'ok   review-gate-mode.sh: prints the effective value and names its source, built-in default and a configured repo both correct\n'

# kit-gate stand-down: marker <kit>/.state/off/review-gate-guard -> silent exit 0 + a kit-gate log line.

sd_in() { jq -n --arg x "git commit -m x" --arg t "$NOREV" --arg c "$CWD" '{session_id: "s-sd", cwd: $c, transcript_path: $t, tool_input: {command: $x}}'; }
sd_out="$(sd_in | sh "$GUARD" 2>/dev/null)"
case "$sd_out" in *'"permissionDecision"'*) ;; *) fail "standdown control: expected a decision without the marker, got: $sd_out" ;; esac
mkdir -p "$T/kit/.state/off"; : > "$T/kit/.state/off/review-gate-guard"; rm -f "$T/kit/.state/guards.log"
sd_out="$(sd_in | sh "$GUARD" 2>/dev/null)"; sd_rc=$?
[ -z "$sd_out" ] && [ "$sd_rc" = 0 ] || fail "standdown: expected empty stdout + exit 0, got rc=$sd_rc out=$sd_out"
grep -aq 'kit-gate standdown review-gate-guard:' "$T/kit/.state/guards.log" || fail "standdown: no kit-gate log line"
rm -f "$T/kit/.state/off/review-gate-guard"
printf 'ok   [standdown] marker present -> silent exit 0 + log line\n'

echo "OK review-gate-guard: commit detection, independent-pass evidence, once-per-session marker, fail-open, deny-on-unresolvable-cd/-C-target (regardless of caller/attendance), ask-on-unresolved-git-dir/work-tree-target (2026-09-14 correction, converts like the normal review-pass ask), the unattended AND subagent ask->deny conversions (with correct precedence and never banking the marker), push/PR detection sharing the same marker as commit, review_gate: push passing a plain commit for any caller while still gating a publish act and never passing one carrying an unresolved --git-dir/--work-tree flag, a compound commit+push command always classified ship (never smuggled through as a quiet local commit, including via a heredoc-body decoy), a gh pr segment resolved with verb=pr (a literal -C in its title never misreads as an unresolvable cd target) and its ACT_WORD derived structurally (never misreads 'pull request' as 'push'), a typo/duplicate review_gate line falling back to commit, and review-gate-mode.sh printing the same value+source the guard itself would resolve, all hold"

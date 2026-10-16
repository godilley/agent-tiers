#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: soft `ask` when a commit or a publish act (`git push` /
# `gh pr create` / `gh pr merge`) is about to run in a session that has NOT yet spawned an independent
# reviewer - the arrival event for SC-5.2 ("any non-trivial diff takes an independent fresh-eyes pass
# before it ships"). Sibling of vcs-commit-guard.sh and hygiene-commit-guard.sh for the commit half:
# same commit-segment regex, same fail-open posture, same log.
#
# Why this exists: measured across two doctrine-usage reviews, SC-5.2 was violated in roughly one of every
# four commit-bearing sessions, and every one of those sessions had the rule loaded - the 2.1% lesson
# again: a rule fires only when something checks it at an ACT, and the act here is the commit (and,
# since the ship-guards wave 2026-10-06, a push/PR too).
#
# --- ship-guards wave (2026-10-06, REPAIRED 2026-10-06 after independent review) ----------------------
# Per-repo `review_gate` config (same local-config seam as hygiene_scope, guard_local_scalar in
# guard-cmdpos.sh - <main-top>/.claude/agent-tiers.local.md, then the kit's kit-config.md, else the
# strict default) picks one of:
#   `commit` (default): a `git commit` asks, a PUBLISH act (push/PR) also asks - this repo wants
#      review before either lands.
#   `push`: a `git commit` PASSES unconditionally for ANY caller (no ask, no marker touch) - this repo
#      is commit-first, review is deferred to the point it actually ships. A PUBLISH act still asks
#      (same as `commit` mode) and its reason says so explicitly, so the model doesn't read the quiet
#      local commits as "review isn't needed here". The commit-mode pass does NOT apply when the
#      commit carries an unresolved --git-dir/--work-tree flag (fix 3, repair wave) - that shape is a
#      "might be the wrong repo entirely" case, not a plain local commit, so it still goes through the
#      normal ask/deny logic in either mode.
# <main-top> (guard_main_top) is the MAIN worktree's top-level dir, not the effective repo dir's own
# toplevel - a linked worktree has no copy of the git-ignored agent-tiers.local.md, so reading at the
# worktree's own top would silently fall back to `commit` every time. Resolved from the EFFECTIVE repo
# dir (CWD after cd/-C resolution, same dir the marker's repo component already uses), not the raw
# payload cwd. Mode resolution is deferred until AFTER the once-per-session-per-repo marker check (see
# below) - a session that already got its one ask for this repo never pays for guard_main_top's git
# calls or guard_local_scalar's file reads again.
#
# REMOVED after independent review, same day: the linked-worktree carve-out (a subagent committing
# inside a `git worktree add` checkout is NOT exempt from this guard - the table never had a row for
# it) and the merge/cherry-pick arm (git merge and git cherry-pick are NOT gated by this guard at all
# any more - see the disclosed-ceilings list below). guard_linked_worktree and GUARD_MERGE_FRAG/
# guard_merge_seg were deleted from guard-cmdpos.sh entirely; guard_main_top stayed (mode is still
# read from the main worktree top even when the effective cwd is a linked worktree the Lead is working
# in directly).
#
# Classification order (fix 1, repair wave): a PUBLISH act (push/PR) is detected FIRST, over the WHOLE
# command - `git commit -am x && git push` is a SHIP act, full stop, even though a commit segment
# exists earlier in the same command. A compound command is never allowed to "borrow" the commit arm's
# push-mode pass to sneak a push through quietly: only once NO ship segment exists anywhere in the
# command does this guard fall back to checking for a plain commit. This also means the push-mode
# commit-pass check below tests `[ "$ACT" = commit ]`, not merely "not ship" - there is no third act
# left to confuse it with now that merge is gone.
#
# Every arm (commit/push/PR) shares the ONE once-per-session-per-repo marker - an answered commit ask
# also silences a later push in the same repo, and vice versa, since the underlying criterion (was a
# reviewer/advisor/codex-read spawned THIS session) is the same question regardless of which act asked
# it.
#
# Disclosed ceilings, not chased further here: `git merge`, `git cherry-pick`, `git rebase`, `git am`,
# `git pull`, `git revert`, `git subtree push` (a real publish act this guard does NOT recognise as
# one), ANY env-assignment prefix (not only `GIT_DIR=`/`GIT_WORK_TREE=` - `FOO=bar git commit` is
# already a disclosed CMDPOS_PREFIX blind spot, see guard-cmdpos.sh's own header), a git ALIAS standing
# in for any of these (`git ci` for `git commit` is invisible - this operates on literal command text,
# same ceiling CMDPOS_PREFIX already discloses for a custom function/alias), and a SCRIPT WRAPPER that
# itself commits/merges/pushes internally (e.g. a repo's own `worktree.sh down --merge`, which merges
# and pushes from inside the script) - this guard sees the wrapper invocation, not what it runs. A
# compound command that ships from a DIFFERENT repo than it commits to (`git -C B commit -m x &&
# git push`, run from repo A) is keyed to its SHIP segment's repo only (ship-first classification,
# above) - A's marker and mode are consulted, never B's; not chased further here. A single-line act
# word that only appears quoted or backticked in a commit MESSAGE (`git commit -m 'see \`git push\`
# docs'`) is the CMDPOS_PREFIX heuristic ceiling (guard-cmdpos.sh's own header: this is a regex over
# command TEXT, not a real shell parser) - a false match there is pre-existing and not fixed by the
# heredoc-stripping fix above, which only addresses the per-LINE `^` anchor ceiling on a heredoc body.
#
# What counts as "an independent pass" (rubric SC-5.2's own compliance expression, mirrored here): an
# Agent/Task tool_use in THIS session's transcript whose input.subagent_type is reviewer | advisor |
# codex-read. STRUCTURED check (grep pre-filter, then jq over the candidate lines), not a text grep: the
# CLI writes an agent-listing attachment near the top of every transcript that quotes agent descriptions
# (one of them contains "/codex:review"), and any tool_result that READS a file mentioning the field would
# also match a bare grep - the first draft of this guard could never fire for exactly that reason (opus
# reviewer, 2026-08-16). Only a real Agent/Task tool_use counts. ponytail: a spawn that was denied or
# errored still counts (its tool_use is in the transcript); the rubric counts only delegates that ran, so
# guard and rubric can disagree on that rare edge - upgrade path is joining the tool_result. A
# `/codex:review` plugin run is NOT detected (it is a user slash command, not a spawn); say so in the
# reason instead. No transcript path -> fail-open.
#
# Commit-segment DETECTION is now STRUCTURAL, not enumerated: any option-shaped token between
# `git` and `commit` (`-C <path>`, `-c <key>=<val>`, `--git-dir=`, `--work-tree=`, `--no-pager`,
# anything) is recognised, so the guard fires - CMDPOS_COMMIT_FRAG in guard-cmdpos.sh, 2026-08-16
# follow-up. Before this, any global option between `git` and `commit` bypassed every commit-time
# guard OUTRIGHT (the bare `git commit` match never fired at all). `--git-dir=`/`--work-tree=`
# specifically mean the marker's REPO component may be wrong (only `-C` is folded into CWD) - this
# guard's own criterion (was a reviewer/advisor/codex-read spawned this session) is repo-independent,
# so the fix is to skip reading/writing the once-per-session-per-repo marker and ask unconditionally,
# not to deny (guard_unresolved_repo_flag(), see below). CORRECTED 2026-09-14, same day (adversarial
# review, LOW): a same-day draft of the guard-ask-deny rule denied this case outright, reasoning it as
# a mechanical "re-spell the target" fix - but a `--git-dir=`/`--work-tree=` pair can be a genuinely
# DETACHED checkout (a bare-repo dotfiles setup) with no `-C` equivalent at all, which
# GUARD_UNRESOLVED_REPO_REASON's own text already says needs a real terminal outside this agent - that
# is a human call, not a form problem, so `ask` (with subagent/unattended conversion) is correct here.
# An unresolvable `cd`/`-C` target (T1.10, below) IS a pure form problem (re-spell it, or split the
# mkdir into a separate tool call) and keeps the unconditional deny.
#
# `ask`, deliberately: SC-5.2 says NON-TRIVIAL, and a hook cannot judge triviality - the human can, in
# one click. To keep this from becoming wallpaper it asks ONCE per session PER REPO: after the first ask
# (whatever the answer) a marker under .state/review-gate-asked/<session-id>__<repo-slug> silences it for
# that session+repo; a later reviewer spawn silences it anyway. Per repo, because a session often commits
# to more than one repo and the trivial docs commit in repo A must not spend the one ask that the risky
# commit in repo B needed. Markers older than default 7 days (AGENT_TIERS_STATE_DAYS) are GC'd
# opportunistically, same as session-prefs. `permissionDecisionReason` on `ask` is shown to the USER, so it is a visible checkpoint.
# ponytail: no diff-size floor - the once-per-session marker is the anti-wallpaper mechanism; the upgrade
# path is a staged+unstaged line count if the ask still lands on trivial commits too often.
#
# Fail-open on any tooling gap (no jq, no transcript, unreadable state dir). The no-reviewer-spawned
# criterion (including the --git-dir/--work-tree shape, which shares this same ask) never denies on an
# ATTENDED, Lead-originated call - the two conversions (unattended session, subagent caller -
# guard_ask_decision) are both a real ask with nobody able to answer it, never an infrastructure gap.
# The unresolvable-cd/-C-target case is the one deny that fires regardless of caller, since it names a
# mechanical fix (re-spell the path, or split the mkdir into a separate call), not a human decision.
# Self-check: review-gate-guard.selfcheck.sh.
set -u
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s review-gate-guard %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

# Timeout tracing, scoped to the expensive window only. A guard killed at its hook budget cannot
# write its own breadcrumb, so the window brackets itself: `start` on entry, `end done=1` on exit.
# A kill inside the window leaves `start` with either `done=0` (SIGTERM: the TERM trap below makes
# dash run the EXIT trap too, which it skips on an untrapped TERM) or no `end` at all (SIGKILL runs
# no trap). Runs that never enter the window -
# the large majority, every Bash call that never reaches the commit-segment/transcript scan below -
# log nothing, which is what keeps this off every Bash call.
GUARD_TRACE_OPEN=0
trap 'if [ "$GUARD_TRACE_OPEN" = 1 ]; then note "end [pid=$$] done=0"; fi' EXIT
trap 'exit 143' TERM

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ]; then
  . "$SELFDIR/guard-cmdpos.sh"
else
  note "fail-open: guard-cmdpos.sh missing - cannot split segments"; exit 0
fi
# A stale guard-cmdpos.sh (partial bundle update, mid-merge checkout) without CMDPOS_COMMIT_FRAG
# would hit `set -u`'s unbound-variable error on first use below instead of a clean, breadcrumbed
# fail-open - opus reviewer, 2026-08-16. Caught here, once, at the same place every other sourcing
# failure is caught.
[ -n "${CMDPOS_COMMIT_FRAG:-}" ] && [ -n "${GUARD_SHIP_FRAG:-}" ] && [ -n "${GUARD_PUSH_FRAG:-}" ] && command -v guard_unresolved_repo_flag >/dev/null 2>&1 && command -v guard_cwd_unresolved >/dev/null 2>&1 && command -v guard_ask_decision >/dev/null 2>&1 && command -v guard_ask_prefix >/dev/null 2>&1 && command -v guard_caller_agent >/dev/null 2>&1 && command -v guard_commit_seg >/dev/null 2>&1 && command -v guard_ship_seg >/dev/null 2>&1 && command -v guard_at_command_position >/dev/null 2>&1 && command -v guard_verb_optspan >/dev/null 2>&1 && command -v guard_local_scalar >/dev/null 2>&1 && command -v guard_main_top >/dev/null 2>&1 || { note "fail-open: guard-cmdpos.sh sourced but a ship-guards function/constant is undefined (stale library?)"; exit 0; }
command -v guard_strip_heredocs >/dev/null 2>&1 || { note "fail-open: guard-cmdpos.sh sourced but guard_strip_heredocs undefined (stale library?)"; exit 0; }
# Heredoc bodies are STRIPPED (not a stand-down, same trade worktree-guard.sh/long-run-guard.sh/
# git-add-stash-guard.sh already made) before classification: plain grep's `^` anchors on the START OF
# EVERY LINE (guard-cmdpos.sh's own header), so a commit-message heredoc BODY line that merely starts
# with `git push`/`gh pr create` (the default harness commit shape is `git commit -m "$(cat <<'EOF'
# ...`) was misread as a real ship act at command position, denying a plain local commit as a push -
# fixed here (2026-10-06). The heredoc OPENER line survives the strip, so a `gh pr create --body
# "$(cat <<'EOF'` segment is still correctly classified ship even though its body happens to start
# with `git commit` (the real act IS a publish, that case must still ask).
SEGMENTS="$(guard_split_segments "$(guard_strip_heredocs "$CMD")")"
# Combined act-exists pre-check (fix 6, repair wave): ONE guard_segs_at_cmdpos call (one grep pass
# over SEGMENTS, same cost class guard_commit_seg alone already was) tests commit-OR-ship before any
# per-act classification runs below - a non-git/non-gh Bash call (the overwhelming majority of every
# Bash call this hook sees) costs exactly this one pass and exits, no more than it cost before this
# wave ever touched this file.
command -v guard_segs_at_cmdpos >/dev/null 2>&1 || { note "fail-open: guard-cmdpos.sh sourced but guard_segs_at_cmdpos undefined (stale library?)"; exit 0; }
[ -n "$(guard_segs_at_cmdpos "$SEGMENTS" "(${CMDPOS_COMMIT_FRAG}|${GUARD_SHIP_FRAG})")" ] || exit 0

# Classify the act (ship-guards wave, 2026-10-06; reordered fix 1, repair wave same day): a PUBLISH
# act (push/PR) is checked FIRST, over the WHOLE command - a compound command carrying BOTH a commit
# and a push (`git commit -am x && git push`) is a SHIP act, period, so the push-mode commit-pass
# below can never let a push ride through quietly behind an earlier commit segment. Only when no ship
# segment exists anywhere does this fall back to the plain commit detector. VERB feeds
# guard_resolve_cwd's own `-C`-after-the-verb bound (same contract guard_commit_seg's callers already
# use with verb=commit); for a ship act it is derived STRUCTURALLY (guard_at_command_position against
# GUARD_PUSH_FRAG), never a substring test on the segment text - a `gh pr create --title "let's push
# this"` segment is a real PR, not a push, even though the word is right there in the title.
ACT_SEG="$(guard_ship_seg "$SEGMENTS")"
if [ -n "$ACT_SEG" ]; then
  ACT=ship; STOP_ERE="$GUARD_SHIP_FRAG"
  if guard_at_command_position "$ACT_SEG" "$GUARD_PUSH_FRAG"; then
    VERB=push; ACT_WORD=push
  else
    # gh pr create/merge have no -C/--git-dir semantics at all (disclosed ceiling, guard-cmdpos.sh's
    # own GUARD_SHIP_FRAG header). verb=pr bounds guard_verb_optspan's own scan to `gh pr` (the first
    # two tokens) instead of letting it run to the segment's end hunting a literal "push"/"commit"
    # token that will never appear - without this bound, a PR --title/--body containing a literal
    # `-C <word>` substring was read as a real cd target (fix 4, repair wave: `gh pr create --title
    # "Fold -C targets in guards"` denied as an unresolvable cd before the fix).
    VERB=pr; ACT_WORD="pull request"
  fi
else
  ACT_SEG="$(guard_commit_seg "$SEGMENTS")"
  [ -n "$ACT_SEG" ] || exit 0   # defensive: the combined pre-check matched SOMETHING; unreachable in practice
  ACT=commit; STOP_ERE="$CMDPOS_COMMIT_FRAG"; VERB=commit; ACT_WORD=commit
fi

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || { note "fail-open: no readable transcript_path in payload"; exit 0; }

# Session id becomes a path component under .state - same charset guard as resume-inject.sh /
# codex-home-isolate.sh (F-12). An unusable id disables the once-per-session marker (asks every commit
# in that session), never a traversal.
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in *[!A-Za-z0-9._-]* | '.' | '..') SESSION_ID="" ;; esac
AGENT_TYPE="$(guard_caller_agent "$INPUT")"
# Repo component of the marker: the git toplevel of the EFFECTIVE cwd (the payload's .cwd, walked
# forward through any `cd` segment before the act - guard_resolve_cwd, F-cwd-bypass 2026-08-16;
# the raw payload field alone silently keyed the marker to the wrong repo whenever the command itself
# cd'd elsewhere), else the cwd itself; slugged with the same path->dashes rule the kit uses for
# project dirs.
PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
CWD=""; UNRESOLVED_CD=""
[ -n "$PAYLOAD_CWD" ] && CWD="$(guard_resolve_cwd "$SEGMENTS" "$STOP_ERE" "$PAYLOAD_CWD" "${VERB:-commit}")"
# An unresolvable `cd`/`-C` target (T1.10, 2026-08-16) means CWD/REPO would be the WRONG repo - same
# treatment as the flag case just below (skip the repo-keyed marker, ask unconditionally); never fall
# back to the payload cwd, which is exactly the wrong-repo marker key that case documents. Fires for
# every act (ship-guards wave) - it names a mechanical fix, not a review-policy question, so
# `review_gate: push` never changes this.
if [ -n "$CWD" ] && guard_cwd_unresolved "$CWD"; then UNRESOLVED_CD="${CWD#unresolved }"; CWD=""; fi
# `--git-dir=`/`--work-tree=` (guard_verb_optspan + the same pair guard_unresolved_repo_flag checks
# for commit) mean CWD/REPO below may be the WRONG repo - this guard's actual criterion (was a
# reviewer/advisor/codex-read spawned THIS SESSION) is repo-independent, only the once-per-session-
# PER-REPO marker is repo-keyed, so the fix is narrower than hygiene's deny or vcs's decline: skip
# reading/writing the marker and just ask every time this shape appears, rather than guess which repo
# "already asked" means (opus advisor, 2026-08-16; generalised to push, ship-guards 2026-10-06 -
# skipped entirely for the gh/PR shape, verb=pr, since --git-dir/--work-tree don't apply to gh).
UNRESOLVED_REPO_FLAG=0
if [ "$ACT" != ship ] || [ "$VERB" = push ]; then
  guard_verb_optspan "$ACT_SEG" "$VERB" | grep -aqxE -- '--(git-dir|work-tree)(=.*)?' && UNRESOLVED_REPO_FLAG=1
fi
# Act-neutral copy of guard-cmdpos.sh's shared GUARD_UNRESOLVED_REPO_REASON (fix 5, repair wave): that
# constant is a 4-consumer shared string hardcoded to say "commit BLOCKED" - the other three guards
# (hygiene-commit-guard.sh, kit-leak-guard.sh, vcs-commit-guard.sh) only ever gate a commit, so it is
# NOT generalised there (would drift their own wording for no reason). This guard's own acts now
# include push/PR too, so it gets its OWN copy with $ACT_WORD substituted instead.
RG_REASON_TMPL="${ACT_WORD} BLOCKED. This command selects the repository the ${ACT_WORD} targets through something this guard recognises but cannot resolve at check time: a --git-dir/--work-tree flag, or a \`cd\`/\`-C\` whose target does not exist yet or is not literal text (the guard runs BEFORE the command, so a \`cd\`/\`-C\` into a directory the SAME command creates has no target to look at yet, and \`cd \"\$VAR\"\` is opaque). It therefore does not know which repo the ${ACT_WORD} targets - every check it would run may belong to a different repo than the intended one. Denied rather than guessing. Make the target resolvable up front: for --git-dir/--work-tree, re-spell as \`git -C <repo> ...\`; for a \`cd\`/\`-C\` into a directory this same command creates, create it in a SEPARATE tool call first; for a variable or command-substitution target, spell the path literally. If this repo genuinely has a detached git-dir and work tree (a bare-repo dotfiles checkout is the usual case), -C cannot express that and this ${ACT_WORD} needs a real terminal outside this agent session - tell the operator, do not route around it."
# 2026-09-14 (guard-ask-deny rule), CORRECTED same day (adversarial review, LOW): the two unresolved-
# target classes are NOT the same case. An unresolvable `cd`/`-C` (T1.10) always has a mechanical fix -
# spell the path literally, or create the directory in a separate tool call first - so it denies,
# regardless of caller, before the evidence check even runs (a wrong-repo scan-and-allow is worse than
# a denied commit). A bare `--git-dir=`/`--work-tree=` pair has NO such fix when it is a genuinely
# detached checkout (a bare-repo dotfiles setup - RG_REASON_TMPL says so itself: "-C cannot express
# that and this needs a real terminal outside this agent session"). That is a human call, not a form
# problem, so it keeps the pre-existing `ask` (skip the once-per-session-per-repo marker only, since
# this criterion is repo-independent - never fall through to a deny), and the reviewer-evidence check
# below still applies normally: a real reviewer spawn silences it exactly like any other act.
if [ -n "$UNRESOLVED_CD" ]; then
  note "deny: unresolvable cd/-C target ($UNRESOLVED_CD) before the $ACT_WORD segment [sid=$SESSION_ID agent=${AGENT_TYPE:-lead}]"
  RGR="review-gate-guard: cd/-C target \`${UNRESOLVED_CD}\` cannot be resolved at check time. ${RG_REASON_TMPL}"
  jq -n --arg r "$RGR" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
fi
REPO=""
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  REPO="$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$REPO" ] || REPO="$CWD"
fi

# Once-per-session-per-repo marker check (MOVED UP, fix 6 repair wave): cheap (a file-existence test),
# so it runs BEFORE review_gate mode resolution below, which is not cheap (guard_main_top: two `cd` +
# two `git rev-parse` calls; guard_local_scalar: file reads). A session that already got its one ask
# for this repo (or had it denied/converted) never pays for mode resolution again on a repeat commit -
# same final decision either order, since the marker's own presence already decides it.
REPO_SLUG="$(printf '%s' "$REPO" | tr -c 'A-Za-z0-9' '-' | cut -c1-120)"
MARKER=""
[ -n "$SESSION_ID" ] && MARKER="${SESSION_ID}__${REPO_SLUG:-norepo}"
ASKED_DIR="${BASE:-${TMPDIR:-/tmp}}/.state/review-gate-asked"
# default 7 (AGENT_TIERS_STATE_DAYS), validated: non-digit, 0, or over 3650 silently falls back to 7.
days="${AGENT_TIERS_STATE_DAYS:-7}"; case "$days" in ''|*[!0-9]*) days=7 ;; esac
[ "$days" -gt 0 ] 2>/dev/null && [ "$days" -le 3650 ] 2>/dev/null || days=7
{ [ -d "$ASKED_DIR" ] && find "$ASKED_DIR" -type f -mtime "+$days" -delete; } 2>/dev/null || true
if [ "$UNRESOLVED_REPO_FLAG" != 1 ] && [ -n "$MARKER" ] && [ -f "$ASKED_DIR/$MARKER" ]; then
  exit 0
fi

# review_gate mode (ship-guards wave, 2026-10-06) - resolved only once the marker above did NOT
# already silence this call, and still before the expensive transcript evidence scan further down.
EFFECTIVE_DIR="$CWD"; [ -n "$EFFECTIVE_DIR" ] || EFFECTIVE_DIR="$PAYLOAD_CWD"
MAIN_TOP="$(guard_main_top "$EFFECTIVE_DIR" 2>/dev/null || true)"
RG_MODE_OUT="$(guard_local_scalar "$MAIN_TOP" review_gate "commit push" commit)"
RG_MODE="$(printf '%s\n' "$RG_MODE_OUT" | sed -n 1p)"
RG_MODE_REASON="$(printf '%s\n' "$RG_MODE_OUT" | sed -n 2p)"
[ -n "$RG_MODE_REASON" ] && note "$RG_MODE_REASON"
# Table (repaired, repair wave 2026-10-06): a plain `git commit` passes unconditionally in `push` mode,
# for ANY caller - but NOT when it carries an unresolved --git-dir/--work-tree flag (fix 3: that shape
# might be targeting an entirely different repo, so it still goes through the normal ask/deny logic
# below in either mode, same as it always has). A publish act (push/PR) NEVER takes this pass, in
# either mode - checked via `[ "$ACT" = commit ]`, not "not ship": there is no third act left to
# confuse this with now that the merge/cherry-pick arm and the linked-worktree carve-out are both gone.
if [ "$ACT" = commit ] && [ "$RG_MODE" = push ] && [ "$UNRESOLVED_REPO_FLAG" != 1 ]; then
  note "pass: commit in push mode (review_gate: push) - local commits are not gated here [sid=$SESSION_ID agent=${AGENT_TYPE:-lead}]"
  exit 0
fi

# The independent-pass evidence: a real Agent/Task tool_use with a review-class subagent_type. grep
# pre-filters candidate lines (transcripts run to many MB; jq over the whole file would eat the 5s
# budget), jq -R/fromjson? tolerates a corrupt line, and the structural select is what stops agent
# listings, pasted prompts and file reads from counting.
GUARD_TRACE_OPEN=1; note "start [pid=$$]"
if grep -a '"subagent_type"' "$TRANSCRIPT" 2>/dev/null \
   | jq -R -r 'fromjson? | .message.content? | if type=="array" then .[] else empty end
               | select(.type=="tool_use" and (.name=="Agent" or .name=="Task"))
               | .input.subagent_type? // empty' 2>/dev/null \
   | grep -qxE 'reviewer|advisor|codex-read'; then
  GUARD_TRACE_OPEN=0; note "end [pid=$$] done=1"   # closes off the transcript scan above
  exit 0
fi
GUARD_TRACE_OPEN=0; note "end [pid=$$] done=1"   # closes off the transcript scan above

DEC="$(guard_ask_decision "${SESSION_ID:-}" "$AGENT_TYPE")"
# The once-per-session-per-repo marker silences an ASK a human answered. A converted DENY has no human
# behind it (unattended, or now a subagent caller - see guard_ask_decision), so writing the marker
# would make the very next identical retry sail through - one nag, then free, with nobody having made
# the judgement the gate exists to collect (opus reviewer 2026-08-23, MEDIUM). This is also what stops
# a delegated worker's commit from silently burning the Lead's own later, real ask in the same repo
# (2026-08-27) - a subagent-converted deny takes the same "don't write the marker" path unattended
# already did. It repeats until a reviewer/advisor/codex-read spawn actually appears in the transcript,
# at which point the evidence check above exits 0 on its own.
if [ "$DEC" != deny ] && [ "$UNRESOLVED_REPO_FLAG" != 1 ] && [ -n "$MARKER" ]; then
  { mkdir -p "$ASKED_DIR" && : > "$ASKED_DIR/$MARKER"; } 2>/dev/null || note "marker write failed for $MARKER - will ask again next commit"
fi
if [ "$UNRESOLVED_REPO_FLAG" = 1 ]; then
  # The --git-dir/--work-tree case (see the comment above where UNRESOLVED_REPO_FLAG is set): no
  # reviewer-evidence was found (or this exits above), and there is no mechanical fix to offer - a
  # human has to say either "re-spell the target" or "this genuinely is a detached checkout, use a
  # real terminal". Same shared reason every other unresolved-repo-target case in this kit uses.
  note "$DEC: unresolved repo-selecting flag (--git-dir/--work-tree) in $ACT_WORD segment [sid=$SESSION_ID agent=${AGENT_TYPE:-lead}]"
  REASON="review-gate-guard: ${RG_REASON_TMPL}"
else
  note "$DEC: $ACT_WORD with no reviewer/advisor/codex-read spawn in session ${SESSION_ID:-<unknown>} repo ${REPO_SLUG:-<unknown>} [sid=$SESSION_ID agent=${AGENT_TYPE:-lead}]"
  REASON="SC-5.2: this session has no independent review pass yet (no reviewer / advisor / codex-read spawn seen; a /codex:review run is not detected, say so if you did one) and is about to $ACT_WORD in ${REPO:-this repo}."
  # push-mode's own local commits pass without asking (see the mode block above) - a publish act still
  # asks in that mode, and says so, so the quiet local commits aren't misread as "review isn't needed".
  if [ "$ACT" = ship ] && [ "$RG_MODE" = push ]; then
    REASON="${REASON} This repo is commit-first (review_gate: push) - local commits don't ask, but review is still due before this ${ACT_WORD} publishes them."
  fi
  REASON="${REASON} Non-trivial diff -> spawn a reviewer first (one opus call, announce-only). Trivial (typo, doc line, config nudge) -> proceed; this asks once per session per repo."
  if [ -n "$AGENT_TYPE" ]; then
    REASON="${REASON% Trivial*} You are a delegated agent - you cannot judge triviality here or spawn a reviewer yourself. Leave the $ACT_WORD as-is, stop, and report this text back to the Lead so it can decide and clear the gate."
  elif [ "$DEC" = deny ]; then
    REASON="${REASON% Trivial*} There is no human here to judge triviality, so this repeats until a reviewer / advisor / codex-read spawn exists in this session - retrying the same $ACT_WORD unchanged will hit the same deny."
  fi
fi
REASON="$(guard_ask_prefix "${SESSION_ID:-}" "$AGENT_TYPE")${REASON}"
jq -n --arg r "$REASON" --arg d "$DEC" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
exit 0

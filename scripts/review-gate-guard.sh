#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: soft `ask` when a `git commit` is about to run in a
# session that has NOT yet spawned an independent reviewer - the arrival event for SC-5.2 ("any
# non-trivial diff takes an independent fresh-eyes pass before it ships"). Sibling of vcs-commit-guard.sh
# and hygiene-commit-guard.sh: same commit-segment regex, same fail-open posture, same log.
#
# Why this exists: measured across two doctrine-usage reviews, SC-5.2 was violated in roughly one of every
# four commit-bearing sessions, and every one of those sessions had the rule loaded - the 2.1% lesson
# again: a rule fires only when something checks it at an ACT, and the act here is the commit.
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
# not to deny or decline (guard_unresolved_repo_flag(), see the marker-read/write sites below).
#
# `ask`, deliberately: SC-5.2 says NON-TRIVIAL, and a hook cannot judge triviality - the human can, in
# one click. To keep this from becoming wallpaper it asks ONCE per session PER REPO: after the first ask
# (whatever the answer) a marker under .state/review-gate-asked/<session-id>__<repo-slug> silences it for
# that session+repo; a later reviewer spawn silences it anyway. Per repo, because a session often commits
# to more than one repo and the trivial docs commit in repo A must not spend the one ask that the risky
# commit in repo B needed. Markers older than 7 days are GC'd opportunistically, same as
# session-prefs. `permissionDecisionReason` on `ask` is shown to the USER, so it is a visible checkpoint.
# ponytail: no diff-size floor - the once-per-session marker is the anti-wallpaper mechanism; the upgrade
# path is a staged+unstaged line count if the ask still lands on trivial commits too often.
#
# Fail-open on any tooling gap (no jq, no transcript, unreadable state dir). Never denies on an ATTENDED,
# Lead-originated call - the two conversions (unattended session, subagent caller - guard_ask_decision)
# are both a real ask with nobody able to answer it, never an infrastructure gap.
# Self-check: review-gate-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s review-gate-guard %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
    tail -n 2500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null || true
  fi
}

INPUT="$(cat 2>/dev/null || true)"
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
[ -n "${CMDPOS_COMMIT_FRAG:-}" ] && command -v guard_unresolved_repo_flag >/dev/null 2>&1 && command -v guard_cwd_unresolved >/dev/null 2>&1 && command -v guard_ask_decision >/dev/null 2>&1 && command -v guard_ask_prefix >/dev/null 2>&1 && command -v guard_caller_agent >/dev/null 2>&1 && command -v guard_commit_seg >/dev/null 2>&1 || { note "fail-open: guard-cmdpos.sh sourced but CMDPOS_COMMIT_FRAG/guard_unresolved_repo_flag/guard_cwd_unresolved/guard_ask_prefix/guard_caller_agent/guard_commit_seg undefined (stale library?)"; exit 0; }
SEGMENTS="$(guard_split_segments "$CMD")"
# Shared detector (guard-cmdpos.sh guard_commit_seg) - the four commit-time guards agree on what a
# commit is because they call ONE function, not because they copy one regex (T1.2, 2026-08-16).
COMMIT_SEG="$(guard_commit_seg "$SEGMENTS")"
[ -n "$COMMIT_SEG" ] || exit 0

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || { note "fail-open: no readable transcript_path in payload"; exit 0; }

# Session id becomes a path component under .state - same charset guard as resume-inject.sh /
# codex-home-isolate.sh (F-12). An unusable id disables the once-per-session marker (asks every commit
# in that session), never a traversal.
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in *[!A-Za-z0-9._-]* | '.' | '..') SESSION_ID="" ;; esac
AGENT_TYPE="$(guard_caller_agent "$INPUT")"
# Repo component of the marker: the git toplevel of the EFFECTIVE cwd (the payload's .cwd, walked
# forward through any `cd` segment before the commit - guard_resolve_cwd, F-cwd-bypass 2026-08-16;
# the raw payload field alone silently keyed the marker to the wrong repo whenever the command itself
# cd'd elsewhere), else the cwd itself; slugged with the same path->dashes rule the kit uses for
# project dirs.
PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
CWD=""; UNRESOLVED_CD=""
[ -n "$PAYLOAD_CWD" ] && CWD="$(guard_resolve_cwd "$SEGMENTS" "$CMDPOS_COMMIT_FRAG" "$PAYLOAD_CWD")"
# An unresolvable `cd`/`-C` target (T1.10, 2026-08-16) means CWD/REPO would be the WRONG repo - same
# treatment as the flag case just below (skip the repo-keyed marker, ask unconditionally); never fall
# back to the payload cwd, which is exactly the wrong-repo marker key that case documents.
if [ -n "$CWD" ] && guard_cwd_unresolved "$CWD"; then UNRESOLVED_CD="${CWD#unresolved }"; CWD=""; fi
# `--git-dir=`/`--work-tree=` (guard_unresolved_repo_flag(), guard-cmdpos.sh) mean CWD/REPO below may
# be the WRONG repo - this guard's actual criterion (was a reviewer/advisor/codex-read spawned THIS
# SESSION) is repo-independent, only the once-per-session-PER-REPO marker is repo-keyed, so the fix is
# narrower than hygiene's deny or vcs's decline: skip reading/writing the marker (a wrong-repo marker
# could wrongly SILENCE an ask that should have fired, or wrongly silence a FUTURE commit to the real
# target) and just ask every time this shape appears, rather than guess which repo "already asked"
# means (opus advisor, 2026-08-16).
UNRESOLVED_REPO_FLAG=0
guard_unresolved_repo_flag "$COMMIT_SEG" && UNRESOLVED_REPO_FLAG=1
[ "$UNRESOLVED_REPO_FLAG" = 1 ] && note "unresolved repo-selecting flag (--git-dir/--work-tree) in commit segment - marker read/write skipped, asking unconditionally"
[ -n "$UNRESOLVED_CD" ] && { UNRESOLVED_REPO_FLAG=1; note "unresolvable cd/-C target ($UNRESOLVED_CD) before the commit segment - marker read/write skipped, asking unconditionally"; }
REPO=""
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  REPO="$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$REPO" ] || REPO="$CWD"
fi
REPO_SLUG="$(printf '%s' "$REPO" | tr -c 'A-Za-z0-9' '-' | cut -c1-120)"
MARKER=""
[ -n "$SESSION_ID" ] && MARKER="${SESSION_ID}__${REPO_SLUG:-norepo}"
ASKED_DIR="${BASE:-${TMPDIR:-/tmp}}/.state/review-gate-asked"
{ [ -d "$ASKED_DIR" ] && find "$ASKED_DIR" -type f -mtime +7 -delete; } 2>/dev/null || true
if [ "$UNRESOLVED_REPO_FLAG" != 1 ] && [ -n "$MARKER" ] && [ -f "$ASKED_DIR/$MARKER" ]; then
  exit 0
fi

# The independent-pass evidence: a real Agent/Task tool_use with a review-class subagent_type. grep
# pre-filters candidate lines (transcripts run to many MB; jq over the whole file would eat the 5s
# budget), jq -R/fromjson? tolerates a corrupt line, and the structural select is what stops agent
# listings, pasted prompts and file reads from counting.
if grep -a '"subagent_type"' "$TRANSCRIPT" 2>/dev/null \
   | jq -R -r 'fromjson? | .message.content? | if type=="array" then .[] else empty end
               | select(.type=="tool_use" and (.name=="Agent" or .name=="Task"))
               | .input.subagent_type? // empty' 2>/dev/null \
   | grep -qxE 'reviewer|advisor|codex-read'; then
  exit 0
fi

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
note "$DEC: commit with no reviewer/advisor/codex-read spawn in session ${SESSION_ID:-<unknown>} repo ${REPO_SLUG:-<unknown>} [sid=$SESSION_ID agent=${AGENT_TYPE:-lead}]"
REASON="SC-5.2: this session has no independent review pass yet (no reviewer / advisor / codex-read spawn seen; a /codex:review run is not detected, say so if you did one) and is about to commit in ${REPO:-this repo}. Non-trivial diff -> spawn a reviewer first (one opus call, announce-only). Trivial (typo, doc line, config nudge) -> proceed; this asks once per session per repo."
if [ -n "$AGENT_TYPE" ]; then
  REASON="${REASON% Trivial*} You are a delegated agent - you cannot judge triviality here or spawn a reviewer yourself. Leave the commit as-is, stop, and report this text back to the Lead so it can decide and clear the gate."
elif [ "$DEC" = deny ]; then
  REASON="${REASON% Trivial*} There is no human here to judge triviality, so this repeats until a reviewer / advisor / codex-read spawn exists in this session - retrying the same commit unchanged will hit the same deny."
fi
REASON="$(guard_ask_prefix "${SESSION_ID:-}" "$AGENT_TYPE")${REASON}"
jq -n --arg r "$REASON" --arg d "$DEC" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
exit 0

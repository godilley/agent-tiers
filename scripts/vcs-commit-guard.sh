#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: warn (do not block) when a `git commit` is about to include a
# path this project's vcs_policy marks `ignore-*` - the class of never-commit personal/machine-local
# artifact (RESUME_SESSION.md, docs/_local/, .claude/agent-tiers.local.md, ...). Fires at the SAME
# commit-time arrival point as hygiene-commit-guard.sh (a sibling, not a merge into it - see below).
#
# Why this exists: `resume-inject.sh` already SURFACES the vcs_policy never-commit list to the model at
# SessionStart/compact/resume - but surfacing is not enforcement, and the incident that motivated the
# vcs_policy feature in the first place was a Lead nudging a commit of RESUME_SESSION.md DESPITE the
# policy existing. This closes the loop at the one point that's actually observable: the commit itself.
#
# `ask` normally, deliberately not a raw `deny`: a policy-ignored file is sometimes committed on purpose
# (a team may choose `commit` for a given key, or a one-off exception is a real decision, not an error) -
# unlike the output-hygiene guard's glyph rule, there is no case where the ignore-* disposition is
# unconditionally wrong to override. `permissionDecisionReason` on `ask` is shown to the USER (not just
# fed back to the model as `deny`'s is), so this is a human-visible checkpoint, not a self-correcting
# nudge. (2026-08-27: `ask` still converts to `deny` when nobody is present to make that judgement -
# an unattended session, or a subagent caller that cannot decide "deliberate exception" on its own
# authority - see guard_ask_decision/guard_ask_prefix in guard-cmdpos.sh. Both are conversions of a real
# finding, never a raw infrastructure response.)
#
# Scope of "what this commit touches" - narrower than hygiene-commit-guard.sh's repo-wide unstaged-diff
# union ON PURPOSE (advisor-reviewed 2026-08-07, docs/_local/2026-08-07-parser-crosscheck-vcs-guard-
# plan.md): hygiene's "scan everything dirty" is glyph-specific reasoning (a glyph ANYWHERE in the tree
# is bad regardless of what this commit stages) that does not transfer to "will THIS commit include
# this file" - copying it would false-`ask` on nearly every commit in a repo where an ignore-personal
# file (RESUME_SESSION.md) is dirty by design in most sessions. Scanned instead: (1) `git diff --cached
# --name-only` (staged), (2) literal path/dir arguments parsed off any `git add` segment in the SAME
# command, quote/`./`-stripped and re-anchored to the repo root (a `.`/`-A`/`--all`/`*`/`:/` token
# instead triggers a REPO-WIDE scan of `git status --porcelain`, capped at 500 entries like hygiene's
# untracked scan, same "over-broad on purpose" rationale - `git add .` really can pick up anything; `--`
# is deliberately EXCLUDED from that list - it means end-of-options and stages nothing by itself, so
# treating it as "everything" would be a false-`ask`), and (3) unstaged-tracked files (`git diff
# --name-only`) when the commit segment carries `-a`/`--all`, OR the add segment carries `-u`/
# `--update` (the identical tracked-modifications-repo-wide case, just spelled on `add`). Note: the
# whole-tree scan reads real `git status` output, so it structurally can't see a path already covered by
# a `.gitignore`/`.git/info/exclude` entry - not a gap in practice, since `git add .` can't stage such a
# path either without `-f`; the guard's other scan legs (staged / explicit `git add <path>` / `-a` on an
# already-tracked file) are what catch the force/already-tracked bypass of that same exclude.
#
# Commit-segment DETECTION is now STRUCTURAL, not enumerated: any option-shaped token between
# `git` and `commit` (`-C <path>`, `-c <key>=<val>`, `--git-dir=`, `--work-tree=`, `--no-pager`,
# anything) is recognised - CMDPOS_COMMIT_FRAG in guard-cmdpos.sh, 2026-08-16 follow-up. Before this,
# any global option between `git` and `commit` bypassed every commit-time guard OUTRIGHT (the bare
# `git commit` match never fired at all). `--git-dir=`/`--work-tree=` specifically now make this guard
# DECLINE to scan at all (guard_unresolved_repo_flag(), before any cwd resolution) rather than scan
# whatever cwd `cd`/`-C` already resolved to, which may be the wrong repo - this guard's `deny` is
# always a conversion of an actual finding (guard_ask_decision), never a raw response to an unresolved
# repo, so refusing to scan is the honest move here, not a wrong-repo `ask` (or `deny`).
#
# vcs_policy resolution: identical two-file order to resume-inject.sh - the project's
# `.claude/agent-tiers.local.md` `vcs_policy:` block if present, else the kit's `kit-config.md`
# `vcs_defaults:` block. Path per key is parsed from the trailing `# <path> ...` comment on that same
# line (the convention both files already use today, e.g. `resume_session: ignore-personal # RESUME_
# SESSION.md ...`) rather than a hardcoded key->path table, which would drift the first time either
# file gains a row. Known, disclosed gap: `task_agents: ... # .claude/agents/<prefix>-*.md` in
# kit-config.md is a PLACEHOLDER, not a real path or glob - any token containing `<`/`>` is skipped
# (breadcrumbed), not silently glob-matched against nothing. No other current key's path token contains
# a glob character, so no glob-matching is implemented; a future globbed key would need one added here.
#
# Commit-segment detection is the shared guard_commit_seg() (guard-cmdpos.sh): CMDPOS_PREFIX +
# CMDPOS_COMMIT_FRAG at command position, so `sudo git commit`, `nohup git commit`, `then git commit`,
# `( git commit )` and `/usr/bin/git commit` all fire, in lockstep across all four commit-time guards.
# CORRECTION 2026-08-16 (Tier 1 review, T1.2/T2.1): the previous version of this comment said the
# guards matched a "narrower" `^[[:space:]]*` anchor, claimed disclosed elsewhere, ON PURPOSE so they would not
# "diverge on e.g. `sudo git commit`". That was the only place `sudo git commit` appeared in guard prose
# (guard-cmdpos.selfcheck.sh asserts the string matches at command position - which is what made the
# false equivalence plausible), and the ceiling was disclosed nowhere - the guards were in lockstep at ZERO wrapper coverage
# (measured: sudo/nohup/path/paren/brace/if-then all silent). The reassuring comment sat exactly
# where a reader would look for the ceiling. Fixed by moving detection into one function.
# `guard_split_segments()` is reused here for the segment split itself - that part carries no
# behavior difference to migrate.
#
# Fail-open on any tooling gap (no jq, no git, cwd missing/unreadable, `git diff`/`git status` failing,
# no vcs_policy source found or unparsable) - breadcrumbed like every other guard in this kit. Never
# emits `deny`. Self-check: vcs-commit-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s vcs-commit-guard %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
    tail -n 2500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null || true
  fi
}

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
sid() { printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true; }   # lazy: only a decision line pays the jq
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
[ -n "${CMDPOS_COMMIT_FRAG:-}" ] && command -v guard_unresolved_repo_flag >/dev/null 2>&1 && command -v guard_cwd_unresolved >/dev/null 2>&1 && command -v guard_ask_decision >/dev/null 2>&1 && command -v guard_ask_prefix >/dev/null 2>&1 && command -v guard_caller_agent >/dev/null 2>&1 && command -v guard_commit_seg >/dev/null 2>&1 && command -v guard_git_add_segs >/dev/null 2>&1 && command -v guard_norm_add_paths >/dev/null 2>&1 || { note "fail-open: guard-cmdpos.sh sourced but CMDPOS_COMMIT_FRAG/guard_unresolved_repo_flag/guard_cwd_unresolved/guard_ask_prefix/guard_caller_agent/guard_commit_seg/guard_git_add_segs/guard_norm_add_paths undefined (stale library?)"; exit 0; }
SEGMENTS="$(guard_split_segments "$CMD")"
COMMIT_SEG="$(guard_commit_seg "$SEGMENTS")"
[ -n "$COMMIT_SEG" ] || exit 0

# `--git-dir=`/`--work-tree=` (guard_unresolved_repo_flag(), guard-cmdpos.sh) mean this guard cannot
# know which repo's vcs_policy/staged content it would be checking - DECLINE rather than guess (this
# guard's deny is always a conversion of a real finding, never a raw response to an unknown repo, so
# scanning the wrong repo has nothing honest to convert; the honest move is to not scan at all, not to
# scan the wrong repo and ask/allow/deny based on it. Checked before any cwd resolution.
if guard_unresolved_repo_flag "$COMMIT_SEG"; then
  note "declined: unresolved repo-selecting flag (--git-dir/--work-tree) in commit segment - cannot know which repo's vcs_policy applies, not scanning [sid=$(sid)]"
  exit 0
fi

PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
if [ -n "$PAYLOAD_CWD" ]; then
  # A `cd` before the commit segment runs the commit somewhere other than the payload's own .cwd -
  # resolve that, not the raw payload field (guard-cmdpos.sh guard_resolve_cwd, F-cwd-bypass 2026-08-16).
  CWD="$(guard_resolve_cwd "$SEGMENTS" "$CMDPOS_COMMIT_FRAG" "$PAYLOAD_CWD")"
  # An unresolvable `cd`/`-C` target (T1.10, 2026-08-16) is the same class as the flag decline above:
  # never fall back to the payload cwd (the wrong repo's vcs_policy), decline to scan.
  if guard_cwd_unresolved "$CWD"; then
    note "declined: unresolvable cd/-C target (${CWD#unresolved }) before the commit segment - cannot know which repo's vcs_policy applies, not scanning [sid=$(sid)]"
    exit 0
  fi
  cd "$CWD" 2>/dev/null || { note "fail-open: cwd ($CWD, resolved from payload $PAYLOAD_CWD) not enterable - scan skipped"; exit 0; }
else
  note "fail-open: no .cwd in payload - scanning whatever repo the hook process inherited"
fi
command -v git >/dev/null 2>&1 || { note "fail-open: git missing"; exit 0; }
TOP="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$TOP" ] || { note "fail-open: not inside a git repo (or bare repo)"; exit 0; }
# cwd's path prefix relative to $TOP (e.g. "sub/", empty at the repo root) - git's own answer to "what
# does a relative add-argument typed HERE resolve to", used below instead of hand-rolling it.
PREFIX="$(git rev-parse --show-prefix 2>/dev/null)"

# --- resolve vcs_policy: project file first, else the kit default (same order as resume-inject.sh) ---
VCS_SRC="$TOP/.claude/agent-tiers.local.md"; VCS_KEY="vcs_policy"
if ! grep -aq "^$VCS_KEY:" "$VCS_SRC" 2>/dev/null; then
  VCS_SRC="${BASE:-}/kit-config.md"; VCS_KEY="vcs_defaults"
fi
[ -f "$VCS_SRC" ] || { note "fail-open: no vcs_policy source found (checked $TOP/.claude/agent-tiers.local.md and ${BASE:-<unset>}/kit-config.md)"; exit 0; }

# key<TAB>path<TAB>disposition rows, ignore-* dispositions only. Same charset/row/length caps as
# resume-inject.sh's equivalent parse (project-controlled file, tokens must never reach the decision
# reason unbounded).
PAIRS="$(awk -v key="$VCS_KEY" '
  $0 ~ "^"key":" {inblk=1; next}
  inblk && /^[^[:space:]#]/ {inblk=0}
  inblk && $2 ~ /^ignore/ && $1 ~ /^[A-Za-z0-9_.-]+:?$/ && length($1) <= 41 && n < 12 {
    k=$1; sub(/:$/,"",k)
    line=$0
    if (sub(/^[^#]*#[[:space:]]*/, "", line)) {
      split(line, parts, /[[:space:]]+/)
      p = parts[1]
      if (length(p) > 0 && length(p) <= 200) { print k "\t" p "\t" $2; n++ }
    }
  }
' "$VCS_SRC" 2>/dev/null)"
[ -n "$PAIRS" ] || { note "fail-open: vcs_policy source ($VCS_SRC) has no ignore-* rows, or is unparsable"; exit 0; }

SKIPPED="$(printf '%s\n' "$PAIRS" | grep -a '[<>]')"
PAIRS="$(printf '%s\n' "$PAIRS" | grep -av '[<>]')"
[ -n "$SKIPPED" ] && note "skipping placeholder path token(s) (contains < or >, not a real path): $(printf '%s' "$SKIPPED" | tr '\n' ';' | cut -c1-160)"
[ -n "$PAIRS" ] || exit 0

# --- what this commit would touch ---
STAGED="$(git -c core.quotePath=false diff --cached --name-only 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] || { note "fail-open: git diff --cached failed (rc=$RC)"; exit 0; }

# literal path/dir args off any `git add` segment. Quote-stripped (a typed `"RESUME_SESSION.md"` token
# carries the quote bytes literally in the command string) and `./`-stripped, then re-anchored to the
# repo root via $PREFIX - a token typed from a subdirectory otherwise compares against the wrong path
# (both a miss on the real target AND a false match against an unrelated root-level policy path of the
# same basename). `-u`/`--update` restages tracked modifications repo-wide (the same class `-a` on the
# commit segment handles, just spelled on `add`); `.`/`-A`/`--all`/`*`/`:/` trigger the whole-tree scan.
# `--` (end-of-options, stages NOTHING by itself) is deliberately EXCLUDED from that list - treating it
# as "everything" was the false-`ask` class this guard exists to avoid.
# Disclosed gap (opus reviewer, 2026-08-16): NOT CMDPOS_COMMIT_FRAG-aware - a `git -C <path> add
# file && git -C <path> commit` fires this guard with the right cwd (the commit half resolves), but
# stays blind to that one not-yet-staged file, same as if no `git add` segment were present.
ADD_SEGS="$(guard_git_add_segs "$SEGMENTS")"
ADD_PATHS=""; WHOLE_TREE=0; UPDATE_TRACKED=0
if [ -n "$ADD_SEGS" ]; then
  # `#` delimiter: CMDPOS_PREFIX contains `/` (same trap guard_resolve_cwd's cd leg documents).
  ADD_TOKENS="$(printf '%s\n' "$ADD_SEGS" | sed -E "s#^[[:space:]]*[({]?[[:space:]]*${CMDPOS_PREFIX}git[[:space:]]+add[[:space:]]*##" | tr '[:space:]' '\n' | grep -av '^[[:space:]]*$')"
  printf '%s\n' "$ADD_TOKENS" | grep -aqxE -- '\.|-A|--all|\*|:/' && WHOLE_TREE=1
  printf '%s\n' "$ADD_TOKENS" | grep -aqxE -- '-u|--update' && UPDATE_TRACKED=1
  # guard_norm_add_paths (guard-cmdpos.sh): shared with kit-leak-guard.sh, and NOT an inline loop -
  # bash 3.2 (macOS /bin/sh) could not parse the `case` this used to carry inside a `$( )` (CI 2026-08-16).
  ADD_PATHS="$(printf '%s\n' "$ADD_TOKENS" | grep -av '^-' | guard_norm_add_paths "$PREFIX")"
fi

UNSTAGED=""
# `-a` can arrive bundled with other short flags (`-am`, `-qa`) - match any single-dash, all-letters
# token containing an `a`, plus the `--all` long form. CORRECTION 2026-08-23: an earlier version of this
# comment claimed the shape "cannot MISS a real -a". It could - `git commit -am"wip"` ends the token at
# a quote, not whitespace. hygiene-commit-guard.sh (where the same miss became load-bearing) now accepts
# a quote as a terminator; here the consequence is only a narrower unstaged scan, so it is left alone
# rather than widened toward more false asks - stated, not silently inherited. Bounded so `--author` (double-dash) can't match.
# `add -u`/`--update` (above) needs the identical unstaged-tracked diff, so both feed one fetch. Known,
# disclosed gap: this matches against the WHOLE commit segment text, quotes included, so `git commit -m
# "handle -a and -A flags"` also sets this (message text, not a real flag) - broadens the unstaged scan
# unnecessarily but cannot MISS a real `-a`, and the false-widen only matters if an unrelated tracked
# ignore-* file also happens to be dirty at the same time. Left as-is: excluding `-m`'s argument text
# needs real quote-aware parsing, and a bad parse trades a rare miss for a common false `ask` - the
# worse direction for a guard whose whole point is avoiding false `ask`s.
NEED_UNSTAGED=0
printf '%s' "$COMMIT_SEG" | grep -aEq -- '(^|[[:space:]])(--all|-[a-zA-Z]*a[a-zA-Z]*)([[:space:]]|$)' && NEED_UNSTAGED=1
[ "$UPDATE_TRACKED" = 1 ] && NEED_UNSTAGED=1
if [ "$NEED_UNSTAGED" = 1 ]; then
  UNSTAGED="$(git -c core.quotePath=false diff --name-only 2>/dev/null)"; URC=$?
  [ "$URC" -eq 0 ] || { note "fail-open: git diff (unstaged) failed (rc=$URC) - unstaged-tracked leg not scanned"; UNSTAGED=""; }
fi

WHOLETREE_LIST=""
if [ "$WHOLE_TREE" = 1 ]; then
  WT_ALL="$(git -c core.quotePath=false status --porcelain --untracked-files=all 2>/dev/null)"; WRC=$?
  if [ "$WRC" -ne 0 ]; then
    note "fail-open: git status failed (rc=$WRC) - whole-tree leg not scanned"
  else
    WT_ALL="$(printf '%s\n' "$WT_ALL" | cut -c4-)"
    WT_COUNT="$(printf '%s\n' "$WT_ALL" | grep -ac '.')"
    if [ "$WT_COUNT" -gt 500 ]; then
      note "whole-tree add: entry count ($WT_COUNT) exceeds the 500-entry scan cap - only the first 500 checked"
      WT_ALL="$(printf '%s\n' "$WT_ALL" | head -n 500)"
    fi
    WHOLETREE_LIST="$WT_ALL"
  fi
fi

TOUCHED="$STAGED
$UNSTAGED
$ADD_PATHS
$WHOLETREE_LIST"

PAIRS_FILE="$(mktemp "${TMPDIR:-/tmp}/vcs-pairs.XXXXXX" 2>/dev/null)" || { note "fail-open: mktemp failed"; exit 0; }
TOUCHED_FILE="$(mktemp "${TMPDIR:-/tmp}/vcs-touched.XXXXXX" 2>/dev/null)" || { rm -f "$PAIRS_FILE"; note "fail-open: mktemp failed"; exit 0; }
printf '%s\n' "$PAIRS" > "$PAIRS_FILE"
printf '%s\n' "$TOUCHED" > "$TOUCHED_FILE"

HIT="$(awk -F'\t' '
  NR==FNR { if ($1!="") { k[++n]=$1; p[n]=$2; d[n]=$3 }; next }
  {
    tp=$0
    if (tp=="") next
    for (i=1;i<=n;i++) {
      pat=p[i]; sub(/\/$/,"",pat)
      if (tp==pat || index(tp, pat "/")==1) { print tp "\t" k[i] "\t" p[i] "\t" d[i]; exit }
    }
  }
' "$PAIRS_FILE" "$TOUCHED_FILE" 2>/dev/null)"
rm -f "$PAIRS_FILE" "$TOUCHED_FILE"

[ -n "$HIT" ] || exit 0

# HIT is "touched-path<TAB>key<TAB>policy-path<TAB>disposition" - all 4 fields come from the awk match
# above, not re-derived by a second lookup (the second-lookup version of this drifted: it re-read PAIRS
# by key and grabbed the PATH column instead of the disposition column). Touched path is real git/command
# output, not policy-controlled, so it's capped here the same way the policy side already is.
HIT_PATH="$(printf '%s' "${HIT%%	*}" | cut -c1-200)"
REST="${HIT#*	}"; HIT_KEY="${REST%%	*}"; REST="${REST#*	}"; HIT_DISP="${REST#*	}"
[ -n "$HIT_DISP" ] || HIT_DISP="ignore-*"

# an already-TRACKED policy path needs `git rm --cached` (a .gitignore/exclude entry has no effect on a
# tracked path); everything else needs `git restore --staged` - same underlying "stop tracking it" goal,
# different command, and the wrong one silently doesn't fix the problem.
if git ls-files --error-unmatch -- "$HIT_PATH" >/dev/null 2>&1; then
  REMEDY="it is already TRACKED - untrack it (git rm --cached -- '$HIT_PATH') and add it to .git/info/exclude so it stops recurring"
else
  REMEDY="unstage it (git restore --staged -- '$HIT_PATH') and add it to .git/info/exclude so it stops recurring"
fi

AGENT_TYPE="$(guard_caller_agent "$INPUT")"
DEC="$(guard_ask_decision "$(sid)" "$AGENT_TYPE")"
REASON="This commit looks like it would include '$HIT_PATH', which vcs_policy marks '$HIT_KEY: $HIT_DISP' (source: $VCS_SRC). If that's unintentional: $REMEDY."
# The subagent-converted deny must not end by telling the very actor it just told to stop to "proceed"
# instead (opus reviewer, 2026-08-27, MEDIUM) - a worker cannot judge "deliberate exception" either.
if [ -n "$AGENT_TYPE" ]; then
  REASON="$REASON You cannot judge whether this is a deliberate exception - leave it as-is, stop, and report this back to the Lead."
else
  REASON="$REASON If it's a deliberate exception, proceed."
fi
REASON="$(guard_ask_prefix "$(sid)" "$AGENT_TYPE")${REASON}"
note "$DEC: $HIT_PATH ($HIT_KEY: $HIT_DISP) [sid=$(sid) agent=${AGENT_TYPE:-lead}]"
jq -n --arg r "$REASON" --arg d "$DEC" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
exit 0

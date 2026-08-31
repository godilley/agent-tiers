#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: run the output-hygiene scan (em/en dash, curly quotes, NBSP,
# ZWSP, ellipsis glyph - the global CLAUDE.md hard rule) against everything about to enter the
# commit - staged diff, ALL unstaged changes to tracked files repo-wide, new untracked files `git add`
# would pick up, and the commit MESSAGE itself - chained to the commit it guards, so it can never run
# unchained again.
#
# Why a hook, not a rerun-by-hand check: a 2026-08-05 session - the hygiene scan existed only as an
# inline python heredoc, hand-rewritten 10 times across one session (growing more paranoid each time:
# rg regex -> dict-based check -> chr()-code construction, because the assistant stopped trusting its
# OWN prior version not to have been mangled in transit), and the ONE time it actually tripped
# (AssertionError) the `git commit` on the next unchained line still ran anyway - the guard and the
# commit were two statements in one Bash call, not `&&`-joined, so the heredoc's exit 1 never stopped
# the commit. This hook removes both failure modes: it IS the canonical check (nothing to
# hand-rewrite), and it fires at the PreToolUse layer, mechanically upstream of the commit itself, so
# there is no "forgot to chain it" left to forget.
#
# Scope: fires on any command whose commit-segment matches `git commit` (per-pipeline-segment split,
# same idiom as grep-footgun-guard.sh - a commit anywhere in a chained command trips this). Runs in
# the EFFECTIVE cwd (the payload's OWN `.cwd`, not the hook process's inherited cwd - the kit-wide
# guard convention - walked forward through any `cd` segment before the commit via guard-cmdpos.sh's
# guard_resolve_cwd), so a `cd other-repo && git commit` scans the right tree. Before 2026-08-16 this
# trusted the raw payload `.cwd` and silently scanned the WRONG repo whenever the command itself
# `cd`'d elsewhere - live-verified false negative, see guard_resolve_cwd's header. Scans, UNION:
# (1) `git diff --cached`, (2) `git diff` (unstaged changes to already-TRACKED files, repo-wide -
# The default scope (`hygiene_scope: repo`, see the scope block below) is not gated on `-a`/`--all`
# being present: PreToolUse fires before the WHOLE Bash
# command runs, so `git add X && git commit` in one call has staged nothing yet at scan time either -
# the round-2 fix that gated this on `-a` closed one instance of that gap, not the class; scanning
# `git diff` unconditionally closes it structurally instead of enumerating every way a change can
# reach the index at commit time - **honest cost, not hidden: this can deny a commit over a glyph in
# an UNRELATED dirty file that isn't actually part of what's being committed** - round 3 review found
# this consequence real and undisclosed; the deny reason below now says so explicitly), (3) new
# UNTRACKED files, only when a `git add` segment is present anywhere in the same command (avoids
# scanning the whole untracked working tree on every commit), resolved against the REPO ROOT (round-3
# HIGH: `git status --porcelain` paths are repo-root-relative, but the prior version tested `[ -f
# "$f" ]` from the payload's `.cwd` - a commit run from ANY subdirectory silently scanned zero
# untracked files while the deny reason still claimed it had), and (4) the commit-segment TEXT
# itself, which catches an inline `-m "message with a violation"` directly - the typed bytes are
# already right there in the command string, no parsing needed (a message passed via `-F <file>` or
# `-m "$VAR"`, or one entered interactively with no `-m`/`-F` at all, is NOT covered - see bypass set).
#
# ponytail: same glyph list as the global CLAUDE.md rule (em dash U+2014, en dash U+2013, NBSP
# U+00A0, ZWSP U+200B, curly quotes U+2018/2019/201C/201D, ellipsis U+2026), matched as literal UTF-8
# BYTE sequences via `grep -aF` - not a `-P`/Unicode-escape dependent match, so this does not silently
# no-op on a grep built without PCRE support. Known bypass set (accurate, not aspirational,
# re-verified in review 2026-08-06, round 3; the plain-`cd` case closed 2026-08-16, commit-segment
# DETECTION is now STRUCTURAL - any option-shaped token between `git` and `commit` is recognised, not
# an enumerated list - via guard_resolve_cwd / CMDPOS_COMMIT_FRAG, that constant's header in
# guard-cmdpos.sh has the full reasoning): RESOLUTION (which repo a commit targets) stays narrower -
# only `-C` moves cwd and is folded in; a commit run against an EXPLICIT `--git-dir`/`--work-tree` DENIES
# outright (2026-08-16 follow-up, guard_unresolved_repo_flag() in guard-cmdpos.sh) rather than scan
# whatever cwd `cd`/`-C` already resolved to, which may be the wrong repo entirely - this guard can
# already `deny` on a glyph, so a wrong-repo scan-and-deny (pointing the model at an unrelated fix) was
# judged worse than refusing up front, given `-C` already covers every legitimate reason to target a
# repo other than the payload cwd in one command; a glyph inside a BINARY file diff is not scanned (`git diff` skips binary hunks by
# design); a commit with `--no-verify` still runs through THIS hook (PreToolUse fires regardless of
# git's own hook bypass flag - a strict IMPROVEMENT over a real git hook, not a gap); the untracked-
# file scan reads the WHOLE untracked set whenever any `git add` segment is present, even a narrowly
# targeted `git add specific-file.txt` (over-broad on purpose - a security-hygiene scan erring toward
# catching more is the safe direction), CAPPED at 500 files (a bigger untracked set is scanned only
# up to the cap - breadcrumbed, not a silent truncation - to bound a 5s hook timeout against a
# pathologically large un-gitignored tree, e.g. a fresh `dist/`); the commit-MESSAGE scan sees only
# the pre-split SEGMENT text, so a message containing a shell metacharacter (`;`/`|`/`&&`) is
# truncated at the split point, and `-F <file>`/`-m "$VAR"` scan the FILENAME/VARIABLE NAME, never
# the actual message body - both real, disclosed gaps, not silently claimed as covered.
# Fail-open on any tooling gap (no jq, no git, cwd missing/unreadable, `git diff` itself failing e.g.
# not a repo/bare repo) - breadcrumb EVERY such path, distinct from "ran clean, nothing to scan" which
# is not a tooling gap and stays silent (F-25). Self-check: hygiene-commit-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s hygiene-commit-guard %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
    tail -n 2500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null || true
  fi
}

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
sid() { printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true; }   # lazy: only a decision line pays the jq
[ -n "$CMD" ] || exit 0

# per-pipeline-segment split via the SHARED guard-cmdpos.sh library - a commit anywhere in a chained
# command trips this, not just a bare standalone `git commit`. This file used to carry its own inline
# sed copy; cold-review F3 (2026-08-10) found that copy was a GNU-ism that silently broke chained-call
# scanning on macOS, fixed once in the library, so the copies migrated onto it.
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
[ -n "${CMDPOS_COMMIT_FRAG:-}" ] && command -v guard_unresolved_repo_flag >/dev/null 2>&1 && command -v guard_cwd_unresolved >/dev/null 2>&1 && command -v guard_commit_seg >/dev/null 2>&1 && command -v guard_git_add_segs >/dev/null 2>&1 && command -v guard_norm_add_paths >/dev/null 2>&1 || { note "fail-open: guard-cmdpos.sh sourced but CMDPOS_COMMIT_FRAG/guard_unresolved_repo_flag/guard_cwd_unresolved/guard_commit_seg/guard_git_add_segs/guard_norm_add_paths undefined (stale library?)"; exit 0; }
SEGMENTS="$(guard_split_segments "$CMD")"
COMMIT_SEG="$(guard_commit_seg "$SEGMENTS")"
[ -n "$COMMIT_SEG" ] || exit 0

# `--git-dir=`/`--work-tree=` DENY unconditionally, before any cwd resolution or content scan
# (guard_unresolved_repo_flag(), guard-cmdpos.sh, 2026-08-16) - this guard can already `deny` on a
# glyph, so scanning the wrong repo's unrelated dirty file and denying on IT (pointing the model at a
# fix that doesn't apply to the commit actually running) is strictly worse than refusing up front. No
# marker, no once-per-session suppression - same posture as the glyph deny this guard already emits.
if guard_unresolved_repo_flag "$COMMIT_SEG"; then
  note "deny: unresolved repo-selecting flag (--git-dir/--work-tree) in commit segment [sid=$(sid)]"
  jq -n --arg r "hygiene-commit-guard: ${GUARD_UNRESOLVED_REPO_REASON}" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
fi

# any `git add` segment in the SAME command -> also cover new untracked files (see header).
ADD_PRESENT=0
# Disclosed gap (opus reviewer, 2026-08-16): NOT CMDPOS_COMMIT_FRAG-aware - a `git -C <path> add
# file && git -C <path> commit` fires this guard with the right cwd (the commit half resolves), but
# ADD_PRESENT stays 0, so the untracked-file scan this flag gates is skipped for that add.
ADD_SEGS="$(guard_git_add_segs "$SEGMENTS")"
[ -n "$ADD_SEGS" ] && ADD_PRESENT=1
# Add-path extraction for the narrow scope below - the same tokens, normalisation and shared helper
# vcs-commit-guard.sh and kit-leak-guard.sh use (third consumer; nothing new is parsed here).
# Pathspec commit (`git commit -m msg file.txt`) bypasses the index entirely - it commits the working
# tree content of the named paths, so under narrow those paths ARE this commit's content and must be
# scanned even with no `git add` anywhere (opus reviewer 2026-08-23, MEDIUM).
COMMIT_PATHS="$(printf '%s\n' "$COMMIT_SEG" | sed -E "s#^[[:space:]]*[({]?[[:space:]]*${CMDPOS_PREFIX}git[[:space:]]+(${CMDPOS_GITOPTS})*commit[[:space:]]*##" | tr '[:space:]' '\n' | grep -av '^[[:space:]]*$' | grep -av '^-' | guard_norm_add_paths "$(git rev-parse --show-prefix 2>/dev/null)")"
ADD_PATHS=""; ADD_WHOLE_TREE=0; ADD_UPDATE=0
if [ -n "$ADD_SEGS" ]; then
  # `#` delimiter: CMDPOS_PREFIX contains `/` (the trap guard_resolve_cwd's cd leg documents).
  ADD_TOKENS="$(printf '%s\n' "$ADD_SEGS" | sed -E "s#^[[:space:]]*[({]?[[:space:]]*${CMDPOS_PREFIX}git[[:space:]]+add[[:space:]]*##" | tr '[:space:]' '\n' | grep -av '^[[:space:]]*$')"
  printf '%s\n' "$ADD_TOKENS" | grep -aqxE -- '\.|-A|--all|\*|:/' && ADD_WHOLE_TREE=1
  printf '%s\n' "$ADD_TOKENS" | grep -aqxE -- '-u|--update' && ADD_UPDATE=1
  ADD_PATHS="$(printf '%s\n' "$ADD_TOKENS" | grep -av '^-' | guard_norm_add_paths "$(git rev-parse --show-prefix 2>/dev/null)")"
fi
# a pathspec commit's paths join the set narrow scans (the -m message's own words are filtered out by
# the same `^-`/token split the add side uses, and a stray word that is not a path simply matches nothing)
ADD_PATHS="$(printf '%s\n%s\n' "$ADD_PATHS" "$COMMIT_PATHS" | grep -av '^[[:space:]]*$' | sort -u)"

PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
if [ -n "$PAYLOAD_CWD" ]; then
  # A `cd` before the commit segment runs the commit somewhere other than the payload's own .cwd -
  # resolve that, not the raw payload field (guard-cmdpos.sh guard_resolve_cwd, F-cwd-bypass 2026-08-16).
  CWD="$(guard_resolve_cwd "$SEGMENTS" "$CMDPOS_COMMIT_FRAG" "$PAYLOAD_CWD")"
  # An unresolvable `cd`/`-C` target (T1.10, 2026-08-16: `mkdir X && cd X && git commit` - X does not
  # exist at PreToolUse time) is the SAME class as --git-dir/--work-tree above and takes the same deny:
  # NEVER fall back to the payload cwd - that scanned the session repo and denied on files the commit
  # never touched (three live false denials, 2026-08-16).
  # ponytail: this ALSO denies `cd "$VAR"`, `cd $(...)` and `cd -` before a commit (non-literal or
  # untracked target = unresolvable, same sentinel). Declining beat guessing: the guard genuinely does
  # not know where the commit lands, and the pre-fix guess (payload cwd) produced the false denials
  # above. Ceiling: legit variable-path commits are a new false-deny surface and the rate is
  # UNMEASURED - review after a week of use (`grep -a 'unresolvable cd/-C target' .state/guards.log`);
  # if material, the upgrade is decline-not-deny for the variable case only, never a fallback to cwd.
  # Third member (opus reviewer): the quote-blind splitter can SYNTHESISE a cd from a string in an
  # earlier segment (`echo "step; cd build" && git commit` -> segment ` cd build"`, unenterable, deny);
  # count that shape separately when reviewing the rate.
  if guard_cwd_unresolved "$CWD"; then
    UNRES="${CWD#unresolved }"
    note "deny: unresolvable cd/-C target ($UNRES) before the commit segment - not scanning the payload cwd instead [sid=$(sid)]"
    jq -n --arg r "hygiene-commit-guard: cd/-C target \`${UNRES}\` cannot be resolved at check time. ${GUARD_UNRESOLVED_REPO_REASON}" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
  cd "$CWD" 2>/dev/null || { note "fail-open: cwd ($CWD, resolved from payload $PAYLOAD_CWD) not enterable - scan skipped"; exit 0; }
  # (--git-dir=/--work-tree= already denied above, before this cwd resolution ever ran.)
else
  note "fail-open: no .cwd in payload - scanning whatever repo the hook process inherited (distinct breadcrumb, kit-wide guard convention)"
fi
command -v git >/dev/null 2>&1 || { note "fail-open: git missing - cannot scan staged diff"; exit 0; }

# Per-repo carve-out: <repo-root>/.hygiene-allow lists root-relative paths whose content
# legitimately CONTAINS the guarded glyphs (files that document them, e.g. a hygiene command's
# own reference table). Diff scans exclude them via pathspec magic; the untracked scan filters
# the file list; the commit-message text is ALWAYS scanned (a glyph typed into -m is a real
# violation regardless of which file the commit touches). Absent/empty file = no carve-out,
# behavior identical to before this seam existed.
TOP="$(git rev-parse --show-toplevel 2>/dev/null)"
ALLOW_LIST=""
if [ -n "$TOP" ] && [ -f "$TOP/.hygiene-allow" ]; then
  ALLOW_LIST="$(grep -av '^[[:space:]]*#' "$TOP/.hygiene-allow" 2>/dev/null | grep -av '^[[:space:]]*$' || true)"
fi
set --
if [ -n "$ALLOW_LIST" ]; then
  set -- ':/'
  while IFS= read -r p; do
    [ -n "$p" ] && set -- "$@" ":(top,exclude)$p"
  done <<ALLOW_EOF
$ALLOW_LIST
ALLOW_EOF
fi

# --- unstaged-scan scope (2026-08-23, bundle-9 W3-2) -------------------------------------------------
# `repo` (default): scan ALL unstaged changes to tracked files repo-wide. Closes the class structurally
# (PreToolUse fires before the whole Bash command, so nothing this command is about to stage is staged
# yet), at a disclosed cost: an unrelated dirty file in the same repo can deny a commit that never
# touched it - and a recipient's first such deny is the moment they unwire the guard.
# `narrow`: scan only the staged diff plus the paths named on a `git add` in THIS command, and the
# whole unstaged set when the commit is `-a`/`--all` (which stages them for real). Cheaper socially,
# and it BUYS BACK a real gap: `git add X && git commit` in one call, where X is neither staged yet nor
# named to us if the add is a directory or a glob we cannot expand at check time.
#
# Resolution order is the vcs_policy seam this kit already has (same two files, same precedence as
# vcs-commit-guard.sh and resume-inject.sh), so a recipient can change it PER REPO without reinstalling:
#   1. this repo's .claude/agent-tiers.local.md   `hygiene_scope: narrow`
#   2. the kit's kit-config.md                    `hygiene_scope: narrow`
#   3. built-in default                           repo
# Anything else - missing file, typo, empty value, two values, an unreadable config - resolves to
# `repo`. A config read by a security guard fails toward the STRICTER branch or it is a bypass with a
# friendly name.
HSCOPE=""
for hs_src in "${TOP:-/dev/null}/.claude/agent-tiers.local.md" "${BASE:-/dev/null}/kit-config.md"; do
  case "$hs_src" in /.claude/*|/kit-config.md) continue ;; esac   # empty TOP/BASE must not read from /
  [ -f "$hs_src" ] || continue
  # More than one hygiene_scope line is ambiguous, and the realistic shape is an operator APPENDING a
  # tightening line and believing they tightened it - so it resolves to repo, not to first-wins.
  hs_n="$(grep -ac '^hygiene_scope:' "$hs_src" 2>/dev/null || echo 0)"
  [ "${hs_n:-0}" -le 1 ] 2>/dev/null || { note "multiple hygiene_scope lines in $hs_src - ambiguous, using repo (strictest)"; HSCOPE=repo; HSCOPE_SRC="$hs_src"; break; }
  hs_val="$(grep -aE '^hygiene_scope:[[:space:]]*[A-Za-z]+[[:space:]]*$' "$hs_src" 2>/dev/null | head -1 | sed -E 's/^hygiene_scope:[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$hs_val" ] || continue
  HSCOPE="$hs_val"; HSCOPE_SRC="$hs_src"; break
done
case "${HSCOPE:-}" in
  narrow) ;;
  repo|'') HSCOPE=repo ;;
  *) note "unrecognised hygiene_scope '${HSCOPE}' in ${HSCOPE_SRC:-?} - falling back to repo (strictest)"; HSCOPE=repo ;;
esac

DIFF="$(git diff --cached -- "$@" 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] || { note "fail-open: git diff --cached failed (rc=$RC) - not a git repo / bare repo / other git error, scan skipped"; exit 0; }
# `-a`/`--all` stages every tracked change for real, so under EITHER scope the unstaged set is part of
# this commit and is scanned. Matched against the WHOLE commit segment, message text included (same
# disclosed shape vcs-commit-guard.sh carries): `git commit -m "handle -a"` sets this too, which widens
# the scan unnecessarily but can never MISS a real -a. Widening is the safe direction here.
COMMIT_ALL=0
printf '%s' "$COMMIT_SEG" | grep -aqE '(^|[[:space:]])(-[A-Za-z]*a[A-Za-z]*([[:space:]"'"'"']|$)|--all([[:space:]]|$))' && COMMIT_ALL=1
if [ "$HSCOPE" = repo ] || [ "$COMMIT_ALL" = 1 ]; then
  UNSTAGED="$(git diff -- "$@" 2>/dev/null)"; URC=$?
elif [ "$ADD_WHOLE_TREE" = 1 ] || [ "$ADD_UPDATE" = 1 ]; then
  # `git add .` / `-A` / `-u` stage tracked changes too, so narrow still has to scan them
  UNSTAGED="$(git diff -- "$@" 2>/dev/null)"; URC=$?
elif [ -n "$ADD_PATHS" ]; then
  # narrow: only the tracked paths this command itself names on a `git add`
  # The `.hygiene-allow` carve-out has to survive here too, or the FRIENDLIER scope becomes the one
  # that false-denies an allowlisted file (opus reviewer 2026-08-23, MEDIUM). It cannot be applied by
  # passing the pathspec set built above - that set opens with `:/`, which would drag every tracked
  # file back into a scan whose whole point is not to. So an allowlisted path is skipped outright.
  # Ceiling: an allowlist DIRECTORY entry does not cover the files beneath it here (the repo-wide leg's
  # `:(top,exclude)<dir>` does) - that errs toward DENY, the safe direction, and is disclosed not fixed.
  UNSTAGED=""; URC=0
  for ap in $(printf '%s\n' "$ADD_PATHS"); do
    [ -n "$ap" ] || continue
    [ -n "$ALLOW_LIST" ] && printf '%s\n' "$ALLOW_LIST" | grep -aqxF -- "$ap" && continue
    ap_d="$(git diff -- "$ap" 2>/dev/null)"; ap_rc=$?
    if [ "$ap_rc" -eq 0 ]; then UNSTAGED="$UNSTAGED
$ap_d"; else URC=$ap_rc; note "fail-open: git diff (unstaged, narrow scope, path $ap) failed (rc=$ap_rc)"; fi
  done
else
  UNSTAGED=""; URC=0
fi
if [ "$URC" -eq 0 ]; then DIFF="$DIFF
$UNSTAGED"; else note "fail-open: git diff (unstaged) failed (rc=$URC) - unstaged half not scanned"; fi

# only ADDED lines (leading +, not the `+++` file header) - a pre-existing violation elsewhere in the
# file is not this commit's problem to fix.
ADDED="$(printf '%s\n' "$DIFF" | grep -aE '^\+[^+]')"

# the commit segment's own raw TEXT - catches an inline -m "message with a violation" directly, no
# message-argument parsing needed (the typed bytes are already right there).
ADDED="$ADDED
+$COMMIT_SEG"

# literal UTF-8 byte sequences, not \x{}/-P escapes - portable on any grep, no capability probe
# needed (see header).
EM="$(printf '\342\200\224')"; EN="$(printf '\342\200\223')"; NBSP="$(printf '\302\240')"
ZWSP="$(printf '\342\200\213')"; LSQ="$(printf '\342\200\230')"; RSQ="$(printf '\342\200\231')"
LDQ="$(printf '\342\200\234')"; RDQ="$(printf '\342\200\235')"; ELL="$(printf '\342\200\246')"

HIT_LINE="$(printf '%s' "$ADDED" | grep -aF -e "$EM" -e "$EN" -e "$NBSP" -e "$ZWSP" -e "$LSQ" -e "$RSQ" -e "$LDQ" -e "$RDQ" -e "$ELL" | head -1)"

# untracked-file scan: resolved against the REPO ROOT, not the possibly-a-subdirectory cwd (round-3
# HIGH), C-quoting disabled so a non-ASCII filename doesn't come back as a `"docs/caf\303\251.md"`
# literal `[ -f ]` can't resolve, and bounded to 500 files with a breadcrumb, not a silent cap - one
# batched `grep -l` over the file list rather than a per-file fork (round-3 MEDIUM: perf/timeout risk).
if [ -z "$HIT_LINE" ] && [ "$ADD_PRESENT" = 1 ]; then
  if [ -n "$TOP" ]; then
    UNTRACKED_FILES="$(git -c core.quotePath=false status --porcelain --untracked-files=all 2>/dev/null | sed -n 's/^?? //p')"
    if [ -n "$ALLOW_LIST" ] && [ -n "$UNTRACKED_FILES" ]; then
      UNTRACKED_FILES="$(printf '%s\n' "$UNTRACKED_FILES" | grep -avxF -e "$ALLOW_LIST" || true)"
    fi
    UNTRACKED_COUNT="$(printf '%s\n' "$UNTRACKED_FILES" | grep -ac '.')"
    if [ "$UNTRACKED_COUNT" -gt 500 ]; then
      note "untracked file count ($UNTRACKED_COUNT) exceeds the 500-file scan cap - only the first 500 checked, not a silent truncation"
      UNTRACKED_FILES="$(printf '%s\n' "$UNTRACKED_FILES" | head -n 500)"
    fi
    if [ -n "$UNTRACKED_FILES" ]; then
      UNTRACKED_HIT_FILE="$(printf '%s\n' "$UNTRACKED_FILES" | while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$TOP/$f" ] || continue
        # Binary skip, untracked path only (2026-08-31, live false-deny on a new PNG
        # whose raw bytes contained a scanned glyph sequence by chance). Tracked
        # binaries never hit this class - git renders their diffs as "Binary files
        # differ" - so byte-scanning only NEW binaries was an asymmetry, not policy.
        # NUL in the first 8KB = binary. A TEXT file carrying stray NULs is the one
        # case this loses; the diff-based scan paths never covered that either.
        if [ "$(head -c 8192 "$TOP/$f" | tr -d '\0' | wc -c)" -ne "$(head -c 8192 "$TOP/$f" | wc -c)" ]; then continue; fi
        printf '%s/%s\0' "$TOP" "$f"
      done | xargs -0 grep -aF -l -e "$EM" -e "$EN" -e "$NBSP" -e "$ZWSP" -e "$LSQ" -e "$RSQ" -e "$LDQ" -e "$RDQ" -e "$ELL" -- 2>/dev/null | head -1)"
      if [ -n "$UNTRACKED_HIT_FILE" ]; then
        HIT_LINE="$(grep -aF -m1 -e "$EM" -e "$EN" -e "$NBSP" -e "$ZWSP" -e "$LSQ" -e "$RSQ" -e "$LDQ" -e "$RDQ" -e "$ELL" -- "$UNTRACKED_HIT_FILE" 2>/dev/null)"
      fi
    fi
  fi
fi

[ -n "$HIT_LINE" ] || exit 0

SNIPPET="$(printf '%s' "$HIT_LINE" | cut -c1-160)"
# Only claim the untracked scan when it ran (opus reviewer, 2026-08-16: the fixed string asserted it always).
ADD_CLAUSE=""; [ "$ADD_PRESENT" = 1 ] && ADD_CLAUSE="new untracked files (a git add was present), "
if [ "$HSCOPE" = narrow ] && [ "$COMMIT_ALL" != 1 ] && [ "$ADD_WHOLE_TREE" != 1 ] && [ "$ADD_UPDATE" != 1 ]; then
  SCOPE_CLAUSE="the staged diff, unstaged changes to the paths this command stages (hygiene_scope: narrow), "
else
  SCOPE_CLAUSE="the staged diff, ALL unstaged changes to already-tracked files repo-wide (not just this commit's own changes - the hit may be in an unrelated dirty file, not something this commit introduces; if that scope is wrong for this repo, that is the OPERATOR's call to change, not yours), "
fi
REASON="A commit is about to introduce an output-hygiene violation (em/en dash, curly quote, NBSP, ZWSP, or ellipsis glyph) - the global CLAUDE.md hard rule. Scanned ${SCOPE_CLAUSE}${ADD_CLAUSE}and the commit message text. First offending line: $SNIPPET . Fix it (ASCII hyphen/straight quotes/two periods) and re-run."
note "deny: output-hygiene glyph - $(printf '%s' "$SNIPPET" | cut -c1-80) [sid=$(sid)]"
jq -n --arg r "$REASON" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0

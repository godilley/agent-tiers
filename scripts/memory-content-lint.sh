#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PostToolUse(Write|Edit|MultiEdit) lint: after a memory-file write, flag content problems the
# system prompt does not check for - a commit sha, a derivable count, a PR number, an attributed quote, or
# a line duplicated verbatim from this project's RESUME_SESSION.md. Widened past memory files: ANY `.md`
# write (except under node_modules/vendor/contrib) is also checked for "repo state a git command answers"
# (an unpushed/ahead/behind count, a clean-tree or uncommitted claim, a sha written as current HEAD) - a
# handoff/notes doc goes stale the same way a memory file does, see content_rules_repo_state in
# lib/content-rules.sh. A non-memory .md gets ONLY that one rule; a memory file gets the full set below
# plus that rule.
#
# Why a hook, not a written rule: `cards/MEMORY.md` MEMORY-4 (the memory-write-vs-independent-review
# conflict LAYERS records) - the system prompt tells every tier to write memory directly, no approval
# step; the operator's own rules say anything that propagates into a future session needs an independent
# check first. A write-time approval gate would satisfy the second and break the first (memory writing is
# meant to be a background act, not an interrupt). This runs the check AFTER the write instead: advisory
# only, never a block, never a revert - same shape as authorship-record.sh (a nudge at the arrival event),
# not a second gate mechanism. It is a cheap regex pass the SAME authoring Lead reads, not an independent
# review in the sense the operator's rule means - see MEMORY-4 for the honest scope of what this satisfies.
#
# Scope: a memory-dir path matching */.claude/projects/*/memory/*, OR "$CLAUDE_CONFIG_DIR"/projects/*/memory/*
# when that env var points somewhere not literally named .claude (e.g. a second account's config dir), OR an
# `autoMemoryDirectory` value read from the user, project or local settings files (memory.md:371-379) - runs
# the FULL rule set. Trailing slashes are normalised on both before matching (a bare glob comparison
# otherwise reads ".../mem/" and ".../mem" as different prefixes and silently stops matching). Settings files
# that fail to parse are skipped, never treated as an error (fail-open). NOT READ: a `policy` settings scope
# or a `--settings`-supplied file (memory.md:371 documents both as valid autoMemoryDirectory sources) -
# disclosed gap, not built: neither has a fixed on-disk path this hook can find without the launching CLI's
# own resolution. ANY OTHER `.md` write (outside node_modules/vendor/contrib) runs the repo-state rule
# ONLY - this is the cheap, universal half, no memory-dir resolution needed. A write that is neither a
# memory-dir path nor a `.md` at all is a silent no-op, checked before any read. Patterns come from
# scripts/lib/content-rules.sh - see that file's own header for its consumers (this hook sources it; the
# doc-style skill points doc audits at it).
#
# Advisory wording for a bare hex token: content-rules.sh's sha rule cannot always tell a commit sha from
# a session/transcript/agent id by shape alone (a full UUID or an `agent-<hex>` token is excluded outright,
# but a bare 7-40 hex run with no such punctuation is genuinely ambiguous) - the finding text below never
# instructs a Lead to delete the token, only to remove it IF it turns out to be a commit sha.
#
# Location gap, CLOSED: this hook's scope gate and resume-inject.sh's SessionStart memory-size advisory
# used to resolve the memory directory two different ways - this hook honoured `autoMemoryDirectory`,
# resume-inject.sh derived it from the git repo root only - so a relocated memory dir could be linted
# here but never sized there, or the reverse. Both now call lib/guard-mempath.sh, which is the superset.
# Still true of both sides: neither reads `CLAUDE_CODE_PROJECT_DIR_NAME` (memory.md:369), and the two
# consumers pass the resolver different project dirs, so a narrower disagreement survives where the host
# does not export `CLAUDE_PROJECT_DIR` - see that library's header for the exact residue.
#
# Wiring: options.tsv row, group memory: the plugin route turns it on with that group in the plugin options; the
# flat route wires it with `install-flat.sh --with-memory-content-lint`, which writes the machine's
# user-level settings.json (so "installed" here means machine-wide, not scoped to one project - see
# `cards/MEMORY.md` for the exact wording this replaced). Kill switch checked first:
# .state/off/memory-content-lint. Fail-open on every tooling gap (no jq, unreadable file, missing library,
# unreadable settings file) with a breadcrumb in .state/guards.log. Never blocks, never exits non-zero on
# a finding.
# Self-check: memory-content-lint.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s memory-content-lint fail-open: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

# Timeout tracing, scoped to the expensive window only (the content_rules_* scan further below) - the
# scope gate, kill switch and every fail-open exit before it are cheap and never traced, which is what
# keeps this off every Write/Edit outside the memory dir. A guard killed at its hook budget cannot
# write its own breadcrumb, so the window brackets itself: `start` on entry, `end done=1` on exit. A
# kill inside the window leaves `start` with either `done=0` (SIGTERM: the TERM trap below makes
# dash run the EXIT trap too, which it skips on an untrapped TERM) or no `end` at all (SIGKILL runs
# no trap).
GUARD_TRACE_OPEN=0
trap 'if [ "$GUARD_TRACE_OPEN" = 1 ]; then note "end [pid=$$] done=0"; fi' EXIT
trap 'exit 143' TERM

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_DIR="${CLAUDE_DIR%/}"
[ -f "$CLAUDE_DIR/agent-tiers/.state/off/memory-content-lint" ] && exit 0
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "jq missing - cannot parse payload"; exit 0; }

FPATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -n "$FPATH" ] || exit 0

# Memory-dir resolution and the scope gate both come from lib/guard-mempath.sh - the ONE definition,
# shared with resume-inject.sh, which used to derive the directory a different way and disagree with
# this file whenever `autoMemoryDirectory` was set (the gap the header above disclosed). A missing
# library degrades to the standard-layout check alone rather than failing the hook: that is the case
# this lint was built for, and losing the relocated-dir branch is a narrower scope, never a wider one.
# STATE: any .md outside third-party trees gets the repo-state rule. MEM: a memory-dir path gets the
# full set. Neither = silent exit before any read (the cheap-gate invariant).
STATE=0
case "$FPATH" in */node_modules/*|*/vendor/*|*/contrib/*) ;; *.md) STATE=1 ;; esac
MEM=0
SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -n "$SELFDIR" ] && [ -f "$SELFDIR/lib/guard-mempath.sh" ]; then
  . "$SELFDIR/lib/guard-mempath.sh"
  AUTO_MEM="$(guard_mem_auto_dir "$CLAUDE_DIR")"
  guard_mem_in_scope "$CLAUDE_DIR" "$FPATH" "$AUTO_MEM" && MEM=1
else
  # Degraded path: standard layout only. The scope test comes FIRST and the breadcrumb second,
  # deliberately - this hook runs on every Write/Edit on the machine, and a `note` ahead of the gate
  # would put a mkdir + date + log append on every write to every path, which is exactly what the
  # cheap-gate invariant at the top of this file exists to prevent.
  case "$FPATH" in */.claude/projects/*/memory/*)
    MEM=1; note "fail-open: lib/guard-mempath.sh missing - standard layout only, relocated dirs unlinted" ;;
  esac
fi
[ "$MEM" = 1 ] || [ "$STATE" = 1 ] || exit 0
[ -f "$FPATH" ] || exit 0   # the write may have failed, or this is a delete-shaped Edit; nothing to lint
[ -r "$FPATH" ] || { note "unreadable: $FPATH"; exit 0; }

LIB="$SELFDIR/lib/content-rules.sh"   # SELFDIR is resolved above, at the memory-path library source
[ -n "$SELFDIR" ] && [ -f "$LIB" ] || { note "lib/content-rules.sh missing - cannot lint"; exit 0; }
. "$LIB"
{ command -v content_rules_shas && command -v content_rules_repo_state; } >/dev/null 2>&1 || { note "content-rules.sh sourced but expected functions undefined (stale library?)"; exit 0; }

# Project root: memory files live at <config>/projects/<slug>/memory/<name>.md; the project's own
# RESUME_SESSION.md is not derivable from that path (the slug is a lossy dash-encoding of the real repo
# path, see resume-inject.sh's own comment on the same slugging), so duplication is checked ONLY when
# CLAUDE_PROJECT_DIR is set (the hook's own env, not derived from FPATH) - fail-open (no dup check) when
# absent, never a guess at the wrong project.
RESUME=""
[ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/RESUME_SESSION.md" ] && RESUME="$CLAUDE_PROJECT_DIR/RESUME_SESSION.md"

FINDINGS=""
add_finding() { [ -n "$1" ] && FINDINGS="${FINDINGS:+$FINDINGS
}$1"; }

# Traced for memory files only: the repo-state scan alone is one grep pass, and tracing it would put two
# guards.log lines on every .md write on the machine.
if [ "$MEM" = 1 ]; then GUARD_TRACE_OPEN=1; note "start [pid=$$]"; fi
n=0
if [ "$MEM" = 1 ]; then
  sha_hits="$(content_rules_shas "$FPATH" 2>/dev/null)"
  if [ -n "$sha_hits" ]; then n=$((n + 1)); add_finding "a token that looks like a commit sha or an id (MEMORY-2 - remove it if it is a commit sha, keep it if it is a session/transcript/agent id - $(printf '%s' "$sha_hits" | head -1 | cut -c1-100))"; fi
  count_hits="$(content_rules_derivable_counts "$FPATH" 2>/dev/null)"
  if [ -n "$count_hits" ]; then n=$((n + 1)); add_finding "a derivable count (MEMORY-2 - $(printf '%s' "$count_hits" | head -1 | cut -c1-100))"; fi
  pr_hits="$(content_rules_pr_number "$FPATH" 2>/dev/null)"
  if [ -n "$pr_hits" ]; then n=$((n + 1)); add_finding "a PR number (MEMORY-2 - $(printf '%s' "$pr_hits" | head -1 | cut -c1-100))"; fi
  attr_hits="$(content_rules_attribution "$FPATH" 2>/dev/null)"
  if [ -n "$attr_hits" ]; then n=$((n + 1)); add_finding "an attributed quote (MEMORY-3: never record who said it - $(printf '%s' "$attr_hits" | head -1 | cut -c1-100))"; fi
  if [ -n "$RESUME" ]; then
    dup_hits="$(content_rules_resume_duplication "$FPATH" "$RESUME" 2>/dev/null)"
    if [ -n "$dup_hits" ]; then n=$((n + 1)); add_finding "a line duplicated from RESUME_SESSION.md (one canonical home per fact - $(printf '%s' "$dup_hits" | head -1 | cut -c1-100))"; fi
  fi
fi
if [ "$STATE" = 1 ]; then
  state_hits="$(content_rules_repo_state "$FPATH" 2>/dev/null)"
  if [ -n "$state_hits" ]; then n=$((n + 1)); add_finding "repo state a git command answers (goes stale; record the lookup command, not its output) - $(printf '%s\n' "$state_hits" | wc -l | tr -d ' ') hit(s), first: $(printf '%s\n' "$state_hits" | head -3 | cut -c1-100 | awk 'NR>1{printf " | "}{printf "%s", $0}')"; fi
fi
if [ "$MEM" = 1 ]; then GUARD_TRACE_OPEN=0; note "end [pid=$$] done=1"; fi   # closes off the scan above

[ "$n" -gt 0 ] || exit 0

if [ "$MEM" = 1 ]; then
  CTX="agent-tiers cards/MEMORY.md: $(basename "$FPATH") was just written with $n content issue(s):
${FINDINGS}
Advisory only, nothing blocked. Fix in place before the next session reads it as fact - see cards/MEMORY.md MEMORY-2/MEMORY-3."
else
  CTX="agent-tiers: $(basename "$FPATH") was just written with $n content issue(s):
${FINDINGS}
Advisory only, nothing blocked. Fix in place when touching the file for its own reason; never a bulk sweep."
fi
jq -n --arg c "$CTX" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}' 2>/dev/null || true
exit 0

#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: `sed -i`/`tee` writing a TRACKED file is legitimate mechanical
# bulk work (SC-5.2a), but the rule's disclosure half - "name the reason in the turn that does it" -
# has no enforcement, only prose. A corpus-wide evidence sweep (2026-09-05) found 25 of 45
# rubric-"compliant" sessions had at least one undisclosed off-instrument write to a real product-repo
# file, scored compliant only because an Edit/Write call ALSO happened elsewhere in the same session -
# the disclosure clause was never actually checked. This closes the loop at the one point that's
# observable: the write itself.
#
# `deny` (2026-09-14, guard-ask-deny rule): this is a FORM problem - use Edit/Write, or disclose the
# Bash write - which the agent can always fix itself, so it is never a human-only decision. A bulk
# mechanical rename genuinely is sometimes the right call; that is exactly what the escape hatch below
# is for, not a reason to ask a human first.
#
# Escape hatch: a `[bash-write:<reason>]` marker anywhere in the command text both ALLOWS and LOGS the
# reason to guards.log (auditable, never silent) - same idiom as maint2-arrival-guard's
# `[no-doctrine-bump]`. Deliberately not an env var: one set and forgotten becomes the default.
# Placement (2026-09-14, adversarial review, MEDIUM): must be a trailing shell COMMENT
# (`# [bash-write:...]`), never a bare trailing word - on `sed` that reads as an extra file argument to
# edit, and on `tee` it creates a stray file literally named `[bash-write:...]`. `guard_marker_text`
# reads raw command text, so a `#`-comment marker is found the same as a bare one; only the remedy text
# and the fixtures needed to say so.
#
# Scope, DISCLOSED not hidden (opus-reviewed 2026-09-05, four real limits, not pretended away):
#  - `sed -i`/`--in-place` and `tee` only, matching the two patterns the evidence actually found -
#    not every possible off-instrument write (a bare `>` redirect is NOT scanned: that pattern is
#    indistinguishable from ubiquitous benign use - piping to a log file, `/dev/null` - without a real
#    shell parser, and scanning it would make this guard fire on nearly every session).
#  - `guard_split_segments` splits on shell metacharacters with NO quote-awareness (same ceiling every
#    guard in this kit accepts), so a `;` or `&` INSIDE a quoted sed script (`sed -i 's/a/b/;s/c/d/'
#    file`) is split as if it ended the command - the segment carrying `sed -i` never reaches the
#    target file and this guard misses the hit entirely. Multi-expression sed one-liners are common;
#    this is a real, not theoretical, miss. Fails toward silence (safe direction), not a false ask.
#  - No `cd`/`-C` tracking (unlike hygiene-commit-guard.sh/vcs-commit-guard.sh's `guard_resolve_cwd`):
#    this guard reads the payload's raw `.cwd` only. A `cd other-repo && sed -i ... file` scans the
#    WRONG repo and can miss a real hit - a known gap, not a claimed capability. Upgrade path: fold in
#    `guard_resolve_cwd` if this ever needs the same rigor as the commit-time guards.
#  - Only the LAST non-flag, non-redirect argument in a hit segment is checked against `git ls-files`
#    (a `sed -i 's/x/y/' a.txt b.txt` only evaluates `b.txt`) - disclosed, not silently wrong: a
#    multi-file sweep with at least one tracked target still surfaces on ANY session that also hits a
#    single-file case, and widening this is only worth it if real misses are observed.
#  - A heredoc body is never scanned (`guard_has_heredoc` stands the whole command down) - same
#    documented ceiling every guard-cmdpos.sh consumer inherits, not unique to this guard.
#
# Fail-open on any tooling gap (no jq, no git, cwd missing/unreadable, not a git repo). Self-check:
# sc52a-write-disclosure-guard.selfcheck.sh.
set -u
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s sc52a-write-disclosure-guard %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
sid() { printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true; }
[ -n "$CMD" ] || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ]; then
  . "$SELFDIR/guard-cmdpos.sh"
else
  note "fail-open: guard-cmdpos.sh missing - cannot split segments"; exit 0
fi
command -v guard_has_heredoc >/dev/null 2>&1 && command -v guard_split_segments >/dev/null 2>&1 && command -v guard_segs_at_cmdpos >/dev/null 2>&1 && command -v guard_at_command_position >/dev/null 2>&1 && command -v guard_caller_agent >/dev/null 2>&1 && command -v guard_marker_text >/dev/null 2>&1 || { note "fail-open: guard-cmdpos.sh sourced but expected helpers undefined (stale library?)"; exit 0; }

# AGENT_TYPE read BEFORE the marker check (2026-09-14, adversarial review, LOW - corrected same day):
# a subagent has no standing to judge "this exception is warranted" any more than it can judge SC-5.2a
# triviality elsewhere in this kit, so its own marker must not clear the gate. Read this early so the
# marker branch below can act on it, instead of allowing unconditionally first and only telling a
# subagent afterward (in the deny text) that it "cannot self-disclose" - a claim the old code never
# enforced.
AGENT_TYPE="$(guard_caller_agent "$INPUT")"

# The escape hatch is checked on the WHOLE command text, not per-segment - it is a blanket author
# declaration for this call, same as `[no-doctrine-bump]`. Lead only: a subagent's marker is logged and
# then ignored, falling through to the normal scan (which still denies if this segment is a real hit).
case "$CMD" in
  *'[bash-write:'*)
    REASON_TXT="$(guard_marker_text "$CMD" bash-write)"
    if [ -z "$AGENT_TYPE" ]; then
      note "skip: [bash-write:$REASON_TXT] marker - author declares the off-instrument write [sid=$(sid)]"
      exit 0
    fi
    note "ignored: [bash-write:$REASON_TXT] marker from a subagent caller - a subagent cannot self-disclose this exception, continuing to scan [sid=$(sid) agent=$AGENT_TYPE]"
    ;;
esac

guard_has_heredoc "$CMD" && exit 0
SEGMENTS="$(guard_split_segments "$CMD")"

# Pre-filter to sed/tee-at-command-position segments FIRST (one grep call, guard_segs_at_cmdpos) -
# cheap enough to pay on every Bash call. git only gets touched once that pre-filter is non-empty, so
# an unrelated command (`ls`, `cat`, ...) never pays a `git rev-parse` at all.
HIT_SEGS="$(guard_segs_at_cmdpos "$SEGMENTS" '(sed|tee)([[:space:]]|$)')"
[ -n "$HIT_SEGS" ] || exit 0

PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$PAYLOAD_CWD" ] && cd "$PAYLOAD_CWD" 2>/dev/null
command -v git >/dev/null 2>&1 || { note "fail-open: git missing"; exit 0; }
TOP="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$TOP" ] || exit 0   # not a git repo: no-op, nothing to protect

# Last non-flag, non-redirect token in a segment - the same "last-wins scalar arg" heuristic
# guard-cmdpos.sh's own functions use elsewhere, applied to `sed -i ... TARGET` / `tee [-a] TARGET`.
# `set -f` around the split (guard_resolve_cwd's own `-C`-loop does the same, opus-reviewer finding
# that motivated it there): unquoted word-splitting on a segment is unavoidable here - it's how a
# shell would tokenize it too - but pathname expansion is not, and would either silently swap in an
# alphabetically-different match or, on no match, leave a literal glob that `git ls-files
# --error-unmatch` can accept as a PATHSPEC, naming `*.md` in the ask instead of a real file.
last_arg() {
  seg="$1"; last=""
  set -f
  for tok in $seg; do
    case "$tok" in
      # `#` starts a shell comment when it is the first character of a WORD (real POSIX rule) - stop
      # scanning entirely once one is seen, or the escape-hatch marker's own trailing comment (2026-09-14,
      # adversarial review, MEDIUM: the marker must be a `# [tag:...]` comment, never a bare word) would
      # get picked up as the "target" by this same last-token heuristic, hiding the real hit. Same
      # disclosed no-quote-awareness ceiling every guard-cmdpos.sh consumer already carries (a `#` inside
      # a quoted string, e.g. `sed -i 's/#foo/bar/'`, is misread the same way real POSIX word-splitting
      # would misread it without quote tracking - not a NEW gap this fix introduces).
      '#'*) break ;;
      -*) ;;                                   # a flag (-i, -a, --in-place, ...)
      '>'*|'<'*|[0-9]'>'*|[0-9]'<'*) ;;         # a redirect target/operator (>, >>, 2>, </dev/null, ...)
      *) last="$tok" ;;
    esac
  done
  set +f
  printf '%s' "$last"
}

# The while loop runs in a subshell (piped input), so a plain variable set inside it would be lost on
# exit - captured via command substitution around the WHOLE pipeline instead (same idiom
# guard_resolve_cwd uses for the identical subshell-scope problem), never a predictable tmp filename
# (no stale-file/PID-reuse window to reason about).
HIT_FILE="$(printf '%s\n' "$HIT_SEGS" | while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  is_hit=0
  if guard_at_command_position "$seg" 'sed\b'; then
    case "$seg" in (*' -i'*|*' --in-place'*|*'-i.'*) is_hit=1 ;; esac
  elif guard_at_command_position "$seg" 'tee\b'; then
    is_hit=1
  fi
  [ "$is_hit" = 1 ] || continue
  tgt="$(last_arg "$seg")"
  case "$tgt" in
    (\"*\") tgt="${tgt#\"}"; tgt="${tgt%\"}" ;;
    (\'*\') tgt="${tgt#\'}"; tgt="${tgt%\'}" ;;
  esac
  tgt="${tgt#./}"
  [ -n "$tgt" ] || continue
  if git ls-files --error-unmatch -- "$tgt" >/dev/null 2>&1; then
    printf '%s\n' "$tgt"
    break
  fi
done)"
[ -n "$HIT_FILE" ] || exit 0

# 2026-09-14 (guard-ask-deny rule; CORRECTED same day, adversarial review, LOW): this is a FORM
# problem, not a human decision - the fix (use Edit/Write, or disclose the Bash write with a marker) is
# mechanical, so it always denies now, Lead included. `guard_ask_prefix`'s framing text was dropped
# here (unlike the other guards in this wave): it describes converting a REAL ask into a deny for a
# caller who cannot answer it ("a question no human is present to answer"), which is false for an
# unconditional deny that fires on EVERYONE including an attended Lead - that text would have lied to
# an unattended session about why it got denied. The subagent-specific closing sentence stays and is
# now actually enforced (the marker branch above ignores a subagent's own [bash-write:], it does not
# just say so after the fact).
DEC=deny
REASON="This command writes to '$HIT_FILE' (a tracked file) via sed -i/tee, off the Edit/Write instrumented path (SC-5.2a). Use Edit/Write instead; if a Bash write is genuinely the right tool here, append a trailing shell comment naming why and what was written - \`# [bash-write:<why + what was written>]\` - and retry. Never a bare trailing word: on a sed command it becomes an extra file argument to edit, and on a tee command it creates a stray file literally named \`[bash-write:...]\`."
if [ -n "$AGENT_TYPE" ]; then
  REASON="$REASON You cannot judge whether this exception is warranted - stop and report this back to the Lead."
fi
note "$DEC: off-instrument write to $HIT_FILE via sed-i/tee, no [bash-write:] marker [sid=$(sid) agent=${AGENT_TYPE:-lead}]"
jq -n --arg r "$REASON" --arg d "$DEC" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
exit 0

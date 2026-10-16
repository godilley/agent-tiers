#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Task|Agent) guard, five rules sharing one arrival event and payload parse
# (A to E; RULE E, the host-blocked report name, is documented at its own block below):
#
# RULE A - an Explore spawn must pass an explicit model. `Explore` otherwise inherits the Lead's own
# model, so a 2+ fan-out under an opus Lead silently becomes an opus fan-out costing many times what
# was intended. Deny when subagent_type is exactly "Explore" (case-sensitive - the tool's own type
# string) and tool_input.model is absent or empty. Field name confirmed live 2026-09-17: a real
# spawn's tool_input carries `model` alongside `description`, `prompt` and `subagent_type`, and the
# key is simply ABSENT (not null, not empty string) when no model is passed - `// empty` below already
# treats both shapes the same way, so no code depends on which one a given host produces.
#
# RULE B - a planted control must not be announced in the brief that carries it. A review brief
# sometimes carries one deliberate pre-verified defect, unmarked, so the reviewer's catch rate can be
# measured; announcing it in the same brief destroys the measurement. Deny when BOTH hold: subagent_type
# is one of reviewer/advisor/boss (case-insensitive) AND the prompt carries an announcement-shaped
# label.
#
# The announcement shape is MEASURED, not guessed: a sweep of 359 real spawn prompts found exactly 6
# leaks, all one of two surface forms - an ALL-CAPS label at the START of a line, either the literal
# "PLANTED CONTROL", "CALIBRATION CHECK", "LIVENESS CONTROL" or "RECALL SEED" (the last two were
# added unmeasured, as the SC-4.2 / SC-4.2c names from doctrine-v25), optionally preceded by a REPEATED run of whitespace, a
# markdown bullet (-, *, +), heading hashes, or bold markers (**), in any combination (a bulleted AND
# bolded label - `- **PLANTED CONTROL**` - is a single optional-group hit away from being missed if the
# prefix can only carry one marker). This is deliberately narrower than a word-level match: the
# legitimate population (a worker brief that asks FOR a planted-defect test harness, the ordinary-
# English "negative control" of a test plan, a UI control) is LARGER than the leak population, and a
# bare regex on "planted"/"control"/"calibration" would wreck all of them. Anchoring on line-start plus
# ALL-CAPS is what a real leak looks like and ordinary prose does not.
#
# Escape marker for a deliberate disclosure: the prompt contains "[control-disclosed:" anywhere. Then
# the guard allows and logs that the marker was used - the same allow-and-log shape memory-write-gate.sh
# uses for its own unattended/subagent arms, rather than a silent pass.
#
# RULE D - a sublead spawn needs a stated reason, and never nests. A sublead is an opus coordinator
# that spawns its own children, so running several in parallel is an opus fan-out: more total tokens
# for less wall time and a smaller Lead context, a trade made once in a plan row via
# "[sublead-approved:<plan row or why>]" in the prompt, which allows and logs. Without the tag the Lead
# gets an ask (an unattended Lead gets it as a deny). Any subagent caller is denied outright, tag or
# not, and a sublead caller may never spawn general-purpose - both close the one-level depth cap.
# transcript-miner is gated identically to sublead: it is also an opus coordinator with its own
# Explore/worker children, so it shares the same tag, the same Lead ask, the same D1 deny from any
# subagent caller, and D2 also denies a transcript-miner caller spawning general-purpose.
#
# All rules fail open on any tooling gap (no jq, no payload fields), with a breadcrumb - a silent
# fail-open is exactly the failure this whole guard class exists to close.
#
# Kill switch: .state/off/task-spawn-guard (enforced by kit-gate.sh), resolved from KIT_ROOT (the
# script's own location), never from CLAUDE_CONFIG_DIR - the kill switch lives in the kit's own .state
# and is shared across every Claude profile pointed at this kit; only the flattened view follows
# CLAUDE_CONFIG_DIR.
# Self-check: task-spawn-guard.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s task-spawn-guard %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
case "$TOOL" in Task|Agent) ;; *) exit 0 ;; esac

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in *[!A-Za-z0-9._-]* | '.' | '..') SESSION_ID="" ;; esac

SUBTYPE="$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"
PROMPT="$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null || true)"

deny() {  # $1 = reason, $2 = breadcrumb (optional, falls back to $1)
  note "deny: ${2:-$1} [sid=$SESSION_ID]"
  jq -n --arg r "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# --- RULE A: Explore must carry an explicit model ---------------------------------------------------
if [ "$SUBTYPE" = "Explore" ]; then
  MODEL="$(printf '%s' "$INPUT" | jq -r '.tool_input.model // empty' 2>/dev/null || true)"
  if [ -z "$MODEL" ]; then
    deny "agent-tiers: an Explore spawn inherits the Lead's own model unless one is passed explicitly, so a fan-out under an opus Lead silently becomes an opus fan-out. Add model: \"sonnet\" to this spawn's tool_input (or a stronger model only if the reasoning genuinely needs it), then retry." \
      "Explore spawn missing an explicit model"
  fi
fi

# --- RULE B: no announced planted control in a reviewer/advisor/boss brief ---------------------------
case "$(printf '%s' "$SUBTYPE" | tr '[:upper:]' '[:lower:]')" in
  reviewer|advisor|boss)
    if [ -n "$PROMPT" ]; then
      if printf '%s' "$PROMPT" | grep -q '\[control-disclosed:'; then
        note "allow: planted-control disclosure marker present in $SUBTYPE brief [sid=$SESSION_ID]"
      elif printf '%s' "$PROMPT" | grep -qE '^[[:space:]]*([-*+][[:space:]]*|#+[[:space:]]*|\*\*)*(PLANTED CONTROL|CALIBRATION CHECK|LIVENESS CONTROL|RECALL SEED)'; then
        deny "agent-tiers: this $SUBTYPE brief announces its own planted control (a PLANTED CONTROL / CALIBRATION CHECK / LIVENESS CONTROL / RECALL SEED label at the start of a line) - the control only works unmarked, so a reviewer's catch rate cannot be measured once it names the defect. State the planted defect in your own notes rather than in the brief. If the disclosure is deliberate, carry [control-disclosed:<why>] anywhere in the prompt and retry." \
          "$SUBTYPE brief announces its own planted control"
      fi
    fi
    ;;
esac

# --- RULE C: an opus/fable worker needs a stated reason -------------------------------------------------
# The worker definition is sonnet, and the doctrine's per-spawn opus override is for clever code only.
# A --breakdown of 2026-09-26..28 measured it applied far wider: 29 of 56 worker spawns passed model
# opus, 14 of 15 sampled descriptions were mechanical (apply fixes, widen a column, migrate data), and
# opus workers alone were about a quarter of the estimated weekly quota spend. Deny unless the prompt
# carries "[opus-worker:<why>]", which then allows and logs, the same escape shape as RULE B.
case "$(printf '%s' "$SUBTYPE" | tr '[:upper:]' '[:lower:]')" in
  worker)
    WMODEL="$(printf '%s' "$INPUT" | jq -r '.tool_input.model // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
    case "$WMODEL" in
      *opus*|*fable*)
        if printf '%s' "$PROMPT" | grep -q '\[opus-worker:'; then
          note "allow: $WMODEL worker with a stated reason [sid=$SESSION_ID]"
        else
          deny "agent-tiers: a worker spawn with model $WMODEL. Workers are sonnet by definition, and the opus override is only for genuinely clever code; routine build, fix, migrate or apply-review work costs roughly twice the quota on opus for no gain. Drop the model override (or pass sonnet), or, if this really is clever code, put [opus-worker:<why>] anywhere in the prompt and retry. If the brief needs judgement calls rather than clever code, no model fixes it: a worker hands every judgement call back to the Lead. Settle those calls first (yourself, or an Advisor on opus, announce-only), then re-brief this worker fully specified at sonnet." \
            "worker spawn with model $WMODEL and no stated reason"
        fi
        ;;
    esac
    ;;
esac

# --- RULE E: a brief must not name a write target the host refuses to a sub-agent ----------------------
# The host refuses a SUB-AGENT's Write when the file's basename matches
# /^(REPORT|SUMMARY|FINDINGS|ANALYSIS).*\.md$/i ("Subagents should return findings as text, not write
# report files"; read from the Claude Code bundle 2026-10-11). Briefs keep naming exactly that
# (findings.md, FINDINGS.md, SUMMARY.md, report-*.md): a 2026-10-11 sweep of real sub-agent transcripts
# found refused Writes across several projects, each a wasted turn plus a file the Lead had to save by
# hand. Read vs write is told apart by the filesystem, not the brief's wording (a write-verb heuristic
# misread a large share of real cases): a file the agent is to READ exists at spawn time, one it is to
# WRITE usually does not. So deny only when a named path with a blocked basename does not exist yet.
# Skipped, never denied: Explore and Plan (no Write tool); a token that cannot be resolved to one path
# (a glob, a $VAR, a URL, ~user/, or a relative path with no cwd in the payload). Scans the first 64 KB.
# Disclosed gaps: a re-run told to overwrite an existing findings.md passes here and is still refused by
# the host; a path containing a space is cut at the space; a brief that quotes the escape marker while
# describing this rule escapes itself. Escape: [report-name-ok:<why>] anywhere in the prompt, logged.
case "$SUBTYPE" in Explore|Plan) E_SKIP=1 ;; *) E_SKIP=0 ;; esac
if [ "$E_SKIP" = 1 ]; then
  :
elif printf '%s' "$PROMPT" | grep -q '\[report-name-ok:'; then
  note "allow: report-name-ok marker present in $SUBTYPE brief [sid=$SESSION_ID]"
else
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
  E_BAD=""
  if E_LIST="$(printf '%s' "$PROMPT" | head -c 65536 | jq -Rrs '[scan("(?i)(?<![^\\s`\"'"'"'(<>=:])((?:[^\\s`\"'"'"'()<>=:]*/)?(?:REPORT|SUMMARY|FINDINGS|ANALYSIS)[^\\s/`\"'"'"'()<>]*\\.md)(?![A-Za-z0-9_/~-]|\\.[A-Za-z0-9])")] | .[][0]' 2>/dev/null)"; then
    E_LIST="$(printf '%s\n' "$E_LIST" | head -20)"
  else
    note "fail-open: RULE E scan failed (jq without regex support?) [sid=$SESSION_ID]"; E_LIST=""
  fi
  while IFS= read -r e_p; do
    [ -n "$e_p" ] || continue
    case "$e_p" in
      *[*?\[\]{}\$]* | //* | "~"[!/]*) note "skip: RULE E cannot resolve '$e_p' [sid=$SESSION_ID]"; continue ;;
      "~/"*) [ -n "${HOME:-}" ] || continue; e_abs="$HOME/${e_p#\~/}" ;;
      /*) e_abs="$e_p" ;;
      *) [ -n "$CWD" ] || { note "skip: RULE E has no cwd for '$e_p' [sid=$SESSION_ID]"; continue; }
         e_abs="$CWD/$e_p" ;;
    esac
    [ -e "$e_abs" ] || E_BAD="${E_BAD:+$E_BAD, }$e_p"
  done <<E_EOF
$E_LIST
E_EOF
  if [ -n "$E_BAD" ]; then
    deny "agent-tiers: this brief names a file to create whose name the host refuses to a sub-agent: $E_BAD. Claude Code blocks a sub-agent's Write when the file name starts with REPORT, SUMMARY, FINDINGS or ANALYSIS and ends in .md, so the agent burns a turn and the file never lands. Rename it (for example review-findings.md, audit-findings.md, or findings.tsv), or ask for the content in the final message and save it yourself, then retry. If the brief only mentions that name (something to read that is created before the agent reaches it, or 'do not write FINDINGS.md'), put [report-name-ok:<why>] in the prompt." \
      "brief names host-blocked write target(s): $E_BAD"
  fi
fi

# --- RULE D: a sublead spawn needs a stated reason, and never nests ---------------------------------
# A sublead is an opus coordinator that spawns its own children, so N parallel subleads is an opus
# fan-out (SC-3.1 rung 3): more total tokens, bought for less wall time and a smaller Lead context.
# The tag is a rate-limiter and a record, not proof of approval: it names the plan row or reason so
# guards.log can be audited. The prompt carries
# "[sublead-approved:<plan row or why>]", which allows and logs (same escape shape as RULE B/C).
# Without it the Lead gets an ask, and an unattended Lead gets it as a deny (guard_ask_decision).
# D1: any SUBAGENT caller is denied outright, tag or not. The depth cap is one level under a
# coordinator, and a sublead or transcript-miner spawned by any subagent is already past it. D2: a
# sublead or transcript-miner caller may not spawn general-purpose, the one stock type that carries
# Agent and could nest again (matched on the caller type lowercased, since guard_caller_agent does
# not lowercase it). Caller identity comes from guard-cmdpos.sh, never a hand-rolled .agent_type
# read. A missing or stale library fails open with a breadcrumb, the direction every rule here takes.
SUB_LC="$(printf '%s' "$SUBTYPE" | tr '[:upper:]' '[:lower:]')"
case "$SUB_LC" in
  sublead|transcript-miner|general-purpose)
    SELFDIR="$(CDPATH= cd "$(dirname "$0")" >/dev/null 2>&1 && pwd || true)"
    if [ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ] && . "$SELFDIR/guard-cmdpos.sh" \
       && command -v guard_caller_agent >/dev/null 2>&1 && command -v guard_ask_decision >/dev/null 2>&1 \
       && command -v guard_ask_prefix >/dev/null 2>&1; then
      AGT="$(guard_caller_agent "$INPUT")"
      AGT_LC="$(printf '%s' "$AGT" | tr '[:upper:]' '[:lower:]')"
      if [ "$SUB_LC" = general-purpose ]; then
        case "$AGT_LC" in
          sublead|transcript-miner)
            deny "agent-tiers: a $AGT does not spawn general-purpose. That type carries the Agent tool, so its children could spawn again, past the depth rule (a coordinator's children never spawn). Use only the child types your definition allows, such as worker (mechanical) or Explore with model sonnet (reads), each briefed not to spawn." \
              "$AGT spawned general-purpose (depth cap)"
            ;;
        esac
      elif [ -n "$AGT" ]; then
        deny "agent-tiers: only the top Lead spawns a $SUB_LC. This call comes from a sub-agent ($AGT), so a $SUB_LC here would put its children past the depth rule (a coordinator's children never spawn). Do the work with the child types your definition allows instead, or return the need upward as a FORK block." \
          "$SUB_LC spawn from subagent $AGT (depth cap)"
      elif printf '%s' "$PROMPT" | grep -q '\[sublead-approved:'; then
        note "allow: $SUB_LC spawn, tag: $(guard_marker_text "$PROMPT" sublead-approved) [sid=$SESSION_ID]"
      else
        DEC="$(guard_ask_decision "$SESSION_ID" "")"
        REASON="$(guard_ask_prefix "$SESSION_ID" "")agent-tiers: $SUB_LC spawn with no [sublead-approved:<plan row or why>] tag. Trade: an opus coordinator plus its own children costs more total tokens than running this slice from here, for less wall time and a smaller Lead context. Allow this one, or, only if a plan row or wave lease already approved it, put the tag naming that row in the prompt and retry; otherwise stop and report the need upward."
        note "$DEC: $SUB_LC spawn with no [sublead-approved:] tag [sid=$SESSION_ID]"
        jq -n --arg r "$REASON" --arg d "$DEC" \
          '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
        exit 0
      fi
    else
      note "fail-open: guard-cmdpos.sh missing or stale - RULE D cannot classify the caller [sid=$SESSION_ID]"
    fi
    ;;
esac
# selfcheck cases: Lead untagged -> ask; Lead tagged -> allow; unattended Lead untagged -> deny with
# UNATTENDED prefix; agent_type=sublead spawning sublead (tagged) -> deny; agent_type=worker spawning
# sublead -> deny; agent_type=sublead spawning general-purpose -> deny; Lead spawning general-purpose
# -> allow; agent_type=main treated as Lead -> ask; guard-cmdpos.sh absent -> allow, fail-open logged;
# Lead tagged with an empty [sublead-approved:] reason -> allow, tag: still logged. Lead untagged
# transcript-miner spawn -> ask; Lead tagged transcript-miner spawn -> allow, logged; agent_type=sublead
# spawning transcript-miner (tagged) -> deny; agent_type=worker spawning transcript-miner (tagged) ->
# deny; agent_type=transcript-miner spawning general-purpose -> deny; agent_type=transcript-miner
# spawning transcript-miner (tagged) -> deny; unattended Lead untagged transcript-miner spawn -> deny with
# UNATTENDED prefix; agent_type=Transcript-Miner (mixed case) spawning general-purpose -> deny.
# Sandbox AGENT_TIERS_STATE_DIR + GUARDS_LOG.

exit 0

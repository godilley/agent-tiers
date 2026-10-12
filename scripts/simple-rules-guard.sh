#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash|AskUserQuestion|SendMessage) guard: six small, literal, unrelated rules
# sharing ONE hook row rather than six. Each extra row costs an sh + jq + library source on every single Bash call
# in every project, so six one-off rules are dispatched here instead of shipped as six separate
# scripts. Dispatch is on tool_name first: the three Bash rules only ever look at
# .tool_input.command, the AskUserQuestion rule only at .tool_input.questions, the SendMessage rules
# look at .tool_input.to and .tool_input.message (Rule G also reads the peer's own session record -
# a host-internal file per live session, observed on host version 2.1.280, not a documented interface).
#
# RULE A - `codex resume --last` and `codex exec resume --last` are both banned. Resuming "the last"
# Codex session is ambiguous once more than one session exists, and it has silently attached to the
# wrong thread - the top-level form and the `exec` form carry the same ambiguity, so both are covered
# by one pattern. Fix: resume by explicit session id.
#
# RULE B - `sudo archlinux-java set` is banned. It changes the machine-wide default JDK for every
# project. Fix: pass the JDK explicitly (JAVA_HOME=..., -Dorg.gradle.java.home=...) instead. The
# non-sudo form (`archlinux-java set` without sudo) is left alone - the rule names the sudo form only.
#
# RULE C - creating (or renaming into) a branch literally named `main` is denied, but ONLY in a repo
# whose origin remote owner is in the operator's own namespace list ($KIT_ROOT/.state/own-namespaces,
# one namespace per line, operator-owned - this guard never writes it). An upstream clone legitimately
# uses `main`, so this cannot be a blanket ban; it is scoped by ownership instead. No namespace list,
# no origin, or an origin URL this guard cannot parse into owner/repo -> allow, breadcrumbed. `-C <dir>`
# and a preceding `cd` are both resolved via guard_resolve_cwd, same as every commit-time guard. Covers
# `checkout -b|-B|--branch main`, `switch -c|-C|--create|--force-create main`, `branch main`, and the
# rename forms `branch -m|-M [old] main` - all land on the same branch name, so all are denied alike.
#
# RULE D - every AskUserQuestion question shows a marked default: single-select, the FIRST option
# carries the literal text "(Recommended)" in its label or its description; multiSelect, at least one
# option does (which ones form the recommended set is judgement, not checked here). Source: the
# gating-workflow skill (an unmarked list reads as equal weight). No questions array at all -> allow.
#
# RULE F - a SendMessage must say what should happen if the recipient already finished. A send to a
# finished agent resumes it from its transcript, so an unlabelled mid-flight message can restart work
# that was done. The body must carry NOOP-IF-DONE (if your task already finished, reply NOOP and stop)
# or RESUME-OK (a deliberate resume with new work). Exempt: any send whose CALLER is a subagent
# (payload agent_type set and not "main"): a subagent reports to its launcher by "main" or by the
# launcher's agentId, and the launcher is never finished. Also exempt: an empty message (a pure
# notify_when_idle subscription). Ceiling: a subagent messaging a finished sibling is not caught.
#
# RULE G - a SendMessage to a peer session that has sat idle too long wakes it, and its next turn
# re-reads its whole context with the prompt cache already expired (5 min TTL, 1h extended) - costly
# and usually unintended. `to` is either a peer NAME (a trailing " [ref]" suffix stripped) or a
# `uds:<socket path>` form; the uds form reads the matching <pid>.json by the socket's own filename
# and confirms .messagingSocketPath, the name form matches every record whose .name equals it AND
# whose .pid is still a live process (kill -0) - no live match -> Rule G does nothing, more than one
# live match for the same name -> fail open (the ref cannot be mapped to a single record). A record
# with a non-numeric statusUpdatedAt, or one that looks like seconds rather than milliseconds
# (< 100000000000), fails open and breadcrumbs why. Idle past AGENT_TIERS_PEER_IDLE_SECS (non-digit,
# empty or 0 -> default 3600s; above 604800 -> clamped to 604800, never reset) -> denied unless the
# message carries WAKE-OK: followed by a non-space reason on the same line. An empty message (a pure
# notify_when_idle subscription) is exempt. The Lead's own denial also reminds that Rule F still
# applies once WAKE-OK is added. Runs BEFORE the subagent-caller exit and Rule F below - unlike Rule
# F, this applies to every caller including a subagent, which pays the same cache-reheat cost.
#
# What none of these catch: a hostile rewrite via env/xargs/sh -c indirection (guard-cmdpos.sh's own
# disclosed ceiling, unchanged here); rule C only recognises https:// and git@host: origin URL forms;
# rule A/B/C are quote-blind command-position text matches, not a real shell parser. The pipe rule
# (pnpm check/build piped into tail/head/grep, exit code lost) lived here as Rule E until 2026-10-01;
# long-run-guard.sh covers that shape and more, so it is the one copy now.
#
# Fail-open on every tooling gap (no jq, no library, unparseable git remote, missing namespace file),
# breadcrumbed to .state/guards.log. Kill switch: .state/off/simple-rules-guard, checked before any
# side effect. Self-check: simple-rules-guard.selfcheck.sh.
#
# KIT_ROOT below is resolved from $0, not from CLAUDE_CONFIG_DIR: the kill switch and own-namespaces
# list both live in the KIT's own .state (shared across every Claude profile pointed at this kit), and
# only a flattened per-profile view follows CLAUDE_CONFIG_DIR - do not "fix" this the other way.
set -u

KIT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${KIT_ROOT:-${TMPDIR:-/tmp}}/.state/guards.log}"
SID=""

note() { # $1 = message, no decision prefix (fail-open breadcrumbs)
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s simple-rules-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}

deny() { # $1 = reason
  note "deny: $(printf '%s' "$1" | cut -c1-140)"
  jq -n --arg r "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

[ -f "${KIT_ROOT:-}/.state/off/simple-rules-guard" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }

SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ -n "$TOOL" ] || exit 0

# --- Rule A: codex resume --last / codex exec resume --last -------------------------------------
rule_a() { # $1 = segments -> stdout: deny reason, empty if no hit
  segs="$1"
  frag='codex[[:space:]]+(exec[[:space:]]+)?resume([[:space:]]|$)'
  matches="$(guard_segs_at_cmdpos "$segs" "$frag")"
  [ -n "$matches" ] || return 0
  printf '%s\n' "$matches" | while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    printf '%s' "$seg" | grep -aqE '(^|[[:space:]])--last([[:space:]]|$)' || continue
    printf 'agent-tiers: resuming the last codex session with --last is ambiguous once more than one session exists, and it has attached to the wrong thread before. Resume by explicit session id instead: codex exec resume <session-id> or codex resume <session-id> (see codex exec resume --help/--list for the id).\n'
    break
  done
}

# --- Rule B: sudo archlinux-java set -------------------------------------------------------------
rule_b() { # $1 = segments -> stdout: deny reason, empty if no hit
  segs="$1"
  frag='sudo[[:space:]]+([^[:space:]=]*/)?archlinux-java[[:space:]]+set([[:space:]]|$)'
  match="$(guard_segs_at_cmdpos "$segs" "$frag" | head -1)"
  [ -n "$match" ] || return 0
  printf 'agent-tiers: sudo archlinux-java set changes the machine-wide default JDK for every project. Pass the JDK explicitly instead (JAVA_HOME=..., -Dorg.gradle.java.home=...) rather than changing the machine default.\n'
}

# --- Rule C: a new branch named main, in the operators own repos only ----------------------------
# RC_BRANCH_FRAG is built after guard-cmdpos.sh is sourced (needs its CMDPOS_GITOPTS), inside the Bash
# branch below - not here, since this fragment is unused on the AskUserQuestion path and the library
# is not sourced there.
rule_c() { # $1 = segments, $2 = payload cwd -> stdout: deny reason, empty if no hit or fail-open
  segs="$1" pcwd="$2"
  match="$(guard_segs_at_cmdpos "$segs" "$RC_BRANCH_FRAG" | head -1)"
  [ -n "$match" ] || return 0

  # Derive the verb from WHICH alternative actually matched at command position, not a free grep
  # over the segment text - a free grep reads "branch" out of a PATH (`git -C ~/src/branch-tool
  # switch -c main`), guard_verb_optspan then finds no literal "branch" token and returns the whole
  # segment unbounded (guard-cmdpos.sh's own optspan bound exists precisely to prevent that). Strip
  # the same leading subshell/group-open guard_segs_at_cmdpos itself strips before its own match test.
  bare="$(printf '%s' "$match" | sed -E 's#^[[:space:]]*[({][[:space:]]*##')"
  verb=""
  printf '%s' "$bare" | grep -aEq "${CMDPOS_PREFIX}git[[:space:]]+(${CMDPOS_GITOPTS})*${RC_FRAG_CHECKOUT}" && verb="checkout"
  if [ -z "$verb" ]; then
    printf '%s' "$bare" | grep -aEq "${CMDPOS_PREFIX}git[[:space:]]+(${CMDPOS_GITOPTS})*${RC_FRAG_SWITCH}" && verb="switch"
  fi
  [ -n "$verb" ] || verb="branch"

  resolved="$(guard_resolve_cwd "$segs" "$RC_BRANCH_FRAG" "$pcwd" "$verb" 1)"
  if guard_cwd_unresolved "$resolved"; then
    note "fail-open: rule C could not resolve the target repo (${resolved#unresolved })"
    return 0
  fi

  NSFILE="${KIT_ROOT:-}/.state/own-namespaces"
  if [ ! -s "$NSFILE" ]; then
    note "fail-open: rule C - no own-namespaces list at $NSFILE"
    return 0
  fi

  url="$(git -C "$resolved" remote get-url origin 2>/dev/null || true)"
  if [ -z "$url" ]; then
    note "fail-open: rule C - $resolved has no origin remote"
    return 0
  fi

  owner=""
  case "$url" in
    https://*/*|http://*/*) owner="$(printf '%s' "$url" | sed -E 's#^https?://[^/]+/([^/]+)/.*#\1#')" ;;
    git@*:*) owner="$(printf '%s' "$url" | sed -E 's#^git@[^:]+:([^/]+)/.*#\1#')" ;;
  esac
  if [ -z "$owner" ]; then
    note "fail-open: rule C - origin URL is not a recognised owner/repo form: $url"
    return 0
  fi

  if grep -av '^[[:space:]]*#' "$NSFILE" 2>/dev/null | grep -av '^[[:space:]]*$' | grep -Fxq "$owner"; then
    printf "agent-tiers: creating a branch named main in %s is denied - this is one of the operator's own repos and the default branch here is master, not main. Use master, or pick a different name for this new branch.\n" "$resolved"
  fi
}

if [ "$TOOL" = "Bash" ]; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  [ -n "$CMD" ] || exit 0

  LIB="$(dirname "$0")/guard-cmdpos.sh"
  [ -r "$LIB" ] || { note "fail-open: guard-cmdpos.sh missing/unreadable at $LIB"; exit 0; }
  . "$LIB" 2>/dev/null || { note "fail-open: guard-cmdpos.sh failed to source"; exit 0; }
  command -v guard_split_segments >/dev/null 2>&1 && command -v guard_has_heredoc >/dev/null 2>&1 \
    && command -v guard_segs_at_cmdpos >/dev/null 2>&1 \
    && command -v guard_resolve_cwd >/dev/null 2>&1 && command -v guard_cwd_unresolved >/dev/null 2>&1 \
    || { note "fail-open: guard-cmdpos.sh sourced but stale (a required helper is undefined)"; exit 0; }
  # Each alternative is also kept as its own constant (RC_FRAG_CHECKOUT/RC_FRAG_SWITCH) so rule_c can
  # test which one matched, rather than grepping the verb word out of the segment text (finding 4).
  RC_FRAG_CHECKOUT="checkout[[:space:]]+(-b|-B|--branch)[[:space:]]+main([[:space:]]|\$)"
  RC_FRAG_SWITCH="switch[[:space:]]+(-c|-C|--create|--force-create)[[:space:]]+main([[:space:]]|\$)"
  RC_FRAG_BRANCH_RENAME="branch[[:space:]]+(-m|-M)([[:space:]]+[^[:space:]]+)?[[:space:]]+main([[:space:]]|\$)"
  RC_FRAG_BRANCH_PLAIN="branch[[:space:]]+main([[:space:]]|\$)"
  RC_BRANCH_FRAG="git[[:space:]]+(${CMDPOS_GITOPTS:-})*(${RC_FRAG_CHECKOUT}|${RC_FRAG_SWITCH}|${RC_FRAG_BRANCH_RENAME}|${RC_FRAG_BRANCH_PLAIN})"

  # A heredoc stands the whole command down - this is an anti-accident nudge, not a security boundary,
  # same carve-out grep-footgun-guard.sh and memory-write-gate.sh already take (guard-cmdpos.sh header).
  guard_has_heredoc "$CMD" && exit 0

  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
  SEGMENTS="$(guard_split_segments "$CMD")"

  REASON="$(rule_a "$SEGMENTS")"
  [ -n "$REASON" ] || REASON="$(rule_b "$SEGMENTS")"
  [ -n "$REASON" ] || REASON="$(rule_c "$SEGMENTS" "$CWD")"
  [ -n "$REASON" ] && deny "$REASON"
  exit 0
fi

if [ "$TOOL" = "AskUserQuestion" ]; then
  QCOUNT="$(printf '%s' "$INPUT" | jq -r '(.tool_input.questions // []) | length' 2>/dev/null || true)"
  case "$QCOUNT" in ''|0) exit 0 ;; esac

  BAD="$(printf '%s' "$INPUT" | jq -r '
    def marked: (((.label // "") + " " + (.description // "")) | contains("(Recommended)"));
    [ (.tool_input.questions // [])[]
      | if (.multiSelect // false) == true then ((.options // []) | any(marked))
        else ((.options[0] // {}) | marked) end
    ] | any(. == false)
  ' 2>/dev/null || true)"
  [ "$BAD" = "true" ] && deny "agent-tiers: every AskUserQuestion question needs a marked default so the operator does not read the options at equal weight. Single-select: put the literal text (Recommended) on the FIRST option (label or description). multiSelect: put it on every option in the recommended set, at least one. Mark it and retry."
  exit 0
fi

# --- Rule G: deny a SendMessage to a peer session that has been idle too long --------------------
rule_g() { # $1 = to, $2 = message, $3 = agent_type -> stdout: deny reason, empty if no hit/fail-open
  to="$1" msg="$2" agt="$3"
  [ -n "$msg" ] || return 0   # a pure notify_when_idle subscription carries no message - not a wake

  sdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
  [ -d "$sdir" ] || return 0

  name="" status="" updated=""

  case "$to" in
    uds:*)
      sockpath="${to#uds:}"
      base="${sockpath##*/}"
      pid="${base%.sock}"
      case "$pid" in ''|*[!0-9]*) return 0 ;; esac
      f="$sdir/$pid.json"
      [ -r "$f" ] || return 0
      # Same liveness rule as the name form: a record left behind by a dead session never denies.
      kill -0 "$pid" 2>/dev/null || return 0
      rec="$(jq -r --arg p "$sockpath" '
        if (.messagingSocketPath // "") == $p
        then [(.name // ""), (.status // ""), (if .statusUpdatedAt == null then "" else (.statusUpdatedAt|tostring) end)] | @tsv
        else "" end
      ' "$f" 2>/dev/null)"
      [ -n "$rec" ] || return 0
      name="$(printf '%s\n' "$rec" | cut -f1)"
      status="$(printf '%s\n' "$rec" | cut -f2)"
      updated="$(printf '%s\n' "$rec" | cut -f3)"
      ;;
    *)
      name="$(printf '%s' "$to" | sed -E 's/[[:space:]]+\[[^][:space:]]+\]$//')"
      [ -n "$name" ] || return 0

      # Cheap text prefilter before any jq fork - an unmatched agent-id `to` (the common subagent
      # case) never pays a jq cost at all.
      candidates="$(grep -lF -- "\"$name\"" "$sdir"/*.json 2>/dev/null)"
      [ -n "$candidates" ] || return 0

      live_count=0 live_file=""
      oldifs="$IFS"
      IFS='
'
      for f in $candidates; do
        IFS="$oldifs"
        [ -r "$f" ] || continue
        rname="$(jq -r '.name // empty' "$f" 2>/dev/null)"
        [ "$rname" = "$name" ] || continue
        rpid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
        case "$rpid" in ''|*[!0-9]*) continue ;; esac
        kill -0 "$rpid" 2>/dev/null || continue
        live_count=$((live_count + 1))
        live_file="$f"
        IFS='
'
      done
      IFS="$oldifs"

      # 0 live matches -> no real peer by that name, do nothing. More than 1 -> the ref cannot be
      # mapped to a single record, fail open rather than guess.
      [ "$live_count" -eq 1 ] || return 0
      status="$(jq -r '.status // empty' "$live_file" 2>/dev/null)"
      updated="$(jq -r '.statusUpdatedAt // empty' "$live_file" 2>/dev/null)"
      ;;
  esac

  [ "$status" = "idle" ] || return 0
  case "$updated" in
    ''|*[!0-9]*) note "fail-open: rule G - statusUpdatedAt for $name is not numeric"; return 0 ;;
  esac
  if [ "$updated" -lt 100000000000 ] 2>/dev/null; then
    note "fail-open: rule G - statusUpdatedAt for $name looks like seconds, not milliseconds"
    return 0
  fi

  thresh="${AGENT_TIERS_PEER_IDLE_SECS:-3600}"
  case "$thresh" in ''|*[!0-9]*) thresh=3600 ;; esac
  [ "$thresh" -gt 0 ] 2>/dev/null || thresh=3600
  [ "$thresh" -le 604800 ] 2>/dev/null || thresh=604800

  now="$(date +%s)"
  idle_secs=$(( now - updated / 1000 ))
  [ "$idle_secs" -gt "$thresh" ] || return 0

  case "$msg" in
    *WAKE-OK:*)
      after="${msg#*WAKE-OK:}"
      line1="$(printf '%s\n' "$after" | head -1)"
      trimmed="$(printf '%s' "$line1" | tr -d '[:space:]')"
      [ -n "$trimmed" ] && return 0
      ;;
  esac

  extra=""
  case "$agt" in
    ''|main|MAIN)
      case "$msg" in
        *NOOP-IF-DONE*|*RESUME-OK*) ;;
        *) extra=" This message will also still need NOOP-IF-DONE or RESUME-OK (Rule F) before it can be sent." ;;
      esac ;;
  esac
  mins=$(( idle_secs / 60 ))
  printf 'agent-tiers: %s has been idle for about %s minute(s), so its prompt cache is cold and this message would wake it and make it re-read its whole context. Do not send unless the wake is deliberate - if it is, put WAKE-OK:<why> in the message and retry.%s\n' "$name" "$mins" "$extra"
}

if [ "$TOOL" = "SendMessage" ]; then
  TO="$(printf '%s' "$INPUT" | jq -r '.tool_input.to // empty' 2>/dev/null || true)"
  MSG="$(printf '%s' "$INPUT" | jq -r '.tool_input.message // empty' 2>/dev/null || true)"
  AGT="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)"

  REASON="$(rule_g "$TO" "$MSG" "$AGT")"
  [ -n "$REASON" ] && deny "$REASON"

  case "$AGT" in ''|main|MAIN) ;; *) exit 0 ;; esac
  [ "$TO" = "main" ] && exit 0
  [ -n "$MSG" ] || exit 0
  case "$MSG" in
    *NOOP-IF-DONE*|*RESUME-OK*) exit 0 ;;
  esac
  deny "agent-tiers: a SendMessage to an agent that already finished resumes it from its transcript, so say which you mean. Put NOOP-IF-DONE in the message (if your task already finished, reply NOOP and stop) for a mid-flight note, or RESUME-OK for a deliberate resume with new work, and retry."
fi

exit 0

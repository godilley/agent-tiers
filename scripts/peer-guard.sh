#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash|Write|Edit|MultiEdit|NotebookEdit) guard: presence-aware peer-session
# advisory/ask/deny. Reads nothing but the live socket directory the host keeps at
# /run/user/<uid>/cc-socks/<pid>.sock (override PEER_GUARD_SOCK_DIR; if that dir doesn't exist, falls
# back to $XDG_RUNTIME_DIR/cc-socks when set - where the host's socket dir lives on macOS is not
# verified) - nothing writes a registry, this script only reads what is already there.
#
# ARM 1 (every matched tool call, LEAD caller only - a subagent never updates or sees this, the Lead's
# own advisory is the once-per-repo-change signal): a same-repo peer is advisory only
# (additionalContext), never a permission decision - it fires once per CHANGE in the peer set for this
# session+repo, not per call. The state file is keyed on session id PLUS repo slug
# ($STATE_DIR/<sid>__<slug>.peers), and is written ONLY at the moment its advisory is actually emitted
# - if ARM 2 also decides this same call, ARM 1's state is left untouched so the advisory is not lost,
# it simply shows up again on the next call instead.
# ARM 2 (Write|Edit|MultiEdit|NotebookEdit only): a write landing in a FOREIGN repo (not this session's
# own, by git-common-dir - see below) is denied once per session per repo (read its docs first, then
# retry), or asks if a live peer is already in that foreign repo. A subagent caller or an unattended
# session gets that ask converted to a deny (guard_ask_decision/guard_ask_prefix, shared with every
# other ask-class guard - see guard-cmdpos.sh); an unattended LEAD (no agent type at all, under the
# session's own unattended flag) gets a deny worded for "nobody can approve this", not the
# approve-oriented ask text. TWO marker kinds, per session+repo: `.nopeer` (written by a Lead's first
# no-peer deny) and `.peer` (written by a real attended-Lead ask). Either one silences a later NO-PEER
# retry; only `.peer` silences a later LIVE-PEER ask - a no-peer marker can never pre-empt a live-peer
# ask that shows up afterward. A marker is always WRITTEN BEFORE the decision it backs is set: if the
# write fails, this call emits NO arm 2 decision at all (noted fail-open, retried on the next write) -
# a decision is never left standing on a marker that may not actually be there. A converted deny
# (subagent, or unattended Lead) and a subagent's no-peer deny never write a marker, so the identical
# retry that caused them hits the same deny again, and the Lead's own first ask/deny in that repo is
# never pre-spent by a subagent's call. A subagent's deny also carries a remedy telling the Lead how
# to clear the gate (one Write/Edit into the target repo) and re-dispatch. The session id plus repo
# slug that keys every marker/state file is capped at 200 chars combined (falls back to a checksum
# slug, `h<cksum of the repo path>`) so a very long repo path cannot produce an unusable filename.
#
# DISCLOSED CEILINGS:
#  - Bash writes into a foreign repo (`cd x && ...`, `git -C x ...`) get only the arm 1 same-repo-peer
#    advisory, never arm 2's foreign-repo ask/deny - this guard does not resolve a Bash command's
#    effective target directory. Upgrade path: reuse guard-cmdpos.sh's cwd resolution (guard_resolve_cwd
#    and friends) if this bites in practice.
#  - pg_is_claude splits /proc/<pid>/cmdline on NUL only; an argv0 containing an embedded newline
#    followed by the literal text "claude" on its own line would pass the basename check - this needs a
#    stale socket, pid reuse, and a crafted argv0 all at once to matter.
#  - A session whose own cwd is not inside a git repo (SESSION_REPO/SESSION_COMMON both empty) treats
#    every repo a write lands in as foreign - there is no "home repo" to compare against.
#  - A superproject and one of its submodules are foreign to each other (different git-common-dir each),
#    same as any two unrelated repos.
#  - The arm 1 advisory fires once per CHANGE in the peer pid set, not once per call - a steady peer set
#    goes silent after the first mention.
#  - A peer's location is its process cwd (the directory it was LAUNCHED in), never where it happens to
#    be writing right now - a Write/Edit call never changes a process's cwd. Two sessions both launched
#    in repo A that go on to edit repo B never see each other as B's peers (a kit edited from sessions
#    launched in some other repo is exactly that shape).
#    Upgrade path, if it bites: derive each peer's working repos from its recent write record instead
#    of its launch cwd.
#  - Linux /proc only. No /proc (not Linux, or unreadable) is a fail-open, breadcrumbed, same as every
#    other tooling gap below.
#  - State and marker files are GC'd opportunistically (mtime, default 7 days via
#    AGENT_TIERS_STATE_DAYS), but only at the moment this
#    guard itself writes a new one - a session that never triggers either arm never grows its own
#    state, and a long-idle guard never pays a GC cost on a pure read ( --list, a no-op call).
#
# Presence source has no registry: a peer is "live" only if kill -0 succeeds AND /proc/<pid>/cmdline's
# argv0 or argv1 basename is literally "claude" - pid reuse and a stale socket left behind by kill -9
# are otherwise false peers. Self is found by walking this process's own ppid chain (override
# PEER_GUARD_SELF_PID for tests) until a passing-the-same-check ancestor is found, and is computed ONCE
# per run (cached, not re-walked per candidate or per pg_scan call) - AFTER the kill-switch check in
# hook mode, and only inside the --list branch in CLI mode, so a kill-switched run never walks /proc or
# logs a note; a candidate is excluded when it IS
# self, is a descendant of self (self appears in the candidate's own ancestry - walked per candidate,
# that part cannot be cached), or is an ancestor of self (the candidate appears in self's CACHED
# ancestry) - nested `claude -p` children and parents of this very session are not peers. If self
# cannot be found at all, nothing is excluded and a breadcrumb is logged (own session may then list
# itself as a peer).
#
# ARM 2's foreign/not-foreign test compares `git rev-parse --git-common-dir` (made absolute) of the
# write target and of the session cwd, not --show-toplevel - a linked worktree of the session's OWN
# repo shares its common-dir, so a worker writing into its own worktree is never "foreign". Arm 1's
# same-repo-peer match, and pg_scan's target filter, deliberately keep --show-toplevel equality instead
# (a worktree session is still not a same-repo PEER of the main tree, by design).
#
# Kill switch: .state/off/peer-guard, checked before any side effect. Fail-open (jq missing, sock dir
# missing/unreadable, /proc unreadable, empty session_id, guard-cmdpos.sh missing or stale) breadcrumbed
# to guards.log.
# Self-check: peer-guard.selfcheck.sh.
set -u

KIT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
BASE="$KIT_ROOT"   # guard-cmdpos.sh's guard_state_dir()/guard_unattended() read $BASE, not KIT_ROOT
LOG="${AGENT_TIERS_GUARDS_LOG:-${KIT_ROOT:-${TMPDIR:-/tmp}}/.state/guards.log}"
SID=""

note() { # $1 = message, no decision prefix (fail-open breadcrumbs)
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s peer-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}

# Where the host's socket dir lives on macOS is not verified; PEER_GUARD_SOCK_DIR is the override.
# The only observed host path is /run/user/<uid>/cc-socks, so that wins over XDG_RUNTIME_DIR whenever
# it actually exists - XDG_RUNTIME_DIR/cc-socks is a fallback for a host where it doesn't.
RUN_UID_SOCK_DIR="/run/user/$(id -u 2>/dev/null)/cc-socks"
if [ -n "${PEER_GUARD_SOCK_DIR:-}" ]; then
  SOCK_DIR="$PEER_GUARD_SOCK_DIR"
elif [ -d "$RUN_UID_SOCK_DIR" ]; then
  SOCK_DIR="$RUN_UID_SOCK_DIR"
elif [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  SOCK_DIR="$XDG_RUNTIME_DIR/cc-socks"
else
  SOCK_DIR="$RUN_UID_SOCK_DIR"
fi

# --- proc / presence helpers -------------------------------------------------------------------------

# pg_is_claude <pid> -> 0 if pid is alive and argv0 or argv1 basename is literally "claude"
pg_is_claude() {
  pid="$1"
  kill -0 "$pid" 2>/dev/null || return 1
  [ -r "/proc/$pid/cmdline" ] || return 1
  a0="$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | sed -n 1p)"
  a1="$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | sed -n 2p)"
  [ "$(basename "${a0:-}" 2>/dev/null)" = "claude" ] && return 0
  [ "$(basename "${a1:-}" 2>/dev/null)" = "claude" ] && return 0
  return 1
}

# pg_ppid <pid> -> stdout the ppid from /proc/<pid>/stat, empty on failure. The comm field is
# parenthesised and may itself contain ")" or spaces, so the ppid is read after the LAST ")" in the
# line (field 2 of the remainder: state, ppid, ...), never by naive field-splitting of the whole line.
pg_ppid() {
  stat="$(cat "/proc/$1/stat" 2>/dev/null)" || { printf ''; return 1; }
  rest="${stat##*) }"
  set -- $rest
  printf '%s\n' "${2:-}"
}

# pg_ancestry <pid> -> stdout, one pid per line: $1 then its ppid chain, capped at 50 hops (defends
# against a /proc read that loops on a corrupt chain rather than hanging this hook).
pg_ancestry() {
  p="$1"; n=0
  while [ -n "$p" ] && [ "$p" != "0" ] && [ "$n" -lt 50 ]; do
    printf '%s\n' "$p"
    p="$(pg_ppid "$p" 2>/dev/null)"
    n=$((n + 1))
  done
}

# pg_self -> stdout this session's own pid (the nearest claude ancestor, override PEER_GUARD_SELF_PID),
# empty if none found.
pg_self() {
  start="${PEER_GUARD_SELF_PID:-${PPID:-}}"
  [ -n "$start" ] || return 0
  for p in $(pg_ancestry "$start"); do
    if pg_is_claude "$p"; then printf '%s\n' "$p"; return 0; fi
  done
  return 0
}

# pg_is_self_or_kin <candidate pid> -> 0 if the candidate must be excluded, against the CACHED
# PG_SELF/PG_SELF_ANCESTRY (computed once per run, below) - the candidate IS self, self is in the
# candidate's own ancestry (candidate is a descendant of self - this walk is per-candidate by nature,
# cannot be cached), or the candidate is in self's cached ancestry (candidate is an ancestor of self).
pg_is_self_or_kin() {
  cand="$1"
  [ -n "$PG_SELF" ] || return 1
  [ "$cand" = "$PG_SELF" ] && return 0
  for p in $(pg_ancestry "$cand"); do [ "$p" = "$PG_SELF" ] && return 0; done
  for p in $PG_SELF_ANCESTRY; do [ "$p" = "$cand" ] && return 0; done
  return 1
}

# pg_common_dir <dir> -> stdout the absolute git-common-dir for <dir>, empty if not a repo or any step
# fails. --git-common-dir is shared across all of a repo's linked worktrees (unlike --show-toplevel),
# so this is the right equality test for arm 2's "is this write actually foreign" decision.
pg_common_dir() {
  d="$1"
  CDPATH= cd "$d" >/dev/null 2>&1 || return 1
  CDPATH= cd "$(git rev-parse --git-common-dir 2>/dev/null)" >/dev/null 2>&1 || return 1
  pwd -P
}

# pg_slug <repo> -> stdout: a filesystem-safe slug for <repo>, capped so "${SID}__<slug>" never
# exceeds 200 chars - falls back to a checksum-based slug (h<cksum of the repo path>) when the plain
# substitution would be too long. Shared by arm 1's state-file slug and arm 2's marker slug so both
# stay capped the same way.
pg_slug() {
  repo="$1"
  slug="$(printf '%s' "$repo" | tr -c 'A-Za-z0-9' '_')"
  combined="${SID}__${slug}"
  if [ "${#combined}" -gt 200 ]; then
    h="$(printf '%s' "$repo" | cksum | cut -d' ' -f1)"
    slug="h${h}"
  fi
  printf '%s\n' "$slug"
}

# pg_gc: opportunistic cleanup of state/marker files older than default 7 days (AGENT_TIERS_STATE_DAYS) -
# called only right after this
# guard itself writes a NEW marker or state file (point 7/cap), never on a bare read, so a read-only
# --list or a silent no-decision call never pays for it. Errors ignored.
pg_gc() {
  # default 7 (AGENT_TIERS_STATE_DAYS), validated: non-digit, 0, or anything over 3650 silently falls
  # back to 7 (a garbage, zero, or absurd value in `find -mtime +N` either errors or deletes nearly
  # everything).
  days="${AGENT_TIERS_STATE_DAYS:-7}"; case "$days" in ''|*[!0-9]*) days=7 ;; esac
  [ "$days" -gt 0 ] 2>/dev/null && [ "$days" -le 3650 ] 2>/dev/null || days=7
  find "$STATE_DIR" -maxdepth 1 -type f -mtime "+$days" -delete 2>/dev/null
  find "$STATE_DIR/foreign" -maxdepth 1 -type f -mtime "+$days" -delete 2>/dev/null
  true
}

# pg_scan <sock_dir> [target_repo] -> stdout "<pid> <age-seconds> <cwd>" per matching live peer (age
# before cwd so a cwd containing spaces can never shift which field is the age). No target_repo: every
# live, non-self claude peer (the raw --list view). With a target_repo: only peers whose cwd's git
# toplevel equals it exactly (a linked worktree has its own toplevel and is never a match for its main
# tree, by construction).
pg_scan() {
  dir="$1"; target="${2:-}"
  [ -d "$dir" ] || return 0
  for sock in "$dir"/*.sock; do
    [ -e "$sock" ] || continue
    pid="$(basename "$sock" .sock)"
    case "$pid" in *[!0-9]*) continue ;; esac
    pg_is_claude "$pid" || continue
    pg_is_self_or_kin "$pid" && continue
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)" || continue
    [ -n "$cwd" ] || continue
    if [ -n "$target" ]; then
      repo="$(CDPATH= cd "$cwd" >/dev/null 2>&1 && git rev-parse --show-toplevel 2>/dev/null)"
      [ -n "$repo" ] || continue
      [ "$repo" = "$target" ] || continue
    fi
    age="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')"
    printf '%s %s %s\n' "$pid" "${age:-0}" "$cwd"
  done
}

# --- self detection: computed ONCE per run (list mode or hook mode), never per candidate/per pg_scan
# call (point 5) - deliberately done AFTER the kill-switch check in hook mode (below) and only inside
# the --list branch here, so a kill-switched run never walks /proc or writes a note. -----------------
PG_SELF=""
PG_SELF_ANCESTRY=""
pg_init_self() {
  PG_SELF="$(pg_self)"
  if [ -n "$PG_SELF" ]; then
    PG_SELF_ANCESTRY="$(pg_ancestry "$PG_SELF")"
  else
    note "self not found, own session may be listed as a peer"
  fi
}

# --- CLI mode: peer-guard.sh --list <dir> --------------------------------------------------------
if [ "${1:-}" = "--list" ]; then
  pg_init_self
  pg_scan "${2:-$SOCK_DIR}"
  exit 0
fi

# --- hook mode: PreToolUse JSON on stdin ----------------------------------------------------------
[ -f "${KIT_ROOT:-}/.state/off/peer-guard" ] && exit 0

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "fail-open: jq missing - cannot parse payload"; exit 0; }

SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SID:-}" in *[!A-Za-z0-9._-]* | '.' | '..') SID="" ;; esac
if [ "${#SID}" -gt 128 ]; then
  note "fail-open: session_id longer than 128"
  exit 0
fi

# self detection happens here, after SID is parsed (still after the kill switch) - so a "self not
# found" note carries the session id instead of an empty one.
pg_init_self

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ -n "$TOOL" ] || exit 0

case "$TOOL" in
  Bash|Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

[ -n "$SID" ] || { note "fail-open: empty session_id - skipping both arms (no markers or state without one)"; exit 0; }

if [ ! -d "$SOCK_DIR" ] || [ ! -r "$SOCK_DIR" ]; then
  note "fail-open: sock dir missing/unreadable ($SOCK_DIR)"
  exit 0
fi
if [ ! -d /proc ] || [ ! -r /proc ]; then
  note "fail-open: /proc unreadable - no presence source on this host"
  exit 0
fi

# Ask/deny parity with every other ask-class guard (point 1): guard_caller_agent / guard_ask_decision /
# guard_ask_prefix, never a hand-rolled .agent_type read or subagent-only deny text. Hard fail-open if
# the library is missing or stale - same pattern as review-gate-guard.sh's own sourcing guard.
SELFDIR="$(CDPATH= cd "$(dirname "$0")" >/dev/null 2>&1 && pwd || true)"
if [ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ]; then
  . "$SELFDIR/guard-cmdpos.sh"
else
  note "fail-open: guard-cmdpos.sh missing - cannot classify caller/ask posture"; exit 0
fi
command -v guard_caller_agent >/dev/null 2>&1 && command -v guard_ask_decision >/dev/null 2>&1 \
  && command -v guard_ask_prefix >/dev/null 2>&1 \
  || { note "fail-open: guard-cmdpos.sh sourced but a needed function is undefined (stale library?)"; exit 0; }

AGT="$(guard_caller_agent "$INPUT")"

PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
STATE_DIR="${PEER_GUARD_STATE_DIR:-${KIT_ROOT:-${TMPDIR:-/tmp}}/.state/peer-guard}"
mkdir -p "$STATE_DIR/foreign" 2>/dev/null || true

SESSION_REPO=""
SESSION_COMMON=""
if [ -n "$PAYLOAD_CWD" ] && [ -d "$PAYLOAD_CWD" ]; then
  SESSION_REPO="$(CDPATH= cd "$PAYLOAD_CWD" >/dev/null 2>&1 && git rev-parse --show-toplevel 2>/dev/null || true)"
  SESSION_COMMON="$(pg_common_dir "$PAYLOAD_CWD")"
fi

# --- ARM 1: same-repo peers, every matched tool, LEAD caller only (point 3) -------------------------
ARM1_OUT=""; ARM1_WRITE_FILE=""; ARM1_WRITE_VAL=""
if [ -z "$AGT" ] && [ -n "$SESSION_REPO" ]; then
  PEERS="$(pg_scan "$SOCK_DIR" "$SESSION_REPO")"
  SESSION_SLUG="$(pg_slug "$SESSION_REPO")"
  PEER_STATE_FILE="$STATE_DIR/${SID}__${SESSION_SLUG}.peers"
  if [ -n "$PEERS" ]; then
    PIDS_SORTED="$(printf '%s\n' "$PEERS" | awk '{print $1}' | sort -n | tr '\n' ' ' | sed 's/ *$//')"
    PREV="$(cat "$PEER_STATE_FILE" 2>/dev/null || true)"
    if [ "$PIDS_SORTED" != "$PREV" ]; then
      N="$(printf '%s\n' "$PEERS" | sed '/^$/d' | wc -l | tr -d ' ')"
      DESC="$(printf '%s\n' "$PEERS" | sed '/^$/d' | awk '{if (NR>1) printf ", "; printf "%s (%ss)", $1, $2}')"
      ARM1_OUT="agent-tiers peer-guard: $N other live Claude session(s) in this repo: ${DESC}. Do not run the test suite, an emulator, a build or a long check concurrently with them, and do not write to a shared branch without a heads-up (SendMessage, carrying NOOP-IF-DONE or RESUME-OK)."
      ARM1_WRITE_FILE="$PEER_STATE_FILE"; ARM1_WRITE_VAL="$PIDS_SORTED"
    fi
  else
    rm -f "$PEER_STATE_FILE" 2>/dev/null || true
  fi
fi

# --- ARM 2: foreign-repo writes, Write|Edit|MultiEdit|NotebookEdit only -----------------------------
ARM2_DECISION=""; ARM2_REASON=""; TARGET_REPO=""
case "$TOOL" in
  Write|Edit|MultiEdit)
    TARGET_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
    ;;
  NotebookEdit)
    TARGET_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.notebook_path // empty' 2>/dev/null || true)"
    ;;
  *)
    TARGET_PATH=""
    ;;
esac

# a relative file_path is resolved against the payload's own cwd (point 3) - if that is empty too,
# there is nothing to resolve against, so arm 2 is skipped for this call.
if [ -n "${TARGET_PATH:-}" ]; then
  case "$TARGET_PATH" in
    /*) ;;
    *) if [ -n "$PAYLOAD_CWD" ]; then TARGET_PATH="$PAYLOAD_CWD/$TARGET_PATH"; else TARGET_PATH=""; fi ;;
  esac
fi

if [ -n "${TARGET_PATH:-}" ]; then
  # a path landing inside a .git dir (repo hooks, config, or a submodule's entry under
  # <super>/.git/modules/x/...) is cut at the FIRST /.git and resolved from the part before it, so it
  # is classified against the owning (super)repo instead of silently skipping arm 2 (point 1 - git
  # rev-parse fails from inside .git itself).
  case "$TARGET_PATH" in
    */.git/*) GITCUT="${TARGET_PATH%%/.git/*}" ;;
    */.git) GITCUT="${TARGET_PATH%/.git}" ;;
    *) GITCUT="" ;;
  esac
  if [ -n "$GITCUT" ]; then
    TDIR="$GITCUT"
  else
    TDIR="$(dirname "$TARGET_PATH")"
  fi
  while [ -n "$TDIR" ] && [ "$TDIR" != "/" ] && [ ! -d "$TDIR" ]; do
    TDIR="$(dirname "$TDIR")"
  done
  if [ -d "$TDIR" ]; then
    TARGET_REPO="$(CDPATH= cd "$TDIR" >/dev/null 2>&1 && git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$TARGET_REPO" ] && [ "$TARGET_REPO" != "$SESSION_REPO" ]; then
      TARGET_COMMON="$(pg_common_dir "$TDIR")"
      if [ -z "$TARGET_COMMON" ] || [ -z "$SESSION_COMMON" ] || [ "$TARGET_COMMON" != "$SESSION_COMMON" ]; then
        # genuinely foreign (different git-common-dir) - not just a different linked worktree of this
        # session's own repo (point 4 / case E, which falls through here with no output at all).
        SLUG="$(pg_slug "$TARGET_REPO")"
        # TWO marker kinds, scanned in this order (peers first) so a no-peer marker can never silence
        # a later live-peer ask: .nopeer is written by a Lead's first no-peer deny, .peer by a real
        # (attended Lead) ask. Either one silences a later NO-PEER retry; only .peer silences a later
        # LIVE-PEER ask.
        MARKER_NOPEER="$STATE_DIR/foreign/${SID}__${SLUG}.nopeer"
        MARKER_PEER="$STATE_DIR/foreign/${SID}__${SLUG}.peer"
        FPEERS="$(pg_scan "$SOCK_DIR" "$TARGET_REPO")"
        REMEDY=" Lead: to clear this for the session, read $TARGET_REPO's docs and make one Write/Edit into $TARGET_REPO yourself (denied once, then marked); then re-dispatch."
        if [ -n "$FPEERS" ]; then
          if [ -f "$MARKER_PEER" ]; then
            : # a real ask already cleared this repo's live-peer gate this session - pass silently
          else
            DEC="$(guard_ask_decision "$SID" "$AGT")"
            FIRST_PID="$(printf '%s\n' "$FPEERS" | awk 'NR==1{print $1}')"
            FIRST_AGE="$(printf '%s\n' "$FPEERS" | awk 'NR==1{print $2}')"
            if [ "$DEC" = ask ]; then
              # real ask, attended Lead: write the marker BEFORE setting the decision (point 1 - a
              # failed write must never leave a decision behind it believes is marked when it isn't).
              # Mark BEFORE the human answers too (point 2), same posture as review-gate-guard.sh: a
              # declined ask followed by an identical retry passes silently.
              if { mkdir -p "$STATE_DIR/foreign" 2>/dev/null && : > "$MARKER_PEER"; } 2>/dev/null; then
                pg_gc
                ARM2_DECISION="ask"
                ARM2_REASON="$(guard_ask_prefix "$SID" "$AGT")agent-tiers peer-guard: this write lands in $TARGET_REPO, where another live Claude session is working ($FIRST_PID ${FIRST_AGE}s). Approve only if the edit cannot collide with it; consider a heads-up via SendMessage first."
              else
                note "fail-open: marker write failed for $MARKER_PEER"
                # no decision emitted this call - fall through, retried on the next write
              fi
            elif [ -z "$AGT" ]; then
              # unattended Lead, no human behind this session to approve an ask at all (point 4) -
              # never marks (no human cleared it), so the retry hits this same deny again.
              ARM2_DECISION="deny"
              ARM2_REASON="$(guard_ask_prefix "$SID" "$AGT")agent-tiers peer-guard: this write lands in $TARGET_REPO, where another live Claude session is working ($FIRST_PID ${FIRST_AGE}s), and this session is unattended, so nobody can approve it. Skip this edit and report it; it cannot be cleared while that session is live."
            else
              # subagent, live peer present: converted deny, never marks - a subagent cannot clear
              # this gate for the session (point 2 / case A).
              ARM2_DECISION="deny"
              ARM2_REASON="$(guard_ask_prefix "$SID" "$AGT")agent-tiers peer-guard: this write lands in $TARGET_REPO, where another live Claude session is working ($FIRST_PID ${FIRST_AGE}s). Approve only if the edit cannot collide with it; consider a heads-up via SendMessage first.${REMEDY}"
            fi
          fi
        else
          if [ -f "$MARKER_NOPEER" ] || [ -f "$MARKER_PEER" ]; then
            : # already cleared (either marker) - pass silently
          else
            if [ -n "$AGT" ]; then
              # subagent, no peer present: deny, but never mark - a subagent cannot clear this gate
              # for the session, so its own retry is denied again, and the Lead's later first-write
              # deny for this same repo is still unspent (point 2 / case B).
              ARM2_DECISION="deny"
              ARM2_REASON="$(guard_ask_prefix "$SID" "$AGT")agent-tiers peer-guard: first write this session into $TARGET_REPO, outside this session's repo. Before writing, read its CLAUDE.md, AGENTS.md and RESUME_SESSION.md (whichever exist) and state the scope of the edit in your reply.${REMEDY}"
            else
              # Lead, no peer present: write the marker BEFORE setting the decision (point 1).
              if { mkdir -p "$STATE_DIR/foreign" 2>/dev/null && : > "$MARKER_NOPEER"; } 2>/dev/null; then
                pg_gc
                ARM2_DECISION="deny"
                ARM2_REASON="agent-tiers peer-guard: first write this session into $TARGET_REPO, outside this session's repo. Before writing, read its CLAUDE.md, AGENTS.md and RESUME_SESSION.md (whichever exist) and state the scope of the edit in your reply. Then retry: this deny fires once per session per repo."
              else
                note "fail-open: marker write failed for $MARKER_NOPEER"
                # no decision emitted this call - fall through, retried on the next write
              fi
            fi
          fi
        fi
      fi
    fi
  fi
fi

# ARM 2's decision wins over ARM 1's advisory when both fire in the same call - one JSON object on
# stdout only. ARM 1's state is deliberately NOT persisted on this path (point 3): the advisory is
# lost for this call, but shows up again on the next one instead of being silently dropped forever.
if [ -n "$ARM2_DECISION" ]; then
  note "$ARM2_DECISION: foreign write to ${TARGET_REPO:-<unknown>}"
  jq -n --arg r "$ARM2_REASON" --arg d "$ARM2_DECISION" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
fi

if [ -n "$ARM1_WRITE_FILE" ]; then
  { printf '%s' "$ARM1_WRITE_VAL" > "$ARM1_WRITE_FILE"; } 2>/dev/null && pg_gc || true
fi
if [ -n "$ARM1_OUT" ]; then
  note "advisory: peer set changed in ${SESSION_REPO:-<unknown>}"
  jq -n --arg r "$ARM1_OUT" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $r}}'
  exit 0
fi

exit 0

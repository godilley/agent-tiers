#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers SessionStart hook: re-inject the project's RESUME_SESSION.md handoff into a
# fresh / compacted / resumed context. Wired ONCE globally (~/.claude/settings.json) so EVERY
# project benefits with no per-project hook. Guarded - a safe no-op when nothing applies.
#
# Behaviour:
#   - Stand-down: if the project ships its OWN resume hook the global one bows out (no double-inject) -
#     that INCLUDES the version stamp and loaded-doctrine manifest below, not just resume content; a
#     project with its own hook gets none of this one's output.
#   - Source-gate: RESUME CONTENT restores on compact|resume|clear|startup (any other/unknown source
#     gets the version stamp + manifest only, fail-closed) - the body is byte-capped (see
#     RESUME_CAP_BYTES below) so the whole inject stays under the host's inline limit.
#   - Structured hookSpecificOutput JSON when jq is present; raw-stdout fallback otherwise.
#   - Disclosure: a headless `claude -p` run started in a project directory is indistinguishable from an
#     interactive startup at this hook's level (both report source=startup), so it also gets the body on
#     startup. Disclosed, not opted out of - no mechanism here tells the two apart.
set -u
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"   # follow a relocated config dir (2nd account etc.)

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s resume-inject %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

# Timeout tracing, scoped to the expensive window only. Unlike the other three guards, this script has
# no single scan-then-decide shape (no identifiable hot block - many small file reads and subprocess
# calls spread across the whole body, none dominant on its own; the 19s timeout this traces, seen
# on a Windows (Git Bash) host, is plausibly death by a thousand small shellouts, not one slow step) -
# so the window covers the whole body, opened right after the stand-down check below (a project that
# owns its own resume hook bows out before the window even opens, logging nothing) and closed at each
# of its several normal exit points further down, all marked `end ... done=1`. A guard killed at its
# hook budget cannot write its own breadcrumb, so the window brackets itself. A kill inside it leaves
# `start` with either `done=0` (SIGTERM: the TERM trap below makes dash run the EXIT trap too, which
# it skips on an untrapped TERM) or no `end` at all (SIGKILL runs no trap).
GUARD_TRACE_OPEN=0
trap 'if [ "$GUARD_TRACE_OPEN" = 1 ]; then note "end [pid=$$] done=0"; fi' EXIT
trap 'exit 143' TERM

# A project that wants to own resume-injection drops its own .claude/hooks/load-resume.sh;
# the global hook then stands down so it doesn't double-inject over the project's richer hook.
[ -f "$DIR/.claude/hooks/load-resume.sh" ] && exit 0
GUARD_TRACE_OPEN=1; note "start [pid=$$]"

# Claude Code slugs projects/ dirs with replace(/[^a-zA-Z0-9]/g,"-") - verified against the CLI
# binary 2026-08-10, prompted by cold-review F9. Matching only `/` made the memory-threshold check
# silently read an empty dir for any project path containing a dot, underscore, or any other
# non-alphanumeric.
slug="$(printf '%s' "$DIR" | tr -c 'A-Za-z0-9' '-')"

# --- version stamp (2026-08-09): the "join key" any after-the-fact usage review needs to attribute a
#     session to an exact doctrine/card/def revision without inferring it from a date. Fires on EVERY
#     SessionStart source, startup included (same as the resume-content restore below now does) - a
#     plain new session is exactly the case a date-inferred join would otherwise have to cover. Cheap
#     (a handful of greps over files already on disk); any read failure fails open to an empty stamp,
#     never an error.
KIT="$CLAUDE_DIR/agent-tiers"
STAMP=""
if [ -f "$KIT/skills/agent-tiers/SKILL.md" ]; then
  dv="$(grep -oE 'doctrine-v[0-9]+ c=[0-9]+-[0-9]+' "$KIT/skills/agent-tiers/SKILL.md" 2>/dev/null | head -1)"
  cards=""
  for c in "$KIT"/skills/agent-tiers/cards/*.md; do
    [ -f "$c" ] || continue
    # card-vN AND its c=<cksum> (MAINT-2 provenance stamp), joined WITHOUT an internal space - without
    # the cksum, a normative edit that forgot to bump card-vN is invisible to a stamp reading the same
    # stale version number; an internal space would make "name=value value" ambiguous against the
    # space-separated list of cards/defs this builds.
    cv="$(grep -oE 'card-v([0-9]+) c=([0-9]+-[0-9]+)' "$c" 2>/dev/null | head -1 | sed -E 's/card-v([0-9]+) c=(.+)/v\1(c=\2)/')"
    [ -n "$cv" ] && cards="$cards $(basename "$c" .md)=$cv"
  done
  defs=""
  for a in "$KIT"/agents/*.md; do
    [ -f "$a" ] || continue
    dn="$(grep -oE 'def-version: ([0-9]+) c=([0-9]+-[0-9]+)' "$a" 2>/dev/null | head -1 | sed -E 's/def-version: ([0-9]+) c=(.+)/v\1(c=\2)/')"
    [ -n "$dn" ] && defs="$defs $(basename "$a" .md)=$dn"
  done
  [ -n "$dv" ] && STAMP="agent-tiers session stamp: ${dv}.${cards:+ cards:${cards}}${defs:+ defs:${defs}}"
fi

# --- loaded-doctrine manifest (2026-08-16): every rule-bearing file THIS session runs under
#     that the kit's own version stamp does not cover - global CLAUDE.md, the project CLAUDE.md / agent-tiers.local.md / RESUME_SESSION.md and project commands + skills. None of
#     these is stamped, any of them may legitimately override a scored rule ("a project file may
#     override"), and a parallel session may edit one mid-run: without this line a usage review cannot
#     tell an overlay-permitted behaviour from a violation, and "poison" (a rule-bearing file changed with
#     no manifest row) has no definition. One token per file, `path=c=<cksum>-<bytes>` or `path=absent`;
#     `~` = the config dir, `./` = the project dir. Its OWN prefix on its OWN line so any parser of the
#     version-stamp line never sees it. Rides on every source, same as the stamp. Fail-open:
#     an unreadable file reads as absent. Globbed names are charset-capped below, so no token can carry a
#     space, `=`, or newline; the fixed paths cannot either.
MANIFEST=""
mf_add() { # $1=label $2=path
  if [ -f "$2" ]; then
    ck="$(cksum < "$2" 2>/dev/null | awk '{print $1"-"$2}')"
    MANIFEST="$MANIFEST $1=c=${ck:-0-0}"
  else
    MANIFEST="$MANIFEST $1=absent"
  fi
}
mf_add '~/.claude/CLAUDE.md' "$CLAUDE_DIR/CLAUDE.md"
mf_add './CLAUDE.md' "$DIR/CLAUDE.md"
mf_add './.claude/agent-tiers.local.md' "$DIR/.claude/agent-tiers.local.md"
mf_add './RESUME_SESSION.md' "$DIR/RESUME_SESSION.md"
# The delegation doctrine itself (2026-08-23, retro run 3): SKILL.md + the policy cards are the
# rule-bearing surface every scoped/measurable retro rubric row is written against, yet before this
# line the manifest carried none of it - 0 of 55 manifested sessions in that run's corpus could show
# whether the doctrine was actually loaded. Fixed set (not a glob): these files are the kit's own
# skill, not project-controlled, so no charset/length/count cap applies (see the globbed blocks below
# for why THOSE need one - a project-shipped filename lands verbatim in model context, these do not).
mf_add '~/.claude/agent-tiers/skills/agent-tiers/SKILL.md' "$KIT/skills/agent-tiers/SKILL.md"
for _c in BOSS HOST MAINT ROUTE XLAB MEMORY; do
  mf_add "~/.claude/agent-tiers/skills/agent-tiers/cards/$_c.md" "$KIT/skills/agent-tiers/cards/$_c.md"
done
unset _c
# Globbed names are PROJECT-controlled (a cloned repo can ship them) and land verbatim in model context -
# same bar as the session-id guard and the vcs_policy parse below: charset [A-Za-z0-9_.-], length <= 64,
# at most 12 rows per glob; anything else is skipped (a newline in a name could otherwise forge a second
# stamp/manifest line that the extractor would parse).
mf_n=0
for f in "$DIR"/.claude/commands/*.md; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  case "$b" in *[!A-Za-z0-9_.-]*) continue ;; esac
  [ "${#b}" -le 64 ] && [ "$mf_n" -lt 12 ] || continue
  mf_add "./.claude/commands/$b" "$f"; mf_n=$((mf_n + 1))
done
mf_n=0
for f in "$DIR"/.claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  b="$(basename "$(dirname "$f")")"
  case "$b" in *[!A-Za-z0-9_.-]*) continue ;; esac
  [ "${#b}" -le 64 ] && [ "$mf_n" -lt 12 ] || continue
  mf_add "./.claude/skills/$b/SKILL.md" "$f"; mf_n=$((mf_n + 1))
done
# Extra rule-bearing files this MACHINE loads (a personal-context skill, a global on-demand rules file):
# one path per line in the untracked .state/manifest-extra, `~/` = the config dir. Kept OUT of the kit
# on purpose - a personal skill name in a shipped hook is a personal-context leak (caught 2026-08-16).
# Same 12-row cap as the globs above; the charset and length caps are DELIBERATELY wider here (these
# are paths, not directory names): the charset adds `/` and `~`, and the length cap is 120, not 64.
# A `#` line is a comment.
MF_EXTRA="$CLAUDE_DIR/agent-tiers/.state/manifest-extra"
if [ -f "$MF_EXTRA" ]; then
  mf_n=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; *[!A-Za-z0-9_./~-]*) continue ;; esac
    [ "${#line}" -le 120 ] && [ "$mf_n" -lt 12 ] || continue
    case "$line" in
      '~/.claude/'*) real="$CLAUDE_DIR/${line#'~/.claude/'}" ;;   # `~/` is only meaningful as `~/.claude/`
      /*) real="$line" ;;
      *) continue ;;                                              # bare `~/x`, relative paths: skipped
    esac
    mf_add "$line" "$real"; mf_n=$((mf_n + 1))
  done < "$MF_EXTRA"
fi
MANIFEST="agent-tiers loaded-doctrine manifest:$MANIFEST"

NL='
'

# --- arrival advisories (2026-08-23): one cheap check per fact that is TRUE, script-checkable, and today
#     surfaces only if a human re-reads the right file at the right moment. Same shape and same posture as
#     the lifecycle-threshold block below and as the project-local retro-due.sh: never blocking, never
#     auto-acting, fail-open on every missing file or tool, and NO new hook file - they ride the stamp
#     line, so they reach a plain startup too (the lifecycle block now also fires there since the
#     SOURCE gate includes startup; its only remaining ceiling is "this project has a
#     RESUME_SESSION.md"). Why a hook and not more prose: measurement across real usage found a small
#     single-digit percent of sessions ending with a reviewed diff, flat across weeks of added
#     doctrine - a rule fires when something checks it at an ACT, not when it is written.
ADVISORY=""
PENDING_TOKENS=""   # optional 2nd arg to adv_add: a SPEECH-ACT advisory's ack token (advisory-ack-guard.sh's Stop hook)
adv_add() { ADVISORY="${ADVISORY:+$ADVISORY$NL}$1"; [ -n "${2:-}" ] && PENDING_TOKENS="${PENDING_TOKENS:+$PENDING_TOKENS$NL}$2"; }

# M. Memory governance (2026-09): MEMORY.md index-size advisory. Deliberately placed HERE,
#    before both the SOURCE gate (the case statement below, which now restores on startup too but still
#    exits early on any OTHER/unknown source) and the no-RESUME early exit (the "$F" check further
#    down) - it rides ADVISORY/STAMP_LINE, which reaches every exit path in this script AFTER the
#    project stand-down at the top (a project shipping its own .claude/hooks/load-resume.sh already
#    exits before this point, same as every other block here - see that stand-down's own comment). The
#    advisory this replaces sat inside the lifecycle-threshold block below, which fires ONLY in a
#    project that already has a RESUME_SESSION.md - so a project's first sessions (no RESUME yet) never
#    saw a breached MEMORY.md until now. Adds a byte check alongside the existing line/file-count checks -
#    Claude Code's own read-time load cap for MEMORY.md (memory.md:401 warns at WRITE time when a Claude
#    edit pushes it over; this is the SessionStart-time equivalent, catching an out-of-band edit a human
#    editor or a restore made). 25000 bytes, not 25600: matches context-map.sh's own MEMORY.md byte cap
#    (scripts/context-map.sh, the "b. auto-memory index" section) rather than inventing a second number
#    for the same documented "25KB" figure. Kill switch checked first, before any read.
#
#    Memory-dir derivation: Claude Code shares ONE auto-memory directory per git repository - every
#    worktree and every subdirectory (memory.md: "derived from the git repository... shared across
#    worktrees and subdirectories") - so the dir is keyed off the git COMMON dir's parent, never off
#    $DIR (which is the launch/worktree path and differs per worktree). Same idiom context-map.sh already
#    uses for its own MEMORY.md row: `git rev-parse --path-format=absolute --git-common-dir`, then its
#    parent. Outside a git repo, $DIR (the project root) is used, matching memory.md's own fallback.
#    Deliberately a SEPARATE slug from the top-of-file "$slug" (which stays $DIR-based: it also keys the
#    session-transcript count in blocks A/F/G below, and Claude Code's transcript directory naming is not
#    claimed to be git-root-based - only the auto-memory directory is documented that way).
#
#    Edge cases, disclosed not built: (1) a git version that predates 2.31 rejects `--path-format` outright
#    - the command fails, `&&` short-circuits, and `mem_root_m` silently stays at its `$DIR` default, which
#    IS the documented outside-git fallback, so this degrades safely rather than erroring, but it means an
#    OLD git on a real repo behaves as if it were not a repo at all. (2) A SUBMODULE's common dir lives
#    under the SUPERPROJECT's `.git/modules/<name>`, so `dirname` of it does not land on the submodule's
#    own root - not verified against what Claude Code itself resolves for a submodule checkout. (3) A
#    `--separate-git-dir` clone has the same shape as (2) for the same reason (the common dir is not a
#    child of the worktree root). Neither (2) nor (3) is built or tested here.
#
#    Resolution now comes from lib/guard-mempath.sh, shared with memory-content-lint.sh. It closes the
#    gap this comment used to disclose: this block derived the dir from the git repo and ignored
#    `autoMemoryDirectory`, while the lint honoured `autoMemoryDirectory` and knew nothing about the git
#    derivation, so a relocated memory dir was linted but never sized, or sized but never linted. The
#    library is the superset of the two. `CLAUDE_CODE_PROJECT_DIR_NAME` (memory.md:369) is still not
#    read, by either side - see the library's own header for why.
LC_MEM_INDEX_MAX=80; LC_MEM_FILES_MAX=80; LC_MEM_BYTES_MAX=25000
if [ ! -f "$CLAUDE_DIR/agent-tiers/.state/off/memory-advisory" ]; then
  # A missing library falls back to the git derivation that was here before, so the advisory degrades
  # to its previous behaviour rather than disappearing.
  _MP_R="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)/lib/guard-mempath.sh"
  if [ -f "$_MP_R" ]; then
    . "$_MP_R"
    MEMDIR_M="$(guard_mem_dir "$CLAUDE_DIR" "$DIR")"
  else
    note "fail-open: lib/guard-mempath.sh missing - memory advisory uses the git derivation only"
    mem_root_m="$DIR"
    gcd_m="$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -n "$gcd_m" ] \
      && mem_root_m="$(dirname "$gcd_m")"
    mem_slug_m="$(printf '%s' "$mem_root_m" | tr -c 'A-Za-z0-9' '-')"
    MEMDIR_M="$CLAUDE_DIR/projects/$mem_slug_m/memory"
  fi
  if [ -f "$MEMDIR_M/MEMORY.md" ]; then
    m_breach=""
    m_n="$(( $(wc -l < "$MEMDIR_M/MEMORY.md" 2>/dev/null || echo 0) ))"
    [ "${m_n:-0}" -gt "$LC_MEM_INDEX_MAX" ] 2>/dev/null && m_breach="$m_breach memory-index(${m_n}>${LC_MEM_INDEX_MAX})"
    m_fc="$(ls -1 "$MEMDIR_M"/*.md 2>/dev/null | wc -l | tr -d ' ')"
    [ "${m_fc:-0}" -gt "$LC_MEM_FILES_MAX" ] 2>/dev/null && m_breach="$m_breach memory-files(${m_fc}>${LC_MEM_FILES_MAX})"
    m_b="$(( $(wc -c < "$MEMDIR_M/MEMORY.md" 2>/dev/null || echo 0) ))"
    [ "${m_b:-0}" -gt "$LC_MEM_BYTES_MAX" ] 2>/dev/null && m_breach="$m_breach memory-bytes(${m_b}b>${LC_MEM_BYTES_MAX}b)"
    [ -n "$m_breach" ] && adv_add "agent-tiers: MEMORY.md thresholds breached:$m_breach - consider /agent-tiers-gc"
  fi
fi

# A. The project layer was never wired. Measured across real usage: several repos with >=3 sessions
#    carried no agent-tiers.local.md, including the single heaviest delegation repo, and nothing ever
#    said so. `-e` not `-d` on .git: a worktree's .git is a FILE. That test is also what keeps this out
#    of scratch checkouts (claude_scratch.*, bare /tmp dirs), which are not repos at all.
if [ -e "$DIR/.git" ] && [ ! -f "$DIR/.claude/agent-tiers.local.md" ] &&
   [ ! -f "$CLAUDE_DIR/agent-tiers/.state/no-project-layer/$slug" ]; then
  n_sess="$(ls -1 "$CLAUDE_DIR/projects/$slug"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${n_sess:-0}" -ge 3 ] 2>/dev/null; then
    # The silence command carries its own mkdir: the parent dir does not exist until the first opt-out,
    # so a bare `touch` published here would ENOENT and the advisory would keep firing (review finding,
    # missed by the selfcheck because the fixture mkdir's it separately instead of running this text).
    adv_add "agent-tiers: $n_sess session(s) in this repo and no .claude/agent-tiers.local.md - the project layer was never wired. ASK before running /agent-tiers-init, do not self-run it. Silence for this repo: mkdir -p $CLAUDE_DIR/agent-tiers/.state/no-project-layer && touch $CLAUDE_DIR/agent-tiers/.state/no-project-layer/$slug" "/agent-tiers-init"
  fi
fi

# F. HOST-1's per-agent model/effort resolution was never probed for this project. Block A already
#    covers "the project layer does not exist at all"; this covers the narrower, previously-invisible
#    case where the layer IS wired (agent-tiers.local.md exists, so A stays silent) but nobody ever ran
#    the probe that fills its `probed_at:` frontmatter field (per templates/agent-tiers.local.md) - a
#    corpus sweep found real projects sitting in exactly this state indefinitely, since nothing else
#    ever checks it. Same n_sess>=3 noise floor and same self-heal shape as block A (a sentinel file,
#    not an env var - see block A's comment on why).
#    The probe exists for hosts not known to resolve model/effort correctly. The interactive native CLI is
#    treated as proven, so there the nag is noise: it stands down when the hook's own env carries
#    CLAUDE_CODE_ENTRYPOINT=cli (observed in a SessionStart hook env, 2026-09-13). `sdk-cli` does NOT
#    count as native: every `claude -p` driver reports it, third-party GUI hosts included.
#    F2. The host-independent half of init: no project brief skill, so every tier spawn here runs without
#    the project's commands and landmines. Fires only when the HOST-1 nag did not, so a non-native host
#    still gets one line pointing at init, which covers both.
if [ -e "$DIR/.git" ] && [ -f "$DIR/.claude/agent-tiers.local.md" ]; then
  n_sess_f="$(ls -1 "$CLAUDE_DIR/projects/$slug"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${n_sess_f:-0}" -ge 3 ] 2>/dev/null; then
    if [ "${CLAUDE_CODE_ENTRYPOINT:-}" != "cli" ] &&
       ! grep -q '^probed_at:' "$DIR/.claude/agent-tiers.local.md" 2>/dev/null &&
       [ ! -f "$CLAUDE_DIR/agent-tiers/.state/no-host-probe/$slug" ]; then
      adv_add "agent-tiers HOST-1: $n_sess_f session(s) in this repo and .claude/agent-tiers.local.md has no probed_at: - host/effort resolution was never probed here, so a silent GUI/host drift would go undetected. ASK before running /agent-tiers-init, do not self-run it (it rewrites this file - see block A above). Silence for this repo: mkdir -p $CLAUDE_DIR/agent-tiers/.state/no-host-probe && touch $CLAUDE_DIR/agent-tiers/.state/no-host-probe/$slug" "/agent-tiers-init"
    elif [ ! -f "$DIR/.claude/skills/tier-project-brief/SKILL.md" ] &&
         [ ! -f "$CLAUDE_DIR/agent-tiers/.state/no-brief-gap/$slug" ]; then
      adv_add "agent-tiers: $n_sess_f session(s) in this repo and no .claude/skills/tier-project-brief/SKILL.md - worker/advisor/reviewer spawns here run without the project's commands and landmines. ASK before running /agent-tiers-init --scaffold-only (step 6 scaffold, no host probe), do not self-run it. Silence for this repo: mkdir -p $CLAUDE_DIR/agent-tiers/.state/no-brief-gap && touch $CLAUDE_DIR/agent-tiers/.state/no-brief-gap/$slug" "/agent-tiers-init"
    fi
  fi
fi

# G. Unregistered injectors: an enabled plugin or a settings hook script with no row in the machine-local
#    layer registry, so nothing records why it loads or who wins when it conflicts with another layer.
#    Opt-in: silent when no registry exists, and when context-map.sh is missing. context-map.sh is resolved
#    from THIS script's own dir, so a sandboxed CLAUDE_CONFIG_DIR still reaches the real mapper. Ids come
#    from settings files a cloned repo can ship and land verbatim in model context, so they get the same
#    charset / length / count caps as the manifest globs above. Kill switch checked before anything runs:
#    .state/off/unregistered-injector.
#    Two silences, same shape as blocks A and F: per repo (.state/no-unregistered/<slug>) for a repo whose
#    project hook is known and deliberately unregistered, and machine-wide (.state/off/...). The mapper
#    runs with stdin detached: this block sits before the hook reads its own payload, so a mapper that ever
#    read stdin would swallow {session_id, source} and turn every compact/resume/startup into the
#    fail-closed unknown-source branch below (no restore at all).
if [ ! -f "$CLAUDE_DIR/agent-tiers/.state/off/unregistered-injector" ] &&
   [ ! -f "$CLAUDE_DIR/agent-tiers/.state/no-unregistered/$slug" ] &&
   [ -f "$CLAUDE_DIR/agent-tiers/.state/LAYERS.md" ]; then
  CM="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/context-map.sh"
  if [ -f "$CM" ]; then
    ui_out="$(CLAUDE_PROJECT_DIR="$DIR" sh "$CM" --unregistered </dev/null 2>/dev/null)"
    ui=""; ui_n=0; ui_more=""
    while IFS= read -r ui_id; do
      case "$ui_id" in ''|*[!A-Za-z0-9_.:@-]*) continue ;; esac
      [ "${#ui_id}" -le 64 ] || continue
      [ "$ui_n" -lt 12 ] || { ui_more="+"; continue; }
      ui="$ui $ui_id"; ui_n=$((ui_n + 1))
    done <<UI_EOF
$ui_out
UI_EOF
    [ -n "$ui" ] && adv_add "agent-tiers: $ui_n$ui_more injector(s) with no row in $CLAUDE_DIR/agent-tiers/.state/LAYERS.md:$ui - add a row (owner, why it loads, precedence class, kill switch) so a conflict has a recorded winner. Silence for this repo: mkdir -p $CLAUDE_DIR/agent-tiers/.state/no-unregistered && touch $CLAUDE_DIR/agent-tiers/.state/no-unregistered/$slug"
  fi
fi

# B. The kit repo sits unpushed. Fires in EVERY repo on purpose - kit state is machine-global and the
#    session that should push is usually not one running inside the kit. No "am I mid-kit-edit?"
#    condition: a SessionStart hook cannot interrupt an edit in the session making it.
if [ -e "$KIT/.git" ]; then
  kit_ahead="$(git -C "$KIT" rev-list --count '@{u}..HEAD' 2>/dev/null)"
  case "${kit_ahead:-}" in ''|*[!0-9]*) kit_ahead=0 ;; esac
  [ "$kit_ahead" -gt 0 ] 2>/dev/null &&
    adv_add "agent-tiers kit: $kit_ahead commit(s) unpushed locally - push before this session ends, or say so (git -C $KIT log --oneline '@{u}..HEAD')"
fi

# C. MAINT-6's band-dial falsifier trial has a hard cut-date, and the card itself predicts the tally
#    stops being appended before it arrives (it did - last append 2026-08-04, verified). The date is
#    PARSED out of the card, never copied here: one source, so moving the date moves this with it.
MAINT_CARD="$KIT/skills/agent-tiers/cards/MAINT.md"
cut_date="$(grep -oE 'Hard cut-date: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$MAINT_CARD" 2>/dev/null | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')"
if [ -n "${cut_date:-}" ]; then
  cut_s="$(date -d "$cut_date" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$cut_date" +%s 2>/dev/null)"
  now_s="$(date +%s 2>/dev/null)"
  if [ -n "${cut_s:-}" ] && [ -n "${now_s:-}" ]; then
    cut_days=$(( (cut_s - now_s) / 86400 ))
    if [ "$cut_days" -le 21 ]; then
      if [ "$cut_days" -lt 0 ]; then cut_when="passed $(( -cut_days )) day(s) ago"; else cut_when="is $cut_days day(s) away"; fi
      cut_stale=""
      if [ ! -f "$KIT/.state/band-tally.md" ]; then
        cut_stale=" and .state/band-tally.md does not exist at all, so the falsifier certainly never ran"
      elif [ -n "$(find "$KIT/.state/band-tally.md" -mtime +14 -print -quit 2>/dev/null)" ]; then
        cut_stale=" and .state/band-tally.md has not been appended in over 14 days, so the falsifier may have FAILED TO RUN"
      fi
      # The stand-down has to be NAMED: unlike the others this one does not self-heal (A has a sentinel,
      # B clears on a push, D on a re-install), and with no lower bound on cut_days it would otherwise
      # fire forever once the date passes - the permanently-on line that trains a Lead to ignore all four.
      adv_add "agent-tiers MAINT-6: the band-dial cut-date $cut_date $cut_when$cut_stale - read MAINT-6's failed-to-run fallback BEFORE deciding, not after. Once decided, move or remove the Hard cut-date line in cards/MAINT.md to stand this down."
    fi
  fi
fi

# D. A flat install's slash-commands go stale against the kit. MAINT-5 says "re-run install-flat.sh after
#    any commands/* change" and nothing checked it: verified 2026-08-23, the installed /agent-tiers-gc
#    and /agent-tiers-init still pointed at a skill renamed the day before. An mtime compare, not a diff -
#    the installed copies are BAKED (${CLAUDE_PLUGIN_ROOT} expanded to an absolute path), so they never
#    compare equal anyway. No-op on a plugin install, where no baked copies exist. Known ceiling: any git
#    operation that rewrites a commands/*.md with no net content change (stash pop, checkout, a branch
#    round-trip) bumps its mtime and fires this. Bounded on purpose - the stand-down is one idempotent
#    install-flat.sh run, which rewrites every baked copy unconditionally and re-orders the mtimes.
if [ -d "$KIT/commands" ]; then
  newest_installed="$(ls -t "$CLAUDE_DIR/commands"/agent-tiers-*.md 2>/dev/null | head -1)"
  if [ -n "${newest_installed:-}" ] &&
     [ -n "$(find "$KIT/commands" -name '*.md' -newer "$newest_installed" -print -quit 2>/dev/null)" ]; then
    adv_add "agent-tiers: kit commands/*.md are newer than the flat-installed copies in $CLAUDE_DIR/commands - re-run scripts/install-flat.sh, the installed slash-commands are stale."
  fi
fi

# E. Doc-lifecycle (2026-08-29): private notes can accumulate closed docs with no terminal state.
#    NOT a speech-act (single adv_add arg, no ack token) - purely informational, never blocks.
#    Composed from doc-lifecycle-check.sh's own CAPPED --summary output ONLY, never the full list -
#    same "a project-controlled filename lands verbatim in model context" discipline as every
#    globbed block above; that script does its own charset/length/row-5 filtering on every name it
#    surfaces. Gated on this being a git repo at all (same `-e "$DIR/.git"` test as block A) so a
#    scratch checkout never runs it.
#    PRIVATE-NOTES findings ONLY, deliberately - unlike A-D this pass has no stand-down of its own,
#    and the tracked-docs pass's own finding is BY DESIGN not something a Lead may act on (the
#    skill and the script both forbid auto-untracking), so surfacing it here would fire every
#    session, forever, in any repo that keeps a tracked docs/plans/ or reviews/ file on purpose -
#    the exact "permanently-on line that trains a Lead to ignore it" block C's own comment warns
#    against (opus reviewer, R2). Private-notes findings DO self-heal (fixing the STATUS line or
#    archiving the doc clears them), so they alone are safe to nudge on. The tracked-docs verdict
#    stays available via `doc-lifecycle-check.sh` standalone and `/agent-tiers:doctor` step 4e,
#    where a human is actually looking.
DLC="$KIT/scripts/doc-lifecycle-check.sh"
if [ -e "$DIR/.git" ] && [ -f "$DLC" ]; then
  dlc_out="$(cd "$DIR" 2>/dev/null && sh "$DLC" --summary 2>/dev/null)"
  dlc_hits="$(printf '%s' "${dlc_out:-}" | grep -v '^doc-lifecycle: 0 ' | grep -v '^doc-lifecycle: no notes dir' \
    | grep -v 'tracked working-doc-shaped' | grep -v '^doc-lifecycle: tracked,')"
  [ -n "$dlc_hits" ] && adv_add "$dlc_hits"
fi

# P. Host-limit falsifier (2026-10-11): HOST_CTX_MAX below is a number read out of the host's bundle, and
#    nothing else notices if a host update moves it. The host leaves its own evidence when it does: an
#    over-limit hook output is saved as <transcript bucket>/<session>/tool-results/hook-*-additionalContext.txt
#    and the model sees only a preview. So: any such file whose content is THIS hook's restore, written
#    after this script last changed, means the budget is too big for the real limit. Stateless on
#    purpose: it repeats on every start until the script is edited (the fix touches this file, which
#    resets the mtime comparison). Fail-open: no bucket, no find, or an unresolvable self path = silent.
#    Only a file of at most HOST_CTX_MAX bytes counts: one that small, persisted anyway, proves the real
#    limit is lower. A bigger one proves only that an inject went over budget, which an older kit
#    version (its files can carry a tag-time mtime older than its persisted restores) or a starved
#    budget also produce, and "lower HOST_CTX_MAX" would be the wrong fix for both. Disclosed false
#    negative: a multi-byte inject over 10000 bytes but under 10000 UTF-16 units is skipped too.
HOST_CTX_MAX=10000
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
if [ -f "$SELF" ] && [ -d "$CLAUDE_DIR/projects/$slug" ]; then
  p_hits=0; p_last=""
  p_list="$(find "$CLAUDE_DIR/projects/$slug" -mindepth 3 -maxdepth 3 -type f \
      -path '*/tool-results/hook-*-additionalContext.txt' -newer "$SELF" 2>/dev/null | head -50)"
  while IFS= read -r p_f; do
    [ -n "$p_f" ] || continue
    p_sz="$(wc -c < "$p_f" 2>/dev/null | tr -d ' ')"
    [ "${p_sz:-0}" -le "$HOST_CTX_MAX" ] 2>/dev/null || continue
    case "$(head -c 64 "$p_f" 2>/dev/null)" in
      "Restored working-state from RESUME_SESSION.md"*) p_hits=$((p_hits + 1)); p_last="$p_f" ;;
    esac
  done <<P_EOF
$p_list
P_EOF
  [ "$p_hits" -gt 0 ] && adv_add "agent-tiers: the host saved this hook's own restore to a file $p_hits time(s) since resume-inject.sh last changed (e.g. $p_last, $(wc -c < "$p_last" | tr -d ' ') bytes), so that session saw only a preview of it. HOST_CTX_MAX in resume-inject.sh is above the host's real inline limit: lower it."
fi

STAMP_LINE="$STAMP"
STAMP_LINE="${STAMP_LINE:+$STAMP_LINE$NL}$MANIFEST"
STAMP_LINE="${STAMP_LINE}${ADVISORY:+$NL$ADVISORY}"

INPUT="$(cat 2>/dev/null || true)"

# SESSION_ID parsed here (not just before the session-prefs block below) because it now has a SECOND
# consumer that must see the plain-startup path too: an observed session (the arrival-advisory swallow
# incident) WAS a plain startup, so a speech-act advisory's pending ack-token has to reach
# advisory-ack-guard.sh even when the case-statement below exits before session prefs are ever read.
# Validate BEFORE it becomes a path component (F-12): this id is concatenated into a file path, so a
# `../`-style id would turn a SessionStart hook into an arbitrary-file read/write. Claude session ids are
# UUIDs: accept only [A-Za-z0-9._-], reject the dot-only names that would name a directory.
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "${SESSION_ID:-}" in
  *[!A-Za-z0-9._-]* | '.' | '..') SESSION_ID="" ;;
esac
if [ -n "${SESSION_ID:-}" ]; then
  PENDING_DIR="$CLAUDE_DIR/agent-tiers/.state/advisory-pending"
  if [ -n "${PENDING_TOKENS:-}" ]; then
    { mkdir -p "$PENDING_DIR" && printf '%s\n' "$PENDING_TOKENS" > "$PENDING_DIR/$SESSION_ID"; } 2>/dev/null || true
  else
    # No speech-act advisory this run (e.g. the condition resolved since a prior compact/resume in the
    # same session) - clear any stale pending file so advisory-ack-guard.sh does not keep blocking on it.
    rm -f "$PENDING_DIR/$SESSION_ID" 2>/dev/null || true
  fi
  # default 7 (AGENT_TIERS_STATE_DAYS), validated: non-digit, 0, or over 3650 silently falls back to 7.
  days="${AGENT_TIERS_STATE_DAYS:-7}"; case "$days" in ''|*[!0-9]*) days=7 ;; esac
  [ "$days" -gt 0 ] 2>/dev/null && [ "$days" -le 3650 ] 2>/dev/null || days=7
  { [ -d "$PENDING_DIR" ] && find "$PENDING_DIR" -type f -mtime "+$days" -delete; } 2>/dev/null || true
fi

# Default is "unknown", not "startup": a plain startup now restores the handoff, so defaulting a
# no-jq or malformed/empty payload to "startup" would restore it too, when the fail-closed branch
# below is supposed to be what fires when the source cannot actually be read.
SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null || echo unknown)"
case "$SOURCE" in
  compact|resume|clear|startup) ;;
  *)
    # Unknown/other source: fail closed, no resume body - only the version stamp / manifest ride
    # out here, since they have no other arrival point.
    if [ -n "$STAMP_LINE" ]; then
      if command -v jq >/dev/null 2>&1; then
        jq -n --arg ctx "$STAMP_LINE" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
      else
        printf '%s\n' "$STAMP_LINE"
      fi
    fi
    GUARD_TRACE_OPEN=0; note "end [pid=$$] done=1"
    exit 0
    ;;
esac

# --- per-session prefs (v3): re-inject session-scoped choices (e.g. code-engine) so they survive
#     compact/resume. Keyed by session_id (from the hook's stdin JSON), NEVER by repo - multiple
#     Leads may run concurrently on one repo. The Lead writes the file when a pref gate fires:
#       ~/.claude/agent-tiers/.state/session-prefs/<session-id>   e.g. "code-engine: codex (set ...)"
#     A /clear mints a new session id, so cleared chats correctly start pref-less. Needs jq; without
#     it prefs are skipped (the Lead just re-asks). Files older than default 7 days
#     (AGENT_TIERS_STATE_DAYS) are GC'd opportunistically.
#     SESSION_ID is already parsed + F-12-validated above (moved there so the speech-act pending-token
#     write reaches the plain-startup path too, not just compact/resume/clear).
PREFS_DIR="$CLAUDE_DIR/agent-tiers/.state/session-prefs"
PREF=""
if [ -n "${SESSION_ID:-}" ] && [ -f "$PREFS_DIR/$SESSION_ID" ]; then
  PREF="session prefs (agent-tiers, this session): $(tr '\n' ' ' < "$PREFS_DIR/$SESSION_ID")"
fi
# default 7 (AGENT_TIERS_STATE_DAYS), validated: non-digit, 0, or over 3650 silently falls back to 7.
days="${AGENT_TIERS_STATE_DAYS:-7}"; case "$days" in ''|*[!0-9]*) days=7 ;; esac
[ "$days" -gt 0 ] 2>/dev/null && [ "$days" -le 3650 ] 2>/dev/null || days=7
{ [ -d "$PREFS_DIR" ] && find "$PREFS_DIR" -type f -mtime "+$days" -delete; } 2>/dev/null || true

F="$DIR/RESUME_SESSION.md"
if [ ! -f "$F" ]; then
  # no handoff file, but a session pref and/or the version stamp may still need re-injecting
  NOPREF="${PREF}${PREF:+$NL}${STAMP_LINE}"
  GUARD_TRACE_OPEN=0; note "end [pid=$$] done=1"
  [ -n "$NOPREF" ] || exit 0
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$NOPREF" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
  else
    printf '%s\n' "$NOPREF"
  fi
  exit 0
fi
# RESUME_CAP_BYTES: the host (Claude Code) saves any hook additionalContext longer than HOST_CTX_MAX
# characters to a file and puts only a ~2000-byte preview in context (found in the CLI bundle as the
# hook-output persist threshold, 1e4, 2026-10-11; a 13.4 KB startup inject here arrived as the preview).
# So the cap is a BUDGET for this hook's whole output, not a fixed size for the handoff: HOST_CTX_MAX
# minus the session prefs and stamp/manifest/advisory lines that ride along, minus RESUME_RESERVE for the
# header, truncation note, lifecycle line and vcs line (the vcs line alone is row- and length-capped
# to well under 1 KB). Bytes are counted, and the host counts UTF-16 units, so the byte budget is never
# under-counted. Past the cap: inject the head, cut at the last whole line that fits, followed by one
# line naming the full file path to read for the rest; if even the FIRST line alone is over the cap,
# inject nothing and just name the path; if the cap is under 1024 because the other lines ate the budget,
# say that instead. If the host limit moves, this constant goes stale: block P
# above (the persisted-file probe) is what notices.
# The reserve covers lines whose size is known only later; two of them carry the project path (the
# truncation note names $F, the vcs line names its source file), so the path length is reserved twice
# plus slack, rather than assuming a short path.
RESUME_RESERVE=$((1536 + 3 * ${#DIR}))
extra_b="$(printf '%s%s' "$PREF" "$STAMP_LINE" | LC_ALL=C wc -c | tr -d ' ')"
RESUME_CAP_BYTES=$((HOST_CTX_MAX - RESUME_RESERVE - ${extra_b:-0}))
[ "$RESUME_CAP_BYTES" -gt 0 ] 2>/dev/null || RESUME_CAP_BYTES=0
rb="$(wc -c < "$F" 2>/dev/null | tr -d ' ')"
# Read and cap in ONE pass, not a separate `wc -c` size check followed by an uncapped `cat` - a
# concurrent write growing the file between those two reads would otherwise let content past the cap
# through. `LC_ALL=C` makes `length()` count BYTES, not characters - a cap meant to bound tokens/bytes
# sent to the model must not undercount a multi-byte UTF-8 line as fewer "characters" than bytes.
CONTENT="$(LC_ALL=C awk -v cap="$RESUME_CAP_BYTES" '{ n += length($0) + 1; if (n > cap) exit 3; print }' "$F")"
cap_rc=$?
if [ "$cap_rc" = 3 ] && [ "$RESUME_CAP_BYTES" -lt 1024 ]; then
  # Starved: the prefs, stamp, manifest and advisory lines left too little room for a useful head. Say
  # so, rather than blaming the handoff's first line. A handoff that fits whole still goes in whole.
  CONTENT="[handoff not injected: the session prefs, stamp, manifest and advisory lines already use ${extra_b:-?} bytes of this hook's ${HOST_CTX_MAX}-character budget. Read $F.]"
elif [ "$cap_rc" = 3 ]; then
  if [ -n "$CONTENT" ]; then
    CONTENT="${CONTENT}${NL}${NL}[handoff truncated: RESUME_SESSION.md is ${rb} bytes, over this hook's ${RESUME_CAP_BYTES}-byte cap, so only the head above (whole lines) was injected. Read $F for the rest.]"
  else
    # The cap was hit before a single whole line fit (the first line alone exceeds it) - there is no
    # "head above" to point at, so say so plainly instead of claiming one.
    CONTENT="[handoff not injected: RESUME_SESSION.md is ${rb} bytes and its first line alone exceeds this hook's ${RESUME_CAP_BYTES}-byte cap. Read $F.]"
  fi
fi

# --- lifecycle threshold advisory (cheap; appends ONE line when breached; mirrors doctor step 4d) ---
# One stated ceiling now: it arrives only when the project has a RESUME_SESSION.md at all (the
# no-handoff early exit above runs first) - it used to also require compact|resume|clear, but the
# SOURCE gate above now includes startup too. A project that breaches every threshold and has no
# handoff file is never told. MEMORY.md's own checks moved OUT of this block in 2026-09 (see block M
# above) precisely because they needed neither constraint - the resume/brief/plans checks below still
# legitimately need the RESUME_SESSION.md constraint, since none of them exist without one.
# Tunable constants - keep in sync with the agent-tiers SKILL.md / doctor thresholds.
LC_RESUME_MAX=70; LC_BRIEF_MAX=4096; LC_PLANS_MAX_KB=500
lc_breach=""
rl="$(( $(wc -l < "$F" 2>/dev/null || echo 0) ))"
[ "${rl:-0}" -gt "$LC_RESUME_MAX" ] 2>/dev/null && lc_breach="$lc_breach resume(${rl}>${LC_RESUME_MAX})"
BRIEF="$DIR/.claude/skills/tier-project-brief/SKILL.md"
if [ -f "$BRIEF" ]; then
  bb="$(( $(wc -c < "$BRIEF" 2>/dev/null || echo 0) ))"
  [ "${bb:-0}" -gt "$LC_BRIEF_MAX" ] 2>/dev/null && lc_breach="$lc_breach brief(${bb}b>${LC_BRIEF_MAX}b)"
fi
if [ -d "$DIR/docs/plans" ]; then
  pk="$(du -sk "$DIR/docs/plans" 2>/dev/null | cut -f1)"
  [ "${pk:-0}" -gt "$LC_PLANS_MAX_KB" ] 2>/dev/null && lc_breach="$lc_breach plans(${pk}KB>${LC_PLANS_MAX_KB}KB)"
fi
[ -n "$lc_breach" ] && CONTENT="${CONTENT}${NL}${NL}⚠ lifecycle thresholds breached:${lc_breach} - consider /agent-tiers-gc"

# --- VCS-policy arrival (2026-08-07): the dispositions live in kit-config.md / the project's
#     agent-tiers.local.md but never reached a Lead in-session - evidenced by a Lead nudging a commit of
#     RESUME_SESSION.md, which the policy AND the user's global gitignore both forbid. Surface the
#     never-commit list at the same arrival point as the handoff itself. Project policy wins over kit
#     defaults; fail-open (no source or unparsable -> no line). One stated ceiling now: it arrives only
#     when the project has a RESUME_SESSION.md at all (the no-handoff early exit above runs first) -
#     it used to also require compact|resume|clear, but the SOURCE gate above now includes startup too.
VCS_SRC="$DIR/.claude/agent-tiers.local.md"; VCS_KEY="vcs_policy"
if ! grep -q "^$VCS_KEY:" "$VCS_SRC" 2>/dev/null; then
  VCS_SRC="$CLAUDE_DIR/agent-tiers/kit-config.md"; VCS_KEY="vcs_defaults"
fi
VCS_LINE=""
if [ -f "$VCS_SRC" ]; then
  # Artifact names charset+length capped and row-capped: this file is PROJECT-controlled (a cloned repo
  # can ship one) and its tokens land verbatim in model context - same bar as the session-id guard above.
  vcs_never="$(awk -v key="$VCS_KEY" '
    $0 ~ "^"key":" {inblk=1; next}
    inblk && /^[^[:space:]#]/ {inblk=0}
    inblk && $2 ~ /^ignore/ && $1 ~ /^[A-Za-z0-9_.-]+:?$/ && length($1) <= 41 && n < 12 \
      {k=$1; sub(/:$/,"",k); out=out sep k; sep=", "; n++}
    END {print out}' "$VCS_SRC" 2>/dev/null)"
  [ -n "$vcs_never" ] && VCS_LINE="vcs policy ($VCS_KEY): NEVER commit or nudge-to-commit: ${vcs_never}. Full map: $VCS_SRC"
fi
[ -n "$VCS_LINE" ] && CONTENT="${CONTENT}${NL}${NL}${VCS_LINE}"

# --- throttle: when RESUME is UNCHANGED and was fully injected recently INTO THIS SESSION, emit a
#     1-line pointer instead of the whole handoff (avoids re-injecting 60+ lines on every rapid resume).
#     A `clear` wipes context, so it ALWAYS gets the full inject. State (hash+epoch+session) lives in the
#     kit dir; only a FULL inject updates it, so a periodic full refresh still happens every window.
#
#     The state is keyed by project AND session. It was project-only until 2026-08-04, which made two
#     sessions on ONE repo inside the window collide: the second was told "already injected ~Nm ago" and
#     silently got no handoff, which was FALSE for that context - the inject had gone to a different
#     session. Proven by execution, and parallel sessions on one repo are normal here. A missing/unusable
#     session id now suppresses NOTHING (fail toward injecting: a redundant handoff is cheap, a lost one
#     is not), and a legacy 2-field state file reads as a session mismatch, which is the same safe path.
STATE_DIR="$CLAUDE_DIR/agent-tiers/.state"
mkdir -p "$STATE_DIR" 2>/dev/null || true
STATE="$STATE_DIR/${slug}.resume"                       # $slug computed above (path→dashes)
HASH="$(cksum < "$F" 2>/dev/null | awk '{print $1"-"$2}')"
NOW="$(date +%s 2>/dev/null || echo 0)"
THROTTLE_SECONDS=600                                     # unchanged + within 10 min → pointer only
suppress=0
if [ "$SOURCE" != "clear" ] && [ -f "$STATE" ] && [ -n "${SESSION_ID:-}" ]; then
  last_hash="$(cut -d' ' -f1 "$STATE" 2>/dev/null)"
  last_ts="$(cut -d' ' -f2 "$STATE" 2>/dev/null)"
  last_sid="$(cut -d' ' -f3 "$STATE" 2>/dev/null)"
  if [ "$HASH" = "$last_hash" ] && [ "$SESSION_ID" = "${last_sid:-}" ] &&
     [ "$((NOW - ${last_ts:-0}))" -lt "$THROTTLE_SECONDS" ] 2>/dev/null; then
    suppress=1
  fi
fi

if [ "$suppress" = 1 ]; then
  mins="$(( (NOW - ${last_ts:-0}) / 60 ))"
  PTR="↻ RESUME_SESSION.md unchanged and already injected ~${mins}m ago - not re-injecting the full handoff; re-read the file if this context has lost it."
  [ -n "$lc_breach" ] && PTR="${PTR}${NL}⚠ lifecycle thresholds breached:${lc_breach} - consider /agent-tiers-gc"
  # The vcs line rides the pointer too: a compact inside the window discards the context that already
  # had it, which is exactly the moment the policy needs to re-arrive.
  [ -n "$VCS_LINE" ] && PTR="${PTR}${NL}${VCS_LINE}"
  [ -n "$PREF" ] && PTR="${PTR}${NL}${PREF}"
  [ -n "$STAMP_LINE" ] && PTR="${PTR}${NL}${STAMP_LINE}"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$PTR" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
  else
    printf '%s\n' "$PTR"
  fi
  GUARD_TRACE_OPEN=0; note "end [pid=$$] done=1"
  exit 0
fi

# full inject: record state so the next UNCHANGED resume IN THIS SESSION within the window is
# throttled - EXCEPT on startup: a /compact minutes later in the same session just discarded this
# handoff from context, so it needs the FULL inject again, not an "already injected" pointer that
# assumes the context still has it.
[ "$SOURCE" = "startup" ] || printf '%s %s %s\n' "$HASH" "$NOW" "${SESSION_ID:-none}" > "$STATE" 2>/dev/null || true
[ -n "$PREF" ] && CONTENT="${CONTENT}${NL}${NL}${PREF}"
[ -n "$STAMP_LINE" ] && CONTENT="${CONTENT}${NL}${NL}${STAMP_LINE}"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "Restored working-state from RESUME_SESSION.md after '$SOURCE':${NL}${NL}${CONTENT}" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
  printf '%s\n\n%s\n' "===== RESUME_SESSION.md (agent-tiers handoff) =====" "$CONTENT"
fi
GUARD_TRACE_OPEN=0; note "end [pid=$$] done=1"
exit 0

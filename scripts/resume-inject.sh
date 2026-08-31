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
#   - Source-gate: RESUME CONTENT only restores on compact|resume|clear, NOT a fresh startup (CLAUDE.md
#     loads then) - but the version stamp + manifest fire on every source, startup included, since they
#     have no other arrival point.
#   - Structured hookSpecificOutput JSON when jq is present; raw-stdout fallback otherwise.
set -u
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"   # follow a relocated config dir (2nd account etc.)

# A project that wants to own resume-injection drops its own .claude/hooks/load-resume.sh;
# the global hook then stands down so it doesn't double-inject over the project's richer hook.
[ -f "$DIR/.claude/hooks/load-resume.sh" ] && exit 0

# Claude Code slugs projects/ dirs with replace(/[^a-zA-Z0-9]/g,"-") - verified against the CLI
# binary 2026-08-10, prompted by cold-review F9. Matching only `/` made the memory-threshold check
# silently read an empty dir for any project path containing a dot, underscore, or any other
# non-alphanumeric.
slug="$(printf '%s' "$DIR" | tr -c 'A-Za-z0-9' '-')"

# --- version stamp (2026-08-09): the "join key" any after-the-fact usage review needs to attribute a
#     session to an exact doctrine/card/def revision without inferring it from a date. Fires on EVERY
#     SessionStart source, startup included (unlike the resume-content restore below, which is
#     source-gated) - a plain new session is exactly the case a date-inferred join would otherwise have
#     to cover. Cheap (a handful of greps over files already on disk); any read failure fails open to an
#     empty stamp, never an error.
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
# The delegation doctrine itself (2026-08-23, retro run 3): SKILL.md + the 5 policy cards are the
# rule-bearing surface every scoped/measurable retro rubric row is written against, yet before this
# line the manifest carried none of it - 0 of 55 manifested sessions in that run's corpus could show
# whether the doctrine was actually loaded. Fixed set (not a glob): these six files are the kit's own
# skill, not project-controlled, so no charset/length/count cap applies (see the globbed blocks below
# for why THOSE need one - a project-shipped filename lands verbatim in model context, these do not).
mf_add '~/.claude/agent-tiers/skills/agent-tiers/SKILL.md' "$KIT/skills/agent-tiers/SKILL.md"
for _c in BOSS HOST MAINT ROUTE XLAB; do
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
#     line, so they reach a plain startup too (the lifecycle block cannot: it sits behind the
#     compact|resume|clear gate AND behind "this project has a RESUME_SESSION.md"). Why a hook and not
#     more prose: measurement across real usage found a small single-digit percent of sessions ending
#     with a reviewed diff, flat across weeks of added doctrine - a rule fires when something checks it
#     at an ACT, not when it is written.
ADVISORY=""
PENDING_TOKENS=""   # optional 2nd arg to adv_add: a SPEECH-ACT advisory's ack token (advisory-ack-guard.sh's Stop hook)
adv_add() { ADVISORY="${ADVISORY:+$ADVISORY$NL}$1"; [ -n "${2:-}" ] && PENDING_TOKENS="${PENDING_TOKENS:+$PENDING_TOKENS$NL}$2"; }

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

STAMP_LINE="$STAMP"
STAMP_LINE="${STAMP_LINE:+$STAMP_LINE$NL}$MANIFEST"
STAMP_LINE="${STAMP_LINE}${ADVISORY:+$NL$ADVISORY}"

INPUT="$(cat 2>/dev/null || true)"

# SESSION_ID parsed here (not just before the session-prefs block below) because it now has a SECOND
# consumer that must see the plain-startup path too: session e824d942 (the arrival-advisory swallow
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
  { [ -d "$PENDING_DIR" ] && find "$PENDING_DIR" -type f -mtime +7 -delete; } 2>/dev/null || true
fi

SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo startup)"
case "$SOURCE" in
  compact|resume|clear) ;;
  *)
    # Plain startup: CLAUDE.md already loads then, so no resume content - but the version stamp /
    # manifest have no other arrival point on a fresh session, so they still ride out here.
    if [ -n "$STAMP_LINE" ]; then
      if command -v jq >/dev/null 2>&1; then
        jq -n --arg ctx "$STAMP_LINE" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
      else
        printf '%s\n' "$STAMP_LINE"
      fi
    fi
    exit 0
    ;;
esac

# --- per-session prefs (v3): re-inject session-scoped choices (e.g. code-engine) so they survive
#     compact/resume. Keyed by session_id (from the hook's stdin JSON), NEVER by repo - multiple
#     Leads may run concurrently on one repo. The Lead writes the file when a pref gate fires:
#       ~/.claude/agent-tiers/.state/session-prefs/<session-id>   e.g. "code-engine: codex (set ...)"
#     A /clear mints a new session id, so cleared chats correctly start pref-less. Needs jq; without
#     it prefs are skipped (the Lead just re-asks). Files older than 7 days are GC'd opportunistically.
#     SESSION_ID is already parsed + F-12-validated above (moved there so the speech-act pending-token
#     write reaches the plain-startup path too, not just compact/resume/clear).
PREFS_DIR="$CLAUDE_DIR/agent-tiers/.state/session-prefs"
PREF=""
if [ -n "${SESSION_ID:-}" ] && [ -f "$PREFS_DIR/$SESSION_ID" ]; then
  PREF="session prefs (agent-tiers, this session): $(tr '\n' ' ' < "$PREFS_DIR/$SESSION_ID")"
fi
{ [ -d "$PREFS_DIR" ] && find "$PREFS_DIR" -type f -mtime +7 -delete; } 2>/dev/null || true

F="$DIR/RESUME_SESSION.md"
if [ ! -f "$F" ]; then
  # no handoff file, but a session pref and/or the version stamp may still need re-injecting
  NOPREF="${PREF}${PREF:+$NL}${STAMP_LINE}"
  [ -n "$NOPREF" ] || exit 0
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$NOPREF" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
  else
    printf '%s\n' "$NOPREF"
  fi
  exit 0
fi
CONTENT="$(cat "$F")"

# --- lifecycle threshold advisory (cheap; appends ONE line when breached; mirrors doctor step 4d) ---
# Two stated ceilings, the same pair the VCS-policy block below carries: it arrives only on
# compact|resume|clear (a fresh-startup session never reaches here), and only when the project has a
# RESUME_SESSION.md at all (the no-handoff early exit above runs first). A project that breaches every
# threshold and has no handoff file is never told.
# Tunable constants - keep in sync with the agent-tiers SKILL.md / doctor thresholds.
LC_MEM_INDEX_MAX=80; LC_MEM_FILES_MAX=80; LC_RESUME_MAX=70; LC_BRIEF_MAX=4096; LC_PLANS_MAX_KB=500
lc_breach=""
MEMDIR="$CLAUDE_DIR/projects/$slug/memory"
if [ -f "$MEMDIR/MEMORY.md" ]; then
  n="$(wc -l < "$MEMDIR/MEMORY.md" 2>/dev/null || echo 0)"
  [ "${n:-0}" -gt "$LC_MEM_INDEX_MAX" ] 2>/dev/null && lc_breach="$lc_breach memory-index(${n}>${LC_MEM_INDEX_MAX})"
  fc="$(ls -1 "$MEMDIR"/*.md 2>/dev/null | wc -l | tr -d ' ')"
  [ "${fc:-0}" -gt "$LC_MEM_FILES_MAX" ] 2>/dev/null && lc_breach="$lc_breach memory-files(${fc}>${LC_MEM_FILES_MAX})"
fi
rl="$(wc -l < "$F" 2>/dev/null || echo 0)"
[ "${rl:-0}" -gt "$LC_RESUME_MAX" ] 2>/dev/null && lc_breach="$lc_breach resume(${rl}>${LC_RESUME_MAX})"
BRIEF="$DIR/.claude/skills/tier-project-brief/SKILL.md"
if [ -f "$BRIEF" ]; then
  bb="$(wc -c < "$BRIEF" 2>/dev/null || echo 0)"
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
#     defaults; fail-open (no source or unparsable -> no line). Two stated ceilings: it arrives only on
#     compact|resume|clear (a fresh-startup session has no arrival for it), and only when the project
#     has a RESUME_SESSION.md at all (the no-handoff early exit above runs first).
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
  exit 0
fi

# full inject → record state so the next UNCHANGED resume IN THIS SESSION within the window is throttled
printf '%s %s %s\n' "$HASH" "$NOW" "${SESSION_ID:-none}" > "$STATE" 2>/dev/null || true
[ -n "$PREF" ] && CONTENT="${CONTENT}${NL}${NL}${PREF}"
[ -n "$STAMP_LINE" ] && CONTENT="${CONTENT}${NL}${NL}${STAMP_LINE}"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "Restored working-state from RESUME_SESSION.md after '$SOURCE':${NL}${NL}${CONTENT}" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
  printf '%s\n\n%s\n' "===== RESUME_SESSION.md (agent-tiers handoff) =====" "$CONTENT"
fi
exit 0

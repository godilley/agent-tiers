#!/usr/bin/env bash
# kit-scope: shared
# agent-tiers - FLAT install for a Claude Code host that does NOT load .claude plugins
# (e.g. the CodeMoss bundled SDK). It exposes the kit as the plain files such hosts DO scan:
#   ~/.claude/skills/<name>/         (symlink -> canonical)
#   ~/.claude/agents/<name>.md       (symlink -> canonical)
#   ~/.claude/commands/agent-tiers-<name>.md  (copy, ${CLAUDE_PLUGIN_ROOT} baked to an abs path,
#                                              renamed to dodge the built-in /init clash)
# and wires the kit's hooks into settings.json through the external-integrations seam (ledger-backed,
# idempotent; PreToolUse guard rows are consent-only via --with-<id> - see section 4).
#
# Canonical source of truth stays ~/.claude/agent-tiers/ - edit there, re-run this to re-flatten.
# The plugin's hooks/hooks.json wires every kit hook (gated by the plugin options), so a plugin install
# needs no flat install; this script refuses to install while an agent-tiers plugin is enabled (and from
# a plugin-cache copy), since each hook would run twice. `--unwire-only` removes kit hook rows from
# settings.json and their ledger rows (with the usual settings backup and prune) and links, copies or
# creates nothing. The enabled-plugin check reads the profile settings.json and
# managed settings files only; a plugin enabled at project scope (<repo>/.claude/settings.json) is not
# checked. Idempotent + safe to re-run.
#
# AGENT_TIERS_TEST_SKIP_HOOK_PROOF=1 is a kit-internal TEST-ONLY knob, read from the environment only
# (no CLI flag, no options.tsv row): the kit's own installer selfchecks set it so they do not re-run
# every wired hook's selfcheck on each of their many installs. Risk if a user exports it: a real install
# wires hooks without proving any of them fires on this host (a guard broken by this host's shell or
# tools is wired silently, the "wired" vs "fires" gap the proof step exists to close); the installer
# prints a SKIPPED line so the run is not silent.
#
# Exit codes: 0 = done (a failed post-wire hook selfcheck, reported as "<id> selfcheck FAILED", is a
# warning and still exits 0, by design: the wiring itself succeeded); 1 = refused or failed (usage error, unknown id, plugin
# refusal, probe refusal, --check found stale copies, or an install that finished but could not
# complete a settings.json step: a failed wire, rewire or --without-<id> removal, or hook wiring skipped
# because settings.json is invalid JSON or the backup names for this second were exhausted). A failed step is also reported on stderr at the end.
set -eu

# Managed settings dirs the plugin-enabled check reads (same form as kit-gate's _kg_managed).
IF_MANAGED='/etc/claude-code:/Library/Application Support/ClaudeCode'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"          # .../.claude/agent-tiers   (canonical kit source)
CLAUDE_DIR="$(cd "$ROOT/.." && pwd)"              # .../.claude               (kit's own parent)
REL="$(basename "$ROOT")"                          # agent-tiers  (for relative symlinks)

# TARGET = the profile we are installing INTO. Claude Code treats CLAUDE_CONFIG_DIR as the whole config
# root (verified: with it set, the CLI builds .claude.json / projects / sessions there and starts logged
# OUT - auth is per-profile), which is how a second account runs alongside the personal one. So EVERY
# artifact must follow it: skills, agents, commands AND settings.json. Sending only the hooks there was
# a split install - the second profile got the guards but none of the tiers.
# The kit itself stays canonical at ROOT and is SHARED by every profile; only the flattened view moves.
TARGET="${CLAUDE_CONFIG_DIR:-$CLAUDE_DIR}"
mkdir -p "$TARGET" 2>/dev/null || true
# Canonicalise before ANY comparison: every branch below turns on TARGET == CLAUDE_DIR, and a trailing
# slash or a relative/symlinked spelling of the SAME directory would otherwise be treated as a second
# profile - creating a duplicate ledger for one settings.json, which then disagrees with itself.
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "install-flat: CLAUDE_CONFIG_DIR '$TARGET' is not a usable directory" >&2; exit 1; }
# Relative links are only meaningful when the kit sits inside the target; across profiles they must be
# absolute or they would resolve against the wrong root.
if [ "$TARGET" = "$CLAUDE_DIR" ]; then LINKBASE="../$REL"; else LINKBASE="$ROOT"; fi

# The integrations ledger describes ONE settings.json, so it is per-profile even though the kit is
# shared: a single id-keyed file would let a second profile's install silently overwrite the first
# profile's rows, and doctor would then report that profile's live hooks as foreign. The default
# profile keeps the original path (no migration); other profiles get a path-derived sibling.
STATE_DIR="$ROOT/.state"
if [ "$TARGET" = "$CLAUDE_DIR" ]; then
  LEDGER="$STATE_DIR/integrations.json"
else
  LEDGER="$STATE_DIR/integrations.$(printf '%s' "$TARGET" | tr -c 'A-Za-z0-9' '-' | sed -e 's/^-*//' -e 's/-*$//').json"
fi

# id;class;event;matcher;timeout   (script = scripts/<id>.sh; empty matcher = none). Derived from the
# `hook` rows of install/options.tsv (the one hook list): class is `core` when the row's group is
# `core`, else `consent`. Defined up here, before flag parsing, so an unknown id can be rejected before
# the install touches anything. Missing/unreadable file, zero hook rows, a hook row without exactly 7
# fields (the 7th, `requires`, is `-` or a comma list of hook ids, each a known hook id other than
# the row's own) or with a non-numeric timeout, or a `;` inside a field is a hard error here, before
# any write.
# The requires column is validated here but not enforced at wire time (precompact-guard's own probe does that).
# resume-inject's timeout is a ceiling, not a cost: on Windows (Git Bash) one startup run measured 19 s
# (likely per-file process spawns in the stamp/manifest; not profiled), and 10 s dropped its output
# silently. Re-running this installer does NOT update the timeout on an already-wired row (see the
# drift note further down), so existing installs need the value changed in settings.json by hand.
OPTIONS_TSV="$ROOT/install/options.tsv"
[ -r "$OPTIONS_TSV" ] || { echo "install-flat: $OPTIONS_TSV missing or unreadable - cannot derive the hook rows" >&2; exit 1; }
HOOK_ROWS="$(awk -F'\t' '
  $1 == "hook" {
    if (NF != 7 || $6 !~ /^[0-9]+$/) { print "install-flat: options.tsv:" NR ": hook row needs 7 fields and a numeric timeout" > "/dev/stderr"; bad = 1; exit }
    if ($7 !~ /^(-|[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*)$/) { print "install-flat: options.tsv:" NR ": hook row requires column is not - or a comma list of hook ids" > "/dev/stderr"; bad = 1; exit }
    ids[$2] = 1; rq[NR] = $7; rid[NR] = $2
    for (i = 1; i <= NF; i++) if (index($i, ";")) { print "install-flat: options.tsv:" NR ": hook row field contains ;" > "/dev/stderr"; bad = 1; exit }
    printf "%s;%s;%s;%s;%s\n", $2, ($3 == "core" ? "core" : "consent"), $4, $5, $6
  }
  END {
    if (bad) exit 1
    for (n in rq) { m = split(rq[n], a, ","); for (j = 1; j <= m; j++) {
      if (a[j] == "-") continue
      if (a[j] == rid[n]) { print "install-flat: options.tsv:" n ": hook row requires itself" > "/dev/stderr"; exit 1 }
      if (!(a[j] in ids)) { print "install-flat: options.tsv:" n ": hook row requires unknown hook id " a[j] > "/dev/stderr"; exit 1 } } }
  }' "$OPTIONS_TSV")" || exit 1
[ -n "$HOOK_ROWS" ] || { echo "install-flat: $OPTIONS_TSV has no hook rows" >&2; exit 1; }
KNOWN_IDS="$(printf '%s\n' "$HOOK_ROWS" | cut -d';' -f1 | tr '\n' ' ')"

has_id() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Flags (external-integrations seam, section 4): --with-<id> wires a consent hook row,
# --without-<id> removes/skips a kit-owned row. Ids = the hook script name minus .sh.
# An unknown id is a hard error, not a silent no-op: a typo'd --with-<guard> would otherwise
# report a successful install with a consent-class control silently absent (review 2026-08-10).
# --force-with-<id> wires the row WITHOUT running its support probe (below) - an escape hatch for a
# probe false negative, never a way to skip the unknown-id/missing-script checks, which still apply.
WITH="" WITHOUT="" HSCOPE_ARG="" FORCE="" UNWIRE=0
for arg in "$@"; do
  case "$arg" in
    --with-*)    WITH="$WITH ${arg#--with-}" ;;
    --force-with-*) fw="${arg#--force-with-}"; WITH="$WITH $fw"; FORCE="$FORCE $fw" ;;
    --without-*) WITHOUT="$WITHOUT ${arg#--without-}" ;;
    # hygiene-commit-guard's unstaged-scan scope (bundle-9 W3-2). A POSTURE choice, not a wiring one, so
    # it is recorded as config rather than a hook row: `repo` (default) scans every unstaged tracked
    # change in the repo - closes the class structurally, but an unrelated dirty file can deny a commit
    # that never touched it; `narrow` scans only what THIS command stages, which re-opens the
    # `git add X && git commit` gap in one call. Written to kit-config.md so it applies to every repo
    # kit-wide, for every repo; a single repo overrides it in its own .claude/agent-tiers.local.md. Not passing
    # the flag changes nothing - an install never silently loosens an existing guard.
    --hygiene-scope=*) HSCOPE_ARG="${arg#--hygiene-scope=}"
      case "$HSCOPE_ARG" in
        repo|narrow) ;;
        *) echo "install-flat: --hygiene-scope must be repo or narrow (got '$HSCOPE_ARG')"; exit 1 ;;
      esac ;;
    --check) CHECK_ONLY=1 ;;
    --unwire-only) UNWIRE=1 ;;
    *) echo "usage: install-flat.sh [--check] [--with-<hook-id>] [--force-with-<hook-id>] [--without-<hook-id>] [--hygiene-scope=repo|narrow] | --unwire-only [--without-<hook-id>]"; exit 1 ;;
  esac
done
if [ "$UNWIRE" = 1 ]; then
  if [ -n "$WITH" ] || [ -n "$HSCOPE_ARG" ] || [ "${CHECK_ONLY:-0}" = 1 ]; then
    echo "install-flat: --unwire-only combines only with --without-<hook-id> (not --with-*, --force-with-*, --hygiene-scope or --check)"; exit 1
  fi
  [ -n "$WITHOUT" ] || WITHOUT=" $KNOWN_IDS"
fi
for w in $WITH $WITHOUT; do
  has_id "$w" "$KNOWN_IDS" || { echo "install-flat: unknown hook id '$w' - known ids: $KNOWN_IDS"; exit 1; }
done
# Same rule for a KNOWN id whose script is not in THIS kit copy (a bundle excludes export-ignored
# scripts such as kit-leak-guard): explicitly requesting it is the same "successful install, consent
# control silently absent" outcome the unknown-id error exists to prevent - so it hard-errors too, up
# front. An UNREQUESTED missing row is still soft-skipped in the wiring loop (a received bundle
# legitimately excludes them). Tier 1 review T1.4, 2026-08-16.
for w in $WITH; do
  [ -f "$ROOT/scripts/$w.sh" ] || { echo "install-flat: --with-$w requested but scripts/$w.sh is not in this kit copy (usually because it is kit-local and export-ignored in .gitattributes, e.g. kit-leak-guard; a partial checkout hits this too). Not installing: a consent control you asked for would otherwise be silently absent."; exit 1; }
done

# Plugin refusal (install modes only). The plugin's hooks/hooks.json already wires every kit hook, so a
# flat install while it is enabled (or from a plugin-cache copy) makes each hook run twice. Nothing is
# written. --check and --unwire-only run regardless.
if [ "${CHECK_ONLY:-0}" != 1 ] && [ "$UNWIRE" != 1 ]; then
  # (a) plugin-cache kit root: <P>/cache/<marketplace>/<plugin>/<version> with <P>/installed_plugins.json
  pr_r="$(cd "$ROOT" && pwd -P)"
  pr_root="$pr_r"; pr_v="${pr_r##*/}"; pr_r="${pr_r%/*}"; pr_p="${pr_r##*/}"; pr_r="${pr_r%/*}"; pr_m="${pr_r##*/}"; pr_r="${pr_r%/*}"
  case "$pr_r" in
    */cache)
      if [ -n "$pr_p" ] && [ -n "$pr_m" ] && [ -n "$pr_v" ] && [ -f "${pr_r%/cache}/installed_plugins.json" ]; then
        echo "install-flat: this kit copy is a Claude Code plugin install ($pr_root, plugin key $pr_p@$pr_m); kit-gate treats hooks run from this copy as plugin hooks (grouped hooks follow the plugin options, default off), every hook would run twice whenever the plugin is enabled, and the cache copy is replaced on a plugin update. Nothing written. Run install-flat.sh from a kit checkout instead, or configure the plugin through its options (pluginConfigs[\"$pr_p@$pr_m\"].options)." >&2
        exit 1
      fi ;;
  esac
  # (b) an agent-tiers plugin enabled in the profile's settings.json or a managed file (later wins)
  set --
  [ -f "$TARGET/settings.json" ] && [ -r "$TARGET/settings.json" ] && set -- "$TARGET/settings.json"
  pr_ifs="$IFS"; IFS=:; set -f
  for pr_md in $IF_MANAGED; do
    IFS="$pr_ifs"; set +f
    [ -f "$pr_md/managed-settings.json" ] && [ -r "$pr_md/managed-settings.json" ] && set -- "$@" "$pr_md/managed-settings.json"
    for pr_mf in "$pr_md"/managed-settings.d/*.json; do
      [ -f "$pr_mf" ] && [ -r "$pr_mf" ] && set -- "$@" "$pr_mf"
    done
    IFS=:; set -f
  done
  IFS="$pr_ifs"; set +f
  if [ "$#" -gt 0 ] && grep -qsF 'agent-tiers@' "$@"; then
    if ! command -v jq >/dev/null 2>&1; then
      echo "install-flat: cannot check whether agent-tiers is enabled as a Claude Code plugin: a settings file mentions agent-tiers@ and jq is not installed. Refusing (fail closed). Nothing written. Install jq and re-run." >&2
      exit 1
    fi
    pr_keys="$(jq -rs 'reduce .[] as $f ({}; . + (($f.enabledPlugins // {}) | with_entries(select(.value != null))))
      | to_entries[] | select((.key | startswith("agent-tiers@")) and .value == true) | .key' "$@" 2>/dev/null)" || {
      pr_why="is not valid JSON"
      for pr_f in "$@"; do jq . "$pr_f" >/dev/null 2>&1 || pr_bad=1; done
      [ "${pr_bad:-0}" = 1 ] || pr_why="has an enabledPlugins that is not a JSON object"
      echo "install-flat: cannot check whether agent-tiers is enabled as a Claude Code plugin: a settings file that mentions agent-tiers@ $pr_why (one of: $*). Refusing (fail closed). Nothing written." >&2
      exit 1
    }
    if [ -n "$pr_keys" ]; then
      pr_first=""
      # one key per line (a key may contain spaces), so read lines rather than word-splitting
      while IFS= read -r pr_k; do
        pr_file=""
        for pr_f in "$@"; do
          jq -e --arg k "$pr_k" '.enabledPlugins[$k] == true' "$pr_f" >/dev/null 2>&1 && pr_file="$pr_f"
        done
        [ -n "$pr_first" ] || pr_first="$pr_k"
        if [ "$pr_k" = "$pr_first" ]; then
          echo "install-flat: $pr_k is enabled as a Claude Code plugin (enabledPlugins in $pr_file). The plugin's hooks/hooks.json already wires every kit hook; wiring them into $TARGET/settings.json too would run each hook twice. Nothing written. To proceed: turn hook groups on or off through the plugin's options (pluginConfigs[\"$pr_k\"].options), or disable the plugin first (/plugin disable $pr_k) and re-run. To remove kit rows already wired in $TARGET/settings.json: install-flat.sh --unwire-only." >&2
        else
          echo "install-flat: also enabled: $pr_k (enabledPlugins in $pr_file)" >&2
        fi
      done <<PR_KEYS_EOF
$pr_keys
PR_KEYS_EOF
      exit 1
    fi
  fi
fi

# Support probe (`# kit-probe: yes` marker): before any settings.json write, ask each REQUESTED
# --with-<id> hook whether THIS host can actually support it. A hook depending on a HOST-STABLE
# fact (a binary on PATH, a sibling hook also wired) that wires anyway and only degrades silently
# at runtime reports a clean install of a guard that will never fire - worse than refusing up front.
# Convention: `sh scripts/<id>.sh --probe` does no side effects, reads no stdin, ignores the kill
# switch; exit 0 with no output = supported, exit 3 with a one-line reason on stdout = unsupported,
# any OTHER exit is also treated as unsupported (a probe that errors is not proof of support). A
# probe must judge HOST-stable facts only, never a per-session one (which terminal a future session
# runs in): notify.sh's own probe was corrected out of doing that - see its header.
# KIT_PROBE_WITH/KIT_PROBE_WITHOUT carry this install's full --with/--without lists, so a probe can
# depend on a SIBLING row also being requested (or REMOVED) in this same run (precompact-guard needs
# authorship-record, and must not be fooled by a same-run `--without-authorship-record` that a
# settings.json grep alone cannot see coming); KIT_PROBE_SETTINGS is the target settings.json, so a
# probe can check what is ALREADY wired there instead. --force-with-<id> (above) skips the probe
# entirely for that id - an escape hatch for a false negative, not a way around the unknown-id/
# missing-script checks above, which still ran first.
for w in $WITH; do
  has_id "$w" "$FORCE" && continue
  grep -q '^# kit-probe: yes$' "$ROOT/scripts/$w.sh" 2>/dev/null || continue
  # `if probe_out=$(...)` (not a bare assignment) so a nonzero probe exit is TESTED, not a bare
  # failing simple command - under this script's `set -e`, the untested form aborts the whole
  # script right here (silently, with the probe's own exit code) before the refusal message below
  # ever runs.
  if probe_out="$(KIT_PROBE_WITH="$WITH" KIT_PROBE_WITHOUT="$WITHOUT" KIT_PROBE_SETTINGS="$TARGET/settings.json" sh "$ROOT/scripts/$w.sh" --probe 2>&1)"; then
    probe_rc=0
  else
    probe_rc=$?
  fi
  if [ "$probe_rc" != 0 ]; then
    reason="$probe_out"
    [ -n "$reason" ] || reason="probe exited $probe_rc with no reason given"
    echo "install-flat: refusing --with-$w: $reason"
    exit 1
  fi
done

# --check: are the BAKED command copies still what the canonical sources would produce? Commands are the
# only baked artifact (skills and agents are symlinks, so they cannot go stale); editing a canonical
# command and forgetting to re-run this installer ships a stale copy, and nothing detects it. Re-runs the
# same substitution the bake loop below does and diffs, so a match is proof, not a mtime guess.
if [ "${CHECK_ONLY:-0}" = 1 ]; then
  stale=0; missing=0; n=0
  for f in "$ROOT"/commands/*.md; do
    n=$((n + 1))
    out="$TARGET/commands/agent-tiers-$(basename "$f" .md).md"
    if [ ! -f "$out" ]; then
      echo "  MISSING  $out"; missing=$((missing + 1)); continue
    fi
    if ! sed -e "s#\${CLAUDE_PLUGIN_ROOT}#$ROOT#g" -e "s#\${AGENT_TIERS_LEDGER}#$LEDGER#g" "$f" \
         | diff -q - "$out" >/dev/null 2>&1; then
      echo "  STALE    $out  (canonical: $f)"; stale=$((stale + 1))
    fi
  done
  echo "commands: $((n - stale - missing)) of $n current, $stale stale, $missing missing  (target: $TARGET)"
  [ "$stale" = 0 ] && [ "$missing" = 0 ] || { echo "re-run install-flat.sh to refresh."; exit 1; }
  exit 0
fi

COPIED=0   # set if a symlink had to fall back to a copy (a drift surface)
if [ "$UNWIRE" = 1 ]; then
  command -v jq >/dev/null 2>&1 || { echo "install-flat: --unwire-only needs jq to edit settings.json safely - install jq and re-run" >&2; exit 1; }
  echo "agent-tiers unwire-only  (settings: $TARGET/settings.json)"
else
mkdir -p "$TARGET/skills" "$TARGET/agents" "$TARGET/commands"

echo "agent-tiers flat-install  (canonical kit: $ROOT)"
echo "                          installing into: $TARGET$([ "$TARGET" = "$CLAUDE_DIR" ] || echo '  [CLAUDE_CONFIG_DIR profile]')"

# --- preflight: the external commands the kit's scripts rely on -------------------------------------
# jq is OPTIONAL - install-flat AND the SessionStart hook both degrade gracefully without it. The rest
# are POSIX / coreutils (present on any standard Linux/macOS); a missing one means a script would fail,
# so surface it now rather than cryptically at hook-time. Non-fatal - the install still proceeds.
missing=""
for c in sed awk cksum date cut wc du tr grep head sort env ln cp mv rm mkdir mktemp cat ls basename dirname find; do
  command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
[ -n "$missing" ] && echo "  ⚠ missing required commands:$missing - kit scripts (probe / resume-inject) may fail; install them and re-run."
command -v jq >/dev/null 2>&1 || echo "  ⚠ jq not found - no hooks are wired (the wiring is printed for manual paste below), the agent-tiers CLI will not run, and installed guard hooks fail open and do nothing."
# Note (T1.5, 2026-08-16): without jq NOTHING is wired below, so WIRED_IDS stays empty and no selfcheck
# runs - which is why this installer never reports a jq-less selfcheck "SKIP: jq absent" (exit 0) as
# proof of a wired guard. That safety is a consequence of the wiring being jq-only, not a designed
# check; if wiring ever gains a jq-less path, the post-wire selfcheck loop must treat SKIP as not-proven.


clear_dest() { # $1=dest $2=log label
  # A pre-existing destination that is NOT a symlink might be real user content (name collision) or a
  # copy-fallback artifact from a prior run - either way, back it up instead of silently rm -rf'ing it.
  # A pre-existing symlink is always kit-managed (this installer is the only thing that creates one
  # here), so it's always safe to replace outright.
  if [ -e "$1" ] && [ ! -L "$1" ]; then
    bak="$1.bak-$(date +%s)"
    mv "$1" "$bak"
    echo "  ⚠ $2: existing non-symlink destination backed up to $(basename "$bak") before replacing"
  else
    rm -rf "$1" 2>/dev/null || true
  fi
}

# Relative symlink where supported; copy where not (e.g. Windows without Developer Mode/admin).
#   $1 = relative link target   $2 = absolute source   $3 = dest   $4 = log label
link_or_copy() {
  clear_dest "$3" "$4"
  if ln -s "$1" "$3" 2>/dev/null && [ -L "$3" ]; then
    echo "  $4 (symlink)"
  else
    rm -rf "$3" 2>/dev/null || true   # ln may have left a copy/partial (e.g. MSYS Git Bash copies instead of linking) - clean before cp
    cp -R "$2" "$3"; COPIED=1
    echo "  $4 (copy - symlinks unsupported here)"
  fi
}

# 1. Skills - relative symlinks (zero drift: kit edits are live immediately), else copies.
#    Deliberately NEVER baked (unlike commands): a baked doctrine copy would go stale against the
#    kit while resume-inject's version stamp reads the CANONICAL file - the session would report a
#    doctrine version it never loaded. Symlinked bodies therefore must not carry a bare
#    ${CLAUDE_PLUGIN_ROOT} - they use the ${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers} default
#    form instead (kit CLAUDE.md convention; cold-review F7).
for d in "$ROOT"/skills/*/; do
  name="$(basename "$d")"
  link_or_copy "$LINKBASE/skills/$name" "$ROOT/skills/$name" "$TARGET/skills/$name" "skill   $TARGET/skills/$name"
done

# 2. Agents - relative symlinks, else copies. Same never-baked rule as skills.
for f in "$ROOT"/agents/*.md; do
  name="$(basename "$f")"
  link_or_copy "$LINKBASE/agents/$name" "$ROOT/agents/$name" "$TARGET/agents/$name" "agent   $TARGET/agents/$name"
done

# 3. Commands - COPIES (the only drift surface): rename to agent-tiers-* (avoids built-in /init),
#    and bake ${CLAUDE_PLUGIN_ROOT} (only set in plugin context) to the absolute canonical path so
#    both Bash and the Read/Write tools resolve it.
for f in "$ROOT"/commands/*.md; do
  base="$(basename "$f" .md)"
  out="$TARGET/commands/agent-tiers-$base.md"
  sed -e "s#\${CLAUDE_PLUGIN_ROOT}#$ROOT#g" -e "s#\${AGENT_TIERS_LEDGER}#$LEDGER#g" "$f" > "$out"
  echo "  command $TARGET/commands/agent-tiers-$base.md  (copy, root baked)"
done

# 3b. Kit config - the user's GLOBAL vcs-policy defaults. Write-if-absent; NEVER clobber user edits.
KIT_CONFIG="$ROOT/kit-config.md"
if [ ! -f "$KIT_CONFIG" ]; then
  cat > "$KIT_CONFIG" <<'KITCONFIG_EOF'
---
# agent-tiers kit config - YOUR global defaults for how kit-managed artifacts are tracked in git.
# Created once by install-flat.sh (write-if-absent) and never overwritten. Edit freely.
# Per project, /agent-tiers:init reads this, offers an override, and records the resolved map in that
# project's .claude/agent-tiers.local.md (vcs_policy:). Changing a default here does NOT retro-apply to
# already-initialised projects - re-run /agent-tiers:init --reprobe (or the gc VCS check) to reconcile.
#
# Disposition values:
#   commit          - track in git (shared with the team)
#   ignore-shared   - add to .gitignore (ignored, but the ignore rule itself is committed/shared)
#   ignore-personal - add to .git/info/exclude (ignored, machine-local, never shared)
vcs_defaults:
  agent_tiers_local:    ignore-personal   # .claude/agent-tiers.local.md (machine-specific; commit never offered)
  project_brief:        ignore-personal   # .claude/skills/tier-project-brief/ (teams may prefer commit)
  task_agents:          ignore-personal   # .claude/agents/<prefix>-*.md (teams may prefer commit)
  agent_memory_local:   ignore-personal   # .claude/agent-memory-local/ (local scope = never commit)
  agent_memory_project: commit            # .claude/agent-memory/ (only if a project opts into memory: project)
  resume_session:       ignore-personal   # RESUME_SESSION.md (personal handoff)
  private_notes:        ignore-personal   # docs/_local/ notes dir -> .git/info/exclude (never on a code branch)

# private-notes seam: a side ref backs up the notes dir; it is NEVER merged into any code branch, so
# private planning docs cannot bleed into the repo's tracked history. `notes-sync.sh` reads/writes the
# per-repo values from .git/config (notes-sync.dir/ref/push); these are the GLOBAL fallbacks + push policy.
#   push: local          - the ref never leaves this machine (SAFE DEFAULT; opt in to push per project)
#   push: <remote-name>  - e.g. private / origin; `notes-sync push`/`sync` sends the ref there
private_notes_ref:
  dir:  docs/_local
  ref:  local/notes
  push: local
  archive_subdir: archive    # terminal-doc folder, relative to dir
  stale_days: 21             # advisory-only: flag a LIVE doc untouched this long
---

# agent-tiers kit config

These are the **global defaults** applied when `/agent-tiers:init` sets up a project. Change a value to
change what a *new* init proposes; a project can override any line during init, and the resolved
per-project map is recorded in that project's `.claude/agent-tiers.local.md` under `vcs_policy:`.

## Operator manual - volatile vendor facts (kept OUT of the doctrine skill)
The `agent-tiers` SKILL states cost DOCTRINE in ratios (opus a small multiple of sonnet = cheap insurance;
fable a large multiple = the tier to guard). The live numbers rot, so they live here, not in the doctrine:

- **Model $/MTok (in/out), Anthropic list pricing as of 2026-07:** haiku 1/5 . sonnet 3/15 . opus 5/25 .
  fable 10/50. So opus is ~1.7x sonnet (cheap scoped insurance) and fable is ~2x opus (the tier to guard).
  Re-check the RATIOS, not the doctrine prose, if list pricing shifts materially.
- **Codex model ids drift per release** - the doctrine names tiers, not ids; read the workspace default from
  `$CODEX_HOME/config.toml` (`model =`), and when unsure omit `model` and set only `effort`
  (`low`/`medium`/`high` are stable). Recent examples only, observed 2026-08-03: workspace default
  `gpt-5.6-sol`, sibling `gpt-5.6-terra` (same generation, same lab - NOT a second lab, see XLAB-11);
  `openai/gpt-5-mini` as a cheap tier. Note the default is often ALREADY the flagship, so "upgrade the model"
  is frequently a no-op ask - the levers are `effort` and brief specificity.

## Workspace boundary - host configuration, not a kit guard (T1.9, 2026-08-16)
The kit ships NO workspace guard: the host enforces a working-directory bound better than a hook can,
wherever it enforces one at all. What that means per configuration (HOST-4 has the ceilings):

- **`--dangerously-skip-permissions` (cc-gui Full Auto, `claude -p ...`): no boundary.** `[run 2026-08-16:
  touch ~/Downloads/at-probe.txt from a Full Auto session, silent success]`. Nothing cards it; nothing
  logs it. If you want a bound in this mode it is CONFIG, in `~/.claude/settings.json`:
      "permissions": { "deny": [ "Read(~/Downloads/**)", "Edit(~/Downloads/**)", "Write(~/Downloads/**)" ] }
  Read/Edit/Write deny rules apply to Claude's file tools; the CLI is documented to apply Read/Edit rules
  to the file commands it recognises inside Bash too (`cat`, `head`, `tail`, `sed`) `[read, not probed on
  this CLI version - probe before relying on it]`. Path syntax: `~/` = home, `//` = filesystem root, a
  bare path is relative to the project.
- **`default` / `plan` (cc-gui Suggest, native CLI interactive):** the CLI enforces its allowlist and asks
  before writing outside it; cc-gui cards that ask, flakily; a native terminal prompts `[unverified]`.
  Nothing to configure unless you want the deny rules above as belt-and-braces.
- **Codex: no equivalent.** The only bound is the per-exec sandbox (`codex exec -s read-only` /
  `workspace-write`, see the XLAB card and codex-run.sh); a `workspace-write` exec can reach whatever that
  sandbox allows, and there is no settings-file deny list. Open gap, stated, not closed.
KITCONFIG_EOF
  echo "  config  ~/.claude/agent-tiers/kit-config.md  (created - edit to taste)"
else
  echo "  config  ~/.claude/agent-tiers/kit-config.md  (present - left as-is)"
fi
fi   # end of install-only sections (unwire-only skips 1, 2, 3, 3b)

# 4. Hooks - the EXTERNAL-INTEGRATIONS seam: one wiring mechanism for every kit hook.
#
#    Two row classes:
#      core    - self-scoping SessionStart hooks, wired on every install (each no-ops where it does
#                not apply, so wiring is always safe and stays correct as the machine changes). No
#                install-time probe: a probe is a stale snapshot nothing re-runs, and every core
#                hook already self-scopes at runtime, so there is nothing a probe would add.
#      consent - per-tool-call rows (PreToolUse guards, and PostToolUse recorders). These run a command
#                around EVERY matching tool call and either shape a permission decision or observe what
#                the session did, i.e. they are security policy or a record of your work: wired ONLY on
#                an explicit --with-<id> flag, never automatically; the exact JSON is printed at wire time.
#    Support probe (2026-09-14): a consent row whose script carries `# kit-probe: yes` (e.g.
#    precompact-guard, notify) is asked, at --with-<id> time and BEFORE any settings.json write,
#    whether THIS host can actually support it (`sh scripts/<id>.sh --probe`) - unlike the runtime
#    self-scoping above, a hook depending on a HOST-STABLE fact (a binary on PATH, a sibling hook
#    also wired) would otherwise wire cleanly and then silently never fire. Deliberately scoped to
#    host-stable facts only, never a PER-SESSION one (which terminal a future session runs in,
#    which project it opens): that varies session to session on the same wired row, so probing it
#    at install time is a stale snapshot nothing re-runs - exactly the trap a probe checking `TERM`
#    at install time fell into and was corrected out of (see notify.sh's own header). Exit 0 =
#    supported, anything else = refused, nothing written. `--force-with-<id>` skips the probe for a
#    false negative.
#    Ledger: .state/integrations.json records every row THIS installer wrote (command, script cksum,
#            time, settings path). Re-runs converge on the target state: ours-current is left alone,
#            ours-stale (target command changed) is rewritten, and a row that mentions a kit script
#            but matches neither the target nor the ledger is FOREIGN - warned about, never touched.
#            A row that byte-matches the target is adopted into the ledger (it IS the target).
#    Proof:  each wired row's scripts/<id>.selfcheck.sh (if present) runs after wiring - "wired" and
#            "fires" are different claims; F-1 happened because docs conflated them.
#    ponytail: the command string is the row's identity; MATCHER drift IS reconciled (a row found under
#    the event but under another matcher is rewired into the target group - Wave B 2026-08-16), event/
#    timeout drift on an adopted or hand-moved row is not (doctor's integrations check reports it), and
#    a same-event group that was ALREADY empty before a removal is pruned with it.
SETTINGS="$TARGET/settings.json"   # STATE_DIR / LEDGER resolved at the top (per-profile)

# dotfiles-friendly commands: write a literal $HOME (expanded by sh at hook runtime) when the kit sits
# at the default path, so settings.json stays machine-portable; otherwise bake the actual root.
if [ "$ROOT" = "$HOME/.claude/agent-tiers" ]; then CMDROOT='$HOME/.claude/agent-tiers'; else CMDROOT="$ROOT"; fi

# count of hook entries whose command byte-equals $2, UNDER EVENT $1 only. The read MUST be event-scoped
# because every write is (add_hook/remove_cmd/rewire_hook): a file-wide count reads a row wired under a
# DIFFERENT event as "already wired", so the installer reports the row green, stamps the ledger, runs the
# selfcheck - and never wires the target event. On a consent guard that is a security control silently
# absent. (A ledger row recorded under another event is a separate, stated ceiling: not reconciled here,
# reported by doctor's integrations check.)
count_cmd() { # $1=event $2=cmd
  jq --arg ev "$1" --arg c "$2" \
    '[ (.hooks? | objects | .[$ev] | arrays | .[])
       | objects | (.hooks? | arrays | .[])
       | objects | .command? | strings | select(. == $c) ] | length' "$SETTINGS"
}
# same, but only inside a group whose matcher is exactly $3 ('' = a group with no matcher). A row present
# under the event but under a DIFFERENT matcher is matcher DRIFT: the guard fires on the wrong tool set
# (opus reviewer, Wave B 2026-08-16, HIGH: security-gate's matcher gained `Bash`, and every already-wired
# install kept `Write|Edit|NotebookEdit` while the installer printed green and stamped the NEW matcher).
count_cmd_matcher() { # $1=event $2=cmd $3=matcher
  jq --arg ev "$1" --arg c "$2" --arg m "$3" \
    '[ (.hooks? | objects | .[$ev] | arrays | .[])
       | objects | select((.matcher // "") == $m) | (.hooks? | arrays | .[])
       | objects | .command? | strings | select(. == $c) ] | length' "$SETTINGS"
}

# Replace settings.json with the content of $1 (a temp file next to it), removing $1. A symlinked
# settings.json is written THROUGH (cat >) so the link survives; a regular file gets the atomic rename.
# On a failed write the pre-image is restored. 0 on success.
settings_commit() { # $1=tmp
  SC_RESTORE_FAILED=0   # callers read it to word their failure line (settings_state)
  if [ -L "$SETTINGS" ]; then
    sc_pre="$(mktemp "$SETTINGS.XXXXXX")" || { rm -f "$1"; return 1; }
    cp "$SETTINGS" "$sc_pre" || { rm -f "$1" "$sc_pre"; return 1; }
    if cat "$1" > "$SETTINGS"; then rm -f "$1" "$sc_pre"; return 0; fi
    cat "$sc_pre" > "$SETTINGS" 2>/dev/null || SC_RESTORE_FAILED=1
    rm -f "$1" "$sc_pre"; return 1
  fi
  mv -f "$1" "$SETTINGS"
}

# Failure-line wording: "unchanged" is only true when the failed write did not need a restore, or the
# restore worked. When both failed, the pre-write backup $BAK is the only intact copy.
settings_state() {
  if [ "${SC_RESTORE_FAILED:-0}" = 1 ]; then
    printf 'write and restore both failed, so settings.json may be unchanged or partly written; the intact pre-install copy is the backup %s' "$BAK"
  else
    printf 'settings.json unchanged'
  fi
}

# Pick a non-colliding backup name into BAK (same scheme as scripts/agent-tiers): the base
# settings.json.bak-YYYYmmdd-HHMMSS, else one past the highest -2..-9 suffix. Returns 1 past -9.
pick_backup() {
  pb_base="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"; BAK="$pb_base"; pb_n=1
  for pb_k in 2 3 4 5 6 7 8 9; do if [ -e "$pb_base-$pb_k" ]; then pb_n=$pb_k; fi; done
  if [ "$pb_n" -gt 1 ] || [ -e "$pb_base" ]; then
    pb_n=$((pb_n + 1))
    [ "$pb_n" -le 9 ] || { BAK="$pb_base"; return 1; }
    BAK="$pb_base-$pb_n"
  fi
}

add_hook() { # $1=event $2=matcher('' = none) $3=cmd $4=timeout  -> 0 on confirmed write
  tmp="$(mktemp "$SETTINGS.XXXXXX")" || return 1
  if [ -n "$2" ]; then
    jq --arg ev "$1" --arg m "$2" --arg c "$3" --argjson t "$4" '
      def h: {type:"command", command:$c, timeout:$t};
      if ((.hooks[$ev] // []) | map(.matcher == $m) | any)
      then .hooks[$ev] |= map(if .matcher == $m then .hooks += [h] else . end)
      else .hooks[$ev] = ((.hooks[$ev] // []) + [{matcher:$m, hooks:[h]}])
      end' "$SETTINGS" > "$tmp" && settings_commit "$tmp"
  else
    jq --arg ev "$1" --arg c "$3" --argjson t "$4" '
      .hooks[$ev] = ((.hooks[$ev] // []) +
        [{hooks: [{type:"command", command:$c, timeout:$t}]}])' "$SETTINGS" > "$tmp" && settings_commit "$tmp"
  fi || { rm -f "$tmp" 2>/dev/null || true; return 1; }
}

remove_cmd() { # $1=event $2=cmd - drop entries with that exact command from THAT event only; prune
  # groups emptied there (never other events - cross-lab finding 4 scoped the blast radius).
  tmp="$(mktemp "$SETTINGS.XXXXXX")" || return 1
  jq --arg ev "$1" --arg c "$2" '
    if .hooks[$ev] then
      .hooks[$ev] |= (map(
          if (.hooks? | type) == "array" then .hooks |= map(select(.command != $c)) else . end
        ) | map(select(((.hooks? // []) | length) > 0)))
    else . end' "$SETTINGS" > "$tmp" && settings_commit "$tmp" || { rm -f "$tmp" 2>/dev/null || true; return 1; }
}

rewire_hook() { # $1=event $2=matcher('' = none) $3=oldcmd $4=newcmd $5=timeout - ONE jq, ONE rename
  # (a two-step remove+add could fail between the writes and leave the row half-migrated).
  tmp="$(mktemp "$SETTINGS.XXXXXX")" || return 1
  jq --arg ev "$1" --arg m "$2" --arg oc "$3" --arg c "$4" --argjson t "$5" '
    def h: {type:"command", command:$c, timeout:$t};
    (if .hooks[$ev] then
       .hooks[$ev] |= (map(
           if (.hooks? | type) == "array" then .hooks |= map(select(.command != $oc)) else . end
         ) | map(select(((.hooks? // []) | length) > 0)))
     else . end)
    | (if $m != "" then
         (if ((.hooks[$ev] // []) | map(.matcher == $m) | any)
          then .hooks[$ev] |= map(if .matcher == $m then .hooks += [h] else . end)
          else .hooks[$ev] = ((.hooks[$ev] // []) + [{matcher:$m, hooks:[h]}])
          end)
       else .hooks[$ev] = ((.hooks[$ev] // []) + [{hooks:[h]}])
       end)' "$SETTINGS" > "$tmp" && settings_commit "$tmp" || { rm -f "$tmp" 2>/dev/null || true; return 1; }
}

ledger_set() { # $1=id $2=cmd $3=event $4=matcher
  ck="$(cksum "$ROOT/scripts/$1.sh" 2>/dev/null | cut -d' ' -f1-2 || true)"
  tmp="$(mktemp "$LEDGER.XXXXXX")" || return 1
  jq --arg id "$1" --arg c "$2" --arg ev "$3" --arg m "$4" --arg ck "$ck" \
     --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg s "$SETTINGS" \
     '.[$id] = {command:$c, event:$ev, matcher:$m, cksum:$ck, wired_at:$at, settings:$s}' \
     "$LEDGER" > "$tmp" && mv -f "$tmp" "$LEDGER" || { rm -f "$tmp" 2>/dev/null || true; return 1; }
}

ledger_del() { # $1=id
  [ -f "$LEDGER" ] || return 0   # unwire-only never creates the ledger
  tmp="$(mktemp "$LEDGER.XXXXXX")" || return 1
  jq --arg id "$1" 'del(.[$id])' "$LEDGER" > "$tmp" && mv -f "$tmp" "$LEDGER" || { rm -f "$tmp" 2>/dev/null || true; return 1; }
}

WIRED_IDS=""
UNWIRE_FAIL=0
SKIP_WIRE=0
if [ "$UNWIRE" = 1 ] && [ ! -f "$SETTINGS" ]; then
  echo "  hook    nothing to unwire ($SETTINGS absent)"
  SKIP_WIRE=1
fi
if [ "$SKIP_WIRE" = 1 ]; then
  :
elif command -v jq >/dev/null 2>&1; then
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  if ! jq . "$SETTINGS" >/dev/null 2>&1; then
    echo "  hook    ✗ $SETTINGS is not valid JSON - fix it and re-run; SKIPPING all hook wiring."
    UNWIRE_FAIL=1
    if [ "$UNWIRE" = 1 ]; then exit 1; fi
  elif ! pick_backup; then
    echo "  hook    ✗ too many settings backups this second ($BAK-2..-9 exist) - re-run in a moment; SKIPPING all hook wiring."
    UNWIRE_FAIL=1
    if [ "$UNWIRE" = 1 ]; then exit 1; fi
  else
    if [ "$UNWIRE" != 1 ]; then mkdir -p "$STATE_DIR"; fi
    if [ -f "$LEDGER" ] && ! jq -e 'type == "object"' "$LEDGER" >/dev/null 2>&1; then
      # mktemp, not a timestamp: two runs in the same second would otherwise clobber the first corpse.
      corrupt="$(mktemp "$LEDGER.corrupt-XXXXXX")" && mv -f "$LEDGER" "$corrupt"
      echo "  hook    ⚠ ledger was invalid/mis-shaped JSON - moved aside ($corrupt), starting fresh"
    fi
    if [ "$UNWIRE" != 1 ] && [ ! -f "$LEDGER" ]; then echo '{}' > "$LEDGER"; fi
    cp -p "$SETTINGS" "$BAK"
    # cp -p inherits settings.json's own perms, which may be world-readable. These copies carry env
    # blocks and API keys verbatim, so clamp them regardless of what the live file allows.
    chmod 600 "$BAK"
    echo "  hook    settings backup: $BAK"
    # Keep only the 5 newest. These are verbatim settings.json copies (env blocks, API keys), so an
    # unbounded pile of them next to the live file is a growing disclosure surface, not just clutter.
    # Sort by NAME, not mtime: the suffix is a zero-padded timestamp, and `cp -p` gives every backup
    # settings.json's OWN mtime - so on idempotent re-runs (settings unchanged) every backup shares one
    # mtime, `ls -t` falls back to name-ASCENDING, and the prune would delete the newest and keep the
    # oldest. Name-descending is correct whatever the mtimes say.
    ls -1 "$SETTINGS".bak-* 2>/dev/null | sort -r | tail -n +6 | while IFS= read -r stale; do rm -f "$stale"; done
    while IFS=';' read -r id class ev m t; do
      if [ -z "$id" ]; then continue; fi
      if [ "$UNWIRE" = 1 ] && ! has_id "$id" "$WITHOUT"; then continue; fi
      # Never wire a row whose script is not actually in this kit copy (a bundle excludes
      # export-ignored scripts): a wired-but-missing hook 127s on EVERY matching tool call and
      # writes a ledger row with an empty cksum (cold-review F4). --without-<id> still falls
      # through: an already-wired row whose script has vanished must stay removable.
      if [ ! -f "$ROOT/scripts/$id.sh" ] && ! has_id "$id" "$WITHOUT"; then
        echo "  hook    ⚠ $id: scripts/$id.sh not present in this kit copy - row skipped"
        continue
      fi
      CMD="sh \"$CMDROOT/scripts/$id.sh\""
      want=1
      if [ "$class" = "consent" ]; then has_id "$id" "$WITH" || want=0; fi
      if has_id "$id" "$WITHOUT"; then want=0; fi

      lcmd="$(jq -r --arg id "$id" '.[$id].command // empty' "$LEDGER" 2>/dev/null || true)"
      lset="$(jq -r --arg id "$id" '.[$id].settings // empty' "$LEDGER" 2>/dev/null || true)"
      # A ledger row recorded against a DIFFERENT settings file is not ours to reconcile here.
      if [ -n "$lset" ] && [ "$lset" != "$SETTINGS" ]; then lcmd=""; fi
      n_target="$(count_cmd "$ev" "$CMD")"
      n_ledger=0
      if [ -n "$lcmd" ] && [ "$lcmd" != "$CMD" ]; then n_ledger="$(count_cmd "$ev" "$lcmd")"; fi
      n_foreign="$(jq --arg n "/$id.sh" --arg c "$CMD" --arg l "${lcmd:-}" \
        '[.. | objects | .command? | strings | select(contains($n)) | select(. != $c and . != $l)] | length' "$SETTINGS")"
      # A row carrying the TARGET command under some OTHER event is invisible to both the foreign check
      # (its command matches the target) and to doctor (the ledger entry exists and its event matches the
      # live group we wired). Nobody else reports it, so report it here - it fires the guard on the wrong
      # event, which is a duplicate hook, not a missing one.
      n_anyevent="$(jq --arg c "$CMD" '[.. | objects | .command? | strings | select(. == $c)] | length' "$SETTINGS")"
      if [ "$n_anyevent" -gt "$n_target" ]; then
        echo "  hook    ⚠ $id: the kit command also appears under an event other than $ev ($((n_anyevent - n_target)) row(s)) - the installer only manages $ev, so that copy fires on the wrong event. Remove it from $SETTINGS by hand."
      fi
      if [ "$n_foreign" -gt 0 ]; then
        echo "  hook    ⚠ $id: $n_foreign FOREIGN row(s) mention $id.sh but match neither the target nor the ledger - left untouched. To let the installer manage them, remove them from $SETTINGS and re-run."
      fi

      if [ "$want" = 1 ]; then
        if [ "$n_target" -gt 0 ] && [ "$(count_cmd_matcher "$ev" "$CMD" "$m")" -gt 0 ]; then
          ledger_set "$id" "$CMD" "$ev" "$m" || true
          echo "  hook    = $id already wired ($ev) - ledger current"
          WIRED_IDS="$WIRED_IDS $id"
        elif [ "$n_target" -gt 0 ]; then
          # wired under the event, but not under THIS matcher: rewire (same command) into the right group.
          if rewire_hook "$ev" "$m" "$CMD" "$CMD" "$t"; then
            ledger_set "$id" "$CMD" "$ev" "$m" || true
            echo "  hook    ~ $id REWIRED ($ev) - matcher drift: row moved to matcher \"$m\""
            WIRED_IDS="$WIRED_IDS $id"
          else
            UNWIRE_FAIL=1; echo "  hook    ✗ $id matcher rewire FAILED - $(settings_state) (backup: $BAK)"
          fi
        elif [ "$n_ledger" -gt 0 ]; then
          if rewire_hook "$ev" "$m" "$lcmd" "$CMD" "$t"; then
            ledger_set "$id" "$CMD" "$ev" "$m" || true
            echo "  hook    ~ $id REWIRED ($ev) - kit-owned row updated to current target"
            WIRED_IDS="$WIRED_IDS $id"
          else
            UNWIRE_FAIL=1; echo "  hook    ✗ $id rewire FAILED - $(settings_state) (backup: $BAK)"
          fi
        else
          if add_hook "$ev" "$m" "$CMD" "$t"; then
            ledger_set "$id" "$CMD" "$ev" "$m" || true
            echo "  hook    + $id wired ($ev${m:+, matcher $m})"
            if [ "$class" = "consent" ]; then
              echo "  hook      consent row JSON: $(jq -cn --arg c "$CMD" --argjson t "$t" '{type:"command", command:$c, timeout:$t}')"
            fi
            WIRED_IDS="$WIRED_IDS $id"
          else
            UNWIRE_FAIL=1; echo "  hook    ✗ $id wire FAILED (jq write error) - $(settings_state) (backup: $BAK)"
          fi
        fi
      else
        if has_id "$id" "$WITHOUT"; then
          removed=0 rfail=0
          if [ "$n_target" -gt 0 ]; then if remove_cmd "$ev" "$CMD"; then removed=1; else rfail=1; fi; fi
          if [ "$n_ledger" -gt 0 ]; then if remove_cmd "$ev" "$lcmd"; then removed=1; else rfail=1; fi; fi
          if [ "$rfail" = 1 ]; then
            UNWIRE_FAIL=1
            if [ "$removed" = 1 ]; then
              echo "  hook    ✗ $id removal FAILED part way - check $SETTINGS (backup: $BAK)"
            else
              echo "  hook    ✗ $id removal FAILED - $(settings_state) (backup: $BAK)"
            fi
          else
            ledger_del "$id" || true
            if [ "$removed" = 1 ]; then echo "  hook    - $id removed"; else echo "  hook    - $id not present (nothing to remove)"; fi
          fi
        elif [ "$n_target" -gt 0 ]; then
          # consent row already present and byte-identical to the target: presence IS prior consent.
          ledger_set "$id" "$CMD" "$ev" "$m" || true
          echo "  hook    = $id present (previously consented) - kept; remove with --without-$id"
          WIRED_IDS="$WIRED_IDS $id"
        else
          echo "  hook    ○ $id available, NOT wired (consent row) - turn its group on with: sh $ROOT/scripts/agent-tiers configure --set group_$(awk -F'\t' -v i="$id" '$1 == "hook" && $2 == i { print $3; exit }' "$ROOT/install/options.tsv" 2>/dev/null </dev/null || true)=true; flat-only alternative: install-flat.sh --with-$id"
        fi
      fi
    done <<HOOK_ROWS_EOF
$HOOK_ROWS
HOOK_ROWS_EOF

    # Proof step: wired != fires. Run each wired row's selfcheck where one ships.
    if [ "${AGENT_TIERS_TEST_SKIP_HOOK_PROOF:-}" = 1 ]; then
      echo "  hook    proof SKIPPED (AGENT_TIERS_TEST_SKIP_HOOK_PROOF=1, test-only knob) - no wired row's selfcheck ran"
    else
      for id in $WIRED_IDS; do
        sc="$ROOT/scripts/$id.selfcheck.sh"
        if [ -f "$sc" ]; then
          if sh "$sc" >/dev/null 2>&1; then
            echo "  hook    ✓ $id selfcheck OK"
          else
            echo "  hook    ⚠ $id selfcheck FAILED - run: sh $sc"
          fi
        fi
      done
    fi
  fi
else
  echo "  hook    jq not found - wire hooks manually in $SETTINGS (.hooks.<event>), one entry each:"
  while IFS=';' read -r id class ev m t; do
    if [ -z "$id" ]; then continue; fi
    if [ "$class" = "consent" ] && ! has_id "$id" "$WITH"; then continue; fi
    echo "          $ev${m:+ (matcher \"$m\")}: { \"type\": \"command\", \"command\": \"sh \\\"$CMDROOT/scripts/$id.sh\\\"\", \"timeout\": $t }"
  done <<HOOK_ROWS_EOF
$HOOK_ROWS
HOOK_ROWS_EOF
fi

if [ "$UNWIRE" = 1 ]; then
  echo "done (unwire only)."
  [ "$UNWIRE_FAIL" = 0 ] || exit 1
  exit 0
fi

# 5. Optional PATH command - agent-tiers-share (bundle + share the kit). Symlink into ~/bin so kit edits
#    propagate automatically. Guarded: never CREATE ~/bin or presume PATH on a recipient's machine.
SHARE_SRC="$ROOT/scripts/agent-tiers-share"
if [ -f "$SHARE_SRC" ]; then
  if [ -d "$HOME/bin" ]; then
    SHARE_DST="$HOME/bin/agent-tiers-share"
    if [ -L "$SHARE_DST" ] && [ "$(readlink "$SHARE_DST")" = "$SHARE_SRC" ]; then
      echo "  bin     ~/bin/agent-tiers-share (symlink already current)"
    else
      rm -f "$SHARE_DST" 2>/dev/null || true
      if ln -s "$SHARE_SRC" "$SHARE_DST" 2>/dev/null && [ -L "$SHARE_DST" ]; then
        echo "  bin     ~/bin/agent-tiers-share -> kit (symlink)"
      else
        rm -f "$SHARE_DST" 2>/dev/null || true
        cp -p "$SHARE_SRC" "$SHARE_DST"
        echo "  bin     ~/bin/agent-tiers-share (copy - symlinks unsupported here; re-run after kit updates)"
      fi
    fi
  else
    echo "  bin     ~/bin absent - to expose the share tool: mkdir -p ~/bin (ensure it's on PATH) then re-run, or run $SHARE_SRC directly"
  fi
fi

if [ "$COPIED" = 1 ]; then
  echo "  NOTE: this platform couldn't symlink, so skills/agents were COPIED (a drift surface)."
  echo "        Re-run this script after any kit update to refresh the copies."
fi

if [ -n "$HSCOPE_ARG" ]; then
  KCFG="$ROOT/kit-config.md"
  [ -f "$KCFG" ] || : > "$KCFG"
  if grep -aq '^hygiene_scope:' "$KCFG" 2>/dev/null; then
    # rewrite in place through a temp file, then copy CONTENT back rather than mv the temp over the
    # target: mv transplants mktemp's 0600 onto a file the operator may have made group-readable.
    tmp_kc="$(mktemp)" || { echo "install-flat: cannot create a temp file for the kit-config rewrite"; exit 1; }
    sed "s#^hygiene_scope:.*#hygiene_scope: $HSCOPE_ARG#" "$KCFG" > "$tmp_kc" && cat "$tmp_kc" > "$KCFG"
    rm -f "$tmp_kc"
  else
    # a kit-config.md with no trailing newline would otherwise glue the key onto the last line, where
    # the guard's `^hygiene_scope:` anchor never matches it - an inert setting reported as a success.
    [ -s "$KCFG" ] && [ -n "$(tail -c1 "$KCFG")" ] && printf '\n' >> "$KCFG"
    printf 'hygiene_scope: %s\n' "$HSCOPE_ARG" >> "$KCFG"
  fi
  printf '  config  hygiene_scope: %s (kit-config.md; a repo can override in .claude/agent-tiers.local.md)\n' "$HSCOPE_ARG"
fi
echo "done. (skills + commands re-scan live; new AGENT types need a host relaunch.)"
# UNWIRE_FAIL (despite the name) also covers install-mode wire/rewire/removal failures and skipped wiring.
[ "$UNWIRE_FAIL" = 0 ] || { echo "install-flat: finished with errors: a settings.json step failed or was skipped (see the hook lines above)" >&2; exit 1; }

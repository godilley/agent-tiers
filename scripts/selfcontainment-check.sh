#!/usr/bin/env sh
# kit-scope: shared
# selfcontainment-check.sh - preflight gate: a script that ships in a bundle but cannot function in
# the RECIPIENT's copy must fail the tag, not ship green. Companion to leak-scan.sh (which checks what
# a bundle LEAKS); this checks what a bundle SHIPS BROKEN.
#
# Origin (2026-08-23 audit): the kit has shipped scripts that silently assumed things only true in the
# origin repo/companion tree - unwired (not in HOOK_ROWS, so no install path ever runs them) or
# origin-only (an env var that resolves only in the operator's machine/companion repo). Free-text
# grep for self-declared "kit-local" comments was TRIED and measured insufficient: of 5 hits, only 2
# were actual self-declarations, the rest described a DIFFERENT file. This check uses a structural
# marker (`# kit-scope: shared|local`, backfilled into every script header) plus mechanical HOOK_ROWS
# parsing instead.
#
# Three rules, run against HEAD (the commit about to be tagged), not the working tree:
#   1. Reachability - every scripts/*.sh that WOULD SHIP (git archive respects export-ignore) is
#      reachable: a HOOK_ROWS id, named in another tracked script's text, or on the exemption list.
#   2. Origin-only deps - a bundled script referencing an env var outside the kit's own allowlist.
#   3. Scope marker - every tracked scripts/*.sh must carry `# kit-scope: shared` or `# kit-scope:
#      local`; `local` must be export-ignored (a local script that isn't excluded ships dead weight
#      or breaks); absence of the marker is itself a fail (an undeclared script is exactly the gap
#      this check exists to close).
#
# Usage: selfcontainment-check.sh [KIT_DIR]   (default: this script's own kit)
# Exit 0 = clean, 1 = a rule was violated (named), 2 = usage/tooling error.
#
# ponytail / disclosed ceiling: Rule 1's "referenced by name" check is a literal basename grep across
# tracked scripts - a script referenced only from a doc, or invoked via a variable/computed path, will
# false-positive as unreachable. Add it to EXEMPT_IDS in that case; this check optimizes for catching
# real orphans (measured: both known orphans to date, maint2-arrival-guard and the old
# advisory-ack-guard miswiring, are name-grep-visible), not for zero false positives.
#
# More disclosed ceilings (opus reviewer 2026-08-24, MEDIUM/LOW, none a live defect today):
# - Rule 2 skips every *.selfcheck.sh entirely (fixture payload strings would self-match a real env
#   var name). But selfchecks DO ship and DO run on the recipient's machine, so a selfcheck carrying a
#   real origin-only dep would slip through. Narrower fix (skip heredoc bodies only, or a per-file
#   opt-out marker) if a selfcheck ever actually needs one - not built until that happens.
# - Rules 2/3 read the WORKING TREE, Rule 1 reads HEAD's archive. Safe as wired (the caller refuses a
#   dirty tree before calling this), wrong for standalone use on a dirty tree per the Usage line above.
# - Rule 3 only flags `local` + not-export-ignored, never the reverse (`shared` + export-ignored).
#   Degrades to a warned skip in install-flat.sh, not silent, if it ever happens.
# - Rule 1 reads HOOK_ROWS only (the flat-install surface); a hook wired solely via hooks/hooks.json
#   (the plugin path) would false-positive as unreachable. No such hook exists today.
# - Unquoted `for f in $ALL_SCRIPTS` word-splits on whitespace, and `is_export_ignored` string-matches
#   `git ls-files` output against `tar -t` output, which quote non-ASCII bytes differently under
#   `core.quotePath`. A path with a space or non-ASCII byte would misbehave. No such path in the kit.
# - This check itself needs a git repo (`git rev-parse --git-dir` above) and is on its own EXEMPT_IDS,
#   so it always exits 2 in an unzipped bundle rather than running (opus advisor 2026-08-24, this was
#   the one undisclosed ceiling of the nine here). Honest failure, not a wrong answer - deliberately
#   NOT turning this into a fourth rule, since `notes-sync.sh` legitimately needs git too and "needs
#   git" would immediately false-positive on it.
set -u

KIT_DIR="${1:-$(CDPATH= cd "$(dirname "$0")/.." && pwd)}"
cd "$KIT_DIR" 2>/dev/null || { echo "selfcontainment-check: cannot cd to kit dir $KIT_DIR" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "selfcontainment-check: git not found" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "selfcontainment-check: $KIT_DIR is not a git repo" >&2; exit 2; }

fail=0
note() { printf '%s\n' "$1" >&2; fail=1; }

# --- exemption list (Rule 1) -------------------------------------------------------------------
# Scripts that are entry points in their own right, never referenced BY id/name from another script.
EXEMPT_IDS='install-flat probe-env lint-doctrine notes-sync selfcontainment-check agent-tiers-share'

# --- HOOK_ROWS ids, parsed the same way install-flat.sh does ------------------------------------
[ -f scripts/install-flat.sh ] || { echo "selfcontainment-check: scripts/install-flat.sh missing - cannot derive HOOK_ROWS" >&2; exit 2; }
# awk with RS="'" (not a line-oriented sed range): HOOK_ROWS is a single-quoted shell string that may
# be one line or many, and its closing quote sits at the END of the last data line, not on a line of
# its own - a line-anchored sed range either never closes (single-line fixtures) or, worse, silently
# prints to EOF and folds unrelated script text into "known ids" (measured against a single-line
# fixture while building this check). Splitting on the quote character itself is shape-independent.
HOOK_IDS="$(awk 'BEGIN{RS="\047"} /HOOK_ROWS=$/{getline; print; exit}' scripts/install-flat.sh | cut -d';' -f1)"
[ -n "$HOOK_IDS" ] || { echo "selfcontainment-check: could not parse any HOOK_ROWS ids from scripts/install-flat.sh - refusing to run Rule 1 blind" >&2; exit 2; }

# --- tracked scripts/*.sh plus the extensionless entry point (working-tree state; the tag equals
# HEAD which the caller's preflight already proved clean, so `git ls-files` == HEAD's tree here) ----
ALL_SCRIPTS="$(git ls-files 'scripts/*.sh' 'scripts/agent-tiers-share')"
[ -n "$ALL_SCRIPTS" ] || { echo "selfcontainment-check: no tracked scripts found" >&2; exit 2; }

is_hook_id() { printf '%s\n' "$HOOK_IDS" | grep -qx "$1"; }
is_exempt_id() { case " $EXEMPT_IDS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
is_selfcheck() { case "$1" in *.selfcheck.sh) return 0 ;; *) return 1 ;; esac; }
# "would ship" ground truth: what `git archive HEAD` actually produces, not `git check-attr`. Measured
# 2026-08-24: check-attr reports the directory-level pattern `scripts/fixtures/ export-ignore` as
# "unspecified" per file, while `git archive` DOES exclude everything under it - the two disagree, and
# archive is what a recipient actually receives, so it is the only source of truth used here.
BUNDLE_FILES="$(git archive HEAD 2>/dev/null | tar -t 2>/dev/null)"
[ -n "$BUNDLE_FILES" ] || { echo "selfcontainment-check: cannot determine bundle contents (git archive/tar failed or produced nothing) - refusing to treat that as an empty bundle" >&2; exit 2; }
is_export_ignored() { printf '%s\n' "$BUNDLE_FILES" | grep -qxF "$1" && return 1; return 0; }

# --- Rule 1: reachability, restricted to what WOULD SHIP (export-ignored files never reach a
# recipient, so they are out of scope for "can a recipient run this") -----------------------------
for f in $ALL_SCRIPTS; do
  is_export_ignored "$f" && continue
  base="$(basename "$f")"
  id="${base%.sh}"
  is_selfcheck "$f" && continue
  is_hook_id "$id" && continue
  is_exempt_id "$id" && continue
  # referenced by name from some OTHER tracked script (helper sourced/invoked by basename).
  # Excludes *.selfcheck.sh and scripts/fixtures/ as referrers (opus reviewer 2026-08-24, HIGH):
  # every guard's own selfcheck names it by basename as a kit-wide convention, so a script referenced
  # ONLY by its own selfcheck would otherwise pass this rule while still being unreachable from any
  # real install path - exactly the orphan shape this check exists to catch.
  if git grep -l -F "$base" -- 'scripts/*.sh' ':(exclude)scripts/*.selfcheck.sh' ':(exclude)scripts/fixtures/*' 'scripts/agent-tiers-share' 2>/dev/null | grep -qv "^$f\$"; then
    continue
  fi
  note "selfcontainment-check: RULE 1 (reachability) - $f ships in bundles but is not in HOOK_ROWS, not referenced by name from another tracked script (other than its own selfcheck), and not on the exemption list. A recipient's copy would have no install path that ever runs it."
done

# --- Rule 2: origin-only env-var dependencies -------------------------------------------------
# Scoped to what ships (bundled, non-export-ignored) and to real logic (.selfcheck.sh files are full
# of fixture PAYLOAD strings holding fake env-var references that are never actually executed by the
# guard - a literal dollar-brace token typed here in this comment would even self-match).
# Standard shell set + Claude/runtime-provided vars the kit is entitled to inherit + the kit's own
# override seams (always carry a safe `${VAR:-default}` fallback) + guard-cmdpos.sh's library
# internals (BASE/SEGMENTS/CMDPOS_*/GUARD_* - set by the SOURCING guard's own convention or by the
# library itself, not real environment variables; a per-file "was this assigned here" check can't see
# across a `. guard-cmdpos.sh` source boundary).
ALLOW_ENV='HOME PATH PWD OLDPWD SHELL USER LOGNAME TMPDIR IFS LANG LC_ALL TERM CDPATH BASH_VERSION
CLAUDE_PLUGIN_ROOT CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CLAUDE_CODE_EXECPATH CLAUDE_EFFORT
CLAUDE_CODE_SESSION_ID CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_ENTRYPOINT CLAUDE_AGENT_SDK_VERSION
CLAUDE_ENV_FILE ANTHROPIC_MODEL TERM_PROGRAM
AGENT_TIERS_GUARDS_LOG AGENT_TIERS_STATE_DIR AGENT_TIERS_LEDGER AGENT_TIERS_SHARE_NO_CLIP
AGENT_TIERS_SHARE_SKIP_CI_GATE
CODEX_HOME CODEX_RUN_BIN
BASE SEGMENTS CMDPOS_COMMIT_FRAG CMDPOS_GITOPTS CMDPOS_PREFIX GUARD_UNATTENDED_PREFIX GUARD_UNRESOLVED_REPO_REASON'
is_allowed_env() { printf '%s\n' "$ALLOW_ENV" | tr -s '[:space:]' '\n' | grep -qx "$1"; }
# "assigned in THIS file" - a var read but never assigned in the same script must come from the
# environment (or a sourced library, covered by the allowlist above).
is_assigned_in() { grep -qE "(^|[^A-Za-z0-9_])$1=[^=]|for[[:space:]]+$1[[:space:]]+in|read[[:space:]].*\\b$1\\b" "$2"; }
for f in $ALL_SCRIPTS; do
  is_selfcheck "$f" && continue
  is_export_ignored "$f" && continue
  cands="$(grep -ohE '\$\{?[A-Z][A-Z0-9_]{3,}\}?' "$f" 2>/dev/null | tr -d '${}' | sort -u)"
  for v in $cands; do
    is_allowed_env "$v" && continue
    is_assigned_in "$v" "$f" && continue
    note "selfcontainment-check: RULE 2 (origin-only dependency) - $f references \$$v, which is neither assigned in that file nor on the kit's env allowlist. If it resolves only in the operator's machine/companion repo, mark the script \`# kit-scope: local\` and export-ignore it; if it's a genuine inherited env var, add it to ALLOW_ENV in this check."
  done
done

# --- Rule 3: scope marker matches disposition -------------------------------------------------
for f in $ALL_SCRIPTS; do
  marker="$(grep -m1 -E '^# kit-scope: (shared|local)[[:space:]]*$' "$f" || true)"
  if [ -z "$marker" ]; then
    note "selfcontainment-check: RULE 3 (scope marker) - $f has no \`# kit-scope: shared\` or \`# kit-scope: local\` header line. Add one; absence is a fail so the rule cannot silently decay as scripts are added."
    continue
  fi
  case "$marker" in
    *local*)
      is_export_ignored "$f" || note "selfcontainment-check: RULE 3 (scope marker) - $f is marked \`kit-scope: local\` but is NOT export-ignored in .gitattributes, so it ships in bundles anyway. Either export-ignore it, or the marker is wrong."
      ;;
  esac
done

if [ "$fail" -eq 0 ]; then
  echo "selfcontainment-check: CLEAN ($(printf '%s\n' "$ALL_SCRIPTS" | wc -l | tr -d ' ') tracked scripts/*.sh checked)"
  exit 0
fi
exit 1

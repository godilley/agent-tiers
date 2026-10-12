#!/usr/bin/env sh
# kit-scope: shared
# Self-check for lib/guard-mempath.sh, the shared memory-directory resolver.
#
# The last case is the one that matters and the reason this file exists: it asserts the two CONSUMERS
# agree. Unit-testing the library alone would pass even if a consumer never called it, which is the
# half-migration the seam was built to end - and exactly what the pre-existing consumer selfchecks do,
# since neither of them exercises `autoMemoryDirectory` on both sides at once.
#
# State sandboxing: everything below lives under one mktemp -d, and nothing writes the real .state.
set -u

SCRIPTS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
LIB="$SCRIPTS/lib/guard-mempath.sh"
[ -f "$LIB" ] || { echo "FAIL: lib/guard-mempath.sh not found"; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (resolver degrades by design)"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# guard_mem_auto_dir falls back to the AMBIENT CLAUDE_PROJECT_DIR when no project dir is passed, and
# project/local settings are read LAST, so they win. Without this, running the kit's selfchecks from a
# repo that sets autoMemoryDirectory fails cases 1, 2, 3, 5 and 6 with messages blaming the library.
export CLAUDE_PROJECT_DIR=""
fails=0
fail() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

CDIR="$T/.claude"
mkdir -p "$CDIR"
. "$LIB"

# --- case 1: no autoMemoryDirectory configured ----------------------------------------------------
# Fails if an absent setting invents a path, which would silently relocate every consumer at once.
printf '{}\n' > "$CDIR/settings.json"
got="$(guard_mem_auto_dir "$CDIR")"
[ -z "$got" ] || fail "case 1: expected empty auto dir, got '$got'"

# --- case 2: an absolute autoMemoryDirectory is returned, trailing slash stripped ------------------
# The trailing slash matters: "$dir/*" against a value ending in / becomes "...//*" and never matches,
# so a configured dir would silently stop being recognised. Fails if the slash survives.
printf '{"autoMemoryDirectory": "%s/mem/"}\n' "$T" > "$CDIR/settings.json"
got="$(guard_mem_auto_dir "$CDIR")"
[ "$got" = "$T/mem" ] || fail "case 2: expected '$T/mem', got '$got'"

# --- case 3: a ~/ value expands, a bare relative value is discarded --------------------------------
# Fails if a relative value is guessed at rather than dropped - that would resolve against whatever
# cwd the hook happened to inherit, which is not knowable at write time.
printf '{"autoMemoryDirectory": "~/mymem"}\n' > "$CDIR/settings.json"
got="$(guard_mem_auto_dir "$CDIR")"
[ "$got" = "$HOME/mymem" ] || fail "case 3: ~/ did not expand, got '$got'"
printf '{"autoMemoryDirectory": "relative/path"}\n' > "$CDIR/settings.json"
got="$(guard_mem_auto_dir "$CDIR")"
[ -z "$got" ] || fail "case 3: a relative value should be discarded, got '$got'"

# --- case 4: last-wins precedence, user -> project -> local ----------------------------------------
# Fails if precedence reverses, which would make a project setting unable to override the user one.
PROJ="$T/proj"; mkdir -p "$PROJ/.claude"
printf '{"autoMemoryDirectory": "%s/from-user"}\n' "$T" > "$CDIR/settings.json"
printf '{"autoMemoryDirectory": "%s/from-project"}\n' "$T" > "$PROJ/.claude/settings.json"
got="$(guard_mem_auto_dir "$CDIR" "$PROJ")"
[ "$got" = "$T/from-project" ] || fail "case 4: project should win over user, got '$got'"
printf '{"autoMemoryDirectory": "%s/from-local"}\n' "$T" > "$PROJ/.claude/settings.local.json"
got="$(guard_mem_auto_dir "$CDIR" "$PROJ")"
[ "$got" = "$T/from-local" ] || fail "case 4: local should win over project, got '$got'"
rm -f "$PROJ/.claude/settings.json" "$PROJ/.claude/settings.local.json"

# --- case 5: an unparseable settings file is skipped, not fatal ------------------------------------
# Fails if a corrupt settings file breaks memory resolution for every consumer.
printf 'not json at all {{{\n' > "$CDIR/settings.json"
got="$(guard_mem_auto_dir "$CDIR")"
[ -z "$got" ] || fail "case 5: expected empty from unparseable settings, got '$got'"

# --- case 6: an empty project dir must not read the filesystem root --------------------------------
# "" + "/.claude/settings.json" is an absolute path to a real location on some machines.
# CEILING, stated rather than implied: this case cannot fail on a normal machine. Deleting the
# library's root-path carve-out entirely leaves it green, because `[ -f "/.claude/settings.json" ]` is
# false wherever there is no config dir at the filesystem root. Making it falsifiable needs a writable
# `/`. It is kept as a regression tripwire for a machine where that path does exist, not as proof.
printf '{}\n' > "$CDIR/settings.json"
got="$(guard_mem_auto_dir "$CDIR" "")"
[ -z "$got" ] || fail "case 6: expected empty, got '$got'"

# --- case 7: guard_mem_dir falls back to the git-repo derivation -----------------------------------
# Fails if the fallback keys off the launch path instead of the repo, which would give a worktree its
# own memory dir when Claude Code shares one per repository.
REPO="$T/repo"; mkdir -p "$REPO/sub"
( cd "$REPO" && git init -q . ) 2>/dev/null
if [ -d "$REPO/.git" ]; then
  from_root="$(guard_mem_dir "$CDIR" "$REPO")"
  from_sub="$(guard_mem_dir "$CDIR" "$REPO/sub")"
  [ "$from_root" = "$from_sub" ] || fail "case 7: a subdirectory resolved to a different memory dir ('$from_root' vs '$from_sub')"
  case "$from_root" in "$CDIR"/projects/*/memory) ;; *) fail "case 7: unexpected shape '$from_root'" ;; esac
else
  echo "note: case 7 skipped, git init unavailable"
fi

# --- case 8: an explicit autoMemoryDirectory overrides the git derivation -------------------------
# Fails if the configured value is ignored in favour of the repo path - the exact disagreement this
# library was built to end.
printf '{"autoMemoryDirectory": "%s/override"}\n' "$T" > "$CDIR/settings.json"
got="$(guard_mem_dir "$CDIR" "$REPO")"
[ "$got" = "$T/override" ] || fail "case 8: autoMemoryDirectory did not override the git derivation, got '$got'"

# --- case 9: in-scope gate covers all three shapes, and rejects outsiders --------------------------
# Fails if the gate widens (a non-memory path linted as memory) or narrows (a relocated config dir
# silently unlinted).
auto="$T/override"
guard_mem_in_scope "$CDIR" "/home/x/.claude/projects/slug/memory/a.md" "" \
  || fail "case 9: standard layout not in scope"
guard_mem_in_scope "$CDIR" "$CDIR/projects/slug/memory/a.md" "" \
  || fail "case 9: relocated config dir not in scope"
guard_mem_in_scope "$CDIR" "$auto/a.md" "$auto" \
  || fail "case 9: autoMemoryDirectory path not in scope"
guard_mem_in_scope "$CDIR" "$T/unrelated/a.md" "$auto" \
  && fail "case 9: an unrelated path was admitted"
# The sibling-prefix probe, and the reason this case exists. With auto=/h/mem, a bare prefix match
# admits /h/mem-archive and /h/memories as memory files and runs the content scan over them. Sharing a
# prefix is the normal case: this selfcheck's own fixtures build autodir, autodir-user and
# autodir-slash as siblings. Without these three lines the gate can lose its path separator and every
# other assertion here still passes.
guard_mem_in_scope "$CDIR" "${auto}-archive/a.md" "$auto" \
  && fail "case 9: a sibling dir sharing the auto-dir prefix was admitted"
guard_mem_in_scope "$CDIR" "${auto}.bak/a.md" "$auto" \
  && fail "case 9: a suffixed sibling of the auto dir was admitted"
guard_mem_in_scope "$CDIR" "$auto" "$auto" \
  && fail "case 9: the auto dir itself (not a file inside it) was admitted"
guard_mem_in_scope "$CDIR" "" "$auto" \
  && fail "case 9: an empty path was admitted"

# --- case 10: the seam is not half-migrated -------------------------------------------------------
# WHAT THIS CHECKS, precisely: that both consumers still CALL the shared resolver, and that the
# resolver hands the same answer to the lint's question and resume-inject's question.
# WHAT IT DOES NOT CHECK, so no reader assumes otherwise: it never executes either consumer. A
# consumer that calls the resolver and then ignores the answer passes this case. End-to-end coverage
# of the lint's own gate lives in memory-content-lint.selfcheck.sh (cases 3c/3c2/3c3); resume-inject's
# size advisory has no equivalent relocated-dir case.
for f in memory-content-lint.sh resume-inject.sh; do
  grep -qE 'guard_mem_in_scope|guard_mem_dir' "$SCRIPTS/$f" 2>/dev/null \
    || fail "case 10: $f does not call the shared resolver (half-migrated seam)"
done
# The two questions the consumers actually ask, against one configuration. These are structurally
# equal whenever an auto dir is set (guard_mem_dir returns it verbatim), so this is a wiring check,
# not an independent proof - see case 8 for the override itself.
printf '{"autoMemoryDirectory": "%s/shared-mem"}\n' "$T" > "$CDIR/settings.json"
mkdir -p "$T/shared-mem"
lint_side="$(guard_mem_auto_dir "$CDIR")"
resume_side="$(guard_mem_dir "$CDIR" "$REPO")"
[ "$lint_side" = "$resume_side" ] \
  || fail "case 10: the two consumers resolve different dirs ('$lint_side' vs '$resume_side')"
guard_mem_in_scope "$CDIR" "$resume_side/MEMORY.md" "$lint_side" \
  || fail "case 10: the dir resume-inject would size is not one memory-content-lint would lint"

if [ "$fails" -eq 0 ]; then
  echo "OK guard-mempath: precedence, ~/ expansion, relative/corrupt/empty inputs, git-repo fallback, autoMemoryDirectory override, the three-shape scope gate with its sibling-prefix probes, and both consumers still calling the shared resolver all hold"
  exit 0
fi
printf 'guard-mempath: %s case(s) failed\n' "$fails"
exit 1

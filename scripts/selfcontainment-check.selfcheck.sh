#!/usr/bin/env sh
# kit-scope: shared
# Self-check for selfcontainment-check.sh. Runnable: `sh selfcontainment-check.selfcheck.sh`.
# Builds a throwaway git repo shaped like a minimal kit (install-flat.sh's HOOK_ROWS block, one
# wired guard, one helper) and plants a violation of each rule in turn.
#
# Disclosed ceiling: no jq dependency, so this does NOT skip - it always runs (unlike selfchecks
# whose guard fails open without jq). If it starts using jq later, add the same SKIP convention the
# other selfchecks use; agent-tiers-share:63 treats a silent skip-as-pass as a tagging hazard.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/scripts"
cp "$DIR/selfcontainment-check.sh" "$W/scripts/"
cd "$W" || exit 1
git init -q -b master; git config user.email t@t.local; git config user.name t

cat > scripts/install-flat.sh <<'EOF'
#!/usr/bin/env sh
# kit-scope: shared
HOOK_ROWS='wired-guard;consent;PreToolUse;Bash;5'
EOF
cat > scripts/wired-guard.sh <<'EOF'
#!/usr/bin/env sh
# kit-scope: shared
exit 0
EOF

run() { sh scripts/selfcontainment-check.sh "$W" >"$W/out" 2>&1; echo $?; }

# --- baseline: clean, everything reachable + marked -> CLEAN ---
git add -A; git commit -qm c1
[ "$(run)" = 0 ] && ok 'clean tree passes' || { bad 'clean tree should pass'; cat "$W/out" >&2; }

# --- Rule 1 violation: an unwired, unmarked, unreferenced script -----------------------------
cat > scripts/orphan.sh <<'EOF'
#!/usr/bin/env sh
# kit-scope: shared
exit 0
EOF
git add -A; git commit -qm c2
[ "$(run)" = 1 ] && ok 'orphan script fails' || bad 'orphan script should fail (rule 1)'
grep -q 'RULE 1' "$W/out" && ok 'orphan failure names RULE 1' || bad 'orphan failure should name RULE 1'
git rm -q scripts/orphan.sh; git commit -qm c2-revert

# --- Rule 1, the HIGH the reviewer found (2026-08-24): an orphan with a MATCHING selfcheck must
# still fail. Every guard's own selfcheck names it by basename (kit convention), so a naive referrer
# search that includes *.selfcheck.sh treats "referenced only by its own selfcheck" as reachable -
# it is not, no install path ever runs orphan.sh itself. This is the exact shape maint2-arrival-guard
# would have had if its marker/export-ignore had been forgotten. -----------------------------------
cat > scripts/orphan.sh <<'EOF'
#!/usr/bin/env sh
# kit-scope: shared
exit 0
EOF
cat > scripts/orphan.selfcheck.sh <<'EOF'
#!/usr/bin/env sh
# kit-scope: shared
GUARD="$(dirname "$0")/orphan.sh"
sh "$GUARD"
EOF
git add -A; git commit -qm c2b
[ "$(run)" = 1 ] && ok 'orphan with a matching selfcheck still fails' || { bad 'an orphan referenced only by its own selfcheck should still fail (rule 1)'; cat "$W/out" >&2; }
grep -q 'RULE 1' "$W/out" && ok 'orphan+selfcheck failure names RULE 1' || bad 'orphan+selfcheck failure should name RULE 1'
git rm -q scripts/orphan.sh scripts/orphan.selfcheck.sh; git commit -qm c2b-revert

# --- Rule 2 violation: a bundled script reading an unlisted env var --------------------------
cat > scripts/wired-guard.sh <<'EOF'
#!/usr/bin/env sh
# kit-scope: shared
echo "${SOME_UNLISTED_ORIGIN_VAR}"
exit 0
EOF
git add -A; git commit -qm c3
[ "$(run)" = 1 ] && ok 'origin-only env var fails' || bad 'unlisted env var should fail (rule 2)'
grep -q 'RULE 2' "$W/out" && ok 'env-var failure names RULE 2' || bad 'env-var failure should name RULE 2'
cat > scripts/wired-guard.sh <<'EOF'
#!/usr/bin/env sh
# kit-scope: shared
exit 0
EOF
git add -A; git commit -qm c3-revert

# --- Rule 3a: kit-scope local but NOT export-ignored -> fails -------------------------------
# The case this check exists to catch (brief's core scenario): a script that self-declares
# local scope but isn't excluded from the bundle still ships to a recipient who can't run it.
cat > scripts/origin-only.sh <<'EOF'
#!/usr/bin/env sh
# kit-scope: local
exit 0
EOF
git add -A; git commit -qm c4
[ "$(run)" = 1 ] && ok 'local-but-not-export-ignored fails' || bad 'local-but-not-export-ignored should fail (rule 3)'
grep -q 'RULE 3' "$W/out" && ok 'local-scope failure names RULE 3' || bad 'local-scope failure should name RULE 3'

# now export-ignore it -> passes (still needs a marker on EVERY tracked script for rule 1's exempt
# check not to fire; give it a name that is not referenced anywhere, matching the real
# maint2-arrival-guard/leak-scan shape)
printf 'scripts/origin-only.sh export-ignore\n' > .gitattributes
git add -A; git commit -qm c5
[ "$(run)" = 0 ] && ok 'export-ignoring the local script clears rule 3' || { bad 'export-ignored local script should pass'; cat "$W/out" >&2; }

# --- Rule 3b: removing the marker entirely also fails (absence must fail, not silently pass) -
cat > scripts/wired-guard.sh <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
git add -A; git commit -qm c6
[ "$(run)" = 1 ] && ok 'missing marker fails' || bad 'a script with no kit-scope marker at all should fail (rule 3)'
grep -q 'RULE 3' "$W/out" && ok 'missing-marker failure names RULE 3' || bad 'missing-marker failure should name RULE 3'

[ "$fail" -eq 0 ] && echo "OK selfcontainment-check: reachability, origin-only env vars, scope-marker/export-ignore mismatch, and marker absence all caught; clean tree passes"
exit $fail

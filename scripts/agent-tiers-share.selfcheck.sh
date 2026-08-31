#!/usr/bin/env sh
# kit-scope: shared
# Self-check for agent-tiers-share (tag-sourced flow). Runnable: `sh agent-tiers-share.selfcheck.sh`.
# Builds a STUB kit repo (share's own orchestration is under test; lint/leak/selfcheck logic each
# have their own selfchecks) and exercises: preflight gating, share/<who>-<n> tag allocation,
# archive exclusions via export-ignore, ledger append+commit, --tag re-send, arg validation.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

command -v bash >/dev/null 2>&1 || { echo "SKIP: bash missing (share is a bash script)"; exit 0; }

W="$(mktemp -d)"; trap 'rm -rf "$W" "$W-out" "$W-nojq" "$W-origin" "$W-ghbin" "$W-bin" "$W-elsewhere"' EXIT
OUT="$W-out"   # OUTSIDE the stub repo - zips/prompts must not dirty the tree under test
export AGENT_TIERS_SHARE_NO_CLIP=1
# Isolation (2026-08-24): almost every test below assumes the CI gate is UNSET so it exercises the
# real (stubbed) gate above - a caller that itself ran with AGENT_TIERS_SHARE_SKIP_CI_GATE=1 (the
# real hatch, used from a real share when CI is down) leaks that into every subprocess this selfcheck
# spawns, silently flipping "green share succeeds" and the ledger-verified assertion to test the
# skip path instead and fail. Unset here so this selfcheck's result never depends on the calling
# shell's env; the one dedicated skip-gate test below sets it back for that single invocation only.
unset AGENT_TIERS_SHARE_SKIP_CI_GATE

# Real (stubbed) CI gate exercise, not the skip var, for the bulk of this file (2026-08-24, opus
# reviewer MEDIUM: the skip var used to cover EVERY test, so the gate's own push/dispatch/poll logic
# had zero coverage anywhere - including the run that found the HIGH bug this fix is next to). A bare
# local repo stands in for origin (push works for real); a stub `gh` on PATH answers the exact four
# calls the gate makes (auth status, repo view, workflow run, run list) with an immediate green result.
# One dedicated test further down still exercises AGENT_TIERS_SHARE_SKIP_CI_GATE explicitly.
ORIGIN="$W-origin"; mkdir -p "$ORIGIN"; git init -q --bare -b master "$ORIGIN" >/dev/null
GHBIN="$W-ghbin"; mkdir -p "$GHBIN"
GH_DISPATCH_LOG="$W-ghbin/dispatch.log"
cat > "$GHBIN/gh" <<EOF
#!/bin/sh
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "repo view") echo "test/test-repo"; exit 0 ;;
  "workflow run") echo "\$*" >> "$GH_DISPATCH_LOG"; exit 0 ;;
  "run list") echo '[{"status":"completed","conclusion":"success"}]'; exit 0 ;;
  *) echo "gh-stub: unhandled invocation: \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$GHBIN/gh"
export PATH="$GHBIN:$PATH"

cd "$W" || exit 1
git init -q -b master; git config user.email t@t.local; git config user.name t
git remote add origin "$ORIGIN"
mkdir -p scripts docs
cp "$DIR/agent-tiers-share" scripts/agent-tiers-share
printf '#!/bin/sh\nexit 0\n' > scripts/lint-doctrine.sh; chmod +x scripts/lint-doctrine.sh
printf '#!/bin/sh\nexit 0\n' > scripts/leak-scan.sh
printf '#!/bin/sh\nexit 0\n' > scripts/selfcontainment-check.sh
printf '#!/bin/sh\nexit 0\n' > scripts/probe-env.sh
printf 'exit 0\n' > scripts/stub.selfcheck.sh
printf 'kit readme\n' > README.md
printf 'secret-ish personal file\n' > docs/personal.md
printf 'docs/personal.md export-ignore\n' > .gitattributes
# prompt templates are files since 2026-08-31; the script hard-fails without them
mkdir -p templates/prompts
printf 'install prompt stub zip=__ZIPNAME__ tag=__TAG__\n' > templates/prompts/zip-install.txt
printf 'review prompt stub zip=__ZIPNAME__\n' > templates/prompts/zip-review.txt
printf 'safety body stub\n' > templates/prompts/safety-wrapper.txt
git add -A; git commit -qm genesis

share() { bash scripts/agent-tiers-share "$@" -o "$OUT" >/dev/null 2>&1; echo $?; }

# missing --who
[ "$(share --plain --review)" = 2 ] && ok 'missing --who exits 2' || bad 'missing --who exits 2'

# dirty tree aborts, no tag
printf 'dirt\n' > dirt.txt
[ "$(share --plain --review --who test)" = 1 ] && ok 'dirty tree aborts' || bad 'dirty tree aborts'
git tag | grep -q . && bad 'dirty tree must not tag' || ok 'dirty tree left no tag'
rm -f dirt.txt

# CI_GATE escape hatch: scoped to this ONE call only (env-prefixed, not exported), so every other
# test in this file goes through the real (stubbed) push/dispatch/poll logic instead.
CI_GATE_OUT="$(AGENT_TIERS_SHARE_SKIP_CI_GATE=1 bash scripts/agent-tiers-share --plain --review --who ci-gate-probe -o "$OUT" 2>&1)"
printf '%s' "$CI_GATE_OUT" | grep -q 'CI GATE SKIPPED' && ok 'CI gate skip warns loudly (test sandbox only)' || bad 'CI gate skip should print its loud warning'
grep -qE "share/ci-gate-probe-1.*	skipped\$" share-ledger.tsv && ok 'ledger records ci_gate=skipped for the escape hatch' || bad 'ledger should record ci_gate=skipped'
# the skip-hatch path never runs the CI gate's own branch push (line ~136), so this is the ONE
# variable-isolated check that the new post-ledger-commit push is what's doing the work here - the
# green-CI-gate assertion below is confounded (the gate ALSO pushes the branch, so it only proves the
# +1 ledger commit made it, not that this path pushes unaided).
git -C "$ORIGIN" rev-parse -q --verify refs/tags/share/ci-gate-probe-1 >/dev/null 2>&1 && \
  ok 'skip-gate path still pushes the tag + ledger commit unaided' || bad 'skip-gate path should push the tag + ledger commit'
git tag -d share/ci-gate-probe-1 >/dev/null 2>&1

# green run through the REAL CI gate (push to the bare origin, gh-stub answers dispatch/poll green):
# tag, zip, ledger committed, ledger's ci_gate column says "verified-linux" (default, no --macos).
[ "$(share --plain --review --who test)" = 0 ] && ok 'green share succeeds' || bad 'green share succeeds'
git rev-parse -q --verify refs/tags/share/test-1 >/dev/null && ok 'tag share/test-1 created' || bad 'tag share/test-1 created'
ls "$OUT"/agent-tiers-test-1-*.zip >/dev/null 2>&1 && ok 'zip produced from tag' || bad 'zip produced from tag'
grep -q "share/test-1" share-ledger.tsv && ok 'ledger row appended' || bad 'ledger row appended'
grep -q "	verified-linux$" share-ledger.tsv && ok 'ledger records CI gate verified-linux (default, no --macos)' || bad 'ledger should record ci_gate=verified-linux'
[ -z "$(git status --porcelain)" ] && ok 'ledger committed (tree clean)' || bad 'ledger committed (tree clean)'
# 2026-08-29: macos legs are opt-in per dispatch. Default must pass run_macos=false explicitly (not
# omit it) - an accidental default flip to true would only ever show up as a real 10x bill otherwise.
tail -1 "$GH_DISPATCH_LOG" | grep -q 'run_macos=false' && ok 'default dispatch passes run_macos=false' || bad 'default dispatch should pass run_macos=false'
# Compare against current master HEAD, not the tag's commit (2026-08-24: the CI-gate branch push
# happens BEFORE the ledger commit exists, so that push alone always
# left the ledger commit and the tag ref local-only - bundles 3, 4, 10 and an 11 run
# were all local-only until pushed by hand). The share script now pushes branch+tag again right
# after the ledger commit, so origin/master must match local master exactly, and the tag itself
# must be on origin too.
# query $ORIGIN directly rather than the local origin/master tracking ref - asserts the real thing
# a push updates, not a local bookkeeping ref that could in principle go stale for other reasons.
[ "$(git -C "$ORIGIN" rev-parse master)" = "$(git rev-parse master)" ] && \
  git -C "$ORIGIN" rev-parse -q --verify refs/tags/share/test-1 >/dev/null 2>&1 && \
  ok 'CI gate + ledger commit + tag all pushed to origin' || bad 'CI gate should have pushed the tagged commit and the tag ref to origin'

# prompt templates are FILES (2026-08-31): the generated prompt must carry the substituted
# zipname, the safety wrapper must come from its template file, and a missing template must be
# a hard error naming the path - never a silently empty prompt.
PF="$(ls -t "$OUT"/review-prompt-*.txt 2>/dev/null | head -1)"
[ -n "$PF" ] && grep -q 'zip=agent-tiers-test-1' "$PF" && \
  ok 'prompt built from template file, __ZIPNAME__ substituted' || bad 'prompt should substitute __ZIPNAME__ from the template file'
[ "$(share --safe --review --tag share/test-1)" = 0 ] && ok 'safe --tag re-send succeeds' || bad 'safe --tag re-send succeeds'
SPF="$(ls -t "$OUT"/review-prompt-*-safe.txt 2>/dev/null | head -1)"
[ -n "$SPF" ] && grep -q 'safety body stub' "$SPF" && \
  ok 'safety wrapper sourced from template file' || bad 'safety wrapper should come from its template file'
mv templates/prompts/zip-review.txt templates/prompts/zip-review.txt.hold
MISSING_RC=0
MISSING_OUT="$(bash scripts/agent-tiers-share --plain --review --tag share/test-1 -o "$OUT" 2>&1)" || MISSING_RC=$?
[ "$MISSING_RC" != 0 ] && printf '%s' "$MISSING_OUT" | grep -q 'missing prompt template' && \
  ok 'missing template hard-fails (nonzero rc) naming the path' || bad 'missing template should die nonzero naming the path'
# the early preflight means that run appended NO ledger row (nothing state-changing ran)
mv templates/prompts/zip-review.txt.hold templates/prompts/zip-review.txt
# the placeholder guard itself: a template that lost __ZIPNAME__ must die, same early preflight
printf 'no placeholder here\n' > templates/prompts/zip-review.txt
PH_RC=0; PH_OUT="$(bash scripts/agent-tiers-share --plain --review --tag share/test-1 -o "$OUT" 2>&1)" || PH_RC=$?
[ "$PH_RC" != 0 ] && printf '%s' "$PH_OUT" | grep -q 'lost its __ZIPNAME__' && \
  ok 'placeholder-less template hard-fails' || bad 'placeholder-less template should hard-fail'
printf 'review prompt stub zip=__ZIPNAME__\n' > templates/prompts/zip-review.txt

# --macos: dispatch carries run_macos=true, ledger records the fuller tier
# TODO (opus reviewer 2026-08-29, LOW): this proves the script's own arg string, never that
# `run_macos` is the name ../.github/workflows/selfcheck.yml actually declares - a rename on either
# side would still pass. When adding that cross-check: skip SILENTLY if the workflow file is absent
# (it's export-ignored, so a recipient bundle never has it - an `echo SKIP` line here would hard-fail
# that recipient's own share preflight at agent-tiers-share:102).
[ "$(share --plain --review --who macos-test --macos)" = 0 ] && ok '--macos share succeeds' || bad '--macos share succeeds'
tail -1 "$GH_DISPATCH_LOG" | grep -q 'run_macos=true' && ok '--macos dispatch passes run_macos=true' || bad '--macos dispatch should pass run_macos=true'
grep -qE "share/macos-test-1.*verified-full\$" share-ledger.tsv && ok 'ledger records ci_gate=verified-full for --macos' || bad 'ledger should record ci_gate=verified-full for --macos'

# archive honors export-ignore
if command -v unzip >/dev/null 2>&1; then
  Z="$(ls "$OUT"/agent-tiers-test-1-*.zip | head -1)"
  unzip -l "$Z" | grep -q 'agent-tiers/README.md' && ok 'zip contains README' || bad 'zip contains README'
  unzip -l "$Z" | grep -q 'personal.md' && bad 'export-ignored file leaked into zip' || ok 'export-ignored file absent from zip'
else
  echo 'SKIP zip content assertions (unzip missing)'
fi

# second share increments
[ "$(share --plain --review --who test)" = 0 ] || bad 'second share succeeds'
git rev-parse -q --verify refs/tags/share/test-2 >/dev/null && ok 'tag increments to share/test-2' || bad 'tag increments to share/test-2'

# $0 resolution: this is the one script meant to be run by BARE NAME via a PATH symlink (~/bin), and
# a bare name (no `/`) makes `dirname "$0"` == "." - found live 2026-08-24 resolving KIT_DIR to the
# CALLER's cwd instead of the kit. Symlink into a throwaway bin dir, invoke by bare name from a THIRD
# directory (neither the stub kit nor its own bin dir), and confirm it still operates on the stub kit.
BAREBIN="$W-bin"; mkdir -p "$BAREBIN"
ln -s "$W/scripts/agent-tiers-share" "$BAREBIN/agent-tiers-share"
ELSEWHERE="$W-elsewhere"; mkdir -p "$ELSEWHERE"
bare_rc=0
( cd "$ELSEWHERE" && PATH="$BAREBIN:$PATH" agent-tiers-share --plain --review --who bare-test -o "$OUT" >/dev/null 2>&1 ) || bare_rc=$?
[ "$bare_rc" = 0 ] && ok 'bare-name invocation via PATH succeeds' || bad "bare-name invocation via PATH should succeed (got rc=$bare_rc)"
git rev-parse -q --verify refs/tags/share/bare-test-1 >/dev/null && \
  ok 'bare-name invocation tagged the STUB kit, not the caller cwd' || bad 'bare-name invocation should have tagged the stub kit'

# same fix's OTHER repaired shape: the ~/bin symlink invoked by FULL path (old code gave dirname="~/bin",
# so KIT_DIR resolved to $HOME instead of the kit - a different wrong answer than the bare-name case above).
fp_rc=0
( cd "$ELSEWHERE" && bash "$BAREBIN/agent-tiers-share" --plain --review --who fp-test -o "$OUT" >/dev/null 2>&1 ) || fp_rc=$?
[ "$fp_rc" = 0 ] && git rev-parse -q --verify refs/tags/share/fp-test-1 >/dev/null && \
  ok 'symlink invoked by full path resolves the kit' || bad "full-path symlink invocation should resolve the kit (rc=$fp_rc)"

# failing selfcheck blocks the tag
printf 'exit 1\n' > scripts/stub.selfcheck.sh
git add -A; git commit -qm "break stub selfcheck"
[ "$(share --plain --review --who test)" = 1 ] && ok 'red selfcheck aborts' || bad 'red selfcheck aborts'
git rev-parse -q --verify refs/tags/share/test-3 >/dev/null && bad 'red preflight must not tag' || ok 'red preflight left no tag'
printf 'exit 0\n' > scripts/stub.selfcheck.sh
git add -A; git commit -qm "fix stub selfcheck"

# F-17: a selfcheck that exits 0 but SKIPped an assertion must still block (opus reviewer 2026-08-24,
# closes the coverage gap the same review found - the old stub only ever exercised exit-1, never SKIP).
printf 'echo "SKIP: fake tool absent"\nexit 0\n' > scripts/stub.selfcheck.sh
git add -A; git commit -qm "skip stub selfcheck"
SKIP_OUT="$(bash scripts/agent-tiers-share --plain --review --who test -o "$OUT" 2>&1)"
[ "$(share --plain --review --who test)" = 1 ] && ok 'SKIPping selfcheck aborts' || bad 'SKIPping selfcheck aborts'
printf '%s' "$SKIP_OUT" | grep -q 'SKIPPED an assertion' && ok 'SKIP failure names SKIP' || bad 'SKIP failure should name SKIP'
git rev-parse -q --verify refs/tags/share/test-3 >/dev/null && bad 'SKIPping preflight must not tag' || ok 'SKIPping preflight left no tag'
printf 'exit 0\n' > scripts/stub.selfcheck.sh
git add -A; git commit -qm "fix stub selfcheck again"

# --tag re-send: no new tag, but a fresh zip + ledger row
before="$(git tag | wc -l)"
[ "$(share --plain --review --tag share/test-1)" = 0 ] && ok 'tag re-send succeeds' || bad 'tag re-send succeeds'
[ "$(git tag | wc -l)" = "$before" ] && ok 're-send adds no tag' || bad 're-send adds no tag'
# 3 rows: original send, safe-wrapper re-send, and this re-send. The missing-template attempt
# appends NOTHING - the early template preflight dies before any state-changing step.
[ "$(grep -c "share/test-1" share-ledger.tsv)" = 3 ] && ok 're-send appends ledger row' || bad 're-send appends ledger row'
grep -qE "share/test-1.*	n/a\$" share-ledger.tsv && ok 're-send records ci_gate=n/a (gate never runs on --tag)' || bad 're-send should record ci_gate=n/a'
# --tag re-send takes the `else` branch entirely, skipping the CI gate section (and its branch
# variable) altogether - its own ledger commit needs the same push, on its own code path.
[ "$(git -C "$ORIGIN" rev-parse master)" = "$(git rev-parse master)" ] && \
  ok 're-send pushes its own ledger commit' || bad 're-send should push its ledger commit'

# T1.5 (2026-08-16): jq absent -> preflight refuses to tag and NAMES jq (11 selfchecks SKIP with exit 0
# without it, so a green preflight would certify an untested kit). Build a PATH with everything but jq.
# (opus reviewer, 2026-08-16: absolutise each PATH entry, split on `:` only (IFS, no set -f: the inner
# glob needs expansion), skip empty dirs, and test
# `-L` as well as `-e` so a dangling link cannot shadow a later real tool - a farm that goes red for a
# non-jq reason would block tagging while blaming the kit, the very outcome T1.5 exists to prevent.)
NOJQ="$W-nojq"; mkdir -p "$NOJQ"
oldIFS="$IFS"; IFS=:
for d in $PATH; do
  [ -n "$d" ] && [ -d "$d" ] || continue
  d="$(cd "$d" 2>/dev/null && pwd)" || continue
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    n="${f##*/}"; [ "$n" = jq ] && continue
    [ -e "$NOJQ/$n" ] || [ -L "$NOJQ/$n" ] || ln -s "$f" "$NOJQ/$n" 2>/dev/null
  done
done
IFS="$oldIFS"
before="$(git tag | wc -l)"
if PATH="$NOJQ" command -v jq >/dev/null 2>&1; then
  echo 'SKIP jq-absent assertion (could not build a jq-less PATH)'
else
  out="$(PATH="$NOJQ" bash scripts/agent-tiers-share --plain --review --who test -o "$OUT" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && ok 'jq absent: preflight refuses' || bad "jq absent: preflight should exit 1 (got $rc)"
  printf '%s' "$out" | grep -q 'jq is not installed' && ok 'jq absent: reason names jq' || bad "jq absent: reason should name jq (got: $(printf '%s' "$out" | tail -1))"
  [ "$(git tag | wc -l)" = "$before" ] && ok 'jq absent: no tag' || bad 'jq absent: must not tag'
fi
rm -rf "$NOJQ"

# T1.4 (2026-08-16): leak-scan.sh is kit-local (export-ignored) - a recipient re-sharing must be told it
# is NOT PRESENT, not "leak-scan FAILED" (which reads as: a leak was found).
git rm -q scripts/leak-scan.sh; git commit -qm "simulate received bundle (no leak-scan.sh)"
out="$(bash scripts/agent-tiers-share --plain --review --who test -o "$OUT" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok 'leak-scan absent: refuses' || bad "leak-scan absent: should exit 1 (got $rc)"
printf '%s' "$out" | grep -q 'leak-scan.sh not present' && ok 'leak-scan absent: says not present' || bad "leak-scan absent: should say not present (got: $(printf '%s' "$out" | tail -1))"
printf '%s' "$out" | grep -q 'leak-scan FAILED' && bad 'leak-scan absent: must not read as a found leak' || ok 'leak-scan absent: does not claim a leak'
[ "$(git tag | wc -l)" = "$before" ] && ok 'leak-scan absent: no tag' || bad 'leak-scan absent: must not tag'
printf '#!/bin/sh\nexit 0\n' > scripts/leak-scan.sh; git add -A; git commit -qm "restore leak-scan.sh stub"

# Same convention (2026-08-24) for selfcontainment-check.sh: a recipient's partial checkout must be
# told NOT PRESENT, not "FAILED" (which reads as a real defect this check found).
git rm -q scripts/selfcontainment-check.sh; git commit -qm "simulate received bundle (no selfcontainment-check.sh)"
out="$(bash scripts/agent-tiers-share --plain --review --who test -o "$OUT" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok 'selfcontainment-check absent: refuses' || bad "selfcontainment-check absent: should exit 1 (got $rc)"
printf '%s' "$out" | grep -q 'selfcontainment-check.sh not present' && ok 'selfcontainment-check absent: says not present' || bad "selfcontainment-check absent: should say not present (got: $(printf '%s' "$out" | tail -1))"
printf '%s' "$out" | grep -q 'selfcontainment-check FAILED' && bad 'selfcontainment-check absent: must not read as a found defect' || ok 'selfcontainment-check absent: does not claim a defect'
[ "$(git tag | wc -l)" = "$before" ] && ok 'selfcontainment-check absent: no tag' || bad 'selfcontainment-check absent: must not tag'

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

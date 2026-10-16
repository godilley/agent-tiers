#!/usr/bin/env sh
# kit-scope: shared
# Self-check for the external-integrations seam in install-flat.sh. The seam is the one kit mechanism
# whose failures are SILENT: a row can be reported wired, stamped into the ledger and pass its own
# script selfcheck while being absent from settings.json. "Wired" and "fires" are different claims, and
# so are "reported wired" and "wired" - this asserts the third one.
#
# Fully sandboxed: runs the real installer under HOME=$T against a copy of the kit, so it writes only
# inside the temp tree (that also keeps step 5 away from the caller's ~/bin, which is $HOME-absolute).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP install-flat: jq absent (seam is jq-only)"; exit 0; }
unset CLAUDE_CONFIG_DIR   # never inherit the caller's profile; cases that need one set it per call
# Every case skips the installer's post-wire proof loop (it re-runs each hook selfcheck per install);
# case H1 is the one that runs it.
AGENT_TIERS_TEST_SKIP_HOOK_PROOF=1; export AGENT_TIERS_TEST_SKIP_HOOK_PROOF

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
cleanup() { chmod -R u+rwX "$T" 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$1"; cleanup; exit 1; }

mkdir -p "$T/.claude"
cp -a "$ROOT" "$T/.claude/agent-tiers" || fail "could not copy kit"
rm -rf "$T/.claude/agent-tiers/.state"
# Point the copy's managed-settings dirs at an empty temp dir so a host's real /etc/claude-code (or the
# macOS path) cannot change any case. Only demanded when the installer under test has the variable
# (an older installer, run for before/after proof, does not).
mkdir -p "$T/managed"
if grep -q '^IF_MANAGED=' "$T/.claude/agent-tiers/scripts/install-flat.sh"; then
  sed "s|^IF_MANAGED=.*|IF_MANAGED='$T/managed'|" "$T/.claude/agent-tiers/scripts/install-flat.sh" > "$T/if.tmp" \
    && cat "$T/if.tmp" > "$T/.claude/agent-tiers/scripts/install-flat.sh"
  grep -qxF "IF_MANAGED='$T/managed'" "$T/.claude/agent-tiers/scripts/install-flat.sh" || fail "IF_MANAGED not rewritten in the kit copy"
fi
# IFSC_ONLY=<P1|P2|P3|P4|P5|U1|U2|L1|B1|F1|F2|F3|H1> runs just that new case (skips cases 1-13) so each can be
# shown failing alone against an older installer. Unset runs everything.
only() { [ -z "${IFSC_ONLY:-}" ] || [ "$IFSC_ONLY" = "$1" ]; }
I="$T/.claude/agent-tiers/scripts/install-flat.sh"
S="$T/.claude/settings.json"
L="$T/.claude/agent-tiers/.state/integrations.json"
# CMDROOT resolves to the literal $HOME form because ROOT == $HOME/.claude/agent-tiers under this HOME.
CG='sh "$HOME/.claude/agent-tiers/scripts/codex-guard.sh"'
GF='sh "$HOME/.claude/agent-tiers/scripts/grep-footgun-guard.sh"'

install() { HOME="$T" sh "$I" "$@" >"$T/out" 2>&1 || { cat "$T/out"; fail "installer exited non-zero ($*)"; }; }
# A stub notify-send, prefixed onto PATH ONLY for the one case that needs notify's probe to report
# supported (case 2b) - this file's own assertions must not depend on whether THIS host happens to
# have a real notify-send (it does here, but the CI runners this selfcheck also runs on may not,
# which is exactly what made case 2b fail everywhere except this machine before this fix). Never
# actually notifies anything: it is never invoked with any real payload, only probed for presence.
NOTIFYSTUB="$T/notify-stub"; mkdir -p "$NOTIFYSTUB"
printf '#!/usr/bin/env sh\nexit 0\n' > "$NOTIFYSTUB/notify-send"; chmod +x "$NOTIFYSTUB/notify-send"
count() { # $1=event $2=cmd -> how many entries under that event carry that command
  jq --arg ev "$1" --arg c "$2" \
    '[(.hooks[$ev] // [])[] | (.hooks? // [])[] | select(.command == $c)] | length' "$S"
}

if [ -z "${IFSC_ONLY:-}" ]; then
# --- 1. core auto-wire, consent withheld until asked -----------------------------------------------
echo '{}' > "$S"
install
[ "$(count SessionStart 'sh "$HOME/.claude/agent-tiers/scripts/resume-inject.sh"')" = 1 ] \
  || fail "core row (resume-inject) should auto-wire"
[ "$(count SessionEnd 'sh "$HOME/.claude/agent-tiers/scripts/guard-summary.sh"')" = 1 ] \
  || fail "core row (guard-summary, SessionEnd) should auto-wire"
[ "$(count PreToolUse "$CG")" = 0 ] || fail "consent row must NOT wire without --with-<id>"
[ "$(count PreCompact 'sh "$HOME/.claude/agent-tiers/scripts/precompact-guard.sh"')" = 0 ] \
  || fail "consent row (precompact-guard) must NOT wire without --with-<id>"
[ "$(count Notification 'sh "$HOME/.claude/agent-tiers/scripts/notify.sh"')" = 0 ] \
  || fail "consent row (notify) must NOT wire without --with-<id>"

# --- 2. consent wiring + ledger stamp --------------------------------------------------------------
install --with-codex-guard
[ "$(count PreToolUse "$CG")" = 1 ] || fail "--with-codex-guard should wire the row"
[ "$(jq -r '.["codex-guard"].event' "$L")" = PreToolUse ] || fail "ledger should record the event"

# --- 2b. non-PreToolUse consent rows wire the same way (precompact-guard: PreCompact, notify: Notification).
#         precompact-guard's install-time probe now refuses without authorship-record also wired/requested
#         (see case 13) - request it alongside here so this wiring-shape test still succeeds. notify's
#         probe is now host-only (notify-send on PATH, nothing terminal-related - see notify.sh's own
#         header) - HOST-INDEPENDENT via $NOTIFYSTUB, not this test host's ambient notify-send, so the
#         probe is exercised as genuinely SUPPORTED on any CI leg, not merely on a machine that happens
#         to have notify-send installed (the bug this replaces: this case used to fail on any host
#         without a real notify-send, CI included).
PATH="$NOTIFYSTUB:$PATH" install --with-authorship-record --with-precompact-guard --with-notify
[ "$(count PreCompact 'sh "$HOME/.claude/agent-tiers/scripts/precompact-guard.sh"')" = 1 ] \
  || fail "--with-precompact-guard should wire the PreCompact row"
[ "$(jq -r '.["precompact-guard"].event' "$L")" = PreCompact ] || fail "ledger should record precompact-guard's event"
[ "$(count Notification 'sh "$HOME/.claude/agent-tiers/scripts/notify.sh"')" = 1 ] \
  || fail "--with-notify should wire the Notification row"
[ "$(jq -r '.["notify"].event' "$L")" = Notification ] || fail "ledger should record notify's event"
# Unwire again immediately so later cases start from the core rows only. (Written when every later
# install() re-ran each wired row's selfcheck; AGENT_TIERS_TEST_SKIP_HOOK_PROOF, exported at the top,
# now skips that proof step here, so the remaining reason is a clean baseline. Case H1 runs the loop.)
install --without-authorship-record --without-precompact-guard --without-notify

# --- 3. THE SILENT ONE: the same command present under a DIFFERENT event must not be mistaken for
#        this row being wired. A file-wide count reports it green and wires nothing.
echo '{}' > "$S"; echo '{}' > "$L"
jq --arg c "$CG" '.hooks.PostToolUse = [{matcher:"Bash", hooks:[{type:"command", command:$c, timeout:5}]}]' \
  "$S" > "$S.t" && mv "$S.t" "$S"
install --with-codex-guard
[ "$(count PreToolUse "$CG")" = 1 ] \
  || fail "row wired under another event must not suppress wiring the target event (guard silently absent)"

# --- 4. removal blast radius: its own event only, siblings and other events survive -----------------
echo '{}' > "$S"; echo '{}' > "$L"
install --with-codex-guard --with-grep-footgun-guard
jq --arg c "$CG" '.hooks.PostToolUse = [{matcher:"Bash", hooks:[{type:"command", command:$c, timeout:5}]}]' \
  "$S" > "$S.t" && mv "$S.t" "$S"
before_ss="$(jq '.hooks.SessionStart | length' "$S")"
install --without-codex-guard
[ "$(count PreToolUse "$CG")" = 0 ] || fail "--without-<id> should remove the row from its event"
[ "$(count PreToolUse "$GF")" = 1 ] || fail "sibling row in the same group must survive removal"
[ "$(count PostToolUse "$CG")" = 1 ] || fail "removal must not reach into another event"
[ "$(jq '.hooks.SessionStart | length' "$S")" = "$before_ss" ] || fail "removal must not touch other events"
jq -e '.["codex-guard"]' "$L" >/dev/null 2>&1 && fail "ledger row should be dropped on --without-<id>"

# --- 5. rewire: a kit-owned row whose command drifted is updated in place, not duplicated -----------
echo '{}' > "$S"; echo '{}' > "$L"
install --with-codex-guard
jq --arg c "$CG" '.hooks.PreToolUse |= map(.hooks |= map(if .command == $c then .command = "sh \"/OLD/codex-guard.sh\"" else . end))' \
  "$S" > "$S.t" && mv "$S.t" "$S"
jq '.["codex-guard"].command = "sh \"/OLD/codex-guard.sh\""' "$L" > "$L.t" && mv "$L.t" "$L"
install --with-codex-guard
[ "$(count PreToolUse "$CG")" = 1 ] || fail "stale kit-owned row should be rewired to the target command"
[ "$(count PreToolUse 'sh "/OLD/codex-guard.sh"')" = 0 ] || fail "rewire should leave no stale duplicate"

# --- 5b. matcher drift: the SAME command wired under a different matcher is moved, not left (opus
#         reviewer Wave B 2026-08-16, HIGH: security-gate's matcher gained Bash and upgrades kept the old one)
echo '{}' > "$S"; echo '{}' > "$L"
install --with-codex-guard
jq --arg c "$CG" '.hooks.PreToolUse |= (map(.hooks |= map(select(.command != $c))) | map(select((.hooks|length)>0)) | . + [{matcher:"Write", hooks:[{type:"command", command:$c, timeout:5}]}])' \
  "$S" > "$S.t" && mv "$S.t" "$S"
install --with-codex-guard
grep -q 'codex-guard REWIRED.*matcher drift' "$T/out" || fail "matcher drift should be reported as a rewire"
# An unwired consent row names its group option (the CLI route), not only the per-row flag (row P1).
grep -q 'memory-write-gate available, NOT wired.*configure --set group_memory=true' "$T/out" || fail "an unwired consent row should name its group option"
[ "$(jq --arg c "$CG" '[.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[] | select(.command==$c)] | length' "$S")" = 1 ] || fail "drifted row should be moved under the target matcher"
[ "$(jq --arg c "$CG" '[.hooks.PreToolUse[] | select(.matcher=="Write") | .hooks[] | select(.command==$c)] | length' "$S")" = 0 ] || fail "drifted row should not remain under the old matcher"
[ "$(count PreToolUse "$CG")" = 1 ] || fail "matcher rewire must not duplicate the row"

# --- 6. a foreign (hand-written) row mentioning a kit script is reported, never touched -------------
echo '{}' > "$S"; echo '{}' > "$L"
jq '.hooks.SessionStart = [{hooks:[{type:"command", command:"sh \"/elsewhere/resume-inject.sh\"", timeout:9}]}]' \
  "$S" > "$S.t" && mv "$S.t" "$S"
install
grep -q "FOREIGN" "$T/out" || fail "a foreign row mentioning a kit script should be reported"
[ "$(count SessionStart 'sh "/elsewhere/resume-inject.sh"')" = 1 ] || fail "foreign row must be left untouched"

# --- 7. a mis-shaped ledger is moved aside, not trusted ---------------------------------------------
echo '[]' > "$L"
install
grep -q "ledger was invalid" "$T/out" || fail "non-object ledger should be moved aside"
[ "$(jq -r 'type' "$L")" = object ] || fail "ledger should be rebuilt as an object"

# --- 8. invalid settings.json: skip all wiring rather than write over it -----------------------------
cp "$S" "$T/settings.good"; printf '{ broken' > "$S"
if HOME="$T" sh "$I" >"$T/out" 2>&1; then fail "invalid settings.json skips all wiring, so the install must exit non-zero"; fi
grep -q "SKIPPING all hook wiring" "$T/out" || fail "invalid settings.json should skip wiring"
grep -q "broken" "$S" || fail "invalid settings.json must be left exactly as found"
cp "$T/settings.good" "$S"

# --- 9. settings backups are bounded: they are verbatim copies of a secret-bearing file ------------
# Pre-plant dated backups rather than looping installs: the backup name is second-resolution, and eight
# installs finish inside ~3s, so the names collide and the assertion would hold with the prune deleted.
rm -f "$S".bak-*
for d in 20200101 20200102 20200103 20200104 20200105 20200106 20200107 20200108; do
  cp -p "$S" "$S.bak-$d-000000"
done
install
n_bak="$(ls -1 "$S".bak-* 2>/dev/null | wc -l)"
[ "$n_bak" -le 5 ] || fail "settings backups should be pruned to 5, found $n_bak"
[ "$n_bak" -ge 1 ] || fail "at least one settings backup should be kept"
# The survivors must be the NEWEST: the oldest planted date must be gone.
[ -f "$S.bak-20200101-000000" ] && fail "pruning kept the oldest backup instead of the newest"

# --- 10. CLAUDE_CONFIG_DIR: a second Claude profile gets the WHOLE kit, not just the hooks ----------
# Claude Code treats that dir as the entire config root, so a split install (hooks there, skills here)
# leaves the second account with guards and no tiers. The default profile must be left alone.
ALT="$T/altprofile"
mkdir -p "$ALT"
# Establish a known default-profile state to compare against (earlier cases left it deliberately churned).
echo '{}' > "$S"; echo '{}' > "$L"
install --with-codex-guard
default_settings_before="$(cat "$S")"
HOME="$T" CLAUDE_CONFIG_DIR="$ALT" sh "$I" --with-codex-guard >"$T/out" 2>&1 \
  || { cat "$T/out"; fail "install into an alternate profile should succeed"; }
[ -e "$ALT/skills/agent-tiers" ]                  || fail "alt profile should receive skills"
[ -e "$ALT/agents/worker.md" ]                    || fail "alt profile should receive agents"
[ -f "$ALT/commands/agent-tiers-doctor.md" ]      || fail "alt profile should receive commands"
[ -f "$ALT/settings.json" ]                       || fail "alt profile should receive settings.json"
jq -e '.hooks.PreToolUse' "$ALT/settings.json" >/dev/null 2>&1 || fail "alt profile should get its hooks"
# Cross-profile symlinks must be absolute: a relative ../agent-tiers would resolve against the wrong root.
[ -d "$ALT/skills/agent-tiers" ] || fail "alt profile skill symlink should resolve (absolute target)"

# --- 10b. bare-placeholder hygiene (cold-review F7): nothing the harness loads may carry a BARE
# ${CLAUDE_PLUGIN_ROOT}/${AGENT_TIERS_LEDGER}. Commands are sed-baked; skills/agents are symlinked
# and never baked (kit CLAUDE.md), so their bodies must use the ${CLAUDE_PLUGIN_ROOT:-...} default
# form - which this bare-form ERE deliberately does NOT match (the char after ROOT is `:` not `}`).
# grep -R (capital), not -r: the flattened view IS symlinks, and -r skips symlinked dirs, which
# would make this assertion pass vacuously on the exact shape it exists to catch.
for view in "$T/.claude" "$ALT"; do
  if grep -RlE '\$\{CLAUDE_PLUGIN_ROOT\}|\$\{AGENT_TIERS_LEDGER\}' \
      "$view/skills/" "$view/agents/" "$view/commands/" 2>/dev/null | grep -q .; then
    fail "flattened view under $view serves a bare placeholder (F7 regression)"
  fi
done
# Re-run must be idempotent on its own artifacts - clear_dest replaces kit-managed dests, no .bak spam.
HOME="$T" CLAUDE_CONFIG_DIR="$ALT" sh "$I" >"$T/out" 2>&1 || { cat "$T/out"; fail "idempotent re-run should succeed"; }
ls -d "$ALT/skills/"*.bak-* "$ALT/agents/"*.bak-* 2>/dev/null | grep -q . \
  && fail "re-run backed up its own artifacts instead of replacing them"
# The default profile is untouched, and its ledger is not overwritten by the second profile's rows.
[ "$(cat "$S")" = "$default_settings_before" ] || fail "installing into another profile must not touch this one"
[ "$(jq -r '.["codex-guard"].settings' "$L")" = "$S" ] \
  || fail "default-profile ledger row should still point at the default settings.json"
alt_ledger="$(ls "$T/.claude/agent-tiers/.state"/integrations.*.json 2>/dev/null | head -1)"
[ -n "$alt_ledger" ] || fail "alt profile should get its OWN ledger file, not share the default one"
[ "$(jq -r '.["codex-guard"].settings' "$alt_ledger")" = "$ALT/settings.json" ] \
  || fail "alt ledger should record the alt profile's settings path"
# doctor's per-profile copy must carry that profile's ledger path, not a stale placeholder.
grep -q "$alt_ledger" "$ALT/commands/agent-tiers-doctor.md" \
  || fail "doctor copy should have the profile's ledger path baked in"
grep -q 'AGENT_TIERS_LEDGER' "$ALT/commands/agent-tiers-doctor.md" \
  && fail "the ledger placeholder should be substituted, not left literal"

# --- 11. T1.4 (2026-08-16): an EXPLICITLY requested --with-<id> whose script is missing from this kit
#         copy (a bundle excludes export-ignored scripts) must hard-error, not warn-and-continue - the
#         same "successful install, consent control silently absent" outcome the unknown-id error
#         prevents. An UNREQUESTED missing row still soft-skips (received bundles legitimately lack it).
rm -f "$T/.claude/agent-tiers/scripts/kit-leak-guard.sh"
echo '{}' > "$S"; echo '{}' > "$L"
if HOME="$T" sh "$I" --with-kit-leak-guard >"$T/out" 2>&1; then
  fail "--with-<id> for a script missing from this copy must exit non-zero (would report a consent control that is absent)"
fi
grep -q 'not in this kit copy' "$T/out" || fail "missing-requested-id error should name the real reason (got: $(head -c 300 "$T/out"))"
[ "$(count PreToolUse 'sh "$HOME/.claude/agent-tiers/scripts/kit-leak-guard.sh"')" = 0 ] || fail "must not wire a row whose script is absent"
HOME="$T" sh "$I" >"$T/out" 2>&1 || { cat "$T/out"; fail "unrequested missing row must still soft-skip (plain install should succeed)"; }

# --- 12. memory-content-lint hook row (2026-09): consent-gated, wires under PostToolUse with the
#         Write|Edit|MultiEdit matcher (MultiEdit added per Lead decision: legacy per permissions.md, but
#         still a live tool the CLI accepts - errors.md/permissions.md do not say it is refused) and not
#         before --with- is asked for.
MCL='sh "$HOME/.claude/agent-tiers/scripts/memory-content-lint.sh"'
echo '{}' > "$S"; echo '{}' > "$L"
install
[ "$(count PostToolUse "$MCL")" = 0 ] || fail "memory-content-lint must NOT wire without --with-memory-content-lint"
install --with-memory-content-lint
[ "$(jq --arg c "$MCL" '[.hooks.PostToolUse[] | select(.matcher=="Write|Edit|MultiEdit") | .hooks[] | select(.command==$c)] | length' "$S")" = 1 ] \
  || fail "--with-memory-content-lint should wire under PostToolUse with matcher Write|Edit|MultiEdit"
[ "$(jq -r '.["memory-content-lint"].event' "$L")" = PostToolUse ] || fail "ledger should record memory-content-lint's event"

# --- 13. Support probe: --with-notify on a host with no notify-send must be REFUSED (nonzero
#         exit), writing nothing - regardless of TERM, since the probe is HOST-ONLY now (no
#         terminal detection at all - see notify.sh's own header on why a per-session fact does
#         not belong in an install-time probe). A minimal WHITELIST, not a full mirror of
#         /usr/bin+/bin+/usr/local/bin (that walked every file in all three, ~10^4 forks, adding
#         ~20s to this file's runtime for no coverage gain - same pattern already fixed in
#         notify.selfcheck.sh's own BASE_TOOLS). The list is install-flat.sh's own documented
#         preflight set (scripts/install-flat.sh:182: sed awk cksum date cut wc du tr grep head
#         sort env ln cp mv rm mkdir mktemp cat ls basename dirname find) plus jq (used throughout,
#         optional at runtime but present on this test host), sh (the probe loop execs `sh
#         scripts/<id>.sh --probe` directly), chmod (settings-backup permission clamp) and readlink
#         (the optional ~/bin/agent-tiers-share symlink step) - deliberately leaving notify-send
#         OUT, the one binary this case exists to prove is absent.
MIRROR="$T/mirror-no-notify-send"; mkdir -p "$MIRROR"
for tool in sed awk cksum date cut wc du tr grep head sort env ln cp mv rm mkdir mktemp cat ls \
            basename dirname find jq sh chmod readlink; do
  p="$(command -v "$tool" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$MIRROR/$tool" 2>/dev/null
done
[ -e "$MIRROR/notify-send" ] && fail "fixture invalid: mirror PATH must not contain notify-send"
echo '{}' > "$S"; echo '{}' > "$L"
before_settings="$(cat "$S")"
if HOME="$T" PATH="$MIRROR" sh "$I" --with-notify >"$T/out" 2>&1; then
  fail "--with-notify on a host with no notify-send should be refused (installer exited 0)"
fi
grep -q 'refusing --with-notify' "$T/out" || fail "refusal should name the row (got: $(head -c 300 "$T/out"))"
grep -q 'force-with-notify' "$T/out" || fail "refusal should name the --force-with-notify escape hatch (got: $(head -c 300 "$T/out"))"
[ "$(cat "$S")" = "$before_settings" ] || fail "a refused probe must leave settings.json byte-identical"

# --- 13b. The refusal holds even with a RECOGNISED OSC terminal env set - proves the probe reads
#          none of TERM/TERM_PROGRAM/WT_SESSION/GHOSTTY_RESOURCES_DIR any more (an earlier version
#          of this probe would have accepted this exact case, which the review flagged as the wrong
#          snapshot: which terminal a FUTURE session runs in is not a host-install-time fact).
echo '{}' > "$S"; echo '{}' > "$L"
before_settings="$(cat "$S")"
if HOME="$T" TERM=xterm-kitty PATH="$MIRROR" sh "$I" --with-notify >"$T/out" 2>&1; then
  fail "--with-notify must be refused on TERM=xterm-kitty with no notify-send - the probe must not resurrect terminal detection"
fi
[ "$(cat "$S")" = "$before_settings" ] || fail "a refused probe must leave settings.json byte-identical"

# --- 14. Support probe: --with-precompact-guard alone (no authorship-record wired or requested) is
#         refused; requesting both together in one install succeeds.
echo '{}' > "$S"; echo '{}' > "$L"
before_settings="$(cat "$S")"
if HOME="$T" sh "$I" --with-precompact-guard >"$T/out" 2>&1; then
  fail "--with-precompact-guard without authorship-record should be refused"
fi
grep -q 'refusing --with-precompact-guard' "$T/out" || fail "refusal should name the row (got: $(head -c 300 "$T/out"))"
[ "$(cat "$S")" = "$before_settings" ] || fail "a refused probe must leave settings.json byte-identical"
HOME="$T" sh "$I" --with-authorship-record --with-precompact-guard >"$T/out" 2>&1 \
  || { cat "$T/out"; fail "--with-authorship-record --with-precompact-guard together should succeed"; }
[ "$(count PreCompact 'sh "$HOME/.claude/agent-tiers/scripts/precompact-guard.sh"')" = 1 ] \
  || fail "precompact-guard should be wired when authorship-record is requested alongside it"

# --- 13. install/options.tsv absent -> the installer exits non-zero before writing settings or ledger.
OT="$T/.claude/agent-tiers/install/options.tsv"
echo '{}' > "$S"; rm -f "$L"
mv "$OT" "$T/options.tsv.bak"
if HOME="$T" sh "$I" >"$T/out" 2>&1; then fail "missing install/options.tsv must make the installer exit non-zero"; fi
grep -q 'options.tsv' "$T/out" || fail "missing options.tsv error should name the file (got: $(head -c 300 "$T/out"))"
[ "$(cat "$S")" = '{}' ] || fail "settings.json must be untouched when options.tsv is missing"
[ ! -e "$L" ] || fail "ledger must not be written when options.tsv is missing"
mv "$T/options.tsv.bak" "$OT"

# --- 13b. a malformed hook row (6 fields, bad requires syntax, unknown required id) makes the installer exit
#     non-zero, naming options.tsv, before it writes settings or ledger. The file is restored after each.
cp "$OT" "$T/options.tsv.bak"
for bad in 'cut' 'syntax' 'unknown' 'self'; do
  msg=''
  case "$bad" in
    cut) awk -F'\t' -v OFS='\t' '$1 == "hook" && !d { print $1, $2, $3, $4, $5, $6; d = 1; next } 1' "$T/options.tsv.bak" > "$OT"; msg='needs 7 fields' ;;
    syntax) awk -F'\t' -v OFS='\t' '$1 == "hook" && !d { $7 = "a b"; d = 1 } 1' "$T/options.tsv.bak" > "$OT"; msg='requires column is not' ;;
    unknown) awk -F'\t' -v OFS='\t' '$1 == "hook" && !d { $7 = "no-such-hook"; d = 1 } 1' "$T/options.tsv.bak" > "$OT"; msg='requires unknown hook id' ;;
    self) awk -F'\t' -v OFS='\t' '$1 == "hook" && !d { $7 = $2; d = 1 } 1' "$T/options.tsv.bak" > "$OT"; msg='requires itself' ;;
  esac
  echo '{}' > "$S"; rm -f "$L"
  if HOME="$T" sh "$I" >"$T/out" 2>&1; then fail "13b ($bad): a bad hook row must make the installer exit non-zero"; fi
  grep -q 'options.tsv' "$T/out" || fail "13b ($bad): error should name options.tsv (got: $(head -c 300 "$T/out"))"
  [ -z "$msg" ] || grep -q "$msg" "$T/out" || fail "13b ($bad): error should contain '$msg' (got: $(head -c 300 "$T/out"))"
  [ "$(cat "$S")" = '{}' ] || fail "13b ($bad): settings.json must be untouched"
  [ ! -e "$L" ] || fail "13b ($bad): ledger must not be written"
done
cat "$T/options.tsv.bak" > "$OT"; rm -f "$T/options.tsv.bak"
fi   # end of cases 1-13 (skipped under IFSC_ONLY)

try() { HOME="$T" sh "$I" "$@" >"$T/out" 2>&1; }
reset() { mkdir -p "$(dirname "$L")"; echo '{}' > "$S"; echo '{}' > "$L"; rm -f "$S".bak-*; rm -rf "$T/.claude/commands" "$T/.claude/skills" "$T/.claude/agents"; }
ENABLED='{"enabledPlugins":{"agent-tiers@m":true}}'

# --- P1. a plugin enabled in the profile's settings.json: every install mode refuses, nothing written
if only P1; then
  reset; echo "$ENABLED" > "$S"
  for a in "" "--with-codex-guard"; do
    # shellcheck disable=SC2086
    if try $a; then fail "P1: install ($a) must be refused while agent-tiers@m is enabled in settings.json"; fi
    [ "$(cat "$S")" = "$ENABLED" ] || fail "P1: refused install must leave settings.json byte-identical ($a)"
    [ ! -e "$T/.claude/commands" ] && [ ! -e "$T/.claude/skills" ] || fail "P1: refused install must write no skills/commands ($a)"
    ls "$S".bak-* >/dev/null 2>&1 && fail "P1: refused install must take no backup ($a)"
    grep -q 'agent-tiers@m' "$T/out" && grep -q -- '--unwire-only' "$T/out" || fail "P1: refusal should name agent-tiers@m and --unwire-only (got: $(head -c 300 "$T/out"))"
  done
fi

# --- P2. enabled only in a managed file; a later managed-settings.d file can switch it off
if only P2; then
  reset; mkdir -p "$T/managed/managed-settings.d"
  echo "$ENABLED" > "$T/managed/managed-settings.json"
  if try; then fail "P2: a plugin enabled only in a managed file must refuse the install"; fi
  grep -q 'managed-settings.json' "$T/out" || fail "P2: refusal should name the managed file (got: $(head -c 300 "$T/out"))"
  echo '{"enabledPlugins":{"agent-tiers@m":false}}' > "$T/managed/managed-settings.d/x.json"
  try || { cat "$T/out"; fail "P2: a later managed file setting it false must lift the refusal"; }
  rm -rf "$T/managed"; mkdir -p "$T/managed"
fi

# --- P3. disabled, or some other plugin enabled: not a refusal
if only P3; then
  reset; echo '{"enabledPlugins":{"agent-tiers@m":false}}' > "$S"
  try || { cat "$T/out"; fail "P3: agent-tiers@m=false must not refuse"; }
  reset; echo '{"enabledPlugins":{"other@m":true}}' > "$S"
  try || { cat "$T/out"; fail "P3: an unrelated enabled plugin must not refuse"; }
fi

# --- P4. --check and --unwire-only still run with the plugin enabled
if only P4; then
  reset; try || { cat "$T/out"; fail "P4: setup install failed"; }
  echo "$ENABLED" > "$S"
  try --check || { cat "$T/out"; fail "P4: --check must run with the plugin enabled"; }
  try --unwire-only || { cat "$T/out"; fail "P4: --unwire-only must run (exit 0) with the plugin enabled"; }
fi

# --- P5. a plugin-cache kit root refuses; the same tree without installed_plugins.json does not
if only P5; then
  reset
  PC="$T/pc/plugins/cache/mk/agent-tiers/1.0.0"; mkdir -p "$PC"
  cp -a "$T/.claude/agent-tiers/." "$PC/" && rm -rf "$PC/.state" || fail "P5: could not build the plugin-cache copy"
  : > "$T/pc/plugins/installed_plugins.json"
  if HOME="$T" CLAUDE_CONFIG_DIR="$T/pcprofile" sh "$PC/scripts/install-flat.sh" >"$T/out" 2>&1; then
    fail "P5: an install from a plugin-cache kit root must be refused"
  fi
  [ ! -e "$T/pcprofile/settings.json" ] || fail "P5: refused install must not create settings.json"
  [ ! -e "$T/pcprofile/skills" ] && [ ! -e "$T/pcprofile/commands" ] || fail "P5: refused install must write no skills/commands"
  grep -q 'agent-tiers@mk' "$T/out" || fail "P5: refusal should name agent-tiers@mk (got: $(head -c 300 "$T/out"))"
  rm -f "$T/pc/plugins/installed_plugins.json"
  HOME="$T" CLAUDE_CONFIG_DIR="$T/pcprofile" sh "$PC/scripts/install-flat.sh" >"$T/out" 2>&1 \
    || { cat "$T/out"; fail "P5: without installed_plugins.json the same tree is not a plugin route and must install"; }
fi

# --- U1. --unwire-only removes only hook rows and creates/links/copies nothing
if only U1; then
  reset; install; install --with-codex-guard
  jq '.hooks.Stop = ((.hooks.Stop // []) + [{hooks:[{type:"command",command:"echo keep"}]}])' "$S" > "$S.t" && mv "$S.t" "$S"
  rm -f "$T/.claude/skills/agent-tiers"; mkdir -p "$T/.claude/skills/agent-tiers"; echo x > "$T/.claude/skills/agent-tiers/keep"
  rm -f "$T/.claude/agent-tiers/kit-config.md"
  try --unwire-only --without-codex-guard || { cat "$T/out"; fail "U1: --unwire-only --without-codex-guard should succeed"; }
  [ "$(count PreToolUse "$CG")" = 0 ] || fail "U1: codex-guard row should be gone"
  [ "$(count SessionStart 'sh "$HOME/.claude/agent-tiers/scripts/resume-inject.sh"')" = 1 ] || fail "U1: core rows must stay when only codex-guard is named"
  [ -f "$T/.claude/skills/agent-tiers/keep" ] || fail "U1: unwire-only must not touch skills"
  ls -d "$T/.claude/skills/"*.bak-* >/dev/null 2>&1 && fail "U1: unwire-only must not back up/replace skills"
  [ ! -e "$T/.claude/agent-tiers/kit-config.md" ] || fail "U1: unwire-only must not recreate kit-config.md"
  jq -e '.["codex-guard"]' "$L" >/dev/null 2>&1 && fail "U1: ledger should drop the codex-guard row"
  grep -q 'done (unwire only)' "$T/out" || fail "U1: final line should be 'done (unwire only).'"
  try --unwire-only || { cat "$T/out"; fail "U1: bare --unwire-only should succeed"; }
  for id in $(awk -F'\t' '$1 == "hook" { print $2 }' "$T/.claude/agent-tiers/install/options.tsv"); do
    [ "$(jq --arg n "/scripts/$id.sh" '[.. | strings | select(contains($n))] | length' "$S")" = 0 ] \
      || fail "U1: bare --unwire-only left a row for $id"
  done
  [ "$(count Stop 'echo keep')" = 1 ] || fail "U1: an unrelated row must survive --unwire-only"
fi

# --- U2. --unwire-only edge cases: no settings file, invalid JSON, a forbidden flag mix
if only U2; then
  reset; rm -f "$S"
  try --unwire-only || { cat "$T/out"; fail "U2: absent settings.json should be a clean no-op (exit 0)"; }
  [ ! -e "$S" ] || fail "U2: unwire-only must not create settings.json"
  printf '{ broken' > "$S"
  if try --unwire-only; then fail "U2: invalid settings.json must make --unwire-only exit non-zero"; fi
  [ "$(cat "$S")" = '{ broken' ] || fail "U2: invalid settings.json must be left as found"
  echo '{}' > "$S"; rm -f "$S".bak-*
  if try --unwire-only --with-codex-guard; then fail "U2: --unwire-only with --with-* must be a usage error"; fi
  [ "$(cat "$S")" = '{}' ] && ! ls "$S".bak-* >/dev/null 2>&1 || fail "U2: the usage error must write nothing"
fi

# --- L1. a symlinked settings.json is written through, never replaced
if only L1; then
  reset; mv "$S" "$T/real-settings.json" && ln -s "$T/real-settings.json" "$S" || fail "L1: could not build the symlink"
  RS="$T/real-settings.json"
  try --with-codex-guard || { cat "$T/out"; fail "L1: wire through a symlink failed"; }
  [ -L "$S" ] || fail "L1: --with-codex-guard replaced the symlinked settings.json"
  [ "$(jq --arg c "$CG" '[.hooks.PreToolUse[]?.hooks[]? | select(.command == $c)] | length' "$RS")" = 1 ] || fail "L1: the link target should hold the new row"
  try --without-codex-guard || { cat "$T/out"; fail "L1: remove through a symlink failed"; }
  [ -L "$S" ] || fail "L1: --without-codex-guard replaced the symlinked settings.json"
  [ "$(jq --arg c "$CG" '[.hooks.PreToolUse[]?.hooks[]? | select(.command == $c)] | length' "$RS")" = 0 ] || fail "L1: the link target should have lost the row"
  try --unwire-only || { cat "$T/out"; fail "L1: unwire through a symlink failed"; }
  [ -L "$S" ] || fail "L1: --unwire-only replaced the symlinked settings.json"
  [ "$(jq '[.. | strings | select(contains("/scripts/resume-inject.sh"))] | length' "$RS")" = 0 ] || fail "L1: the link target should have lost the core rows"
  rm -f "$S" "$RS"; echo '{}' > "$S"
fi

# A stub `date` for the backup-name cases: the one format pick_backup asks for is pinned to a fixed
# second, so a case can pre-create the colliding names without racing the clock (a slow host used to
# reach pick_backup after the pre-created names, and the case passed without testing anything).
DS="$T/datestub"; mkdir -p "$DS"
{ echo '#!/bin/sh'; echo "case \"\$1\" in +%Y%m%d-%H%M%S) echo 20300101-000000 ;; *) exec $(command -v date) \"\$@\" ;; esac"; } > "$DS/date"
chmod +x "$DS/date"
BK="$S.bak-20300101-000000"
try_pinned() { ( PATH="$DS:$PATH"; export PATH; try "$@" ); }

# --- B1. a backup name already taken (by the CLI, same second) is never overwritten
if only B1; then
  reset
  echo cli-backup > "$BK"; echo cli-backup > "$BK-2"
  try_pinned || { cat "$T/out"; fail "B1: installer failed"; }
  [ -f "$BK-3" ] || fail "B1: precondition not met: the installer did not pick the pinned name's -3 slot (stub date unused?)"
  for f in "$BK" "$BK-2"; do
    [ "$(cat "$f")" = cli-backup ] || fail "B1: pre-existing backup $f was overwritten"
  done
  ls -1 "$S".bak-* | grep -qvE 'settings\.json\.bak-[0-9]{8}-[0-9]{6}(-[2-9])?$' && fail "B1: backup names must match the CLI scheme"
fi

# --- F1. partial failures exit non-zero and are worded truthfully
if only F1; then
  # (b) every backup name for this second taken: hook wiring is skipped, which must not exit 0
  reset
  echo x > "$BK"; for k in 2 3 4 5 6 7 8 9; do echo x > "$BK-$k"; done
  if try_pinned; then fail "F1b: install skipped for exhausted backups but exited 0"; fi
  grep -q 'too many settings backups' "$T/out" || fail "F1b: precondition not met: no 'too many settings backups' line (got: $(head -c 300 "$T/out"))"
  # (a)+(c) a read-only symlink target: the removal write fails AND so does the restore
  reset
  if [ "$(id -u)" = 0 ]; then
    echo "note F1a/F1c: running as root, a read-only file does not stop the write - cases not exercised"
  else
    RS="$T/real-settings.json"; mv "$S" "$RS" && ln -s "$RS" "$S" || fail "F1: could not build the symlink"
    try --with-codex-guard || { cat "$T/out"; fail "F1: setup wire failed"; }
    chmod 444 "$RS"
    if try --without-codex-guard; then chmod 644 "$RS"; fail "F1a: a failed --without removal must not exit 0"; fi
    chmod 644 "$RS"
    grep -q 'codex-guard removal FAILED' "$T/out" || fail "F1a: precondition not met: no removal FAILED line (got: $(head -c 400 "$T/out"))"
    grep 'removal FAILED' "$T/out" | grep -q 'settings.json unchanged' && fail "F1c: restore failed too, yet the line claims settings.json is unchanged"
    grep 'removal FAILED' "$T/out" | grep -q "backup $S.bak-" || fail "F1c: the line must name the surviving backup (got: $(grep 'removal FAILED' "$T/out"))"
    rm -f "$S" "$RS"; echo '{}' > "$S"
  fi
fi

# --- F3. install mode: invalid settings.json (wiring skipped) and a failed wire also exit non-zero
if only F3; then
  reset; printf '{ broken' > "$S"
  if try; then fail "F3: invalid settings.json skipped all wiring but the install exited 0"; fi
  grep -q 'SKIPPING all hook wiring' "$T/out" || fail "F3: precondition not met: no SKIPPING line (got: $(head -c 300 "$T/out"))"
  grep -q 'finished with errors' "$T/out" || fail "F3: expected the end-of-run 'finished with errors' line"
  reset
  if [ "$(id -u)" = 0 ]; then
    echo "note F3 (wire FAILED): running as root, a read-only file does not stop the write - not exercised"
  else
    RS="$T/real-settings.json"; mv "$S" "$RS" && ln -s "$RS" "$S" || fail "F3: could not build the symlink"
    chmod 444 "$RS"
    if try --with-codex-guard; then chmod 644 "$RS"; fail "F3: a failed wire must not exit 0"; fi
    chmod 644 "$RS"
    grep -q 'codex-guard wire FAILED' "$T/out" || fail "F3: precondition not met: no wire FAILED line (got: $(head -c 400 "$T/out"))"
    grep -q 'finished with errors' "$T/out" || fail "F3: expected the end-of-run 'finished with errors' line"
    rm -f "$S" "$RS"; echo '{}' > "$S"
  fi
fi

# --- F2. plugin-refusal edge cases: a key with a space, a non-object enabledPlugins
if only F2; then
  reset; echo '{"enabledPlugins":{"agent-tiers@my mk":true}}' > "$S"
  if try; then fail "F2d: a plugin key with a space must still refuse"; fi
  grep -qF 'agent-tiers@my mk is enabled' "$T/out" || fail "F2d: the whole key must be named (got: $(head -c 300 "$T/out"))"
  reset; echo '{"enabledPlugins":"agent-tiers@m"}' > "$S"
  if try; then fail "F2e: a non-object enabledPlugins must still refuse"; fi
  grep -q 'not a JSON object' "$T/out" || fail "F2e: expected a 'not a JSON object' reason (got: $(head -c 300 "$T/out"))"
  grep -q 'not valid JSON' "$T/out" && fail "F2e: valid JSON must not be called invalid"
  reset; printf '{"x":"agent-tiers@", ' > "$S"
  if try; then fail "F2e: invalid JSON mentioning agent-tiers@ must refuse"; fi
  grep -q 'not valid JSON' "$T/out" || fail "F2e: control: genuinely invalid JSON should still say so (got: $(head -c 300 "$T/out"))"
fi

# --- H1. the post-wire proof loop runs (and reports a failing hook selfcheck) unless the test knob is set
if only H1; then
  reset
  KS="$T/.claude/agent-tiers/scripts"; rm -f "$T/proof.log"; : > "$T/h1.ids"; : > "$T/h1.saved"
  first=""; n=0
  for id in $(awk -F'\t' '$1=="hook" && $3=="core"{print $2}' "$T/.claude/agent-tiers/install/options.tsv"); do
    [ -f "$KS/$id.selfcheck.sh" ] || continue
    cp -p "$KS/$id.selfcheck.sh" "$T/h1.save.$id"; echo "$id" >> "$T/h1.saved"
    if [ -z "$first" ]; then first="$id"; rc=1; else rc=0; echo "$id" >> "$T/h1.ids"; fi
    printf '#!/usr/bin/env sh\necho %s >> "%s/proof.log"\nexit %s\n' "$id" "$T" "$rc" > "$KS/$id.selfcheck.sh"
    n=$((n + 1))
  done
  [ "$n" -ge 2 ] || fail "H1: expected at least 2 core hook ids with a selfcheck, found $n"
  ( unset AGENT_TIERS_TEST_SKIP_HOOK_PROOF; try ) || { cat "$T/out"; fail "H1: installer must exit 0 even when a hook selfcheck fails (knob unset)"; }
  grep -q "$first selfcheck FAILED" "$T/out" || fail "H1: expected a '$first selfcheck FAILED' line (knob unset)"
  while read -r id; do
    grep -q "$id selfcheck OK" "$T/out" || fail "H1: expected a '$id selfcheck OK' line (knob unset)"
  done < "$T/h1.ids"
  while read -r id; do
    grep -qx "$id" "$T/proof.log" 2>/dev/null || fail "H1: expected stub for $id to have run (knob unset)"
  done < "$T/h1.saved"
  grep -q 'proof SKIPPED' "$T/out" && fail "H1: no 'proof SKIPPED' line expected with the knob unset"
  rm -f "$T/proof.log"; reset
  AGENT_TIERS_TEST_SKIP_HOOK_PROOF=1 try || { cat "$T/out"; fail "H1: installer must exit 0 with the knob set"; }
  grep -q 'proof SKIPPED' "$T/out" || fail "H1: expected a 'proof SKIPPED' line with the knob set"
  grep -q 'selfcheck OK\|selfcheck FAILED' "$T/out" && fail "H1: no selfcheck OK/FAILED line expected with the knob set"
  [ ! -e "$T/proof.log" ] || fail "H1: no hook selfcheck may run with the knob set (proof.log exists)"
  while read -r id; do cp -p "$T/h1.save.$id" "$KS/$id.selfcheck.sh"; done < "$T/h1.saved"
fi

cleanup
echo "OK install-flat: seam wires, scopes, rewires and reports - and never claims a row it did not write (nor one it was asked for and could not)"

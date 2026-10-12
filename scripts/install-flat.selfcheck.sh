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

T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
cleanup() { chmod -R u+rwX "$T" 2>/dev/null || true; rm -rf "$T"; }
fail() { printf 'FAIL: %s\n' "$1"; cleanup; exit 1; }

mkdir -p "$T/.claude"
cp -a "$ROOT" "$T/.claude/agent-tiers" || fail "could not copy kit"
rm -rf "$T/.claude/agent-tiers/.state"
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
# Unwire again immediately: every later install() call below re-runs EVERY wired row's own
# selfcheck (the proof step), and notify.selfcheck.sh alone spends real wall-clock seconds on
# delayed-click assertions - leaving these two wired would multiply that cost across every
# remaining case in this file for no additional coverage (the wiring behaviour is already proven
# above).
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
install
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

# --- 12. memory-content-lint HOOK_ROWS row (2026-09): consent-gated, wires under PostToolUse with the
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

cleanup
echo "OK install-flat: seam wires, scopes, rewires and reports - and never claims a row it did not write (nor one it was asked for and could not)"

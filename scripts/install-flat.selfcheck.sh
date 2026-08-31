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

# --- 2. consent wiring + ledger stamp --------------------------------------------------------------
install --with-codex-guard
[ "$(count PreToolUse "$CG")" = 1 ] || fail "--with-codex-guard should wire the row"
[ "$(jq -r '.["codex-guard"].event' "$L")" = PreToolUse ] || fail "ledger should record the event"

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

cleanup
echo "OK install-flat: seam wires, scopes, rewires and reports - and never claims a row it did not write (nor one it was asked for and could not)"

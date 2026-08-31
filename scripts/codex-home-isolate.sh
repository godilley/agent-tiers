#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers SessionStart hook: isolate CODEX_HOME per Claude session.
#
# Why: concurrent codex runs (across Claude sessions, INCLUDING the codex plugin's long-lived
# `app-server`) collide on the shared ~/.codex global state (state_*.sqlite / sessions / auth),
# and `resume --last` picks the wrong session. Giving each Claude session its own CODEX_HOME
# isolates that state and scopes resume, while preserving parallel work. Verified from source
# that both entrypoints honor an inherited CODEX_HOME (plugin resolveCodexHome = env.CODEX_HOME
# || ~/.codex; app-server spawns with env: process.env; broker `codex exec` inherits the Bash env)
# and that the plugin does NOT spawn the app-server at SessionStart (so CODEX_HOME is in the env
# by first codex use).
#
# Manual terminal codex is UNTOUCHED: this only acts inside a Claude Code SessionStart (needs
# $CLAUDE_ENV_FILE + a session id); a bare `codex` in your shell has neither -> uses ~/.codex.
# Wired ONCE globally; a no-op whenever anything is missing (fail-open, but now leaves a breadcrumb).
set -u

# Breadcrumb: fail-open is intentional (never block a session), but a silent fall-back to shared
# ~/.codex hid real misconfig (cross-lab finding 4). Log the reason to a small, bounded file.
LOG="$HOME/.codex-homes/isolate.log"
note() {
  # $1 = short reason. Best-effort; never fail the hook on a logging error.
  { mkdir -p "$HOME/.codex-homes" 2>/dev/null && printf '%s no-op: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
  # Keep it bounded (~200 lines) without a rotation dep. ponytail: naive tail-truncate, fine at this size.
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 200 ]; then
    tail -n 100 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null || true
  fi
}

# Nothing to isolate for a user who has never touched Codex: no ~/.codex and no codex CLI -> exit
# BEFORE any provisioning, deliberately without note() (which would itself create ~/.codex-homes -
# the exact $HOME noise a non-Codex consumer of this core-wired hook should never see).
[ -d "$HOME/.codex" ] || command -v codex >/dev/null 2>&1 || exit 0

# Must have the session env-file to export into; absent -> not a context we can affect -> no-op.
# (This hook only ever runs at a Claude SessionStart, so a MISSING env-file here is an anomaly worth noting.)
[ -n "${CLAUDE_ENV_FILE:-}" ] || { note "no CLAUDE_ENV_FILE (harness did not provide one) -> shared ~/.codex"; exit 0; }

INPUT="$(cat 2>/dev/null || true)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "${SID:-}" ] || SID="${CLAUDE_CODE_SESSION_ID:-}"
[ -n "${SID:-}" ] || { note "no session id -> cannot key a home -> shared ~/.codex"; exit 0; }

# Validate the id before it becomes a path (cross-lab finding 15). Claude session ids are UUIDs;
# accept only [A-Za-z0-9._-]. Anything else (path separators, ..) -> refuse rather than build a path.
case "$SID" in
  *[!A-Za-z0-9._-]* | '' | '.' | '..') note "session id failed safe-char check ('$SID') -> shared ~/.codex"; exit 0 ;;
esac

SRC="$HOME/.codex"
DEST="$HOME/.codex-homes/$SID"
mkdir -p "$DEST" 2>/dev/null || { note "mkdir '$DEST' failed -> shared ~/.codex"; exit 0; }
# Credentials live here (auth.json) -> 0700, not the default 0755 (cross-lab finding 14).
chmod 700 "$DEST" 2>/dev/null || true

# provision: SYMLINK both config.toml and auth.json to the live canonical ~/.codex files.
# auth: codex writes auth.json IN-PLACE (open-truncate, verified 2026-07-25 via --with-api-key: the
# symlink was followed, canonical inode unchanged), NOT rename-replace, so a symlink is NOT de-linked
# on refresh. That gives every session home ONE shared auth.json -> an OAuth refresh (single-use token
# rotation) writes back to the shared file, so homes never diverge into refresh_token_reused/401.
# Copy was WRONG here (concurrent refresh -> unrecoverable divergence); keyring was WRONG too (codex
# keys the keyring account by sha256(CODEX_HOME), so per-home homes get divergent entries, not shared).
# Ceilings: a `codex logout` INSIDE a session home clears the shared auth -> unsupported (re-asserted
# each start below, but a mid-session logout still bites); config.toml symlink is shared mutable state,
# a `codex config` write would hit shared config (finding 12, accepted: rare + user-driven); concurrent
# in-place refresh across homes is a narrow race but RECOVERABLE (one shared file), unlike copy.
link_canonical() {  # $1 = filename under ~/.codex; (re)point $DEST/$1 at the canonical file
  [ -e "$SRC/$1" ] || return 0
  [ -L "$DEST/$1" ] && [ "$(readlink "$DEST/$1" 2>/dev/null)" = "$SRC/$1" ] && return 0  # already correct
  rm -f "$DEST/$1" 2>/dev/null                          # drop a stale copy / broken or wrong link
  ln -s "$SRC/$1" "$DEST/$1" 2>/dev/null || note "symlink $1 failed in '$DEST'"
}
link_canonical config.toml
link_canonical auth.json

# export for the whole session: both broker `codex exec` and the plugin app-server inherit it.
printf "export CODEX_HOME='%s'\n" "$DEST" >> "$CLAUDE_ENV_FILE"

# GC: deliberately NOT shipped here. A prior `find -mtime +14 -exec rm -rf` was pulled 2026-07-25:
# dir mtime is a weak liveness signal (does not advance on internal sqlite writes) and there is no
# lease/lock, so a still-in-use or resumed-after-14d home could be reaped mid-session. Disk growth
# (~40MB/home) is a known, non-destructive ceiling (design doc section 6). A safe GC needs a
# lease/heartbeat + never-touch-$DEST guard before it can run at SessionStart. ponytail: no GC yet.

exit 0

#!/usr/bin/env sh
# kit-scope: shared
# self-check for codex-home-isolate.sh - no framework; asserts core behavior in a throwaway HOME.
set -u
SCRIPT="$(CDPATH= cd "$(dirname "$0")" && pwd)/codex-home-isolate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
perm() {  # `stat -c` is GNU-only, `-f` is BSD/macOS - a failed `-f` probe leaks noise to stdout too,
  # so try GNU first and only fall back on an empty result, never blend the two attempts' output.
  p="$(stat -c '%a' "$1" 2>/dev/null)"; [ -n "$p" ] && printf '%s\n' "$p" || stat -f '%Lp' "$1"
}

export HOME="$TMP/home"
mkdir -p "$HOME/.codex"
printf 'model="x"\n' > "$HOME/.codex/config.toml"
printf '{"access_token":"AAA"}\n' > "$HOME/.codex/auth.json"
SID="test-1111-2222"

# 1. happy path: provisions the session home + writes the export line
ENVF="$TMP/envfile"; : > "$ENVF"
printf '{"session_id":"%s","source":"startup"}\n' "$SID" | env -u CLAUDE_CODE_SESSION_ID CLAUDE_ENV_FILE="$ENVF" sh "$SCRIPT" || fail "happy path non-zero exit"
DEST="$HOME/.codex-homes/$SID"
[ -d "$DEST" ]                                      || fail "session home not created"
[ -L "$DEST/auth.json" ]                            || fail "auth.json not symlinked (item 2: shared canonical)"
[ "$(readlink "$DEST/auth.json")" = "$HOME/.codex/auth.json" ] || fail "auth.json symlink points to wrong target"
grep -q 'AAA' "$DEST/auth.json"                     || fail "auth.json (via symlink) content wrong"
[ -L "$DEST/config.toml" ]                          || fail "config.toml not symlinked"
[ "$(perm "$DEST")" = "700" ]                       || fail "session home not chmod 700 (finding 14)"
grep -q "export CODEX_HOME='$DEST'" "$ENVF"         || fail "CODEX_HOME export not written"

# 1b. auth writes IN-PLACE through the symlink -> canonical file updated, link survives (item 2 premise)
printf '{"access_token":"BBB"}\n' > "$DEST/auth.json"
[ -L "$DEST/auth.json" ]                            || fail "in-place write de-linked the symlink"
grep -q 'BBB' "$HOME/.codex/auth.json"              || fail "write did not reach the shared canonical file"

# 1c. migration: a stale COPY from an older provision is replaced by a symlink on re-run
rm -f "$DEST/auth.json"; printf '{"access_token":"OLDCOPY"}\n' > "$DEST/auth.json"  # a real file, not a link
printf '{"session_id":"%s"}\n' "$SID" | env -u CLAUDE_CODE_SESSION_ID CLAUDE_ENV_FILE="$ENVF" sh "$SCRIPT" || fail "re-run non-zero exit"
[ -L "$DEST/auth.json" ]                            || fail "stale copy not migrated to a symlink"

# 2. no CLAUDE_ENV_FILE -> no-op, clean exit (manual-terminal case)
OUT="$(printf '{"session_id":"%s"}\n' "$SID" | env -u CLAUDE_ENV_FILE -u CLAUDE_CODE_SESSION_ID sh "$SCRIPT"; echo "rc=$?")"
echo "$OUT" | grep -q 'rc=0' || fail "no-env-file case should exit 0"

# 3. no session id anywhere -> no-op (does not write an export)
ENVF3="$TMP/envfile3"; : > "$ENVF3"
printf '{}\n' | env -u CLAUDE_CODE_SESSION_ID CLAUDE_ENV_FILE="$ENVF3" sh "$SCRIPT" || fail "no-sid non-zero exit"
[ -s "$ENVF3" ] && fail "wrote an export with no session id"

# 4. unsafe session id (path traversal) -> refused, no export, no path built (finding 15)
ENVF4="$TMP/envfile4"; : > "$ENVF4"
printf '{"session_id":"../../etc/evil"}\n' | env -u CLAUDE_CODE_SESSION_ID CLAUDE_ENV_FILE="$ENVF4" sh "$SCRIPT" || fail "bad-sid non-zero exit"
[ -s "$ENVF4" ] && fail "wrote an export for an unsafe session id"

echo "ALL PASS"

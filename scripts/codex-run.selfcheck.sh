#!/usr/bin/env sh
# kit-scope: shared
# Self-check for codex-run.sh: stub the codex binary (CODEX_RUN_BIN=/bin/echo) and assert the scan
# hard-fails on planted secrets (exit 3), passes a clean tree, and passes probes through unscanned.
set -u
W="$(dirname "$0")/codex-run.sh"
fail() { printf 'FAIL: %s\n' "$1"; rm -rf "$T"; exit 1; }
T="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
mkdir -p "$T/clean" "$T/dirty"
# Build the planted key at runtime (concatenation) so THIS file never matches the scan pattern itself -
# otherwise the kit tree could never pass its own wrapper's scan.
K="AKIA"; K="${K}ABCDEFGHIJKLMNOP"
echo "aws_key=$K" > "$T/dirty/notes.txt"

out="$(CODEX_RUN_BIN=/bin/echo sh "$W" exec -s read-only -C "$T/clean" - 2>&1)"; rc=$?
[ "$rc" = 0 ] || fail "clean tree should pass (rc=$rc: $out)"
printf '%s' "$out" | grep -q "^exec -s read-only -C" || fail "argv should pass through to codex unchanged"

CODEX_RUN_BIN=/bin/echo sh "$W" exec -C "$T/dirty" - >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || fail "key-shaped content should exit 3 (got $rc)"

touch "$T/clean/.env"
CODEX_RUN_BIN=/bin/echo sh "$W" exec -C "$T/clean" - >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || fail "credential-class filename (.env) should exit 3 (got $rc)"

out="$(CODEX_RUN_BIN=/bin/echo sh "$W" login status 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "login status" ] || fail "allowlisted local subcommand should pass through unscanned"

CODEX_RUN_BIN=/bin/echo sh "$W" review --cd "$T/dirty" >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || fail "non-exec egress mode (review) must ALSO be scanned (got $rc)"

CODEX_RUN_BIN=/bin/echo sh "$W" exec --cd="$T/dirty" - >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || fail "--cd= form must be scanned (got $rc)"

# Attached short-option value: clap accepts -Cdir, so the scan must resolve it too. Missing this form
# meant the wrapper scanned cwd while codex read an entirely different (unscanned) tree.
CODEX_RUN_BIN=/bin/echo sh "$W" exec "-C$T/dirty" - >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || fail "attached -C<dir> form must be scanned (got $rc)"

# The scan must READ EVERYTHING. Both of these scanned clean before: rg's default binary detection
# skips any file containing a NUL, and a size cap skipped anything large - so a key in a DB dump or a
# binary blob egressed while the wrapper reported green.
mkdir -p "$T/binary"
printf 'HEADER\000\000junk aws=%s\n' "$K" > "$T/binary/blob.dat"
CODEX_RUN_BIN=/bin/echo sh "$W" exec -C "$T/binary" - >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || fail "a key inside a binary (NUL-bearing) file must be found (got $rc)"

mkdir -p "$T/large"
head -c 2000000 /dev/zero | tr '\0' 'x' > "$T/large/dump.sql"
printf '\naws=%s\n' "$K" >> "$T/large/dump.sql"
CODEX_RUN_BIN=/bin/echo sh "$W" exec -C "$T/large" - >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] || fail "a key in a >1MB file must be found - no silent size cap (got $rc)"

# Scanner error (not a hit) must ALSO exit 3: an unscannable tree never egresses. Its own tree, with no
# planted secret, so a pass here can only mean the scanner-error path fired. Skipped as root, where mode
# 000 does not deny traversal.
if [ "$(id -u)" != 0 ]; then
  # An unreadable FILE, deliberately not an unreadable directory: `find` still exits 0 on a file it
  # cannot read, so ONLY the content-scanner return code can catch this. A mode-000 directory would
  # make `find` fail too and the case would pass even with that return-code check deleted.
  mkdir -p "$T/errtree" && echo placeholder > "$T/errtree/locked.txt" && chmod 000 "$T/errtree/locked.txt"
  find "$T/errtree" -print >/dev/null 2>&1 || fail "fixture invalid: find should still exit 0 here"
  CODEX_RUN_BIN=/bin/echo sh "$W" exec -C "$T/errtree" - >/dev/null 2>&1; rc=$?
  chmod 644 "$T/errtree/locked.txt"
  [ "$rc" = 3 ] || fail "scanner error on an unreadable FILE must fail CLOSED with exit 3 (got $rc)"
  rm -rf "$T/errtree"

  # Symlink to key material outside the workspace: the tool follows it, so the scan must too.
  mkdir -p "$T/linked"; printf 'aws=%s\n' "$K" > "$T/outside-secret.txt"
  ln -s "$T/outside-secret.txt" "$T/linked/creds"
  CODEX_RUN_BIN=/bin/echo sh "$W" exec -C "$T/linked" - >/dev/null 2>&1; rc=$?
  [ "$rc" = 3 ] || fail "a symlink to key material outside the workspace must be scanned (got $rc)"
  rm -rf "$T/linked" "$T/outside-secret.txt"
fi

rm -f "$T/clean/.env"; touch "$T/clean/.env.example"
CODEX_RUN_BIN=/bin/echo sh "$W" exec -C "$T/clean" - >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] || fail ".env.example template should be exempt (got $rc)"

CODEX_RUN_BIN=/bin/echo sh "$W" exec -C "$T/nonexistent" - >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] || fail "missing workspace should exit 2 (got $rc)"

rm -rf "$T"
echo "OK codex-run: scan fail-closed on secrets, clean pass-through otherwise"

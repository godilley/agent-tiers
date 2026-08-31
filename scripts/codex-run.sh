#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers codex-run - the ONE sanctioned entrypoint for the codex CLI inside a Claude session.
#
# Why: XLAB-5 bans raw `codex` from a Claude session and the kit's own incident log (XLAB-14) records
# the prose-only ban being violated minutes after it was made ("luck, not design"). The codex-guard
# PreToolUse hook (consent row) denies bare invocations and points here. This wrapper adds the ONE
# mechanical control a raw call skips: a HARD-FAIL secrets scan (SC-5.3 step 3) of the directory codex
# will read, run before anything egresses. Everything else (run-pattern, background/sentinel
# choreography, session resume) stays with the caller - substitute `codex` -> `codex-run.sh` and the
# argv passes through unchanged (we `exec`, so PID/wait semantics hold for the caller's `& $!`).
#
# usage: codex-run.sh <codex argv...>        e.g. codex-run.sh exec -s read-only -C /tmp/x ...
# Scan policy is an ALLOWLIST (cross-lab finding 1): only known-LOCAL subcommands (login, logout,
# --version, help) pass unscanned; every other mode - exec, review, resume, fork, aliases, future
# unknowns - is presumed egress-capable and scanned first (fail-closed on the unknown).
# exit:  3 = SECRETS FAIL-CLOSED (hits on stderr; relocate/redact per SC-5.3a - deliberately NO
#        bypass flag) - also returned when the SCANNER ITSELF errors (an unscannable tree never
#        egresses). 2 = usage/target error. Otherwise codex's own exit code.
# Test seam: CODEX_RUN_BIN overrides the codex binary (selfcheck uses /bin/echo).
# Known limits (stated, per SC-5.3's honesty note): scans the workspace root only - resolved from all
# five -C/--cd forms (see below), else cwd - not git history, not paths fed via other file-bearing
# options, not inherited env, and bundled short flags (-abC dir) are not unpacked; symlink LOOPS make the
# scanner error out (exit 3, fail-closed) rather than being chased; the patterns are a
# tripwire for common key shapes, not a DLP product; template names (.env.example etc.) are exempted.
# Within the workspace the read is total: every file, any size, binary included (see the scan block).
set -u

BIN="${CODEX_RUN_BIN:-codex}"
[ $# -gt 0 ] || { echo "usage: codex-run.sh <codex argv...>" >&2; exit 2; }

# Known-local subcommands: no workspace read, no model egress -> pass through unscanned.
case "$1" in
  login|logout|--version|-V|--help|-h|help) exec "$BIN" "$@" ;;
esac

# The workspace codex will read: -C <dir> / --cd <dir>, else cwd. codex's parser is clap, which accepts
# a short option's value separated (-C dir), attached (-Cdir) or with = (-C=dir) - ALL THREE must be
# understood here or the scan reads one tree while codex reads another. Last occurrence wins, matching
# clap's own last-wins for a scalar arg. Order matters: -C=dir must be tested before -Cdir, which it
# also matches.
DIR="$(pwd)"; prev=""
for a in "$@"; do
  case "$prev" in -C|--cd) DIR="$a" ;; esac
  case "$a" in
    -C=*|--cd=*) DIR="${a#*=}" ;;
    -C?*)        DIR="${a#-C}" ;;
  esac
  prev="$a"
done
[ -d "$DIR" ] || { echo "codex-run: workspace '$DIR' does not exist" >&2; exit 2; }

# --- secrets scan (hard fail-closed, including on scanner error) -----------------------------------
# Content tripwires (key-material shapes) + filename tripwires (files that ARE key material).
# Both scanners read EVERYTHING: `--text`/`-a`, no size cap, and symlinks FOLLOWED (`--follow`/`-R`/`-L`).
# All three were bug fixes, and all three have the same shape - the scanner quietly declining to read
# somewhere the tool will happily read: rg's binary detection skipped any NUL-bearing file, `--max-filesize
# 1M` skipped anything larger, and none of the three followed a symlink, so `ln -s ~/.aws/credentials .`
# inside the workspace scanned CLEAN. A tripwire that reports green on the likeliest hiding places is worse
# than none. Cost: milliseconds on a normal source tree, but this is now an UNBOUNDED read - a workspace
# holding a multi-GB artifact pays for it on every wrapped call. Fail slow beats pass blind; if that ever
# bites, the fix is a real scanner (gitleaks) behind the same exit-3 contract, not a silent cap.
# ponytail: case-sensitive ERE, .git excluded (history is out of scope - see limits);
# upgrade path = a real scanner (gitleaks/trufflehog) behind the same exit-3 contract.
PAT='-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{30,}'
SCAN_ERR=0
if command -v rg >/dev/null 2>&1; then
  CONTENT_HITS="$(rg -l --text --follow --no-ignore --hidden --glob '!.git' -e "$PAT" "$DIR" 2>/dev/null)"
  rc=$?; [ "$rc" -gt 1 ] && SCAN_ERR=1          # rg: 0 hits, 1 none, 2+ error (2 IS reachable: an
                                                # unreadable file or dir - and on an unreadable FILE
                                                # `find` still exits 0, so this check is the only
                                                # thing that catches it. Not redundant with FILE_HITS.)
else
  # find -L + grep, not `grep -R`: BSD grep -R does not follow symlinks (needs -S, which GNU grep
  # lacks), so a `ln -s ~/.aws/credentials .` scanned CLEAN on macOS (CI, 2026-08-16). Same .git prune
  # as FILE_HITS below. The sh -c wrapper maps grep exit 0/1 (hits / none) to 0 and anything else
  # (unreadable file = 2) to non-zero, which `-exec ... {} +` propagates as find's own exit status
  # (POSIX) -> SCAN_ERR, preserving the fail-closed-on-unreadable contract the rg path has.
  CONTENT_HITS="$(find -L "$DIR" -name .git -prune -o -type f -exec sh -c 'grep -lEa -e "$0" "$@"; [ "$?" -le 1 ]' "$PAT" {} + 2>/dev/null)"
  rc=$?; [ "$rc" -gt 0 ] && SCAN_ERR=1
fi
FILE_HITS="$(find -L "$DIR" -name .git -prune -o \( \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name 'id_rsa*' -o -name 'id_ed25519*' -o -name 'credentials*.json' -o -name '.netrc' \) ! -name '.env.example' ! -name '.env.sample' ! -name '.env.template' ! -name '.env.dist' \) -print 2>/dev/null)" || SCAN_ERR=1

if [ "$SCAN_ERR" = 1 ]; then
  echo "codex-run: secrets scan could NOT complete (scanner error on '$DIR') - failing CLOSED per SC-5.3. Fix the tree/tooling and retry; an unscannable workspace never egresses." >&2
  exit 3
fi

if [ -n "$CONTENT_HITS" ] || [ -n "$FILE_HITS" ]; then
  {
    echo "codex-run: SECRETS SCAN FAILED - refusing to expose '$DIR' to codex (SC-5.3 fail-closed)."
    if [ -n "$CONTENT_HITS" ]; then echo "  key-shaped content in:"; printf '%s\n' "$CONTENT_HITS" | sed -e 's/^/    /' -e '20q'; fi
    if [ -n "$FILE_HITS" ]; then echo "  credential-class files:"; printf '%s\n' "$FILE_HITS" | sed -e 's/^/    /' -e '20q'; fi
    echo "  Resolution (SC-5.3a): RELOCATE the minimum artifact to a clean dir outside the repo and run"
    echo "  there - or remove/redact the hits. There is deliberately no bypass flag."
  } >&2
  exit 3
fi

exec "$BIN" "$@"

#!/usr/bin/env sh
# kit-scope: shared
# Self-check for codex-guard.sh: synthetic PreToolUse(Bash) payloads; assert the deny fires ONLY for
# command-position bare `codex` and the wrapper/mentions pass. Exits non-zero on first failure.
set -u
GUARD="$(dirname "$0")/codex-guard.sh"
# decision/breadcrumb lines go to a SANDBOX log, never the real kit's .state/guards.log (opus reviewer, Wave D:
# in-place selfchecks had filled the live record with fixture noise)
SBLOG="$(mktemp -d)/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG"
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails CLOSED by design without it)"; exit 0; }

run() { # $1 = the Bash command string; echo DENY or ALLOW
  p="$(jq -n --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}')"
  out="$(printf '%s' "$p" | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then echo DENY; else echo ALLOW; fi
}

[ "$(run 'codex exec -s read-only -C /tmp/x --json -o /tmp/o -')" = DENY  ] || fail "bare codex exec should DENY"
[ "$(run 'codex login status')" = DENY  ] || fail "bare codex login should DENY (probes route via the wrapper too)"
[ "$(run 'cd /tmp && codex exec -')" = DENY  ] || fail "codex after && should DENY"
[ "$(run 'true; codex --version')" = DENY  ] || fail "codex after ; should DENY"
[ "$(run 'rg -n "codex exec" agents/codex-read.md')" = ALLOW ] || fail "mention inside args should ALLOW"
[ "$(run 'echo codex')" = ALLOW ] || fail "codex as an argument should ALLOW"
[ "$(run 'sh "$HOME/.claude/agent-tiers/scripts/codex-home-isolate.sh"')" = ALLOW ] || fail "codex-* script paths should ALLOW"
[ "$(run '"$HOME/.claude/agent-tiers/scripts/codex-run.sh" exec -s read-only -C /tmp/x -')" = ALLOW ] || fail "the wrapper should ALLOW"
[ "$(run 'ls -la')" = ALLOW ] || fail "unrelated command should ALLOW"
[ "$(run 'command codex exec -')" = DENY ] || fail "'command codex' launcher should DENY"
[ "$(run 'exec codex exec -')" = DENY ] || fail "'exec codex' launcher should DENY"
[ "$(run 'nohup codex exec - &')" = DENY ] || fail "'nohup codex' launcher should DENY"
[ "$(run 'sudo codex exec -')" = DENY ] || fail "'sudo codex' launcher should DENY"
[ "$(run 'time codex exec -')" = DENY ] || fail "'time codex' launcher should DENY"
[ "$(run '{ codex exec -; }')" = DENY ] || fail "codex opening a brace group should DENY"
[ "$(run 'codex&')" = DENY ] || fail "codex terminated by & (no space) should DENY"
[ "$(run 'true && (codex --version)')" = DENY ] || fail "codex in a subshell should DENY"
# The launcher list must not turn into a substring match: these are different commands.
[ "$(run 'sudocodex exec')" = ALLOW ] || fail "sudocodex is not sudo+codex"
[ "$(run 'mytime codex-run.sh')" = ALLOW ] || fail "a codex-* path behind another word should ALLOW"

# heredoc body false positive (2026-09-02): a heredoc BODY line starting with "codex " looks like a
# fresh command at line-start to a plain `grep`, which anchors `^` per line, not per command - this
# must still ALLOW. (Updated 2026-10-12: the old comment here said "the line-filter only scans lines
# that carry `<<`" - that filter is gone, replaced by stripping heredoc BODIES, so the reasoning is now
# "the body is stripped before the scan ever sees it", same expected answer.)
[ "$(run 'cat > notes.md <<EOF
codex is banned in this kit, see XLAB-5
EOF')" = ALLOW ] || fail "codex mentioned in a heredoc body should ALLOW (body-strip fix)"

# heredoc-as-stdin false NEGATIVE (2026-09-02, opus reviewer HIGH): `codex exec` takes its prompt on
# stdin, so this is the single most natural way to invoke the exact thing this guard bans - the
# heredoc operator lives on the SAME line as the invocation, so the opener line (kept verbatim by the
# body-strip) must still catch it. A naive "stand down entirely on any heredoc" carve-out (the first
# cut of this fix) missed this.
[ "$(run 'codex exec - <<'"'"'EOF'"'"'
do the thing
EOF')" = DENY ] || fail "codex exec with a heredoc-supplied stdin prompt should DENY"

# codex-guard HIGH (found by execution, 2026-10-12): a codex call on a line AFTER a closed heredoc was
# invisible to the old "only << lines" filter and silently ALLOWED. Must DENY now that only the body is
# stripped.
[ "$(run 'cat > p.txt <<EOF
hi
EOF
codex exec - < p.txt')" = DENY ] || fail "codex after a closed heredoc should DENY"

# codex as the first line, BEFORE a heredoc opens later in the same command - also must DENY. The old
# filter kept only lines carrying `<<`, so it allowed this shape too (the codex line has none);
# pinned down alongside the "after" case above.
[ "$(run 'codex exec -
cat > p.txt <<EOF
hi
EOF')" = DENY ] || fail "codex before a later heredoc should DENY"

# unterminated heredoc containing a codex line in its (never-closed) body: the strip helper leaves the
# whole command AS-IS (same ceiling as guard_strip_heredocs in guard-cmdpos.sh), so this still DENIES -
# fail-CLOSED, not a silent ALLOW just because the body was never bounded.
[ "$(run 'cat > p.txt <<EOF
codex exec -' )" = DENY ] || fail "unterminated heredoc containing a codex line should DENY (fail-closed)"

# Malformed (non-JSON) payloads: fail CLOSED when codex is mentioned, open otherwise.
raw() { out="$(printf '%s' "$1" | sh "$GUARD" 2>/dev/null || true)"; if printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then echo DENY; else echo ALLOW; fi; }
[ "$(raw 'not json but mentions codex here')" = DENY  ] || fail "unparseable payload mentioning codex should DENY (fail-closed)"
[ "$(raw 'not json, nothing relevant')"       = ALLOW ] || fail "unparseable payload without codex should ALLOW"

# Wave D: a deny writes a decision line with the sid
jq -n '{tool_name:"Bash", session_id:"sess-cg", tool_input:{command:"codex exec hello"}}' | sh "$GUARD" >/dev/null 2>&1 || true
grep -aqE '^[^ ]+ codex-guard deny: .*\[sid=sess-cg\]$' "$SBLOG" || fail "no decision line in sandbox log"
echo "OK codex-guard: deny fires only for command-position bare codex; decision line logged with sid"

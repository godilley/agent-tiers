#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: XLAB-5 made mechanical - NO bare `codex` from a Claude session.
#
# The kit's own incident log (XLAB-14) records the prose ban being violated minutes after it was made
# ("luck, not design"), so this converts it to a deny at the call site. ANY command-position `codex`
# is denied - including login/version probes - with the fix in the reason: route through
# scripts/codex-run.sh (the sanctioned wrapper; probes pass through unscanned, `exec` hard-fails on a
# secrets hit). The wrapper's filename deliberately does not match bare `codex`, so wrapped calls pass
# this guard untouched; human terminal use is unaffected (hooks fire only in Claude's Bash tool).
#
# FAIL-CLOSED class (SC-5.3), unlike the kit's fail-open guards: if jq is missing the payload cannot
# be parsed precisely, so any Bash payload CONTAINING the word codex is denied (crude, stated in the
# reason) rather than allowed. Anti-accident, not anti-adversary: `env`/`xargs`/`sh -c` indirection is
# not chased - the audience is a Lead slipping into old habit, not a hostile agent. Wiring: options.tsv
# row, group delegation: the plugin route turns it on with that group in the plugin options; the flat
# route wires it with `install-flat.sh --with-codex-guard`. Selfcheck: codex-guard.selfcheck.sh.
set -u
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0
# CLAUDE_PLUGIN_ROOT is not reliably set for a hook's own shell (only baked into flat-installed
# commands/*.md); resolve the kit root from THIS script's own location instead, same as lint-doctrine.sh.
KIT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd)"

LOG="${AGENT_TIERS_GUARDS_LOG:-${KIT_ROOT:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
SID=""
# Decision line (Wave D, 2026-08-16): guards.log is THE durable human record of blocks (HOST-4 - under
# cc-gui / -p nobody sees a deny), so every deny/ask logs `<ts> <guard> deny|ask: <text> [sid=<id>]`;
# the SessionEnd summary and doctor count these lines by session id.
logdec() { # $1 = "deny: ..." | "ask: ..."   (sid parsed HERE, lazily; empty on the jq-less path)
  command -v jq >/dev/null 2>&1 && SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s codex-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
deny() { # $1 = reason. jq path emits the JSON decision; the jq-less path uses the rc-2 stderr protocol.
  logdec "deny: $(printf '%s' "$1" | cut -c1-140)"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
  printf '%s\n' "$1" >&2
  exit 2
}

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
FIX="Bare codex invocations are banned in Claude sessions (XLAB-5): a direct call skips the egress preflight and isolation discipline. Re-run via the sanctioned wrapper: replace 'codex' with '$KIT_ROOT/scripts/codex-run.sh' (same argv - probes pass through, exec gets a hard-fail secrets scan). One codex call per Bash command."

if ! command -v jq >/dev/null 2>&1; then
  case "$INPUT" in
    # NOTE: no wrapper advice here. Without jq the test is a substring match, so the wrapper's own path
    # (scripts/codex-run.sh) contains "codex" and is denied too - recommending it would be a loop.
    # Installing jq is the only remedy that restores command-position precision.
    *codex*) deny "jq is missing, so this guard cannot parse the command precisely - it is failing CLOSED on any Bash payload mentioning codex, INCLUDING the codex-run.sh wrapper. Install jq to restore precise command-position matching; until then no codex path can be reached from a Claude session. (Ban rationale, XLAB-5: a direct call skips the egress preflight and isolation discipline.)" ;;
  esac
  exit 0
fi

CMDSTR="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

# Heredoc present: strip heredoc BODY lines before scanning, keep everything else (opener lines, and
# any command before/after the heredoc on the whole multi-line string) verbatim. The earlier approach
# ("scan only lines containing `<<`") was WRONG: it dropped lines before the opener and after the
# terminator too, so a codex call on its OWN line after a closed heredoc (`cat > p.txt <<EOF` / body /
# `EOF` / `codex exec - < p.txt`) was invisible to the scan and silently ALLOWED (found by execution,
# 2026-10-12). Stripping only the BODY keeps the real false-positive fix this guard needs - a HEREDOC
# BODY line that happens to start with `codex ...` (writing a doc/script that mentions it as example
# text) must still ALLOW - while keeping every real command line, including one chained after the
# heredoc closes, in view. `codex exec - <<'EOF' ... EOF` (the operator on the SAME line as the
# invocation - `codex exec` takes its prompt on stdin, the single most natural way to invoke the exact
# thing this guard bans) still DENIES: the opener line is never stripped.
#
# Inline copy of guard_strip_heredocs() from guard-cmdpos.sh (not sourced - this guard is deliberately
# standalone/fail-CLOSED, see header). An UNTERMINATED heredoc is left entirely as-is (awk exits 1),
# same ceiling as the shared helper: a body with no known end cannot be safely bounded, so SCAN falls
# back to the full unmodified CMDSTR - still fail-CLOSED (a real codex line inside an unterminated body
# still DENIES), just coarser (may also deny on a body line that merely mentions codex as text). If the
# awk step fails for any other reason, same fallback applies.
SCAN="$CMDSTR"
case "$CMDSTR" in
  *'<<'*)
    STRIPPED="$(printf '%s\n' "$CMDSTR" | awk '
      BEGIN { tag = ""; dash = 0 }
      {
        line = $0
        if (tag == "") {
          print line
          if (match(line, /<<-?[ \t]*('"'"'[^'"'"']*'"'"'|"[^"]*"|[A-Za-z_][A-Za-z0-9_]*)/)) {
            seg = substr(line, RSTART, RLENGTH)
            dash = (seg ~ /^<<-/) ? 1 : 0
            rest = seg
            sub(/^<<-?[ \t]*/, "", rest)
            gsub(/^'"'"'|'"'"'$/, "", rest)
            gsub(/^"|"$/, "", rest)
            tag = rest
          }
        } else {
          cand = line
          if (dash) sub(/^\t+/, "", cand)
          if (cand == tag) { tag = ""; dash = 0 }
        }
      }
      END { if (tag != "") exit 1 }
    ' 2>/dev/null)"
    [ $? -eq 0 ] && SCAN="$STRIPPED"
    ;;
esac

if [ -z "$CMDSTR" ]; then
  # Unparseable/empty payload: this guard's class is fail-CLOSED, so mirror the jq-less path rather
  # than silently allowing (cross-lab finding 7).
  case "$INPUT" in
    *codex*) deny "The Bash payload could not be parsed but mentions codex - failing CLOSED. $FIX" ;;
  esac
  exit 0
fi
# Quote masking: a quoted string is data, not command structure, so `rg -n 'a|codex exec|b' f` must not
# read the `|` as a pipe into codex. One awk pass over the whole string (heredocs already stripped)
# rewrites SCAN: outside quotes a backslash before a metacharacter, quote, blank or backslash becomes
# `__`, before a newline a space, and before any other char just that char (`\codex` is codex); a `#`
# that starts a word (after a blank, newline, ; & | ( or ), not after { or $) begins a comment, copied
# raw to the end of its line; a comment holding a quote character falls back to the raw scan, because a
# `#` misread as a comment would swallow a real quote and leave the mask out of step with the shell
# (`[ ${#msg} -gt 0 ] && git commit -m 'a` / `b'` / `codex exec - # don't` once ALLOWED); inside '...' and $'...' every shell metacharacter (| ; & ( ) { } < > ` \ $) becomes `_` and
# newline a space; inside "..." the same, EXCEPT that $(...) (parentheses counted) and backtick spans stay
# raw because they execute. The quote characters themselves are deleted, so `"codex" exec -` and
# `'codex' exec -` become a command-position codex and DENY. A quote in a comment, an unterminated quote, an unbalanced `$(`,
# any awk failure, or a command over 20,000 characters (cap: the char walk is quadratic on some awks)
# leaves SCAN unmasked: fail CLOSED, same as the heredoc fallback above.
MASKED=""
[ "${#SCAN}" -le 20000 ] && MASKED="$(printf '%s\n' "$SCAN" | awk '
  function mk(c) { if (c == "\n") return " "; return (index("|;&(){}<>`\\$", c) ? "_" : c) }
  { s = s (NR > 1 ? "\n" : "") $0 }
  END {
    sp = 1; st[1] = "N"; dp[1] = 0; out = ""; n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1); nx = substr(s, i + 1, 1); cur = st[sp]
      if (cur == "S") { if (c == "\047") sp--; else out = out mk(c); continue }
      if (cur == "A") {
        if (c == "\\") { out = out "__"; i++ }
        else if (c == "\047") sp--
        else out = out mk(c)
        continue
      }
      if (cur == "D") {
        if (c == "\\") {
          if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`" || nx == "\n") { out = out "__"; i++ }
          else out = out "_"
        }
        else if (c == "\"") sp--
        else if (c == "$" && nx == "(") { out = out "$("; i++; sp++; st[sp] = "C"; dp[sp] = 0 }
        else if (c == "`") { out = out c; sp++; st[sp] = "B"; dp[sp] = 0 }
        else out = out mk(c)
        continue
      }
      # code contexts: N (top level), C ($(...) in a double quote), B (backtick span in a double quote)
      pv = (i > 1) ? substr(s, i - 1, 1) : "\n"
      if (c == "#" && index(" \t\n;&|()", pv)) {
        j = index(substr(s, i), "\n")
        cm = (j == 0) ? substr(s, i) : substr(s, i, j - 1)
        if (index(cm, "\047") || index(cm, "\"")) exit 1
        out = out cm; if (j == 0) i = n; else i += j - 2
        continue
      }
      if (c == "\\") {
        if (nx == "\n") out = out " "
        else if (nx == "" || index("|;&(){}<>`$\047\"\\ \t", nx)) out = out "__"
        else out = out nx
        i++
      }
      else if (c == "\047") { sp++; st[sp] = "S" }
      else if (c == "$" && nx == "\047") { i++; sp++; st[sp] = "A" }
      else if (c == "\"") { sp++; st[sp] = "D" }
      else if (cur == "C" && c == "(") { dp[sp]++; out = out c }
      else if (cur == "C" && c == ")") { out = out c; if (dp[sp] == 0) sp--; else dp[sp]-- }
      else if (cur == "B" && c == "`") { out = out c; sp-- }
      else out = out c
    }
    if (sp != 1) exit 1
    printf "%s\n", out
  }
' 2>/dev/null)" && [ -n "$MASKED" ] && SCAN="$MASKED"

# Command-position codex: line start or after ; & | ( { $( ` - optionally behind a bare launcher, then
# codex as a whole word (followed by space, end of line, or a terminator like ; & | )).
# The launcher list is every prefix that still leaves codex in command position AND is plain habit:
# command/exec/nohup/sudo/time. It stops there deliberately - env/xargs/sh -c REWRITE the command and
# chasing them is anti-adversary work this guard does not claim (see header).
# Mentions inside strings/args (rg codex, echo codex, paths like codex-home-isolate.sh, and the
# wrapper's own codex-run.sh) do not match, and neither does a metacharacter inside a quoted string
# (masked above). Ceiling: the mask is a lexical approximation, not a shell parser: it does not follow
# `${..}` nesting inside "$(...)" beyond paren counting, and it falls back to the raw scan only on the
# cases named above, not on every shape a real shell would read differently.
if printf '%s\n' "$SCAN" | grep -Eq '(^|[;&|({]|\$\(|`)[[:space:]]*((command|exec|nohup|sudo|time)[[:space:]]+)?codex([[:space:];&|)]|$)'; then
  deny "$FIX"
fi
exit 0

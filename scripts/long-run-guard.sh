#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: stop the repeated incident (named in two separate project
# docs) where an agent runs a long check/build in a shape that loses the exit code, then strands
# itself polling to recover it: piping pnpm check/pnpm build/a hooked git commit into
# tail/head/grep/etc discards the exit status; the harness auto-backgrounds any Bash call at the
# 120s default tool timeout with no exit code at all; and a while/until + sleep loop written to
# wait until it is done is the loop this guard exists to make unnecessary. The fix is mechanical
# (foreground, unpiped, a timeout ceiling above the command's own real runtime) so it is enforced
# here instead of relying on every brief remembering to say so.
#
# Scope: fires when a chained Bash segment runs pnpm check / pnpm check:* / pnpm build / pnpm
# build:* / pnpm typecheck / pnpm run check|build / pnpm -w|-r|-F|--filter check|build|typecheck
# (pnpm's own option-skipping, same idea as CMDPOS_GITOPTS) / git commit (any CMDPOS_GITOPTS-aware
# form - a hooked commit runs the full check) at command position, and denies when any of:
#   (a) that segment's output is piped into another command (`| tail`, `|& tee`, any consumer -
#       a redirect to a FILE, `2>&1`, `&>`, `>&2`, is fine: only a pipe loses the exit code; none
#       of these shapes end in a bare trailing `&` or contain a bare `|`, so no special-casing is
#       needed to tell them apart from (a)/(b) - see the ponytail note below)
#   (b) the tool call itself has run_in_background true, or the segment ends in a bare `&`
#       (shell backgrounding - the same lost-exit-code shape run_in_background covers)
#   (c) the tool call's timeout is absent or below 600000 (ms)
#   (d) the command is wrapped in a while/until loop that also mentions sleep
# and, for ANY Bash call (no long command needed):
#   (e) a while/until loop runs sleep and either (tier 1) the command names a harness-owned output
#       (tasks/*.output, subagents/*.jsonl, the session tasks dir), bounded or not: every stranded poll
#       loop observed watched these, a bounded one still strands the agent until its timeout, and the
#       harness already sends a completion notification; or (tier 2) the loop has no bound: no
#       `timeout` wrapper on the shell that runs it, no counter or deadline compared in its condition
#       (or in its body next to a break/exit/return), and not a `while read` loop (which ends at end
#       of input). Tier 2's deny text names the Monitor tool first, a bounded loop as the fallback.
# Everything else - other pnpm/git commands, the same commands foreground/unpiped/timed right, a
# `||`/`&&` alternative (the exit code is still read, just branched on), or any of these words
# appearing only inside a quoted string (a commit message's `->`/`|`/`<email>`) - is allowed.
#
# (c) is CONDITIONAL for a git commit segment: it only applies when the repo the commit targets
# actually has a pre-commit hook (core.hooksPath - resolved the way git itself does: `--type=path`
# so `~` expands, joined against the WORKTREE ROOT when relative, never the command's own cwd, since
# githooks(5) runs hooks from the worktree root regardless of where the commit was invoked from - or
# the default .git/hooks path, containing an executable pre-commit) - a two-second commit in a repo
# with no hook would otherwise be denied on every attempt for a runtime that was never at risk. The
# repo is resolved the same way every sibling commit-time guard does (guard_resolve_cwd off a
# preceding cd/-C, else the payload cwd); an unresolvable target is treated the same as "no hook"
# here (skip (c) for that segment) rather than denied, since the thing (c) protects against - a slow
# hooked check silently backgrounded - cannot be assessed without knowing the repo, and (a)/(b)/(d)
# already cover the shapes that don't need that knowledge. A pnpm segment in the SAME command still
# forces (c) unconditionally - the hook carve-out is git-commit-specific, pnpm check/build always
# runs the real work directly.
#
# The repo-resolution walk (guard_commit_seg/guard_resolve_cwd) reads SEGMENTS_RAW - split from the
# heredoc-stripped text WITHOUT quote-blanking - never the quote-blanked SEGMENTS used for the pipe/
# loop/long-command scans below. A quoted cd/-C target (`cd "/repo" && git commit`, `git -C "/repo"
# commit`) would otherwise arrive as `cd ""`/`-C ""` once quotes are blanked, which
# guard_norm_cd_target resolves to $HOME - a RESOLVED (not unresolved) wrong answer, so (c) got
# skipped against $HOME's own hook state instead of the real repo's (guards-review-2, 2026-09-23,
# ADDED finding). SEGMENTS_RAW is split with guard_split_segments_qsafe, not the quote-blind
# guard_split_segments, so a semicolon inside an unrelated quoted commit message earlier in the same
# chained command still cannot manufacture a false extra segment for this walk to trip over.
#
# Heredoc bodies are STRIPPED (guard_strip_heredocs), not a stand-down: this is a policy-boundary
# guard (it exists to stop a specific work-losing incident, the same class guard-cmdpos.sh's own
# header says guard_has_heredoc's stand-down is wrong for), and the harness's own default commit
# shape is `git commit -m "$(cat <<'EOF' ... EOF)"` - a bare `guard_has_heredoc` bail let every
# commit through unchecked. Quoted content is blanked (guard_strip_quotes) before any pipe/loop/
# long-command scan, so a commit message's own `|`/`->`/`<email>` text never trips this guard.
#
# ponytail: (a)/(d) are shell-string regex heuristics, same ceilings as every sibling guard built
# on guard-cmdpos.sh (see its header). (a)'s piping check runs on pipeline chunks (the command
# split only on &&/; - a pipe or a trailing background & intentionally stays attached to its chunk,
# since guard_split_segments's normal &&/;/pipe/& split would break that chunk apart and lose the
# very relationship this check exists to see) and only recognises the target command as the FIRST
# stage of a pipe (the shape that pipes the target's own output away); a target appearing as a
# LATER stage (input piped INTO it) is a different shape and not flagged. A `||` is neutralised
# before the `|`-stage count so `cmd || echo fail` is never counted as piping the exit code away.
# `2>&1`/`&>`/`>&N` need NO special handling under the &&/;-only chunk split and trailing-&-only
# background check: none of those shapes contain a bare `|` (so they cannot inflate the pipe-stage
# count) and none of them END a chunk in a bare `&` (the digit/`>`/target after the `&` is always
# the last character, not `&` itself), so they read through untouched either way. An earlier version
# of this file neutralised them to a placeholder before this split anyway; guards-review-2
# (2026-09-23, claim 11) traced every input against the current &&/;-only chunking and trailing-&-
# only background check and found none where that neutralisation changed the verdict - dead code,
# removed here rather than kept as a comforting no-op (a selfcheck case proving it dead, not just
# passing either way, sits alongside the removal).
# (d) is coarse by construction: it does not verify the loop actually wraps the target command,
# only that while/until and sleep both appear somewhere in the same tool call alongside a target
# command - a real parser would be needed to bind them precisely, and a false positive here just
# asks for the same foreground-with-timeout shape the guard wants anyway. The hook check for (c)
# only looks at the FIRST git commit segment (guard_commit_seg's own convention, shared by every
# commit-time guard in this kit) - a second chained commit targeting a different repo is not
# separately assessed. The pnpm option-skip does not know a wrapper like `npx pnpm check` or
# `corepack pnpm check` - that would mean widening CMDPOS_PREFIX's own wrapper list, a shared-
# library change with every OTHER guard in this kit as a blast radius, out of scope for a single
# guard's fix pass. `pnpm --filter X build` where X itself contains a space (`--filter "my pkg"
# build`) is not recognised - same "value atom cannot span a space" ceiling guard-cmdpos.sh already
# discloses for its own GITOPTS matching.
#
# (e) lives in this guard rather than a new hook: it is the same stranded-polling incident class,
# shares this guard's consent row and kill switch (shell_footguns group), and costs one process per
# Bash call instead of two. It reads the heredoc-stripped text (not quote-blanked), turns unquoted
# newlines into `;`, tokenises with guard_argv and walks the tokens with a loop-frame stack; an
# `sh -c` script is re-read the same way (3 levels max); under a `timeout` wrapper its loops still
# count for tier 1 but never as unbounded.
# ponytail: (e) ceilings in the ALLOW direction (a real unbounded loop passes) - a remote script handed
# over with no shell word (`ssh host '...'`, `kubectl exec pod -- '...'`) is not inspected; a loop
# inside `$( )`/backticks is not seen; a script file run by name is not seen; a heredoc body fed to a
# shell (`sh <<EOF`) is not seen; a busy loop with no sleep is allowed; a counter that is incremented
# but never compared to anything meaningful still reads as a bound; a `timeout` word anywhere before
# the shell word counts as the wrapper (`echo timeout 5 sh -c '...'` too); a path built only from
# variables (`$TMPDIR/claude-$UID/...`) is not recognised by tier 1.
# Ceilings in the DENY direction (a bounded or harmless loop is denied) - a body `break` counts only
# with a counter/deadline test in the same body; a spaced compound step (`$(( i += 1 ))`, `(( i -= 1 ))`)
# is not read as a step (`i=$((i+1))`, `(( i++ ))`, `(( --n ))` are); bash `;&`
# case fall-through is not read as a pattern start; a shell word anywhere in a simple command (`echo sh
# -c '...'` too) has its -c script read; a harness path named anywhere in the command (a comment, an
# unrelated argument) trips tier 1 for any sleep loop in it; a comment glued to a subshell's close
# (`(cmd)# ...`) is read as words (`)#` is not a comment start, so `$(date)#` stays one word), which can
# also hide a loop when the comment holds an apostrophe. `#` comments (a word-start `#`) and case
# patterns are skipped. Self-check: long-run-guard.selfcheck.sh.
set -u
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
logdec() {
  SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s long-run-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
command -v jq >/dev/null 2>&1 || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
[ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ] || exit 0
. "$SELFDIR/guard-cmdpos.sh" 2>/dev/null || exit 0
command -v guard_strip_heredocs >/dev/null 2>&1 && command -v guard_strip_quotes >/dev/null 2>&1 \
  && command -v guard_split_segments_qsafe >/dev/null 2>&1 || exit 0

# Strip heredoc bodies (keep the opener, drop the content - see header), then blank quoted content.
# The pipe/loop/long-command scans below read CMD_P (quote-blanked, so a commit message's own text
# cannot false-trip them); the repo-resolution walk further down reads SEGMENTS_RAW instead (real
# quoted values intact, so a quoted cd/-C target resolves to the real repo, not $HOME - see header).
CMD_HD="$(guard_strip_heredocs "$CMD")"
CMD_NQ="$(guard_strip_quotes "$CMD_HD")"
CMD_P="$CMD_NQ"

# --- (e) unbounded poll loop -------------------------------------------------------------------------
# lrg_nl: every UNQUOTED, unescaped newline -> ` ; ` (guard_argv reads an unquoted newline as a plain
# blank, so a multi-line loop would lose its separators). Quoted newlines and backslash pairs are kept.
# An unquoted `#` at word start (text start, or after a blank, newline or one of ;&|( ) starts a
# comment: its text up to the next newline is dropped. A mid-word `#` (`$#`, `a#b`, `${#x}`) is kept.
lrg_nl() {
  printf '%s' "$1" | awk '
    BEGIN { RS = "\032"; SQ = "\047"; DQ = "\042" }
    {
      s = $0; n = length(s); st = 0; out = ""
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (st == 1) { out = out c; if (c == SQ) st = 0; continue }
        if (c == "\\") { out = out c substr(s, i + 1, 1); i++; continue }
        if (st == 2) { out = out c; if (c == DQ) st = 0; continue }
        if (c == "#" && (i == 1 || index(" \t\n;&|(", substr(s, i - 1, 1)))) {
          while (i < n && substr(s, i + 1, 1) != "\n") i++
          continue
        }
        if (c == "\n") out = out " ; "
        else { out = out c; if (c == SQ) st = 1; else if (c == DQ) st = 2 }
      }
      printf "%s", out
    }'
}

# lrg_scan: guard_argv token lines in; out: `LOOP` per while/until loop with sleep, `DENY` per such loop
# with no bound, and `SUB<TAB>0|1<TAB>script` per `sh -c` script (1 = a timeout wraps that shell).
# Frame stack: kind L (while/until) or F (for/select), mode c (cond/head) or b (body); every token is
# appended to every open frame's own cond or body text.
lrg_scan() {
  awk '
    BEGIN { SEP = "\034"; cmdpos = 1; sp = 0; tmo = 0; tsk = 0; tval = 0; shm = 0; shc = 0; shv = 0; cdp = 0; cs = 0; pat = 0 }
    function addnames(tok,    s, e) {
      s = substr(tok, 2)
      while (match(s, /\$\{?[A-Za-z_][A-Za-z0-9_]*/)) {
        m = substr(s, RSTART, RLENGTH); sub(/^\$\{?/, "", m); cand[m] = 1
        s = substr(s, RSTART + RLENGTH)
      }
      s = substr(tok, 2)
      while (match(s, /\$\(\(/)) {
        s = substr(s, RSTART + RLENGTH); e = index(s, "))"); if (!e) e = length(s) + 1
        addids("w" substr(s, 1, e - 1)); s = substr(s, e)
      }
    }
    function addids(tok,    s) {
      s = substr(tok, 2)
      while (match(s, /[A-Za-z_][A-Za-z0-9_]*/)) {
        cand[substr(s, RSTART, RLENGTH)] = 1; s = substr(s, RSTART + RLENGTH)
      }
    }
    function isnumop(t) { return t == "w-lt" || t == "w-le" || t == "w-gt" || t == "w-ge" || t == "w-eq" || t == "w-ne" }
    # stepped(nm, all): nm is incremented or decremented somewhere in the frame text `all`, or
    # reassigned from `date +%s`. A pre-op `++nm`/`--nm` counts only at payload start or after `(`/`,`,
    # or after a blank inside `((`; outside an arithmetic `(( ))` span a token starting `--` is a long
    # option (`--count`), never a step; inside one (`(( --n > 0 ))`) it is a pre-decrement.
    function stepped(nm, all,    n, a, i, s, v, ar, pd) {
      n = split(all, a, SEP); ar = 0; pd = 0
      for (i = 1; i <= n; i++) {
        # ar: inside a `(( ))` span; pd counts its parens so an inner `(n)` does not end it early.
        if (!ar && a[i] == "g(" && i < n && a[i + 1] == "g(") { ar = 1; pd = 0 }
        if (ar) { if (a[i] == "g(") pd++; else if (a[i] == "g)" && --pd <= 0) ar = 0 }
        s = substr(a[i], 2)
        if (!ar && substr(s, 1, 2) == "--") continue
        if (match(s, "(^|[^A-Za-z0-9_])" nm "(\\+\\+|--|\\+=|-=)")) return 1
        if (match(s, "(^|[(,])(\\+\\+|--)" nm "([^A-Za-z0-9_]|$)")) return 1
        if (index(s, "((") && match(s, "[ \t](\\+\\+|--)" nm "([^A-Za-z0-9_]|$)")) return 1
        if (substr(s, 1, length(nm) + 1) == nm "=") {
          v = substr(s, length(nm) + 2)
          if (match(v, "(^|[^A-Za-z0-9_])" nm "([^A-Za-z0-9_]|$)") || index(v, "date +%s")) return 1
        }
      }
      return 0
    }
    function bound(T, all,    n, a, i, j, cmp, ar, txt, nm) {
      split("", cand); cmp = 0
      n = split(T, a, SEP)
      for (i = 1; i <= n; i++) {
        if (isnumop(a[i])) { cmp = 1; if (i > 1) addnames(a[i - 1]); if (i < n) addnames(a[i + 1]) }
        else if (a[i] == "g(" && i < n && a[i + 1] == "g(") {
          ar = 0
          for (j = i + 2; j <= n && !(a[j] == "g)" && j < n && a[j + 1] == "g)"); j++) {
            if (index(substr(a[j], 2), "<") || index(substr(a[j], 2), ">")) ar = 1
            addids(a[j])
          }
          if (ar) cmp = 1
          i = j
        }
      }
      txt = T; gsub(SEP, " ", txt)
      if (cmp && (index(txt, "date +%s") || index(txt, "$" "SECONDS") || index(txt, "$" "{SECONDS}") || index(txt, "EPOCHSECONDS") || ("SECONDS" in cand))) return 1
      for (nm in cand) if (stepped(nm, all)) return 1
      return 0
    }
    function evalf(k,    all) {
      all = ct[k] SEP bt[k]
      if (hs[k]) print "LOOP"
      if (hs[k] && !(rc[k] || bound(ct[k], all) || (bk[k] && bound(bt[k], all)))) print "DENY"
    }
    {
      tag = substr($0, 1, 1); w = substr($0, 2)
      if (tag == "u") next
      for (k = 1; k <= sp; k++) { if (mode[k] == "c") ct[k] = ct[k] SEP $0; else bt[k] = bt[k] SEP $0 }
      # case patterns (after `in` or `;;`, through the closing `)`) are never commands or keywords.
      if (pat) {
        if (tag == "g" && w == ")") { pat = 0; cmdpos = 1 }
        else if (tag == "w" && w == "esac") { pat = 0; cdp--; cmdpos = 0 }
        next
      }
      if (cs) { if (tag == "w" && w == "in") { cs = 0; pat = 1 }; next }
      if (tag == "g") { cmdpos = 1; tmo = 0; tsk = 0; tval = 0; shm = 0; shc = 0; shv = 0; if (w == ";;" && cdp) pat = 1; next }
      if (tag != "w" && tag != "o") next
      if (shm) {
        if (shc) { printf "SUB\t%d\t%s\n", tmo, w; shm = 0; shc = 0; next }
        if (shv) { shv = 0; next }
        if (w == "-o" || w == "+o") { shv = 1; next }
        if (w ~ /^--./ || w ~ /^\+./) next
        if (w ~ /^-[^-]/) { if (index(w, "c")) shc = 1; next }
        shm = 0
      }
      if (tsk) {
        if (tval) { tval = 0; next }
        if (w == "-k" || w == "-s" || w == "--signal" || w == "--kill-after") { tval = 1; next }
        if (w ~ /^-[ks]./ || w == "--foreground" || w == "--preserve-status" || w == "-v" || w ~ /^--signal=/ || w ~ /^--kill-after=/) next
        tsk = 0; next
      }
      # a `timeout` word or a shell word anywhere in a simple command (`sudo -u x sh -c`, `docker
      # compose exec db timeout 60 sh -c`, `su --shell=/bin/bash -c`); an assignment word
      # (`SHELL=/bin/bash`) is never a shell word.
      if (w == "timeout") { tmo = 1; tsk = 1; next }
      b = w; sub(/.*\//, "", b)
      if (w !~ /^[A-Za-z_][A-Za-z0-9_]*=/ && (b == "sh" || b == "bash" || b == "dash" || b == "zsh" || b == "ksh")) { shm = 1; shc = 0; shv = 0; cmdpos = 0; next }
      if (!cmdpos) next
      if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) next
      if (w == "if" || w == "then" || w == "else" || w == "elif" || w == "!") next
      if (w == "do") { if (sp) mode[sp] = "b"; next }
      if (w == "case") { cdp++; cs = 1; cmdpos = 0; next }
      if (w == "esac" && cdp) { cdp--; cmdpos = 0; next }
      if (w == "while" || w == "until" || w == "for" || w == "select") {
        sp++; kind[sp] = (w == "while" || w == "until") ? "L" : "F"; mode[sp] = "c"
        ct[sp] = ""; bt[sp] = ""; hs[sp] = 0; rc[sp] = 0; bk[sp] = 0
        if (kind[sp] == "F") cmdpos = 0
        next
      }
      cmdpos = 0
      if (w == "done") { if (sp) { if (kind[sp] == "L") evalf(sp); sp-- }; next }
      if (w == "nohup" || w == "env" || w == "command" || w == "time" || w == "exec" || w == "nice" || w == "sudo") { cmdpos = 1; next }
      if (b == "sleep") { for (k = 1; k <= sp; k++) if (kind[k] == "L") hs[k] = 1; next }
      if (sp && kind[sp] == "L") {
        if (w == "read" && mode[sp] == "c") { rc[sp] = 1; next }
        if ((w == "break" || w == "exit" || w == "return") && mode[sp] == "b") { bk[sp] = 1; next }
      }
    }
    END { while (sp) { if (kind[sp] == "L") evalf(sp); sp-- } }
  '
}

# lrg_poll <script> <depth> <wrapped>: prints `LOOP` when the script, or an `sh -c` script inside it
# (3 levels max, deeper is ignored), holds a while/until loop with sleep, and `DENY` when such a loop
# is unbounded and no timeout wraps it or any shell above it (wrapped=1). Subshell keeps vars local.
lrg_poll() (
  out="$(guard_argv "$(lrg_nl "$(guard_strip_heredocs "$1")")" | lrg_scan)"
  printf '%s\n' "$out" | grep -qx LOOP && echo LOOP
  [ "$3" = 1 ] || { printf '%s\n' "$out" | grep -qx DENY && echo DENY; }
  [ "$2" -lt 3 ] || exit 0
  printf '%s\n' "$out" | while IFS= read -r l; do
    case "$l" in SUB*)
      r="${l#SUB?}"; w="$3"; [ "${r%%[!0-9]*}" = 1 ] && w=1
      lrg_poll "$(printf '%s' "${r#??}" | tr '\036' '\n')" $(($2 + 1)) "$w" ;;
    esac
  done
)

HAS_POLL_LOOP=0
POLL_UNBOUNDED=0
HARNESS_PATH=0
if command -v guard_argv >/dev/null 2>&1 \
  && printf '%s' "$CMD_HD" | grep -aEq '(^|[^A-Za-z0-9_])(while|until)([^A-Za-z0-9_]|$)' \
  && printf '%s' "$CMD_HD" | grep -aEq '(^|[^A-Za-z0-9_])sleep([^A-Za-z0-9_]|$)'; then
  POLL_OUT="$(lrg_poll "$CMD_HD" 1 0)"
  case "$POLL_OUT" in *LOOP*) HAS_POLL_LOOP=1 ;; esac
  case "$POLL_OUT" in *DENY*) POLL_UNBOUNDED=1 ;; esac
  printf '%s' "$CMD_HD" | grep -aEq "/tasks/[^[:space:]'\"]*\.output|/subagents/[^[:space:]'\"]*\.jsonl|claude-[0-9]+/[^[:space:]'\"]+/tasks([^A-Za-z0-9_.-]|\$)" \
    && HARNESS_PATH=1
fi
POLL_HARNESS_REASON="deny: this loop polls a harness-owned output (a tasks/*.output or subagents/*.jsonl file, or the session tasks dir). The harness sends a completion notification for every subagent and run_in_background command, so end the turn and wait for it; do not poll, bounded or not."
POLL_REASON="deny: a while/until loop with sleep and no bound never ends when the awaited condition never comes true. To wait on an external condition (a port, a URL, a file another process writes), prefer the Monitor tool. Fallback, a bounded loop: wrap it in timeout (timeout 600 sh -c 'until [ -s f ]; do sleep 10; done'), or put a counter or deadline in the condition (i=0; until [ -s f ] || [ \$i -ge 60 ]; do sleep 10; i=\$((i+1)); done), or loop a fixed count (for i in \$(seq 60); do [ -s f ] && break; sleep 10; done). Then read the exit status."
POLL_DENY=""
if [ "$HAS_POLL_LOOP" = 1 ] && [ "$HARNESS_PATH" = 1 ]; then POLL_DENY="$POLL_HARNESS_REASON"
elif [ "$POLL_UNBOUNDED" = 1 ]; then POLL_DENY="$POLL_REASON"; fi
deny_out() {
  logdec "${1%%. *}"
  jq -n --arg r "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# Any pnpm flag may sit between `pnpm` and the verb: the named ones, plus a generic `-x` and a generic
# `--x [value]` (the value branch is optional so `--silent build` still reaches the verb). Before
# 2026-10-01 only the named flags were known, so `pnpm -s check | tail` slipped past this guard while
# simple-rules-guard's Rule E (since removed in favour of this one copy) still caught it.
PNPM_OPT="(run|-w|-r|--filter=[^[:space:]]+|--filter[[:space:]]+[^[:space:]]+|-F[[:space:]]+[^[:space:]]+|-F=?[^[:space:]]+|-[^[:space:]-][^[:space:]]*|--[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)"
PNPM_FRAG="pnpm[[:space:]]+(${PNPM_OPT}[[:space:]]+)*(check(:[A-Za-z0-9_:-]+)?|build(:[A-Za-z0-9_-]+)?|typecheck)([[:space:]]|\$)"
LONGCMD_FRAG="(${PNPM_FRAG}|${CMDPOS_COMMIT_FRAG})"

SEGMENTS="$(guard_split_segments "$CMD_P")"
FOUND_SEGS="$(guard_segs_at_cmdpos "$SEGMENTS" "$LONGCMD_FRAG")"
if [ -z "$FOUND_SEGS" ]; then
  [ -n "$POLL_DENY" ] && deny_out "$POLL_DENY"
  exit 0
fi

# Pipeline CHUNKS: split only on &&/; - a pipe or a trailing background & stays attached to its own
# chunk, which is exactly the relationship (a) and the background half of (b) need to see.
CHUNKS="$(printf '%s\n' "$CMD_P" | awk '{ gsub(/&&|;/, "\n"); print }')"
PIPED=0
BACKGROUND=0
HIT="$(printf '%s\n' "$CHUNKS" | while IFS= read -r chunk; do
  bare="$(printf '%s' "$chunk" | sed -E 's|^[[:space:]]*[({][[:space:]]*||')"
  protected="$(printf '%s' "$bare" | sed 's/||/@OR@/g')"
  first="$(printf '%s' "$protected" | awk -F'|' '{print $1}')"
  nstages="$(printf '%s' "$protected" | awk -F'|' '{print NF}')"
  printf '%s' "$first" | grep -aEq "${CMDPOS_PREFIX}${LONGCMD_FRAG}" || continue
  if [ "${nstages:-1}" -gt 1 ]; then echo PIPE; break; fi
  trimmed="$(printf '%s' "$bare" | sed -E 's/[[:space:]]+$//')"
  case "$trimmed" in (*'&') echo BG; break ;; esac
done)"
case "$HIT" in
  PIPE) PIPED=1 ;;
  BG) BACKGROUND=1 ;;
esac

LOOP_SLEEP=0
if printf '%s' "$CMD_P" | grep -aEq '(^|[^A-Za-z0-9_])(while|until)([^A-Za-z0-9_]|$)' \
  && printf '%s' "$CMD_P" | grep -aEq '(^|[^A-Za-z0-9_])sleep([^A-Za-z0-9_]|$)'; then
  LOOP_SLEEP=1
fi

RUNBG="$(printf '%s' "$INPUT" | jq -r 'if .tool_input.run_in_background == true then "1" else "0" end' 2>/dev/null || echo 0)"

TIMEOUT="$(printf '%s' "$INPUT" | jq -r '.tool_input.timeout // empty' 2>/dev/null || true)"
TIMEOUT_BAD=0
case "$TIMEOUT" in
  '' | *[!0-9]*) TIMEOUT_BAD=1 ;;
  *) [ "$TIMEOUT" -ge 600000 ] || TIMEOUT_BAD=1 ;;
esac

# Does (c) even apply to what was found? Unconditional the moment a pnpm target is present;
# conditional on an actual pre-commit hook when the only target found is a git commit.
PNPM_SEGS="$(guard_segs_at_cmdpos "$SEGMENTS" "$PNPM_FRAG")"
TIMEOUT_APPLIES=0
[ -n "$PNPM_SEGS" ] && TIMEOUT_APPLIES=1

if [ "$TIMEOUT_APPLIES" = 0 ]; then
  SEGMENTS_RAW="$(guard_split_segments_qsafe "$CMD_HD")"
  COMMIT_SEG="$(guard_commit_seg "$SEGMENTS_RAW")"
  if [ -n "$COMMIT_SEG" ] && command -v git >/dev/null 2>&1; then
    PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
    REPO="$PAYLOAD_CWD"
    [ -n "$PAYLOAD_CWD" ] && REPO="$(guard_resolve_cwd "$SEGMENTS_RAW" "$CMDPOS_COMMIT_FRAG" "$PAYLOAD_CWD")"
    if [ -n "$REPO" ] && ! guard_cwd_unresolved "$REPO"; then
      HOOKSPATH="$(git -C "$REPO" config --type=path --get core.hooksPath 2>/dev/null || true)"
      HOOKDIR=""
      if [ -n "$HOOKSPATH" ]; then
        case "$HOOKSPATH" in
          /*) HOOKDIR="$HOOKSPATH" ;;
          # githooks(5): a relative hooksPath is relative to the WORKTREE ROOT, never the cwd the
          # commit happened to run from - a commit invoked from a subdirectory must not join this
          # against that subdirectory (guards-review MEDIUM finding, 2026-09-23).
          *) TOPLEVEL="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || true)"
             [ -n "$TOPLEVEL" ] && HOOKDIR="$TOPLEVEL/$HOOKSPATH" ;;
        esac
      else
        GP="$(git -C "$REPO" rev-parse --git-path hooks 2>/dev/null || true)"
        if [ -n "$GP" ]; then
          case "$GP" in /*) HOOKDIR="$GP" ;; *) HOOKDIR="$REPO/$GP" ;; esac
        fi
      fi
      [ -n "$HOOKDIR" ] && [ -x "$HOOKDIR/pre-commit" ] && TIMEOUT_APPLIES=1
    fi
    # unresolved repo or no git: TIMEOUT_APPLIES stays 0 for this commit - (a)/(b)/(d) still cover it.
  fi
fi

REMEDY="run it foreground, no pipe, timeout: 900000 on the tool call, and read the exit code directly - never pipe (| or |&) into another command, never run_in_background or a trailing & background operator, never poll it in a while/until+sleep loop."

REASON=""
if [ "$RUNBG" = 1 ]; then
  REASON="deny: run_in_background on a long check/build/commit would return a shell id instead of an exit code. $REMEDY"
elif [ "$PIPED" = 1 ]; then
  REASON="deny: a pipe discards the exit code; run it foreground and read \$?. $REMEDY"
elif [ "$BACKGROUND" = 1 ]; then
  REASON="deny: a trailing & backgrounds a long check/build/commit the same way run_in_background does - no exit code is ever read. $REMEDY"
elif [ "$LOOP_SLEEP" = 1 ]; then
  REASON="deny: a while/until+sleep loop around a long check/build/commit is exactly the stranded-polling shape this guard exists to prevent. $REMEDY"
elif [ "$TIMEOUT_APPLIES" = 1 ] && [ "$TIMEOUT_BAD" = 1 ]; then
  REASON="deny: a long check/build/commit needs timeout >= 600000 on the tool call, or the harness auto-backgrounds it at 120000ms with no exit code. $REMEDY"
elif [ -n "$POLL_DENY" ]; then
  REASON="$POLL_DENY"
fi

[ -n "$REASON" ] || exit 0
deny_out "$REASON"

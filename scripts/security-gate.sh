#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Write|Edit|NotebookEdit|Bash) guard: M2 content-side scan. dangerous-actions-
# blocker.sh covers the COMMAND line and the file PATH; this covers the CONTENT being written -
# hardcoded secrets/provider key formats and the loudest injection-prone patterns (SQLi/command-
# injection/eval-of-untrusted-input/path-traversal-to-a-sensitive-target). Scans EVERY file type,
# deliberately NOT skipping .md/.txt (the ultimate-guide survey named `pre-commit-secrets.sh`
# skipping markdown/text as its stated blind spot - a real secret pasted into a doc sails through
# that shape; this hook does not repeat it).
#
# Scope: Write scans .tool_input.content in full; Edit scans .tool_input.new_string only (the
# content actually being introduced - old_string is what's leaving, not a risk to flag);
# NotebookEdit scans .tool_input.new_source (its own field name - NOT file_path/content, verified
# against the shipped binary's tool schema strings, not assumed by analogy to Write/Edit).
# Bash (T1.7, 2026-08-16) scans a command's LITERAL WRITE PAYLOAD. Write shapes: a `>`/`>>` redirect
# whose target is not /dev/* (redirect-scoped, so `> f 2>/dev/null` counts f), a `tee`, `sed -i`,
# `perl -i`, or `dd of=` at command position (guard_segs_at_cmdpos, guard-cmdpos.sh - not a second
# hand-rolled matcher), or a heredoc (`<<`/`<<-` + word; not `<<<`). A command with no write shape
# (`ls -la`, `grep AKIA .`, `make 2>&1 | tail`) is not scanned. Once ANY write shape is present the
# payload is the WHOLE command (the quote-blind splitter would otherwise drop a payload containing
# `;`/`|`/`&` onto a segment with no write shape). The secret-class checks run on every write shape; the
# code-shaped checks (SQL / exec-eval / traversal) run only for heredoc / sed / perl payloads, because a
# plain redirect far more often carries a query or command PASSED TO A CLIENT whose output is redirected.
# Fixture exemption: EVERY write target (redirect/tee/sed/perl, relative ones resolved against the
# payload cwd) must be fixture-shaped; a target that cannot be read from the text gives no exemption.
#
# Known bypass set (accurate, not aspirational; the Bash arm added the two largest entries 2026-08-16,
# T2.5): (1) TOOL-PATH - before the Bash arm, `sed -i`, `cat > f <<EOF`, `tee`, `perl -pi`, `python -
# <<PY` reached disk with this gate never invoked; MultiEdit is STILL not covered (below). (2)
# GENERATED CONTENT - a program's stdout redirected to disk (`python -c 'open("f","w").write(...)'`,
# `curl ... > f`, `base64 -d > f`, `cp`/`mv`/`install`/`dd if=` from elsewhere, `git apply`, `patch`)
# is not inspectable from the command line; the payload text is not in the command. Same class as the
# quoted-string residual T1.2 discloses. This ceiling is NOT theoretical: during the wave that built
# this arm (2026-08-16) runtime assembly (`SV="SEL"; SV="${SV}ECT"`, python patch files under a
# fixtures/ path) was the ROUTINE workaround for the guard false-firing on test literals - benign, and
# indistinguishable from assembling a real secret to get it past the scan. Read this guard as blocking
# ACCIDENTAL literal writes, not deliberate evasion (the kit's stated anti-accident-not-anti-adversary
# stance). (3) The Bash arm is QUOTE-BLIND, like every guard here: a `>`
# inside a string makes a segment write-shaped (over-fires: scans text that is not written), and a
# heredoc body containing the guarded shapes denies even when the heredoc is a comment or a test
# fixture written to a non-fixture path (T1.7 budget: if the false-positive rate is bad in practice,
# re-scope, do not tune). (4) Not seen as writes: `>|` (the splitter eats the `|`), `exec 3> f`, `cp
# /dev/stdin f`, `curl -o f`, `awk '{print > "f"}'` (inside a program string), and any tool not in the
# list above. (5) A `psql <<EOF ... EOF` / `mysql <<EOF` heredoc IS scanned by the SQL check (a heredoc
# is code-shaped to this arm) - disclosed over-fire, same budget as (3).
#
# ponytail: regex pattern-matching, not semantic analysis - same heuristic class as the other guards.
# Known bypass set (accurate, not aspirational, re-verified in review 2026-08-06, round 2): a secret
# split across two separate Edit calls, or built at runtime via string concatenation/base64/env-var
# interpolation in the SOURCE being written, is not reconstructed and passes; provider-key regexes
# are a curated LIST, not exhaustive - a key shape not yet added here (a new/uncommon provider) is
# not caught, only the common shapes currently listed; the SQLi/command-injection heuristics require
# the keyword and the concat/interpolation operator on the SAME LINE (a multi-line build - keyword on
# one line, `+` on the next - is not caught); the SQL check ALSO requires a clause keyword
# (FROM/INTO/SET/VALUES/WHERE) on that same line, both UPPERCASE (round 2 added the clause
# requirement after `npm config ... delete prefix --userconfig="${VAR}"`/`git update-ref` false-
# denied on the bare verb; round 3 found verb+clause TOGETHER still false-denied ordinary English
# sharing a line with an f-string, e.g. `f"cannot delete {n} rows from {table}"` - fixed by requiring
# uppercase, which also means a real query WRITTEN lowercase is no longer caught, a disclosed
# tradeoff); a parameterized-query call that merely LOOKS like concatenation in a comment is a
# residual known false-positive source (accepted); round 4 (2026-08-24) found the f-string alt
# (`f["']`) had no left boundary - ANY word ending in "f" directly before a quote matched (a PDO
# named placeholder `:f'` closing the PHP string, or `buf"`/`leaf'`), so a real parameterized query
# ending `WHERE full_name = :f'` false-denied. Fixed by requiring the `f` be preceded by
# start-of-line/space/`=`/`(`/`,`/`[`/`{`/`+` - the shape an f-string opener actually appears in
# (incl. `[f"..."]`/`{f"..."}` list/dict literals and `pre+f"..."`), not a bare identifier suffix -
# `:` deliberately stays out, that's the PDO-placeholder bug; MultiEdit is NOT covered (its
# tool_input field shape was not verified against the real schema during this build - a guess here
# would be worse than a stated gap; add it once confirmed). The provider-key/hardcoded-secret checks
# SKIP a path that looks like a test fixture (`*.selfcheck.sh`, a `test`/`fixture`/`fixtures` path
# SEGMENT - bound to `/`, not a bare substring: round-3 review found the first cut of this exemption
# used an unbound `*fixture*` glob that also exempted a repo checked out at `~/git/test-fixtures/`
# entirely, or any file merely named `fixture_loader.py` - `.example`/`.sample`) - without this, the
# guard denied writing its OWN test data once wired live (round-2 review HIGH:
# `security-gate.selfcheck.sh`'s intentionally-fake key-shaped test strings are exactly what the
# pattern is built to catch). This is a real, disclosed bypass, not a false reassurance: an
# adversarial write COULD name a file `secret.example` to smuggle a real key past this specific check
# - accepted per the kit's existing anti-accident-not-anti-adversary stance (same stance
# codex-guard.sh already states); the SQLi/injection/traversal checks below carry no such exemption.
# Fail-open on any tooling gap - EVERY fail-open path breadcrumbs to `.state/guards.log` (F-25).
# Self-check: security-gate.selfcheck.sh.
set -u

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s security-gate fail-open: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
  if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 5000 ]; then
    tail -n 2500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null || true
  fi
}

# T2.6 (2026-08-16): a reason is read by the MODEL as the acting party (under cc-gui / -p nobody else
# sees it, HOST-4) and must stay legible to a human at a prompt - so every hard deny carries the same
# what-to-do-now tail: the fix, the fixture escape hatch, and "tell the operator, do not route around".
# Two tails, because the fixture-path escape hatch is honoured ONLY by the secret-class checks (the SQL /
# exec-eval / traversal checks run regardless of path) - offering it on a check that ignores it sends the
# model into a guaranteed second deny (opus reviewer, Wave B).
DENY_TAIL_SECRET="What to do now: remove the flagged value from the content and retry - reference an env var or a secret store instead; a deliberate test fixture belongs under a tests/ or fixtures/ path or a *.example file. If the content is intended exactly as-is, stop and tell the operator what was blocked and why; do not rewrite the value or move it to another tool to slip past this check."
DENY_TAIL_CODE="What to do now: rewrite the flagged construct (parameterised query / argument list instead of a built string / a resolved path) and retry - there is no path-based exemption for this check. If the construct is intended exactly as-is, stop and tell the operator what was blocked and why; do not move it to another tool to slip past this check."
# Decision line (Wave D, 2026-08-16): guards.log is THE durable human record of blocks (HOST-4 - under
# cc-gui / -p nobody sees a deny), so every deny/ask logs `<ts> <guard> deny|ask: <text> [sid=<id>]`;
# the SessionEnd summary and doctor count these lines by session id.
logdec() { # $1 = "deny: ..." | "ask: ..."   (sid parsed HERE, lazily - one jq only when a decision is logged)
  SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s security-gate %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
deny() { # $1 = reason  $2 = secret|code (tail selector, default secret)
  case "${2:-secret}" in code) tail="$DENY_TAIL_CODE" ;; *) tail="$DENY_TAIL_SECRET" ;; esac
  logdec "deny: ${TOOL:-?} $(printf '%s' "$1" | cut -c1-140)"
  jq -n --arg r "$1 $tail" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

INPUT="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "jq missing - cannot parse payload"; exit 0; }
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ -n "$TOOL" ] || { note "no tool_name in payload"; exit 0; }

case "$TOOL" in
  Write)        FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
                TEXT="$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || true)" ;;
  Edit)         FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
                TEXT="$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || true)" ;;
  NotebookEdit) FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.notebook_path // empty' 2>/dev/null || true)"
                TEXT="$(printf '%s' "$INPUT" | jq -r '.tool_input.new_source // empty' 2>/dev/null || true)" ;;
  Bash)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    [ -n "$CMD" ] || exit 0
    # zero-fork pre-filter: most Bash calls carry no write shape at all (opus reviewer, Wave B: the full
    # arm is ~10 spawns on every Bash call otherwise).
    case "$CMD" in *'>'*|*'<<'*|*tee*|*sed*|*perl*|*'of='*) ;; *) exit 0 ;; esac
    # write-shape detection lives in the shared library (T1.7: "do not hand-roll a second matcher").
    [ -f "$BASE/scripts/guard-cmdpos.sh" ] || { note "guard-cmdpos.sh missing - Bash write scan skipped"; exit 0; }
    . "$BASE/scripts/guard-cmdpos.sh"
    command -v guard_segs_at_cmdpos >/dev/null 2>&1 && command -v guard_split_segments >/dev/null 2>&1 || { note "guard-cmdpos.sh sourced but guard_segs_at_cmdpos/guard_split_segments undefined (stale library?)"; exit 0; }
    SEGS="$(guard_split_segments "$CMD")"
    # (a) redirect TARGETS, one per line: every `>`/`>>` followed by a token that is not `&`/`>` (so
    #     `2>&1`/`>&2` are not writes), minus /dev/* - REDIRECT-scoped, not segment-scoped, so `> f
    #     2>/dev/null` still counts f (opus reviewer, Wave B).
    W_TARGETS="$(printf '%s\n' "$SEGS" | grep -aoE '>>?[[:space:]]*[^&>[:space:]][^[:space:];&|)]*' | sed -E 's/^>>?[[:space:]]*//' | grep -avE '^/dev/' || true)"
    # (b) tee / sed -i / perl -i / dd of= at command position (option tokens may precede -i: `sed -n -i`).
    SEDPERL_FRAG='(sed([[:space:]]+-[a-zA-Z]+)*[[:space:]]+(-[a-zA-Z]*i|--in-place)|perl([[:space:]]+-[a-zA-Z]+)*[[:space:]]+-[a-zA-Z]*i)'
    W_TEE="$(guard_segs_at_cmdpos "$SEGS" 'tee([[:space:]]|$)' || true)"
    W_SEDPERL="$(guard_segs_at_cmdpos "$SEGS" "$SEDPERL_FRAG" || true)"
    W_DD="$(guard_segs_at_cmdpos "$SEGS" 'dd[[:space:]]+.*of=' || true)"
    # (c) heredoc: a real heredoc shape (`<<`/`<<-`, optional quote, a word), not a `<<<` here-string or a
    #     `<<` inside a pattern/message.
    W_HERE=0; printf '%s' "$CMD" | grep -avE '<<<' | grep -aqE "<<-?[[:space:]]*['\"]?[A-Za-z_]" && W_HERE=1
    [ -n "$W_TARGETS" ] || [ -n "$W_TEE" ] || [ -n "$W_SEDPERL" ] || [ -n "$W_DD" ] || [ "$W_HERE" = 1 ] || exit 0
    # Once ANY write shape is present, the payload is the WHOLE command: the splitter is quote-blind, so a
    # `;`/`|`/`&` inside the payload would otherwise carry most of it onto a segment with no write shape
    # (opus reviewer, Wave B, MEDIUM: `echo 'password: "..."; x=1' > f` scanned nothing). More over-fire,
    # which this arm already accepts.
    TEXT="$CMD"
    # Bash-only: the SQL / exec-eval / traversal checks (code-shaped content) run only when the payload is
    # code-shaped - a heredoc body or a sed/perl replacement - not for a plain redirect, where the text is
    # far more often a QUERY OR COMMAND PASSED TO A CLIENT whose OUTPUT is redirected (`psql -c "SELECT ...
    # ${ID}" > out.csv`; opus reviewer, Wave B). A `psql <<EOF` heredoc still fires: disclosed over-fire.
    BASH_CODE_CHECKS=0; { [ "$W_HERE" = 1 ] || [ -n "$W_SEDPERL" ]; } && BASH_CODE_CHECKS=1
    # Fixture exemption: EVERY write target must be fixture-shaped (a fixture write in one segment must not
    # exempt a real write in another - opus reviewer, Wave B); relative targets are normalised against the
    # payload cwd so `> tests/keys.py` from a repo root is exempt like its absolute spelling. FP (for the
    # reason text) is the first target; no readable target -> a placeholder, and no exemption.
    PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
    ALL_TARGETS="$W_TARGETS"
    [ -n "$W_TEE" ] && ALL_TARGETS="$ALL_TARGETS
$(printf '%s\n' "$W_TEE" | sed -nE 's/.*(^|[[:space:]])tee[[:space:]]+(-a[[:space:]]+)?([^[:space:];&|)<]+).*/\3/p')"
    [ -n "$W_SEDPERL" ] && ALL_TARGETS="$ALL_TARGETS
$(printf '%s\n' "$W_SEDPERL" | sed -nE 's/.*[[:space:]]([^[:space:];&|)]+)[[:space:]]*$/\1/p')"
    ALL_TARGETS="$(printf '%s\n' "$ALL_TARGETS" | grep -av '^$' || true)"
    FP="$(printf '%s\n' "$ALL_TARGETS" | head -1)"
    [ -n "$FP" ] || FP="(Bash write, target not readable from the command text)"
    BASH_ALL_FIXTURE=0
    if [ -n "$ALL_TARGETS" ]; then
      BASH_ALL_FIXTURE=1
      oldIFS="$IFS"; IFS='
'
      set -f; set -- $ALL_TARGETS; set +f
      IFS="$oldIFS"
      for tgt in "$@"; do
        case "$tgt" in ~/*) tgt="$HOME/${tgt#\~/}" ;; esac
        case "$tgt" in /*) ;; *) tgt="${PAYLOAD_CWD:-.}/${tgt#./}" ;; esac
        case "$tgt" in
          *.selfcheck.sh|*.example|*.sample|*/test/*|*/tests/*|*/testdata/*|*/__tests__/*|*/fixture/*|*/fixtures/*) ;;
          *) BASH_ALL_FIXTURE=0 ;;
        esac
      done
    fi
    ;;
  *) exit 0 ;;
esac
[ -n "$TEXT" ] || exit 0

# test-fixture exemption for the key/secret checks ONLY (see bypass-set note above) - a bounded,
# disclosed trade-off, not a blanket path exemption.
FIXTURE_PATH=0
case "$FP" in
  # exact segments only: in a case glob `*` matches `/`, so `*/test*/*` would exempt an entire repo
  # checked out at ~/git/test-fixtures/ (cold-review F5, 2026-08-10 - the same hole round 3 fixed
  # for `fixture` had been left open here).
  *.selfcheck.sh|*.example|*.sample|*/test/*|*/tests/*|*/testdata/*|*/__tests__/*|*/fixture/*|*/fixtures/*) FIXTURE_PATH=1 ;;
esac
# Bash: the decision was taken over ALL write targets above, not the first one.
[ "$TOOL" = Bash ] && FIXTURE_PATH="${BASH_ALL_FIXTURE:-0}"

if [ "$FIXTURE_PATH" != 1 ]; then
  # provider key shapes (curated list, see bypass-set note above) + generic hardcoded-secret
  # assignment. PEM header checked separately - it's all leading punctuation, so a \b word-boundary
  # anchor never matches its start.
  # CORRECTION 2026-08-17: an earlier version of this comment called \b "unverified on Apple libc
  # regex". It is verified - the T1.1 probe recorded in dangerous-actions-blocker.sh's header ran on a
  # real Mac (macOS 26.5.2, BSD /usr/bin/grep) and Apple's grep honours \b; that guard's selfcheck now
  # asserts it on whatever host it runs on. The secret-shape ERE stays deliberately byte-identical in
  # both files (286 bytes, diff clean, re-verified 2026-08-17), so any portability rewrite must land in
  # both or consolidate.
  printf '%s' "$TEXT" | grep -aqE '\b(sk-ant-[A-Za-z0-9_-]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|sk_live_[A-Za-z0-9]{20,}|rk_live_[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|gh[oprsu]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{12,}|ASIA[A-Z0-9]{12,}|AIza[A-Za-z0-9_-]{30,}|xox[bps]-[A-Za-z0-9-]{10,})' && \
    deny "Content being written to $FP contains what looks like a live API key/token - hard deny."
  printf '%s' "$TEXT" | grep -aqE -- '-----BEGIN[[:space:]](RSA|EC|OPENSSH|DSA)?[[:space:]]*PRIVATE KEY-----' && \
    deny "Content being written to $FP contains a PEM private-key header - hard deny."
  # obvious placeholder values (round-3 review LOW: a real doc/template line like
  # `api_key = "your-api-key-here"` or `password: "changeme123"` was denied with no override) are
  # excluded from the ASSIGNMENT check specifically - the key-SHAPE checks above don't need this,
  # a real provider key format is specific enough not to collide with a placeholder word.
  SECRET_HIT="$(printf '%s' "$TEXT" | grep -aiE '\b(password|passwd|secret|api[_-]?key|access[_-]?token)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9+/=_-]{8,}["'"'"']' || true)"
  if [ -n "$SECRET_HIT" ] && ! printf '%s' "$SECRET_HIT" | grep -aiqE '(your[_-]?|my[_-]?|change[_-]?me|xxxx|placeholder|example|dummy|<[^>]*>)'; then
    deny "Content being written to $FP contains what looks like a hardcoded secret assignment - hard deny."
  fi
fi

# SQL injection: an SQL keyword, a CLAUSE keyword (FROM/INTO/SET/VALUES/WHERE), AND a string-concat/
# interpolation operator adjacent to a quote, all on the SAME LINE (per-line co-occurrence - NOT
# independent whole-content checks; the clause-keyword requirement was added in round 2 after the
# 2-keyword version false-denied non-SQL code, see bypass-set note above). UPPERCASE-only (round 3:
# even verb+clause together still false-denied ordinary English sharing a line with an f-string/`${`
# - `f"cannot delete {n} rows from {table}"`, `"select from the cache first"` - both supply lowercase
# verb+clause+operator for free. Requiring uppercase is the cheapest real narrowing; the disclosed
# cost is a lowercase-written real query (`"select * from users where id = " + x`, a real but less
# common style) is no longer caught - accepted, see bypass-set note above).
# Bash arm: code-shaped checks only for code-shaped payloads (heredoc / sed / perl) - see the arm above.
[ "$TOOL" = Bash ] && [ "${BASH_CODE_CHECKS:-1}" = 0 ] && exit 0
SQL_LINES="$(printf '%s' "$TEXT" | grep -aE '\b(SELECT|INSERT|UPDATE|DELETE)\b' | grep -aE '\b(FROM|INTO|SET|VALUES|WHERE)\b')"
if [ -n "$SQL_LINES" ]; then
  printf '%s' "$SQL_LINES" | grep -aqE '"[[:space:]]*\+|\+[[:space:]]*"|\$\{|(^|[[:space:]=(,[{+])f["'"'"']' && \
    deny "Content being written to $FP builds a SQL-shaped string by concatenation/interpolation - looks like a SQLi risk, hard deny (use a parameterized query)." code
fi

# command injection / eval: shelling out or eval'ing with unsanitized interpolation, same same-line
# co-occurrence discipline as the SQL check above.
printf '%s' "$TEXT" | grep -aqE '\b(exec|system|popen|subprocess\.(call|run|Popen)|child_process\.exec|eval)\((f["'"'"']|[^)]*(\+|\$\{|[[:space:]=(,[{+]f["'"'"']))' && \
  deny "Content being written to $FP shells out or eval's with string-built/interpolated input - looks like a command-injection/eval risk, hard deny." code

# path traversal reaching a sensitive-looking target - narrowed from a bare ../../../ literal (which
# false-positived on ordinary deep relative imports in a monorepo) to traversal actually aimed at
# something worth flagging.
printf '%s' "$TEXT" | grep -aqiE '(\.\./){2,}(etc/|\.ssh/|\.aws/|passwd|shadow|id_rsa)' && \
  deny "Content being written to $FP contains a path-traversal literal aimed at a sensitive target - hard deny." code

exit 0

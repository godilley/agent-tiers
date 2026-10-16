#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash|Write|Edit|NotebookEdit|MultiEdit) guard: M2 command+file deny list -
# a real HARD deny, distinct from the harness's own BUILT-IN destructive-command classifier (verified
# live in the shipped binary: it already flags git reset --hard/force-push/clean -f/branch -D/commit
# --amend, rm -rf, DROP/TRUNCATE/DELETE FROM, kubectl delete, terraform destroy with a "Note: ..."
# annotation on the permission prompt). That classifier only ANNOTATES a prompt the user can still
# approve (or that auto/bypass permission modes skip past); it never hard-denies. This hook covers
# the SAME ground where a hard stop is warranted (force-push to main/master, DROP/TRUNCATE DATABASE)
# plus what the built-in classifier does not touch at all: dd/mkfs/fork-bomb, --no-preserve-root,
# npm/pnpm/yarn publish, a secret shape on the command line itself, and protected-filename
# writes/edits. Don't re-litigate what the built-in already covers well (rm -rf, git reset --hard) -
# this hook is the gap-filler, not a parallel copy.
#
# Scope: Bash matcher checks .tool_input.command; Write/Edit/MultiEdit matcher checks
# .tool_input.file_path (MultiEdit shares this field name with Write/Edit, so the PATH check covers
# it even though the CONTENT check in security-gate.sh still declines MultiEdit - that guard would
# need to guess an unverified `edits[].new_string` shape, this one does not); NotebookEdit checks
# .tool_input.notebook_path (its own field name, verified against the shipped binary's tool schema
# strings, not assumed by analogy) - all symlink-resolved via `readlink -f`, so a symlink planted to
# dodge the literal-name check is still caught.
#
# Command-position matching (dd/mkfs/git-push/etc must be actually RUNNING, not just mentioned as an
# argument to rg/sed/cat/a commit message) is now the SHARED `guard-cmdpos.sh` library, not a
# hand-rolled PREFIX - round 3 review found this file's own copy and a sibling deploy guard's copy
# had already drifted in both directions after one round of independent patching (this file had
# sudo/env/time, the sibling didn't; the sibling gained compound-keyword/backtick forms proving a
# real incident, this file never did). See guard-cmdpos.sh's header for what "command position"
# covers and its own disclosed ceilings.
#
# ponytail: literal-substring + anchored-regex matching beyond the shared library, not a real shell
# parser. Known bypass set (accurate, not aspirational, re-verified in review 2026-08-06, round 3):
#   - Bash: quoting/variable-expansion/base64-wrapping any of the literal strings evades it
#     (`d''d if=...`, `$(echo ZGQ= | base64 -d)`); a heredoc body is not unwrapped; the secret-pattern
#     check scans the RAW command text only, not resolved env var values; provider-key regexes are a
#     curated LIST (see security-gate.sh's matching note), not exhaustive; the force-push check
#     resolves the CURRENT branch via `git rev-parse --abbrev-ref HEAD` only for the no-refspec shape
#     (`git push -f`/`git push --force [origin]`, plus a bare `HEAD`/`+HEAD` refspec, which is the same
#     shape wearing a ref) - the no-refspec form allows at most ONE token beside the force flag, so
#     `git push --force origin --verbose` is still ALLOWED on a main/master checkout (a real miss
#     shape, disclosed 2026-08-23, not chased). The branch is resolved in the
#     directory guard_resolve_cwd derives from the command itself (a preceding `cd`, a `git -C <repo>` inside the push segment) seeded by the
#     payload `.cwd` - an UNRESOLVABLE target (`cd $VAR`, a dir this same command creates) is DENIED,
#     not guessed past (W1-1, 2026-08-23; the same T1.10 posture the commit-time guards take). A
#     resolved directory that isn't a git repo, or a push whose remote name happens to look
#     branch-shaped, is a stated ceiling, not chased further; `--git-dir=`/`--work-tree=` on a push are
#     not resolved and are DENIED for that reason, the same posture the four commit-time guards take;
#     DROP/TRUNCATE requires a DB-client name at command position in the SAME segment
#     as the SQL words - a client invoked through a wrapper script that itself execs `psql` is not
#     followed.
#   - Write/Edit/NotebookEdit/MultiEdit: a protected file written by an indirect path Claude does not
#     construct itself (e.g. Bash `cp secret .env`) is NOT caught here - that's covered by the
#     Bash-side dangerous write pattern only if the destination literal appears in the command; a path
#     containing `..` segments that `readlink -f` cannot resolve (nonexistent parent dirs) falls back
#     to the raw literal-suffix check, which is weaker than full canonicalization.
# Fail-open on any tooling gap (no jq, unreadable input) - never block a session on infrastructure;
# breadcrumb every fail-open to `.state/guards.log` (F-25's own finding: new guards must not ship
# silent) - an empty extracted VALUE from a well-formed payload (no command / no path - genuinely
# nothing to check) is NOT a tooling gap and stays silent, matching every sibling guard's convention
# (grep-footgun-guard.sh, codex-guard.sh). Self-check: dangerous-actions-blocker.selfcheck.sh.
#
# `\b` on macOS - RESOLVED 2026-08-16 (T1.1). Probe `printf 'dd x\n' | /usr/bin/grep -cE 'dd\b'`
# ran on a REAL Mac (GitHub Actions macos-latest: macOS 26.5.2, arm64 VMAPPLE, Darwin 25.5.0,
# /usr/bin/grep BSD, run 31959192081) and printed 1: Apple's grep honours \b. The selfcheck now
# asserts this on whatever host it runs on (step 0), so it can never be open-and-invisible again.
# What that SAME run found instead - the real Darwin failure, and a worse one: this file did not
# PARSE under macOS /bin/sh (bash 3.2.57): bash < 4 scans a `$( ... )` body for its closing paren
# and treats an apostrophe inside a # comment there as an open quote ("what's", "payload's" in the
# SEG_HIT loop) -> "unexpected EOF while looking for matching `''", exit 2 on EVERY tool call. A
# PreToolUse exit 2 is a BLOCKING error, so on a Mac this guard fail-CLOSED the whole session
# rather than DENY-MISSING. Rule for this file and every guard: NO apostrophes in comments inside a
# command substitution. The macOS CI job (.github/workflows/selfcheck.yml) is what catches it now.
set -u
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"   # env override: selfchecks point it at a sandbox
note() {
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s dangerous-actions-blocker fail-open: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" >> "$LOG"; } 2>/dev/null || true
}

# T2.6 (2026-08-16): the reason is read by the MODEL as the acting party (under cc-gui / -p nobody else
# sees it, HOST-4) and must stay legible to a human at a prompt - one shared what-to-do-now tail.
DENY_TAIL="What to do now: there is no override for this in the session - do not retry a variant or route around it with another tool. Tell the operator what was blocked and why; if they still want it done, they run it themselves in a real terminal."
# Decision line (Wave D, 2026-08-16): guards.log is THE durable human record of blocks (HOST-4 - under
# cc-gui / -p nobody sees a deny), so every deny/ask logs `<ts> <guard> deny|ask: <text> [sid=<id>]`;
# the SessionEnd summary and doctor count these lines by session id.
logdec() { # $1 = "deny: ..." | "ask: ..."   (sid parsed HERE, lazily - one jq only when a decision is logged)
  SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s dangerous-actions-blocker %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
deny() { # $1 = reason
  logdec "deny: ${TOOL:-?} $(printf '%s' "$1" | cut -c1-140)"
  jq -n --arg r "$1 $DENY_TAIL" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# script-relative, readable-guarded BEFORE the `.` (the POSIX dot special builtin ABORTS dash/busybox on a missing file, and that abort exit code is the PreToolUse BLOCKING code - the fail-closed inversion this guard must never have).
LIB="$(dirname "$0")/guard-cmdpos.sh"
[ -r "$LIB" ] || { note "guard-cmdpos.sh missing/unreadable at $LIB"; exit 0; }
# shellcheck source=guard-cmdpos.sh
. "$LIB" 2>/dev/null || { note "guard-cmdpos.sh failed to source"; exit 0; }
command -v guard_at_command_position >/dev/null 2>&1 || { note "guard-cmdpos.sh sourced but guard_at_command_position undefined"; exit 0; }

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || { note "jq missing - cannot parse payload"; exit 0; }
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ -n "$TOOL" ] || { note "no tool_name in payload"; exit 0; }

# --- Bash: command-level deny list -----------------------------------------------------------
if [ "$TOOL" = "Bash" ]; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  [ -n "$CMD" ] || exit 0

  PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
  # PUSH_FRAG gives `git push` the same pre-verb option span CMDPOS_COMMIT_FRAG gives `git commit`, so
  # `git -C <repo> push -f` is both DETECTED here and RESOLVED by guard_resolve_cwd (which folds the
  # -C into the directory it reports). BARE_PUSH_SHAPE is the no-refspec form - a force flag plus at
  # most one positional token (the remote) - tested against the command-position-stripped segment,
  # which the leg trims of a group open/close before testing.
  PUSH_FRAG="git[[:space:]]+(${CMDPOS_GITOPTS})*push([[:space:]]|\$)"
  PUSH_TAIL='[[:space:]]*$'
  # A bare `HEAD` refspec IS the no-refspec shape wearing a ref - it force-pushes whatever branch is
  # checked out - so it takes the same branch resolution (2026-08-23; found while proving W1-1, and
  # named as a ceiling by the same review). `+HEAD` is the force-shorthand form of it. `HEAD:<dest>`
  # is deliberately NOT matched: it names its destination, so the main/master scan above already owns
  # it and treating it as current-branch would be a false deny of a feature-branch push.
  HEAD_REF='(^|[[:space:]+])HEAD([[:space:]]|$)'
  BARE_PUSH_SHAPE="^git[[:space:]]+(${CMDPOS_GITOPTS})*push[[:space:]]+(--force(-with-lease)?|-f)([[:space:]]+[A-Za-z0-9_.-]+)?${PUSH_TAIL}|^git[[:space:]]+(${CMDPOS_GITOPTS})*push[[:space:]]+[A-Za-z0-9_.-]+[[:space:]]+(--force(-with-lease)?|-f)${PUSH_TAIL}"
  # T1.10-style reason for an unresolvable push target: same shape as GUARD_UNRESOLVED_REPO_REASON
  # (which is commit-specific in its own wording), kept local - one consumer, no seam earned. The
  # CAUSE is a parameter because there are three of them, and a deny that names the wrong one is read
  # by the model as the acting party (T2.6): a group-scoped `cd /tmp` was reported as "not literal
  # text" when it is both literal and existent (opus reviewer 2026-08-23, LOW).
  push_reason() {
    echo "Force-push with no explicit ref targets whatever branch is checked out in the repo the command runs in, and this guard cannot work out WHICH repo that is: $1. Denied rather than guessed past - a force-push to main/master is irreversible, a re-spelled command costs one retry. Make it resolvable: spell the path literally, create the directory in a SEPARATE tool call first, re-spell --git-dir/--work-tree as a -C into the repo, or name the branch explicitly in the refspec so no branch resolution is needed."
  }
  # Config can only ADD protected names - main/master stay hardcoded below, never env-gated.
  # $1 = the directory already resolved for this push (may be "unresolved ..." or empty); used only
  # to read the remote's default branch, never to decide allow/deny (that stays guard_cwd_unresolved's
  # job, unchanged, further down). A name from the remote or from AGENT_TIERS_PROTECTED_BRANCHES is
  # rejected unless every char is in [A-Za-z0-9._/-] - a hostile value must not inject regex syntax
  # into the alternation this builds; a literal "." in a kept name is escaped so it still matches only
  # itself, not "any char" (over-wide would be a false-deny risk on an unrelated branch, not a
  # weakening, but there is no reason to accept it).
  protected_branch_re() {
    PB_DIR="$1"
    PB_NAMES="main|master"
    case "$PB_DIR" in
      ""|unresolved\ *) : ;;
      *)
        if command -v git >/dev/null 2>&1; then
          # Full ref form, not --short: --short can return an ambiguous "remotes/origin/x" on a
          # ref name that collides elsewhere in the refs namespace, and the origin/-prefix strip
          # below would then silently drop it (leaving PB_DEF_NAME unset instead of wrong - safe,
          # but the full form is unambiguous so there is no reason to accept that risk).
          PB_DEF_REF="$(cd "$PB_DIR" 2>/dev/null && git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
          PB_DEF_NAME="${PB_DEF_REF#refs/remotes/origin/}"
          # git itself allows ( ) + { | in a branch name - unescaped, any of those makes the
          # alternation an INVALID ERE, grep exits 2, the caller's `if` reads that as no-match, and
          # the deny is skipped for main/master too (a remote-controlled value weakening a hard deny).
          # Same charset gate as AGENT_TIERS_PROTECTED_BRANCHES below: reject rather than escape.
          case "$PB_DEF_NAME" in
            *[!A-Za-z0-9._/-]*) PB_DEF_NAME="" ;;
          esac
          if [ -n "$PB_DEF_NAME" ] && [ "$PB_DEF_NAME" != "$PB_DEF_REF" ]; then
            PB_NAMES="$PB_NAMES|$(printf '%s' "$PB_DEF_NAME" | sed 's/\./\\./g')"
          fi
        fi
        ;;
    esac
    # noglob around the loop: an unquoted `for x in $VAR` word-splits AND pathname-expands, so a
    # value like "release/*" would glob against the hook's OWN cwd and iterate real filenames
    # instead of the literal string (found in review). Restore the prior noglob state rather than
    # assuming it was off - `set +f` unconditionally would turn ON globbing for the rest of the
    # script if some caller had already set -f.
    case $- in *f*) PB_HADF=1 ;; *) PB_HADF=0 ;; esac
    set -f
    for PB_EXTRA in ${AGENT_TIERS_PROTECTED_BRANCHES:-}; do
      case "$PB_EXTRA" in
        "") continue ;;
        *[!A-Za-z0-9._/-]*) continue ;;
      esac
      PB_NAMES="$PB_NAMES|$(printf '%s' "$PB_EXTRA" | sed 's/\./\\./g')"
    done
    [ "$PB_HADF" = 1 ] || set +f
    printf '%s' "$PB_NAMES"
  }
  push_n=0

  # fork-bomb check runs against the WHOLE command, NOT per-segment: the bomb's own syntax legitimately
  # spans a `;` (`:(){ :|:& };:`), so splitting on `;` before matching breaks the very case this exists
  # to catch (caught by this script's own selfcheck before shipping - a segment-split version silently
  # ALLOWED the canonical fork bomb). Low FP risk regardless (a very specific, unusual syntax shape).
  printf '%s' "$CMD" | grep -aEq ':\(\)[[:space:]]*\{[[:space:]]*:\|:&?[[:space:]]*\}[[:space:]]*;?[[:space:]]*:' && \
    deny "Fork-bomb pattern detected - hard deny."

  # NOTE: the loop body is a FUNCTION whose output is CAPTURED into a variable, not piped to a
  # subshell that would call deny() itself - the `exit 0` in deny() inside a piped subshell would only
  # exit that subshell, not the script. deny() is called AFTER, in the real script context.
  # A function, not an inline multi-line `$( ... )` body, ON PURPOSE (macOS CI, 2026-08-16): bash 3.2
  # (macOS /bin/sh and /bin/bash) pre-scans a `$( ... )` body for its closing paren with a scanner
  # that mis-tokenises comments, case patterns and quotes inside it - three successive parse errors
  # were fixed one at a time before the shape itself was recognised as the bug. A function body is
  # parsed by the normal parser on every bash. The same rule applies to every guard: no multi-line
  # command-substitution bodies; put the body in a function and substitute the CALL.
  seg_scan() { while IFS= read -r seg; do
    guard_at_command_position "$seg" 'dd\b' && printf '%s' "$seg" | grep -aq 'of=/dev/' && \
      { echo "dd writing directly to a raw /dev/ device is a hard deny (can destroy a disk/partition irreversibly)."; break; }
    guard_at_command_position "$seg" 'mkfs([.]|[[:space:]])' && \
      { echo "mkfs (filesystem format) is a hard deny - destroys all data on the target."; break; }
    # --no-preserve-root only when "rm" is what is actually running IN THIS SEGMENT (round-3 review:
    # the prior version matched the literal string anywhere, denying "rg -- "--no-preserve-root"
    # docs/" - the same argument-position FP class already fixed on every other check here).
    guard_at_command_position "$seg" 'rm\b' && printf '%s' "$seg" | grep -aq -- '--no-preserve-root' && \
      { echo "--no-preserve-root defeats the safety check rm has - hard deny."; break; }
    # DROP/TRUNCATE only when the segment is actually RUNNING a DB client, not just mentioning the
    # words (a "grep -r "DROP TABLE"" search is read-only and must not trip this).
    guard_at_command_position "$seg" '(psql|mysql|mysqlsh|sqlite3|mongo|mongosh|redis-cli)\b' && \
      printf '%s' "$seg" | grep -aqiE '\b(DROP|TRUNCATE)[[:space:]]+(DATABASE|TABLE)\b' && \
      { echo "DROP/TRUNCATE DATABASE/TABLE is a hard deny - irreversible, no confirm-then-undo path."; break; }
    guard_at_command_position "$seg" '(npm|pnpm|yarn)[[:space:]]+publish\b' && \
      { echo "Package publish is a hard deny (irreversible, public) - confirm with the human first, then run it yourself in the terminal."; break; }
    # force-push to main/master: force flag and an EXPLICIT main/master ref token both required
    # WITHIN THIS SEGMENT ("+ref" refspec form included - a leading "+" is force-push shorthand with
    # no --force/-f flag at all). If the force flag is present but NO ref token names main/master
    # AND the segment has no OTHER positional ref argument either (a bare "git push -f"/"git push
    # --force [origin]", which force-pushes whatever branch is currently checked out), resolve the
    # current branch in the payload cwd and check THAT instead (round-3 review: the no-refspec form
    # was the single most common real shape and was completely unguarded).
    if guard_at_command_position "$seg" "$PUSH_FRAG"; then
      # every test below reads the segment with a group open/close (`(`/`{`, `)`/`}`) trimmed off both
      # ends: `(git push -f)` arrives as ONE segment (the splitter does not break on bare parens), and
      # an untrimmed trailing `)` defeats the `([[:space:]]|$)` tail every one of these patterns ends
      # with - the force FLAG itself stopped matching, so the whole leg went silent (2026-08-23).
      segb="$(printf '%s' "$seg" | sed -E 's#^[[:space:]]*[({][[:space:]]*##; s#[[:space:]]*[)}][[:space:]]*$##')"
      push_n=$((push_n + 1))
      # The force-flag and main/master scans read the ARGUMENT TAIL (everything after the verb), never
      # the whole segment: the pre-verb option span now legitimately carries PATHS, and a checkout
      # directory named `main`/`master` is a common layout, so a `-C` into one was a hard deny of a
      # perfectly safe feature-branch force-push, with no override (opus reviewer 2026-08-23, MEDIUM -
      # introduced by making detection GITOPTS-aware). BARE_PUSH_SHAPE still reads the whole stripped
      # segment: its job is to match the option span and the tail together.
      segtail="$(printf '%s' "$segb" | sed -E "s#${CMDPOS_PREFIX}git[[:space:]]+(${CMDPOS_GITOPTS})*push##")"
      # RCWD/PROTECTED_RE are resolved LAZILY (at most once per push segment, by either leg below) -
      # reset here so a PREVIOUS push segment's values are never reused for this one.
      RCWD=""
      PROTECTED_RE=""
      # ORIGINAL static main/master check, text UNCHANGED from before the remote-default/env-config
      # addition further down: this is the one path that must keep working even if every dynamic
      # mechanism below it has a bug, so it stays a plain literal grep, never built from a variable.
      if printf '%s' "$segtail" | grep -aqE '(--force(-with-lease)?\b|(^|[[:space:]])-f([[:space:]]|$)|(^|[[:space:]])\+(origin/)?(main|master)\b)'; then
        if printf '%s' "$segtail" | grep -aqE '(^|[[:space:]/:+])(main|master)([[:space:]:]|$)'; then
          echo "Force-push targeting main/master is a hard deny."; break
        elif { printf '%s' "$segb" | sed -E "s#${CMDPOS_PREFIX}##" | grep -aEq "$BARE_PUSH_SHAPE"; } \
             || printf '%s' "$segtail" | grep -aqE "$HEAD_REF"; then
          # W1-1 (2026-08-23): the shape test runs on the segment with the SHARED command-position
          # prefix stripped off (`#` delimiter - CMDPOS_PREFIX contains a literal `/`), not on its own
          # `^[[:space:]]*` anchor. That anchor admitted leading whitespace and nothing else, so every
          # wrapper the outer command-position match already sees through (sudo, nohup, /usr/bin/git,
          # a `(` subshell open) fell straight past this leg and the force-push was ALLOWED.
          # `--git-dir=`/`--work-tree=` select the repo without moving the shell, and nothing here
          # resolves them - so DENY rather than branch-check a directory already known to be the wrong
          # one (opus reviewer 2026-08-23, MEDIUM: detection became GITOPTS-aware, resolution did not).
          # Same posture and the same test the four commit-time guards take, reusing the verb
          # parameter this wave added.
          if guard_verb_optspan "$seg" push | grep -aqxE -- '--(git-dir|work-tree)(=.*)?'; then
            push_reason "a --git-dir/--work-tree flag names the repo, and this guard does not resolve those"; break
          fi
          # push_n = WHICH push segment this is. guard_resolve_cwd stops at the first stop_ere match by
          # default, which is the wrong segment for every push after the first (HIGH, same review).
          [ -n "$RCWD" ] || RCWD="$(guard_resolve_cwd "$SEGMENTS" "$PUSH_FRAG" "$PAYLOAD_CWD" push "$push_n")"
          if guard_cwd_unresolved "$RCWD"; then
            # An EMPTY payload cwd with no cd/-C in the command is a tooling gap (no directory to
            # start the walk from), not an unresolvable target - fail open with a breadcrumb, the same
            # posture every other infrastructure gap in this guard takes. A real unresolvable target
            # denies.
            if [ -z "${RCWD#unresolved }" ]; then
              note "no cwd in payload - cannot resolve the branch a no-refspec force-push targets"
            else
              push_reason "the \`cd\`/\`-C\` target \`${RCWD#unresolved }\` does not exist yet, is not literal text (this guard runs BEFORE the command, so a directory the command itself creates is not there to look at and a variable target is opaque), or was scoped to a subshell group that has since closed"; break
            fi
          elif command -v git >/dev/null 2>&1; then
            CUR_BRANCH="$(cd "$RCWD" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
            # Leading-paren pattern form "(main|master)": POSIX, and REQUIRED here - bash 3.2 (macOS
            # /bin/sh) scans this enclosing $( ... ) for its closing paren and reads a bare "master)"
            # as it (measured on macOS CI 2026-08-16: "syntax error near unexpected token "(").
            case "$CUR_BRANCH" in
              (main|master) echo "Force-push with no explicit ref targets the CURRENT branch ($CUR_BRANCH) - a hard deny."; break ;;
            esac
            # Dynamic protected names (remote default branch + AGENT_TIERS_PROTECTED_BRANCHES) cannot
            # share the leading-paren case above - a pattern built from a variable hits the same bash
            # 3.2 parse failure the comment above describes, just with the variable's value instead of
            # a literal - so loop over the names instead of a case alternation. A plain string compare,
            # not a grep, so there is no ERE-injection surface here even before protected_branch_re's
            # own charset filter.
            [ -n "$PROTECTED_RE" ] || PROTECTED_RE="$(protected_branch_re "$RCWD")"
            case $- in *f*) PB_HADF=1 ;; *) PB_HADF=0 ;; esac
            set -f
            for PB_NAME in $(printf '%s' "$PROTECTED_RE" | tr '|' ' '); do
              PB_NAME="$(printf '%s' "$PB_NAME" | sed 's/\\\./\./g')"
              if [ "$CUR_BRANCH" = "$PB_NAME" ]; then
                [ "$PB_HADF" = 1 ] || set +f
                echo "Force-push with no explicit ref targets the CURRENT branch ($CUR_BRANCH) - a hard deny."; break 2
              fi
            done
            [ "$PB_HADF" = 1 ] || set +f
          fi
        fi
      fi
      # SEPARATE dynamic-name check (remote default branch + AGENT_TIERS_PROTECTED_BRANCHES), run
      # AFTER the static main/master check above, never folded into it: a bug in this leg (or a
      # hostile config value) can then never disable the static deny, only miss ITS OWN extra names.
      # Gated on a GENERIC force-push shape (any force flag, or a leading "+" on any ref - not just
      # main/master) so a plain non-force push never pays for guard_resolve_cwd/protected_branch_re.
      if printf '%s' "$segtail" | grep -aqE '(--force(-with-lease)?\b|(^|[[:space:]])-f([[:space:]]|$)|(^|[[:space:]])\+[A-Za-z0-9_./-])'; then
        [ -n "$RCWD" ] || RCWD="$(guard_resolve_cwd "$SEGMENTS" "$PUSH_FRAG" "$PAYLOAD_CWD" push "$push_n")"
        [ -n "$PROTECTED_RE" ] || PROTECTED_RE="$(protected_branch_re "$RCWD")"
        PB_DYN_MATCH="$(printf '%s' "$segtail" | grep -aoE "(^|[[:space:]/:+])(${PROTECTED_RE})([[:space:]:]|\$)" 2>/dev/null)"
        PB_DYN_STATUS=$?
        if [ "$PB_DYN_STATUS" -gt 1 ]; then
          # A protected-branch name that still broke the pattern despite protected_branch_re's own
          # charset filter (defense in depth, not the expected path) - deny rather than let an
          # unreadable check silently pass as allow.
          echo "Force-push branch-name check failed (a protected-branch config value - the repo's remote default branch, or AGENT_TIERS_PROTECTED_BRANCHES=\"${AGENT_TIERS_PROTECTED_BRANCHES:-}\" - produced an invalid pattern) - denied rather than allowed past a broken check."; break
        fi
        if [ -n "$PB_DYN_MATCH" ]; then
          PB_DYN_MATCH="$(printf '%s' "$PB_DYN_MATCH" | head -1 | sed -E 's#^[[:space:]/:+]*##; s#[[:space:]:]*$##')"
          echo "Force-push targeting protected branch ($PB_DYN_MATCH) is a hard deny."; break
        fi
      fi
    fi
  done; }
  SEGMENTS="$(guard_split_segments "$CMD")"
  SEG_HIT="$(printf '%s\n' "$SEGMENTS" | seg_scan)"
  [ -n "$SEG_HIT" ] && deny "$SEG_HIT"

  # secret shape on the command line itself (not file content - that's security-gate.sh's job) -
  # scans the WHOLE command deliberately, no command-position restriction: a leaked key is dangerous
  # regardless of where in the command it sits (this is content, not a command name). Same curated
  # key-shape list as security-gate.sh, kept in sync deliberately (two independent, dependency-free
  # scripts by kit convention - not a shared-file abstraction for two consumers).
  printf '%s' "$CMD" | grep -aqE '\b(sk-ant-[A-Za-z0-9_-]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|sk_live_[A-Za-z0-9]{20,}|rk_live_[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|gh[oprsu]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{12,}|ASIA[A-Z0-9]{12,}|AIza[A-Za-z0-9_-]{30,}|xox[bps]-[A-Za-z0-9-]{10,})' && \
    deny "Command line contains what looks like a live API key/token - hard deny (don't paste secrets into a shell command; use an env var reference)."
  exit 0
fi

# --- Write/Edit/NotebookEdit/MultiEdit: protected-filename block ------------------------------
if [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ] || [ "$TOOL" = "NotebookEdit" ] || [ "$TOOL" = "MultiEdit" ]; then
  if [ "$TOOL" = "NotebookEdit" ]; then
    FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.notebook_path // empty' 2>/dev/null || true)"
  else
    FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
  fi
  [ -n "$FP" ] || exit 0

  # Symlink resolution trusts OUTPUT over exit code: macOS readlink -f PRINTS the
  # correctly resolved path and STILL exits 1 when the final target does not exist
  # (probed on macOS 26 public CI, 2026-08-31) - a plain `a || b` chain then ran the
  # python3 fallback as well, the substitution captured BOTH lines, and the basename
  # check matched nothing (fail-open). python3's os.path.realpath stays as the
  # fallback for a readlink with no usable output; the raw literal is last resort,
  # matching the already-disclosed weaker-check ceiling (2026-08-10 audit).
  RESOLVED="$(readlink -f -- "$FP" 2>/dev/null || true)"
  [ -n "$RESOLVED" ] || RESOLVED="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$FP" 2>/dev/null || true)"
  [ -n "$RESOLVED" ] || RESOLVED="$FP"
  BASE_NAME="$(printf '%s' "$RESOLVED" | sed 's#.*/##')"

  # same enumerated .env* suffix set as the global settings.json Read() deny list (not a `.env.*`
  # wildcard - that would also catch .env.example/.env.sample, common safe committed templates),
  # plus SC-5.1a's own named credential files (~/.aws/credentials, ~/.docker/config.json,
  # ~/.kube/config - basenames too generic for the exact-match case above, checked by path suffix).
  case "$BASE_NAME" in
    .env|.env.local|.env.development|.env.production|.env.staging|.env.test|id_rsa|id_ed25519|id_ecdsa|id_dsa|.npmrc|.pgpass|.netrc)
      deny "Write/Edit to a protected credential file ($BASE_NAME) is a hard deny." ;;
  esac
  case "$RESOLVED" in
    *.pem) deny "Write/Edit to a .pem (private key material) file is a hard deny." ;;
    */.aws/credentials) deny "Write/Edit to ~/.aws/credentials is a hard deny." ;;
    */.docker/config.json) deny "Write/Edit to ~/.docker/config.json (may carry registry credentials) is a hard deny." ;;
    */.kube/config) deny "Write/Edit to ~/.kube/config (cluster credentials) is a hard deny." ;;
  esac
  exit 0
fi

exit 0

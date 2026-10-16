#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers SHARED library: command-position matching for PreToolUse(Bash) guards. SOURCED, not
# executed directly - a guard does `. "$(dirname "$0")/guard-cmdpos.sh"` then calls its functions.
#
# Why this exists: dangerous-actions-blocker.sh and a project-specific deploy guard (kit-local, not
# bundled) each hand-rolled their own "is this command actually being RUN, not just mentioned as an
# argument" PREFIX regex - the textbook 2-live-consumers case for a shared seam. They drifted in BOTH
# directions within one review round (round 3, 2026-08-06): the deploy guard never got `sudo`;
# dangerous-actions-blocker never got the compound-keyword (`if`/`until`/`while`/...) or backtick
# forms the sibling earned fixing a real incident. This is the ONE definition now; the guards source
# it and none hand-rolls a copy again.
#
# What "command position" means: the segment START (after splitting on && || | ; &), the start of a
# `$( ... )` command substitution, the start of a backtick substitution, optionally preceded by a
# compound-command keyword (if/until/while/do/else/then/!) and/or a REPEATABLE run of simple wrapper
# tokens (sudo/command/env/time/nohup/bash/sh/`timeout N`) in any order/combination - round 3 found
# the prior single-optional-group shape only allowed ONE wrapper (`nohup bash x.sh` failed: nohup
# consumed the only slot, `bash` then didn't match what came next). The repeatable group fixes that
# class structurally instead of adding wrappers one at a time as new incidents surface.
#
# ponytail: still a regex heuristic, not a real shell parser - unquoted, no shell-metacharacter
# awareness beyond the segment split. Known ceilings (accurate, not aspirational): `env FOO=bar cmd`
# is not matched (the assignment token is not the same shape as a wrapper word - the segment's actual
# command is buried after an arbitrary-length env-assignment prefix, which needs real parsing to find
# reliably); a wrapper token used with its OWN flags before the wrapped command (`timeout --signal=9
# 30 cmd`) may not match depending on the flag shape; a custom function/alias standing in for a
# wrapper is invisible (this operates on the literal command text only). Wrappers that take the
# command as a QUOTED STRING argument (`bash -c "git commit"`, `sh -c`, `eval`, `xargs`, `ssh host
# '...'`, `su -c`) are a whole class this library cannot see into: the wrapped command lives inside a
# string literal, so seeing it means parsing that string as a nested command line - a real parser,
# not a regex. Disclosed 2026-08-16 (Tier 1 review, T1.2); no upgrade path short of a parser.
#
# Path prefix: `([^[:space:]=]*/)?` lets an absolute/relative PATH to the binary match too
# (`/usr/bin/git commit`, `../bin/rm -rf`), not only `./` - a Tier 1 review (2026-08-16) measured
# `/usr/bin/git commit` silent through every commit-time guard. The `=` exclusion keeps an
# env-assignment token (`X=/usr/bin/git commit` runs `commit`, not git) from being read as a path;
# `env FOO=bar cmd` stays a disclosed ceiling either way. This constant is SHARED - widening it also
# widens dangerous-actions-blocker (`/bin/rm --no-preserve-root` now matches; before, it did not).

CMDPOS_PREFIX='(^|\$\(|`)[[:space:]]*((if|until|while|do|else|then|!)[[:space:]]+)?((sudo|command|env|time|nohup|bash|sh|timeout[[:space:]]+[0-9]+[a-zA-Z]?)[[:space:]]+)*([^[:space:]=]*/)?'

# guard_has_heredoc <cmd> -> exit 0 if the raw command text contains ANY literal `<<` substring - a
# heredoc redirect (`<<`/`<<-`), but also a herestring (`<<<`), a merge-conflict marker (`<<<<<<<`), a
# left-shift operator inside a quoted code snippet, or `<<` appearing in ordinary text (a commit
# message reading "renders as <<foo>>"). Plain substring test, deliberately not narrower - correctly
# excluding `<<<` from a coarse "stand down" carve-out needs distinguishing it from `<<`, which this
# does not attempt (opus reviewer, 2026-09-02, MEDIUM: an earlier version of this comment claimed `<<<`
# was excluded - false, and exactly the "reassuring comment where the ceiling should be" failure this
# file already corrects itself for elsewhere). Every caller below stands its WHOLE command down on a
# true result, so any of the above shapes is now unscanned by that guard - accepted, each caller's own
# comment says so. Plain grep's `^` anchors on the START OF EVERY LINE, not the start of the command, so a
# HEREDOC BODY line that happens to start with a guarded verb (`codex ...`, `cd ...`, `git commit ...`)
# is mistaken for a real command at command position by every CMDPOS_PREFIX match in this file -
# distinct from the "wrapped in a quoted string" ceiling already disclosed above (that's single-line
# quoting; this is grep's per-line anchor over multi-line input). grep-footgun-guard.sh and
# pgrep-footgun-guard.sh each independently invented the same one-line carve-out ("stand down on ANY
# heredoc anywhere in the command" - coarse, not per-line masking) before this existed as a shared
# function; extracted here once a 3rd consumer needed it (hygiene-commit-guard.sh - 2026-09-02;
# codex-guard.sh never called this - it keeps its own inline heredoc handling, see its own header).
# NOT wired into guard_split_segments/guard_at_command_position themselves and
# NOT applied to every consumer of this library: dangerous-actions-blocker.sh, vcs-commit-guard.sh,
# kit-leak-guard.sh, review-gate-guard.sh and maint2-arrival-guard.sh all source this file too but do
# NOT call this - standing THEM down on any heredoc would flip a current false-POSITIVE nuisance
# (heredoc body text mistaken for a dangerous/scanned command) into a false-NEGATIVE gap (a real
# dangerous command, commit, or policy-relevant add chained AFTER a heredoc closes, in the same Bash
# call, would go unscanned) - unacceptable for the guards that are an actual security/leak/policy
# boundary. Callers that DO use this are anti-accident nudges or a style/habit check where erring
# toward fewer false positives is the safer trade; each caller's own comment names this ceiling.
guard_has_heredoc() {
  case "$1" in *'<<'*) return 0 ;; esac
  return 1
}

# guard_strip_heredocs <cmd> -> stdout: <cmd> with every heredoc BODY removed (the `<<TAG`/`<<-TAG`
# opener line is kept verbatim, including any command text before or after the marker on that same
# line; only the body lines through - and including - the terminator line are dropped). Exists so a
# caller can SEE the real command structure around a heredoc (a `git commit -m "$(cat <<'EOF' ...`
# shape is the default harness commit message form) instead of standing the whole guard down
# on guard_has_heredoc, which is the right trade for a style nudge but wrong for a POLICY-boundary
# guard (worktree-guard.sh, long-run-guard.sh, git-add-stash-guard.sh all adopted this on
# 2026-09-23 after a review found their heredoc bail let a hooked commit with no timeout, or a
# `git add -A` chained before a heredoc'd commit, through unseen). guard_has_heredoc's remaining callers
# (grep-footgun-guard.sh, pgrep-footgun-guard.sh, memory-write-gate.sh, simple-rules-guard.sh,
# sc52a-write-disclosure-guard.sh) are UNCHANGED; hygiene-commit-guard.sh moved to this helper on 2026-10-12. Stand-down is still the right trade for a style/habit nudge
# where a false deny costs more than an unscanned heredoc-adjacent command; this helper is offered
# for any of them to adopt later, not force-migrated here.
#
# Line-oriented, single heredoc opener recognised per source line (a bare TAG, or a TAG in matching
# single/double quotes, right after `<<`/`<<-`) - two heredocs later in the SAME multi-line command
# are both found in sequence (the scan resumes looking for a new opener once a body closes); two
# heredocs opened on the ONE line (`diff <(cat <<A) <(cat <<B)`) only recognises the first - ponytail
# ceiling, a real parser would be needed for that shape and it is not the incident this exists for.
# `<<-`'s own leading-tab stripping is honoured when matching the terminator line, same as the shell.
# An UNTERMINATED heredoc (no line ever equals the tag) is left ENTIRELY AS-IS - the whole original
# <cmd> is returned unchanged, not a partial strip - since a body with no known end cannot be safely
# bounded, and a caller silently mis-scanning past where the real command resumes is worse than the
# false-negative wide-open heredoc guard_has_heredoc callers already accept.
# Opener detection is QUOTE-AWARE (2026-10-14; before, any `<<` substring was an opener, so `echo "x
# <<EOF"` followed by a real command and a line `EOF` dropped that real command from every scan, and a
# herestring `cat <<< EOF` did the same): a `<<` inside single or double quotes is not an opener, a
# herestring `<<<` never is (nor at its 2nd/3rd character), and a `#` comment (a `#` at line start or
# after a blank or `;&|(`) ends the scan of that line. Quote state carries across lines; body lines of
# an active heredoc are not scanned. A `$(` seen at top level or inside double quotes opens a nested
# context whose quote state starts at 0; the `)` that closes it (paren depth counted at state 0 inside
# that context) restores the enclosing state - this is what keeps the default `git commit -m "$(cat
# <<'EOF'` shape recognised. Ceilings: a `<<` inside arithmetic `$(( ))` followed by a name-shaped word
# reads as an opener; backticks do not open a nested context; a `)` inside a `case` pattern within
# `$( )` closes the context early.
guard_strip_heredocs() {
  cmd="${1:-}"
  case "$cmd" in *'<<'*) : ;; *) printf '%s' "$cmd"; return 0 ;; esac
  out="$(printf '%s\n' "$cmd" | awk '
    BEGIN { tag = ""; dash = 0; q = 0; dep = 0; sp = 0; SQ = "\047"; DQ = "\042" }
    {
      line = $0
      if (tag != "") {
        cand = line
        if (dash) sub(/^\t+/, "", cand)
        if (cand == tag) { tag = ""; dash = 0 }
        next
      }
      print line
      n = length(line); i = 1; found = 0
      while (i <= n) {
        c = substr(line, i, 1)
        if (q == 1) { if (c == SQ) q = 0; i++; continue }
        if (c == "\\") { i += 2; continue }
        if (substr(line, i, 2) == "$(") { sp++; sq[sp] = q; sd[sp] = dep; q = 0; dep = 0; i += 2; continue }
        if (q == 2) { if (c == DQ) q = 0; i++; continue }
        if (c == SQ) { q = 1; i++; continue }
        if (c == DQ) { q = 2; i++; continue }
        if (c == "#" && (i == 1 || index(" \t;&|()", substr(line, i - 1, 1)) > 0)) break
        if (c == "(") { dep++; i++; continue }
        if (c == ")") {
          if (dep > 0) dep--
          else if (sp > 0) { q = sq[sp]; dep = sd[sp]; sp-- }
          i++; continue
        }
        if (substr(line, i, 3) == "<<<") { i += 3; while (substr(line, i, 1) == "<") i++; continue }
        if (!found && substr(line, i, 2) == "<<" && match(substr(line, i), /^<<-?[ \t]*('"'"'[^'"'"']*'"'"'|"[^"]*"|[A-Za-z_][A-Za-z0-9_]*)/)) {
          seg = substr(line, i, RLENGTH)
          dash = (seg ~ /^<<-/) ? 1 : 0
          rest = seg
          sub(/^<<-?[ \t]*/, "", rest)
          gsub(/^'"'"'|'"'"'$/, "", rest)
          gsub(/^"|"$/, "", rest)
          tag = rest; found = 1
          i += RLENGTH; continue
        }
        i++
      }
    }
    END { if (tag != "") exit 1 }
  ')"
  rc=$?
  if [ "$rc" -eq 0 ]; then printf '%s' "$out"; else printf '%s' "$cmd"; fi
}

# guard_strip_quotes <str> -> stdout: <str> with the CONTENT of every single- or double-quoted
# region replaced by nothing (`"a | b"` -> `""`, `'x -> y'` -> `''`) so a scan for a bare shell
# metacharacter (`|`, `>`, a bare `.`) elsewhere in a guard does not trip on quoted TEXT - a commit
# message, a `-m "rename a -> b"`, an email address in `--author="A <a@b.c>"`. The quote CHARACTERS
# themselves are kept (so `"..."`/`'...'` still reads as one quoted token, not vanish entirely) and
# nesting the other quote style inside is preserved as opaque content, matching real shell quoting
# (a `'` has no special meaning inside `"..."` and vice versa). No backslash-escape awareness inside
# double quotes (`"a \" b"` ends the quoted region at the escaped `"`, same ceiling every guard in
# this kit already accepts for quote handling elsewhere - a real parser would be needed to do
# better) - ponytail, disclosed rather than silently wrong. Callers that need the ACTUAL content of
# a quoted argument (git-add-stash-guard.sh's own path/subcommand tokens) do their own narrow
# per-token unquote instead of this blanket strip - this function is for guards that only need to
# know a metacharacter is NOT really there, never for guards that need the value that was there.
guard_strip_quotes() {
  printf '%s' "${1:-}" | awk '
    BEGIN { RS = "\032"; SQ = "\047"; DQ = "\042" }
    {
      s = $0; n = length(s); state = 0; out = ""
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (state == 0) {
          out = out c
          if (c == SQ) state = 1
          else if (c == DQ) state = 2
        } else if (state == 1) {
          if (c == SQ) { out = out c; state = 0 }
        } else {
          if (c == DQ) { out = out c; state = 0 }
        }
      }
      printf "%s", out
    }
  '
}

# CMDPOS_GITOPTS / CMDPOS_COMMIT_FRAG: the "this segment IS a git commit" fragment shared by all four
# commit-time guards (review-gate-guard.sh, kit-leak-guard.sh [kit-local, not bundled],
# vcs-commit-guard.sh, hygiene-commit-guard.sh). Every guard finds its commit segment through
# guard_commit_seg() below (CMDPOS_PREFIX + this fragment, after a leading `(`/`{` strip) and passes
# the same fragment bare as guard_resolve_cwd()'s stop_ere, so detection and resolution cannot drift.
# CORRECTION 2026-08-16 (Tier 1 review, T1.2): an earlier version of this comment said each guard's
# own `^[[:space:]]*${CMDPOS_COMMIT_FRAG}` grep and CMDPOS_PREFIX were "equivalent anchors". They were
# not - `^[[:space:]]*` admits leading whitespace and nothing else, so `sudo`/`nohup`/`then`/`(`/`{`/
# path-prefixed commits fired dangerous-actions-blocker (full prefix) and NONE of the four commit-time
# guards (measured: 6 wrapper shapes silent, review-gate-guard.sh, real PreToolUse payloads). The
# false equivalence was asserted here, in the single source of truth, which is what licensed the copy;
# it is corrected here so the next guard author is not entitled to copy the narrow anchor again.
#
# DETECTION (does this segment match at all) is a STRUCTURAL rule, not an enumerated list: any
# option-shaped token between `git` and `commit` is accepted, whether it's a bare boolean flag
# (`--no-pager`, `-p`, `--bare`) or an attached-value flag (`--git-dir=/x`) via the generic
# `-[^[:space:]]+` branch, or a SEPARATED-value flag (`-C <path>`, `-c <key>=<val>`) via the named
# branch, which must list those specifically since a bare `-[^[:space:]]+` would otherwise swallow
# only the flag and leave its value token unable to match anything (opus advisor, 2026-08-16: the
# first two rounds tonight hand-enumerated `-C`, then `-c`/`--no-pager`/`--no-optional-locks`
# one at a time and would keep needing a new alternative every time a new shape surfaced - this
# closes that treadmill structurally). The separated-value list (`-C`/`-c`/`--git-dir`/`--work-tree`/
# `--namespace`/`--super-prefix`/`--exec-path`/`--config-env`/`--attr-source`) is from git's own
# handle_options() and should be re-verified against `man git` if it ever needs a new entry - a
# missing one just fails to match (today's behaviour), never a false match.
#
# RESOLUTION (which repo does it target) stays narrower than detection, deliberately: only `-C` moves
# cwd (git's own "run as if started in <path>" flag) and guard_resolve_cwd folds it into the resolved
# cwd, same as it already folds a preceding `cd`. `--git-dir=`/`--work-tree=` are RECOGNISED (the guard
# fires) but NOT RESOLVED - unlike every other unlisted flag, this pair is DENIED outright by
# hygiene-commit-guard.sh and (conditionally) kit-leak-guard.sh via guard_unresolved_repo_flag() below,
# rather than left to scan a possibly-wrong repo (opus advisor, 2026-08-16: deny outright, don't
# leave gaps - see that function's header for the per-guard reasoning and the one real legitimate
# use case a bare-repo dotfiles layout would have for these flags over `-C`, absent in the environment where this was decided).
# `export GIT_DIR`/`GIT_WORK_TREE` derived from one oracle `git rev-parse` call could still make every
# downstream git call in a guard target the right repo instead of denying - not done: bigger, more edge
# cases (bare repos, relative paths, `--git-dir` without `--work-tree`) than an evening's worth for a
# shape that isn't typed by accident. (An earlier version of this comment claimed the reason was
# "reconstructing git commands from untrusted text is a NEW risk class" - wrong, corrected 2026-08-16:
# `cd /tmp/hostile-repo && git diff` already runs a downstream git call against arbitrary repo content
# and config today, via the plain `cd`/`-C` path every guard already resolves; the honest reason to
# prefer deny over resolve here is size and edge count, not a risk class this kit didn't already carry.)
# Every OTHER unlisted separated-value flag stays a silent, undenied bypass - narrower blast radius
# (they don't select which repo the content comes from) and no evidence any of them get typed either.
# A separated-value flag whose value contains whitespace (`git -C "/my repo" commit`, or equally
# `git -c "user.name=A B" commit`) still fails detection entirely for ANY flag in the named list - the
# value atom `[^[:space:]]+` cannot span a space (same "literal text only" ceiling this library already
# discloses elsewhere) - silent bypass, not a wrong-repo resolution. The env-var form (`GIT_DIR=x
# GIT_WORK_TREE=y git commit`) is COMPLETELY DARK - CMDPOS_PREFIX does not match an env-assignment
# prefix (see its own header), so COMMIT_SEG never matches and no guard fires at all, deny or otherwise.
# This is NOT a security boundary (a model that wanted to evade one of these guards has that door, and
# a plain `cd` to a hostile repo besides) - it exists to stop the FOUR guards from confidently reporting
# on/denying the wrong repo's content, the same "refuse to decide from data you know may be wrong"
# posture as everything else in this file.
CMDPOS_GITOPTS='((-C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--exec-path|--config-env|--attr-source)[[:space:]]+[^[:space:]]+|-[^[:space:]]+)[[:space:]]+'
CMDPOS_COMMIT_FRAG="git[[:space:]]+(${CMDPOS_GITOPTS})*commit([[:space:]]|\$)"

# guard_verb_optspan <segment> <verb> -> stdout, one token per line: the tokens from `git` through the
# FIRST literal <verb> word (inclusive), after stripping a leading subshell-open (`(`/`{`). Shared by
# guard_resolve_cwd's `-C` extraction below and guard_unresolved_repo_flag() - both need "just the
# pre-verb option tokens, nothing from the commit message or a --amend flag's own value" and must agree
# on where that boundary is, so it lives here once (extracted from guard_resolve_cwd, 2026-08-16 - two
# live consumers now, the doctrine trigger). See guard_resolve_cwd's header for why a plain token scan
# to the first literal verb word, not a regex-match capture, is what bounds this.
# The verb became a PARAMETER on 2026-08-23 (bundle-9 W1-1): dangerous-actions-blocker.sh needs the same
# pre-verb span for `push` to fold `git -C <repo> push -f`, which is the second live consumer the
# kit's own build-prove-propagate trigger asks for. guard_commit_optspan stays as the commit wrapper so
# the four commit-time guards are untouched.
guard_verb_optspan() {
  bare="$(printf '%s' "$1" | sed -E 's#^[[:space:]]*[({][[:space:]]*##')"
  printf '%s' "$bare" | tr '[:space:]' '\n' | grep -av '^[[:space:]]*$' | awk -v v="$2" '{print} $0==v{exit}'
}
guard_commit_optspan() { guard_verb_optspan "$1" commit; }

# guard_unresolved_repo_flag <segment> -> exit 0 if a REPO-SELECTING flag (`--git-dir`/`--work-tree`,
# separated OR `=`-attached form) is present in the pre-verb option span, exit 1 otherwise. Deliberately
# narrower than "any unresolved GITOPTS flag" - `-c`/`--namespace`/`--exec-path`/`--config-env`/
# `--attr-source` don't select WHICH repo's content the commit's checks would be reading, only
# `--git-dir`/`--work-tree` do (same class -C is in, which IS resolved). Callers decide what to do with
# a true result (hygiene-commit-guard.sh denies unconditionally; kit-leak-guard.sh denies unless the
# flag values provably rule out a kit checkout; vcs-commit-guard.sh/review-gate-guard.sh just decline
# to scan/mark and proceed, since neither can be dangerously WRONG the way a scan-and-deny can). NOTE
# (2026-08-23): "never denies" is now an ATTENDED, Lead-originated-session property for those two -
# under the unattended flag, OR when the caller is a subagent (2026-08-27), their ask is returned as a
# deny carrying the same remedy (guard_ask_decision below). The decline paths here are unchanged, and
# no hard deny is ever converted.
guard_unresolved_repo_flag() {
  guard_commit_optspan "$1" | grep -aqxE -- '--(git-dir|work-tree)(=.*)?'
}

# guard_repo_flag_values <segment> -> stdout, one value per line: the VALUES of any `--git-dir=`/
# `--work-tree=` tokens in the pre-verb option span (both `--git-dir=X` attached and `--git-dir X`
# separated forms). A separated form's flag as the LAST option token (`--git-dir` with nothing after
# it, e.g. immediately followed by the segment's terminal `commit` token) yields `commit` itself as a
# bogus "value" - callers deny on it anyway (a `$CWD/commit` candidate essentially never satisfies the
# kit-shape test, so this degrades to the scope gate's own answer, never a missed deny) but should not
# treat it as a real path. Only consumer today: kit-leak-guard.sh's conditional deny (is the flag value
# provably NOT a kit checkout?) - single-consumer, kept here anyway since it's the natural extension of
# guard_commit_optspan/guard_unresolved_repo_flag and any second caller would want the same parse.
guard_repo_flag_values() {
  guard_commit_optspan "$1" | awk '
    /^--(git-dir|work-tree)=/ { sub(/^--[a-z-]+=/, ""); print; f=0; next }
    f { print; f=0; next }
    /^--(git-dir|work-tree)$/ { f=1; next }
  '
}

# GUARD_UNRESOLVED_REPO_REASON: shared deny-reason text for BOTH unresolvable-target classes -
# guard_unresolved_repo_flag() hits and a guard_resolve_cwd() `unresolved` answer (T1.10, 2026-08-16:
# the second class reuses this path rather than growing a sibling; the text names both causes and
# both fixes) - so hygiene-commit-guard.sh and kit-leak-guard.sh cannot drift on the wording (opus
# advisor, 2026-08-16). Each caller prepends its own guard name and, for the cd/-C class, the target.
# The "every check it would run" clause is deliberately generic, not an enumerated list - hygiene's
# actual checks (staged diff, unstaged tracked changes, untracked files, commit message) and
# kit-leak's (leak-scan.sh over the index + add paths) differ, and a per-guard enumeration here would
# either drift out of sync with one of them or need per-guard variants, defeating the point of a
# shared constant (opus reviewer, 2026-08-16 caught the first draft naming hygiene's checks in
# kit-leak's deny text).
GUARD_UNRESOLVED_REPO_REASON="commit BLOCKED. This command selects the repository the commit lands in through something this guard recognises but cannot resolve at check time: a --git-dir/--work-tree flag, or a \`cd\`/\`-C\` whose target does not exist yet or is not literal text (the guard runs BEFORE the command, so \`mkdir X && cd X && git commit\` has no X to look at, and \`cd \"\$VAR\"\` is opaque). It therefore does not know which repo the commit targets - every check it would run may belong to a different repo than the one being committed to. Denied rather than guessing (a scan of the wrong repo can deny on a file this commit never touches). Make the target resolvable up front: for --git-dir/--work-tree, re-spell as \`git -C <repo> commit ...\` or \`cd <repo> && git commit ...\`; for a \`cd\`/\`-C\` into a directory this same command creates, create it in a SEPARATE tool call first, then commit; for a variable or command-substitution target, spell the path literally. If this repo genuinely has a detached git-dir and work tree (a bare-repo dotfiles checkout is the usual case), -C cannot express that and this commit needs a real terminal outside this agent session - tell the operator, do not route around it."

# --- unattended mode (2026-08-23) --------------------------------------------------------------
# A hook `ask` BLOCKS the tool call in every permission configuration, including bypassPermissions
# (HOST-4, measured 2026-08-16), and reaches a human only where the host has a prompt channel. So an
# unattended preplanned run halts at the first `ask` and stays halted until someone comes back.
#
# The flag: an empty file at `.state/unattended.<session-id>`, written by the /unattended command.
# Per SESSION, never per repo (concurrent Leads on one repo must not inherit each other's posture),
# and a /clear mints a new id, so a cleared chat correctly starts attended. Same charset guard as
# every other session-id-as-path-component in the kit (F-12): an id that is not [A-Za-z0-9._-] is
# treated as absent, never as a traversal.
#
# What it does NOT do: a hard DENY is never converted, in either direction. The security posture of
# this kit is identical attended or not - the only thing that changes is that a question nobody can
# answer becomes a machine-readable refusal WITH its remedy, which the model can act on, instead of a
# halt. The gate is still enforced: review-gate's remedy (spawn a reviewer, retry the commit) is
# exactly as actionable in deny form.
#
# Fail direction: a MISSING or misspelled flag means the guards keep asking - the run halts, which is
# the status quo, never a silent conversion in the wrong session.
#
# Probed live 2026-08-23: a SUB-AGENT's PreToolUse payload carries the parent session id - a Worker's
# blocked `grep` logged the parent sid. So the flag DOES reach the spawns that do an unattended run's
# actual work. Same premise guard-summary.sh relies on for its own counting.
GUARD_UNATTENDED_PREFIX="UNATTENDED MODE: this session is flagged unattended (.state/unattended.<session-id>), so a question no human is present to answer is returned as a deny you can act on instead of a halt. The requirement itself is unchanged - do what the remedy below says and retry. "

# DELEGATED-AGENT case (2026-08-27): the same "nobody can answer this ask" problem as unattended mode,
# but for a subagent tool call instead of a human-absent session. A subagent has no standing to judge
# triviality or spawn a reviewer, and there is no channel back to the Lead - so the honest move is the
# same as unattended's: convert ask -> deny, worded at the actor that can actually act (stop, don't
# retry a variant, report the text back so the Lead sees it). Takes priority over unattended (see
# guard_ask_prefix below) - a subagent's ask is unanswerable regardless of who's watching the session.
# FAIL DIRECTION (mirrors guard_unattended's own note above): a payload guard_caller_agent does not
# recognise as a subagent (no agent_id - see its header for the probe) means the guards keep asking -
# the attended-Lead status quo. Only a call guard_caller_agent reads as a subagent converts to deny.
GUARD_SUBAGENT_PREFIX="DELEGATED AGENT: this tool call came from a sub-agent, not the session Lead, so a question with no one able to answer it is returned as a deny instead of a halt. This gate is the Lead's to clear, not yours - do not retry a variant or route around it with another tool. Stop, and report this text verbatim in your final message so the Lead can see it and act. "

# Resolution order: the env override (selfchecks point it at a sandbox), then the caller's own $BASE -
# every guard computes that BEFORE it cds anywhere - and only then a $0-derived fallback. vcs-commit-
# guard cds into the target repo before it reaches its ask, so a $0-first order would look for the flag
# under the COMMITTED repo whenever $0 is relative (opus reviewer 2026-08-23, LOW). Empty means "no
# state dir", never a bare /.state.
guard_state_dir() {
  d="${AGENT_TIERS_STATE_DIR:-}"
  [ -n "$d" ] || d="${BASE:-}${BASE:+/.state}"
  [ -n "$d" ] || d="$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
  case "$d" in ''|'/.state') d="" ;; *) case "$d" in */.state) ;; *) d="$d/.state" ;; esac ;; esac
  printf '%s\n' "$d"
}

# guard_unattended <session_id> -> exit 0 if THIS session is flagged unattended
guard_unattended() {
  case "${1:-}" in
    '' | *[!A-Za-z0-9._-]* | '.' | '..') return 1 ;;
  esac
  d="$(guard_state_dir)"
  [ -n "$d" ] || return 1
  [ -f "$d/unattended.$1" ]
}

# guard_caller_agent <input_json> -> stdout: a non-empty name when the tool call came from a SUBAGENT,
# empty when it came from the session Lead. The test is `.agent_id`, not `.agent_type` (2026-10-14):
# probed on Claude Code 2.1.296 with PreToolUse(Bash) payload dumps, a plain main session carries
# neither field, a main session started with `--agent <name>` carries agent_type=<name> and NO
# agent_id, and a subagent carries agent_type AND a hex agent_id. Reading agent_type alone therefore
# treated a `--agent` main session as a subagent and converted every one of its asks to a deny.
# Rule: no (or empty) agent_id -> empty (the Lead), whatever agent_type says. agent_id present ->
# the agent_type, charset-stripped like every other payload-derived value in this kit (SESSION_ID in
# review-gate-guard.sh, etc) and with the `main`/`MAIN` sentinel normalised away (authorship-record.sh
# and numeric-claim-ledger.sh call this and record `MAIN` for an empty answer); when that leaves nothing (agent_type absent,
# empty, `main`, or failing the charset) the answer is the literal `subagent`, so a subagent is never
# read as the Lead because of an odd agent_type. Unparsable input -> empty.
# A plugin-namespaced type (`<plugin>:<agent>`, e.g. `agent-tiers:sublead`) is reduced to the part after
# the LAST `:` first, so name-keyed consumers see `sublead`; every name-keyed use only ADDS restrictions,
# so stripping the namespace never grants more.
# FAIL DIRECTION: a host that sends no agent_id for subagents would have every subagent read as the
# Lead. For the ask-class consumers that means asks stay asks (the attended status quo). For the
# DENY-class consumers it fails OPEN to Lead privileges: agent-selfdef-guard lets a subagent write its
# own definition, sc52a-write-disclosure-guard honours a subagent's own [bash-write:] marker, and
# task-spawn-guard's depth cap lets a subagent spawn a sublead. The probe above is the only evidence
# that current hosts send agent_id.
guard_caller_agent() {
  agt="$(printf '%s' "${1:-}" | jq -r 'if ((.agent_id // "") | tostring) != "" then "S" + ((.agent_type // "") | tostring) else "" end' 2>/dev/null || true)"
  case "$agt" in S*) agt="${agt#S}" ;; *) printf '\n'; return 0 ;; esac
  agt="${agt##*:}"
  case "$agt" in main|MAIN) agt="" ;; esac
  case "$agt" in *[!A-Za-z0-9._-]*) agt="" ;; esac
  [ -n "$agt" ] || agt="subagent"
  printf '%s\n' "$agt"
}

# guard_ask_decision <session_id> [agent_type] -> stdout: `ask` normally, `deny` when the session is
# unattended OR the caller is a subagent ($2 non-empty, i.e. guard_caller_agent returned a name - see
# its header for the agent_id rule, and GUARD_SUBAGENT_PREFIX above).
# Callers prepend guard_ask_prefix's output to their OWN reason text when this returns deny, and log
# the decision word they got - so guards.log records these denies like any other (HOST-4: the log is
# the durable human record of what a guard blocked). Existing single-arg callers are unaffected: a
# missing $2 is empty, same as "no agent".
guard_ask_decision() {
  if [ -n "${2:-}" ] || guard_unattended "${1:-}"; then printf 'deny\n'; else printf 'ask\n'; fi
}

# guard_ask_prefix <session_id> <agent_type> -> stdout: which reason-prefix a converted deny gets.
# Subagent takes priority over unattended (both could be true at once; a subagent's ask is unanswerable
# either way, and it's the more specific, more actionable diagnosis). Empty when the decision is a plain
# `ask` - callers can prepend this unconditionally, no `[ "$DEC" = deny ] &&` needed.
guard_ask_prefix() {
  if [ -n "${2:-}" ]; then printf '%s' "$GUARD_SUBAGENT_PREFIX"
  elif guard_unattended "${1:-}"; then printf '%s' "$GUARD_UNATTENDED_PREFIX"
  fi
}

# guard_marker_text <cmd> <tag> -> stdout: the text inside a `[<tag>:<reason>]` marker anywhere in
# <cmd>, newline-flattened (`tr` to a space, same as maint2-arrival-guard.sh's own marker reads - a
# multi-line REASON would otherwise write a second, unprefixed, model-controlled line into guards.log)
# and capped at 140 chars; empty when the tag is absent. Lifted 2026-09-14 from
# sc52a-write-disclosure-guard.sh's own `[bash-write:]` extraction (its first consumer) so kit-leak-
# guard.sh's `[leak-exception:]` and vcs-commit-guard.sh's `[vcs-exception:]` don't each hand-roll the
# same sed/tr/cut pipeline. Per-tag by construction (the sed pattern is built from $2), so one guard's
# marker can never satisfy another's check - callers never need to guard against that themselves.
guard_marker_text() {
  cmd="${1:-}"; tag="${2:-}"
  [ -n "$tag" ] || return 0
  case "$cmd" in
    *"[$tag:"*)
      printf '%s' "$cmd" | sed -n "s/.*\[$tag:\([^]]*\)\].*/\1/p" | tr '\n' ' ' | cut -c1-140
      ;;
  esac
}

# guard_split_segments <cmd> -> stdout, one pipeline segment per line (splits on && || | ; &), ALWAYS
# with a trailing newline - a `while IFS= read -r seg; do ... done` fed straight from this function's
# stdout silently skips the LAST segment if the output doesn't end in \n (POSIX `read` returns
# non-zero on a final line with no trailing newline, so the loop body never runs for it - caught live
# while proving this library on its first consumer: `printf '%s'`, the intuitive choice, does
# NOT add one, and a single-segment command, the common case, has no internal `;`/`&&`/etc for `sed`
# to turn into a newline either, so EVERY single-segment command was silently un-scanned). `printf
# '%s\n'` on the INPUT guarantees the output ends in \n too. Same idiom every guard in this kit
# already used ad hoc (each via its own `printf '%s\n' "$SEGMENTS"` re-emit before its while loop);
# centralized here as the second half of the command-position seam (a segment boundary is where
# "command position" resets).
guard_split_segments() {
  # awk, not sed: `sed 's/&&/\n/g'` is a GNU-ism - BSD/macOS sed emits a literal `n` in the
  # replacement, gluing chained segments into one line so no non-first segment is ever scanned
  # (cold-review F3, 2026-08-10). POSIX awk gsub handles the newline on both. Leftmost-longest
  # alternation makes `&&` win over `&` at the same position, matching the old sequential sed.
  printf '%s\n' "$1" | awk '{ gsub(/&&|\|\||\||;|&/, "\n"); print }'
}

# guard_split_segments_qsafe <cmd> -> stdout, same CONTRACT as guard_split_segments (one segment per
# line, ALWAYS trailing \n, segment text otherwise RAW) but QUOTE-AWARE: a &&/||/|/;/&/|& INSIDE a single-
# or double-quoted region is never treated as a boundary. guard_split_segments is quote-BLIND (it gsubs
# the delimiter characters wherever they appear), so a one-line commit message containing its own `;`
# or `&&` (`git commit -m "docs: WIP; git stash is shared"`) gets sliced mid-string, and the fragment
# after the accidental split can then match a verb-detection regex AT COMMAND POSITION even though it
# was never a real second command - worktree-guard.sh and git-add-stash-guard.sh both hit this
# (guards-review-2, 2026-09-23, claim 5/finding). Scans character by character with quote state
# 0/1/2 (none/single/double), same state machine as guard_strip_quotes, and does NOT blank quoted
# content: callers keep reading real argument values.
# Rules (2026-10-14 fix pass, each one probed wrong before it):
# - Every raw newline is a segment boundary, INSIDE quotes too, as before this pass. Keeping a quoted
#   newline inside its segment (an RS-byte encoding was tried) made any quote mis-track that balances
#   out again (`echo "$(printf "it's")"`, then a newline, a real command, and a comment holding `'`)
#   hide whole later lines from every consumer that matches at line start; a split quoted argument
#   only costs a consumer an unbalanced fragment, which fails toward scanning more, not less. There is
#   no `#` comment rule here either: a `#` mid-word (`$(x)#`) is not a comment to the shell.
# - Input is read as whole lines joined with \n, with no in-band record separator byte (an earlier
#   RS of 0x1A let that byte inside quotes reset the quote state).
# - Backslash: outside quotes `\X` is copied as both bytes and X is never a separator or a quote
#   opener (`ls \; rm x` is one segment); backslash-newline outside quotes (a line continuation) is
#   removed, both bytes. Inside double quotes `\"` and `\\` are copied as a pair and do not end the
#   quote. Inside single quotes a backslash is literal, as in the shell.
# - Redirection ampersands are not separators: `&` right after `>`/`<` (`2>&1`, `>&2`, `<&0`) and `&`
#   right before `>` (`&>f`, `&>>f`). `>|` is a redirect, not a pipe. `|&` is ONE separator.
# Ceilings (disclosed, not fixed): quote state does NOT reset inside a `$( )` nested in double quotes
# (`"$(echo ")")"` mis-tracks), and separators inside an UNQUOTED `$( )`/backtick still split, the same
# as at top level. A caller that needs to know a metacharacter is ABSENT (not the real value) still
# calls guard_strip_quotes on the INDIVIDUAL matched segment.
guard_split_segments_qsafe() {
  printf '%s' "${1:-}" | awk '
    BEGIN { SQ = "\047"; DQ = "\042"; RSB = "\036" }
    { s = s (NR > 1 ? "\n" : "") $0 }
    # scan(rs): rs=1 would map a newline inside quotes to RS; only rs=0 (raw newline) is used, see header.
    function scan(rs,    n, state, out, i, p, c, c2) {
      n = length(s); state = 0; out = ""; i = 1; p = ""
      while (i <= n) {
        c = substr(s, i, 1)
        if (state == 0) {
          c2 = substr(s, i, 2)
          if (c == "\\") {
            if (c2 != "\\\n") out = out c2
            i += 2; p = "\\"; continue
          }
          if (c2 == "&&" || c2 == "||" || c2 == "|&") { out = out "\n"; i += 2; p = ""; continue }
          if (c == "&" && (p == ">" || p == "<" || substr(s, i + 1, 1) == ">")) { out = out c; i++; p = c; continue }
          if (c == "|" && p == ">") { out = out c; i++; p = c; continue }
          if (c == "|" || c == ";" || c == "&") { out = out "\n"; i += 1; p = ""; continue }
          out = out c; p = c
          if (c == SQ) state = 1
          else if (c == DQ) state = 2
          i += 1
        } else if (state == 1) {
          out = out ((c == "\n" && rs) ? RSB : c)
          if (c == SQ) state = 0
          i += 1
        } else {
          c2 = substr(s, i, 2)
          if (c2 == "\\" DQ || c2 == "\\\\") { out = out c2; i += 2; continue }
          out = out ((c == "\n" && rs) ? RSB : c)
          if (c == DQ) state = 0
          i += 1
        }
      }
      endstate = state
      return out
    }
    END {
      if (NR == 0) exit
      out = scan(0)
      printf "%s\n", out
    }
  '
}

# guard_argv <segment> -> stdout: the segment as shell WORDS, one token per line, each line = one TAG
# byte + payload, every line newline-terminated. Payload newlines (a literal newline, or an RS already
# in the input, inside quotes) are emitted as RS (0x1E). Word rules follow POSIX: blanks (space, tab,
# newline, RS) outside quotes separate words; quote removal is applied; outside quotes `\X` -> X and
# backslash-newline is removed; inside double quotes only `\$ \` \" \\` and backslash-newline are
# escapes, any other `\X` keeps both bytes; inside single quotes a backslash is literal.
# Tags:
#   w  plain word, quotes removed (`'ssh'` -> `wssh`, `s\sh` -> `wssh`).
#   o  opaque word: has, outside single quotes, an unescaped `$` followed by one of
#      A-Za-z_0-9 { ( @ * # ? $ ! - ' "  or an unescaped backtick. `$(..)`, `${..}`, backticks and a
#      `<(`/`>(` process substitution at word start are consumed nesting-aware (parens/braces counted,
#      quotes inside tracked), so the word does not end at a space inside them; their text is kept
#      verbatim, the rest of the word is quote-removed. `$'..'` is kept verbatim (not decoded).
#   g  grouping/control: an unquoted `(`/`)` not part of `$(`/`<(`/`>(` (its own token even when
#      attached: `(ssh` -> `g(` `wssh`); `{`, `}`, `!` only as a whole unquoted word; `;;`. Any other
#      unquoted control operator left in the input (`;` `&` `|` `&&` `||` `|&`, which a segment from
#      the splitters should not carry) is also emitted as a `g` token rather than glued to a word.
#   r  redirection: `[0-9]*` + one of `<<<` `<<-` `<<` `>>` `>&` `<&` `<>` `>|` `>` `<`, or `&>>`/`&>`
#      (no digits), plus its target word (attached or the next word). Payload = `<op> <target>`, the op
#      KEEPS its fd digits (`2>&1` -> `r2>& 1`), target quote-removed; empty target -> `<op> ` (trailing
#      space). The target produces no `w` token of its own.
#   R  the same, when the target word is opaque (`2>"$log"` -> `R2> $log`).
#   u  no payload, ALWAYS the last line, when a quote or a `$(`/`${`/backtick/`<(` is still open at end
#      of input (the unclosed text is still emitted as part of the last token).
# `VAR=value` words are ordinary w/o tokens (the caller decides). For a heredoc operator the target is
# the delimiter word; the BODY is not this function's business (strip it first, guard_strip_heredocs).
# Also `o`: a word holding, unquoted and unescaped, a glob character (`*`, `?`, `[`), a brace span
# containing `,` or `..` (`{ssh,vps}`, `{a..b}`), or a leading `~` - the shell rewrites those, so the
# literal text is not the word that runs (`'*'` and `\*` stay `w`). A backslash-newline between words
# produces no token. Input is read as whole lines joined with \n (no in-band record separator byte).
# ponytail ceilings: a `#` comment is NOT recognised (its words are tokenised like any others, and an
# apostrophe in it opens a quote that may end in `u`, the conservative direction); a `)` inside a
# `case` pattern within `$( )` closes the substitution early; arithmetic `$(( ))` is just a nested
# `$(`; a brace span is only seen when it has no blank or metacharacter inside. POSIX awk only (no
# gensub, no 3-arg match).
guard_argv() {
  printf '%s' "${1:-}" | awk '
    BEGIN {
      SQ = "\047"; DQ = "\042"; RSB = "\036"; NL = "\n"
      VSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_0123456789{(@*#?$!-" SQ DQ
      META = " \t\n" RSB ";&|<>()"
    }
    # sub_end(p, open, close): position of the char closing a substitution whose body starts at p
    # (depth 1 already open), quotes inside tracked, backslash skips one char; 0 when never closed.
    function sub_end(p, op, cl,    d, q, ch) {
      d = 1; q = 0
      while (p <= n) {
        ch = substr(s, p, 1)
        if (q == 1) { if (ch == SQ) q = 0 }
        else if (ch == "\\") p++
        else if (q == 2) { if (ch == DQ) q = 0 }
        else if (ch == SQ) q = 1
        else if (ch == DQ) q = 2
        else if (ch == op) d++
        else if (ch == cl) { d--; if (d == 0) return p }
        p++
      }
      return 0
    }
    function bq_end(p,    ch) {
      while (p <= n) {
        ch = substr(s, p, 1)
        if (ch == "\\") p++
        else if (ch == "`") return p
        p++
      }
      return 0
    }
    # take_sub(p): p at `$(`, `${`, `<(`, `>(` or a backtick; appends the verbatim text to W, sets
    # opaque, returns the position after it (n+1 and unclosed=1 when it never closes).
    function take_sub(p,    ch, e) {
      ch = substr(s, p, 1)
      if (ch == "`") e = bq_end(p + 1)
      else if (substr(s, p + 1, 1) == "{") e = sub_end(p + 2, "{", "}")
      else e = sub_end(p + 2, "(", ")")
      opq = 1
      if (e == 0) { W = W substr(s, p); unclosed = 1; return n + 1 }
      W = W substr(s, p, e - p + 1)
      return e + 1
    }
    # word(p): parse one shell word from p into W (quote-removed) / opq; returns the end position.
    function word(p,    q, ch, d, e) {
      W = ""; opq = 0; q = 0
      if (substr(s, p, 1) == "~") opq = 1
      if ((substr(s, p, 2) == "<(" || substr(s, p, 2) == ">(")) p = take_sub(p)
      while (p <= n) {
        ch = substr(s, p, 1)
        if (q == 1) {
          if (ch == SQ) q = 0; else W = W ch
          p++; continue
        }
        if (ch == "\\") {
          d = substr(s, p + 1, 1)
          if (d == NL) { p += 2; continue }
          if (q == 2 && index("$`" DQ "\\", d) == 0) { W = W ch; p++; continue }
          W = W d; p += 2; continue
        }
        if (ch == "$") {
          d = substr(s, p + 1, 1)
          if (d != "" && index(VSET, d) > 0) {
            opq = 1
            if (d == "(" || d == "{") { p = take_sub(p); continue }
            if (d == SQ && q == 0) {
              e = p + 2
              while (e <= n && substr(s, e, 1) != SQ) { if (substr(s, e, 1) == "\\") e++; e++ }
              if (e > n) { W = W substr(s, p); unclosed = 1; p = n + 1; continue }
              W = W substr(s, p, e - p + 1); p = e + 1; continue
            }
          }
          W = W ch; p++; continue
        }
        if (ch == "`") { p = take_sub(p); continue }
        if (q == 2) {
          if (ch == DQ) q = 0; else W = W ch
          p++; continue
        }
        if (index(META, ch) > 0) break
        if (ch == "*" || ch == "?" || ch == "[") opq = 1
        else if (ch == "{") {
          e = p + 1
          while (e <= n && index(META, substr(s, e, 1)) == 0 && substr(s, e, 1) != "}") e++
          if (substr(s, e, 1) == "}" && (index(substr(s, p, e - p), ",") > 0 || index(substr(s, p, e - p), "..") > 0)) opq = 1
        }
        if (ch == SQ) q = 1
        else if (ch == DQ) q = 2
        else W = W ch
        p++
      }
      if (q != 0) unclosed = 1
      return p
    }
    function emit(t, pl) { gsub(/\n/, RSB, pl); printf "%s%s\n", t, pl }
    { s = s (NR > 1 ? "\n" : "") $0 }
    END {
      n = length(s); i = 1; unclosed = 0
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == " " || c == "\t" || c == NL || c == RSB) { i++; continue }
        if (substr(s, i, 2) == "\\" NL) { i += 2; continue }
        # redirection: [0-9]* then an operator (process substitution `<(`/`>(` excluded)
        j = i
        while (j <= n && index("0123456789", substr(s, j, 1)) > 0) j++
        rop = ""
        if (j == i && (substr(s, j, 3) == "&>>")) rop = "&>>"
        else if (j == i && substr(s, j, 2) == "&>") rop = "&>"
        else if (substr(s, j, 3) == "<<<" || substr(s, j, 3) == "<<-") rop = substr(s, j, 3)
        else if ((c2 = substr(s, j, 2)) == "<<" || c2 == ">>" || c2 == ">&" || c2 == "<&" || c2 == "<>" || c2 == ">|") rop = c2
        else if ((substr(s, j, 1) == "<" || substr(s, j, 1) == ">") && !(j == i && substr(s, j + 1, 1) == "(")) rop = substr(s, j, 1)
        if (rop != "") {
          op = substr(s, i, j - i) rop
          k = j + length(rop)
          while (k <= n && (substr(s, k, 1) == " " || substr(s, k, 1) == "\t")) k++
          tc = substr(s, k, 1)
          if (k <= n && (index(META, tc) == 0 || substr(s, k, 2) == "<(" || substr(s, k, 2) == ">(")) {
            i = word(k)
            emit(opq ? "R" : "r", op " " W)
          } else { emit("r", op " "); i = k }
          continue
        }
        if (c == "(" || c == ")") { emit("g", c); i++; continue }
        if (c == ";" || c == "&" || c == "|") {
          c2 = substr(s, i, 2)
          if (c2 == ";;" || c2 == "&&" || c2 == "||" || c2 == "|&") { emit("g", c2); i += 2 }
          else { emit("g", c); i++ }
          continue
        }
        st = i
        i = word(i)
        raw = substr(s, st, i - st)
        if (raw == "{" || raw == "}" || raw == "!") emit("g", raw)
        else emit(opq ? "o" : "w", W)
      }
      if (unclosed) print "u"
    }
  '
}

# guard_segs_at_cmdpos <segments> <target_ere> -> stdout: EVERY segment (original text, unstripped -
# callers re-parse and log it) where target_ere matches at COMMAND POSITION (CMDPOS_PREFIX), matched
# after stripping a leading subshell/group open (`(`/`{`), the same strip guard_resolve_cwd's `cd` leg
# and guard_commit_optspan do. Empty output = no match. FLAT cost - one sed + one grep over the whole
# blob, not per segment (opus reviewer, 2026-08-16: a per-segment loop was 2 execs x segments x every
# wired guard on EVERY Bash call; this is 5 processes regardless of segment count).
guard_segs_at_cmdpos() {
  n="$(printf '%s\n' "$1" | sed -E 's#^[[:space:]]*[({][[:space:]]*##' | grep -anE "${CMDPOS_PREFIX}$2" | cut -d: -f1 | tr '\n' ',')"
  [ -n "$n" ] || return 0
  printf '%s\n' "$1" | awk -v want=",$n" 'index(want, "," NR ",")'
}

# guard_commit_seg <segments> -> stdout: the FIRST segment that is a `git commit` at command position
# (guard_segs_at_cmdpos + CMDPOS_COMMIT_FRAG). This is THE commit-segment detector for all four
# commit-time guards (2026-08-16, Tier 1 review T1.2): before it, each guard hand-copied
# `grep -aE "^[[:space:]]*${CMDPOS_COMMIT_FRAG}"`, which sees no wrapper at all - see
# CMDPOS_COMMIT_FRAG's header for the measured miss and the corrected claim that licensed it.
guard_commit_seg() {
  guard_segs_at_cmdpos "$1" "$CMDPOS_COMMIT_FRAG" | head -1
}

# guard_git_add_segs <segments> -> stdout: every `git add` segment at command position (original
# text). Shared by hygiene-commit-guard.sh (ADD_PRESENT) and vcs-commit-guard.sh (ADD_SEGS) - both
# used the narrow `^[[:space:]]*git[[:space:]]+add` anchor this file now forbids, so `(git add . &&
# git commit)` fired the commit half and blinded the add half (opus reviewer, 2026-08-16). Still NOT
# CMDPOS_GITOPTS-aware (`git -C x add` is a disclosed gap, CMDPOS_ADD_FRAG follow-up).
GUARD_GIT_ADD_FRAG='git[[:space:]]+add([[:space:]]|$)'
guard_git_add_segs() {
  guard_segs_at_cmdpos "$1" "$GUARD_GIT_ADD_FRAG"
}

# guard_norm_add_paths <prefix> : stdin = one `git add`/`git commit` path token per line -> stdout =
# the same tokens quote-stripped, leading `./` dropped, absolute paths kept, everything else joined
# to <prefix> (git rev-parse --show-prefix, so a token typed in a subdir resolves the way git will).
# Shared by vcs-commit-guard.sh (ADD_PATHS) and kit-leak-guard.sh (EXTRA, COMMIT_PATHS) - each used to
# carry this as an inline `$( ... | while ...; case ...; done)` loop, and macOS CI (2026-08-16) showed
# bash 3.2 (macOS /bin/sh) cannot parse a `case` with `\"*\")` patterns inside a command substitution
# ("syntax error near unexpected token newline"), so every `git add <path> && git commit` silently
# fail-opened on a Mac. A function body is parsed normally; the guards substitute the CALL.
guard_norm_add_paths() {
  while IFS= read -r tok; do
    case "$tok" in
      \"*\") tok="${tok#\"}"; tok="${tok%\"}" ;;
      \'*\') tok="${tok#\'}"; tok="${tok%\'}" ;;
    esac
    tok="${tok#./}"
    case "$tok" in
      /*) printf '%s\n' "$tok" ;;
      *) printf '%s\n' "$1$tok" ;;
    esac
  done
}

# guard_at_command_position <segment> <target_ere> -> exit 0 if target_ere matches at command
# position within segment (after the shared PREFIX), exit 1 otherwise. target_ere is a bare ERE
# fragment (no anchors) - e.g. 'instance-root\.sh([[:space:]]|$)' or 'dd\b'.
# Strips a leading subshell/group open (`(`/`{`) first, the same strip guard_segs_at_cmdpos,
# guard_verb_optspan and guard_resolve_cwd's legs all do - without it a `(cmd ...)` segment matched
# none of CMDPOS_PREFIX's anchors and the whole check went silent (found 2026-08-23 proving W1-1's
# `(git push -f)` case; this function was the last copy still missing the strip).
guard_at_command_position() {
  printf '%s' "$1" | sed -E 's#^[[:space:]]*[({][[:space:]]*##' | grep -aEq "${CMDPOS_PREFIX}$2"
}

# guard_resolve_cwd <segments> <stop_ere> <start_cwd> -> stdout: the directory the FIRST segment
# matching stop_ere (at command position) will actually run in.
#
# Why this exists: every commit-time guard (review-gate-guard.sh, kit-leak-guard.sh,
# vcs-commit-guard.sh, hygiene-commit-guard.sh) used to `cd` straight to the PreToolUse payload's
# `.cwd` and treat that as "the repo this commit targets" - true only when the command never `cd`s
# itself. `cd ~/.claude/agent-tiers && git commit ...` run from a project session cds into the kit
# repo for real, but the payload's `.cwd` stays the SESSION's project dir: every guard computed the
# wrong repo (usually not a kit checkout, not the review-gated repo) and silently skipped -
# live-verified 2026-08-16 (a private-vocab-tagged staged file committed straight through kit-leak-guard,
# and the same commit skipped review-gate-guard too, both because $CWD pointed at the wrong repo).
# kit-leak-guard.sh and leak-scan.sh are KIT-LOCAL, NOT BUNDLED (export-ignored in .gitattributes), so a
# recipient can reproduce only the review-gate-guard half of that verification; the kit-leak half is
# an origin-machine observation (stated 2026-08-16, Tier 1 review T1.4).
# Walks segments IN ORDER, stops at the first one matching stop_ere (the commit segment itself is
# never treated as a `cd`), and for every earlier `cd <dir>` segment at command position, actually
# cds there (relative to the running cwd so a chain of cds composes) - same idiom the guards already
# use to resolve the payload cwd, just seeded by the command text instead of trusting `.cwd` blindly.
# A `cd`/`-C` into a directory that doesn't exist/isn't enterable, or a `cd -`, or a non-literal
# target (`cd "$VAR"`, `cd $(cmd)`) is UNRESOLVABLE: the cwd becomes unknown and, unless a later
# ABSOLUTE hop recovers it (guard_hop below), the answer is `unresolved <first bad target>` instead
# of a directory (see guard_cwd_unresolved below). Before 2026-08-16 (T1.10) it fell soft to
# the running cwd, and `mkdir X && cd X && git commit` - X does not exist at PreToolUse time - made
# every commit guard scan the SESSION repo and deny on files that commit never touched (three live
# false denials, 2026-08-16). Callers decide what an unresolved answer means (hygiene-commit-guard.sh
# denies, kit-leak-guard.sh denies unless the target provably isn't a kit checkout, vcs-commit-guard.sh
# declines to scan, review-gate-guard.sh skips its repo-keyed marker) - never fall back to the payload
# cwd: that IS the wrong-repo scan this exists to prevent. Bare `cd` / `cd ~` -> $HOME. A `(cd X &&
# ...)` subshell-wrapped segment is recognised too - the segment split does not break on bare `(`/`)`,
# so the wrapper is stripped before the cd match (opus reviewer, 2026-08-16: the wrapper alone hid a
# real `cd` from this function while the guards' own COMMIT_SEG match still fired on the commit half,
# so the resolved cwd silently stayed wrong for exactly the class this function exists to fix).
# ponytail: `cd -` (previous dir) is not tracked - reported unresolved (see guard_norm_cd_target
# below); not worth a stateful OLDPWD dance for a guard heuristic. `cd "$VAR"`/`cd $(cmd)` are not
# resolved either (same "literal text only" ceiling guard-cmdpos.sh already discloses for its prefix
# match) - the literal `$VAR` is not a directory, so they surface as unresolved, which is the honest
# answer. The walk stops at the FIRST stop_ere match
# regardless of what runs after it, so a chained `cd a && commit1 && cd b && commit2` only ever
# resolves commit1's repo - pre-existing (COMMIT_SEG is itself `head -1` in every guard), not new here.
# No cap on segments walked (kit's other scan legs cap around 500) - a hostile/generated 100+-segment
# chain is a measurable slice of the 5s hook budget; accepted, not expected in real usage.

# guard_norm_cd_target <raw> -> stdout: quote-stripped, `~`-expanded target; bare/empty -> $HOME;
# exactly `-` (the unsupported `cd -`/previous-dir form) -> empty. Shared by both cd-segment and
# `-C`-token resolution below so the two don't drift on quoting/`~`/`-` handling.
guard_norm_cd_target() {
  t="$1"
  case "$t" in
    \"*\") t="${t#\"}"; t="${t%\"}" ;;
    \'*\') t="${t#\'}"; t="${t%\'}" ;;
  esac
  case "$t" in
    '') t="$HOME" ;;
    '~') t="$HOME" ;;
    '~/'*) t="$HOME/${t#'~/'}" ;;
    -) t="" ;;
  esac
  printf '%s\n' "$t"
}

# guard_cd_into <cwd> <target> -> stdout: the resolved directory, or empty if unenterable.
# CDPATH= on both hops: a `cd` whose target matches an exported CDPATH entry writes the resolved path
# to STDOUT (POSIX), which would otherwise leak into the result alongside pwd's own output and corrupt
# it (opus reviewer, 2026-08-16). Neutralized here rather than trusted to be unset in the hook's env.
guard_cd_into() {
  CDPATH= cd "$1" >/dev/null 2>&1 && CDPATH= cd "$2" >/dev/null 2>&1 && pwd
}

# <verb> (4th arg, default `commit`): the literal word that bounds the pre-verb option span the `-C`
# extraction below reads - see guard_verb_optspan. A caller passing a non-commit stop_ere must pass its
# verb too, or a `-C` before that verb is not folded (dangerous-actions-blocker.sh passes `push`).
# <nth> (5th arg, default 1): stop at the Nth segment matching stop_ere, not the first. Every
# commit-time guard resolves for ONE segment (`guard_commit_seg | head -1`), so first == the segment
# they test and the default is right for them. A caller that TESTS EVERY matching segment must say
# WHICH one it is asking about, or every match after the first silently gets the FIRST match's
# directory - opus reviewer 2026-08-23, HIGH: a chained command whose second push segment sat after a
# `cd` into another repo resolved to the payload cwd and allowed a force-push to master there.
# Earlier matches are passed over, never treated as `cd`s (a `-C` on a git verb does not move the shell).
guard_resolve_cwd() {
  segs="$1" stop_ere="$2" cwd="$3" verb="${4:-commit}" nth="${5:-1}" hit=0 unres="" grp=""
  printf '%s\n' "$segs" | (
    while IFS= read -r seg; do
      # A cd that opened a group/subshell (`(cd X && git pull) && git commit`, `$(cd X && ...)`) is scoped
      # to that group: once a `)`/`}`/backtick shows up in a LATER non-stop segment, the real shell is
      # back where it was, but this walk had folded X in - a RESOLVED wrong answer (opus reviewer, wave
      # A 2026-08-16, MEDIUM: pre-existing, hidden behind the paren strip). Decline rather than restore
      # the pre-group cwd: the splitter is quote-blind, so a `)` inside a later string would make a
      # restore guess wrong in the other direction. Single-level only (ponytail); a later absolute hop
      # still recovers, as anywhere else.
      # Strip a leading subshell/group-open (`(`/`{`) ONCE, for every leg below - see the long note at
      # the stop leg for why the anchors need it.
      bare="$(printf '%s' "$seg" | sed -E 's#^[[:space:]]*[({][[:space:]]*##')"
      is_stop=0; printf '%s' "$bare" | grep -aEq "${CMDPOS_PREFIX}${stop_ere}" && is_stop=1
      # The stop segment is exempt from the group-close check (its own `)` closes the group the walk is
      # ending on anyway). A segment that MATCHES the stop pattern but is passed over by nth is NOT:
      # exempting it let a `cd` scoped to an already-closed subshell survive to the segment that really
      # stops the walk, resolving the wrong repo (opus reviewer 2026-08-23, MEDIUM - reachable only
      # once nth existed, since before it the walk always stopped at the first match).
      if [ -n "$grp" ] && { [ "$is_stop" = 0 ] || [ $((hit + 1)) -lt "$nth" ]; }; then
        case "$seg" in *')'*|*'}'*|*'`'*) cwd=""; [ -n "$unres" ] || unres="$grp"; grp="" ;; esac
      fi
      # `bare` (above) is the segment with a leading subshell/group-open stripped: the segment splitter
      # does not break on bare parens, so `(cd /x && git commit ...)` arrives as ONE segment starting
      # with `(cd`, and `( git commit -m x )` as one starting with `( git`, which CMDPOS_PREFIX's
      # anchors (^, $(, backtick) do not recognise as command position. The stop (commit) leg never
      # had this strip until 2026-08-16 (Tier 1 review, T1.2) - it walked PAST a `( git commit )` and
      # kept treating later segments as cd candidates; the cd leg had it since the paren fix below.
      if [ "$is_stop" = 1 ]; then
        hit=$((hit + 1))
        [ "$hit" -lt "$nth" ] && continue
        # `-C <path>` inside the commit segment ITSELF changes git's effective cwd before it runs,
        # same as a preceding `cd` - fold any (repeated, left-to-right, each relative to the last)
        # -C token into the resolved cwd before stopping (CMDPOS_COMMIT_FRAG above is what let this
        # segment match stop_ere with a -C token present in the first place). `--git-dir=`/
        # `--work-tree=` are NOT resolved here - see CMDPOS_COMMIT_FRAG's header for why (hygiene- and
        # kit-leak-guard.sh instead DENY on them via guard_unresolved_repo_flag(), before this function
        # even needs to guess a cwd).
        # guard_commit_optspan() bounds the search to the pre-verb option tokens ONLY - opus reviewer,
        # 2026-08-16: without that bound, a `-C` anywhere LATER in the segment (inside `git commit
        # --amend -C HEAD`'s own --reuse-message flag, or the literal substring "-C /tmp" typed into a
        # `-m` commit MESSAGE) was read as a real cd target, silently redirecting every guard to the
        # wrong (or an unrelated) repo - the exact silent-wrong-cwd class this whole function exists to
        # close. A regex-match-capture version of that bound was theorized to have a subtler
        # leftmost-longest swallow case; mutation-tested (opus advisor, 2026-08-16), it did not
        # reproduce, but the plain token-scan guard_commit_optspan() uses has no such ambiguity to begin
        # with and was kept for that reason - see its own header for the class of miss it trades in
        # instead (a named flag whose OWN value happens to be the literal word "commit" - contrived).
        dashc="$(guard_verb_optspan "$seg" "$verb" | awk 'f{print; f=0} $0=="-C"{f=1}')"
        if [ -n "$dashc" ]; then
          # Positional-parameter loop, not a piped `while read` - a second pipe here would nest
          # ANOTHER subshell and lose $cwd updates the moment it closes (the same trap this whole
          # function's outer `printf | ( ... )` wrapper exists to avoid). `set -f`: an unquoted `set
          # --` still globs a `-C` target containing `*`/`?`/`[` against the hook's real cwd (opus
          # reviewer, 2026-08-16) - suppressed for the duration of the loop, restored after.
          oldIFS="$IFS"; IFS='
'
          set -f; set -- $dashc; set +f
          IFS="$oldIFS"
          for t in "$@"; do
            guard_hop "$t"
          done
        fi
        break
      fi
      if printf '%s' "$bare" | grep -aEq "${CMDPOS_PREFIX}cd([[:space:]]|\$)"; then
        # `#` delimiter, not `/`: CMDPOS_PREFIX itself contains a literal `/` (the optional `./`
        # wrapper strip), which broke the substitution silently defaulting `target` to empty (found
        # live while proving this function - a failed sed here always fell through to the bare-`cd`
        # case, so EVERY `cd <dir>` resolved to $HOME instead of <dir>).
        guard_hop "$(printf '%s' "$bare" | sed -E "s#${CMDPOS_PREFIX}cd[[:space:]]*##; s#^[[:space:]]+##; s#[[:space:]]+\$##")"
        # remember a group-opening cd (leading `(`/`{`, or `$(`/backtick command position) - see the
        # group-close check at the top of the loop.
        grp=""; printf '%s' "$seg" | grep -aEq '^[[:space:]]*([({]|\$\(|`)' && grp="$raw"
      fi
    done
    if [ -n "$cwd" ]; then printf '%s\n' "$cwd"; else printf 'unresolved %s\n' "$unres"; fi
  )
}

# guard_hop <raw cd/-C target> - one hop of guard_resolve_cwd's walk, applied to the subshell's $cwd/
# $unres (called ONLY from inside that subshell; not a public helper). A hop that cannot be entered
# marks the cwd UNKNOWN (cwd="", $unres = the FIRST raw target that failed, kept for the caller's
# reason text) rather than being skipped; a later ABSOLUTE hop (`cd /x`, `-C /x`, `cd ~/x`) recovers,
# since it does not depend on the running cwd (`cd nope; git -C /kit commit` lands in /kit whatever
# `nope` was - found while proving T1.10: the first cut stopped at the first bad hop and kit-leak-guard
# reported /kit's commit as out of scope). A later RELATIVE hop while unknown stays unknown.
# TODO (carried, opus reviewer 2026-08-17 and 2026-08-23): guard_resolve_cwd arms `grp` from this
# function's `$raw`, so a BARE `cd` that opens a group (`(cd && git pull) && git commit -m x`) leaves
# raw empty, the group is never armed, and the group-close invalidation never fires - $HOME is then
# reported as a RESOLVED answer. Arm grp from the segment text instead. Rare shape; not fixed here.
guard_hop() {
  raw="$1"; t="$(guard_norm_cd_target "$raw")"
  new=""
  if [ -n "$t" ]; then
    case "$t" in
      /*) new="$(guard_cd_into / "$t")" ;;
      *)  [ -n "$cwd" ] && new="$(guard_cd_into "$cwd" "$t")" ;;
    esac
  fi
  if [ -n "$new" ]; then cwd="$new"; unres=""
  else cwd=""; [ -n "$unres" ] || unres="$raw"; fi
}

# guard_cwd_unresolved <guard_resolve_cwd result> -> exit 0 if the resolver DECLINED (an unresolvable
# `cd`/`-C` target, or `cd -`); the raw target text is `${result#unresolved }`. A resolved answer is
# always an absolute path (pwd), so "does not start with /" is the whole test - callers never
# string-compare the sentinel themselves.
guard_cwd_unresolved() {
  case "$1" in /*) return 1 ;; *) return 0 ;; esac
}

# --- ship-guards wave (2026-10-06, repaired 2026-10-06): a generic local-config scalar and the push/
# PR detector review-gate-guard.sh needs for its publish arm. guard_linked_worktree and the
# merge/cherry-pick detector (GUARD_MERGE_FRAG/guard_merge_seg) from the first pass were REMOVED after
# independent review - the worktree carve-out and the merge arm are not part of the shipped design.

# guard_main_top <dir> -> stdout: the MAIN worktree's top-level directory - the parent of the resolved
# `git rev-parse --git-common-dir` (that dir is always <main-top>/.git, main checkout or linked
# worktree alike), never the toplevel of <dir> itself, which for a linked worktree is the worktree's
# OWN directory, not the main checkout that holds the git-ignored `.claude/agent-tiers.local.md` a
# linked worktree has no copy of (the reason this function exists at all - review-gate-guard.sh's
# mode config has to be read from the main checkout even when the effective cwd is a worktree, e.g. a
# Lead working directly inside one). `CDPATH= cd` on both hops - same neutralization guard_cd_into
# already applies, and for the same reason: a `cd` whose target matches an exported CDPATH entry
# writes the resolved path to STDOUT (POSIX), which would otherwise corrupt the captured directory.
# ponytail ceiling: a bare repo's common-dir is not literally named ".git" under a work tree - taking
# dirname of it would land one level too shallow; not chased further (bare-repo dotfiles layouts are
# already a disclosed ceiling elsewhere in this file, see GUARD_UNRESOLVED_REPO_REASON).
guard_main_top() {
  d="${1:-}"; [ -n "$d" ] || return 1
  cd_raw="$(CDPATH= cd "$d" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)" || return 1
  [ -n "$cd_raw" ] || return 1
  cd_r="$(CDPATH= cd "$d" 2>/dev/null && CDPATH= cd "$cd_raw" 2>/dev/null && pwd -P)" || return 1
  dirname "$cd_r"
}

# guard_local_scalar <top> <key> <allowed-values-space-separated> <strict-default> -> stdout:
#   line 1: the resolved value (always one of <allowed-values>, since missing/typo/empty/duplicate
#           all fall back to <strict-default>)
#   line 2: present ONLY when resolution fell back for a reason worth a breadcrumb ("<source>:
#           <why>") - absent on a clean resolve, so a caller can test for a second line rather than
#           parse the reason text to decide whether to log it.
# Generalises hygiene-commit-guard.sh's own pre-refactor `hygiene_scope` resolver (same two-file
# order and precedence: <top>/.claude/agent-tiers.local.md, then $BASE/kit-config.md; same "empty
# path must not read from /" guard) to any `key: value` line, since review_gate needed a second,
# differently-keyed scalar and a second hand-rolled copy is exactly the seam this library exists to
# prevent (guard-cmdpos.sh's own header, round 3 of the kit's doctrine). A found key line resolves
# from THAT file - this does not keep searching the second file on a malformed value in the first
# (a typo in the repo's own override should not let the kit-wide default quietly win instead); only
# a MISSING file or an ABSENT key moves on to the next source. A trailing `# comment` on the value
# line is stripped before matching, so `review_gate: push  # rolled out 2026-10` parses to `push`.
guard_local_scalar() {
  gls_top="${1:-}" gls_key="${2:-}" gls_allowed="${3:-}" gls_strict="${4:-}"
  gls_val="" gls_reason="" gls_src=""
  for gls_src in "${gls_top:-/dev/null}/.claude/agent-tiers.local.md" "${BASE:-/dev/null}/kit-config.md"; do
    case "$gls_src" in /.claude/*|/kit-config.md) continue ;; esac   # empty top/BASE must not read from /
    [ -f "$gls_src" ] || continue
    gls_n="$(grep -ac "^${gls_key}:" "$gls_src" 2>/dev/null || echo 0)"
    if [ "${gls_n:-0}" -gt 1 ] 2>/dev/null; then
      gls_reason="$gls_src: multiple ${gls_key} lines - ambiguous, using $gls_strict"
      gls_val="$gls_strict"
      break
    fi
    [ "${gls_n:-0}" -eq 1 ] 2>/dev/null || continue
    gls_raw="$(grep -aE "^${gls_key}:" "$gls_src" 2>/dev/null | head -1 | sed -E "s/^${gls_key}:[[:space:]]*//; s/[[:space:]]*#.*\$//; s/[[:space:]]*\$//")"
    [ -n "$gls_raw" ] || { gls_reason="$gls_src: empty ${gls_key} value - using $gls_strict"; gls_val="$gls_strict"; break; }
    gls_val="$gls_raw"
    case " $gls_allowed " in
      *" $gls_val "*) ;;
      *) gls_reason="$gls_src: unrecognised ${gls_key} '${gls_val}' - using $gls_strict"; gls_val="$gls_strict" ;;
    esac
    break
  done
  [ -n "$gls_val" ] || gls_val="$gls_strict"
  printf '%s\n' "$gls_val"
  [ -n "$gls_reason" ] && printf '%s\n' "$gls_reason"
  return 0
}

# GUARD_PUSH_FRAG / GUARD_SHIP_FRAG / guard_ship_seg: `git push`, `gh pr create`, or `gh pr merge` at
# command position - the publish arm of the ship-guards table. GUARD_PUSH_FRAG is exposed separately
# (not just inlined into GUARD_SHIP_FRAG) so a caller that already has a matched ship segment can tell
# STRUCTURALLY which alternative it was (`guard_at_command_position "$seg" "$GUARD_PUSH_FRAG"`), rather
# than a substring test on the segment text (`case $seg in *push*)`) - a substring test would misread
# a `gh pr create --title "let's push this"` segment as a git push because the TITLE happens to
# contain the word (review-gate-guard.sh's own ACT_WORD classification needs this, repair wave
# 2026-10-06). One combined ERE for detection (one grep pass via guard_segs_at_cmdpos, not three),
# matching the flat-cost contract guard_segs_at_cmdpos's own header already requires of every caller.
# ponytail ceiling: `gh` has no CMDPOS_GITOPTS-shaped option span modeled here (no `gh -C`/`gh -c`
# equivalent exists to fold), so a global `gh` flag before `pr` is not recognised - disclosed, not a
# measured incident; `gh pr create`/`gh pr merge` are typed bare in practice.
GUARD_PUSH_FRAG="git[[:space:]]+(${CMDPOS_GITOPTS})*push([[:space:]]|\$)"
GUARD_SHIP_FRAG="(${GUARD_PUSH_FRAG}|gh[[:space:]]+pr[[:space:]]+(create|merge)([[:space:]]|\$))"
guard_ship_seg() {
  guard_segs_at_cmdpos "$1" "$GUARD_SHIP_FRAG" | head -1
}

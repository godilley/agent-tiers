#!/usr/bin/env sh
# kit-scope: shared
# Self-check for guard-cmdpos.sh - the shared splitter/command-position library four guards now source
# (dangerous-actions-blocker, vcs-commit-guard, hygiene-commit-guard, grep-footgun-guard). Exists because
# cold-review F3 (2026-08-10) found the previous sed-based splitter was a GNU-ism: on BSD/macOS sed the
# `\n` replacement emitted a literal `n`, gluing chained segments into one line so every consumer
# silently stopped scanning non-first segments. These asserts fail loudly on any host where splitting
# regresses, instead of every dependent guard passing vacuously. Exits non-zero on first failure.
set -u
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

# 0. Parse check, BEFORE the source below: ~30 hooks dot-source this library, and a syntax error makes
# sh (bash in POSIX mode) and dash exit 2 at the source line, which blocks every PreToolUse(Bash) call.
for psh in sh dash bash; do
  if command -v "$psh" >/dev/null 2>&1; then
    perr="$("$psh" -n "$(dirname "$0")/guard-cmdpos.sh" 2>&1)" || fail "$psh -n reports a parse error in guard-cmdpos.sh: $perr"
    [ -z "$perr" ] || fail "$psh -n reports a parse error in guard-cmdpos.sh: $perr"
  else
    printf 'note: %s not installed, its parse check skipped\n' "$psh"
  fi
done
printf 'ok   guard-cmdpos.sh parses under sh -n, dash -n and bash -n (where installed)\n'

. "$(dirname "$0")/guard-cmdpos.sh" || fail "cannot source guard-cmdpos.sh"
command -v guard_split_segments >/dev/null 2>&1 || fail "guard_split_segments undefined after source"

# 1. Every separator produces a real newline split (the F3 regression core).
[ "$(guard_split_segments 'a && b' | wc -l)" -eq 2 ] || fail "'&&' did not split (F3 regression)"
[ "$(guard_split_segments 'a || b' | wc -l)" -eq 2 ] || fail "'||' did not split"
[ "$(guard_split_segments 'a | b'  | wc -l)" -eq 2 ] || fail "'|' did not split"
[ "$(guard_split_segments 'a ; b'  | wc -l)" -eq 2 ] || fail "';' did not split"
[ "$(guard_split_segments 'a & b'  | wc -l)" -eq 2 ] || fail "'&' did not split"
[ "$(guard_split_segments 'a && b; c | d')" = "$(printf 'a \n b\n c \n d\n')" ] || fail "mixed separators split wrong"

# 2. No literal 'n' glued in (the exact BSD-sed failure shape).
[ "$(guard_split_segments 'foo && git commit' | sed -n 2p)" = ' git commit' ] || fail "second segment mangled (BSD-sed shape)"

# 3. Single-segment command still ends in \n (a read loop must not skip the only segment).
[ "$(guard_split_segments 'git commit -m x' | wc -l)" -eq 1 ] || fail "single segment lost its trailing newline"

# 4. Command-position matcher: hits at segment start / after sudo, misses mid-argument.
guard_at_command_position 'git commit -m x' 'git[[:space:]]+commit' || fail "cmdpos missed a plain hit"
guard_at_command_position 'sudo git commit' 'git[[:space:]]+commit' || fail "cmdpos missed after sudo"
guard_at_command_position 'echo "git commit"' 'git[[:space:]]+commit' && fail "cmdpos matched inside an argument"

# 4b. guard_has_heredoc (2026-09-02): a command containing a heredoc redirect is detected; one without
# is not - the callers that use this (grep-footgun-guard.sh, memory-write-gate.sh, simple-rules-guard.sh,
# pgrep-footgun-guard.sh) stand down entirely on a true result, so a false positive here (missing a real
# heredoc) would silently widen every one of their accepted ceilings.
guard_has_heredoc "$(printf 'cat <<EOF\ngit commit -m x\nEOF')" || fail "guard_has_heredoc missed a real heredoc"
guard_has_heredoc "git commit -m x" && fail "guard_has_heredoc false-positived on a plain command"

# 5. guard_resolve_cwd: the cd-aware effective-cwd resolver (F-cwd-bypass, 2026-08-16). Own sandbox
#    tree + a fake $HOME so the `~` cases (the literal incident reproducer) are host-independent.
command -v guard_resolve_cwd >/dev/null 2>&1 || fail "guard_resolve_cwd undefined after source"
TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"   # macOS TMPDIR ends in "/" - a "//" in T breaks every pwd comparison (CI, 2026-08-16)
T="${TMPBASE}/at-cmdpos-resolve.$$"
rm -rf "$T"; mkdir -p "$T/home/.claude/agent-tiers" "$T/a" "$T/a/sub" "$T/b" "$T/b/sub" "$T/start" "$T/start/HEAD" "$T/start/commit" || fail "cannot build sandbox"
trap 'rm -rf "$T"' EXIT
HOME_SAVE="${HOME:-}"; HOME="$T/home"

check_rc() { # $1=want $2=segs $3=stop_ere $4=start_cwd $5=label
  got="$(guard_resolve_cwd "$2" "$3" "$4")"
  [ "$got" = "$1" ] || fail "guard_resolve_cwd $5: want=$1 got=$got"
  printf 'ok   [%s] %s\n' "$got" "$5"
}
command -v guard_norm_cd_target >/dev/null 2>&1 || fail "guard_norm_cd_target undefined after source"
command -v guard_cd_into >/dev/null 2>&1 || fail "guard_cd_into undefined after source"
STOP="$CMDPOS_COMMIT_FRAG"   # the REAL shared fragment, not a stale local copy - drift would go undetected otherwise

# 5a. no cd at all -> falls back to start_cwd unchanged.
check_rc "$T/start" "$(guard_split_segments "git commit -m x")" "$STOP" "$T/start" "no cd -> unchanged"

# 5b. bare `cd` / `cd ~` -> HOME.
check_rc "$T/home" "$(guard_split_segments "cd && git commit -m x")" "$STOP" "$T/start" "bare cd -> HOME"
check_rc "$T/home" "$(guard_split_segments "cd ~ && git commit -m x")" "$STOP" "$T/start" "cd ~ -> HOME"

# 5c. the literal 2026-08-16 incident reproducer.
check_rc "$T/home/.claude/agent-tiers" "$(guard_split_segments "cd ~/.claude/agent-tiers && git commit -m x")" "$STOP" "$T/start" "incident reproducer (cd ~/.claude/agent-tiers)"

# 5d. quoted target.
check_rc "$T/a" "$(guard_split_segments "cd \"$T/a\" && git commit -m x")" "$STOP" "$T/start" "quoted cd target"

# 5e. chained cd composes relative to the running cwd, not the start cwd.
check_rc "$T/a/sub" "$(guard_split_segments "cd $T/a && cd sub && git commit -m x")" "$STOP" "$T/start" "chained relative cd"

# 5f. unresolvable target (does not exist) is REPORTED, never silently left at the running cwd -
#     T1.10, 2026-08-16: `mkdir X && cd X && git commit` has no X at PreToolUse time, and the old
#     "fall soft to the running cwd" made every commit guard scan the SESSION repo (three live false
#     denials). The answer is the `unresolved <raw target>` sentinel; guard_cwd_unresolved recognises
#     it, and a resolved answer (absolute path) is never mistaken for it.
command -v guard_cwd_unresolved >/dev/null 2>&1 || fail "guard_cwd_unresolved undefined after source"
check_rc "unresolved $T/does-not-exist" "$(guard_split_segments "cd $T/does-not-exist && git commit -m x")" "$STOP" "$T/start" "unresolvable cd -> unresolved sentinel"
check_rc "unresolved $T/does-not-exist" "$(guard_split_segments "mkdir $T/does-not-exist && cd $T/does-not-exist && git commit -m x")" "$STOP" "$T/start" "the T1.10 incident shape (mkdir X && cd X && git commit)"
guard_cwd_unresolved "$(guard_resolve_cwd "$(guard_split_segments "cd $T/does-not-exist && git commit -m x")" "$STOP" "$T/start")" || fail "guard_cwd_unresolved did not recognise the sentinel"
guard_cwd_unresolved "$(guard_resolve_cwd "$(guard_split_segments "cd $T/a && git commit -m x")" "$STOP" "$T/start")" && fail "guard_cwd_unresolved false-positive on a resolved absolute path"
# a chain that resolves and THEN hits a bad cd is unresolved as a whole (the sentinel names the bad hop)
check_rc "unresolved nope" "$(guard_split_segments "cd $T/a && cd nope && git commit -m x")" "$STOP" "$T/start" "good cd then bad cd -> unresolved"
# non-literal targets are the literal text `$VAR` - not a directory - so they surface as unresolved too
check_rc 'unresolved "$REPO"' "$(guard_split_segments 'cd "$REPO" && git commit -m x')" "$STOP" "$T/start" 'cd "$VAR" -> unresolved'
# `-C` into a missing dir on the commit segment itself: same class, same sentinel
check_rc "unresolved $T/does-not-exist" "$(guard_split_segments "git -C $T/does-not-exist commit -m x")" "$STOP" "$T/start" "-C into missing dir -> unresolved"
# a later ABSOLUTE hop recovers from an earlier bad one (`cd nope; git -C /kit commit` lands in /kit
# whatever nope was); a later RELATIVE hop does not (still unknown, and the FIRST bad target is cited)
check_rc "$T/b" "$(guard_split_segments "cd $T/nope && cd $T/b && git commit -m x")" "$STOP" "$T/start" "bad cd then absolute cd -> recovered"
check_rc "$T/b" "$(guard_split_segments "cd $T/nope && git -C $T/b commit -m x")" "$STOP" "$T/start" "bad cd then absolute -C -> recovered"
check_rc "unresolved $T/nope" "$(guard_split_segments "cd $T/nope && cd sub && git commit -m x")" "$STOP" "$T/start" "bad cd then relative cd -> still unresolved, first target cited"
# a cd that opened a GROUP which closes before the commit is scoped to that group - a real shell is
# back in the start cwd; the walk declines rather than fold it in (opus reviewer, wave A 2026-08-16,
# MEDIUM: pre-existing resolved-wrong answer). Group closing AT the commit segment (5h) still resolves.
check_rc "unresolved $T/a" "$(guard_split_segments "(cd $T/a && git pull) && git commit -m x")" "$STOP" "$T/start" "paren-cd whose group closes before the commit -> unresolved"
check_rc "unresolved $T/a" "$(guard_split_segments "echo hi && \$(cd $T/a && git log) ; git commit -m x")" "$STOP" "$T/start" "\$(cd ...) substitution closing before the commit -> unresolved"
check_rc "$T/b" "$(guard_split_segments "(cd $T/a && git pull) && cd $T/b && git commit -m x")" "$STOP" "$T/start" "group-closed cd then absolute cd -> recovered"
# a resolvable cd is still resolved (the fix must not turn every cd into a decline)
check_rc "$T/a" "$(guard_split_segments "mkdir -p $T/a && cd $T/a && git commit -m x")" "$STOP" "$T/start" "mkdir of an EXISTING dir then cd -> resolved"

# 5g. `cd -` is not tracked (no OLDPWD dance) - reported unresolved rather than silently left at the
#     running cwd; must never leak OLDPWD's stdout print into the result.
check_rc "unresolved -" "$(guard_split_segments "cd - && git commit -m x")" "$STOP" "$T/start" "cd - -> unresolved, not corrupted"

# 5h. subshell-wrapped `(cd X && git commit ...)` - the split does not break on bare parens, so this
#     arrives as one `(cd ...`-prefixed segment; must still be recognised as a cd.
check_rc "$T/b" "$(guard_split_segments "(cd $T/b && git commit -m x)")" "$STOP" "$T/start" "paren-wrapped cd"

# 5i. the walk stops at the FIRST stop_ere match - a `cd` appearing only because the guard's own
#     command-position splitter cut a quoted commit MESSAGE on its embedded `;` must never be read as
#     a real cd (the commit segment itself matches stop_ere first, so the walk never reaches it).
check_rc "$T/a" "$(guard_split_segments "cd $T/a && git commit -m \"hello; cd $T/b\"")" "$STOP" "$T/start" "stops at commit, ignores message-embedded cd"

# 6. CMDPOS_COMMIT_FRAG itself: DETECTION is now STRUCTURAL (any option-shaped token between `git`
#    and `commit`), not an enumerated list - opus advisor follow-up, 2026-08-16. Recognises `-C`,
#    `--git-dir=`, `--work-tree=`, `--paginate`, and anything else option-shaped; still does NOT
#    recognise a bare `-C` with no following `commit` (not a commit at all) or a `-C` path containing
#    whitespace (the path atom can't span a space - disclosed ceiling, see CMDPOS_COMMIT_FRAG's header).
printf '%s' "git -C /x commit -m y" | grep -aEq "^[[:space:]]*${CMDPOS_COMMIT_FRAG}" || fail "CMDPOS_COMMIT_FRAG missed 'git -C /x commit'"
printf '%s' "git commit -m y" | grep -aEq "^[[:space:]]*${CMDPOS_COMMIT_FRAG}" || fail "CMDPOS_COMMIT_FRAG regressed on a bare 'git commit'"
printf '%s' "git -C /x status" | grep -aEq "^[[:space:]]*${CMDPOS_COMMIT_FRAG}" && fail "CMDPOS_COMMIT_FRAG false-matched 'git -C /x status' (no commit)"
printf '%s' "git --git-dir=/x commit -m y" | grep -aEq "^[[:space:]]*${CMDPOS_COMMIT_FRAG}" || fail "CMDPOS_COMMIT_FRAG missed 'git --git-dir=/x commit' (detection is now structural - this should MATCH, even though resolution still doesn't follow it, see 6f)"
printf '%s' "git --work-tree=/x commit -m y" | grep -aEq "^[[:space:]]*${CMDPOS_COMMIT_FRAG}" || fail "CMDPOS_COMMIT_FRAG missed 'git --work-tree=/x commit'"
printf '%s' "git --paginate commit -m y" | grep -aEq "^[[:space:]]*${CMDPOS_COMMIT_FRAG}" || fail "CMDPOS_COMMIT_FRAG missed 'git --paginate commit' (an UNLISTED boolean flag - proves the generic branch generalizes, not just the enumerated ones)"

# 6a. a single `-C <path>` inside the commit segment resolves the target repo directly (no preceding cd).
check_rc "$T/a" "$(guard_split_segments "git -C $T/a commit -m x")" "$STOP" "$T/start" "single -C, no preceding cd"

# 6b. repeated `-C` composes left-to-right, each relative to the last (real git semantics).
check_rc "$T/a/sub" "$(guard_split_segments "git -C $T/a -C sub commit -m x")" "$STOP" "$T/start" "chained -C composes"

# 6c. a preceding `cd` AND a `-C` on the commit segment both apply, in order.
check_rc "$T/a/sub" "$(guard_split_segments "cd $T/a && git -C sub commit -m x")" "$STOP" "$T/start" "cd then -C composes"

# 6d. quoted `-C` target.
check_rc "$T/b" "$(guard_split_segments "git -C \"$T/b\" commit -m x")" "$STOP" "$T/start" "quoted -C target"

# 6e. paren-wrapped cd (5h's shape) COMPOSED with -C on the commit half: `(cd X && git -C sub
#     commit ...)` splits into `(cd X ` and ` git -C sub commit ...)` - the second segment has no
#     leading paren of its own. (Since 2026-08-16 the guards' own detector, guard_commit_seg(),
#     paren-strips too, so `( git commit )` as ONE bare segment IS recognised - section 8 below.)
check_rc "$T/b/sub" "$(guard_split_segments "(cd $T/b && git -C sub commit -m x)")" "$STOP" "$T/start" "paren-wrapped cd composed with -C"

# 6f. control: `--git-dir=` is now RECOGNISED (fires the guard, see the new 'is a commit' assert
#     above) but still NOT RESOLVED into cwd (disclosed ceiling, only -C moves cwd) - the resolver
#     falls back to start_cwd, same as if no cd/-C were present at all. Proves this is an honest gap,
#     not a silent mis-resolution to some OTHER wrong directory.
check_rc "$T/start" "$(guard_split_segments "git --git-dir=$T/a/.git commit -m x")" "$STOP" "$T/start" "--git-dir= recognised but not resolved (disclosed ceiling)"

# 6f2. `-C`/`-c`/`--no-pager` combined in one segment: `-C` resolves, the others are recognised
#      (fire the guard) but need no resolution of their own (they don't move cwd).
check_rc "$T/a" "$(guard_split_segments "git -C $T/a -c core.quotePath=false --no-pager commit -m x")" "$STOP" "$T/start" "-C resolves alongside recognised-but-inert -c/--no-pager"

# 6g. CRITICAL falsifier (opus reviewer, 2026-08-16): a `-C` appearing AFTER the commit verb - inside
#     the commit MESSAGE text, or in git's own `--amend -C <commit>` (--reuse-message) flag - must
#     NOT be read as a cd target. The first draft of the -C extraction scanned the WHOLE segment
#     instead of truncating to the matched git-through-commit span, so `-C /tmp` typed into a `-m`
#     string silently redirected every guard to /tmp; this is the falsifier that would have caught it.
check_rc "$T/start" "$(guard_split_segments "git commit -m \"see -C $T/b for scripted runs\"")" "$STOP" "$T/start" "message-embedded -C is NOT read as a cd target"
check_rc "$T/start" "$(guard_split_segments "git commit --amend -C HEAD")" "$STOP" "$T/start" "--amend -C HEAD (git's --reuse-message) is NOT read as a cd target"

# 6g2. A ref genuinely named "commit" after `--amend -C` (contrived but syntactically real) - proves
#     the token-scan truncation stops at the FIRST literal "commit" (the real verb), not a later one.
#     $T/start/commit exists in the sandbox specifically so this is a REAL falsifier (a truncation bug
#     would resolve here, not silently match the unchanged expectation for the wrong reason - the same
#     vacuous-test trap already caught once tonight on the plain --amend -C HEAD case above). NOTE:
#     this does NOT demonstrate a regex-based truncation would have failed here - mutation-tested
#     against the actual sed/grep on this host (opus reviewer, 2026-08-16), it did not, and the
#     swallow this test was originally written to falsify is structurally impossible with
#     CMDPOS_GITOPTS's grammar (see guard_resolve_cwd's header). Kept as a regression pin on the
#     token-scan's own, differently-shaped ceiling (guard-cmdpos.sh's header names it).
check_rc "$T/start" "$(guard_split_segments "git commit --amend -C commit")" "$STOP" "$T/start" "--amend -C commit resolves to the real verb, not a later 'commit' token"

# 6h. `-c <key>=<val>` / `--no-pager` / `--no-optional-locks` are recognised (guard fires) but need no
#     cwd handling - unlike `-C` they don't move cwd, so the resolved cwd stays start_cwd absent an
#     actual cd/-C elsewhere in the command.
printf '%s' "git -c core.quotePath=false commit -m x" | grep -aEq "^[[:space:]]*${CMDPOS_COMMIT_FRAG}" || fail "CMDPOS_COMMIT_FRAG missed 'git -c core.quotePath=false commit'"
printf '%s' "git --no-pager commit -m x" | grep -aEq "^[[:space:]]*${CMDPOS_COMMIT_FRAG}" || fail "CMDPOS_COMMIT_FRAG missed 'git --no-pager commit'"
check_rc "$T/a" "$(guard_split_segments "cd $T/a && git -c core.quotePath=false commit -m x")" "$STOP" "$T/start" "-c recognised, cd still resolved, -c itself does not move cwd"

# 7. guard_unresolved_repo_flag / guard_repo_flag_values (2026-08-16, gap-closure wave 4): the shared
#    detection used by hygiene-commit-guard.sh's unconditional deny, kit-leak-guard.sh's conditional
#    deny, and vcs/review-gate-guard.sh's decline-to-scan.
command -v guard_unresolved_repo_flag >/dev/null 2>&1 || fail "guard_unresolved_repo_flag undefined after source"
command -v guard_repo_flag_values >/dev/null 2>&1 || fail "guard_repo_flag_values undefined after source"

# 7a. CRITICAL falsifier (opus advisor, 2026-08-16): a commit MESSAGE merely containing the text
#     "--git-dir" must NOT match - the ORIGINAL breadcrumb code (a raw substring grep over the whole
#     segment, not the bounded optspan) had exactly this bug; this is the shape that would have made
#     the deny escalation a wrong-deny generator if built on top of it unfixed.
guard_unresolved_repo_flag 'git commit -m "use --git-dir here"' && fail "guard_unresolved_repo_flag false-matched message text containing --git-dir"
guard_unresolved_repo_flag 'git commit -m "see --work-tree docs"' && fail "guard_unresolved_repo_flag false-matched message text containing --work-tree"

# 7b. real flags, both forms, both names - must match.
guard_unresolved_repo_flag 'git --git-dir=/x commit -m y' || fail "guard_unresolved_repo_flag missed attached --git-dir="
guard_unresolved_repo_flag 'git --git-dir /x commit -m y' || fail "guard_unresolved_repo_flag missed separated --git-dir"
guard_unresolved_repo_flag 'git --work-tree=/x commit -m y' || fail "guard_unresolved_repo_flag missed attached --work-tree="
guard_unresolved_repo_flag 'git --work-tree /x commit -m y' || fail "guard_unresolved_repo_flag missed separated --work-tree"

# 7c. -C alone (already resolved elsewhere) and other recognised-but-inert flags must NOT trip this -
#     it is specifically the repo-SELECTING pair, not "any unresolved GITOPTS flag".
guard_unresolved_repo_flag 'git -C /x commit -m y' && fail "guard_unresolved_repo_flag false-matched plain -C (already resolved by guard_resolve_cwd, not this check's job)"
guard_unresolved_repo_flag 'git -c core.quotePath=false commit -m y' && fail "guard_unresolved_repo_flag false-matched -c (does not select a repo)"
guard_unresolved_repo_flag 'git --no-pager commit -m y' && fail "guard_unresolved_repo_flag false-matched --no-pager"

# 7d. value extraction, both forms, both names, multiple in one segment.
GOT="$(guard_repo_flag_values 'git --git-dir=/x/.git --work-tree=/x commit -m y' | tr '\n' ' ')"
[ "$GOT" = "/x/.git /x " ] || fail "guard_repo_flag_values (attached) got: $GOT"
GOT="$(guard_repo_flag_values 'git --git-dir /x/.git --work-tree /x commit -m y' | tr '\n' ' ')"
[ "$GOT" = "/x/.git /x " ] || fail "guard_repo_flag_values (separated) got: $GOT"
GOT="$(guard_repo_flag_values 'git -C /x commit -m y')"
[ -z "$GOT" ] || fail "guard_repo_flag_values extracted a value with no --git-dir/--work-tree present: $GOT"

# 8. guard_commit_seg (2026-08-16, Tier 1 review T1.2): the shared commit-segment detector, replacing
#    four hand-copied `^[[:space:]]*${CMDPOS_COMMIT_FRAG}` greps that saw NO wrapper at all. Measured
#    silent before the fix (real PreToolUse payloads into review-gate-guard.sh): sudo, nohup, /usr/bin/,
#    ( ), { }, if-then. Mutation-tested 2026-08-16 (each reverted alone, section fails on the named
#    case): narrow `^[[:space:]]*` anchor -> sudo misses; no paren strip -> `( git commit )` misses;
#    old `(\./)?` prefix -> /usr/bin/git misses; resolver stop leg unstripped -> 8d resolves to $T/b.
command -v guard_commit_seg >/dev/null 2>&1 || fail "guard_commit_seg undefined after source"
must_fire() { # $1=command  (whole command line, split here exactly as the guards do)
  got="$(guard_commit_seg "$(guard_split_segments "$1")")"
  [ -n "$got" ] || fail "guard_commit_seg MISSED a real commit: $1"
  printf 'ok   [fires] %s\n' "$1"
}
must_not_fire() {
  got="$(guard_commit_seg "$(guard_split_segments "$1")")"
  [ -z "$got" ] || fail "guard_commit_seg FALSE-MATCHED (guard would ask on a non-commit): $1 -> $got"
  printf 'ok   [silent] %s\n' "$1"
}
# 8a. must-fire: the bare form, -C, and the seven measured-silent wrapper shapes.
must_fire 'git commit -m x'
must_fire 'git -C /tmp/repo commit -m x'
must_fire 'sudo git commit -m x'
must_fire 'nohup git commit -m x'
must_fire '/usr/bin/git commit -m x'
must_fire '( git commit -m x )'
must_fire '{ git commit -m x; }'
must_fire 'if true; then git commit -m x; fi'
must_fire 'cd /tmp && sudo git commit -m x'
must_fire 'echo hi && $(git commit -m x)'
# 8b. must-not-fire: the failure mode of an over-broad fix is a guard that asks on `echo`.
must_not_fire 'git commit-tree abc'
must_not_fire 'echo git commit is a thing'
must_not_fire 'grep -r "git commit" .'
must_not_fire 'git status'
must_not_fire 'X=/usr/bin/git commit'
must_not_fire 'echo /usr/bin/git commit -m x'
must_not_fire 'bash -c "git commit -m x"'   # disclosed ceiling (quoted-string wrapper): documents that it is silent, not a bypass claim
# 8c. returns the ORIGINAL segment text (callers re-parse/log it), not the stripped form.
[ "$(guard_commit_seg "$(guard_split_segments '( git commit -m x )')")" = '( git commit -m x )' ] || fail "guard_commit_seg did not return the original segment text"
# 8d. resolver: a `( git commit )` stop segment is recognised (walk stops there), so a `cd` AFTER it
#     is not folded in - before the fix the stop leg had no paren strip and walked past it.
check_rc "$T/a" "$(guard_split_segments "cd $T/a && ( git commit -m x ) && cd $T/b")" "$STOP" "$T/start" "paren-wrapped commit stops the walk (cd after it ignored)"
# 8f. guard_git_add_segs (opus reviewer, 2026-08-16): the add legs in hygiene/vcs used the same narrow
#     anchor, so `(git add . && git commit -m x)` fired the commit half and blinded the add half.
command -v guard_git_add_segs >/dev/null 2>&1 || fail "guard_git_add_segs undefined after source"
[ "$(guard_git_add_segs "$(guard_split_segments '(git add . && git commit -m x)')")" = '(git add . ' ] || fail "guard_git_add_segs missed a paren-wrapped git add"
[ "$(guard_git_add_segs "$(guard_split_segments 'sudo git add -A; git commit -m x')")" = 'sudo git add -A' ] || fail "guard_git_add_segs missed sudo git add"
[ "$(guard_git_add_segs "$(guard_split_segments 'git add a && git add b && git commit')" | wc -l)" -eq 2 ] || fail "guard_git_add_segs should return EVERY add segment"
[ -z "$(guard_git_add_segs "$(guard_split_segments 'echo git add . && git commit -m x')")" ] || fail "guard_git_add_segs false-matched an argument"
[ -z "$(guard_git_add_segs "$(guard_split_segments 'git commit -m x')")" ] || fail "guard_git_add_segs matched with no add present"
# 8g. flat-cost contract: many segments, none a commit, still exactly one answer (empty) - and a
#     commit at segment 140 of 150 is found with its ORIGINAL text (140, not 40: a substring match on
#     the line-number list would return segment 40 - mutation-tested, it does).
MANY="$(i=0; while [ $i -lt 150 ]; do i=$((i+1)); if [ $i -eq 140 ]; then printf ' ( git commit -m x ) && '; else printf 'echo %s && ' $i; fi; done; printf 'true')"
[ "$(guard_commit_seg "$(guard_split_segments "$MANY")")" = '  ( git commit -m x ) ' ] || fail "guard_commit_seg lost a commit deep in a long chain (got: $(guard_commit_seg "$(guard_split_segments "$MANY")"))"

# 8h. guard_norm_add_paths (macOS CI, 2026-08-16): the shared token normaliser that replaced three
#     inline `case`-in-`$( )` loops bash 3.2 could not parse.
command -v guard_norm_add_paths >/dev/null 2>&1 || fail "guard_norm_add_paths undefined after source"
GOT="$(printf '%s\n' '"a b.md"' "'c.md'" './d.md' '/abs/e.md' 'f.md' | guard_norm_add_paths 'sub/' | tr '\n' '|')"
[ "$GOT" = 'sub/a b.md|sub/c.md|sub/d.md|/abs/e.md|sub/f.md|' ] || fail "guard_norm_add_paths got: $GOT"

# 8e. widened path prefix: dangerous-actions-blocker's own matcher now sees a path-prefixed binary.
guard_at_command_position '/bin/rm --no-preserve-root -rf /' 'rm\b' || fail "cmdpos missed a path-prefixed binary (/bin/rm)"
guard_at_command_position 'echo /bin/rm -rf /' 'rm\b' && fail "cmdpos matched a path-prefixed binary inside an argument"

HOME="$HOME_SAVE"

# 9. guard_caller_agent / guard_ask_decision / guard_ask_prefix (2026-08-27): the subagent-aware
#    extension to the ask/deny seam - review-gate-guard.sh, vcs-commit-guard.sh, kit-leak-guard.sh all
#    convert through this ONE place. guard_unattended/guard_ask_decision had NO prior selfcheck coverage
#    anywhere in this kit (grepped clean before this wave, despite 3 live consumers) - covered here
#    alongside the new functions since this wave touches guard_ask_decision's own body.
command -v guard_caller_agent >/dev/null 2>&1 || fail "guard_caller_agent undefined after source"
command -v guard_ask_prefix >/dev/null 2>&1 || fail "guard_ask_prefix undefined after source"

# 9a. guard_caller_agent: with an agent_id present, returns .agent_type (charset-stripped when
#     unusable, `subagent` when that leaves nothing); empty with no agent_id and on unparsable input.
[ "$(guard_caller_agent '{"agent_type":"worker","agent_id":"a0test"}')" = "worker" ] || fail "guard_caller_agent missed a real agent_type"
[ -z "$(guard_caller_agent '{"session_id":"abc"}')" ] || fail "guard_caller_agent should be empty with no agent_type field"
[ -z "$(guard_caller_agent '{"agent_type":"bad; rm -rf /"}')" ] || fail "guard_caller_agent did not strip an unusable agent_type"
[ "$(guard_caller_agent '{"agent_type":"bad; rm -rf /","agent_id":"a0test"}')" = "subagent" ] || fail "guard_caller_agent: an unusable agent_type on a subagent must still read as a subagent"
[ -z "$(guard_caller_agent 'not json')" ] || fail "guard_caller_agent should be empty on unparsable input, not fail closed"
# Fail-direction regression (opus reviewer, 2026-08-27, MEDIUM): a future CLI convention stamping the
# Lead's own payload with "main"/"MAIN" must not fail CLOSED (every ask-class guard hard-denying every
# Lead commit) - normalised to "no agent", same sentinel authorship-record.sh/numeric-claim-ledger.sh
# already use the other direction (`.agent_type // "MAIN"`).
[ -z "$(guard_caller_agent '{"agent_type":"main"}')" ] || fail "guard_caller_agent should treat main as no-agent (fail-open direction)"
[ -z "$(guard_caller_agent '{"agent_type":"MAIN"}')" ] || fail "guard_caller_agent should treat MAIN as no-agent (fail-open direction)"

# 9a2. agent_id is the subagent test (2026-10-14, probed: a `--agent <name>` MAIN session sends
#      agent_type without agent_id; only a subagent sends both).
[ -z "$(guard_caller_agent '{"agent_type":"probeagent"}')" ] || fail "guard_caller_agent: agent_type without agent_id is the Lead (a --agent main session), must be empty"
[ "$(guard_caller_agent '{"agent_type":"worker","agent_id":"a1b2c3"}')" = "worker" ] || fail "guard_caller_agent: agent_id with agent_type worker must return worker"
[ "$(guard_caller_agent '{"agent_id":"a1b2c3"}')" = "subagent" ] || fail "guard_caller_agent: agent_id alone must return subagent"
# 9a3. plugin-namespaced types: the part after the LAST colon is the name.
[ "$(guard_caller_agent '{"agent_type":"agent-tiers:sublead","agent_id":"a1b2"}')" = "sublead" ] || fail "guard_caller_agent: agent-tiers:sublead must read as sublead"
[ "$(guard_caller_agent '{"agent_type":"caveman:cavecrew-builder","agent_id":"a1b2"}')" = "cavecrew-builder" ] || fail "guard_caller_agent: caveman:cavecrew-builder must read as cavecrew-builder"
[ -z "$(guard_caller_agent '{"agent_type":"agent-tiers:sublead"}')" ] || fail "guard_caller_agent: namespaced type without agent_id is the Lead"
[ "$(guard_caller_agent '{"agent_type":"x:main","agent_id":"a1b2"}')" = "subagent" ] || fail "guard_caller_agent: x:main with agent_id must read as subagent"
[ "$(guard_caller_agent '{"agent_type":"agent-tiers:","agent_id":"a1b2"}')" = "subagent" ] || fail "guard_caller_agent: trailing colon must read as subagent"

# 9b. guard_ask_decision: unchanged single-arg behaviour (attended/unattended, regression-pinned since
#     it never had coverage) plus the new second arg (agent present -> deny regardless of attended state).
# guard_state_dir() appends /.state to an override unless it already ends in one (unattended-guard.
# selfcheck.sh's own convention) - name it accordingly, or the marker below lands one level off.
AGENT_TIERS_STATE_DIR="$T/.state"; export AGENT_TIERS_STATE_DIR
mkdir -p "$AGENT_TIERS_STATE_DIR" || fail "cannot build unattended sandbox"
[ "$(guard_ask_decision "notflagged")" = "ask" ] || fail "guard_ask_decision: attended session, no agent -> should ask"
: > "$AGENT_TIERS_STATE_DIR/unattended.flagged" || fail "cannot write unattended marker"
[ "$(guard_ask_decision "flagged")" = "deny" ] || fail "guard_ask_decision: unattended session -> should deny (pre-existing behaviour, regression pin)"
[ "$(guard_ask_decision "notflagged" "worker")" = "deny" ] || fail "guard_ask_decision: subagent caller -> should deny even when attended"
[ "$(guard_ask_decision "notflagged" "")" = "ask" ] || fail "guard_ask_decision: empty agent_type arg must behave like no agent"
rm -f "$AGENT_TIERS_STATE_DIR/unattended.flagged"

# 9c. guard_ask_prefix: subagent wording takes priority over unattended when both are true; empty when
#     the decision would be a plain ask (so callers can prepend it unconditionally).
[ -z "$(guard_ask_prefix "notflagged" "")" ] || fail "guard_ask_prefix should be empty for a plain ask"
[ "$(guard_ask_prefix "notflagged" "worker")" = "$GUARD_SUBAGENT_PREFIX" ] || fail "guard_ask_prefix did not return the subagent prefix for a subagent caller"
: > "$AGENT_TIERS_STATE_DIR/unattended.flagged" || fail "cannot write unattended marker (2)"
[ "$(guard_ask_prefix "flagged" "")" = "$GUARD_UNATTENDED_PREFIX" ] || fail "guard_ask_prefix did not return the unattended prefix"
[ "$(guard_ask_prefix "flagged" "worker")" = "$GUARD_SUBAGENT_PREFIX" ] || fail "guard_ask_prefix should prefer the subagent prefix when both unattended and subagent are true"
rm -f "$AGENT_TIERS_STATE_DIR/unattended.flagged"
unset AGENT_TIERS_STATE_DIR

# 9d. guard_marker_text (2026-09-14, guard-ask-deny rule): lifted from sc52a-write-disclosure-guard.sh's
#     own `[bash-write:]` extraction so kit-leak-guard.sh's `[leak-exception:]` and vcs-commit-guard.sh's
#     `[vcs-exception:]` share one implementation. Absent, present, multi-line-flattened, over-140-capped,
#     and per-tag (one guard's tag never matches another's marker text).
command -v guard_marker_text >/dev/null 2>&1 || fail "guard_marker_text undefined after source"
[ -z "$(guard_marker_text "git commit -m x" bash-write)" ] || fail "guard_marker_text: absent tag must be empty"
[ "$(guard_marker_text "git commit -m x [bash-write:bulk rename]" bash-write)" = "bulk rename" ] || fail "guard_marker_text: did not extract a present marker's text"
[ -z "$(guard_marker_text "git commit -m x [leak-exception:not this tag]" bash-write)" ] || fail "guard_marker_text: a DIFFERENT tag's marker must not match"
# A multi-line COMMAND (e.g. a heredoc) where TWO separate lines each carry their own [bash-write:]
# fragment: sed prints once per MATCHING line (not once overall), so an unflattened result would carry
# an embedded newline straight into guards.log - a second, unprefixed, model-controlled log line. tr
# joins those into one space-separated line instead.
ML="$(printf 'echo [bash-write:first]\necho [bash-write:second]')"
[ "$(guard_marker_text "$ML" bash-write)" = "first second" ] || fail "guard_marker_text: two matching lines must be newline-flattened into one space-joined line, got: $(guard_marker_text "$ML" bash-write)"
LONG_REASON="$(printf 'a%.0s' $(seq 1 200))"
GOT="$(guard_marker_text "git commit -m x [bash-write:$LONG_REASON]" bash-write)"
[ "${#GOT}" -eq 140 ] || fail "guard_marker_text: a >140-char reason must be capped at 140 chars, got length ${#GOT}"
# 2026-09-14 (adversarial review, MEDIUM): the marker's mandated PLACEMENT is a trailing shell comment
# (`# [tag:...]`), never a bare trailing word (git reads a bare word as a pathspec; on sed/tee it becomes
# an extra file argument or a stray file) - confirm the helper finds it there exactly the same as a bare
# marker, since it reads raw command text and does not care where `#` falls.
[ "$(guard_marker_text 'git commit -m "test"  # [vcs-exception:RESUME_SESSION.md, kept on purpose]' vcs-exception)" = "RESUME_SESSION.md, kept on purpose" ] \
  || fail "guard_marker_text: did not find a marker placed in a trailing shell comment"
printf 'ok   guard_marker_text: absent/present/multi-line-flattened/140-capped/per-tag/trailing-comment-placement all hold\n'

# 2026-08-23: the two parameters the force-push consumer added - verb (which word bounds the pre-verb
# option span) and nth (stop at the Nth matching segment, not the first). Pinned here because the
# shared seam owns its own regressions; before nth existed, every match after the first silently got
# the FIRST match's directory.
PFRAG="git[[:space:]]+(${CMDPOS_GITOPTS})*push([[:space:]]|$)"
V="$T/verbtest"; mkdir -p "$V/sub" || fail "cannot build verb sandbox"
got="$(guard_resolve_cwd "$(guard_split_segments "git -C $V/sub push -f")" "$PFRAG" "$V" push)"
[ "$got" = "$V/sub" ] || fail "verb=push did not fold the push segment's own -C (got $got)"
printf 'ok   [%s] verb=push folds the push segment -C\n' "$got"
got="$(guard_resolve_cwd "$(guard_split_segments "git push -f origin -C $V/sub")" "$PFRAG" "$V" push)"
[ "$got" = "$V" ] || fail "verb=push folded a -C sitting AFTER the verb (got $got)"
printf 'ok   [%s] verb=push ignores a post-verb -C (the default verb would fold it)\n' "$got"
segs="$(guard_split_segments "git push origin x && cd $V/sub && git push -f")"
got="$(guard_resolve_cwd "$segs" "$PFRAG" "$V" push 2)"
[ "$got" = "$V/sub" ] || fail "nth=2 did not resolve the SECOND matching segment (got $got)"
printf 'ok   [%s] nth=2 resolves the second matching segment\n' "$got"
got="$(guard_resolve_cwd "$segs" "$PFRAG" "$V" push)"
[ "$got" = "$V" ] || fail "nth default stopped somewhere other than the first match (got $got)"
printf 'ok   [%s] nth default stops at the first match\n' "$got"

# 2026-09-23 (guards-review fix pass): guard_strip_heredocs - the harness's own default commit
# shape (git commit -m "$(cat <<'EOF' ... EOF)") must keep the opening line intact and drop the body.
SQ="'"
NL='
'
HD1="git commit -m \"\$(cat <<${SQ}EOF${SQ}${NL}hello world${NL}EOF${NL})\""
EXP1="git commit -m \"\$(cat <<${SQ}EOF${SQ}${NL})\""
GOT="$(guard_strip_heredocs "$HD1")"
[ "$GOT" = "$EXP1" ] || fail "guard_strip_heredocs: default commit-message shape not stripped as expected: [$GOT]"
printf 'ok   guard_strip_heredocs: default commit-message heredoc opener kept, body dropped\n'

# nested $( ) around the heredoc - the strip is purely line-oriented, nesting depth does not matter.
# Exact-output pinned, not just a negative grep (a negative-only assertion passes if the function
# returned NOTHING at all, guards-review-2 point 11) - the opener line must still be there verbatim.
HD2="echo \"\$(echo \"\$(cat <<${SQ}X${SQ}${NL}inner${NL}X${NL})\")\""
EXP2="echo \"\$(echo \"\$(cat <<${SQ}X${SQ}${NL})\")\""
GOT2="$(guard_strip_heredocs "$HD2")"
[ "$GOT2" = "$EXP2" ] || fail "guard_strip_heredocs: nested \$( ) shape not stripped as expected: [$GOT2]"
printf 'ok   guard_strip_heredocs: nested $( ) heredoc body stripped, opener line pinned exactly\n'

# two heredocs in one command - both bodies stripped, the scan resumes after the first closes.
# Exact-output pinned (same reason as HD2 above).
HD3="cat <<${SQ}A${SQ}${NL}first${NL}A${NL}cat <<${SQ}B${SQ}${NL}second${NL}B"
EXP3="cat <<${SQ}A${SQ}${NL}cat <<${SQ}B${SQ}"
GOT3="$(guard_strip_heredocs "$HD3")"
[ "$GOT3" = "$EXP3" ] || fail "guard_strip_heredocs: two-heredoc shape not stripped as expected: [$GOT3]"
printf 'ok   guard_strip_heredocs: two heredocs in one command both stripped, output pinned exactly\n'

# guard_split_segments_qsafe - the fix for guards-review-2's claim 5/finding: guard_split_segments
# is quote-BLIND and slices a one-line commit message containing its own ';'/'&&' mid-string; the
# qsafe variant must keep that whole thing as ONE segment.
QS_CMD="git commit -m \"docs: WIP; git stash is shared\""
BLIND_N="$(guard_split_segments "$QS_CMD" | wc -l | tr -d ' ')"
[ "$BLIND_N" -eq 2 ] || fail "guard_split_segments: expected the quote-blind splitter to still slice this at 2 lines (baseline for the qsafe contrast), got $BLIND_N"
SAFE_N="$(guard_split_segments_qsafe "$QS_CMD" | wc -l | tr -d ' ')"
[ "$SAFE_N" -eq 1 ] || fail "guard_split_segments_qsafe: a ';' inside a quoted string must not split, got $SAFE_N lines"
[ "$(guard_split_segments_qsafe "$QS_CMD")" = "$QS_CMD" ] || fail "guard_split_segments_qsafe: real segment text must stay unquoted-unchanged"
printf 'ok   guard_split_segments_qsafe: quoted ; does not split, real text kept intact (contrast: quote-blind splitter gets it wrong)\n'
# every OTHER separator still splits, same contract as guard_split_segments, just quote-aware.
[ "$(guard_split_segments_qsafe 'a && b' | wc -l)" -eq 2 ] || fail "guard_split_segments_qsafe: unquoted && did not split"
[ "$(guard_split_segments_qsafe 'a | b'  | wc -l)" -eq 2 ] || fail "guard_split_segments_qsafe: unquoted | did not split"
[ "$(guard_split_segments_qsafe 'git commit -m x' | wc -l)" -eq 1 ] || fail "guard_split_segments_qsafe: single segment lost its trailing newline"
printf 'ok   guard_split_segments_qsafe: unquoted separators still split, single segment keeps trailing newline\n'

# unterminated heredoc - left entirely as-is (never a partial strip).
HD4="cat <<${SQ}NEVER${SQ}${NL}still going"
GOT4="$(guard_strip_heredocs "$HD4")"
[ "$GOT4" = "$HD4" ] || fail "guard_strip_heredocs: unterminated heredoc was altered instead of left as-is"
printf 'ok   guard_strip_heredocs: unterminated heredoc left as-is\n'

# guard_strip_quotes - quote characters survive, content between them does not; unquoted text is untouched.
GQ="$(guard_strip_quotes "git commit -m \"fix: a -> b | c <x@y>\" --author=${SQ}A <a@b>${SQ}")"
printf '%s' "$GQ" | grep -aq -- '->' && fail "guard_strip_quotes: quoted content leaked through (->)"
printf '%s' "$GQ" | grep -aq '<x@y>' && fail "guard_strip_quotes: quoted content leaked through (email)"
[ "$GQ" = "git commit -m \"\" --author=${SQ}${SQ}" ] \
  || fail "guard_strip_quotes: unquoted structure not preserved: [$GQ]"
printf 'ok   guard_strip_quotes: quote chars kept, content blanked, unquoted text untouched\n'

# --- 2026-10-14 fix pass: qsafe splitter (backslash, redirect ampersands),
# quote-aware heredoc openers, guard_argv. One assertion per case; every case below was probed wrong
# against the previous library unless its comment says it is a regression pin.
RS_B="$(printf '\036')"
qn() { guard_split_segments_qsafe "$1" | wc -l | tr -d ' '; }
# A raw newline is a boundary even inside quotes (see the qsafe header for why the RS encoding was dropped).
[ "$(qn "ssh vps 'ls${NL}cat x'; ls")" -eq 3 ] || fail "qsafe: a newline inside quotes must still be a segment boundary (want 3 segments)"
[ "$(qn 'ssh vps ls \; rm x')" -eq 1 ] || fail "qsafe: an escaped ; must not split"
[ "$(qn 'cat x 2>&1')" -eq 1 ] || fail "qsafe: 2>&1 must not split"
[ "$(qn 'echo x >&2')" -eq 1 ] || fail "qsafe: >&2 must not split"
[ "$(qn 'cmd &> f')" -eq 1 ] || fail "qsafe: &> must not split"
[ "$(qn 'a >| f')" -eq 1 ] || fail "qsafe: >| must not split"
[ "$(qn 'a |& b')" -eq 2 ] || fail "qsafe: |& must be ONE separator (2 segments)"
printf 'ok   guard_split_segments_qsafe: newline always a boundary, escaped ;, redirect ampersands, >|, |&\n'

GOT="$(guard_strip_heredocs "echo \"x <<EOF\"${NL}ssh vps rm x${NL}EOF")"
case "$GOT" in *"ssh vps rm x"*) true ;; *) false ;; esac || fail "guard_strip_heredocs: a quoted <<EOF is not an opener, the ssh line must survive: [$GOT]"
GOT="$(guard_strip_heredocs "cat <<< EOF${NL}ssh vps rm x${NL}EOF")"
case "$GOT" in *"ssh vps rm x"*) true ;; *) false ;; esac || fail "guard_strip_heredocs: a herestring <<< is not an opener, the ssh line must survive: [$GOT]"
[ "$(guard_strip_heredocs "$HD1")" = "$EXP1" ] || fail "guard_strip_heredocs: default commit shape regressed under quote-aware openers (regression pin)"
printf 'ok   guard_strip_heredocs: quoted << and herestring are not openers; default commit shape still strips\n'

# 2026-10-18: the delimiter is the WHOLE shell word after quote removal (hd_word). Bypass shape per
# form: opener, a body line, the shell's real closer, a real command, then a line equal to the first
# chunk only (where the old regex ended the body, hiding the real command). Exact output pinned.
TAB="$(printf '\t')"
hd_case() { # $1=opener word $2=shell closer line $3=fake closer
  got="$(guard_strip_heredocs "cat <<$1${NL}bodytext${NL}$2${NL}ssh vps rm x${NL}$3")"
  [ "$got" = "cat <<$1${NL}ssh vps rm x${NL}$3" ] || fail "guard_strip_heredocs: delimiter <<$1 (closer [$2]) must drop the body and keep the real command: [$got]"
}
hd_case 'E"F"' EF E
hd_case '"E"F' EF E
hd_case 'E\F' EF E
hd_case '\EOF' EOF E
hd_case "${SQ}E${SQ}\"F\"G" EFG E
hd_case '-"E"F' "${TAB}EF" E
printf 'ok   guard_strip_heredocs: E"F", "E"F, E\\F, \\EOF, '"'"'E'"'"'"F"G, -"E"F (tab closer) read as the whole word\n'
# refused words keep today's result: not an opener, every line scanned as a command.
HD5="cat <<\$X${NL}ssh vps rm x${NL}\$X"
[ "$(guard_strip_heredocs "$HD5")" = "$HD5" ] || fail "guard_strip_heredocs: <<\$X must stay a non-opener (input unchanged)"
HD6="cat <<\"EF${NL}ssh vps rm x${NL}EF"
[ "$(guard_strip_heredocs "$HD6")" = "$HD6" ] || fail "guard_strip_heredocs: <<\"EF (unterminated quote) must stay a non-opener (input unchanged)"
printf 'ok   guard_strip_heredocs: <<$X and an unterminated <<"EF stay non-openers (regression pin)\n'
# a delimiter starting with a digit is refused: $((1<<2)) is a shift, and a later line `2` must not
# swallow the command between them as a heredoc body.
HD7="x=\$((1<<2))${NL}ssh vps rm x${NL}2"
[ "$(guard_strip_heredocs "$HD7")" = "$HD7" ] || fail "guard_strip_heredocs: \$((1<<2)) must not open a heredoc (input unchanged)"
printf 'ok   guard_strip_heredocs: $((1<<2)) is not a heredoc opener\n'
# guard_strip_quotes: a 0x1A byte inside quotes is content, not a record break.
SUB="$(printf '\032')"
GQ="$(guard_strip_quotes "echo \"a${SUB} | rm x\"")"
case "$GQ" in *'| rm x'*) fail "guard_strip_quotes: a 0x1A byte ended the quoted region: [$GQ]" ;; esac
[ "$GQ" = 'echo ""' ] || fail "guard_strip_quotes: 0x1A inside quotes not blanked as content: [$GQ]"
printf 'ok   guard_strip_quotes: a 0x1A byte inside quotes stays quoted content\n'

argv_is() { # $1=segment $2=expected tokens joined by |, RS shown as ~
  got="$(guard_argv "$1" | tr "${RS_B}" '~' | tr '\n' '|')"
  [ "$got" = "$2" ] || fail "guard_argv [$1]: want [$2] got [$got]"
}
command -v guard_argv >/dev/null 2>&1 || fail "guard_argv undefined after source"
argv_is "ssh vps 'ls /x'" 'wssh|wvps|wls /x|'
argv_is 's\sh vps' 'wssh|wvps|'
argv_is 'ssh "$h" uptime' 'wssh|o$h|wuptime|'
argv_is '> /dev/null ssh vps x' 'r> /dev/null|wssh|wvps|wx|'
argv_is 'cat x 2>&1' 'wcat|wx|r2>& 1|'
argv_is '(ssh vps)' 'g(|wssh|wvps|g)|'
argv_is 'f(){ ssh x; }' 'wf|g(|g)|g{|wssh|wx|g;|g}|'
argv_is 'echo $(ssh vps hostname)' 'wecho|o$(ssh vps hostname)|'
argv_is 'diff <(ssh a cat x) y' 'wdiff|o<(ssh a cat x)|wy|'
argv_is "echo 'unclosed" 'wecho|wunclosed|u|'
argv_is "\$'a\\nb'" "o\$'a\\nb'|"
argv_is "echo \"a${NL}b\" 2>\"\$log\"" 'wecho|wa~b|R2> $log|'
printf 'ok   guard_argv: w/o/g/r/R/u tokens on the contract cases\n'

# 2026-10-14 review round: comment apostrophes, unbalanced quotes, 0x1A, glob/brace/tilde opacity.
[ "$(qn "# it's gone${NL}git worktree remove x")" -eq 2 ] || fail "qsafe: an apostrophe in a # comment must not merge the next line (want 2 segments)"
[ "$(guard_split_segments_qsafe "echo 'oops${NL}git add -A" | sed -n 2p)" = "git add -A" ] || fail "qsafe: after an unbalanced quote, a later line must be its own segment"
# Review round 2 (claim adjudication): quote mis-tracks that balance out, mid-word `#`, comment after a
# line continuation - each merged a real later command into an earlier segment under the RS encoding.
[ "$(guard_split_segments_qsafe "echo \"\$(printf \"it's\")\"${NL}git add -A${NL}# it's" | sed -n 2p)" = "git add -A" ] || fail "qsafe: a balanced-out quote mis-track must not merge the next line"
[ "$(qn 'echo $(echo x)#; git add -A')" -eq 2 ] || fail "qsafe: a mid-word # is not a comment (want 2 segments)"
[ "$(guard_split_segments_qsafe "true \\${NL}# it's${NL}git add -A${NL}# it's" | sed -n 2p)" = "git add -A" ] || fail "qsafe: a comment after a line continuation must not merge the next line"
SUB_B="$(printf '\032')"
[ "$(qn "echo '${SUB_B};x'; y")" -eq 2 ] || fail "qsafe: a 0x1A byte inside quotes must not reset quote state (want 2 segments)"
# RGP2-K: comment awareness. A backslash in a comment is literal, so its newline still ends the segment.
[ "$(qn "ls # a\\${NL}ssh vps \"rm x\"")" -eq 2 ] || fail "qsafe: a backslash at the end of a comment must not join the next line (want 2 segments)"
[ "$(guard_split_segments_qsafe "ls # a\\${NL}ssh vps \"rm x\"" | sed -n 2p)" = 'ssh vps "rm x"' ] || fail "qsafe: the line after a backslash-ended comment must be intact"
[ "$(qn 'echo a # x; rm -rf y')" -eq 1 ] || fail "qsafe: a ; inside a comment must not split (want 1 segment)"
[ "$(qn 'echo a#b; rm y')" -eq 2 ] || fail "qsafe: a mid-word # must not start a comment (want 2 segments)"
[ "$(qn 'echo ${#x}; rm y')" -eq 2 ] || fail "qsafe: \${#x} must not start a comment (want 2 segments)"
[ "$(guard_split_segments_qsafe "ls # \"it's${NL}rm y; z" | sed -n 2p)" = 'rm y' ] || fail "qsafe: a quote inside a comment must not open a quote (the next line still splits)"
[ "$(qn 'echo ${x:-(#)}; ssh vps "rm x"')" -eq 2 ] || fail "qsafe: a # after ( inside \${ } must not start a comment (want 2 segments)"
[ "$(qn 'echo ${x:- #}; ssh vps "rm x"')" -eq 2 ] || fail "qsafe: a # after a blank inside \${ } must not start a comment (want 2 segments)"
[ "$(guard_split_segments_qsafe 'echo ${x:- #}; ssh vps "rm x"' | sed -n 2p)" = ' ssh vps "rm x"' ] || fail "qsafe: the command after a \${ } holding # must be intact"
printf 'ok   guard_split_segments_qsafe: comments at word start run to the newline, literal backslash and quotes, mid-word # ordinary\n'
argv_is "echo '${SUB_B}' x" "wecho|w${SUB_B}|wx|"
argv_is '{ssh,vps} x' 'o{ssh,vps}|wx|'
argv_is '/usr/bin/ss[h] vps' 'o/usr/bin/ss[h]|wvps|'
argv_is '~/bin/x' 'o~/bin/x|'
argv_is "'*'" 'w*|'
argv_is '\*' 'w*|'
argv_is "ssh vps \\${NL}  'ls /x'" 'wssh|wvps|wls /x|'
printf 'ok   review round: comment apostrophe, unbalanced-quote fail-safe, 0x1A, glob/brace/tilde opaque, backslash-newline\n'

# --- ship-guards wave (2026-10-06, repaired 2026-10-06): main-top, guard_local_scalar, ship detector ---
# guard_linked_worktree and guard_merge_seg were REMOVED after independent review (worktree carve-out
# and merge arm dropped from the design) - guard_main_top stays: review_gate mode is still read from
# the main worktree top even when the effective cwd is a linked worktree (e.g. a Lead working
# directly inside one), so its own worktree-sandbox coverage stays too.
command -v guard_main_top >/dev/null 2>&1 || fail "guard_main_top undefined after source"
command -v guard_local_scalar >/dev/null 2>&1 || fail "guard_local_scalar undefined after source"
command -v guard_ship_seg >/dev/null 2>&1 || fail "guard_ship_seg undefined after source"

WT="${TMPBASE}/at-cmdpos-worktree.$$"
rm -rf "$WT"; mkdir -p "$WT/main" || fail "cannot build worktree sandbox"
( cd "$WT/main" && git init -q && git config user.email t@t && git config user.name t && printf x > f && git add f && git commit -qm i ) || fail "cannot init worktree-sandbox main repo"
( cd "$WT/main" && git worktree add -q --detach "$WT/linked" HEAD ) || fail "cannot add linked worktree"
trap 'rm -rf "$T" "$WT"' EXIT

MAIN_R="$(cd "$WT/main" && pwd -P)"
[ "$(guard_main_top "$WT/main")" = "$MAIN_R" ] || fail "guard_main_top wrong from the main checkout itself"
[ "$(guard_main_top "$WT/linked")" = "$MAIN_R" ] || fail "guard_main_top did not resolve the main top from inside a linked worktree"
printf 'ok   guard_main_top: resolves the main checkout from both the main checkout and a linked worktree\n'

# guard_main_top must use CDPATH= on its own cd hops (same neutralization guard_cd_into already
# applies) - a `cd` whose target matches an exported CDPATH entry writes the resolved path to STDOUT
# (POSIX), which would otherwise corrupt the captured directory and desync this from the real repo.
CDPATH_SAVE="${CDPATH:-}"; CDPATH=".:/tmp"; export CDPATH
[ "$(guard_main_top "$WT/linked")" = "$MAIN_R" ] || fail "guard_main_top desynced under an exported CDPATH"
CDPATH="$CDPATH_SAVE"; [ -n "$CDPATH_SAVE" ] && export CDPATH || unset CDPATH
printf 'ok   guard_main_top: resolves correctly even under an exported CDPATH\n'

# The case above passes vacuously: $d ("$WT/linked") is ABSOLUTE, so CDPATH is never consulted for
# the `cd "$d"` hop - CDPATH only applies to a RELATIVE argument. The real exposure is the SECOND hop:
# from the MAIN checkout (not a linked worktree), `git rev-parse --git-common-dir` prints a RELATIVE
# ".git", so `cd "$cd_raw"` is `cd .git` - relative, and CDPATH-sensitive if the function's own
# `CDPATH=` prefix on that cd were ever lost. Build a DECOY dir with its own .git subdirectory,
# export CDPATH pointing at it, and confirm guard_main_top run on the MAIN checkout still resolves
# to the REAL repo, not the decoy's.
DECOY="${TMPBASE}/at-cmdpos-cdpath-decoy.$$"
rm -rf "$DECOY"; mkdir -p "$DECOY/.git" || fail "cannot build CDPATH decoy dir"
trap 'rm -rf "$T" "$WT" "$DECOY"' EXIT
CDPATH_SAVE="${CDPATH:-}"; CDPATH="$DECOY"; export CDPATH
[ "$(guard_main_top "$WT/main")" = "$MAIN_R" ] || fail "guard_main_top: a CDPATH decoy with its own .git hijacked the relative 'cd .git' hop from the main checkout"
CDPATH="$CDPATH_SAVE"; [ -n "$CDPATH_SAVE" ] && export CDPATH || unset CDPATH
printf 'ok   guard_main_top: a CDPATH decoy (its own .git dir) does not hijack the relative cd .git hop from the main checkout\n'

# guard_local_scalar: typo, duplicate line, trailing comment, missing file - same resolution order as
# the hygiene_scope resolver this generalises (local.md first, then BASE/kit-config.md), fails toward
# the caller's own strict default on anything unparsable.
GLSD="${TMPBASE}/at-cmdpos-scalar.$$"; rm -rf "$GLSD"; mkdir -p "$GLSD/top/.claude" "$GLSD/base" || fail "cannot build scalar sandbox"
BASE_SAVE="${BASE:-}"; BASE="$GLSD/base"
printf 'k: push\n' > "$GLSD/top/.claude/agent-tiers.local.md"
[ "$(guard_local_scalar "$GLSD/top" k "commit push" commit | sed -n 1p)" = "push" ] || fail "guard_local_scalar missed a clean value"
printf 'k: sideways\n' > "$GLSD/top/.claude/agent-tiers.local.md"
OUT="$(guard_local_scalar "$GLSD/top" k "commit push" commit)"
[ "$(printf '%s' "$OUT" | sed -n 1p)" = "commit" ] || fail "guard_local_scalar did not fall back on a typo'd value"
[ -n "$(printf '%s' "$OUT" | sed -n 2p)" ] || fail "guard_local_scalar gave no breadcrumb reason on a typo'd value"
printf 'k: push\nk: commit\n' > "$GLSD/top/.claude/agent-tiers.local.md"
[ "$(guard_local_scalar "$GLSD/top" k "commit push" commit | sed -n 1p)" = "commit" ] || fail "guard_local_scalar: two lines should resolve to the strict default, not first-wins"
printf 'k: push  # rolled out 2026-10\n' > "$GLSD/top/.claude/agent-tiers.local.md"
[ "$(guard_local_scalar "$GLSD/top" k "commit push" commit | sed -n 1p)" = "push" ] || fail "guard_local_scalar did not strip a trailing comment"
rm -f "$GLSD/top/.claude/agent-tiers.local.md"
[ "$(guard_local_scalar "$GLSD/top" k "commit push" commit | sed -n 1p)" = "commit" ] || fail "guard_local_scalar: missing file should fall back to the strict default"
printf 'k: push\n' > "$GLSD/base/kit-config.md"
[ "$(guard_local_scalar "$GLSD/top" k "commit push" commit | sed -n 1p)" = "push" ] || fail "guard_local_scalar did not fall through to the second (kit-config) source when the first is missing"
printf 'k: commit\n' > "$GLSD/top/.claude/agent-tiers.local.md"
[ "$(guard_local_scalar "$GLSD/top" k "commit push" commit | sed -n 1p)" = "commit" ] || fail "guard_local_scalar: the repo-local file should win over kit-config"
BASE="$BASE_SAVE"; rm -rf "$GLSD"
printf 'ok   guard_local_scalar: typo/duplicate/missing-file/trailing-comment/precedence all resolve correctly\n'

# ship detector: must fire at command position (incl. `-C`) and stay silent on an argument/quoted/
# grep mention - the same false-positive trap guard_commit_seg's own 8b section already guards.
[ -n "$(guard_ship_seg "$(guard_split_segments 'git -C /tmp/repo push')")" ] || fail "guard_ship_seg missed 'git -C x push'"
[ -n "$(guard_ship_seg "$(guard_split_segments 'gh pr create')")" ] || fail "guard_ship_seg missed 'gh pr create'"
[ -n "$(guard_ship_seg "$(guard_split_segments 'gh pr merge 1')")" ] || fail "guard_ship_seg missed 'gh pr merge'"
[ -z "$(guard_ship_seg "$(guard_split_segments 'echo git push')")" ] || fail "guard_ship_seg false-matched 'echo git push'"
[ -z "$(guard_ship_seg "$(guard_split_segments 'git log --grep push')")" ] || fail "guard_ship_seg false-matched 'git log --grep push'"
[ -z "$(guard_ship_seg "$(guard_split_segments 'echo "run git push later"')")" ] || fail "guard_ship_seg false-matched a quoted mention"
printf 'ok   guard_ship_seg: fires on git -C push / gh pr create / gh pr merge, silent on echo/log --grep/quoted mention\n'

# GUARD_PUSH_FRAG: structural classification of WHICH ship alternative matched - a caller must not
# substring-test the segment text for "push" (a gh PR title containing the word would misclassify).
command -v guard_at_command_position >/dev/null 2>&1 || fail "guard_at_command_position undefined after source"
guard_at_command_position "$(guard_ship_seg "$(guard_split_segments 'git -C /tmp/repo push')")" "$GUARD_PUSH_FRAG" || fail "GUARD_PUSH_FRAG missed a real git push segment"
guard_at_command_position "$(guard_ship_seg "$(guard_split_segments "gh pr create --title \"let's push this\"")")" "$GUARD_PUSH_FRAG" && fail "GUARD_PUSH_FRAG false-matched a gh pr segment whose TITLE text contains the word push"
printf "ok   GUARD_PUSH_FRAG: structurally tells a real git push from a gh pr segment merely mentioning push in its text\n"

echo "OK guard-cmdpos: splits on every separator with trailing newline, command-position anchors hold, guard_resolve_cwd resolves cd/paren/quote/chain/-C correctly and REPORTS an unresolvable target (T1.10) instead of falling back (message-embedded -C is not a bypass; a later literal 'commit' token does not get swallowed past the real verb), detection is structural (any option-shaped flag recognised, not an enumerated list), guard_unresolved_repo_flag/guard_repo_flag_values correctly bound to the pre-verb span (message text does not false-match), guard_commit_seg sees through sudo/nohup/path/paren/brace/if-then and stays silent on echo/grep/commit-tree/status, guard_ask_decision converts to deny on unattended OR a subagent caller (never silently on neither), guard_ask_prefix prefers subagent wording over unattended, guard_strip_heredocs preserves the opener and drops the body (default commit shape, nested $( ), two heredocs, unterminated left as-is, exact output pinned), guard_strip_quotes blanks quoted content while keeping structure, guard_split_segments_qsafe keeps a quoted ; from splitting a segment while every unquoted separator still splits, guard_main_top resolves the main checkout from both the main checkout and a linked worktree (and under an exported CDPATH), guard_local_scalar generalises the hygiene_scope resolver (typo/duplicate/missing-file/trailing-comment/precedence), guard_ship_seg detects push/gh-pr at command position and stays silent on an argument or quoted mention, and GUARD_PUSH_FRAG structurally distinguishes a real push from a gh pr segment that merely mentions it"

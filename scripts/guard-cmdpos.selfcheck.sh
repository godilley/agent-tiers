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

# 9a. guard_caller_agent: extracts .agent_type, empty when absent, charset-stripped when unusable,
#     empty (not a failure) on unparsable input.
[ "$(guard_caller_agent '{"agent_type":"worker"}')" = "worker" ] || fail "guard_caller_agent missed a real agent_type"
[ -z "$(guard_caller_agent '{"session_id":"abc"}')" ] || fail "guard_caller_agent should be empty with no agent_type field"
[ -z "$(guard_caller_agent '{"agent_type":"bad; rm -rf /"}')" ] || fail "guard_caller_agent did not strip an unusable agent_type"
[ -z "$(guard_caller_agent 'not json')" ] || fail "guard_caller_agent should be empty on unparsable input, not fail closed"
# Fail-direction regression (opus reviewer, 2026-08-27, MEDIUM): a future CLI convention stamping the
# Lead's own payload with "main"/"MAIN" must not fail CLOSED (every ask-class guard hard-denying every
# Lead commit) - normalised to "no agent", same sentinel authorship-record.sh/numeric-claim-ledger.sh
# already use the other direction (`.agent_type // "MAIN"`).
[ -z "$(guard_caller_agent '{"agent_type":"main"}')" ] || fail "guard_caller_agent should treat main as no-agent (fail-open direction)"
[ -z "$(guard_caller_agent '{"agent_type":"MAIN"}')" ] || fail "guard_caller_agent should treat MAIN as no-agent (fail-open direction)"

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

echo "OK guard-cmdpos: splits on every separator with trailing newline, command-position anchors hold, guard_resolve_cwd resolves cd/paren/quote/chain/-C correctly and REPORTS an unresolvable target (T1.10) instead of falling back (message-embedded -C is not a bypass; a later literal 'commit' token does not get swallowed past the real verb), detection is structural (any option-shaped flag recognised, not an enumerated list), guard_unresolved_repo_flag/guard_repo_flag_values correctly bound to the pre-verb span (message text does not false-match), guard_commit_seg sees through sudo/nohup/path/paren/brace/if-then and stays silent on echo/grep/commit-tree/status, guard_ask_decision converts to deny on unattended OR a subagent caller (never silently on neither), guard_ask_prefix prefers subagent wording over unattended"

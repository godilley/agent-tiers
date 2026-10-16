# CONTRACT card - the Spawn Contract, unpacked (long forms and evidence of the hot rules)
*card-v2 c=3509054877-16995 - bump on every normative edit (see MAINT-2); quote it when a return leans on this card's rules.*

> **Owns no rule id.** Every rule here is defined in the hot Spawn Contract in SKILL.md; this card holds
> each one's long form, mechanism and evidence (moved out of the hot path 2026-08-16, T3.1, and out of
> SKILL.md into this card in doctrine-v29 - nothing deleted). An edit here edits the SC rule it unpacks:
> bump `doctrine-v` in SKILL.md in the same commit. Load it from a hot rule's "unpacked below"; an
> ordinary spawn never needs it. Where a block restates its hot line, the hot line in SKILL.md wins;
> the block carries mechanism and history. In the moved text, "above", "the hot line", "here", "this
> file" and "this prose" mean SKILL.md, where each block was written; inside a block, "above" can also
> mean earlier in that block. A rule's whole section is its hot line plus its block in this card.

Each block below is the long form of a hot rule above; the hot line carries the id, the rule and the
headline measurement, this carries the mechanism and the evidence. Read on dispatch, not on every spawn.

### SC-1.3 - the hunt counter, unpacked
- **The hunt counter, unpacked.** It is the hypothesis twin of SC-6.3's execution counter, which only
  fires on spawns: a solo Lead can loop through evidence-grounded reversals forever without tripping
  anything, because each one is individually exempt above. Their COUNT is not exempt. **The unit is the
  HUNT** (one open question plus the theories about it): re-framing the question does not
  reset the count, only a primary-source finding that changes the GOAL does. On the 2nd, stop theorizing
  and route the QUESTION out to a second mind with a distilled brief (`see SC-4.1`) BEFORE the next claim
    - who that is follows the band, not this rule: interface-band, an Advisor (announce-only, `see SC-3.1`);
  reasoning-band, at minimum a fresh-context Advisor, and fable or cross-lab when your own opus reasoning
  produced the falsified theories (`see SC-1.6`, `see BOSS-3`). An execution attempt that also falsifies a
  theory ticks BOTH counters and this one fires first: it is the cheaper move and it does not spend the
  human's gate. One dispatch resets the count once; a 2nd trip on the same hunt after a return is BOSS-1's
  "keeps reversing its own conclusion" row - stop + ask (`see SC-6.3`). **The count is tracked in the Lead's
  own working notes as it goes** (a corpus-wide sweep found the count held this way in every real instance,
  never via a separate ledger file - a persistent-file requirement here was aspirational, not observed), and
  the same tracking IS the material the distilled brief draws from. (Evidenced 2026-08-06: four falsified
  theories and four user catches in one session, every escalation user-triggered, and the one Advisor
  dispatch resolved what solo theorizing could not. Same trap as the delegation skill's solo-hunt
  check-stop (a hunt not cracked in ~2-3 probes) - that one hands the CHURN to a read-only agent,
  this one hands the QUESTION.)

### SC-1.6 - evidence
Evidenced 2026-08-04: on a code-grounded diff a same-model fresh-context opus Reviewer returned 12 real
defects that two READING passes, one of them cross-lab, had both missed.

### SC-3.4 - scope change outside a lease, evidence
2026-08-16: a leak-scanner fix surfaced while moving files for an unrelated item; it was gated as its own
question, approved, and shipped as its own commit - the alternative was a silent scope change inside a
"move five files" task.

### SC-4.1a - evidence
(Evidenced 2026-08-06: a 5-agent fan-out briefed with our own rule ids plus the tier names returned findings only
inside that taxonomy; a 3-agent corrective pass over dirs it never opened - 2 unprimed, 1 adversarial -
returned three findings with no bucket in our vocabulary and a stronger validation of the ladder, stronger
because it survived an adversarial argument instead of a friendly comparison.)

### SC-4.2a / SC-4.2b / SC-4.2c - liveness vs recall, unpacked
- `SC-4.2a` **"Discounted" means: re-verify its evidence-bearing claims against the primary source, and drop
  its unevidenced judgments.** NOT "disregard the return". Missing a control proves it did not read the source
  for THAT claim; it says nothing about a claim that cites file:line, and a control-failing reviewer may still
  have earned its evidenced findings. Throwing the whole return away is both wrong and unusable.
- `SC-4.2b` **A caught control proves liveness, not recall.** The classes planted so far - a false claim about
  a readable file, a fabricated `file:line`, a real defect at the wrong severity, a correct claim asserted as
  already-fixed - are each disproved by one read. A defect planted only in a materialised diff also mismatches
  the real files read beside it (mechanism inferred, not measured). Evidence: on 2026-08-04 two read-only
  review layers each caught their control and six real defects survived both, found only by execution. The
  recorded misses were not one-read classes: a missing prohibition and a surface the docs never name
  (2026-09-14), and two real defects in a directory the reviewer syntax-checked instead of read (2026-08-24).
  Scaling the count or varying among one-read classes does not turn liveness into recall.
- `SC-4.2c` **Recall, the method details.** A held-back real defect is free and realistic, but it was found
  by the Lead, so it leans easy. Mutation seeding picks by list order (the first class not used in the
  previous seeded review), never by taste; single hunk each; a seed counts only once the seeding Worker
  shows one real input whose output differs between original and mutant (on 2026-10-10 two seeds in a row
  were equivalent: the remaining conditions already covered the deleted check, and the seeder's own account
  of the effect was wrong); recorded in chat with the copy's path before the spawn; diff via plain `git diff`, never a form that carries commit messages. A git worktree carries
  only committed state, so seed uncommitted work in a `cp -a` copy instead. The list, weighted to omission
  because that is where the misses were:
  1. **Delete a check** - an early return, a validation, a deny branch, a `--` end-of-options.
  2. **Loosen a boundary** - `<` to `<=`, drop one arm of a regex alternation or `case`, widen a glob.
  3. **Drop a semantics flag** - `rg --text`, `grep -a`, a quoting pair, `set -u`.
  4. **Swallow an error** - append `|| true`, discard a return code, send a check's stderr to `/dev/null`.
  5. **Scope slip** - fix one call site and leave its sibling; key on the wrong event, variable or path.
  6. **Drift a claim** (prose targets) - change behaviour and leave the line describing it, or widen a
     claim's scope, or drop an "inferred".
  One to three seeds is an alarm, not a rate: record seeded/caught with the finding count so a rate builds up
  across reviews. **Capture-recapture** (readers find `a` and `b` verified defects, `m` shared): Chapman
  `(a+1)(b+1)/(m+1) - 1`, which survives `m = 0`. It assumes independent captures; readers sharing a model,
  brief or read-only access miss the same defects, inflating `m` and driving the estimate down (the 2026-08-04
  pair would have estimated near zero). Compute it free on a dual-lab pass that already ran (XLAB-12), read it
  as a lower bound, never as the sole recall check. Dedupe and verify before counting: synthesis, Lead-owned.

### SC-4.1b - evidence

What is directly verified (2026-08-23): `agents/advisor.md` grants `Read, Grep, Glob` and no Bash, so a ref,
a range or a command's output cannot be materialised by that tier. What is REPORTED, across sessions, by the
operator rather than counted: that such a brief comes back as a fluent review of the working tree with no
signal that the artifact was swapped. The causal step between the two has not been reproduced under control -
the cheap experiment is to brief an Advisor against a ref that differs from the working tree and see whether
the return admits it. The rule holds on the verified half alone: the brief names something the tier cannot
open, which is a defect in the brief regardless of how the tier then behaves.

### SC-5.1 - the stash leak, evidence
  **A worktree is NOT whole-repo isolation, and `git stash` is the leak that bit us:** worktrees share one `.git`,
  so `refs/stash` is repo-wide (`git -C <any-worktree> rev-parse --git-path refs/stash` resolves to the SAME
  file). Observed 2026-08-18: two independent worker transcripts, content swapped between worktrees, and one of the
  two confirmed using `git stash`/`stash pop`; "both stashed concurrently" is the inferred mechanism, the
  shared `refs/stash` path is the verified half. So: **ban `git stash`
  in a parallel-worker brief** (not git generally - `add`/`commit`/`diff`/`status`/`log` are properly
  worktree-scoped). For the "compare against the unmodified version" need it was being used for, brief
  `git show HEAD -- <file>` or a plain file copy instead.

### SC-5.1a - the three sandbox traps
 Three traps to
carry, not assume the sandbox self-documents: (1) `permissions.deny` READ rules do **not** reach a Bash
subprocess - only `sandbox.credentials.files` protects `~/.npmrc`/`~/.aws/credentials` from a spawned
shell; (2) a bare `"docker"` in `excludedCommands` unsandboxes the WHOLE invocation, not just the docker
call - scope any exclusion to the exact command, never the bare name; (3) a broad CDN wildcard in the
domain allowlist enables exfil via that allowed domain - allowlist the specific host, not a wildcard.
(Sourced from the shipped harness's own sandbox docs, cross-checked 2026-08-06 against known external
sandbox-escape findings - closed for free where it applies; worktree isolation still owns the
write-containment half SC-5.1 states.)

### SC-5.2 - the arrival event, unpacked
  Arrival event (2026-08-16; ship point per repo since 2026-10-06): `review-gate-guard` (PreToolUse `ask`,
  once per session per repo, when the transcript holds no reviewer / advisor / codex-read spawn). The ship
  point is where a diff leaves the place only this session uses, set per repo by `review_gate:` in
  `.claude/agent-tiers.local.md`: `commit` (default) gates `git commit` plus `git push` / `gh pr
  create|merge`, so a worker there does not commit (the Lead commits after the review); `push` (a
  commit-first repo, where the pre-commit hook is the check run) lets every caller commit and gates push
  and PR only (a commit spelled with `--git-dir`/`--work-tree` still asks, and an unresolvable `cd`/`-C`
  target still denies, in either mode). A command that both commits and pushes is gated as a push. Never set `push` in a repo that
  does not push (it would gate nothing); `/agent-tiers:doctor` prints the effective mode. Ungated,
  disclosed: `merge`, `cherry-pick`, `rebase`, `am`, `pull`, `revert`, `git subtree push`, git aliases,
  any env-assignment prefix, and script wrappers (`worktree.sh down --merge` merges and pushes inside a
  script). Opt-in: the Commit review group (flat install:
  `install-flat.sh --with-review-gate-guard`); an install without it has only this prose, which measured
  at roughly one violation in four commit-bearing sessions over two reviewed corpora (2026-08-10, 2026-08-15).
  In a session flagged by `/unattended on`, that `ask` arrives as a DENY carrying the same remedy (spawn a
  reviewer, retry the commit) rather than a halt nobody is present to clear - the gate is enforced either
  way, and no hard deny is ever converted (HOST card, unattended mode). Same conversion, independently
  (2026-08-27): when the CALLER is a subagent (a delegated worker's own commit, or any push), the ask
  also arrives as a deny - a delegated agent has no standing to judge triviality or spawn a reviewer
  either, and there is no channel back to the Lead for a real `ask` to reach. Worded at the worker (stop,
  report it back) rather than at a human. See `guard_caller_agent`/`guard_ask_decision` in
  `guard-cmdpos.sh`.

### SC-5.2a - evidence
2026-08-16: the author of the Bash write-scan wrote every patch to the kit that day via `python3
/tmp/fixtures/*.py`, because the guards false-fired on its test literals - a full day of kit edits with no
authorship row, by the person who knew best why the row exists.

### SC-6.1a - the four riders, unpacked
- **A lookup is complete only when you have followed the CALL PATH, not the symbol.** Reading the callee
without the caller produces a confident inversion, which is **worse than no lookup** - it arrives with
authority attached and displaces the review that would have caught it.
- **A correction you have just made to your own conclusion is the highest-risk statement in the artifact.** It
enters the next review pass as a CLAIM to be adjudicated, never as settled fact.
- **The user's own earlier words are a primary source too.** Before asserting "you said X", or building a
correction on a position the user took earlier in the session, pull the VERBATIM quote - a paraphrase from
memory is the confident inversion above, aimed at the user. **If the session was compacted, the earlier
turns are a SUMMARY and not the source:** read the transcript file, or quote nothing and ask the user to
confirm your reading. Never quote from a summary - a fabricated quote attributed to the user is worse than
the paraphrase it replaced. (Evidenced 2026-08-06: a Lead paraphrased the user's hypothesis into its
opposite and then "corrected" it; quoting back and letting the user confirm the reading would have cost
one sentence.)
- **This applies to THIS doctrine too.** A rule you found by grep or a partial read is a partial lookup, and
the failure mode is specific: you propose a rule that already exists, or you read a permissive headline
whose restriction lives in the next clause. Before proposing or editing any rule here, read its whole
section - and `see MAINT-2` for the `doctrine-v` / `card-v` stamp so a return can name the revision it
applied. (2026-08-04: a session proposed four rules the kit already had, after reading this file by grep
plus two slices. Stated ceiling, no-hook: a partial read leaves no tool call to gate, so this one fires
only for someone already applying SC-6.1a.)
(Hot line: lookup and review are complements, not substitutes - the lookup answers what a debate cannot, and a
reviewer is what catches a partial lookup.)

### SC-6.1b - the checklist long form
**The decorative-CI trap - a gate you build or review must clear 4 questions, not just
run green.** A common evidence-discipline gap: a status check that reports without stopping anything is
theater, and the trap is easy to ship by accident (a real external example: a shipped review gate `exit
1`s by regex-parsing an LLM-authored markdown table - still LLM self-grading, just parsed
deterministically, and its own author's docs call this out). Before trusting or shipping ANY verification
gate (a hook, a CI job, a Stop-check):
1. **Deterministic or LLM-self-grading?** Lint/typecheck/test exit codes are deterministic; an LLM
   judging its own diff, even parsed by a strict regex after, is still self-grading underneath.
2. **Is there a real stop-the-line mechanism?** A required status check on the protected branch, not a
   job that merely reports and can be merged past.
3. **Is there traceability?** Can a failure be traced back to the exact rule/spec clause it violated?
4. **Does spec stay authoritative?** The gate checks the diff against a spec that does not itself drift
   silently with the code.

### SC-6.1b - the kit-specific reading
For this kit specifically: as a merge-blocking AUTOMATED gate (CI, a Stop-hook), keep LLM review
advisory-only - the real automated gate is exit codes (lint/test). `SC-5.2`'s independent pass is a
different mechanism, and the discriminator that keeps it off question 1's self-grading trap is
INDEPENDENCE (a genuinely different mind reviewing, `see SC-1.6`) - not that it is human-facing rather
than automated; a judgment pass graded by the SAME author is exactly the theater question 1 names,
regardless of audience. Disclosed rather than argued away: `SC-1.6`'s ROUTINE-class carve-out lets a
reasoning-band Lead self-run this pass on its OWN diff - that carve-out IS the self-grading shape
question 1 warns about, a real residual overlap, not a false alarm. Narrowing that carve-out is a
separate decision, not settled by this rule. (Sourced 2026-08-06, cross-checked against a real shipped
gate that fails this checklist despite looking rigorous - don't copy the YAML, adopt the checklist.)

### SC-6.4 - why the check-in is repeated in the FINAL message
The Agent tool returns only the agent's **FINAL** message. An opening check-in line does NOT survive back
to the Lead if the agent runs ANY tools afterward. So the check-in must be **repeated as the first line of
the FINAL return** (the kit's `advisor`/`worker` already do this). A live GUI panel still shows it streaming.

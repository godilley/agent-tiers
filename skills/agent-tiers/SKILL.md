---
name: agent-tiers
description: >-
  v4 delegation doctrine: the Lead/Worker/Advisor/Reviewer/Boss tier vocabulary, driven by a CHEAP
  interface-layer Lead that routes, briefs and verifies while intelligence is METERED - bought per call
  at the cheapest tier that clears the job. Owns the every-spawn Spawn Contract, the Lead capability-band
  dial, the scope matrix and per-spawn model override, the escalation ladder, cross-provider handoff with
  the generate-vs-verdict split, review modes and planted controls, and the agent check-in line. Use when
  delegating to a sub-agent, deciding which tier or model fits a task, briefing a review or fan-out
  audit, routing work to another provider, or when a session is genuinely stuck.
---

# Agent tiers v4 - Lead / Worker / Advisor / Reviewer / Boss
*doctrine-v16 c=3098324220-58119 - bump on every normative edit (see MAINT-2); quote it when a review or return leans on these rules.*

**v4 doctrine: the standing cost is a cheap INTERFACE-LAYER Lead; intelligence is metered.** The Lead
converses, routes, writes tight briefs, verifies returns, and gates; deep reasoning is bought per
call from a thinking tier instead of ground out in the Lead's own (context-heavy, every-turn-billed)
context. The Lead still owns project knowledge, synthesis, and every final decision - never delegated.

## The Spawn Contract - the every-spawn checklist (READ THIS; everything after is cold reference)
Six steps, every spawn, in order. Route by task SHAPE, never a self-judged "hardness" gut-call (a weak
Lead's blind spot is not knowing what it doesn't know - so shape is the trigger, not a feeling).

**Copy this block into your working notes for any spawn that isn't on the SC-1.4 trivial-work whitelist,
and check items off as you clear them:**
```
- [ ] 1. CLASSIFY - trust-class? disclosure-sensitive? any tripwire? (SC-1.1-1.6)
- [ ] 2. ROUTE - shape -> tier + band, per the scope matrix (SC-2.1-2.2)
- [ ] 3. AUTHORIZE - spend rung / disclosure gate / irreversible-action gate / wave lease (SC-3.1-3.4)
- [ ] 4. BRIEF - shared template, self-contained, gap-check vs discovery split, planted control if a review (SC-4.1-4.2)
- [ ] 5. ISOLATE/EXECUTE - writer isolation, sandbox, egress preflight if cross-lab (SC-5.1-5.4)
- [ ] 6. VERIFY + RECOVER - grade the return, check-in line, recovery ladder if it failed (SC-6.1-6.4)
```

### 1. CLASSIFY - trust-class + disclosure, conservative by default
Tag two things before routing:
- `SC-1.1` **Trust-class?** touches **security**, **architecture**, or is **hard-to-reverse** (data-loss / deploy /
  costly to undo). Unsure -> treat as IN-class (never let the weak link under-classify past the gate).
- `SC-1.2` **Disclosure-sensitive?** will any step send repo content to another lab (Codex)? Unknown -> treat as sensitive.

**The classifier cannot be the sole grader of its own trust-criticality**, so:
- `SC-1.3` **Escalation tripwires (force escalation regardless of gut-call):** any trust-class tag; a diff/design you
  cannot fully grade at your own depth (`see SC-1.3a`); security/auth/secrets touched; schema/data migration; deploy / release
  / push / delete; a cross-lab send; **reversing your own prior conclusion WITHOUT new primary evidence** (a
  reversal grounded in a primary source you just read is the system working; one grounded in argument is the
  tripwire); a 3rd attempt at one goal (the stop fires BEFORE the 3rd runs, `see SC-6.3`); **a 2nd falsified
  hypothesis or 2nd material user correction on the SAME hunt** (`see SC-1.3a`; unpacked below).
  - The hunt counter (unit = the HUNT: re-framing the question does not reset the count, only a primary-source
    finding that changes the GOAL does; on the 2nd, route the QUESTION out to a second mind - one dispatch resets
    the count once, a 2nd trip after a return is BOSS-1's stop-and-ask; log each dead theory to `ATTEMPTS.md`;
    evidenced 2026-08-06): unpacked below.
- `SC-1.3a` **The operator words above are ARTICULATION TESTS, not feelings** (they gate SC-1.3, SC-1.4 and
  SC-6.1(c), so they get one owner). Each is satisfied only if you can WRITE the thing it names; if you
  cannot produce it, the answer is the escalating one. A self-assessment cannot be fixed by wording, but it
  can be converted into an artifact you either have or do not:
  - **"can fully grade at your own depth"** = you can NAME the specific failure modes you are checking for
    and the evidence that would reveal each. Cannot state the test -> cannot grade it -> escalate.
  - **"fully verify by eye"** = you can enumerate everything this change could break and check each one in
    the diff **without running anything**. If it needs a run to know, it is not by-eye.
  - **"material" disagreement** = the two parties would take DIFFERENT ACTIONS. Different wording, emphasis
    or confidence about the same next step is not material.
  - **"falsified"** = you WROTE a claim (chat, plan, or artifact) and a later read or run contradicted it.
    If you cannot name the sentence and what contradicted it, it still counts - under-counting is the exact
    failure this tripwire exists for, so the ambiguous case ticks.
  - **"user correction"** = a MATERIAL one, same bar as "material" above: it changed your conclusion or your
    next action. A typo, a formatting nit, or a restated preference is not one.
- `SC-1.4` **Trivial-work whitelist (the ONLY shapes a Lead self-handles without routing):** read / search / grep;
  running tests or builds; a one-line or pattern-mechanical edit you can fully verify by eye (`see SC-1.3a`);
  routing / brief writing itself; restating already-known facts. Everything else routes. **A tripwire
  OVERRIDES the whitelist** - a one-line edit that touches auth/secrets is trust-class, not trivial.
- `SC-1.5` **Uncertain -> escalate UPWARD** (Advisor / reasoning-band / human), never downward and never silent.
- `SC-1.6` **Trust-bearing work gets a pre-ship RECLASSIFICATION gate** using the same taxonomy. The gate's existence
  and criteria are **band-invariant** (band changes WHO runs it, never WHETHER). **Independence is REQUIRED**
  for **top-stakes** (security / auth / deploy / release / schema-or-data migration) and any **UNKNOWN** class:
  those always get a second, DIFFERENT mind. **WHICH axis buys that independence is owned by XLAB-12** - it is
  chosen by CLAIM SHAPE, not by the Lead's band: repo-access for a code-grounded claim, provider (cross-lab /
  fable) for a domain-fact or judgement one, and AUTHORSHIP always. Under an interface-band Lead an opus
  Reviewer/Advisor is already the different mind; under a reasoning-band Lead a same-CONTEXT self-verify is not
  independence at all, so the reader is at minimum a FRESH-CONTEXT spawn, and cross-lab/fable when the claim is
  domain-fact or judgement shaped. (Evidence 2026-08-04, unpacked below.)
  A reasoning-band Claude-strong Lead may self-run the gate ONLY for an explicitly **ROUTINE** class - a config
  / UI / doc / test tweak with NO security, deploy, or schema surface. See Trust taxonomy.

### 2. ROUTE - shape -> tier + band (defaults, not laws)
`SC-2.1` Match the SHAPE to a row (override per spawn with the Agent `model` param; per-project overrides in
`.claude/agent-tiers.local.md`; picking a model this table does NOT already name for the shape is a
deviation - state it and get approval first, `see ROUTE-3`):

| Task shape | Who | Model | Effort |
|---|---|---|---|
| Converse, route, brief-write, verify, light synthesis | Lead | sonnet (GUI-set, never file-pinned) | high |
| Rote scripted procedure (log scrape, db query, scripted deploy) | L3 task agent | **haiku** | low |
| Mechanical with some judgment (build+verify, refactor-by-rote, gates, PR-prep) | Worker / L3 task agent | sonnet | low-medium |
| Fan-out research / audit first pass | worker / auditor / Explore | sonnet | low-medium |
| Deep reasoning: design, plan, tricky-debug hypothesis (ONE bounded ask) | Advisor | opus | high |
| Curate a set of cheap audit drafts | Reviewer | opus | high |
| Clever CODE, session pref = codex (per-host, authed) | `codex-write` (isolated worktree) | codex tier (XLAB-11) | low-high |
| Clever CODE otherwise / no codex this host | Worker with `model: opus` | opus | medium-high |
| Stuck circuit-breaker (gated) | Boss | different from the Lead (opus; fable if opus implicated) | xhigh |
| Exceptional hardest-reasoning call (gated, explicit) | Advisor/Boss with `model: fable` | fable | xhigh |

`SC-2.2` **Band:** an **interface-band** Lead routes reasoning DOWN to the Advisor; a **reasoning-band** Lead reaches
OUT for independence (see Lead capability-band). A trust-class VERDICT is owned only by a **reasoning-band
AND Claude-strong** tier (defined in Trust taxonomy, cold section) - an interface-band Lead must route that verdict out.

### 3. AUTHORIZE - three ORTHOGONAL permissions + a wave lease
Cost is not the only gate. Check each that applies:
- `SC-3.1` **Spend** (cost ladder): (1) FREE any sonnet/haiku spawn; (2) ANNOUNCE-ONLY one scoped opus call -
  state one line (tier, model, why) and proceed; (3) GATED an opus fan-out (2+ parallel opus), the Boss, and
  anything fable. A cross-provider (Codex) call is gated by default, but its exact rung is owned by XLAB-9 -
  STOP and load the XLAB card before authorizing it. **The built-in `Explore` agent inherits the Lead's
  model** (measured over two reviewed session corpora, 2026-08-10 and 2026-08-15: every observed case):
  a 2+ Explore fan-out under an opus Lead IS a rung-3 opus fan-out - pass `model: sonnet` (ROUTE-2's row
  for it) or gate it.
- `SC-3.2` **Cross-provider disclosure** (sending repo content to another lab): gated SEPARATELY via the step-5
  preflight - not folded into spend.
- `SC-3.3` **Irreversible-or-external action** (deploy, delete, push, external side effect): always GATED, independent
  of spend.

`SC-3.4` **Wave lease (fixes gate-batching - a repeated-interrupt accessibility cost):** ONE human approval can cover a
NAMED wave - state **objective + mechanisms + scope + expiry**. Inside the lease, spawn freely without
re-gating. The lease ENDS and you re-gate on: a scope change; **a failure whose recovery changes the
MECHANISM, the SANDBOX, or the DISCLOSURE SET** (a mechanical retry of an otherwise identical call is not a
lease-ending failure - state those three invariants on the record when you exercise this); a NEW disclosure; a
Boss spawn; any destructive action. The gate tracks "can the human react between spawns," not cumulative spend. OUTSIDE a
lease, checkpoint a long SERIAL run of announce-only opus calls at a natural milestone; UNDER a lease, the
human-set expiry / named milestone IS the checkpoint trigger. Never hardcode a numeric trigger. **The
scope-change trigger binds OUTSIDE a lease too:** work that turns out to need a mechanism the task did not
name is re-gated before it is built, not absorbed because it is adjacent (evidence 2026-08-16, unpacked below).

### 4. BRIEF - self-contained (agents start blind)
`SC-4.1` Every metered spawn rides the ONE shared template `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/templates/escalation-brief.md`:
goal; facts gathered + paths; attempts WITH results (or point at `ATTEMPTS.md`); the ONE question / acceptance
criteria; constraints; out-of-scope. STATE the spawned model/effort in the brief so the check-in can report it
truthfully (agents cannot introspect their live model).

`SC-4.1a` **"Self-contained" is not "pre-framed" - split the brief by TASK SHAPE.** Context naming our own
concepts (rule ids, tier names, card ids, kit vocabulary) is either the question itself or a primer; it is
never neutral. **Test: if a valid answer could be "a thing we have no name for", the shape is DISCOVERY.**
- **GAP-CHECK shape** (does X cover rule Y? is this consistent with the ladder? where does it contradict us?):
  our taxonomy IS the question - state it in full, exactly as SC-4.1 says. An unprimed reader here returns
  unmapped mush.
- **DISCOVERY shape** (what is out there? what are we missing? what has no bucket in our system?): brief it
  UNPRIMED - target, dirs, acceptance criteria, and NOT ONE of our concept names. A reader handed our
  vocabulary first can only return findings that vocabulary can express, and it then reports the gap CLOSED.
  Unprimed means unprimed on OUR taxonomy, not on the spawn's own config: the declared model/effort line and
  the check-in still stand (`see SC-4.1`). The Lead maps the return onto the taxonomy AFTER it lands - that
  mapping is synthesis, never delegated.
- **A mixed ask runs as TWO spawns, never one blended brief.** A primed reader cannot un-see the framing, so
  a blend silently buys the gap-check at the price of the discovery half. Reader-side, this is the FRAMING
  axis (see XLAB-12); it is the cheapest independence axis there is, bought by the brief alone.
(Evidence 2026-08-06, unpacked below.)

`SC-4.1b` **A brief for a Bash-less tier names only artifacts that tier can OPEN: a path that exists, or
content inlined in the brief text - never a ref or a command to go and run.**
Advisor/Reviewer/Boss hold no Bash (Reviewer also holds Write), so "review `abc123..def456`", "the diff", "the
previous version", "the output of X" name artifacts they cannot materialise, and the brief is already broken
whatever the tier then does. The reported failure is silent substitution - they review the nearest reachable
thing (usually the working tree) and the return does not say so, marking a review gate satisfied that never ran
(reported across sessions and the tool grant verified 2026-08-23; the substitution behaviour itself has NOT been
reproduced under control - see SC-4.1b evidence below). The Lead has Bash: materialise it FIRST (`git diff A..B > /tmp/target.diff`) and brief
the path. Check at brief-writing time: *can this tier open every artifact I just named?* If the target must be
COMPUTED and the reasoning must be independent, the instrument is `Explore` with an explicit `model:` override -
read-only at the tool layer, and it has Bash (`model:` is not optional there, see SC-3.1).

`SC-4.2` **Planted control - any fan-out REVIEW whose findings you will act on.** Seed the brief with at least
one claim or defect you have **already verified**, formatted identically to the uncertain items and
**unmarked**. A reviewer that "refutes" a control has its other refutations discounted; one that confirms them
has earned its other verdicts. **Prefer a real known defect over an invented one** - nothing to remember to
remove, and it tests the exact defect class the pass is for. Record the controls in the chat before spawning so
they cannot ship by accident. This is the cheap instrument for `SC-6.1` tier (c) - grading a reviewer whose
correctness you cannot evaluate at your own depth. (Review-MODE shape: see Escalation briefs.)
  - `SC-4.2a` **"Discounted" means re-verify its evidence-bearing claims against the primary source and drop its
    unevidenced judgments** - NOT "disregard the return" (unpacked below).
  - `SC-4.2b` **A control everyone catches has stopped measuring:** scale the COUNT to the findings you expect
    (not "at least one"), distribute position, vary the class, never reuse across parallel reviewers, and **read a 100% catch rate as a failing instrument** - on this
    kit's own record every control ever planted was caught (unpacked below).

### 5. ISOLATE / EXECUTE - contain writers + gate cross-lab egress
- `SC-5.1` **DELEGATED writers run isolated:** `codex-write` and worktree-parallel writers write in an **isolated
  worktree/branch, NEVER the live checkout** (`codex-write` ALWAYS, no exception). TWO carve-outs, both native
  Claude only: (i) the Lead's own whitelist-qualified trivial edit in the live checkout (step 1); (ii) a single
  signed-off Worker on a well-specified live-tree slice (no parallel writer, revert-on-failure per step 6
  quarantine). No deploy / external action from a writer; the Claude gate runs before any merge or production execution.
  **A worktree is NOT whole-repo isolation, and `git stash` is the leak that bit us:** worktrees share one `.git`,
  so `refs/stash` is repo-wide (`git -C <any-worktree> rev-parse --git-path refs/stash` resolves to the SAME
  file). Observed 2026-08-18: two independent worker transcripts, content swapped between worktrees, and one of the
  two confirmed using `git stash`/`stash pop`; "both stashed concurrently" is the inferred mechanism, the
  shared `refs/stash` path is the verified half. So: **ban `git stash`
  in a parallel-worker brief** (not git generally - `add`/`commit`/`diff`/`status`/`log` are properly
  worktree-scoped). For the "compare against the unmodified version" need it was being used for, brief
  `git show HEAD -- <file>` or a plain file copy instead.
- `SC-5.1a` **Use the harness-NATIVE sandbox first, worktree isolation second - they answer different
  questions.** A worktree contains WRITES (a bad edit lands on a disposable branch); it does nothing about a
  process reading credentials, hitting the network, or touching the host outside the repo. Claude Code ships
  its own OS-level sandbox (Seatbelt on macOS, bubblewrap+socat on Linux) - FS read-all/write-CWD-only by
  default, network via a SOCKS5 proxy + domain allowlist - so a genuinely risky command (an unvetted script,
  a build step that shells out further) should run sandboxed, not just worktree-isolated. Three traps to carry (deny
  READ rules do not reach a Bash subprocess - use `sandbox.credentials.files`; a bare `excludedCommands` name
  unsandboxes the whole invocation - scope it to the exact command; a CDN wildcard in the allowlist is an exfil
  path - allowlist the specific host) - unpacked below.
- `SC-5.2` **Any non-trivial diff takes an independent fresh-eyes pass before it ships - INCLUDING one the Lead
  authored itself.** The step-5 "writer" framing is not a loophole: **authorship**, not delegation, is what creates
  the blind spot, so a Lead-authored diff is in scope exactly as a delegated one is. Top-stakes ALWAYS takes the
  independent pass per SC-1.6, at every band. Only for an explicitly ROUTINE class may a reasoning-band Lead run
  the pass at its own depth; an interface-band Lead never may (the cheap Lead cannot grade a deep call).
  **The argument that will occur to you and is wrong:** "another pass is low marginal value here" is a statement
  about the diff you have ALREADY reviewed, never about the diff you are about to author - a review obligation is
  discharged against an artifact, and does not carry to the next one. Codex output is never solely Codex-reviewed.
  Measured, not asserted: across 140 sessions and 6 weeks this rule fired in **2.1%** of sessions and did not move
  as the doctrine grew, which is why `authorship-record` exists as a hook rather than a seventh restatement here.
  Arrival event (2026-08-16): `review-gate-guard` (PreToolUse `ask` at `git commit`, once per session per
  repo, when the transcript holds no reviewer / advisor / codex-read spawn). Consent-class: wired only via
  `install-flat.sh --with-review-gate-guard`; an install without it has only this prose, which measured
  at roughly one violation in four commit-bearing sessions over two reviewed corpora (2026-08-10, 2026-08-15).
  In a session flagged by `/unattended on`, that `ask` arrives as a DENY carrying the same remedy (spawn a
  reviewer, retry the commit) rather than a halt nobody is present to clear - the gate is enforced either
  way, and no hard deny is ever converted (HOST card, unattended mode). Same conversion, independently
  (2026-08-27): when the CALLER is a subagent (a delegated worker's own commit, not the Lead's), the ask
  also arrives as a deny - a delegated agent has no standing to judge triviality or spawn a reviewer
  either, and there is no channel back to the Lead for a real `ask` to reach. Worded at the worker (stop,
  report it back) rather than at a human. See `guard_caller_agent`/`guard_ask_decision` in
  `guard-cmdpos.sh`.
- `SC-5.2a` **Writes stay on the instrumented path.** File edits go through `Edit`/`Write`/`NotebookEdit`,
  which the write-path guards observe in full (`MultiEdit` gets the path check and the authorship row but NOT
  the content scan - `security-gate`'s declared bypass; prefer `Edit` for content that could carry a secret).
  A Bash write (`sed -i`, a heredoc, a script that
  writes files) is legitimate for mechanical bulk work - many call sites, a file too large to edit in place,
  a generated artifact - but it is **off-instrument**: no `authorship-record` row, and content the gate cannot
  read from the command line is unscanned (`security-gate`'s disclosed generated-content ceiling). Name the
  reason in the turn that does it and say which files were written. Default plus declared exception, not a
  ban: the kit ships no bulk-replace tool. (Evidence 2026-08-16, unpacked below.)
- `SC-5.3` **Cross-lab egress preflight (run before ANY cross-lab send; FAIL CLOSED).** Any pass that invokes a
  non-Claude provider first STOPS and loads the XLAB card; then this preflight runs before the send: (1) workspace sensitivity -
  unknown STOPS the send; (2) name the exact files/diff being sent; (3) scan for secrets / credentials /
  private data; (4) minimize / redact to the minimum needed; (5) explicit consent. A solo local repo with your
  own authed account stays lightweight (all five steps still run as quick self-checks - none skipped, no gate
  ceremony); the moment secrets are present -> fail closed, do not send.
  - `SC-5.3a` **The unit is the WORKING DIRECTORY, not the artifact you mean to send.** A clean document in a
    dirty tree is still a fail-closed: the provider reads the wider tree regardless of the brief. So the
    resolution is not only "do not send" - it is **RELOCATE**: copy the minimum artifact to an isolated dir
    OUTSIDE the repo, run there, and list that dir to confirm nothing else is reachable. Redaction shape when
    you relocate: see XLAB-10.
  - **Honesty about scope (the preflight's limit):** this preflight gates disclosure INTENT, not sandbox
    containment - `codex exec` can still read the wider tree, git history, and inherited env. That is exactly
    why the secrets case fails CLOSED (prohibit the send) rather than trusting redaction; for a clean solo
    kit the intent-gate suffices.
- `SC-5.4` **Two layers, do not conflate:** the session-level consents (XLAB-7) grant the CHANNEL
  (may Codex write / review this session); THIS preflight gates each SEND on top. A send of files not already
  cleared by a prior preflight is a **NEW disclosure** (re-run the preflight; it also ends a wave lease).

### 6. VERIFY + RECOVER - grade the return, always have a recovery move
`SC-6.1` **Verify has three tiers - don't collapse into rubber-stamping:** (a) *observable outputs* (tests pass, diff
matches, file state; and via the agentsview ledger - see Companions - what a sub-agent ACTUALLY did vs its
self-summary) - verify directly; (b) *internal consistency* (reasoning coheres, cites real files, no
self-contradiction) - check at your own depth; (c) *a judgment call whose correctness you genuinely cannot
evaluate at your own depth* (`see SC-1.3a`) - this is NOT verify-and-proceed: **escalate** (gate to human / get a second
independent opinion / upgrade the Lead for that call). Under an interface-band Lead, (c) is a STANDING risk,
not an edge case. The reflex for (c) on a **top-stakes** trust-class review = a dual-lab pass (XLAB-12); a
routine tier-(c) call resolves with a single opus Advisor.

`SC-6.1a` **A CHECKABLE fact is settled by reading the primary source - never by adjudicating between two
models, and never by buying a third opinion.** A version boundary, an API signature, a release date, a
lockfile constraint: two models arguing teaches you about the models, not about the fact.
Four load-bearing riders (follow the CALL PATH, not the symbol; your own fresh correction is the highest-risk
claim in the artifact; the user's earlier words are a primary source - quote VERBATIM, never from a compaction
summary; this doctrine too - read the whole section before proposing a rule) and their evidence: unpacked below.
Lookup and review are **complements, not substitutes**.
`SC-6.1b` **The decorative-CI trap - a gate you build or review must clear 4 questions, not just
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
For this kit: LLM review stays advisory as an AUTOMATED gate (exit codes are the gate); `SC-5.2`'s pass is
kept off question 1 by INDEPENDENCE, and `SC-1.6`'s ROUTINE carve-out is a disclosed residual overlap
(unpacked below).
`SC-6.2` **Fail-OPEN on a trust verdict is banned:** if the trust-class verdict OWNER (a reasoning-band Claude-strong
tier) is unavailable mid-session, **STOP and tell the human** - never let a weaker/faster tier silently inherit
a trust-class verdict.

`SC-6.3` **Recovery ladder (the daily failed-worker case; log each move to `ATTEMPTS.md`):**
- **Accept** - return verifies clean -> done.
- **Repair** - small, well-understood gap -> resume the SAME agent ONCE with a corrective note.
- **Restart fresh** - context contaminated / agent looping -> NEW agent on a clean brief, do not resume.
  (Count it: after a failed repair this restart IS the 3rd execution attempt - Stop + ask fires FIRST.)
- **Re-shape to Advisor** - output reveals a reasoning task mislabeled mechanical (also the backstop for
  shape-misclassification) -> re-route as an Advisor ask, not another Worker attempt.
- **Quarantine** - a partial WRITER failed -> an isolated-worktree writer's output stays unmerged (inspect,
  salvage by hand or discard); a signed-off LIVE-tree Worker that broke the tree gets reverted before any retry.
- **Stop + ask** - count each EXECUTION attempt (the original + repair + restart = 3). BEFORE a 3rd attempt,
  STOP and surface the attempt log; the human authorizes ONE of: the Boss gate (circuit-breaker; load the BOSS
  card before spawning), a re-shape, or one final retry. This is the same threshold as the step-1 "3rd+
  attempt" tripwire (one counter, one action).

`SC-6.4` **Then:** repeat the spawned agent's check-in (`name . tier . model . effort . def-v<N>`; model is DECLARED
not introspected, def-v is disk-verifiable) as the FIRST line of its FINAL message - the opening check-in is
stripped once the agent runs any tool (see Check-in-return gotcha). After editing an agent definition, compare
the check-in's `def-v<N>` to disk before trusting behaviour-dependent results (staleness protocol: see MAINT-2).

*Everything below is COLD REFERENCE - the Spawn Contract's unpacked bodies (long form + evidence of the hot
rules), the tier vocabulary, the capability-band dial, routing rationale (ROUTE card), cross-provider handoff,
lifecycle/gc. Read it when designing or changing the system, not on every spawn.*

## The Spawn Contract, unpacked (moved out of the hot path 2026-08-16, T3.1 - nothing deleted)
Each block below is the long form of a hot rule above; the hot line carries the id, the rule and the
headline measurement, this carries the mechanism and the evidence. Read on dispatch, not on every spawn.

### SC-1.3 - the hunt counter, unpacked
- **The hunt counter, unpacked.** It is the hypothesis twin of SC-6.3's execution counter, which only
  fires on spawns: a solo Lead can loop through evidence-grounded reversals forever without tripping
  anything, because each one is individually exempt above. Their COUNT is not exempt. **The unit is the
  HUNT** (one open question plus the theories about it, `see BOSS-2`): re-framing the question does not
  reset the count, only a primary-source finding that changes the GOAL does. On the 2nd, stop theorizing
  and route the QUESTION out to a second mind with a distilled brief (`see SC-4.1`) BEFORE the next claim
    - who that is follows the band, not this rule: interface-band, an Advisor (announce-only, `see SC-3.1`);
  reasoning-band, at minimum a fresh-context Advisor, and fable or cross-lab when your own opus reasoning
  produced the falsified theories (`see SC-1.6`, `see BOSS-3`). An execution attempt that also falsifies a
  theory ticks BOTH counters and this one fires first: it is the cheaper move and it does not spend the
  human's gate. One dispatch resets the count once; a 2nd trip on the same hunt after a return is BOSS-1's
  "keeps reversing its own conclusion" row - stop + ask (`see SC-6.3`). Log each falsified theory to
  `ATTEMPTS.md` as it dies (`see BOSS-2` - `ruled out:` / `suspicion:` are exactly this ledger) so the
  count is a FILE, not a memory, and the log IS the distilled brief. (Evidenced 2026-08-06: four falsified
  theories and four user catches in one session, every escalation user-triggered, and the one Advisor
  dispatch resolved what solo theorizing could not. Same trap as the delegation skill's solo-hunt
  check-stop, memory note: check-stop-delegate-the-hunt - that one hands the CHURN to a read-only agent,
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

### SC-4.2a / SC-4.2b - control calibration, unpacked
- `SC-4.2a` **"Discounted" means: re-verify its evidence-bearing claims against the primary source, and drop
  its unevidenced judgments.** NOT "disregard the return". Missing a control proves it did not read the source
  for THAT claim; it says nothing about a claim that cites file:line, and a control-failing reviewer may still
  have earned its evidenced findings. Throwing the whole return away is both wrong and unusable.
- `SC-4.2b` **A control everyone catches has stopped measuring.** Scale the COUNT to the findings you expect
  (not "at least one"); DISTRIBUTE position across the brief, never as its own flagged paragraph; VARY the
  CLASS - a false claim about a readable file is one mode, a fabricated `file:line`, a real defect stated at the
  wrong severity, and a correct claim asserted as already-fixed are others. Never reuse one control across
  parallel reviewers if independence is the point. **Record the catch rate and read 100% as a failing
  instrument**, not as a good pass: on this kit's own record every control ever planted was caught, which means
  the difficulty was never calibrated.

### SC-4.1b - evidence

What is directly verified (2026-08-23): `agents/advisor.md` grants `Read, Grep, Glob` and no Bash, so a ref,
a range or a command's output cannot be materialised by that tier. What is REPORTED, across sessions, by the
operator rather than counted: that such a brief comes back as a fluent review of the working tree with no
signal that the artifact was swapped. The causal step between the two has not been reproduced under control -
the cheap experiment is to brief an Advisor against a ref that differs from the working tree and see whether
the return admits it. The rule holds on the verified half alone: the brief names something the tier cannot
open, which is a defect in the brief regardless of how the tier then behaves.

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
plus two slices. Stated ceiling: nothing enforces this at read time; it fires only for someone already
applying SC-6.1a.)
(Hot line: lookup and review are complements, not substitutes - the lookup answers what a debate cannot, and a
reviewer is what catches a partial lookup.)

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

*The exceptional-mechanism normative rules live in five single-owner **policy cards** under
`cards/`, each loaded on dispatch from the hot Spawn Contract (never on an ordinary spawn):
**XLAB** (cross-provider Codex), **BOSS** (stuck circuit-breaker), **MAINT** (definitions / staleness / gc /
project layer), **HOST** (model resolution + env probes), **ROUTE** (routing rationale - the five axes, the
per-spawn model/effort levers, and the rule that stops a cheap Lead grinding a hard shape). The cold sections here carry rationale + `see <id>`
pointers into those cards; the card is the rule's one owner.*

| Tier | Who | Model | Effort | Role | Tools |
|---|---|---|---|---|---|
| **Lead** | the main interactive session | **sonnet** interface-band default; **opus (or fable)** reasoning-band per work-class - fable adds the top-of-band COST qualifier, not a third band (see Lead capability-band) | high | The interface layer: converse, route, brief, verify, gate, synthesise, decide. Does NOT grind high-reasoning shapes itself (see ROUTE-4). | full |
| **Worker** | `worker` / `<project>-worker` | sonnet (haiku if rote; **opus per-spawn** for clever code) | low / medium (opus clever-code spawn: medium-high) | Fully-specified mechanical jobs (build, search, transform, verify). Follows the brief; does not decide. | scoped (read/edit/write/bash - canonical: worker.md frontmatter) |
| **Advisor** | `advisor` | opus | high | Deep reasoning on ONE bounded question OR a bounded design/plan; returns a recommendation (or plan) + confidence. Never edits. | read-only |
| **Reviewer** | `reviewer` | opus | high | Curates several cheap first-pass audit drafts into ONE trustworthy list - cuts false positives, re-rates severity, dedups, ADDS what the cheap pass missed. Never edits code. | read-only + writes its one curated file |
| **Boss** | `boss` | **different from the Lead** (opus for a sonnet Lead; fable if opus reasoning was already implicated) | xhigh | Rare, **always human-gated** circuit-breaker: delivers an independent VERDICT on a distilled brief when the Lead is stuck; the Lead still OWNS adopting it (the value is independence, not authority-transfer). Never gathers; bounces vague briefs. | read-only |

- **Model is the main cost lever (doctrine, not prices).** Opus is only a **small multiple of sonnet**, so a
  single scoped opus call is cheap insurance; **fable is a large multiple - it is the tier to guard**, not
  opus. This logic holds for any pricing with that shape; the live per-MTok numbers are a volatile vendor fact
  kept in the operator manual (`${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/kit-config.md`, absent under plugin-path installs -
  only the flat installer creates it), not here - re-check the RATIOS there if present and list pricing
  shifts materially. Effort is the secondary lever.
- **The escalation ladder and scope matrix are the Spawn Contract above** - that is the every-spawn
  decision. The rest of this skill (including the bullets here) is cold reference.
- Workers stay dumb-and-fast by design - give them exact instructions, not problems to solve.
  `advisor` answers one bounded question or drafts one bounded plan; `reviewer` curates a SET.
- The **Lead is GUI-configured** - never pin its model/effort from files. v4's recommended panel
  setting is **Sonnet @ high** (interface-band default); dial effort up for synthesis-heavy stretches, or
  set **Opus (reasoning-band)** for an architecture/doctrine session (see Lead capability-band). Setting
  **Fable** puts the Lead at the TOP of the reasoning band, where the cost qualifier bites: expect to delegate
  bulk reading rather than do it, or the session is expensive for no capability gain. The panel
  stays authoritative; the kit only configures and verifies the sub-agents.

## Lead capability-band - the per-session dial (choose up-front, hold for the session)
The Lead's model is not a fixed default; it is a per-session **capability BAND**, a human GUI dial set at
session start by work-class. Written model-agnostic (ids drift):
- **Interface-band Lead** (below the thinking ceiling; today Sonnet - the v4 default): reaches **DOWN**, buys
  capability per-call from the Advisor. The standing cheap-Lead mode above.
- **Reasoning-band Lead** (at the ceiling; today Opus **and above - fable is reasoning-band, not a third
  band**): already HOLDS the capability, so it reaches **OUT** for independence (cross-lab / fable) +
  context-protection - a *different* mind, not more reasoning.
  - **Cost qualifier at the TOP of the band (today: a fable Lead).** Band is the direction of REACH; it says
    nothing about price. At the top of the reasoning band the scarce resource is no longer capability, it is
    **context and per-turn cost** - the band's "answers in-context" trade is *tokens for latency*, and a
    top-of-band token is a multiple of opus on **every turn of a growing context**. So a top-of-band Lead
    reaches out on BOTH axes at once: **DOWN for mechanical volume** (bulk reads, greps, transcript sweeps,
    inventories) and **OUT for independence**, holding only **synthesis, the trust-class verdict, and the
    gate** in its own context. The counter-intuitive consequence: its trivial-work whitelist **SHRINKS**.
    `SC-1.4` lets a Lead self-handle read / search / grep because at interface band a read is cheap; at the
    top of the band a bulk read is the most expensive act in the session. **There, delegate by TOKEN VOLUME,
    not by difficulty** - hand off work you are entirely capable of, precisely because you are the wrong tier
    to spend tokens on it. (A one-line edit you can verify by eye stays self-handled; volume is the trigger,
    not judgment.)
- **Metering has a cost the dial must weigh:** routing DOWN means brief -> blind spawn re-reads context the
  Lead already had -> return -> verify (round-trip latency + redundant token reload). A reasoning-band Lead
  answers in-context. So on a reasoning-heavy session the interface-band's per-token savings can be offset by
  latency + re-reads - part of why the dial exists.

**Selection rule (class-proxy, decidable at session start):** default interface-band; choose reasoning-band
from the START for *architecture / doctrine synthesis* or an *anticipated deep empirical hunt the Lead must
own turn-over-turn* - continuity/ownership of the reasoning, NOT raw hardness (a hard *bounded* question stays
interface-band + Advisor). A forgotten dial just runs interface-band + boundary-correction: a safe default.

**Band-aware at runtime, agnostic in doctrine.** The Lead reads its own model line (trustworthy for the VALUE,
not for narrating a CHANGE) and maps to a band via the per-host `model -> band` boundary; that map drifts, so
it is probed and owned as a host fact (see HOST-2), with an unknown / aliased / new model resolving to the
conservative interface-band.

**Correction ladder - a mid-session switch of the LEAD's own model is not on it (2026-08-30, corrected).**
"Lossless" was the wrong frame: a mid-session switch re-reads the FULL transcript, wrong turns included, so
the new model inherits whatever misled the session instead of fixing it - fidelity to a poisoned transcript is
the bug, not a virtue. In order:
1. **Pick the right band up-front** (above) - avoid needing correction at all.
2. **Session fork/branch, if this host supports it** (probe, never assume - not universal, absent on some GUI
   hosts) - retry from before the bad turn. The only mechanism that is actually clean.
3. **A higher-tier agent call via a Lead-authored brief** (Advisor/Boss) - a curated distillation, not a raw
   transcript replay. Unsound only if an EARLIER spawn was already briefed on the SAME assumption now
   suspected - a fresh call re-inherits it through the Lead's own brief, and that case needs rung 4. A prior
   spawn on unrelated work does not disqualify this rung (the Boss itself exists for exactly the case where
   prior dispatches already happened - see BOSS-1/SC-1.3, this rung must not outrank that circuit-breaker).
4. **Session-boundary restart** (fresh session on a *distilled* `RESUME_SESSION.md`) - lossy but genuinely
   clean, works on every host. The reliable fallback when 2 and 3 are unavailable or already spent.
A mid-session switch of the Lead's OWN model is dropped from the ladder entirely - never reached for or
suggested by the Lead. If the human does it anyway that is their call; the Lead should not react to its own
system-prompt changing as if something broke.

**The band flips only the Lead's default REACH** (down for capability vs out for independence); every other
tier/mechanism is invariant. Its *benefit* shipped as a stated ASSUMPTION on a kill-switch trial; that trial
is **CLOSED (2026-08-30)** - the dial stays, the tally methodology does not. Verdict and reasoning: MAINT-6.

### Trust taxonomy - the verdict-owner + the three authorities
The trust-class DEFINITION (touches security / architecture / hard-to-reverse) and the conservative
"unsure -> treat as in-class, never let the weak link under-classify past the gate" default are owned in the
hot core (see SC-1.1, SC-1.6). This section owns the two things the hot core only names - the concrete verdict
owner and the three authorities:
- **Who concretely owns the verdict:** a **reasoning-band AND Claude-strong** tier - concretely a **Claude opus
  or fable tier**, whether that is a reasoning-band Lead or an opus Advisor/Reviewer/Boss it routes the verdict
  to. Band is not provider: Codex and every non-Claude tier only GENERATE inputs, they never own this verdict
  regardless of their own strength; an interface-band (sonnet) Lead does not own it either and routes it out to
  an opus tier.
- **Three distinct authorities - do not conflate them:** the **safety verdict** (is this trust-class artifact
  sound?) is produced by a Claude opus/fable tier; the **adoption decision** (do we act on it?) is owned by the
  **Lead**; an **override** is owned by the **human**, invoked only on a **material conflict** (`see SC-1.3a`) - a disagreement
  over trust classification, ship / no-ship, or required remediation, not merely two reviews surfacing different
  findings. That material-conflict bar is exactly what the cross-lab provider-disagreement rule trips on (see
  XLAB-8): a genuine disagreement over classification or ship-decision, not any divergence of findings.

## Project extension + self-maintenance - the MAINT card
Extending the tiers to a project (the 3 layers: global agents, the L2 `tier-project-brief`, L3 prefixed task
agents) and the kit's own self-maintenance split (worker learnings vs Lead-solo `MEMORY.md` curation; contract
changes via DEF-DELTA) have ONE owner: the **MAINT card** (`cards/MAINT.md`). It loads when wiring the project
layer or editing a definition, not on an ordinary spawn.

Rationale worth keeping in view (the rules live in the card, cited):
- The project layer extends the tiers through a `skills:` hook rather than agent copies, so the brief stays
  single-source and a name collision cannot silently shadow a tier; the mechanics are MAINT-1.
- Definition changes route through DEF-DELTA + the def-version staleness protocol instead of self-edits - that
  is what stops a stale definition from silently running; the procedure is MAINT-3 and MAINT-2.

## Boss - the stuck circuit-breaker (rare, human-gated)
The Boss mechanism has ONE owner: the **BOSS card** (`cards/BOSS.md`), loaded on dispatch from the recovery
ladder (`SC-6.3` "stop + ask" offers the Boss gate) and the spend ladder (`SC-3.1`, rung 3). An ordinary spawn
never pages into it.

Rationale worth keeping in view (the rules live in the card, cited):
- The Boss's value is independence, not more strength: a different model on a clean framing sees what the
  looping Lead can't. It fires after Workers/Advisor, on what they produced (see BOSS-1 for the fire-it/don't test).
- It runs on distilled context and never gathers - its fuel is the `ATTEMPTS.md` log captured at each
  check-stop (see BOSS-2), and it bounces a brief that lacks the attempt log + hypothesis (see BOSS-3).
- Every Boss spawn is gated and runs a model different from the Lead's for real independence (see BOSS-3);
  the Lead still owns adopting the verdict (see SC-6.2).

## How per-agent model/effort resolves - the HOST card
How a spawn's frontmatter `model:`/`effort:` actually resolves is GUI-specific (frontmatter-override behavior,
the `CLAUDE_CODE_EFFORT_LEVEL` pin, `$CLAUDE_EFFORT` for worker-effort verification) and has ONE owner: the
**HOST card** (`cards/HOST.md`, see HOST-1). `/agent-tiers:init` runs the probe and records the resolved answer
in `.claude/agent-tiers.local.md`; a spawn inherits those values.

## Dynamic model/effort -> the ROUTE card
The tier table gives each tier a DEFAULT model/effort. The **scope matrix** (Spawn Contract step 2 ROUTE, top
of skill) is the every-spawn decision. The rationale behind it - the five routing axes, the per-spawn model /
effort override levers, the routing doctrine that keeps a cheap Lead from under-thinking a hard shape, and the
band nuance on the verify tiers - has ONE owner: the **ROUTE card** (`cards/ROUTE.md`), see ROUTE-1 to ROUTE-5.

## Cross-provider handoff - Claude manages, Codex writes/reviews (per-host)
The cross-provider machinery has ONE owner: the **XLAB card** (`cards/XLAB.md`). It loads on dispatch, not on
every spawn - `SC-3.1` (spend), `SC-3.2` (disclosure), and `SC-5.3` (egress preflight) all point to it, so an
ordinary native-Claude spawn never pages into it. It is a card and not inline hot core because Codex is an
exceptional mechanism (a second lab, generate-only): its rules would be dead weight on the ordinary spawn checklist.

The rationale worth keeping in view (each normative statement lives in the card or the hot core, cited - never
restated here):
- The provider split is two orthogonal axes, not a per-tier cross-product: native Claude tiers own reasoning +
  the verdict; two thin least-authority brokers (`codex-write`, `codex-read`) own the write/read generate paths
  (see XLAB-1). Codex is generate-only, so a verdict-owning per-tier copy would be the wrong shape.
- Codex output is delegated + unverified, so it inherits the same isolation and review-pass rules as any
  delegated writer (see SC-5.1, SC-5.2) plus the cross-lab specifics (see XLAB-2, XLAB-3).
- The trust split - generate liberally, but a Claude-strong tier holds the verdict, and provider disagreement
  routes to the human - is the cross-lab face of the trust taxonomy (see XLAB-8, SC-6.2).
- A Codex session resumes by explicit session-id, spend is classed by the actual codex invocation, and each
  send is gated for disclosure (see XLAB-4, XLAB-9, XLAB-10 and the hot SC-5.3 preflight).
- Availability is per-host, consents are per-session and independent, and the model/effort x brief-specificity
  knob is the Lead's (see XLAB-6, XLAB-7, XLAB-11). The review path has a programmatic and an interactive
  entrypoint to one seam (see XLAB-12).

## Escalation briefs - ONE shared template (universal seam)
The brief requirement itself is the hot rule (see SC-4.1); this section owns the shared TEMPLATE and its
consumer deltas. Why it earns a section: the brief IS the cost control - a tight brief lets a cheaper tier
clear the job (the Codex 2-D model/effort x brief-specificity rule, see XLAB-11, applies to Claude tiers
equally). Three real consumers (Advisor asks, Boss briefs, Codex handoffs) now share ONE template,
`${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/templates/escalation-brief.md`: goal . facts gathered (paths cited) .
attempts with results (or point at `ATTEMPTS.md`) . the ONE question / acceptance criteria .
constraints . out-of-scope. Consumer deltas: Advisor gets "the ONE question"; the Boss delta (attempt log +
current hypothesis, bounce rule) is owned at BOSS-3; Codex gets acceptance criteria + touch-only scope.
`codex-handoff-brief.md` is retained as a pointer to the shared template. The template is the FLOOR, not the
thing that makes a cheap tier clear the job - for a review spawn, the MODE below carries most of the load.

### Review-mode delta - pick the mode by artifact MATURITY, not by stakes
- **Move-shaped change (text relocated, not rewritten): put the BEFORE-state in the brief.** A read-only
  Reviewer cannot run `git show HEAD~1`, so "nothing deleted" is only inferable from the after-state; attach
  `git show HEAD~1 -- <files>` (or the diff) into the brief text. Cheaper than granting Bash and keeps the tier
  read-only. Standard from 2026-08-16 (T3.1: the pass reported "inferred, not verified" for exactly this).
A review brief's mode decides what the reviewer can possibly return, so it is chosen, not defaulted:
- **New / unreviewed work -> ADVERSARIAL.** "Attack it; assume the obvious critiques are already in it."
- **Converged work (already reviewed once and corrected) -> CLAIM ADJUDICATION.** Numbered claims, one verdict
  each from `CONFIRMED` / `REFUTED` / `UNVERIFIABLE`; **evidence MANDATORY for REFUTED** (an unevidenced
  REFUTED is discarded - return UNVERIFIABLE instead, which is a respectable answer); plus an explicit line
  that **returning zero refutations is a valid and expected outcome**, and a matching "do not defer either."
- **An adversarially-briefed reviewer CANNOT return empty** - the brief manufactures the findings. If you need
  "empty" to be a possible answer, change the **BRIEF**. Not the model, not the effort.
- **Escape hatch, mandatory on any claim list:** end with two free-form slots - *"which claim are you least
  confident in, and why"* and *"what is missing"*. A per-claim verdict cannot express **"true as stated, but
  the artifact draws the opposite conclusion from it"**; the reviewer will correctly answer CONFIRMED and the
  error ships. That slot is what catches it.
- **Stopping rule: stop when the MODES are exhausted, not at a round count.** A further round pays only if it
  applies a mode the artifact has not had (adversarial -> adjudication -> internal consistency -> editorial).
  Re-running a mode the artifact already survived buys noise. A consistency pass is briefed to check ONLY
  internal coherence - forbid fact-checking explicitly, or it silently becomes a worse adversarial pass - and
  asks the reviewer to **report its coverage** ("I enumerated N cross-references and checked all of them"),
  which is what distinguishes an exhaustive pass from a sampled one.
Every mode above still carries a planted control (`SC-4.2`).

## The check-in line
The check-in requirement + return-placement are the hot rule (see SC-6.4); this section owns which of its
fields `name . tier . model . effort . def-v<N>` are DECLARED vs runtime-VERIFIABLE - miss that and the
check-in becomes a rubber stamp:
- **model = DECLARED** (restated from the brief - an agent CANNOT introspect its own live model). To verify the
  REAL model, read the harness transcript where the host exposes it (per-host - see `.claude/agent-tiers.local.md`).
- **effort:** Workers read the REAL effort from `$CLAUDE_EFFORT`; read-only agents report the declared value.
- **def-v<N> = runtime-VERIFIABLE against disk** (compare the quoted stamp to the canonical file - the
  staleness check, see MAINT-2).

## ⚠️ Check-in-return gotcha (portable technique)
The Agent tool returns only the agent's **FINAL** message. An opening check-in line does NOT survive back
to the Lead if the agent runs ANY tools afterward. So the check-in must be **repeated as the first line of
the FINAL return** (the kit's `advisor`/`worker` already do this). A live GUI panel still shows it streaming.

## Lifecycle - staleness, curation, change management - the MAINT card
The 3-layer artifacts (agents, briefs, memories, RESUME, plan docs) drift and bloat if unmanaged; the MAINT
card owns the lifecycle rules. Rationale worth keeping in view (cited):
- A watcher lag means an edited agent file is not immediately live, which is the whole reason the def-version
  check exists; the protocol is MAINT-2 (dispatched from SC-6.4).
- Drift and bloat are detected read-only (`/agent-tiers:doctor`) and fixed under gates (`/agent-tiers-gc`); the
  gc guarantees, thresholds, resume-injection throttle, and manual controls are MAINT-4.
- The add / remove / promote lifecycle, VCS disposition, and per-artifact ownership are MAINT-5.

## Evaluations
Three manual scenario+rubric evals for the hot rules this doctrine's own measurements flag as fragile
(the hunt counter, the gap-check/discovery briefing split, the SC-5.2 review gate):
`${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/evaluations/`. Paste-and-grade, not scripted - see that
directory's README for why.

## Companions (optional power-ups)
Two optional external companions amplify the kit - the **agentsview** session ledger (verify/diagnose a
sub-agent's real run: tools, timings, usage) and the **Codex cross-lab** layer (the write path + dual-lab
review, see the XLAB card). Both opt-in, both degrade gracefully; the kit works standalone. See the README
Companions section for setup pointers.

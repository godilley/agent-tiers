---
name: agent-tiers
description: >-
  v4 delegation doctrine: the Lead/Worker/Advisor/Reviewer/Boss tier vocabulary, driven by a Lead on
  any model (its capability band sets how it delegates) that routes, briefs and verifies while
  intelligence is METERED - bought per call at the cheapest tier that clears the job. Owns the every-spawn Spawn Contract, the Lead capability-band
  dial, the scope matrix and per-spawn model override, the escalation ladder, cross-provider handoff with
  the generate-vs-verdict split, review modes and planted controls, and the agent check-in line. Use when
  delegating to a sub-agent, deciding which tier or model fits a task, briefing a review or fan-out
  audit, routing work to another provider, or when a session is genuinely stuck.
---

# Agent tiers v4 - Lead / Sublead / Worker / Advisor / Reviewer / Boss
*doctrine-v32 c=4027606369-45092 - bump on every normative edit (see MAINT-2); quote it when a review or return leans on these rules.*

**v4 doctrine: the Lead routes and decides; intelligence is metered.** The Lead converses, routes,
writes tight briefs, verifies returns, and gates; work it need not hold itself is bought per call from
the tier that fits it (for an interface-band Lead that includes deep reasoning) instead of ground out in
the Lead's own (context-heavy, every-turn-billed) context. The Lead still owns project knowledge, synthesis, and every final decision - never delegated.

## The Spawn Contract - the every-spawn checklist (READ THIS; everything after is cold reference)
Six steps, every spawn, in order. Route by task SHAPE, never a self-judged "hardness" gut-call (a weak
Lead's blind spot is not knowing what it doesn't know - so shape is the trigger, not a feeling).

**Copy this block into your working notes for any spawn that isn't on the SC-1.4 trivial-work whitelist,
and check items off as you clear them:**
```
- [ ] 1. CLASSIFY - trust-class? disclosure-sensitive? any tripwire? (SC-1.1-1.6)
- [ ] 2. ROUTE - shape -> tier + band, per the scope matrix (SC-2.1-2.2)
- [ ] 3. AUTHORIZE - spend rung / disclosure gate / irreversible-action gate / wave lease (SC-3.1-3.4)
- [ ] 4. BRIEF - shared template, self-contained, gap-check vs discovery split, liveness control if a review, recall seed per SC-4.2c (SC-4.1-4.2c)
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
    the count once, a 2nd trip after a return is BOSS-1's stop-and-ask; evidenced 2026-08-06): unpacked below.
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
| Converse, route, brief-write, verify, light synthesis | Lead | any (GUI-set, never file-pinned; band per Lead capability-band) | high |
| Rote scripted procedure (log scrape, db query, scripted deploy) | L3 task agent | **haiku** | low |
| Mechanical with some judgment (build+verify, refactor-by-rote, gates, PR-prep) | Worker / L3 task agent | sonnet | low-medium |
| Fan-out research / audit first pass | worker / auditor / Explore | sonnet | low-medium |
| Deep reasoning: design, plan, tricky-debug hypothesis (ONE bounded ask) | Advisor | opus | high |
| Curate a set of cheap audit drafts | Reviewer | opus | high |
| Lead one independent slice of a larger task over its own children (GATED, `[sublead-approved:<why>]` tag) | Sublead | opus | high |
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
  a 2+ Explore fan-out under an opus Lead IS a rung-3 opus fan-out - pass `model: sonnet` (the scope
  matrix's own row for it) or gate it. A `sublead` spawn is rung 3 too (an opus coordinator plus its
  own children), and so is a `transcript-miner` (a project-defined coordinator of the same shape; the
  kit does not ship one); task-spawn-guard Rule D gates both alike: the Lead is asked unless
  the prompt carries the `[sublead-approved:]` tag, a subagent caller is denied, and neither may spawn
  general-purpose. N of them in parallel are one named wave under SC-3.4.
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
goal; facts gathered + paths; attempts WITH results; the ONE question / acceptance
criteria; constraints; out-of-scope. Record requested model/effort in the spawn record as declarations, not runtime proof.
The shared identity-evidence contract at SC-6.4 governs reporting and verification.

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

`SC-4.2` **Planted control = a LIVENESS check - any fan-out REVIEW whose findings you will act on.** Seed the
brief or target with one claim or defect you have **already verified**, formatted identically to the uncertain
items and **unmarked**. Expect a catch rate near 100%: a catch proves the reviewer READ that region, nothing
more, and a miss discounts its other refutations. A caught control does **not** earn the other verdicts -
recall is a separate instrument (SC-4.2c). **Prefer a real known one-read item over an invented one** - nothing
to remember to remove; a known real defect that takes reasoning to find is worth more as a recall seed
(SC-4.2c). Record the controls in the chat before spawning so they cannot ship by accident.
Necessary, not sufficient, for `SC-6.1` tier (c): it grades attention, never judgment. (Review-MODE shape: see
Escalation briefs.)
  - `SC-4.2a` **"Discounted" means re-verify its evidence-bearing claims against the primary source and drop its
    unevidenced judgments** - NOT "disregard the return" (unpacked below).
  - `SC-4.2b` **A caught control proves liveness, not recall:** every one-read class is caught by any reviewer
    that opens the file, so ONE control per brief is enough, placed in the region most likely to be skimmed
    (coverage, not difficulty). A near-100% liveness catch rate is the expected reading (unpacked below).
  - `SC-4.2c` **Recall needs a defect the reviewer must reason to find, seeded in the TARGET, never named in the
    brief.** Any review: a **held-back real defect** when one is already known and verified. Top-stakes
    (the `SC-1.6` list) with none to hold back: **mutation seeding** - a Worker applies one to three mutations from
    the fixed list (unpacked below) in a scratch copy; the Lead materialises the diff FROM that copy and
    briefs that copy's paths, so diff and files agree; the mutated copy is never a merge source. A recall
    miss means the review MODE is short: add a mode or axis (an execution pass), not a re-run. Two-reader
    capture-recapture is a lower bound only (unpacked below).

### 5. ISOLATE / EXECUTE - contain writers + gate cross-lab egress
- `SC-5.1` **DELEGATED writers run isolated:** `codex-write` and worktree-parallel writers write in an **isolated
  worktree/branch, NEVER the live checkout** (`codex-write` ALWAYS, no exception). TWO carve-outs, both native
  Claude only: (i) the Lead's own whitelist-qualified trivial edit in the live checkout (step 1); (ii) a single
  signed-off Worker on a well-specified live-tree slice (no parallel writer, revert-on-failure per step 6
  quarantine). No deploy / external action from a writer; the Claude gate runs before any merge or production execution.
  **A worktree is NOT whole-repo isolation:** worktrees share one `.git`, so `refs/stash` is repo-wide
  (`git -C <any-worktree> rev-parse --git-path refs/stash` resolves to the SAME file). **Ban `git stash` in a
  parallel-worker brief** (not git generally - `add`/`commit`/`diff`/`status`/`log` are worktree-scoped); for
  "compare against the unmodified version" brief `git show HEAD -- <file>` or a plain file copy (unpacked below).
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
  the pass at its own depth; an interface-band Lead never may (it cannot grade a deep call at its own depth).
  **The argument that will occur to you and is wrong:** "another pass is low marginal value here" is a statement
  about the diff you have ALREADY reviewed, never about the diff you are about to author - a review obligation is
  discharged against an artifact, and does not carry to the next one. Codex output is never solely Codex-reviewed.
  Measured, not asserted: across 140 sessions and 6 weeks this rule fired in **2.1%** of sessions and did not move
  as the doctrine grew, which is why `authorship-record` exists as a hook rather than a seventh restatement here.
  Arrival event: `review-gate-guard` (PreToolUse `ask`, once per session per repo, when the transcript holds no
  reviewer / advisor / codex-read spawn) at the ship point set per repo by `review_gate:` in
  `.claude/agent-tiers.local.md`: `commit` (default) gates commit plus push / PR, so a worker there does not
  commit; `push` lets every caller commit and gates push and PR only. Never set `push` in a repo that does not
  push (it would gate nothing). Under `/unattended on` the ask arrives as a deny carrying its remedy (spawn a
  reviewer, retry). A subagent caller (a worker's own commit, or any push) gets that deny whether or not
  the session is unattended, worded at the subagent: stop and report it to the top Lead (a Sublead passes it
  up unresolved), never spawn and retry. Ungated: merge / rebase / cherry-pick / pull, aliases, env prefixes
  and script wrappers (`worktree.sh down --merge` pushes inside a script), so a silent guard is not proof of
  a review. Opt-in (the Commit review group; flat install: `install-flat.sh --with-review-gate-guard`); the full ungated list
  and the measured prose-only violation rate are unpacked below.
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
  non-Claude provider first STOPS and loads the XLAB card; then this preflight runs before the send: (1) workspace
  sensitivity and OWNERSHIP - unknown sensitivity STOPS the send; name whose code it is (the user's own, or not:
  a client's or anyone else's - an employer's, a collaborator's, vendored proprietary code) and whether the
  owner's terms allow sending it to that lab - unknown ownership: ask the user, and their answer settles
  ownership (nobody to ask: treat it as not the user's own). Ownership follows the content's origin, not the
  directory it is sent from (relocating per SC-5.3a does not change it). (2) name the exact files/diff being
  sent; (3) scan for secrets / credentials / private data; (4) minimize / redact to the minimum needed;
  (5) explicit consent - for code the user does not own, the user's consent cannot stand in for the owner's:
  what counts is the owner's terms or a permission the user relays from the owner, not the user's own view
  that it is fine; none stated -> stop here. In an unattended session, stop unless the user relayed the
  owner's permission or terms before the session went unattended (an agent's own reading of a LICENSE or
  contract file is not enough). Only a solo local repo of the user's own code, sent with their own authed
  account, stays lightweight (all five steps still run as quick self-checks - none skipped, no gate
  ceremony); the moment secrets are present -> fail closed, do not send.
  - `SC-5.3a` **The unit is the WORKING DIRECTORY, not the artifact you mean to send.** A clean document in a
    dirty tree is still a fail-closed: the provider reads the wider tree regardless of the brief. So the
    resolution is not only "do not send" - it is **RELOCATE**: copy the minimum artifact to an isolated dir
    OUTSIDE the repo, run there, and list that dir to confirm nothing else is reachable. Redaction shape when
    you relocate: see XLAB-10.
  - **Honesty about scope (the preflight's limit):** this preflight gates disclosure INTENT, not sandbox
    containment - `codex exec` can still read the wider tree, git history, and inherited env. That is exactly
    why the secrets case fails CLOSED (prohibit the send) rather than trusting redaction; for a clean solo
    repo of the user's own code the intent-gate suffices.
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
`SC-6.1b` **The decorative-CI trap - a gate you build, review or trust (a hook, a CI job, a Stop-check) must
clear 4 questions, not just run green:** (1) deterministic, or LLM self-grading (still self-grading when a
strict regex parses it)? (2) a real stop-the-line mechanism (a required check on the protected branch), not a
report that can be merged past? (3) can a failure be traced to the exact rule/spec clause? (4) does the spec
stay authoritative, not drift silently with the code? For this kit: LLM review stays advisory as an AUTOMATED
gate (exit codes are the gate); `SC-5.2`'s pass is kept off question 1 by INDEPENDENCE, and `SC-1.6`'s ROUTINE
carve-out is a disclosed residual overlap (the external example and the kit reading: unpacked below).
`SC-6.3` **Recovery ladder (the daily failed-worker case; track each move as you go):**
- **Accept** - return verifies clean -> done.
- **Repair** - small, well-understood gap -> resume the SAME agent ONCE with a corrective note.
  A send to a finished agent resumes it, so every `SendMessage` names its intent: `RESUME-OK` for a repair
  or new work, `NOOP-IF-DONE` for a mid-flight note (reply NOOP and stop if already finished).
  `simple-rules-guard` Rule F denies a send carrying neither.
- **Restart fresh** - context contaminated / agent looping -> NEW agent on a clean brief, do not resume.
  (Count it: after a failed repair this restart IS the 3rd execution attempt - Stop + ask fires FIRST.)
- **Re-shape to Advisor** - output reveals a reasoning task mislabeled mechanical (also the backstop for
  shape-misclassification) -> re-route as an Advisor ask, not another Worker attempt.
- **Partial return** - a worker stopped under its definition's Stopping rule: (a) an unsettled decision ->
  settle it and brief the remainder, not counted as an attempt; (b) a check it could not fix -> Repair or
  Re-shape on that check, counted; a run the harness cut off -> re-dispatch the remainder narrower, not
  counted; a stop citing anything else (size, effort, time) is a failed return -> Restart narrower, counted.
- **Quarantine** - a partial WRITER failed -> an isolated-worktree writer's output stays unmerged (inspect,
  salvage by hand or discard); a signed-off LIVE-tree Worker that broke the tree gets reverted before any retry.
- **Stop + ask** - count each EXECUTION attempt (the original + repair + restart = 3). BEFORE a 3rd attempt,
  STOP and surface the attempt history; the human authorizes ONE of: the Boss gate (circuit-breaker; load the BOSS
  card before spawning), a re-shape, or one final retry. This is the same threshold as the step-1 "3rd+
  attempt" tripwire (one counter, one action).

`SC-6.4` **Then:** repeat the agent's role/definition check-in (`name . tier . def-v<N>`) as the
FIRST line of its FINAL message. Keep model/effort out of the greeting. Apply the identity-evidence
contract in "The check-in line" below before reporting runtime identity; declarations are not proof.
After editing a definition, compare its returned `def-v<N>` to disk before trusting behaviour-dependent
results (staleness protocol: see MAINT-2). A matching stamp does not verify model or effort.

*Everything below is COLD REFERENCE - the Spawn Contract's unpacked bodies (long form + evidence of the hot
rules), the tier vocabulary, the capability-band dial, routing rationale (ROUTE card), cross-provider handoff,
lifecycle/gc. Read it when designing or changing the system, not on every spawn.*

## The Spawn Contract, unpacked - load cards/CONTRACT.md
Every "unpacked below" and "evidence below" in the hot rules above is in `cards/CONTRACT.md`: the long form,
mechanism and evidence of each hot rule, in sections keyed by rule id. Load it when a hot rule's mechanism or
evidence is in question, or to seed a recall review (SC-4.2c's mutation list lives there); not on every spawn.

## Policy cards - one owner per mechanism
Each card is the one owner of its rules; this table points, it never restates. Load a card on its trigger.

| Card | Owns | Load when |
|---|---|---|
| XLAB | cross-provider (Codex) handoff, XLAB-1 to XLAB-14 | before authorizing or running any cross-lab call (SC-3.1, SC-3.2, SC-5.3) |
| BOSS | the stuck circuit-breaker, BOSS-1, BOSS-3 | before a Boss spawn (SC-6.3 stop + ask, SC-3.1 rung 3) |
| MAINT | project layer, def-version staleness, gc, add/remove/promote, MAINT-1 to MAINT-10 | wiring the project layer, editing a definition, doctor/gc (SC-6.4) |
| HOST | per-host model/effort resolution and the model -> band map, HOST-1 to HOST-4 | resolving how a spawn's model/effort resolves; `/agent-tiers:init` records it |
| ROUTE | routing rationale and the Lead's own model, ROUTE-1, ROUTE-3 to ROUTE-6 | a non-obvious route, a fan-out's model/effort, who owns a verdict (from SC-2.1 via ROUTE-3) |
| MEMORY | deltas on the system prompt's memory spec, MEMORY-1 to MEMORY-5 | reference card, not dispatched: consult before writing or auditing durable memory |
| CONTRACT | no rule ids: the hot rules' long forms and evidence | a hot rule's "unpacked below" (stub above) |

XLAB is a card and not hot core because Codex is an exceptional mechanism: its rules would be dead weight on
the ordinary spawn.

`TIER-1` **The tiers and their tool surfaces.** Advisor and Boss are read-only; Reviewer is read-only
on code and returns its findings inline (its Write grant goes unused); Worker, Sublead and Lead write. The grant, not the prose, is what
enforces this - so a tier whose behaviour disagrees with this table is a mis-granted definition, not a
lapse in judgement. A Reviewer's full list is in its final message: persist it yourself if the next
step needs a file.

| Tier | Who | Model | Effort | Role | Tools |
|---|---|---|---|---|---|
| **Lead** | the main interactive session | **sonnet** interface-band or **opus (or fable)** reasoning-band, chosen per work-class - fable adds the top-of-band COST qualifier, not a third band (see Lead capability-band) | high | Converse, route, brief, verify, gate, synthesise, decide. An interface-band Lead does NOT grind high-reasoning shapes itself (see ROUTE-4). | full |
| **Worker** | `worker` / `<project>-worker` | sonnet (haiku if rote; **opus per-spawn** for clever code) | low / medium (opus clever-code spawn: medium-high) | Fully-specified mechanical jobs (build, search, transform, verify). Follows the brief; does not decide. | scoped (read/edit/write/bash - canonical: worker.md frontmatter) |
| **Advisor** | `advisor` | opus | high | Deep reasoning on ONE bounded question OR a bounded design/plan; returns a recommendation (or plan) + confidence. Never edits. | read-only |
| **Reviewer** | `reviewer` | opus | high | Curates several cheap first-pass audit drafts into ONE trustworthy list - cuts false positives, re-rates severity, dedups, ADDS what the cheap pass missed. Never edits code. | read-only, returns its list inline |
| **Boss** | `boss` | **different from the Lead** (opus for a sonnet Lead; fable if opus reasoning was already implicated) | xhigh | Rare, **always human-gated** circuit-breaker: delivers an independent VERDICT on a distilled brief when the Lead is stuck; the Lead still OWNS adopting it (the value is independence, not authority-transfer). Never gathers; bounces vague briefs. | read-only |
| **Sublead** | `sublead` | opus | high | Lead for ONE independent slice: cuts it into child jobs, briefs and routes them, verifies every return, hands one verified result upward. GATED (task-spawn-guard Rule D, `[sublead-approved:]` tag). Never pushes, deploys or deletes. | read/edit/write/bash + Agent, SendMessage (canonical: sublead.md frontmatter) |

- Cost levers (model first, effort second), dumb-and-fast Workers, and the GUI-set Lead: see ROUTE-6.

## Lead capability-band - the per-session dial (choose up-front, hold for the session)
`BAND-1` **The band is chosen up-front by work-class and held for the session.** A mid-session switch of
the Lead's own model is not a correction move (see the correction ladder below).
The Lead's model is not a fixed default; it is a per-session **capability BAND**, a human GUI dial set at
session start by work-class. Written model-agnostic (ids drift):
- **Interface-band Lead** (below the thinking ceiling; today Sonnet): reaches **DOWN**, buys
  capability per-call from the Advisor. ROUTE-4 is its standing operating mode.
- **Reasoning-band Lead** (at the ceiling; today Opus **and above - fable is reasoning-band, not a third
  band**): already HOLDS the capability, so it reaches **OUT** for independence (cross-lab / fable) +
  context-protection - a *different* mind, not more reasoning.
  - **Top of the band (today a fable Lead):** its trivial-work whitelist SHRINKS - delegate by TOKEN VOLUME,
    not difficulty; a by-eye one-line edit stays self-handled, and synthesis, the trust-class verdict and the
    gate stay in its own context (cost qualifier and the metering trade-off: see ROUTE-6).

**Selection rule (class-proxy, decidable at session start):** neither band is the default; choose reasoning-band
from the START for *architecture / doctrine synthesis* or an *anticipated deep empirical hunt the Lead must
own turn-over-turn* - continuity/ownership of the reasoning, NOT raw hardness (a hard *bounded* question stays
interface-band + Advisor); interface-band suits a session that is mostly routing and mechanical work. A
forgotten dial runs whichever band the GUI holds, under that band's rules, so routing stays correct; a
forgotten Fable dial is the cost case ROUTE-6 guards.

The model -> band map is a per-host fact (see HOST-2).
**Correction ladder:** a mid-session switch of the Lead's own model is not on it and is never reached for or
suggested by the Lead; if the human does it anyway, do not react to the changed system prompt as if something
broke. The four rungs (band up-front, session fork, Lead-briefed higher tier, session restart): see ROUTE-6.

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

## Escalation briefs - ONE shared template (universal seam)
The brief requirement itself is the hot rule (see SC-4.1); this section owns the shared TEMPLATE and its
consumer deltas. Why it earns a section: the brief IS the cost control - a tight brief lets a cheaper tier
clear the job (the Codex 2-D model/effort x brief-specificity rule, see XLAB-11, applies to Claude tiers
equally). Three real consumers (Advisor asks, Boss briefs, Codex handoffs) now share ONE template (the SC-4.1 template).
Consumer deltas: Advisor gets "the ONE question"; the Boss delta (attempts +
current hypothesis, bounce rule) is owned at BOSS-3; Codex gets acceptance criteria + touch-only scope.
`codex-handoff-brief.md` is retained as a pointer to the shared template. The template is the FLOOR, not the
thing that makes a cheap tier clear the job - for a review spawn, the MODE below carries most of the load.

### Review-mode delta - pick the mode by artifact MATURITY, not by stakes
`REVMODE-1` **A review brief states its MODE, and the mode is chosen by artifact maturity, not stakes.**
An adversarially-briefed reviewer cannot return empty; if empty must be possible, change the brief.
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
Every mode above still carries a planted control (`SC-4.2`); a review also carries a recall seed when one is known, and always at top-stakes (`SC-4.2c`).

## The check-in line
The check-in requirement and return placement are owned by SC-6.4. Identity reporting has one
shared contract for every provider, tier and adapter:

- **Requested (declared, unverified):** the native model selector or alias and requested effort,
  taken from the actual spawn settings where accessible. A brief is a declaration only. Definition
  defaults do not establish what a particular invocation requested.
- **Resolved:** a harness or adapter configuration record tied to this invocation. Keep its
  concrete model ID separate from the requested alias. Resolution is not backend observation.
- **Observed:** model/effort from harness-owned runtime evidence tied to this agent and turn,
  with the evidence source named. A provider response establishes only fields it actually reports.
  For a translating gateway, a rewritten client model label is not independent upstream proof.
- **Missing evidence:** label the corresponding field **unverified**. Read-only tiers do not gain
  tools or permission to obtain evidence; the Lead obtains it through the active adapter. Never
  promote a role name, greeting, brief, launch flag or frontmatter default into an observation.
- **Effort:** a nonempty `$CLAUDE_EFFORT` tool result is a Claude harness observation for that
  agent's current turn, not upstream confirmation and not model evidence. Other adapters use
  their native runtime records. Keep requested, harness and upstream effort distinct if they differ.
- **Mismatch:** report the discrepancy and stop relying on identity-dependent results until the
  Lead resolves it from runtime evidence. Do not edit a return to match the requested selection.
- **Definition version:** compare the returned stamp to the canonical file for staleness
  (see MAINT-2). This is separate from identity verification.

Example: `requested model=sonnet (declared); resolved model=gpt-6-sol (adapter record);
observed model=gpt-6-sol, effort=medium (upstream response for this child request)`.
Without the last record, observed identity remains unverified. The same distinction applies when
`opus` resolves to a concrete Claude model ID. A broker reports its own and its engine's evidence
separately. This contract defines reporting; it does not claim that an enforcement hook is installed.
Why the check-in must head the FINAL message (the Agent tool returns only that one): CONTRACT card, SC-6.4.

## Lifecycle - staleness, curation, change management - the MAINT card
Staleness protocol: see MAINT-2 (dispatched from SC-6.4); doctor and gc: see MAINT-4; add / remove /
promote and VCS disposition: see MAINT-5.

## Evaluations
Three manual scenario+rubric evals for the hot rules this doctrine's own measurements flag as fragile
(the hunt counter, the gap-check/discovery briefing split, the SC-5.2 review gate):
`${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/evaluations/`. Paste-and-grade, not scripted - see that
directory's README for why.

## Companions (optional power-ups)
Two optional external companions amplify the kit - the **agentsview** session ledger (verify/diagnose a
sub-agent's real run: tools, timings, usage) and the **Codex cross-lab** layer (the write path + dual-lab
review, see the XLAB card). Both opt-in, both degrade gracefully; the kit works standalone. See docs/extending.md
(Companions) for setup pointers.

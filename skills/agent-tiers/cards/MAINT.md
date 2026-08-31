# MAINT card - definition updates, staleness, gc, project-layer maintenance
*card-v10 c=4275117116-16238 - bump on every normative edit (see MAINT-2); quote it when a return leans on this card's rules.*

> **Single owner of the kit-maintenance machinery.** Load this card when adding / updating / removing a tier
> artifact, editing an agent definition, running doctor/gc, or wiring the project layer - dispatched from the
> Spawn Contract at `SC-6.4` (the def-version staleness protocol) and reached via `/agent-tiers:doctor` /
> `/agent-tiers-gc`. An ordinary task spawn never needs it.

**Contents:** MAINT-1 project extension (3 layers) . MAINT-2 def-version staleness . MAINT-3 self-maintenance
split . MAINT-4 doctor + gc . MAINT-5 add/update/remove/promote . MAINT-6 band-dial falsifier trial (closed) .
MAINT-7 numbers in doctrine . MAINT-8 measurement integrity . MAINT-9 guard-seam rule.

## MAINT-1 Project extension - the 3 layers (global tiers + project brief)
Tiers ship global and generic; a project extends them without duplication via one skill. There is no native
`extends` for agents - a same-named project agent *replaces* the global (no merge) - so the inheritance seam is
the `skills:` hook, not the agent file.

| Layer | Where | What |
|---|---|---|
| **L1 global tiers** | `~/.claude/agent-tiers/agents/*.md` | generic `worker`/`advisor`/`reviewer` bodies. Each declares `skills: [tier-project-brief]`. `worker` also `memory: local`. |
| **L2 project brief** | `.claude/skills/tier-project-brief/SKILL.md` | ONE per repo: build/test/verify commands + landmines + domain map. Preloaded into every tier via the hook. Absent -> graceful skip (tiers run generic, no error). |
| **L3 project task agents** | `.claude/agents/<prefix>-*.md` | wholly-new PREFIXED agents for repeated procedures; they also hook `tier-project-brief`, so env facts stay single-source. |

- **Why the hook, not a copy:** `skills:` injects the skill's full content at spawn, and works cross-scope (a
  global agent can preload a project skill). The brief lives in exactly one place and every tier + task agent
  picks it up. Keep the brief <= ~1-2k tokens - it rides on *every* spawn.
- **Names collide by replacement.** A project `.claude/agents/<name>` silently shadows a global `<name>`
  (precedence: managed > `--agents` flag > project > user; no merge). So never reuse a tier name for a project
  agent - always prefix (`repo-gates`, not `worker`).
- **`memory:` is worker-class only.** Enabling `memory:` auto-adds Read/Write/Edit - fine for `worker`, but it
  would break `advisor`/`boss` read-only enforcement. Don't add it to them.
- **Slow watcher on some hosts.** New agent files and frontmatter edits register only after the watcher refresh -
  seconds on the standalone CLI, up to minutes on some GUIs. Project skills hot-load fast. Don't rely on
  same-turn effect of an agent-file change; verify after a wait or next session (see MAINT-2).

## MAINT-2 Staleness protocol - `def-version` (kills the stale-definition landmine)
Editing an agent file does NOT take effect immediately - the host's watcher re-reads it only at a later message
boundary (seconds on the CLI, up to minutes in some GUIs), and a stale spawn silently runs the OLD definition.
So every agent body carries a `def-version: N` stamp and quotes `def-v<N>` in its check-in (`see SC-6.4` for
the check-in return):
1. Edit the canonical file -> bump `def-version` in the SAME edit.
2. The agent is now PENDING-REFRESH: assume every spawn runs the OLD definition until proven otherwise.
3. Before any behaviour-dependent use, spawn once and compare the check-in's `def-v<N>` to disk. Match -> live.
   Mismatch -> do not trust behaviour-dependent results; end your reply so the user's next message makes a
   boundary (or relaunch the host for a brand-new agent type). Mechanical file edits BY a worker don't need
   this (their job doesn't depend on the new stamp); behaviour changes do.

`/agent-tiers:doctor` greps every stamp; a live worker spawn confirms disk==live.

**The hot doctrine carries `doctrine-v<N>` under its title (added 2026-08-04), same bump rule.** A review
that says "I applied SC-5.2" could not previously name which SC-5.2 it read.

**Every stamp CARRIES the cksum of its own file** (`c=<sum>-<bytes>`, that line excluded), and
`lint-doctrine.sh` check 5 recomputes it: edit without bumping and the mismatch is mechanical. Repair with
`lint-doctrine.sh --stamp`. This exists because the bump was measured to be a memory test that failed -
on 2026-08-04 every kit obligation discharged by a PROGRAM was current (integrations ledger, symlinked
skills) and every one discharged by an agent remembering was stale (`def-v` 4/7/11; MAINT-6 itself shipped
without its bump, caught only by a review). Detection, not prevention: the obligation stands, but nothing
now depends on anyone noticing.

**Cards carry a `card-v<N>` stamp under the title - same bump-on-normative-edit rule, different purpose.**
Cards hot-load as skill content (no watcher lag), so there is NO pending-refresh protocol for them; the stamp
exists for provenance - an agent or report whose conclusions lean on a card's rules quotes the card-v it read,
so a later review can tell which revision was in play. Stamp introduced 2026-08-03 at card-v1; earlier card
history is untracked.

## MAINT-3 Self-maintenance - split policy
- **Learnings** (a flaky test, a build timing, a gotcha) -> the `worker`'s `memory: local` dir, which it
  maintains itself: concise `notes-<topic>.md`. `MEMORY.md` curation is a Lead-triggered SOLO task - never let
  parallel workers OR a second concurrent Lead curate it at once (write races): `MEMORY.md` curation assumes a
  single writer.
- **Contract changes** (procedure steps, frontmatter, brief content) -> an agent never edits its own
  definition. It returns one line - `DEF-DELTA(<agent-name>): <proposed change + why>` - and the Lead applies
  it, gated (AskUserQuestion). This also sidesteps the slow watcher: a self-edit wouldn't apply promptly
  anyway. The Lead edits the real kit path (agents are symlinks; refuse-through-symlink -> edit the canonical
  `~/.claude/agent-tiers/...` file).

## MAINT-4 Detect + curate - `doctor` (read-only) + `gc` (gated fixer)
`/agent-tiers:doctor` step 4d measures artifacts vs thresholds and emits `gc suggested: <areas>`.
`/agent-tiers-gc` is the FIXER: it proposes retire/merge/archive/dedup per area, gates each, applies only what
is approved, never auto-deletes, and never touches the personal `~/.claude/CLAUDE.md`. Two seams surface it
automatically: the SessionStart hook appends a one-line advisory when a threshold is breached, and the Lead
check-stops at checkpoint moments (pre-compact, after writing a memory, during init/doctor). Thresholds
(tunable, kept in sync across doctor / the hook / here): memory index >80 lines or >80 files - RESUME >70
lines - brief >4KB - agent `MEMORY.md` >150 lines - docs/plans >500KB.

The SessionStart hook also throttles re-injection: it injects the full `RESUME_SESSION.md` only when the
content changed or the last full inject was >10 min ago (a `clear` always gets full - context was wiped);
otherwise it emits a one-line "unchanged, not re-injecting" pointer. This stops the same 60-line handoff being
re-pasted on every rapid resume (measured: ~7-13x per session before the throttle). State (content hash +
timestamp + **session id**) lives in `~/.claude/agent-tiers/.state/<slug>.resume`. The session id is
load-bearing: while the state was project-keyed only (until 2026-08-04) two sessions on ONE repo inside the
window collided and the second was told "already injected" while silently receiving **no handoff at all**.
A missing or unusable session id now suppresses nothing - a redundant handoff is cheap, a lost one is not.

Manual controls: `/agent-tiers-resume [steer]` refreshes `RESUME_SESSION.md` on demand, steerable like `/compact
<steer>` (e.g. "pausing X mid-way for a read-only side task"). `/agent-tiers-hygiene` backfixes output-hygiene
artifacts (em/en dashes, invisible/control chars, curly quotes) in a project's existing files,
detect-then-gated-fix.

## MAINT-5 Change management - add / update / remove / promote
- **ADD** a project skill/agent/brief-fact only on a 2nd real consumer (universal-seams rule); one speculative
  use -> keep it inline in the Lead's prompt.
- **UPDATE** via DEF-DELTA (agent-proposed) or Lead-observed need -> gated apply -> def-version bump ->
  PENDING-REFRESH (MAINT-2). Tiny brief edits (typo/command) = show the diff, no formal gate.
- **REMOVE** only via `gc` with evidence (unused across sessions, superseded, proven stale). Never silent.
- **PROMOTE** project->global when the same pattern hits a 2nd project: generalise into a kit template / global
  agent (the superset), demote project copies to brief-fills. A fact passing *"true in a different repo?"* ->
  global memory / global CLAUDE.md. DEMOTE is symmetric (global thing, 1 consumer -> project).
- **VCS disposition** of every artifact = the user's `~/.claude/agent-tiers/kit-config.md` defaults if
  present, else kit defaults - overridable per project at init and recorded in `.claude/agent-tiers.local.md`
  `vcs_policy:` (`doctor` flags drift).
- **Ownership:** agent definitions = Lead only (gated + version bump) - brief = Lead (gated-lite) - Lead
  memories = Lead - worker `notes-*.md` = worker - worker `MEMORY.md` curation = Lead-solo - kit canonical files
  = Lead (edit `~/.claude/agent-tiers/...`, re-run `install-flat.sh` after any `commands/*` change).

## MAINT-6 Band-dial falsifier trial - CLOSED 2026-08-30
The Lead capability-band dial (see the hot skill) shipped as a stated ASSUMPTION on trial, not settled
doctrine. Closed here on the trial's own predicted fallback, not on renewed data.

**Honest mechanism statement (why this closes on cost, not a tally):** the tally was a MANUAL, append-only
log - nothing wrote it automatically, nothing enforced it. It never got appended to in practice - the append
competed with exactly the session moment it was meant to capture, and lost, every time: the exact
failed-to-run case this card predicted.

**Verdict: override the fallback's default, keep the dial, drop the tally.** The fallback's literal rule
(survive only if reasoning-band sessions are visibly cheaper per outcome) would CUT the dial - no cheaper-
per-outcome evidence exists, because no tally exists. Cutting anyway is deliberately overridden: a sonnet
(interface-band) Lead self-drives well now, needed correction mostly covers scope-creep and under-explained
asks, both now largely absorbed by the "universal seams over bespoke" rule (`delegation/SKILL.md` - a
recurring need graduates into shared doctrine instead of needing a stronger Lead to catch it fresh each
time) - but reasoning-band Leads remain a real, used capability for architecture/doctrine sessions (see the
selection rule under Lead capability-band), and cutting the dial to satisfy a metric that never ran would
delete working practice, not bad practice. Recorded as an override, not a pass.

What actually needed fixing was not whether the dial exists, but its CORRECTION mechanism: the "mid-session
switch is the fidelity-preserving escape hatch" claim was wrong (fidelity to a wrong-turn transcript inherits
the wrong turn, not a fix) - corrected the same day, see the correction ladder under Lead capability-band in
the hot skill.

No hard cut-date remains - this trial is concluded, not extended.

## MAINT-7 Numbers in doctrine - a design constant, a dated observation, or a command
A number in prose is one of three things: a **design constant** ("2+ live consumers", a schema version), a
**dated observation** ("2.1%, 2026-08-04, n=140" - it cannot move; the world moved, the observation did
not), or **current state**, which is never written as a value - it is written as the command that produces
it (`git rev-list --count`, `ls | wc -l`, `grep -c`). A recorded state number is a movable number frozen
in a doc: it reads as true after it stops being true, and nothing notices. Two 2026-08-16 shapes: a
"0 hits" grep result recorded in a review doc became `lint-doctrine.sh` check 6 the same day, because the
next guard author who typed one of those substrings would have proved the record wrong silently; and a
"8 guard fires per session" count had to be labelled *measured during guard development, not
representative* before it could be written down at all, or a one-week review would read any lower
number as an improvement. When you cite a number, say which of the three it is.

## MAINT-8 Measurement integrity - the method takes the articulation test before the number is cited
Before a derived number is cited, the MEASUREMENT METHOD is itself subject to the articulation test
(`see SC-1.3a`): name the ways *this* measurement can lie. Prefer deterministic tools; still check the
invocation, and re-derive a number that will be cited by a second method first. "Compute it with a
script" is not the fix - the 2026-08-06 figures came from deterministic tooling (an unreset accumulator,
a `\w+` regex dropping hyphenated tokens) and were wrong. Strongest case (2026-08-16): the kit's own
`guards.log` was promoted to *the* record of guard blocks and a `doctor` count built on it - and 163 of
its 163 lines were fixture noise, because the guards' selfchecks ran the real scripts in place and wrote
to the real log. The instrument was polluted by the measurer's own tests, and a count of "blocks" would
have been a count of the test suite. Ask "who else writes to this?" before you count it.

## MAINT-9 Seam rule - a guard needing logic another guard has SOURCES it, never copies it
One evidenced rule, no threshold table (the source rule, `delegation/SKILL.md`, demands a REAL recurring
need): a guard that needs logic another guard already has sources the shared library
(`scripts/guard-cmdpos.sh`) and does not copy it. Copies drift the day they are made. 2026-08-16, same
day, three shapes: (1) a second, narrower `tee` matcher written beside the shared one that had just
selected the segment - the two disagreed on a subshell-wrapped `tee` immediately (Wave B review); (2)
ten scripts each carrying their own copy of the log-rotation idiom, nine of them on `guards.log` sharing
one cap - so raising that cap was a nine-file edit; the tenth (`codex-home-isolate.sh`, its own log, its
own cap) was left alone on purpose. Derivation, run from the kit root 2026-08-17 (pasted, not paraphrased -
this is the FOURTH number in the chain: "twelve" was inherited from a review doc and never counted, "nine"
was counted but silently dropped the tenth, and the first version of THIS sentence carried a command,
`grep -l 'tail -n' scripts/*.sh`, that actually returns 12 because two unrelated files match; a command
that would produce the number is not the number):
      $ grep -l 'tail -n [0-9]* "\$LOG"' scripts/*.sh | xargs -n1 basename | sort | tr '\n' ' '
      authorship-record.sh codex-home-isolate.sh dangerous-actions-blocker.sh framing-guard.sh
      hygiene-commit-guard.sh kit-leak-guard.sh numeric-claim-ledger.sh review-gate-guard.sh
      security-gate.sh vcs-commit-guard.sh
      $ grep -h 'tail -n [0-9]* "\$LOG"' scripts/*.sh | sed -E 's/.*(tail -n [0-9]+).*/\1/' | sort | uniq -c
            1 tail -n 100        <- codex-home-isolate.sh, its own log
            9 tail -n 2500       <- the guards.log cap, moved together
  (MAINT-8's failure, in MAINT-9, in the same commit, then again in the fix); (3) `guard_hop`/`guard_cwd_unresolved` landing in the library once, so four commit guards changed
posture in one edit each. Older, same class: three hand-copied command-position anchors that
`sudo git commit` bypassed together (T1.2), and three copies of one quote-strip that bash 3.2 could not
parse (`guard_norm_add_paths`).

**This block is itself now stale, on purpose left uncorrected rather than silently edited** (external
review, 2026-08-24): `advisory-ack-guard.sh` joined `guards.log`'s family after 2026-08-17, so re-running
the same two commands today returns 11 scripts and 10 sharing the cap, not the 10/9 pasted above. That is
not a bug in this card, it is MAINT-9's own thesis firing again on its own worked example - the fix is to
re-run it, same as any other pasted number, not to trust either count.


# XLAB card - cross-provider (Codex) handoff
*card-v6 c=2855912847-25600 - bump on every normative edit (see MAINT-2); quote it when a return leans on this card's rules.*

> **Single owner of the cross-provider machinery.** Load this card before authorizing or executing any
> pass that invokes a non-Claude provider (dispatched from the Spawn Contract: `SC-3.1` spend, `SC-3.2`
> disclosure, `SC-5.3` egress preflight all point here). An ordinary native-Claude spawn never needs it.
> Rules a cross-lab pass already inherits from the hot core are NOT restated here - they carry a `see SC-x`
> pointer so the rule keeps one owner.

Claude manages, Codex generates. Codex is a GENERATE source only; every trust-class VERDICT stays with a
reasoning-band Claude-strong tier (`see SC-6.2`, and XLAB-8 below).

**Contents:** XLAB-1 agent structure . XLAB-2 write-path isolation . XLAB-3 unverified output . XLAB-4 resume
by session-id . XLAB-5 never fire codex from the Lead . XLAB-6 availability + circuit-breaker . XLAB-7 two
consents . XLAB-8 generate vs verdict . XLAB-9 spend rung . XLAB-10 disclosure guardrail . XLAB-11
model/effort ladder . XLAB-12 review path . XLAB-13 concurrency . XLAB-14 measure the blast radius.

## XLAB-1 Agent structure - two orthogonal axes, not a per-tier cross-product
The provider split does NOT duplicate the tier files (no `codex-advisor` / `codex-reviewer` / `codex-boss`).
- **Tier / role axis** (Lead, Worker, Advisor, Reviewer, Boss) = native Claude agents; they own reasoning and
  every trust-class verdict. Resumable warm via the harness (`SendMessage` continues the same in-context agent).
- **Provider axis** = thin brokers (Claude agents shelling out to `codex exec`), split by a least-authority
  boundary into TWO fixed-sandbox entrypoints, not per-tier duplicates:
  - `codex-write` = the WRITE path (`-s workspace-write`, isolated worktree per XLAB-2).
  - `codex-read` = the READ path (`-s read-only`, generate-only: review / adversarial-review / diagnose;
    never writes, never owns a verdict).
- Semantic purpose (implement / review / diagnose) rides in the BRIEF, not in duplicate agent files. A THIRD
  broker is added only on a real recurring need (universal-seams trigger), never a `codex-<tier>` per-role copy.

## XLAB-2 Write-path isolation and the pre-merge gate
`codex-write` isolation, the no-deploy-from-writer rule, and the gate-before-merge are the general
delegated-writer rules - `see SC-5.1` (isolated worktree/branch, never the live checkout; `codex-write` always,
no carve-out). This card adds only the cross-lab specifics:
- A clean tree gives *attribution*; the isolated worktree gives *containment* against deploy / hot-reload / hooks.
- Self-contained brief (Codex starts blind): the shared escalation-brief template - goal, exact files,
  constraints, acceptance criteria, out-of-scope (XLAB-11 sets the model/effort + brief-specificity knobs).

## XLAB-3 Output is unverified - it always takes a Claude review pass
Codex output is UNVERIFIED delegated work, and Codex never reviews its own code. The review-pass requirement
itself is the hot rule - `see SC-5.2` (any non-trivial diff takes an independent fresh-eyes pass, including
one the Lead authored itself; self-run only for an explicitly ROUTINE class). This is the cross-lab instance
of that rule, not a second copy of it.

## XLAB-4 Resume asymmetry - by explicit session-id only
`SendMessage` to a broker resumes the Claude WRAPPER (warm, in-context), but the Codex session underneath is a
separate resource: `codex exec` is one-shot and a fresh call is a NEW cold Codex thread. The Codex session is
resumable only by its explicit session-id (captured from the `thread.started` event), which the wrapper binds
to the task/worktree - a re-invocation with cold-start cost, not warm continuation, and not coupled to
`SendMessage`. So expect no warm stateful resume from a cross-provider agent; state carries only as far as the
wrapper re-threads it, and only by session-id. `codex exec resume --last` is banned: it picks the newest
session for the cwd, so any parallel Codex call resumes the WRONG conversation (context / disclosure
cross-contamination). No id -> start fresh with a full brief. Bind `task-id + codex-session-id + worktree +
disclosure-set` so a resume is unambiguous.

## XLAB-5 Never fire `codex exec` from the Lead. At all.
TWO distinct failure modes, ONE rule - the ban is on the Lead invoking codex directly, foreground or
background, briefed or throwaway.

**Mechanically enforced since 2026-08-04:** the `codex-guard` PreToolUse(Bash) hook (consent row,
`install-flat.sh --with-codex-guard`) DENIES any command-position bare `codex` - probes included - and
points at the ONE sanctioned entrypoint, `scripts/codex-run.sh`: non-exec subcommands (login status,
--version) pass through unscanned; `exec` runs a HARD-FAIL secrets scan of the `-C` tree (SC-5.3 step 3,
exit 3, deliberately no bypass flag; resolution = relocate per SC-5.3a). The brokers route through the
wrapper (`codex-read` def-v7+, `codex-write` def-v11+), so the guard cleanly separates sanctioned broker
traffic from a Lead slipping into a raw call. Anti-accident, not anti-adversary (indirection is not
chased); this prose stays the RULE the mechanism serves.

**(a) Foreground - the isolation bypass.** A direct foreground call **skips the `SC-5.3` egress preflight and
the broker's isolation discipline**, which is the entire reason the broker exists. **This includes throwaway
probes** - a model list, a version check, a connectivity test. The convenience of a one-off Bash call is
*precisely* when the discipline gets skipped, because the task feels too small to deserve it. (Proven
2026-08-03: a model-list probe fired with cwd set to a repo holding 13 tracked credential files, minutes after
the Lead had committed to never running codex in that repo. Blast radius was one path string **only because
the prompt happened to need no reads** - luck, not design. See XLAB-14 for the audit that established that.)

**(b) Detached background - the orphaning.** A bare **detached** background shell (`&`) is tied to the Claude
Code process, so a session/process teardown
orphans it: the work may finish and write its output file, but no completion notification arrives and it cannot
be resumed. Route it through the harness-tracked `codex-write` / `codex-read` agent, which owns + polls its own
background bash to completion per XLAB-13's run pattern (background-launch via `run_in_background`, foreground
bounded wait). Do NOT foreground the `codex exec` either - the Bash tool kills it at the 2-min default and the
10-min max cannot cover a high-effort run (see XLAB-13). (Proven 2026-07-23: a Lead-fired background `codex
exec` review completed on disk but lost its completion record across a session boundary - the salvage was
reading the `-o` file by hand.)

## XLAB-6 Per-host availability + session circuit-breaker
Codex is reachable wherever the `codex` CLI is on PATH and authed (probe via
`"${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/scripts/codex-run.sh" login status` - the wrapper passes probes through and
keeps the codex-guard hook quiet; bare `codex login status` is denied where the guard is wired); the desktop app is
not required. Availability is point-in-time per host - record it in `.claude/agent-tiers.local.md` (a probe at
SessionStart). On a host with no authed codex the routing never reaches for it. A failed Codex turn
trips a session circuit-breaker: suppress Codex for the rest of that session.

## XLAB-7 Two independent per-session consents (do not conflate)
1. **Write-engine preference** - "who writes code this session?" Codex is beta/flaky, so opt-IN; default Claude
   (worker / opus-worker). Ask once at the first real code task (not at session start); sticky per session id in
   `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/.state/session-prefs/<session-id>` (survives compaction via the SessionStart hook; a
   `/clear` re-asks). Stored per SESSION, never per repo. Failure -> Claude path for that task, pref unchanged.
2. **Cross-provider review consent** - "may Codex REVIEW this session?" Independent of (1): a session can review
   cross-lab without letting Codex write, or vice-versa. Its own default + fallback.

## XLAB-8 Generate vs verdict - the trust split and provider disagreement
Any provider may GENERATE code / findings / critiques - cheap, liberal, cross-lab (author lab A -> reviewer lab
B catches same-lab blind spots; frame it as a measured benefit routed by risk/cost/yield, not a universal
"near-free"). Who owns the VERDICT on a trust-class artifact is defined by the Trust taxonomy (`see SC-2.2`;
fail-closed if that owner is unavailable, `see SC-6.2`). This card owns only the cross-provider additions:
Codex is never the sole pre-ship security/architecture reviewer, and provider disagreement is surfaced to the
human, never auto-arbitrated between providers:
- On a **trust-class** artifact, a **material conflict** (disagreement over trust classification, ship /
  no-ship, or required remediation - not merely two reviews surfacing different findings) STOPS work for an
  explicit HUMAN decision; the Claude-strong verdict informs it but does not silently tie-break.
- On a **non-trust-class** artifact, the Claude verdict governs and work proceeds.

## XLAB-9 Codex-spend rung - classify by the actual execution resource
The step-3 spend ladder is the hot owner (`see SC-3.1`); this card owns the codex-specific classification.
Name the four resources "broker" used to conflate: the **wrapper** (the native Claude `codex-write` /
`codex-read` agent), the **plugin broker** (the `/codex` plugin's reusable process), the **codex session** (a
persisted Codex conversation), and a **codex invocation** (each CLI process start/resume). Classify by the
codex INVOCATION, not the wrapper:
- **Rung 2 (announce-only):** a read-only review reusing an already-live plugin broker foreground, and nothing else.
- **Rung 3 (gated):** any Codex write, any fresh `codex exec` invocation (including one a warm wrapper fires -
  the wrapper being warm does not lower its cold codex invocation to rung 2), any cold-broker or background call.
- State foreground/background per call so one invocation cannot fall into two classes. **Fail-closed on
  transition:** a rung-2 plugin-broker call that ends up cold-starting or backgrounding has changed mechanism -
  abort and re-gate at rung 3. **Degrade exception:** the Claude-strong verdict tier unavailable mid-session ->
  STOP, tell the human (`see SC-6.2`); never let the fast-shallow lab silently inherit a trust-class verdict.

## XLAB-10 Data-disclosure guardrail
A cross-provider call discloses repo content to the other lab; the categorical per-send gate is the hot egress
preflight (`see SC-5.3`, fail-closed - secrets present means do not send, regardless of repo). The cross-lab
guardrail this card adds on top: do not cross-lab-review a shared or sensitive tree; a solo local repo with
your own authed account and no secrets stays lightweight (SC-5.3 owns what that means: the steps still run, fast).

**Redaction shape when you relocate (`SC-5.3a`): SOFTEN the payload in place, never remove STRUCTURE.** Keep
every heading, number and cross-reference target verbatim and replace only the sensitive value
(`REDACTED-HOST`). A structural redaction (dropping a whole section) **manufactures false positives** in any
consistency or coherence pass and destroys the very graph the reviewer was sent to check. Tell the reviewer
redactions exist and that **a redaction is not a finding**. Verify structure survived before the send - grep
the heading / reference / question counts against the original, do not eyeball it. The intent-vs-containment reasoning behind the
fail-closed default (`codex exec` still reads the wider tree, git history, and inherited env, so redaction is
not trusted) is owned at the hot preflight (`see SC-5.3`).

## XLAB-11 Model/effort ladder + brief-specificity (the Lead decides - nothing auto-picks)
`codex-write` / `codex exec` passes model + effort straight through (`-m <id>`, `-c
model_reasoning_effort=<...>`); omit both and Codex runs on the host's configured default. There is no
task-difficulty heuristic, so match the call to the job:

| Task class | `effort` | `model` | Why |
|---|---|---|---|
| Trivial / mechanical (rote edit, boilerplate, rename-by-pattern) | `low` | a cheap tier | don't burn a strong model on rote work |
| Normal implementation (a bounded feature, a clear bug fix) | `medium` | omit (workspace default) | the default coding model is the right baseline |
| Review / diagnose (doctrine, text, small or well-scoped diff) | `medium` | omit (workspace default) | a review does NOT auto-earn `high`; start at `medium` and reserve `high` for a genuinely hard/subtle code review |
| Hard / clever / diverse (subtle algorithm, tricky concurrency, a subtle-code review, a genuinely different mind) | `high` | a strong coding tier | the whole point of the handoff is a diverse, capable coder |

- Concrete Codex model ids DRIFT per release, hard-coded nowhere in doctrine - read the workspace default from
  `$CODEX_HOME/config.toml` (`model =`; the config-read bullet below owns why probing is banned); recent-example
  ids are parked in `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/kit-config.md` if present (plugin-path installs don't ship
  it - only the flat installer creates it; without it, just read `$CODEX_HOME/config.toml` directly). When
  unsure, omit `model` and set only `effort` (levels `low`/`medium`/`high` are stable). Effort is the
  higher-leverage knob; reach for a model override mainly to go cheaper on trivial work or to pin a strong model
  on hard work.
- **Before promising anyone a "run it on the flagship" upgrade, READ `$CODEX_HOME/config.toml` for the
  `model =` line.** The workspace default is usually already the flagship, which makes the upgrade a no-op and
  the real levers `effort` + brief specificity (below). Read the file rather than probing: `model_list` is not
  reliably a CLI subcommand, and probing means an invocation, which XLAB-5 bans from the Lead anyway.
- **Two same-generation variants of one lab are NOT two labs.** Running both flagship siblings buys less
  independence than one Codex plus one Claude; if the pass needs the PROVIDER axis (XLAB-12), cross the lab.
- **Brief specificity is itself a knob, inversely coupled to model/effort.** A tight brief (exact files,
  concrete acceptance criteria, out-of-scope fenced, the one non-obvious gotcha named) does the reasoning up
  front, so a lower tier clears it; a loose/exploratory brief pushes that burden onto the model and needs a
  higher tier. The decision is 2-D: how hard is the problem x how much did the brief already pin down.
- Because the Lead reviews the output anyway, default to starting a rung LOWER and escalating: send a tight
  brief at the cheaper tier, review the diff against the acceptance criteria, and only bump `effort`/`model`
  (or iterate a sharper brief, resuming by session-id per XLAB-4) on the turns that genuinely need it. If you
  reach for `high` + strongest model, first ask whether a more specific brief is the cheaper, more reliable fix.

## XLAB-12 The review path - two entrypoints to one read-only seam
The `codex-read` agent (a briefed `codex exec -s read-only` run - the programmatic path the Lead spawns) and
the `codex` plugin (`/codex:review` breadth, `/codex:adversarial-review` pressure-test, `/codex:rescue`
2nd-diagnosis - the interactive path) reach the SAME read-only cross-lab seam; they are not competing
mechanisms. Both GENERATE findings that feed a Claude-owned verdict (XLAB-8), never replace it. Raw invocation
shape, documented so you can read what the broker runs - **NOT a Lead-invocable path, see XLAB-5**:
`codex exec - < brief.md -m <id> -c model_reasoning_effort=<...> -s <sandbox>`.

**Dual-lab review** = the concrete shape of the independent pass SC-1.6 already mandates for a **top-stakes**
trust-class change (security / auth / deploy / release / schema-or-data migration) or an unknown-class one:
fresh opus Advisor (same-lab) + `codex-read` (cross-lab), Lead synthesizes and owns the verdict (XLAB-8).

**"Dual-lab" means two independent READERS that differ on the AXIS that matters for the artifact - provider is
one axis, not the definition.** Choose the second reader's axis deliberately, because the wrong axis buys
nothing:
| Artifact / claim shape | Decisive axis | Consequence |
|---|---|---|
| **Code-grounded** claim (does this file really do X?) | **REPO ACCESS** | a reader that cannot open the file returns sound reasoning at UNCALIBRATED confidence. Give at least one half repo access. |
| **Domain-fact or judgement** claim (which version removed X? is this sequencing right?) | **PROVIDER** | a same-lab reader shares the author's blind spot and will ENDORSE the author's error. This is the case cross-lab exists for. |
| **Anything the reviewing party AUTHORED** | **AUTHORSHIP** (dominates the other two) | the author cannot be the fresh eyes at any band or provider, and a same-CONTEXT re-read is not a second reader. Minimum: a fresh-context spawn. Evidenced 2026-08-04 - a same-model fresh-context opus Reviewer found 12 real defects on a code-grounded diff that two reading passes, one cross-lab, had both missed; the axis that was missing was authorship, not provider. |
| **Discovery / gap-finding** ask (what is out there? what has no bucket in our vocabulary?) | **FRAMING** | a reader handed the target's own taxonomy returns only what that taxonomy can express, and then reports the gap CLOSED. Distinct from a same-lab or same-author blind spot, and NOT fixed by changing either. Brief one reader UNPRIMED - no kit names, no concept ids (`see SC-4.1a`, which owns the rule). The one axis the BRIEF alone buys: no second provider, no egress. |
| **Pure-text coherence** (contradictions, dangling refs, terminology drift) | none | two readers of any provenance converge. Do NOT pay egress for this pass. |
(Evidenced 2026-08-03 across three passes on one document: the repo-access half caught what the blind half
could not; the cross-lab half was the ONLY reader to challenge a version boundary its same-lab sibling
endorsed; on the pure-text pass both halves returned the same findings.)
(Evidenced 2026-08-06 on the framing axis: a fan-out primed with our own concept names returned nothing
outside them; an unprimed re-run of the same source returned three findings our vocabulary had no bucket
for, and an adversarial pass returned a STRONGER validation of the ladder than the primed pass could.)
`SC-6.1`'s tier-(c) reflex inherits
this: pick the AXIS first, then the reader - and where the axis is FRAMING, then the brief.
The default *for that population* - NOT every review; below top-stakes the pass is a single opus
Advisor/Reviewer (SC-5.2 - opus is already the different mind under a sonnet Lead). Graceful: no codex /
consent off -> the opus half alone gives fresh eyes under an interface-band Lead; under a reasoning-band
(opus) Lead the cross-lab half *is* the independence (a same-model self-review shares blind spots). Per-send
egress preflight (SC-5.3) still gates each send; a wave lease (SC-3.4) covers a named batch.

## XLAB-13 Concurrency - one shared `~/.codex`, isolated per Claude session
Codex keeps GLOBAL mutable state in `$CODEX_HOME` (default `~/.codex`): `state_*.sqlite`, `sessions/`,
`goals_*.sqlite`, `auth.json`. BOTH entrypoints share it - the `codex-write`/`codex-read` brokers
(`codex exec`) and the `/codex` plugin's long-lived per-cwd `codex app-server` (which also spawns a SECOND
direct app-server on `BROKER_BUSY`). So two concurrent codex runs across sessions/worktrees corrupt each
other's state and make `resume --last` pick the wrong conversation - the same shared-state root as the
`--last` cross-contamination XLAB-4 bans. A doctrine line an agent reads cannot fix this: two independent
sessions are mutually blind, so coordination has to be structural.
- **Fix (built + finalised 2026-07-25): per-Claude-session `CODEX_HOME`.** A global SessionStart hook
  (`agent-tiers/scripts/codex-home-isolate.sh`) sets `CODEX_HOME=~/.codex-homes/<session-id>` for the whole
  session via `$CLAUDE_ENV_FILE`, provisioning it: **SYMLINK both `config.toml` and `auth.json`** to the live
  `~/.codex` files. auth is symlinked (not copied) because codex writes auth.json IN-PLACE (open-truncate,
  verified via `--with-api-key`: the link survives), so ALL homes share one auth.json and an OAuth refresh
  (single-use token rotation) writes back to it - a COPY would 401 the other homes (`refresh_token_reused`),
  and `cli_auth_credentials_store=keyring` does NOT help (codex keys the keyring account by
  `sha256(CODEX_HOME)`, so per-home homes diverge). BOTH entrypoints inherit the home - the broker
  `codex exec` from the session Bash env, the plugin because `resolveCodexHome()` honors `$CODEX_HOME` and the
  app-server spawns with `env: process.env` (both source-verified). Per-session (not per-invocation) preserves
  resume-by-id continuity (XLAB-4). Hardening: session home is `chmod 700`; the session id is validated before
  it becomes a path; fail-open no-ops leave a breadcrumb in `~/.codex-homes/isolate.log`.
- **Manual / interactive codex is untouched** - the hook no-ops outside Claude Code (no `$CLAUDE_ENV_FILE` /
  session id) and there is NO global binary interceptor, so a bare `codex` in a terminal uses `~/.codex`.
  Applies in a plugin-ignoring GUI harness too (verified: the GUI fires `~/.claude/settings.json` SessionStart).
  Ceiling: a `codex logout` INSIDE a session home clears the shared auth (unsupported).
- **Residual - plugin broker reuse (accepted, documented).** The `/codex` plugin keys its long-lived
  app-server broker by cwd only (`state.mjs` `${CLAUDE_PLUGIN_DATA}/state/<slug>-<sha256(cwd)>`), NOT by
  session/`CODEX_HOME`. So two CONCURRENT Claude sessions in the SAME repo BOTH using `codex:rescue` attach to
  ONE app-server -> the 2nd runs in the 1st's home (context bleed); teardown has the same cwd-only gap. The
  `CODEX_HOME` fix does NOT close this, and an env-layer patch cannot: SessionStart hooks run in PARALLEL (no
  order contract) and the plugin re-exports the shared `CLAUDE_PLUGIN_DATA` at both start and end. Severity is
  now non-corrupting (wrong-home bleed, not global corruption). Operational rule: do not run two concurrent
  same-repo sessions both invoking `codex:rescue`. Clean fix lives upstream (sub-key the broker state by
  session + owner-guard); a local plugin edit is rejected (overwritten on plugin update).
- **Run pattern + output-file hygiene (brokers, def codex-read v6 / codex-write v9; two dual-xlab passes +
  transient-fixture verified 2026-07-29):** each `codex exec` is **background-launched** (`run_in_background`,
  never a detached `&`; capture the codex PID to a pidfile at launch) and **waited on in the FOREGROUND** by a
  bounded `for i in $(seq 1 50); do grep -q '^CODEX_EXIT=' STREAM && break; sleep 10; done` loop, re-issued (the
  WAIT only, never a 2nd codex call) to a total deadline. Never a backgrounded `sleep`/`until` (ends the
  wrapper's turn -> Lead `SendMessage` nudge, the 2026-07-29 churn), and NEVER foreground the `codex exec`
  itself (the Bash tool kills it at the 2-min default; the 10-min max cannot cover a high-effort review). The
  hardening the v4/v7 draft AND the v5/v8 first-fix both missed (each dogfood-caught): (1) **LITERAL printed
  paths**, never a cross-call `$var` (empty in a new shell -> `grep pattern ""` hangs) - B1; (2) an **exit
  sentinel** (`echo "CODEX_EXIT=$?" >> STREAM` as the launch's last action) + **bounded cap + total deadline**
  so a crash/kill returns `BLOCKED` + trips the XLAB-6 breaker instead of hanging - B2; (3) **break on the
  sentinel ONLY** - `turn.completed` fires pre-teardown, so breaking on it races the `-o` flush and spuriously
  BLOCKs ~3-20% of SUCCESSFUL runs; (4) the poll bash needs an explicit **`timeout: 540000`** (the 2-min Bash
  DEFAULT, not the 10-min max, else the deadline collapses to ~6 min); (5) on BLOCKED, **reap the orphan** with
  `kill "$(cat PIDFILE)"` - no KillShell tool exists, `pkill -f codex` kills sibling runs, and parent/task-id
  kill orphans the child. Success needs ALL THREE: `turn.completed` present, `^CODEX_EXIT=0$`, nonempty `-o`.
  The `-o` final message + `--json` stream go to UNIQUE `mktemp` files in `/tmp` (a fixed repo-root name races
  concurrent runs + pollutes `git status`).
- **Rejected: a `flock` on `codex exec`.** Advisory, and wraps only ONE of the two entrypoints - the plugin
  app-server ignores it, so it does not close the cross-mechanism race that actually fired. State isolation
  does.

## XLAB-14 After a cross-lab control failure, MEASURE the blast radius - never assert it
A skipped preflight, a wrong cwd, an unintended send: do not report "it was probably fine." The other lab
keeps its own transcript, so read it. Open the codex session file under `$CODEX_HOME/sessions/<date>/rollout-*.jsonl`
(the id is in the `thread.started` event, see XLAB-4) and report, as measured facts: **which tool calls the
model actually made** (zero is the good answer), whether `agents_md` was populated, and whether any repo file
CONTENT appears in the transcript versus only a path string. Then state plainly whether the small blast radius
was **design or luck** - a prompt that happened to need no reads is luck, and luck does not close the finding.
Disclose to the human in the same message; a control failure you found yourself is still a control failure.

---
name: delegation
description: >-
  Hard rules + gating-fit for spawning sub-agents - worktree isolation, never parallel-writing the
  same tree, resumable agentId iteration, foreground-vs-background and how delegation interacts with
  the message-queue gating; plus the build→prove→propagate rollout discipline (universal seams over
  bespoke). Use when launching or coordinating sub-agents, or structuring an incremental rollout.
---

# Delegation hard-rules (the *how*; the decision guide is the Spawn Contract in the `agent-tiers` skill)

## Hard rules
- **Never** parallel-write the same live tree (races) → worktrees. ⚠️ Built-in `isolation: "worktree"`
  derives from the *current* repo - if another agent is active there, hand-roll an off-project `/tmp`
  repo instead.
- **Never `git stash` in a parallel-worker brief.** Worktrees share one `.git`, so `refs/stash` is repo-wide -
  two workers stashing concurrently pop each other's changes (2026-08-18: the content swap across two worktrees
  and the shared ref path are observed, the concurrent-stash mechanism is inferred - one of the two workers
  confirmed stashing). Brief `git show HEAD -- <file>` or a file copy for the before/after need instead. Everything
  else workers normally run (`add`/`commit`/`diff`/`status`/`log`) IS worktree-scoped.
- **Never** delegate synthesis/understanding - plan from agents' findings yourself.
- **Always verify** output (re-run tests for code; spot-check files) - a summary ≠ truth.
- **Self-contained prompts** - agents start blind: include paths, build/test commands, conventions.
  Sub-agents rarely invoke the `Skill` tool directly (measured via a session-transcript scan:
  11/153 `Skill` calls logged came from a non-main agent, small relative to 216 total
  subagent-transcript rows), so a Bash-less tier's brief has to carry skill content inline rather
  than relying on it to self-invoke.
- Agents return a resumable `agentId` → iterate by resuming it, not re-briefing from scratch (where the
  harness supports it; some harnesses don't expose `SendMessage` - then spawn a fresh minimal agent).
- **Authorization: see Spawn Contract step 3** (the `agent-tiers` skill) - three orthogonal permissions
  (spend / cross-provider disclosure / irreversible-or-external action) + the wave lease. Step 3 is the single
  owner; do not restate the cost ladder here (the quick shape: sonnet/haiku FREE, one scoped opus
  announce-only, opus fan-out / Boss / fable / any fresh `codex exec` GATED).

## Gating fit (delegation × the message-queue workflow)
- **Long** delegated work → `run_in_background` so you stay responsive and can still open a gate;
  short fan-outs (~30s) can be foreground.
- **Verify background-Task survival PER HOST, do not assume it.** On the interactive CLI and on the GUI
  host tested here, backgrounded Tasks survived turn end (verified by PID-tracking real runs across
  turns); an earlier "GUI kills background Tasks at turn end" verdict was a probe artefact - every probe
  let the CLI process exit, so all of them measured teardown, and the control shared the confound. Rule
  kept from that: a probe proves nothing unless it varies ONE thing. If backgrounded workers DO vanish at
  turn end on your host, foreground them (launch + collect in one turn, write to disk before ending).
  Long detached `Workflow` runs remain the open case - keep that turn open until they complete.
- After agents return: **synthesise → gate** (that's the user's injection window). Don't let a big
  multi-agent op starve all gating - checkpoint between waves.
- "Run it all / don't stop" overrides per-task.

## When each mode fits
- **Fan-out research** (parallel `Explore`, read-only): open-ended >~3 queries / several independent
  questions / protect main context. Low-risk, use liberally.
- **Check-stop on a solo hunt**: an investigation not cracked in **~2-3 probes** is a *hunt*, not a
  lookup - stop grinding sequential read-only cycles in main context. Hand the churn to a read-only agent
  with a self-contained brief (symptom + suspect surface + the exact comparison to run), ask for a
  **confidence marker**, then **guided-review** its findings (verify, don't rubber-stamp - you keep the
  conclusion, the agent absorbs the churn). The "one more probe, almost there" feeling is exactly the trap
  the probe-count trigger overrides.
- **Worktree parallel writers**: ≥2 independent isolated chunks (e.g. pure, self-testable modules).
- **Reviewer agent** (`reviewer`): curates several cheap auditors' noisy drafts into one trustworthy list
  (cut false positives, re-rate, dedup, add misses); also a fresh-eyes pass on a big/risky diff.
  Announce-only (one scoped opus call, above); gated only if run AS an opus fan-out (2+ parallel opus).
- **Pipeline** (read→plan→write→review): fine, but sequential, not parallel.

## Context budget (the sensor for "protect main context")
Concrete signals for when context pressure should trigger the fan-out/compact decisions above, not just
the vague "protect main context" phrase:
- **Search before reading** - grep/glob to locate the relevant span before reading a full file; use
  offset/limit reads over whole-file reads when you already know roughly where the target is.
- **Summarize as you go** - carry forward a summary of a tool/sub-agent result, not the raw content,
  once you've extracted what you need from it.
- **~50% context utilization is a soft heuristic**, not a hard gate - treat rising utilization as a
  signal to fan out a sub-agent or compact, the same way a breached RESUME_SESSION threshold signals `gc`.

## Build → prove → propagate (universal seams over bespoke)
When a capability is needed in **2+ places**, don't bolt a bespoke copy onto each - build **ONE** shared
mechanism as the **superset** so future consumers *wire in* rather than forcing a redesign, then roll it out:
1. **Build** the shared seam (record / bridge / base) covering all known consumers.
2. **Prove** it on the **safest / simplest consumer first** (often the lowest-stakes / debug one - which
   also exercises the richest surface); gate before touching production paths.
3. **Propagate** to the rest and **delete the bespoke paths** - never leave it half-migrated.

Trigger = a **REAL recurring need (2+ live consumers)**, never hypothetical - this does NOT override "a few
similar lines beat a premature abstraction." This partitions cleanly for delegation: build+prove is one
focused chunk (Lead or a well-briefed Worker, gated); each propagation is an independent, fully-specified
Worker slice. Keeps a codebase versatile + open to whatever comes next instead of locking it down.

## Tier fit (this kit, v4)
- A **Worker** (`worker` / `<project>-worker`) = fully-specified mechanical job, cheap model, no decisions.
  Spawn with `model: opus` for clever code when no second coding engine applies; `model: haiku` for rote
  scripted procedures.
- An **Advisor** (`advisor`, opus) = one bounded question OR one bounded design/plan needing real
  reasoning → returns a recommendation/plan, never edits. Announce-only under the v3 ladder.
- A **Reviewer** (`reviewer`, opus) = curates several cheap auditors' noisy drafts into one trustworthy list
  (cut false positives, re-rate severity, dedup, add misses) → writes one curated file, never edits code.
- **`codex-write`** (cross-engine WRITE path, per-host where codex is authed) = Claude briefs, Codex writes in
  an ISOLATED worktree, Claude verifies + owns the review (never Codex-reviews-its-own-code; interface-band Lead
  -> opus Reviewer for any non-trivial diff). Codex REVIEW = the read-only `codex` plugin. GATED when it spawns
  a broker / writes / runs background (see the agent-tiers skill's cross-provider section).
- The **Lead** (main chat, a per-session capability BAND) keeps the knowledge, routes, verifies, synthesises,
  decides. Don't delegate the deciding. An **interface-band** Lead (sonnet default) routes deep thinking DOWN
  instead of grinding it at sonnet depth; a **reasoning-band** Lead (opus, for architecture/synthesis) holds
  the depth and reaches OUT for independence (cross-lab / fable) instead.

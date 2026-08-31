# Escalation brief - <one-line title>

> ONE template for every metered escalation: Advisor asks, Boss briefs, Codex code-handoffs.
> The brief IS the cost control - a tight brief lets a cheaper tier clear the job. The target
> starts BLIND: it sees only the working dir + this brief. Fill what applies; delete these lines.
> Consumer deltas: Advisor -> "The ask" is ONE bounded question or plan request. Boss -> attempts
> + hypothesis are REQUIRED (it bounces without them). Codex -> acceptance criteria + scope are
> REQUIRED; keep the ask implementation-shaped. Review spawns -> also fill the Review mode block.

## Goal
<the outcome wanted, 1-3 sentences - not the steps>

## The ask
<Advisor: the ONE question / the bounded plan to draft.
 Boss: the ONE decision needed.
 Codex: what to build/change.>

## Facts gathered (cite paths)
- `<file:line>` - <fact>
- <env/build facts the target cannot infer>

## Attempts so far (Boss: required; others: if any)
- tried: <exact command / edit> -> result: <exact error / observation> -> ruled out: <what>
- (or point at `ATTEMPTS.md`)
- current hypothesis: <one line>

## Scope - touch only these (Codex/Worker)
- `<path/or/dir>` - <why>

## Acceptance criteria (how the Lead will check)
- [ ] <observable behaviour / test / the shape a good answer must have>
- [ ] <build/typecheck clean, edge case handled, ...>

## Constraints
- <style/framework rules; do NOT change public APIs / X; perf or dependency limits>
- **Blast radius (any brief that RUNS things):** state the sandbox as a boundary, never a list of files to
  avoid - "write nothing outside `<SANDBOX>`", which covers `$HOME` dotfiles, `~/bin`, symlink TARGETS and
  anything a script you invoke rewrites. A named-file ban leaks: on 2026-08-04 a verify-only pass told to
  never touch the live `settings.json` obeyed that exactly, and its sandbox runs still repointed the real
  `~/bin/agent-tiers-share` at `/tmp`. If the target must run an installer or a hook, give it an isolated
  `HOME` too, and say how to check afterwards.

## Out of scope (do NOT do)
- <adjacent things to leave alone; no refactors beyond the goal>

## Review mode (review briefs only - delete otherwise; doctrine: the skill's Review-mode delta)
- Mode, picked by artifact MATURITY: <ADVERSARIAL (new/unreviewed: "attack it") | CLAIM ADJUDICATION
  (converged: numbered claims, one verdict each CONFIRMED/REFUTED/UNVERIFIABLE; evidence MANDATORY
  for REFUTED; state that zero refutations is a valid outcome - and not to defer either)>
- Planted control(s) (SC-4.2): <the pre-verified claim/defect, seeded above UNMARKED and formatted
  like the uncertain items; record them in chat BEFORE spawning>
- Escape hatches (mandatory on any claim list): end the ask with "which claim are you least
  confident in, and why" + "what is missing".

## Spawn record (fill at send time)
- tier: <advisor|boss|worker|codex-write|codex-read> . model: <sonnet|opus|fable|codex-id> . effort: <level>
  (state the model here so the agent's check-in can report it truthfully)

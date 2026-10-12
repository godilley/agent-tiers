# BOSS card - the stuck circuit-breaker (rare, always human-gated)
*card-v4 c=1458414831-4261 - bump on every normative edit (see MAINT-2); quote it when a return leans on this card's rules.*

> **Single owner of the Boss mechanism.** Load this card before spawning a Boss - dispatched from the
> Spawn Contract recovery ladder (`SC-6.3` "stop + ask" offers the Boss gate) and the spend ladder (`SC-3.1`,
> where the Boss is a rung-3 gated call). An ordinary spawn never needs it.

> Workers churn -> Lead distills -> (only if still stuck) Boss delivers an independent verdict the Lead owns adopting.

The value is **independence** - a different model given a clean framing sees what the looping Lead can't. Not
"a smarter model" (don't assume that, and don't frame it that way to the user). It fires *after* Workers /
Advisor, on what they produced - almost never instead of them. The Lead still owns adopting the verdict (`see
SC-1.5` for who owns a trust-class verdict; the Boss GENERATES the independent view, it does not seize authority).

## BOSS-1 Fire it / don't
Quick test: *"Could a fresh same-model agent answer this cheaply?"* yes -> Worker or Advisor, not the Boss.

| Right call | Wrong call -> use instead |
|---|---|
| **3rd+ attempt** at the same goal, no real progress - the attempt history shows fixes that "worked" then regressed differently | First attempt at anything -> just try normally |
| Lead keeps **reversing its own conclusion** / every probe "confirms" a hypothesis yet the fix never works - a foundational assumption is suspect | Grindable question ("which of 40 files import X?") -> Worker |
| **Advisor and Lead deadlock** on a high-stakes, hard-to-reverse call (migration, data-loss risk) - Boss tiebreaks with both cases in the brief | Fresh scoped design/approach question, not stuck -> Advisor |
| | Low-stakes / easily reversible fork -> just pick and move on |
| | "It doesn't work and I'm not sure why", no real attempt history yet -> too early; distill first (the Boss bounces it) |
| | "Go investigate the codebase and figure out what's wrong" -> wrong: the Boss decides on gathered context, it is not a gatherer |

## BOSS-3 Spawn procedure - preconditions, gate, brief delta, bounce
1. **Preconditions:** a 2nd check-stop has fired on this hunt (a check-stop is a hunt not cracked in ~2-3
   probes, the delegation skill's solo-hunt check-stop; the recovery-ladder attempt count, `see SC-6.3`, is
   the same counter, one counter one action) and the Lead can state the ONE decision needed. Can't state it
   -> too early, keep distilling. A first check-stop, or any session that never gets stuck, needs no Boss
   consideration at all - that is the expected outcome, not an omission.
2. **Brief (inline, agents start blind):** the shared escalation-brief template, with the Boss's REQUIRED delta -
   each attempt WITH result, drawn from the brief's own "Attempts so far" section, + the current hypothesis. A
   brief missing those earns a `BOUNCE:`. The ONE decision asked is the acceptance criterion.
3. **Gate - every spawn, before spending:** AskUserQuestion showing the model, the decision asked, and where the
   brief is. Never auto-fire. In GUIs where the structured-ask tool ships deferred, prefetch its schema early
   (a deferred tool cannot be called until its schema is fetched, and a `/compact` resets that) rather than
   falling back to a plain-text ask.
4. **Spawn:** read-only, synchronous/foreground in GUIs that kill background agents
   (a host that ends the CLI process at each turn boundary takes detached work down with it), with an
   explicit model DIFFERENT from the Lead's via the Agent-tool `model` param. For a v4 sonnet Lead the
   frontmatter `opus` is the natural default; pick **fable** instead
   when opus reasoning was already implicated in the deadlock (an Advisor / opus-worker produced or endorsed the
   stuck conclusion - a second opus opinion adds little independence). A reasoning-band Lead reaches for fable or
   cross-lab (Codex) here for the same reason. Record requested model/effort as declared in the spawn record (see SC-6.4).
5. **On return:** verify model independence against runtime evidence, not the check-in (see SC-6.4). A `BOUNCE:` reply means *distill harder* - fill
   the named gaps and re-gate; never widen the Boss's scope to "go look around", and never retry the same brief.

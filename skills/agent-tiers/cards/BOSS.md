# BOSS card - the stuck circuit-breaker (rare, always human-gated)
*card-v1 c=4053528561-4930 - bump on every normative edit (see MAINT-2); quote it when a return leans on this card's rules.*

> **Single owner of the Boss mechanism.** Load this card before spawning a Boss - dispatched from the
> Spawn Contract recovery ladder (`SC-6.3` "stop + ask" offers the Boss gate) and the spend ladder (`SC-3.1`,
> where the Boss is a rung-3 gated call). An ordinary spawn never needs it.

> Workers churn -> Lead distills -> (only if still stuck) Boss delivers an independent verdict the Lead owns adopting.

The value is **independence** - a different model given a clean framing sees what the looping Lead can't. Not
"a smarter model" (don't assume that, and don't frame it that way to the user). It fires *after* Workers /
Advisor, on what they produced - almost never instead of them. The Lead still owns adopting the verdict (`see
SC-6.2` for who owns a trust-class verdict; the Boss GENERATES the independent view, it does not seize authority).

## BOSS-1 Fire it / don't
Quick test: *"Could a fresh same-model agent answer this cheaply?"* yes -> Worker or Advisor, not the Boss.

| Right call | Wrong call -> use instead |
|---|---|
| **3rd+ attempt** at the same goal, no real progress - attempt log shows fixes that "worked" then regressed differently | First attempt at anything -> just try normally |
| Lead keeps **reversing its own conclusion** / every probe "confirms" a hypothesis yet the fix never works - a foundational assumption is suspect | Grindable question ("which of 40 files import X?") -> Worker |
| **Advisor and Lead deadlock** on a high-stakes, hard-to-reverse call (migration, data-loss risk) - Boss tiebreaks with both cases in the brief | Fresh scoped design/approach question, not stuck -> Advisor |
| | Low-stakes / easily reversible fork -> just pick and move on |
| | "It doesn't work and I'm not sure why", no attempt log -> too early; distill first (the Boss bounces it) |
| | "Go investigate the codebase and figure out what's wrong" -> wrong: the Boss decides on gathered context, it is not a gatherer |

## BOSS-2 The attempt log - the Boss's fuel (start it on the SECOND check-stop, not by habit)
The Boss needs "what was tried and why it failed" - so capture it when it's cheap, not reconstruct it when
stuck. **Trigger, not habit:** start the log when a **second check-stop fires on the same hunt** (a check-stop
is a hunt not cracked in ~2-3 probes; memory note: check-stop-delegate-the-hunt). A first check-stop, and any session
that never gets stuck, needs no file - a long multi-wave session with no repeated-failure hunt should
end with no `ATTEMPTS.md` and that is the expected outcome, not an omission. Once triggered, append a record
per attempt to an untracked scratch `ATTEMPTS.md` at the repo root (one hunt per file-lifetime; clear it when
the hunt closes):

```
## attempt N - <one-line what>
tried:     <exact command / edit>
result:    <exact error / observation>
ruled out: <what this eliminates>
suspicion: <current hypothesis>
```

A 2nd+ check-stop on the same hunt is the moment to consider offering the Boss gate. The recovery-ladder
attempt count (`see SC-6.3`) is the same counter - one counter, one action.

## BOSS-3 Spawn procedure - preconditions, gate, brief delta, bounce
1. **Preconditions:** the attempt log exists (i.e. a 2nd check-stop fired on this hunt, see BOSS-2) and the
   Lead can state the ONE decision needed. Can't state it -> too early, keep distilling.
2. **Brief (inline, agents start blind):** the shared escalation-brief template, with the Boss's REQUIRED delta -
   each attempt WITH result (or point at `ATTEMPTS.md`) + the current hypothesis. A brief missing those earns a
   `BOUNCE:`. The ONE decision asked is the acceptance criterion.
3. **Gate - every spawn, before spending:** AskUserQuestion showing the model, the decision asked, and where the
   brief is. Never auto-fire. In GUIs where the structured-ask tool ships deferred, prefetch its schema early
   (memory note: prefetch-askuserquestion-before-forking) rather than falling back to a plain-text ask.
4. **Spawn:** read-only, synchronous/foreground in GUIs that kill background agents
   (memory note: gui-kills-background-workflows), with an explicit model DIFFERENT from the Lead's via the Agent-tool
   `model` param. For a v4 sonnet Lead the frontmatter `opus` is the natural default; pick **fable** instead
   when opus reasoning was already implicated in the deadlock (an Advisor / opus-worker produced or endorsed the
   stuck conclusion - a second opus opinion adds little independence). A reasoning-band Lead reaches for fable or
   cross-lab (Codex) here for the same reason. State the spawned model/effort in the brief so the check-in can
   report them truthfully.
5. **On return:** verify the check-in names the expected model. A `BOUNCE:` reply means *distill harder* - fill
   the named gaps and re-gate; never widen the Boss's scope to "go look around", and never retry the same brief.

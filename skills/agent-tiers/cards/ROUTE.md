# ROUTE card - how a spawn's model, effort and provider get chosen
*card-v1 c=1262656917-8806 - bump on every normative edit (see MAINT-2); quote it when a return leans on this card's rules.*

> **Single owner of the routing RATIONALE.** The every-spawn decision itself is the scope matrix in Spawn
> Contract step 2 ROUTE (hot, top of skill) - this card is the model behind it: the five axes, the per-spawn
> override levers, and the standing rule that stops a cheap Lead grinding a hard shape at its own depth.
> Load it when a route is non-obvious, when choosing model/effort for a fan-out, or when deciding who owns
> a verdict - reached from the cold routing section of the hot skill, NOT dispatched by a Spawn Contract
> rule. An ordinary, obvious spawn never needs it.

The tier table gives each tier a DEFAULT model/effort. On top sit the **five-axis routing model** (the
framing), a **scope matrix** (those axes instantiated as task-shape defaults), a **per-spawn override** the
Lead applies at the Agent call, and the **routing doctrine** that keeps the cheap Lead from under-thinking
hard shapes.

## ROUTE-1 Five-axis routing - the model above the matrix
Route on FIVE orthogonal axes, in order; each sets ONE output. Do not collapse them into "which model is
best." The scope matrix in Spawn Contract step 2 ROUTE (top of skill) is these axes INSTANTIATED as task-shape defaults.

| # | Axis | The question | Decides |
|---|---|---|---|
| 1 | **Verb / shape** | build . review . unstuck . gather . decide | **ROLE** (implementer / reviewer / breaker / researcher / arbiter) |
| 2 | **Trust class** | security / architecture / hard-to-reverse? (Trust taxonomy) | **who OWNS the verdict** + whether it is gated |
| 3 | **Independence** | need a *different mind*, not more of the same? | **PROVIDER of the 2nd pass** (cross to the other lab / fable) |
| 4 | **Hardness x stakes** | how hard, how bad if wrong? | **MODEL x EFFORT** |
| 5 | **Brief specificity** | how much did I already pin down? | trades *against* axis 4 - tighten the brief before buying a tier |

**One-line rule:** verb picks the role; trust class picks who OWNS the answer; independence picks who does the
2nd pass; hardness x stakes + brief specificity set the price. **Provider is chosen per PASS, never per
artifact.** Provider defaults before axis 3 pulls cross-lab: *implement code* -> the per-session write-engine
pref (Codex if opted, else a Claude worker); *reason / decide / verdict* -> **Claude** (the trust anchor).

**What the three reasoning-capable tiers are actually for (2026-08-30, haiku's role is ROUTE-2):** sonnet is not sharp enough to own a hard decision
alone - that is WHY it routes reasoning out rather than grinding it (see ROUTE-4), not a limitation to work
around. Fable is too expensive to spend on anything but thinking - a fable-tier agent doing mechanical volume
is a routing mistake, not a luxury (the top-of-band cost qualifier under Lead capability-band is the same
point from the other side). Opus is the middle: capable of both, cheapest at neither - the default reasoning
tier for one bounded ask.

## ROUTE-2 Scope matrix - instantiated in Spawn Contract step 2 ROUTE
The task-shape -> tier/model/effort table is the every-spawn decision, so it sits in the Spawn Contract above. The
notes that belong with it: haiku is for fully-scripted procedures with mechanical output (weaker summaries -
verify, and keep judgment-bearing work at sonnet or above); the codex row is the cross-engine lever (see
"Cross-provider handoff"), inapplicable on a host with no second engine (clever code then takes the
opus-worker row).

## ROUTE-3 Per-spawn override - the Lead's runtime lever
- **Model:** override per spawn with the **Agent-tool `model` param** (`sonnet|opus|haiku|fable`). Beats the
  frontmatter default; the main lever - proven for the Boss (forces model-independence) and the v4
  opus-worker (clever code without Codex). When overriding, STATE the spawned model in the brief so the
  agent's check-in can report it truthfully (agents cannot introspect their live model).
- **Deviating from the matrix default needs approval first (2026-08-30).** Using an already-documented
  default (Boss's different model, the opus-worker row for clever code without Codex) is routine, not a
  deviation - no gate. Picking a model the scope matrix does NOT already name for that shape is a deviation:
  state it to the user with the reason, before spawning. A deviation that recurs and earns its place
  graduates into the scope matrix itself (universal seams over bespoke, `delegation/SKILL.md`) rather than
  staying a standing one-off.
- **Effort:** the Agent tool has **no effort param** - a single spawn's effort comes from frontmatter
  `effort:` (honored unless `CLAUDE_CODE_EFFORT_LEVEL` pins it, see HOST-1). To vary effort per task WITHOUT
  new agent files, run a **Workflow** - `agent(prompt, {model, effort})` sets both per agent, which also
  makes Workflows the standard mechanism for MIXED model/effort fan-outs (e.g. haiku finders + one opus
  verifier in a pipeline). Whether a host reaps detached/background workflow runs is a per-host fact - probe it
  and keep a reaping host's Workflow in-turn rather than fire-and-forget (see HOST-3).
- **Rule of thumb:** override MODEL per spawn within the defaults the matrix already names; a deviation from
  those defaults is gated (above). Reach for a Workflow when a fan-out genuinely needs
  mixed model/effort. One-off spawn at default effort - just use the Agent tool. The escalation ladder
  applies by CONTENT, not mechanism: a Workflow containing 2+ opus agents is rung 3 (gated); an all
  sonnet/haiku Workflow is rung 1 (free).

## ROUTE-4 Routing doctrine - the cheap Lead must not under-think
The Lead knows its own model (its system prompt states it). Under v4 the Lead is cheap BY DESIGN, so this
is the standing operating mode, not an edge case: when the task shape is high-reasoning (design, a stuck
hunt, a risky hard-to-reverse call), the Lead must NOT quietly grind it at sonnet depth. Instead:
1. **Route DOWN by default**: write a tight brief and send the thinking to the Advisor (announce-only,
   rung 2) - the cheap Lead stays the manager, the clever tier does the thinking. Same "Lead manages,
   clever tier thinks" shape as the cross-provider handoff, just for reasoning instead of code.
2. The Lead handles a high-reasoning shape ITSELF only when the USER explicitly directs it in the message
   ("work through this yourself") - **never the Lead's own judgment call** that a brief would cost more than
   the thinking (2026-08-30, tightened - "small enough" was the Lead's own escape hatch from routing DOWN,
   which is exactly the failure mode this rule exists to stop). Synthesis of returns, the adoption decision,
   and brief-writing are the Lead's own job regardless - not a shape that gets "handled itself" under this
   rule (see the complements below, SC-1.4). Even when explicitly directed, spin a cheap Worker to re-check
   the CHECKABLE part of the result (do the cited files/lines say what it claims, do the facts hold) - it
   does not grade the judgment, and anything trust-class still takes SC-1.6 independence regardless. If the
   user's direction also rules out spawning ("no need to delegate"), say so and take that verification pass
   yourself instead of spawning against it.
3. For a genuinely exceptional call (hardest reasoning, high stakes), offer the gated fable rung - or the
   user can upgrade the Lead's model/effort via the GUI for that session.
**Band branch:** the above (route DOWN) is the INTERFACE-band Lead. A REASONING-band Lead already holds the
depth, so it does NOT route reasoning down for capability - it reaches OUT for independence (cross-lab / fable)
or to protect its own context, and it can OWN a trust-class verdict directly (an interface-band Lead must route
that verdict out; see Trust taxonomy). Same "manager buys the right 2nd mind" shape, opposite direction. At the
TOP of the reasoning band (a fable Lead) this gains a second direction: it also routes MECHANICAL VOLUME down,
not for capability but because its own tokens are the wrong ones to spend on bulk reading (see the cost
qualifier under Lead capability-band).
The complements: verify every return (summary != truth), and synthesis/decisions stay in the Lead.

## ROUTE-5 Band nuance on the three verify tiers
**The three verify tiers are Spawn Contract step 6** (top of skill) - that is the every-spawn owner. Band
nuance that belongs here as cold detail: verify-tier-(c) ("can't grade at my own depth -> escalate") is a
STANDING risk under an interface-band Lead; under a REASONING-band Lead it RECEDES (the Lead grades deep calls
at its own depth) - but the INDEPENDENCE need persists (a same-mind self-verify shares blind spots), so
top-stakes trust-class verdicts still get a cross-lab / fable independent pass.

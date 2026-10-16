# ROUTE card - how a spawn's model, effort and provider get chosen
*card-v5 c=843567507-13579 - bump on every normative edit (see MAINT-2); quote it when a return leans on this card's rules.*

> **Single owner of the routing RATIONALE.** The every-spawn decision itself is the scope matrix in Spawn
> Contract step 2 ROUTE (hot, top of skill) - this card is the model behind it: the five axes, the per-spawn
> override levers, and the standing rule that stops an interface-band Lead grinding a hard shape at its own depth.
> Load it when a route is non-obvious, when choosing model/effort for a fan-out, or when deciding who owns
> a verdict - reached from the Policy cards table in the hot skill and from SC-2.1 via ROUTE-3. An
> ordinary, obvious spawn never needs it.

The tier table gives each tier a DEFAULT model/effort. On top sit the **five-axis routing model** (the
framing), a **scope matrix** (those axes instantiated as task-shape defaults), a **per-spawn override** the
Lead applies at the Agent call, and the **routing doctrine** that keeps an interface-band Lead from under-thinking
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

**What the three reasoning-capable tiers are actually for (2026-08-30; haiku's role is the scope matrix's
own row, Spawn Contract step 2 ROUTE):** sonnet is not sharp enough to own a hard decision
alone - that is WHY it routes reasoning out rather than grinding it (see ROUTE-4), not a limitation to work
around. Fable is too expensive to spend on anything but thinking - a fable-tier agent doing mechanical volume
is a routing mistake, not a luxury (the top-of-band cost qualifier, see ROUTE-6, is the same point
from the other side). Opus is the middle: capable of both, cheapest at neither - the default reasoning
tier for one bounded ask.

## ROUTE-3 Per-spawn override - the Lead's runtime lever
- **Model:** override per spawn with the **Agent-tool `model` param** (`sonnet|opus|haiku|fable`). Beats the
  frontmatter default; the main lever - proven for the Boss (forces model-independence) and the v4
  opus-worker (clever code without Codex). Record the requested override in the spawn record as declared,
  then verify identity using the shared contract at SC-6.4; brief text is not runtime proof.
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

## ROUTE-4 Routing doctrine - an interface-band Lead must not under-think
The Lead knows its own model (its system prompt states it). For an interface-band (sonnet) Lead this is
the standing operating mode, not an edge case (a reasoning-band Lead reaches OUT instead, see Lead capability-band in the skill): when the task shape is high-reasoning (design, a stuck
hunt, a risky hard-to-reverse call), the Lead must NOT quietly grind it at sonnet depth. Instead:
1. **Route DOWN by default**: write a tight brief and send the thinking to the Advisor (announce-only,
   rung 2) - the Lead stays the manager, the clever tier does the thinking. Same "Lead manages,
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
not for capability but because its own tokens are the wrong ones to spend on bulk reading (see ROUTE-6).
The complements: verify every return (summary != truth), and synthesis/decisions stay in the Lead.

## ROUTE-5 Band nuance on the three verify tiers
**The three verify tiers are Spawn Contract step 6** (top of skill) - that is the every-spawn owner. Band
nuance that belongs here as cold detail: verify-tier-(c) ("can't grade at my own depth -> escalate") is a
STANDING risk under an interface-band Lead; under a REASONING-band Lead it RECEDES (the Lead grades deep calls
at its own depth) - but the INDEPENDENCE need persists (a same-mind self-verify shares blind spots), so
top-stakes trust-class verdicts still get a cross-lab / fable independent pass.

## ROUTE-6 The Lead's own model - cost levers, top-of-band cost, metering, correction ladder
Moved verbatim from the hot skill in doctrine-v29 (the tier-table bullets and the Lead capability-band
section); the band rule itself (BAND-1) and its selection rule stay in the hot skill. In the moved text,
"above", "this skill" and "the bullets here" refer to the hot skill (SKILL.md), where it was written.

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
- The **Lead is GUI-configured** - never pin its model/effort from files. No band is the default:
  **Sonnet @ high** (interface-band) suits a routing-heavy session, **Opus** (reasoning-band) an
  architecture/doctrine session (see Lead capability-band); dial effort up for synthesis-heavy stretches. Setting
  **Fable** puts the Lead at the TOP of the reasoning band, where the cost qualifier bites: expect to delegate
  bulk reading rather than do it, or the session is expensive for no capability gain. The panel
  stays authoritative; the kit only configures and verifies the sub-agents.

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

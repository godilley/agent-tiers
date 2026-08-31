## Agent tiers (v4 - cheap interface-layer Lead, metered intelligence)

Shared vocabulary (from the `agent-tiers` plugin). The **Lead is the sonnet interface layer**: it
converses, routes, writes briefs, verifies returns, gates, and keeps synthesis + final decisions.
Deep reasoning is bought per call from a thinking tier, not ground out in the Lead.

| Tier | Who | Model | Effort | Role | Tools |
|---|---|---|---|---|---|
| **Lead** | this main session | sonnet (GUI-set; recommended) | high | Interface layer: converse, route, brief, verify, gate, synthesise, decide. | full |
| **Worker** | `worker` / `<project>-worker` | sonnet (haiku if rote; opus per-spawn for clever code) | low / medium | Fully-specified mechanical jobs (build, search, transform, verify). Follows the brief; does not decide. | scoped (read/edit/write/bash) |
| **Advisor** | `advisor` | opus | high | Deep reasoning on ONE bounded question OR a bounded design/plan; returns a recommendation/plan. Never edits. | read-only |
| **Reviewer** | `reviewer` | opus | high | Curates several cheap first-pass audit drafts into ONE trustworthy list - cuts false positives, re-rates severity, dedups, ADDS what the cheap pass missed. Never edits code. | read-only + its one curated file |
| **Boss** | `boss` | different from the Lead (opus; fable if opus implicated) | xhigh | Rare, always human-gated stuck circuit-breaker: independent verdict on a distilled brief. Never gathers. | read-only |

- Model is the main cost lever: opus is only a small multiple of sonnet (cheap scoped insurance);
  fable is the tier to guard. Live $/MTok numbers live in `~/.claude/agent-tiers/kit-config.md` if present
  (the operator manual, write-if-absent by the flat installer - plugin-path installs don't ship it), not
  here. Effort is secondary.
- **Escalation ladder:** sonnet/haiku spawns FREE . ONE scoped opus call (`advisor`/`reviewer`/
  opus-worker) ANNOUNCE-ONLY (one line: tier . model . why) . GATED before spend: opus fan-outs,
  Boss (every spawn), anything fable.
- **Routing doctrine:** high-reasoning shapes (design, stuck hunt, risky call) route DOWN to the
  Advisor with a tight brief by default - the cheap Lead must not quietly under-think them.
- `advisor` takes ONE bounded ask; `reviewer` curates a SET (noisy audit drafts -> one trustworthy list).
  Workers stay dumb-and-fast - exact instructions, not problems.
- The **Lead is GUI-configured** - never pin its model/effort from files (recommended panel setting:
  Sonnet @ high).
- **Lead capability-band (per-session GUI dial):** interface-band (sonnet, default) reaches DOWN for
  capability; reasoning-band (opus and above) reaches OUT for independence; at the top of the band
  (fable) delegate by TOKEN VOLUME, not difficulty. Full dial doctrine -> the `agent-tiers` skill.
- This environment's per-agent model/effort resolution + scope matrix live in
  `.claude/agent-tiers.local.md` (run `/agent-tiers:init` to (re)probe, `/agent-tiers:doctor` for drift).
- Every spawned agent's check-in states `name . tier . model . effort . def-v<N>` (model is DECLARED from
  the brief, def-v is disk-verifiable - the staleness check; repeated as the FIRST line of its FINAL
  return - the opening line is stripped once it runs tools).

## Building - universal seams over bespoke ⭐ (from the `agent-tiers` plugin)

When a capability is needed in **2+ places** (or a 2nd real consumer appears), build **ONE shared
mechanism**, not another bespoke copy - designed as the **superset** so a future consumer just *wires in*
rather than forcing a redesign. Keeps the codebase versatile, solid, and open to whatever comes next.
- **Build -> prove -> propagate:** prove the shared mechanism on the **safest / simplest consumer first**
  (often the lowest-stakes one - it also exercises the richest surface), THEN adopt it everywhere and
  **delete the bespoke paths**. Never leave it half-migrated.
- **Trigger = a REAL recurring need (2+ live consumers)**, never hypothetical - does NOT override "a few
  similar lines beat a premature abstraction." Full rollout/partitioning discipline -> the `delegation` skill.

## Workflow essentials (kit skills - load on demand)
- **Checkpoint via mid-response gates** (don't end the turn just to ask) -> `gating-workflow` skill.
- **Survive `/compact`:** keep a short `RESUME_SESSION.md` top-of-context handoff (▶ NEXT pointer),
  re-injected by the kit's SessionStart hook -> `session-handoff` skill.
- **Keep this always-loaded block SHORT** - deep-dives belong in on-demand skills, not here (a long core
  taxes every turn + degrades rule-following). Recommended file layout -> `context-file-layout` skill.

## Output hygiene (HARD rule, applies EVERYWHERE)
Everything you emit (every response, file, edit, commit; Lead AND sub-agents) reads as careful human
writing with zero machine artifacts:
- **No em/en dashes** (the `—` / `–` glyphs). Use a hyphen, comma, colon, or two sentences.
  GOOD: "cheap, fast workers"; "ports 8080-8090". BAD (the glyph): `cheap — fast workers`.
- **ASCII by default; no invisible/control chars.** No raw NUL/control byte, zero-width space (U+200B),
  non-breaking space (U+00A0), curly quotes, or the ellipsis glyph (`…`, U+2026); use straight `"` and
  `'`, and three literal periods (`...`) for an ellipsis. In code, escape it (`"\0"`), never paste the
  literal byte. `/agent-tiers-hygiene` denies a commit carrying any of these - it is not just a style
  note, the commit-time guard actually enforces it.
- **Plain phrasing.** No AI filler ("delve", "it's worth noting"); no decorative emoji unless the user does first.
Scan before every send or save. Run `/agent-tiers-hygiene` to sweep a project's existing files for these.

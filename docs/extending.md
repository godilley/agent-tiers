<a name="top"></a>
# Extending the tiers

[Back to the README](../README.md)

## How a project extends the tiers (3 layers)<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

Tiers ship global and generic; a project extends them **without duplication** via one skill (there's no
native agent `extends`, so the seam is the `skills:` hook):

| Layer | Where | What it is |
|---|---|---|
| **L1 global tiers** | the kit's own agent files | each declares `skills: [tier-project-brief]` |
| **L2 project brief** | `.claude/skills/tier-project-brief/SKILL.md` | One per repo: build/test/verify + landmines. Absent -> graceful skip |
| **L3 project task agents** | `.claude/agents/<prefix>-*.md` | Repeated procedures, hooking the same brief. Always PREFIXED |

An unprefixed L3 name would replace the global tier of the same name, which is why the prefix rule is
hard. Self-maintenance is split: the `worker` keeps its own **learnings** in `memory: local`;
**contract** changes are never self-edited - an agent flags the proposed change in its return and the
Lead applies it, gated.

## Companions (optional power-ups)<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

The kit works standalone; two opt-in companions turn it good -> great, both degrade gracefully:

- **[agentsview](https://github.com/kenn-io/agentsview)** (kenn-io, MIT, user-scope MCP) - a session ledger across every agent run. Pull recent
  runs, search all sessions, and verify what a sub-agent *actually did* (tools, timings, health, cost)
  instead of trusting its summary. The go-to verify/diagnose layer.
- **Codex cross-lab layer** (per-host) - a genuinely different lab for the write path and, especially,
  **dual-lab review**: a fresh opus + a cross-lab Codex pass on the same diff, Lead synthesizes (see
  [the XLAB card](../skills/agent-tiers/cards/XLAB.md) - "cards" are this kit's short doctrine-reference
  files under `skills/agent-tiers/cards/`). Two independent minds beat one model reviewing itself.

And two plugins that are not part of the kit at all, but the author won't run a session without
them - switching to a host that lacked them made everything feel subtly off for a day before the
cause clicked:

- **[caveman](https://github.com/JuliusBrussee/caveman)** - ultra-compressed agent communication,
  full technical substance with the filler cut. Pairs naturally with a metered setup: cheaper
  turns everywhere, not just on the big calls.
- **[ponytail](https://github.com/DietrichGebert/ponytail)** - makes the agent reach for the
  laziest solution that actually works before writing new code. The tier system routes work to
  the cheapest capable model; ponytail keeps the work itself small.

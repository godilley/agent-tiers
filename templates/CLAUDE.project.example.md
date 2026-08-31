# <Project> - CLAUDE.md

> **Example project core** - fill each section, then delete these quote lines. Keep it **scannable +
> SHORT** (tables, **bold**, short bullets): this file loads on every turn AND into every project
> sub-agent, so length is a tax. Deep-dives belong in `.claude/skills/<x>/SKILL.md`, not here.
> The global `~/.claude/CLAUDE.md` holds portable defaults (you, machine, technique); THIS file holds
> **project facts + overrides**. Layout guidance → the `context-file-layout` skill.

## What it is
One-liner: purpose, language/stack, target platform + version.

## Layout
| Module / dir | Purpose |
|---|---|
| `...` | `...` |

## Build / run / test / deploy
Exact commands. Note any **non-default JDK / tool paths** an agent must pass explicitly.

## Conventions
Code style, naming, and the **testing approach** (e.g. "prove pure logic against the real compiled class").

## Architecture
Key subsystems, a few lines each. **Link a skill** for any deep-dive rather than inlining it.

## Gotchas
Non-obvious traps, framework quirks, things that bit us (so they don't again).

## Delegation surface
What is **safe to fan-out** to sub-agents here (e.g. pure testable classes) vs what stays with the Lead
(coupled glue / framework wiring). What **every agent prompt must carry** (repo path, build/test cmds,
conventions). See the `delegation` skill + global "Delegating to sub-agents".

## Overrides
Any global defaults this project changes (e.g. verbosity, autonomy, commit habits).

## Pointers
Deep-dives → `.claude/skills/`. Session handoff → `RESUME_SESSION.md` (kit hook injects it). Plans / memory
→ where they live. Agent-tier vocab + the build→prove→propagate rule are injected by `/agent-tiers:init`.

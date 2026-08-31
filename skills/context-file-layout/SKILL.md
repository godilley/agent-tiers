---
name: context-file-layout
description: >-
  How to structure CLAUDE.md and the surrounding context files (global vs project, skills,
  RESUME_SESSION, auto-memory) so the always-loaded core stays short and rules actually get followed -
  the recommended layout, the portable-vs-local split, the anti-bloat rule, and a refactor playbook for
  an existing huge / absent / mis-split setup. Use when setting up or cleaning up a project's context files.
---

# CLAUDE.md + context layout - what goes where

## The layout

| Surface | Holds | Loaded | Keep it |
|---|---|---|---|
| **Global** `~/.claude/CLAUDE.md` | portable defaults: about-you, machine/env, technique/workflow | every session, every project | short |
| **Project** `CLAUDE.md` | local: what-it-is, architecture, build/run/test, conventions, gotchas, delegation surface, overrides | every turn **and into every project sub-agent** | **SHORT - it's a per-turn tax** |
| **Skills** `.claude/skills/<x>/SKILL.md` | on-demand deep-dives, ONE subsystem each | only when the skill's `description` matches | as deep as needed |
| **`RESUME_SESSION.md`** | transient top-of-context handoff: HEAD/version, deployed-vs-unverified, a ▶ NEXT pointer | re-injected after `/compact`·resume·clear by the SessionStart hook | a pointer, not a 2nd doc |
| **Auto-memory** | durable cross-cutting facts (always-loaded index + per-fact files) | the index, always | concise; deep-dives → their own files |

## Placement test
**"True in a different repo?"** → yes = **global**, no = **project**. A deep-dive on ONE subsystem → a
**skill**, not the core. Transient working-state → **RESUME_SESSION**. A durable fact you'll want next
session → **memory**. Precedence: global = defaults, project **overrides**.

## The anti-bloat rule (why this matters) ⭐
The global and project `CLAUDE.md` are **always-loaded** - the project one loads on every turn AND into
every project sub-agent. Past a point a long core (a) wastes context + cost and (b) **degrades
rule-following** - the model skims a wall of text and misses the rules that count. **Keep the core short;
push depth into on-demand skills.** A 1000-line CLAUDE.md is a smell, not thoroughness.

## Maturity annotations (dated confidence tags)
Any fact added or updated in memory files, kit skill docs, or RESUME_SESSION gets a trailing inline tag:
`*[YYYY-MM-DD]* 🌱|🌿|🌳|🌲` - 🌱 Seedling (new, unverified) · 🌿 Growing (validated 2-3x) · 🌳 Mature
(proven across projects) · 🌲 Evergreen (foundational, rarely re-checked).
- **Rewrite in place, never append.** An update REPLACES the existing entry's tag/date - one canonical
  home per fact, matching the anti-bloat rule above. This is NOT a changelog; a growing pile of dated
  annotations under one heading is the same bloat this skill exists to prevent.
- **These emoji are a functional exception** to the global "no decorative emoji" rule (a scanning aid,
  not decoration) - noted here and at the memory index header so neither reads as self-contradictory.
- Applies going forward only. Retagging existing content is a separate, deliberate pass, not automatic.

## Refactor an existing setup - audit → present → confirm → apply
For a project (or a new kit user) whose setup is **huge / absent / mis-split**:
1. **AUDIT** - read their global + project `CLAUDE.md` and any `RESUME_SESSION.md` / memory. Classify each
   chunk: portable→global · local→project-core · deep-dive→a skill · transient→RESUME · durable-cross-cutting→memory · redundant→cut.
2. **PRESENT** - show the proposed moves (what splits to which skill, what's duplicated, what's missing)
   and the core's size before/after. Flag the biggest always-loaded offenders.
3. **CONFIRM** - let them choose: apply all / pick some / hold. **Never auto-mangle a CLAUDE.md.**
4. **APPLY** - scaffold the project `CLAUDE.md` from `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/templates/CLAUDE.project.example.md`
   if absent; move deep-dives to `.claude/skills/<x>/SKILL.md` (each pulled by its `description`); slim the
   core to pointers; set up `RESUME_SESSION.md` (the kit's SessionStart hook injects it).
   ⚠️ **Leave their PERSONAL global content alone** - suggest *structure*, never overwrite their about-you /
   machine / preferences. The global is theirs; you only help them organise it.

## Example
The recommended **project** shape ships at `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/templates/CLAUDE.project.example.md`
(short core + skill pointers). Use it as the target shape, not a verbatim drop-in.

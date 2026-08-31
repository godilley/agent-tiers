---
name: tier-project-brief
description: >-
  Project extension brief for {{PROJECT}}, preloaded into tier agents (worker/advisor/reviewer) via their
  skills-hook. Carries the exact build/test/verify commands, landmines, and domain map so the Lead need
  not re-transmit them. Not for direct Lead invocation - it rides along on sub-agent spawns.
---

# {{PROJECT}} - tier agent brief

You are working on **{{PROJECT}}** - {{DOMAIN}}.

## Build
- {{BUILD_CMD}}

## Test / verify
- {{TEST_CMD}}
- **VERIFY RULE:** {{VERIFY_RULE}}

## Landmines (do not rediscover these)
- {{LANDMINES}}

## Scope discipline
Make the minimal change the brief specifies; don't widen scope or refactor adjacent code. If a step needs
a decision or context you weren't given, STOP and hand back to the Lead.

<!-- Fill from repo detection or ask the user. Keep this ≤ ~1-2k tokens: it is injected into EVERY tier
     spawn. Include only what ISN'T already auto-injected via CLAUDE.md / .claude/rules / the memory
     index - the concrete commands + landmine specifics a sub-agent needs to ACT. -->

---
description: Update RESUME_SESSION.md on demand (the session handoff), optionally steered by text after the command (like /compact <steer>) to say what or why you are checkpointing.
argument-hint: "[steer]: what/why to capture, e.g. 'pausing the X refactor mid-way to start a read-only side task'"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

You are the **Lead** refreshing this project's `RESUME_SESSION.md` handoff on demand. The argument (optional)
is STEER: it tells you what or why you are checkpointing, exactly like `/compact <steer>`. Honor it.

## Gather (fast, read-only)
- `git status --short`, current branch + `HEAD`, and what changed this session (staged / unstaged / untracked).
- The current `RESUME_SESSION.md` (if any) and the live task list / what is in-progress in THIS session.

## Write RESUME_SESSION.md as a POINTER, not a second doc (session-handoff discipline)
Keep it short (the SessionStart hook re-injects it; long = costly). Structure:
- **TL;DR** one or two lines: HEAD + version, tree state (clean / WIP), deployed vs unverified.
- **▶ NEXT** the single most important next action, concrete enough to act on cold.
- Only the durable facts a fresh or compacted context could not re-derive. Convert relative dates to absolute.

## Apply the STEER
- **Pausing mid-task for a side project / fresh session:** capture WHERE you stopped and the exact resume-here
  step as `▶ NEXT`, plus a one-line `PAUSED: <task> to do <side thing>` so the interruption is obvious. Do not
  lose the in-flight state.
- **Read-only / no-change session:** note "no code changed this session" and point `▶ NEXT` at the open question
  or decision, not a code action.
- **General checkpoint:** just refresh TL;DR + `▶ NEXT` to current reality.
- **No steer given:** infer the checkpoint from git + the session and refresh to current reality.

## Then emit the fresh-session paste (session-handoff discipline)
After writing RESUME, also emit a copy-pasteable **kickoff paste** in chat (a fenced code block) so the human
does not hand-write one: read-first pointers (RESUME + the exact plan/spec files for `▶ NEXT`), the imperative
task with its exit condition, the rails that apply (irreversible-action / hygiene / scope), a suggested Lead
band, and the watch-outs (unproven / `def-v1` / PENDING-REFRESH agents, disclosure gates, known traps). Keep it
lean - a launch pad, not a second RESUME. See the `session-handoff` skill's "Fresh-session paste" section.

## Guardrails
- Edit ONLY `RESUME_SESSION.md` (the paste is chat output, not a file). Do not commit, push, or touch code.
- Preserve still-relevant existing content (open work items, deferred list); update, do not blindly overwrite.
- If it grows past ~70 lines, slim the oldest resolved items to a pointer (or suggest `/agent-tiers-gc`).
- Updating the file changes its content hash, so the next SessionStart injects the full refreshed handoff (correct).

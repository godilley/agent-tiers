---
name: session-handoff
description: >-
  The RESUME_SESSION.md handoff discipline for surviving /compact and fresh/cleared contexts - what to
  keep in it, when to update it (as you work, not batched), and how the SessionStart hook re-injects it.
  Use when checkpointing before a compact, or when a resumed session needs to re-derive state.
---

# Session handoff - surviving /compact and fresh contexts

Compaction (auto or manual) drops conversation-only state; only **disk-backed** context returns. Keep a
top-of-context handoff file so a fresh/compacted session resumes instantly without re-deriving state.

## RESUME_SESSION.md (repo root)
A **pointer, not a second reference doc** - keep it light. Hold:
- **HEAD + version**, branch, deployed-vs-unverified state.
- Files changed this chunk, key decisions, and **what failed** (so you don't repeat it).
- A **▶ NEXT** pointer: the exact next step.

Update it **as you work, not batched** - every checkpoint, before any `/compact`.

## Auto-injection
The kit ships a **SessionStart hook** (`scripts/resume-inject.sh`) that re-injects
`$CLAUDE_PROJECT_DIR/RESUME_SESSION.md` on **compact / resume / clear** - not a fresh startup, where
CLAUDE.md already loads and there's no working-state to restore (guarded - silent when the file is
absent). It's wired ONCE, so you do NOT need per-project wiring; just keep the file current.
- **Standalone CLI:** the plugin's own hook provides this.
- **Plugin-ignoring GUI** (e.g. CodeMoss): `scripts/install-flat.sh` wires the same script into the
  **global `~/.claude/settings.json`** SessionStart hook, so it covers every project.
- A project wanting richer/own behaviour can drop its own `.claude/hooks/load-resume.sh`; the global
  hook detects it and **stands down** (no double-inject).

## What goes where
- **Durable facts** (architecture, build/test, conventions, gotchas) → project `CLAUDE.md` or auto-memory.
- **Transient working-state** (this chunk's progress, the ▶ NEXT) → `RESUME_SESSION.md`.
- Never rely on the compaction summary to carry a rule or a decision - write it to disk.

## Checkpoint-before-compact ritual
Before compacting: commit pending work (stage **specific** paths, not `-A`), refresh `RESUME_SESSION.md`
(▶ NEXT) + any durable facts, close out any doc whose plan is done or paused (see `doc-lifecycle`),
then compact. After a compact: re-read `CLAUDE.md` + `RESUME_SESSION.md`
before continuing; confirm no task state was lost.

## Fresh-session paste (emit it automatically at every handoff)
Whenever EITHER party pushes toward a new/fresh/compacted session (a checkpoint, "let's take this fresh",
a pre-compact, a "start a new session for X"), the Lead emits a copy-pasteable **kickoff paste** in chat
IN ADDITION to refreshing `RESUME_SESSION.md`. RESUME is the state doc; the paste is the imperative kickoff
that saves the human hand-writing one. Emit it unprompted - do not wait to be asked.

Shape (minimal, a strong starting point the human can trim, not an exhaustive spec):
- **Read-first pointers:** `RESUME_SESSION.md` + the exact plan/spec files for the next task (not everything).
- **The imperative task:** the ▶ NEXT step as "do X, then Y", with the acceptance/exit condition.
- **Rails:** the gates that apply (irreversible-action, output-hygiene, "don't touch product code"), and a
  suggested Lead **band** for the work-class.
- **Watch-outs:** unproven/`def-v1` agents, PENDING-REFRESH defs, disclosure gates, known traps for this task.

Put the paste in a fenced code block so it copies clean. Keep it lean - it is a launch pad, not a second
RESUME. The `/agent-tiers:resume` command refreshes RESUME and emits this paste together.

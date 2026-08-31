---
name: gating-workflow
description: >-
  Mechanics of mid-response gating with AskUserQuestion - how the option boxes render, the
  "Just 1 / Both 1+2" numbered-body trick, multiSelect/preview/Other, and the discover-before-choose
  tool-shape rule. Use when composing an AskUserQuestion or unsure how to present a fork.
---

# Gating mechanics (the *how*; the triggering *rule* lives in the global core)

## AskUserQuestion option boxes
- The option boxes **render almost no text** - keep labels/descriptions **ultra-terse**. Put the real
  detail as **numbered items in the chat body**, and make each option label **point to a number**
  ("Just 1", "Just 2", "Both 1+2") so the body defines what 1 & 2 *are* rather than restating it.
- Batch up to 4 questions. `multiSelect: true` for non-exclusive choices. `preview` for visual compare.
  "Other" is always available = free text.
- **Pre-gate body prose renders LATE under cc-gui** (a third-party Claude Code GUI wrapper app; tested 2026-08-13). Body text sits as raw markdown
  until a tool call lands after it - so put the numbered detail, then **a tool call**, then the
  AskUserQuestion, and the body is formatted by the time the box opens. Bold, lists and inline code all
  come good that way; **tables do NOT** - they stayed raw even after the tool call, so never use one in a
  pre-gate body.
  - ⭐ **Use a call you needed ANYWAY** - just defer it to sit between body and gate. Inventing a spacer
    is the fallback, not the move.
  - If you must invent one, **don't optimise which**: measured over two passes, the gap is ~2-2.7s of
    model turn and the candidate ordering (`TaskList` / `Read` / `ToolSearch`) reversed between runs, so
    the differences are inside the noise. Any zero-arg call does; Bash `true` (zero output) is enough.
    **Not `Read`** - an unchanged file gets refused as a wasted call.
- ⭐ **A "(Recommended)" first option is MANDATORY** on every preference/fork - undifferentiated options
  are harder to act on, so this is an accessibility requirement, not a style choice. Descriptions ≤ ~12
  words. If you genuinely have no preference, **say why** in the body and still suggest a sensible
  default. A missing recommendation is a bug.

## Gate timeout fallback
The numbered-body trick applies in **every** harness, no special-casing.
- **Only fallback:** if an AskUserQuestion call TIMES OUT or errors, re-present the options as a plain
  **numbered list in chat** and **end the turn** so the user answers with a normal message. This is the
  one sanctioned exception to "never end the turn just to ask" - a dead gate gives no window at all.

## EnterPlanMode vs AskUserQuestion
- Non-trivial **code** → EnterPlanMode → write plan → ExitPlanMode for sign-off. Plan mode is for
  approval, not research.
- A fork/clarification mid-work → AskUserQuestion (it injects a fresh box ahead of the queue).

## Discover before choose (live-learn)
Never assume a tool's shape from memory. Enumerate available tools incl. **deferred** (name-only);
fetch unknown schemas with **ToolSearch**; read the schema to find the *mechanism* (pauses for input?
structured? approval?); match mechanism → need. Re-derive when tools change or new ones appear.

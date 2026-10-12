---
name: gating-workflow
description: >-
  Mechanics of gating with AskUserQuestion (context as an ended reply, then the box) - how the option boxes render, what the box
  must carry on its own (Checked line, cost per option, marked default incl. multiSelect),
  preview/Other, and the discover-before-choose tool-shape rule. Use when composing an
  AskUserQuestion or unsure how to present a fork.
---

# Gating mechanics (the *how*; the triggering *rule* lives in the global core)

## AskUserQuestion option boxes
- **The box must stand alone, and its context arrives as an ENDED reply.** Prose written before a
  tool call (the gate included) can come back as a "narration" thinking block that the operator sees
  only as a generated one-line summary (native CLI, observed 2026-10-01, and the summary misstated a
  number; reproduced 2026-10-03 on some models, not all). A reply that ends with no tool call after
  it arrives in full. So: write the context (findings, tables, options) as a reply that ends with
  the line `operator:ask_next`; `notify-tag-guard` sends the turn straight back and `ask-gate`
  admits the AskUserQuestion after that send-back (native CLI; the gate cannot stop prose written
  inside the send-back response itself, so ask with no text before the call). Labels name the option
  (1-5 words), never a bare number pointing at the body. Per-option detail goes in `preview`
  (single-select only; roughly 15 lines show, the rest is cut with "N lines hidden").
- **Before asking**, read what the repo can answer. Question text ends `Checked: <what was read or
  run>` or `Checked: nothing, <why>`. Measured failure: a CSS feature recommended above the repo's
  documented browser ceiling, checked only afterwards.
- Batch up to 4 questions. `multiSelect: true` for non-exclusive choices. `preview` for visual compare.
  "Other" is always available = free text.
- **cc-gui (a third-party Claude Code GUI wrapper app)** rendered pre-gate body text late and left
  tables raw (tested 2026-08-13). The old workaround there, a tool call between body and gate, is
  the exact shape the native CLI summarizes away; the `ask_next` route above is native-CLI only:
  both hooks stand down on any other host, where `ask_next` just ends the turn - there, end on the
  context with `operator:want_input` and ask next turn.
- ⭐ **A marked default is MANDATORY** (accessibility, not style: an unmarked list reads as equal
  weight and stalls the choice). Single-select: the first option carries `(Recommended)`. multiSelect:
  EVERY option in the recommended set carries it, order free, at least one (an empty set is a
  single-select question with "None (Recommended)"). Its description names the fact that decides it:
  a marker with no reason is a stamp. Every description carries its cost in countables (files, call
  sites, steps), about 12 words. `simple-rules-guard` Rule D enforces the marker, not the reason.

## Gate timeout fallback
The box-stands-alone rule applies in **every** harness, no special-casing.
- **Timeout fallback:** if an AskUserQuestion call TIMES OUT or errors (an `ask-gate` deny is neither:
  follow it), re-present the options as a plain **numbered list in chat** and **end the turn** so
  the user answers with a normal message. This and the non-CLI fallback above are the two sanctioned
  exceptions to "never end the turn just to ask" - a dead gate gives no window at all.
- **Content too big for the box is not an exception to that rule.** A batch to review or a report is
  the ended reply itself: final line `operator:ask_next` (native CLI; elsewhere `operator:want_input`),
  the fork asked right after the send-back.

## EnterPlanMode vs AskUserQuestion
- Non-trivial **code** → EnterPlanMode → write plan → ExitPlanMode for sign-off. Plan mode is for
  approval, not research.
- A fork/clarification mid-work → AskUserQuestion (it injects a fresh box ahead of the queue).

## Discover before choose (live-learn)
Never assume a tool's shape from memory. Enumerate available tools incl. **deferred** (name-only);
fetch unknown schemas with **ToolSearch**; read the schema to find the *mechanism* (pauses for input?
structured? approval?); match mechanism → need. Re-derive when tools change or new ones appear.

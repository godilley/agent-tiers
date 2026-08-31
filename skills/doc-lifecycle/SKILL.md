---
name: doc-lifecycle
description: >-
  How a private planning/investigation doc in a project's notes dir reaches a clean terminal state
  instead of accumulating forever. Use when creating a new dated doc under docs/_local (or
  equivalent), closing one out because its work shipped or was superseded, or deciding whether
  something worth keeping should be promoted into tracked reference documentation.
---

# Doc lifecycle

**Scope**: `YYYY-MM-DD-*.md` files directly inside a project's notes dir (`private_notes_ref.dir`,
default `docs/_local`, resolved the same way `notes-sync.sh` resolves it - `git config --get
notes-sync.dir`, falling back to the literal default). A named state file with no date prefix
(`state-ledger.md`, a ledger, a watermark file) is out of scope by construction, not a violation.

**Terminal folder**: `<notes_dir>/archive/` (flat, no year subdirs). A doc's STATUS is terminal if
and only if it lives in `archive/`; it is open if it lives directly in the notes dir.

**`doc-style`'s `STATUS:` line is documented there as optional; inside a notes dir it is
mandatory** (`LIVE`, `SHIPPED`, `SUPERSEDED by <doc>`, `RECORD, written <date>`, `BLOCKED on
<what>` - same vocabulary, no new value). This is a narrowing for one location, not a
contradiction between the two skills.

**Creation**: new dated docs are created with `notes-sync.sh new <slug>` (never by hand) - that
command stamps today's real UTC date and a `STATUS: LIVE` line so both are correct by
construction, closing the actual bug that produced 100% non-compliance in one repo's existing
docs (a hand-typed date can misdate, and a hand-typed `STATUS:` line is easy to skip). `--from
<path>` graduates an existing file's content into the notes dir the same way.

**Close ritual** - a checklist a human or a Lead follows manually, nothing here is scripted, every
step is a judgment call:
1. Re-read the doc's open items.
2. Move them **by content** into whatever doc is current/live - never leave a pointer that
   requires re-opening the closed doc for active work.
3. Rewrite the closed doc's line 1 to a terminal STATUS, plus one line naming where open items
   went.
4. `mv` into `archive/`. This step always happens regardless of the disposition decision below -
   archive is the resting place either way, tracked or not.

**Disposition (tracked vs stays private) is a SEPARATE decision, and it belongs to the user,
never to a Lead acting on this checklist.** Default: stays private, never tracked, even after
closing - a doc having existed, or having been the plan that shipped, is never itself sufficient
reason to track it. Skip this entirely unless the user raises it. When the user does decide
something is worth keeping visible, promotion means **copying** the specific content into a real
tracked doc (README, ADR, actual `docs/`) - it is never a byproduct of the close ritual above, and
it never means leaving the original file tracked in place. **A Lead must never run `notes-sync.sh
migrate`, `git rm --cached`, or any other untrack/promote action on its own initiative off the
back of a `doc-lifecycle-check.sh` finding** - that report is evidence for the user's decision,
never an instruction queue.

**Advisory check, never a guard, in either direction**: `doc-lifecycle-check.sh` never blocks a
commit, a write, or anything else - every finding is a candidate for the user's own disposition
decision. Three entry points:
- Standalone: `scripts/doc-lifecycle-check.sh` in any repo, any time - always exits 0, full list.
- SessionStart advisory (`resume-inject.sh` block E): passive, automatic, a capped summary only.
- `/agent-tiers:doctor` step 4e: the explicit "check this repo now" ask, full list shown inline.

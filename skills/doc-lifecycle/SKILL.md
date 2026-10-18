---
name: doc-lifecycle
description: >-
  How a private planning/investigation doc in a project's notes dir reaches a clean terminal state
  instead of accumulating forever. Use when creating a new dated doc under docs/_local (or
  equivalent), closing one out because its work shipped or was superseded, or deciding whether
  something worth keeping should be promoted into tracked reference documentation. Also the
  outstanding-work ledger: its five labels, the DONE line form, the typed trigger tokens and the
  archive cap that ledger-check.sh reads at SessionStart.
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

## Outstanding-work ledger (one per project, `docs/_local/*outstanding-work-ledger*.md`, line 1 `STATUS: LIVE`)
A deferral is a decision with a cost, so it is recorded where a reader can test it. One entry is one
top-level `- **title**` bullet with these label lines (each at the start of its own line):
- `Deferred:` what is not being done. Marks the bullet as an entry.
- `Cost:` what it costs while undone, in countables where possible.
- `Forced by:` the concrete trigger, or the literal `nothing named`. Optionally one typed token the
  reader can evaluate: `[session: S5]` (fires when that plan row is DONE), `[exists: path]`,
  `[date: YYYY-MM-DD]`, `[grep>=N: regex @ path]`.
  Anchor it. "The next publish" is true the day it is written and unreadable a week later: nobody can
  tell whether that next has already passed. Name what it is next after (a date, a sha, a version) or
  use a typed token (a count goes in a `[grep>=N: ...]` token), and give the command that checks it. ledger-check flags an untyped
  trigger saying "next" with no anchor (L6).
- `Probe:` the cheapest check that would settle it now, and its result or `not run`.
- `Source:` where it was found (a review, a session, a path:line).
Retire with a line-start `DONE <date> [<session id or sha>]: <the check that proves it>`. Never delete
the line. A DONE with nothing after the colon, or carrying `uncommitted`, `PARTIAL`, `except` or
`pending`, is not a retirement. Asked-for work is never deferred without a human: `Narrowed:` plus an
AskUserQuestion at the time. A `Deferred:` line is for an out-of-scope find whose trigger cannot fire
before the session ends; one that can fire is a fork, not a deferral.

`scripts/ledger-check.sh` (SessionStart, advisory) reads every live ledger: typed triggers that now
hold, untyped trigger lines naming a DONE plan session, unanchored "next" triggers, DONE lines with no check or a qualifier,
cited shas not in HEAD's history, DONE lines for a plan row that is not DONE, and the cap. Prose
triggers are counted, never judged; entries with no labels are counted as legacy and listed only when
their trigger line names a finished session. The plan it reads, when present: the first live
`docs/_local/*.md` with a `## Status table` heading over rows `| <session id> | <state> | <proof> |`,
a row finished when its state starts `DONE`.
Proof text (a DONE line, a status row's proof cell) names the command that proves it. A count it
quotes is the result at close and says so (`41/41 cases at close`); a bare count reads as the current
figure and goes stale the next time the suite grows. Never refresh an old count: the current figure
is the command, re-run.
Cap: 1500 lines or 150 KB per ledger. Past it, move closed entries older than 14 days to
`<name>-archive.md` (`STATUS: ARCHIVE`), DONE lines verbatim; still over the cap means too many open
entries, which is a human triage, not a formatting fix. Kill switch `.state/off/ledger-check`.

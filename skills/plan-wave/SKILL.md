---
name: plan-wave
description: >-
  Run one wave of a plan as parallel sublead agents, one per plan row, each in its own worktree,
  while the human is present to answer forks. Use when a plan doc has a wave table (rows with ids,
  Waits on, state) or a ready-set command, and the human asks for the ready rows to run now,
  delegated, in this session. The Lead relays every FORK block, reviews each finished row, and
  merges finished rows in wave order.
---

# plan-wave

The Lead is the only thing that talks to the human and the only thing that touches the default
branch. Row agents build in worktrees and hand back `FORK:` blocks or a final return with an
outcome line (the `sublead` return contract). Nothing here is a script: the Lead runs the steps.

## Project settings (optional keys in `.claude/agent-tiers.local.md`)
Each key is optional; the default applies when it is absent.
- `wave_plan:` path of the plan doc holding the wave table. Default: ask the human which doc.
- `wave_ready_cmd:` a command whose output lists the ready row ids. Default: the Lead computes the
  ready set from the wave table (below).
- `wave_merge_check:` the command that must pass on the merged tree before the merge commit, run
  foreground with its exit code read. Default: the checks the rows' returns named, re-run.
- `wave_kickoff:` path of a paste template for row briefs. It replaces the skeleton below, so it
  must carry every skeleton item itself.

## The wave table (the default ready-set source)
One table in the plan doc, one row per unit of work:

    | id | Waits on | state | proof |
    |----|----------|-------|-------|
    | W1 | -        | not started | |
    | W3 | W2       | not started | |
    | W5 | external: <what> | not started | |

`state` is `not started`, `running`, `DONE <date>`, `PARTIAL` or `STOPPED`. A row is READY when it
is `not started` and every id in `Waits on` is `DONE`; an `external:` entry is never satisfied by
the table, the human clears it. `PARTIAL` and `STOPPED` rows are not ready: the Lead decides each
one (re-brief the remainder as a new row, or answer its stop) before the next wave. A `running` row
with no live agent (the session ended mid-wave) goes back to `not started` after the Lead checks its
worktree for work worth keeping.

Each row id has a section in the plan doc naming: the repo the row EDITS (it can differ from the
repo holding the plan), what it does, what it owns (files, symbols), what it must not touch, and
its check command. If the plan doc is tracked, the Lead's state edits go in their own commit;
an ignored notes dir needs none.

## Before the wave
1. The wave is the ready set, computed, never hand-picked. A ready set of none means the plan is
   finished or blocked on an `external:` line: say which. Confirm the default branch of each repo
   the wave edits is clean (`git status --porcelain` empty).
2. Seam owners are settled before spawning: for every pair of ready rows, compare their owned files.
   Two rows that touch one file are either serialised (one waits on the other) or given disjoint
   symbols in their briefs. A merge-time clash between two rows of one wave is a defect in this step.
   Merge position: the order the rows will merge in, set now (rows that others build on first).
3. Lease: N rows in parallel is N opus coordinators plus their children, a gated spend. State the
   wave once (row ids, N, what each does, when it ends) and get the human's yes before spawning.
   A row that becomes ready mid-wave and was not in that statement is re-gated, not rolled in. The
   first wave a repo runs this way is capped at 2 rows: read both returns' spawn ledgers before a
   wider one.
4. Per row: `sh "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/scripts/worktree.sh" up <id>`, run
   inside the repo the row edits; the worktree is `<that repo>/.claude/worktrees/<id>` on branch
   `<id>`. The merge and the teardown below happen in that repo too. When a row edits a repo other
   than the session's own, the Lead clears peer-guard per worktree before spawning (a subagent's
   write there is denied and sets no marker): read the worktree's docs, make one no-op Write in it
   (the first is denied and sets the marker, the retry lands) and remove that file again.
5. Per row, a self-contained brief (the agent starts blind): from `wave_kickoff` if set, else:
   - the row's section of the plan, copied in, and the absolute worktree path, with "run every
     command and every edit inside this path; a relative path or a bare git command elsewhere
     lands on the default branch";
   - "do not edit the handoff file (RESUME_SESSION.md), the plan doc or the wave table; they may be
     symlinked into the worktree and belong to the Lead";
   - owns / must not touch / reserved ids (numbers or prefixes another row could also pick);
   - merge position in this wave;
   - "If this row reads as more than one session, or its scope is unclear, return a FORK at turn
     one before building anything";
   - the row's check command, and the heavy-run window if the Lead names one ("no full test run
     while another row runs its own; check with the Lead by FORK if unsure");
   - commits: in a repo whose `review_gate` is `push`, commit on the row branch; in `commit` mode
     (the default), do NOT commit: leave the change in the worktree, the Lead commits after review
     (a subagent's commit is checked against the Lead's transcript and is denied until the Lead has
     a review spawn). Never push, never touch the default branch.
   No attributed quotes and no "the human wants": the plan is the authority.

## Spawning
- One `Agent` call per ready id, all in one message: `subagent_type: sublead`, no `model:` (the
  definition carries it), `run_in_background: true`. The prompt's first line is
  `[sublead-approved: plan row <id>, wave <date>]`; task-spawn-guard Rule D asks without it and
  logs it with the row (Rule D gates a project-defined `transcript-miner` spawn the same way; the kit does not ship one). The tag records the
  lease from step 3; it is not the approval itself.
- Set each spawned row's `state` to `running`. Record agent id against row id: `SendMessage` to that
  id (carrying `RESUME-OK`) is how a fork answer or a correction reaches it.
- End the turn while agents run. Never poll; returns arrive as notifications.

## On a FORK block
1. If the plan or a tracked doc already settles it, answer from the doc and cite the line; do not
   ask the human. If the fork names the wrong object or the agent narrowed scope, correct it.
2. Otherwise ask with AskUserQuestion: the agent's readings as options, costs in countables, its
   default first and marked, a `Checked:` line. Context too big for the box goes in an ended reply
   first.
3. Send the answer with a one-line reason, nothing attributed.
4. Write the decision into the row's plan section in the same turn, so a re-run does not ask again.

## On a final return, by its outcome line
- `STOPPED (fork)`: as above.
- `STOPPED (a)` (an unsettled decision): settle it, then resume with the answer; not an attempt.
- `STOPPED (b)` (a check it could not fix): repair once by resume with the failing check quoted, or
  re-shape; a further try is the third attempt, so stop and ask the human first.
- No outcome line at all: it stopped early. Read its last report, then resume it once.
- A completion notification with no report is not a return: the agent ended its turn while waiting
  on background work and has not finished.
- `done`: the steps below.

## On done
1. Read the diff, not the summary: committed rows `git diff <default>...<id>`; uncommitted rows
   (commit mode) `git -C <worktree> diff` plus `git -C <worktree> status --porcelain` for new files.
   Check every proof command it names exists and its result is in the return. Read its Deviations
   section: a narrowed or reinterpreted rule is a fork that was not asked.
2. Review: anything non-trivial gets an independent pass on a materialised diff (write the diff to a
   scratch file, brief the path) with a planted control, per the agent-tiers review rules; the
   trust-class surfaces (security, permissions, contracts, data, deploy) always do. In commit mode the
   Lead then commits on the row branch inside the worktree.
3. Merge in the merge position only: in the main checkout on the default branch,
   `git merge --no-ff --no-commit <id>` (`--no-ff`, so even the first merge stops for the check),
   then `wave_merge_check` foreground, then commit. A row whose turn has not come waits; a row that
   blocks the order for long is a FORK to the human (re-order, or wait), never a silent skip. On a
   clash, abort the merge and send the row's agent back to merge the default branch in, adapt and
   re-run its check; then merge again.
4. After each merge: the row's `state` is `DONE <date>` with its proof; newly ready rows inside the
   lease can be spawned at once; close any ledger lines the row discharged; refresh the handoff
   file's NEXT pointer. Push only when the human asks or the repo's flow says so.
5. `sh "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/scripts/worktree.sh" down <id>` in that repo
   once merged (merged-and-clean gate; never a raw `git worktree remove`, never `down --merge`,
   which pushes).

## Traps
- Worktrees share `refs/stash`: no `git stash` anywhere in the wave.
- Worktrees share machine-local files through symlinks (notes, plans, the handoff file): only the
  Lead edits the wave table and the handoff.
- A repo-local skill with the same name shadows this one in that repo; retire the local copy once
  this one covers it.

<a name="top"></a>
<h1 align="center">Plan waves</h1>

<p align="center"><i>Run a plan's ready rows as parallel helpers, one copy of the repo each, merged in a set order</i></p>

<div align="center">

| <img src="assets/spacer.svg" width="21" height="1">[**README**](../README.md)<img src="assets/spacer.svg" width="21" height="1"> | <img src="assets/spacer.svg" width="1" height="1">[**Why delegate**](usage.md)<img src="assets/spacer.svg" width="1" height="1"> | <img src="assets/spacer.svg" width="3" height="1">[**Work shapes**](work-shapes.md)<img src="assets/spacer.svg" width="3" height="1"> | <img src="assets/spacer.svg" width="29" height="1">[**Levels**](levels.md)<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="9" height="1">**Plan waves**<img src="assets/spacer.svg" width="10" height="1"> | <img src="assets/spacer.svg" width="20" height="1">[**Glossary**](glossary.md)<img src="assets/spacer.svg" width="20" height="1"> |
|:-:|:-:|:-:|:-:|:-:|:-:|

</div>

<hr>

> [!NOTE]
> **plan-wave** is a skill, not a script: the main session runs the steps. The main session is the only thing that talks to you and the only thing that touches the default branch.

| Step<br><img src="assets/spacer.svg" width="173" height="1"> | What happens<br><img src="assets/spacer.svg" width="300" height="1"> | As it looks<br><img src="assets/spacer.svg" width="1" height="1"> |
|---|---|---|
| 📋 [**The ready set**](#the-ready-set) | **Computed, never hand-picked**<br><i>&rsaquo; Rows whose dependencies are all done.</i> | `ready set from table: I7, I9, REQ1, M1`<br><sub><i>H1 waits M1, G waits an external probe</i></sub> |
| 🤝 [**The lease**](#the-lease) | **One statement, one yes**<br><i>&rsaquo; Which rows, how many helpers, when it ends.</i> | `Run wave 5 as laid out above (REQ1, I9, M1 now; I7 after REQ1 merges)?`<br><sub><i>answered in 70 s</i></sub> |
| 🚀 [**The spawn**](#the-spawn) | **One helper per row**<br><i>&rsaquo; Each in its own copy of the repo, in the background.</i> | `[sublead-approved: plan row REQ1, wave 2026-10-15]`<br><sub><i>first line of every row's brief</i></sub> |
| 📥 [**A fork**](#a-fork) | **Answered from the plan, or asked**<br><i>&rsaquo; The helper's readings become your options.</i> | `FORK: removing Write from the reviewer leaves doctrine [...]`<br><sub><i>default: (1), cost: 4 files, 7 sites</i></sub> |
| ✅ [**The merge**](#the-merge) | **Diff read, review, check, commit**<br><i>&rsaquo; In merge order, one row at a time.</i> | `git merge --no-ff --no-commit REQ1`<br><sub><i>then the check, then the commit</i></sub> |

> [!TIP]
> A **row** is one unit of work in the plan's wave table. A **wave** is the set of ready rows run together.

---

<a name="the-ready-set"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">📋 The ready set 📋<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>One table in the plan doc, one row per unit of work.</sub></p>

```text
| id | Waits on         | state       | proof |
|----|------------------|-------------|-------|
| W1 | -                | not started |       |
| W3 | W2               | not started |       |
| W5 | external: <what> | not started |       |
```

<kbd>State</kbd> `not started`, `running`, `DONE <date>`, `PARTIAL` or `STOPPED`.<br>
<kbd>Ready</kbd> a row that is `not started` and every id in its `Waits on` is `DONE`.<br>
<kbd>External</kbd> an `external:` entry is never satisfied by the table. **You clear it.**<br>
<kbd>Clean</kbd> the default branch of each repo the wave edits has no uncommitted changes before anything spawns.<br>
<kbd>Seams</kbd> two rows that would touch one file are either serialised (one waits on the other) or told which functions each may edit, so they never meet. Merge order is set now.

---

<a name="the-lease"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🤝 The lease 🤝<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>N rows in parallel is N strong-model helpers plus their children: <b>a spend you say yes to once</b>.</sub></p>

<kbd>The statement</kbd> row ids, how many helpers, what each does, when the wave ends.<br>
<kbd>Your yes</kbd> one question box. A row that becomes ready mid-wave and was not in the statement is asked about again, not rolled in.<br>
<kbd>First time</kbd> the first wave a repo runs this way is capped at 2 rows.

#### Real example

A later wave in a long plan (the first-wave cap of 2 was long past). The main session ended its reply with the statement, then asked. Trimmed:

```text
Wave 5 proposal (ready set from table: I7, I9, REQ1, M1; H1 waits M1, G waits external probe).

Seam clash: I7 (extras) and REQ1 both own `install/options.tsv` + `scripts/agent-tiers`. Serialise: I7 waits on REQ1 (REQ1 changes the row format; I7 adds rows in it).

| Row  | Repo | Does  | Merge pos |
| REQ1 | kit  | [...] | 1         |
| I9   | kit  | [...] | 2         |

Lease: 3 opus subleads now, 4th (I7) spawned when REQ1 merges. Ends when all four merged or stopped.
```

| The ask<br><img src="assets/spacer.svg" width="110" height="1"> | As it went |
|---|---|
| The question | Run wave 5 as laid out above (REQ1, I9, M1 now; I7 after REQ1 merges)? |
| Options | all four **(Recommended)**; all but I7; kit rows only |
| Answered in | **70 s**, first option |

---

<a name="the-spawn"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🚀 The spawn 🚀<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>One helper per ready row, all in one message, all in the background.</sub></p>

<kbd>Worktree</kbd> `worktree.sh up <id>`: a separate copy of the repo on branch `<id>`.<br>
<kbd>Brief</kbd> self-contained, because the helper starts blind: the row's section of the plan, the absolute worktree path, what it owns and must not touch, its merge position, its check command, its own scratch folder, the commit rule (commit on the row branch when the repo's `review_gate` is `push`, otherwise leave the change for the main session to commit after review), and "if this row reads as more than one session, return a FORK at turn one".<br>
<kbd>Tag</kbd> the brief's first line is `[sublead-approved: plan row <id>, wave <date>]`. It names the lease the spawn belongs to; your yes in the question box is the approval.<br>
<kbd>Then</kbd> the main session ends its turn and waits. It never polls; returns arrive as notifications.

What the tag changes:

```diff
- Agent  subagent_type: sublead  prompt: "Build row REQ1 [...]"
  task-spawn-guard asks you first: no approval tag on a sublead spawn
+ Agent  subagent_type: sublead  prompt: "[sublead-approved: plan row REQ1, wave 2026-10-15] Build row REQ1 [...]"
```

---

<a name="a-fork"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">📥 A fork 📥<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>A helper cannot ask you. An open decision comes back as a <b>FORK block</b>.</sub></p>

<kbd>From the plan</kbd> if the plan or a tracked doc already settles it, the main session answers from the doc and cites the line. You are not asked.<br>
<kbd>Otherwise</kbd> one question box: the helper's readings as options, costs in countables, its default first and marked.<br>
<kbd>Written down</kbd> the decision goes into the row's plan section the same turn, so a re-run does not ask again.

#### Real example

```text
FORK: removing Write from the reviewer leaves doctrine and two commands saying it has Write
  readings: (1) fix them now [...] (2) revert item 4 and keep the Write-based def
  default: (1), because item 4 was asked for and doctor would otherwise flag every install
  cost: 4 files, 7 sites, 1 doctrine-vN bump [...]
  blocks: merging [...] without a broken doctor check
```

Put to the person with **3 other open decisions** as one box of 4 questions; answered in under two minutes.

---

<a name="the-merge"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">✅ The merge ✅<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Rows are merged by the main session or stopped. Nothing merges on a summary.</sub></p>

<kbd>Read the diff</kbd> not the report. Every check the helper names must exist and its result must be in the return.<br>
<kbd>Review</kbd> anything non-trivial gets an independent reviewer on the diff, with a planted mistake to prove it read it.<br>
<kbd>Merge</kbd> in merge position only: `git merge --no-ff --no-commit <id>`, the check runs on the merged tree, then the commit. A clash sends the row's helper back to merge the default branch in and re-run its check. A row that blocks the order for long goes to you as a fork, never a silent skip.<br>
<kbd>Teardown</kbd> `worktree.sh down <id>` once merged; it refuses an unmerged or dirty worktree.

> [!WARNING]
> **Three ways a row stops** instead of finishing. `STOPPED (fork)`: an open decision, answered as above. `STOPPED (a)`: a guard or permission stop, quoted; the main session settles it (your call, or another route) and resumes the row, which does not count as an attempt. `STOPPED (b)`: a check it could not make pass; repaired once by resuming with the failing check quoted, or re-shaped. A further try would be the third attempt, so it goes to you first.

#### Real example

| Elapsed<br><img src="assets/spacer.svg" width="48" height="1"> | What happened |
|---|---|
| 0h00 | `/plan-wave` on a plan doc. One question box, answered in 70 s. Three helpers spawned. |
| 0h32 | First row merged after review and a re-run of its checks. |
| 9h15 | A burst: 4 helpers in 22 minutes, 11 question boxes, 16 messages typed in the hour. |
| 13h18 | Unattended mode on. The person leaves. |
| 13h29 | A guard refuses a merge commit: it names a file only the person may change. Three commands handed back. |
| 19h51 | The person is back and runs them. Two more helpers spawned. Merges at 20h56 and 21h16. |

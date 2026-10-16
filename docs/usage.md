<a name="top"></a>
# Using the kit

[Back to the README](../README.md)

The kit lets your agent run with **more freedom**: it hands work to helper agents, runs jobs in
parallel, and keeps going while you are away. At the same time it **tightens protection**: a guard
stops a dangerous act before it runs, and its message tells the agent what to do instead. And it
**smooths known pitfalls** that waste a session without anyone noticing: a `pgrep -f` that matches
its own shell, a long `pnpm` check or `git commit` piped into `tail` that loses its exit code, a poll loop that never ends,
a recursive `grep` that silently skips binary files.

This page shows what that looks like day to day, with real captures. Words in bold that you do not
know are in the [Glossary](#glossary). Every number comes from one maintainer's own sessions, a heavy
and unusual user: read the numbers as a ranking of what is common, not as a prediction for you.

**Reading this page.** Times are UTC (a trailing `Z` means UTC). Row ids such as P1, PX, RG2, RD1,
DOC1 and REQ1 are names of rows in one real plan and mean nothing outside it. "Real capture,
trimmed" means copied from a real session and cut with `[...]`.

- [Why delegate at all](#why-delegate-at-all)
- [Work shapes](#work-shapes)
- [Choosing a level](#choosing-a-level)
- [What changes after install](#what-changes-after-install)
- [plan-wave](#plan-wave)
- [Glossary](#glossary)

## Why delegate at all<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

Six effects, each with one real example.

| Effect | In one line | Real example |
|---|---|---|
| 1. You stay in the conversation | The main session (the **Lead**) keeps talking to you while agents work in the background. | While one **sublead** row ran, the person typed 6 new messages into the main session and the main session forwarded 8 messages to that running agent (15:55Z to 16:09Z), without waiting for the agent to finish. |
| 2. More sets of eyes | The agent that writes a change never reviews it. A **reviewer** starts from a fresh context, so it does not inherit the writer's assumptions. A deliberately planted mistake in the review brief (a **planted control**) shows whether the reviewer actually read the change. It proves reading, not that it found everything. | In the plan's wave table (its proof column), row DOC1's review "found 7 real + caught the planted control". |
| 3. The right model per job | Mechanical work goes to a fast model, a hard call to a strong one. | Over 24 sessions in one project's history, main sessions made 240 spawns: Explore 79 (72 of them on sonnet), **worker** 60 (sonnet 50, haiku 8, opus 2), sublead 43, reviewer 39, **advisor** 11. Sublead, reviewer and advisor run on the model named in their agent definition (the agent's own file), opus, unless a spawn names another. |
| 4. Work in parallel | Separate plan rows run at once, each in its own git **worktree**. | The second screenshot below: two subleads on two plan rows at the same time. |
| 5. The mess stays out of your thread | File dumps, test output and dead ends stay inside the sub-agent. The main session receives its final report. | Token examples in the list after this table. |
| 6. Stops and questions come back to one place | A sub-agent cannot reach you. Its open decisions return to the main session as a **FORK block**, and the main session asks you one batched question. | A real FORK block and the question that followed, below. |

**Effect 5, in numbers.** Each figure is the tokens the sub-agent reported using at exit. The exact
meaning of that field is undocumented, so these are examples, never a total and never "a saving".
None of it entered the main session's context except each final report.

- sublead, row P1: 221,451. Row PX: 260,516. Row RD1: 160,346.
- sublead, row RG2: 258,340 at its first return, 279,633 at the end of its resume (do not add
  them).
- Explore, a docs sweep: 122,388. Reviewer, a doctrine review: 121,597 and 142,112 (two reviews).

**Effect 6, a real FORK block.** Real capture, trimmed. A sublead returned this (commit ids
dropped):

```text
FORK: removing Write from the reviewer leaves doctrine and two commands saying it has Write
  readings: (1) fix them now: skills/agent-tiers/SKILL.md:161,346-350,357 (doctrine bump),
            skills/delegation/SKILL.md:108, commands/init.md:54-55, commands/doctor.md:16 (doctor and init
            check for `tools: Read, Grep, Glob, Write`, so they now report a mismatch on every install)
            (2) revert item 4 and keep the Write-based def
  default: (1), because item 4 was asked for and doctor would otherwise flag every install
  cost: 4 files, 7 sites, 1 doctrine-vN bump, an install-flat re-run; [...]
  blocks: merging [...] without a broken doctor check
```

The main session put it to the person, together with three other open decisions, as one question
box holding 4 questions (sent 11:23:44Z, answered 11:25:32Z). Each question carried its readings,
a marked default and a `Checked:` line. Take the shape from the capture: what is open, the
readings, a default, the cost, and what it blocks. The file names inside it do not matter.

## Work shapes<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

Most common first. For each shape: what happens, what the agent can now do on its own, and what
stops it going wrong. "Level" says which install level switches the stopping mechanism on (see
[Choosing a level](#choosing-a-level)). Effects point back to the table above.

### a. Long sessions, several at once

![The status line and agent tree of a long session: an Opus Lead, context 37%, 25h46m, one sublead with four Sonnet children](assets/usage-long-session.png)

*A long session as captured (masked: the folder name, the session id and part of one agent's progress label). Opus Lead, context 37% (373k of a 1,000k window), session clock
25h46m, +6270/-717 lines, idle 0s, auto mode on, 6 agents. The tree shows one sublead (Opus, high
effort) and its four Sonnet children, each on a named evidence task. The 37% is the context used
since the session's one compaction (2026-10-16T04:36Z; the session began at 14:13Z the day before, so its 25h46m clock puts the capture near 15:59Z, about 11.4 hours after the compaction), not
over the whole 25h46m.*

![The status line of a second session in a second project: two Opus subleads running two plan rows in parallel](assets/usage-parallel-session.png)

*A different session in a second project, captured at the same time (masked: the folder name, the
session id and parts of two agents' progress labels). Opus Lead, context 29% (292k of 1,000k),
session clock 12h26m, +12260/-1412 lines, idle 532s (the main session had written nothing for 532 s), auto mode on, 6 agents
plus 1 shell. Two Opus subleads run two plan rows in parallel: one has a Sonnet child at medium
effort, the other is waiting on its full check re-run. One compaction, at 2026-10-16T07:08Z; the
last event before the capture was about 15:48Z, so the 29% is context used in about 8.7 hours
since that compaction.*

Which part of the status line is whose:

| Part | Whose |
|---|---|
| Folder, model, git branch, context bar with used/window and cache-read tokens, session duration, lines added and removed this session, short session id, `idle:Ns` (seconds since the transcript was last written) | The kit's main status line (`scripts/statusline.sh`), the optional "Status line" extra |
| Per-agent rows: `[model / effort]` (`-` when the host reports no effort), a `1M` badge for the 1M-context model variant, the task description, then `->` and the agent's live progress label | The kit's `scripts/statusline-subagent.sh`, same extra |
| The `auto mode on (shift+tab to cycle)` line, the agent and shell count, the `main` row, the tree lines, `1 more` | Claude Code's own interface |

**What one real long session looked like** (first event 2026-10-15T14:13Z, counted up to
2026-10-16T16:07Z). Counts come from its transcript and its sub-agents' transcripts.
Counts include spawns a guard later denied; resumes by message are not counted.

| What | Count |
|---|---|
| Spawns, in total | 103: 24 by the main session, 79 by its sub-agents |
| Spawns by type | reviewer 41, worker 33, sublead 16, Explore 12, advisor 1 |
| Spawns by `model:` parameter | sonnet 36, opus 22, haiku 1, none 44 (none means the agent definition's own model) |
| Messages typed by the person | 52 (plus 25 question-box answers); longest gap between typed messages 7h44m |
| Question-box calls | 26, holding 43 questions: 1 denied by `ask-gate`, 25 admitted and answered in a median of 30 s (min 4 s, max 934 s) |
| FORK blocks from sub-agents | 9, in 6 hand-backs: 3 hand-backs led to a question to the person (1 of the 3 inferred from the question's header), 3 the main session settled without asking (2 stated in its text, 1 inferred) |
| Merges | 18 merge commands (each `--no-ff --no-commit`: a merge that always makes a merge commit and stops before committing, so the check runs on the merged tree first; then commit) merging 17 branches (15 plan rows) |
| Messages sent to existing agents (running or finished) | 18, all carrying `RESUME-OK` (a marker that says resuming a finished agent is intended) |
| Replies ending in an operator tag | 122 of 163 main-session text blocks (57 `no_input_required`, 40 `want_input`, 25 `ask_next`) |
| Stop send-backs from `notify-tag-guard` | 26 (25 `ask_next`, 1 missing tag); `ask-gate` denied 1 question and admitted 25 |
| Guard denies | 13 in the main session, 40 in its sub-agents before 15:53Z (most common: 9 recursive `grep`, 8 "DELEGATED AGENT" conversions, 4 `task-spawn-guard`, 3 `pgrep`, 4 `long-run-guard`) |

A short timeline, scrubbed:

| When (UTC) | What happened |
|---|---|
| Day 1, 14:13 | The person starts the session with `/plan-wave` on a plan doc. 14:14: one question box (2 questions, the first: run wave 5?) answered in 70 s. 14:16: three sublead agents spawned in the background. The main session idles between hand-backs. |
| Day 1, 14:45 | First row merged after the main session reviews it and re-runs the checks. A long-run guard denied the first merge command once; the retry passed. |
| Day 1, 23:28 | A burst: 4 subleads spawned in 22 minutes while the person answers 11 question boxes and types 16 messages in that hour. |
| Day 2, 03:31 | The person sets unattended mode and leaves (see below). |
| Day 2, 10:04 | The person runs 3 handed-back commands. 10:11: two more subleads spawned. Merges committed at 11:09 and 11:29. 11:16: the person turns unattended off. |

#### Runs on its own

- **Plan rows as subleads**, each in its own worktree, in the background ([plan-wave](#plan-wave)).
  No level needed: the agent definitions and the skill ship with the kit. Effects 1, 4, 5.
- **Background agents report back** when done. `subagent-bg-return-guard` (group `delegation`,
  level `full`) blocks a sub-agent from returning while a background command it started is still
  running: it is sent back once, to wait for the command or to say plainly that its result was not observed.
- **Unattended mode** (`/agent-tiers:unattended on`; the command ships with the kit). While it is
  on, a question box or plan mode is denied with text telling the agent to take the reading that
  keeps existing behaviour and is the smaller diff, note the fork in its report, and continue, and
  other guards' asks become actionable denies. The question-box and plan-mode denies come from
  `unattended-guard` (group `attention`, level `full`). Every other guard that would ask (review gate,
  `reach-guard`, `peer-guard`) turns the ask into a deny the agent can act on instead; that is built
  into those guards, so it needs their groups on, not the attention group.
- **Long checks cannot hang** (`long-run-guard`, group `shell_footguns`, level `recommended`): it
  denies a `pnpm` check, build or typecheck, or a `git commit`, that is piped into another command,
  backgrounded, polled in a `while`/`until` plus `sleep` loop, or run with a tool timeout under 10
  minutes (for a commit, only when the repo has a pre-commit hook). For any command, it denies a sleep
  loop that watches an agent's output file or has no bound.
- **Desktop notifications** on permission prompts and on `operator:want_input`, and the
  **end-of-reply tag** (group `attention`, level `full`; the tag check and the `want_input`
  notification act only in the native Claude Code CLI).
- **Sessions side by side** (`peer-guard`, group `multi_session`, level `full`, Linux only): notes
  another live session in the same repo, and denies a session's first write into a different repo
  with text telling the agent to read that repo's docs first; the retry then goes through.

#### Back and forth

A decision the agent cannot make comes back as **one batched question** with a marked default and
what was checked, instead of a guess. Two guards keep that honest (group `attention`, level `full`,
native CLI only). First, `ask-gate` refuses, once, a question box that does not come straight after
a Stop-hook **send-back** (ending a reply with `operator:ask_next` is what triggers one). The reason:
text written just before a question box can reach you only as a one-line summary, so the context goes
in a finished reply first. Real capture, trimmed:

> Not yet: ask only after your context has ENDED a reply. Text written before a tool call (this
> question included) can reach the operator only as a one-line summary, so the table or findings
> this decision needs may never be seen. End this response now with that context as plain text, with
> no question in it, and make its final line exactly: operator:ask_next - you are sent straight back
> here to ask, and the question is admitted then. [...]

Then `notify-tag-guard` sends the agent straight back to ask. Real capture, trimmed:

> agent-tiers: ask_next - the context above has been delivered. Ask the decision NOW:
> call AskUserQuestion as the only thing in this response, with no text before it [...]

In the long session above, `notify-tag-guard` sent the agent back with `ask_next` 25 times, and its
25 admitted question-box calls were answered in a median of 30 s. With unattended mode on, this
exchange is replaced by the deny text described above.

**Unattended, as it really went.** The flag was on for 7h45m (03:31Z to 11:16Z). No question was
asked in that window, so the unattended deny never fired in this session (the mechanism above is
described from the script, not from this session). About 11 minutes in, a row's fork was settled
from the plan, the suite passed under two shells, and then `reach-guard` denied the merge commit,
because its message named a file only the person may change. Real capture, trimmed:

> reach-guard: this command writes to or acts on reach-guard's own allowlist, class data, state, kill
> switch or a settings stand-down key (reach-guard), and it is not a pure read. No agent changes
> those, the session Lead included: the user does it by hand outside the agent session. Do not retry
> a variant or route around it with another tool.

In plain words: `reach-guard` leaves any act on its own allowlist, data (its table of which commands
reach where) or switches (including the file that turns it off) to the person. This merge commit's
command named its allowlist file, so it refused and the main session handed the commit back.

The main session stopped with `operator:want_input` and handed back 3 commands. Real capture,
trimmed:

```text
git -C ~/.claude/agent-tiers commit -m "Merge row RA1: reach-guard labels, persist line, read grants"
sh ~/.claude/agent-tiers/scripts/worktree.sh down RA1
sh ~/.claude/agent-tiers/scripts/install-flat.sh --with-reach-guard-grant
```

The last line re-wires the hook that turns your yes to a `reach-guard` question into a session-long
allowance.

The session then waited about 6h20m (03:42Z to 10:04Z) until the person ran them. That is the honest shape of
unattended mode: it keeps the agent going on what it may decide, and still stops at what only the
person may do.

### b. A read-only sweep

- **You ask:** look through some files and report back.
- **Main session:** spawns **Explore**, a built-in Claude Code agent that only reads, on sonnet, and
  can run several at once. The most common spawn: 79 Explore spawns, in 14 of those 24 sessions (72 on sonnet, 5 on
  opus, 1 with no model, 1 pinned to a specific model id). Explore gives no check-in line.
- **On its own:** reads and classifies, returns a table. The main session decides what to write.
- **What stops it going wrong:** `task-spawn-guard` (group `delegation`, level `full`) denies an
  Explore spawn with no `model:`, because it would silently inherit the main session's model and an
  Opus fan-out would cost accordingly. Real capture, trimmed (an older Claude Code version printed it without the usual hook-error prefix):

> agent-tiers: an Explore spawn inherits the Lead's own model unless one is passed explicitly, so a
> fan-out under an opus Lead silently becomes an opus fan-out. Add model: "sonnet" to this spawn's
> tool_input (or a stronger model only if the reasoning genuinely needs it), then retry.

- **Effects:** 3, 5.

Real capture, trimmed. The spawn (2026-10-14T12:18:35Z): `subagent_type: Explore`, `model: sonnet`,
description "Classify 11 docs STATUS", prompt starting "Read-only classification task. Do not edit
anything." It returned a table at 12:19:48Z. The main session then spot-checked the evidence it
cited before using any of it.

### c. A routine change

- **You ask:** a small, fully specified fix.
- **Main session:** briefs a **worker** (sonnet, medium effort, can edit and run commands) in its
  own worktree, then a reviewer (opus, no shell) on the resulting diff, then commits.
- **On its own:** the worker edits and verifies. The reviewer returns findings inline.
- **What stops it going wrong:**
  - `review-gate-guard` (group `commit_review`, level `recommended`): before a commit, push,
    `gh pr create` or `gh pr merge` with no reviewer, advisor or `codex-read` spawn in the session,
    it asks once per session per repo. With `review_gate: push` in the repo's
    `.claude/agent-tiers.local.md`, local commits pass and only publishing asks. For a sub-agent, or
    an unattended session, the ask becomes a deny that says what to do. Real capture, trimmed:

> SC-5.2: this session has no independent review pass yet (no reviewer / advisor / codex-read spawn
> seen; a /codex:review run is not detected, say so if you did one) and is about to commit in [...].
> Non-trivial diff -> spawn a reviewer first (one opus call, announce-only). Trivial (typo, doc
> line, config nudge) -> proceed; this asks once per session per repo.

"Announce-only" means the main session states it is making one opus call and proceeds without asking.

  - `hygiene-commit-guard` (same group): denies a commit that adds an em or en dash, curly quote,
    non-breaking or zero-width space, or ellipsis glyph. That is a cost of the level, stated plainly.
  - `git-add-stash-guard` (group `safety`, level `recommended`): denies blanket staging (`git add -A`,
    `.`, `-u`) and every `git stash` except `list` and `show`.
- **Effects:** 2, 3, 5.

Real capture, trimmed (2026-10-12). The worker's brief began "Work ONLY in the git worktree [...]
Edit only scripts/codex-guard.sh, scripts/codex-guard.selfcheck.sh and the two comment lines in
scripts/guard-cmdpos.sh named below. No commit, no stash, no spawning agents." Its check-in line
and the reviewer's:

```text
Hi, I'm worker - Worker tier, def-v8. Fixed the codex-guard.sh heredoc-scan defect (lines-after-heredoc bypass) and the two stale guard-cmdpos.sh comments.
Hi, I'm reviewer - Reviewer tier, def-v11. Adjudicating 10 pre-publish fix claims against the kit diff.
**Result: 8 CONFIRMED, 2 REFUTED, 0 UNVERIFIABLE.** Both refutations are narrow: the claim says more than the code does [...]
```

The fix itself does not matter here; the shape does. The reviewer checked 10 claims about a whole
pre-publish fix round: this worker's change, a second worker's, and edits the main session made itself.
8 held and 2 did not, and one of the 2 was the planted mistake, which is how the main session knew the
reviewer had read the diff.

The main session's next text: "Control caught (claim 2 REFUTED). The rest is small follow-on comment
and doc drift, fixing it myself." The worker had not committed; the main session applied its diff and
committed it with the rest of the round. The commit subject: "fix: pre-publish review - codex-guard heredoc bypass, hygiene
heredoc scan, leaks, Sublead docs".

### d. A design question

- **You ask:** which of two designs, or what is wrong with this plan.
- **Main session:** spawns an **advisor** (opus, read-only: its tools are Read, Grep and Glob) with one
  bounded question. It returns findings, a recommendation and a confidence.
- **What stops it going wrong:** it cannot edit or run anything, and the main session checks its
  citations before folding the answer in. An advisor spawn also counts as a review for
  `review-gate-guard`.
- **Effects:** 2, 3.

Real capture, trimmed (2026-10-10). Check-in and the first recommendation line:

```text
Hi, I'm advisor - Advisor tier, def-v9. Pressure-testing the SC-4.2 planted-control redesign (liveness vs recall) and drafting the replacement text. Runtime model/effort: **unverified** (no harness evidence available to me).
HANDOFF: adopt the liveness/recall split with three changes. [...]
```

The main session's next text: "Advisor citations verified (SKILL.md:166-177, template:49-50,
task-spawn-guard:86). Folding advisor result into plan, then gating 4 forks."

In plain words: "liveness vs recall" is whether a planted mistake shows the reviewer read the change,
versus whether it found everything. "HANDOFF:" is the advisor's recommendation line.

### e. A multi-part plan, in parallel

Several rows at once, one sublead per row, each in its own worktree, merged in a set order. See
[plan-wave](#plan-wave). Effects 1, 2, 4, 5, 6. Level: the skill ships with the kit; a sublead spawn without
its `[sublead-approved:...]` tag is asked about by `task-spawn-guard` (level `full`).

### f. A risky or quietly broken command

A guard denies it and tells the agent what to do next. The table lists every guard with at least 10
denies or asks in the maintainer's own guard log (2026-08-16 to 2026-10-16, rows carrying a real
session id), plus `unattended-guard`, ranked by denies plus asks. The counts measure how often each pitfall came up, not harm prevented. Each deny text is
addressed to the agent and names the next step.

| Guard (group, level) | Count | What would have gone wrong without it |
|---|---|---|
| `grep-footgun-guard` (shell_footguns, recommended) | deny 1729 | A recursive GNU `grep` skips files it deems binary, so "no matches" can be false. |
| `pgrep-footgun-guard` (shell_footguns, recommended) | deny 305 | `pgrep -f` matches the full command line, including the shell wrapping the call, so a "still running?" check can match itself. `pkill -f` can signal its own parent. |
| `review-gate-guard` (commit_review, recommended) | ask 196, deny 105, passed 211 (commits let through in `review_gate: push` mode) | A commit or push goes out with no independent review in the session. |
| `long-run-guard` (shell_footguns, recommended) | deny 195 | A `pnpm` check or build, or a hooked `git commit`, piped into another command loses its exit code; backgrounded or under-timed, it ends with no exit code; a sleep loop with no bound can poll forever. |
| `sc52a-write-disclosure-guard` (commit_review, recommended) | deny 151, ask 9 | Writes to tracked files that bypass the edit tools (`sed -i`, `tee`) with no stated reason. |
| `memory-write-gate` (memory, full) | deny 124 | A new memory note is written without first checking whether the fact is already recorded, and without asking you. |
| `hygiene-commit-guard` (commit_review, recommended) | deny 117 | A commit carries an em or en dash, curly quote, odd space or ellipsis glyph. |
| `security-gate` (safety, recommended) | deny 63 | Content about to be written holds a live-looking key, a private key header, a hard-coded secret, or code that builds SQL or shell commands from strings. |
| `simple-rules-guard` (multi_session, full) | deny 62 | Small literal rules: a question box whose first option is not marked `(Recommended)`; a message that could resume a finished agent by accident (it carries neither `RESUME-OK` nor `NOOP-IF-DONE`); waking a long-idle session; `codex exec resume --last` attaching to the wrong thread. |
| `git-add-stash-guard` (safety, recommended) | deny 59 | Blanket `git add` stages untracked scratch files. `git stash` is one ref shared by every worktree, so it can take another session's uncommitted work. |
| `reach-guard` (safety, recommended) | deny 33, ask 21 | An agent runs a command that reaches another machine or a logged-in account. |
| `task-spawn-guard` (delegation, full) | deny 44 | A spawn on the wrong model, a worker on opus with no stated reason, a sublead from a sub-agent. |
| `peer-guard` (multi_session, full) | deny 40, ask 2 | A session writes into another repo without reading its docs. |
| `ask-gate` (attention, full) | deny 28 | A question box reaches you without the context it depends on. |
| `worktree-guard` (safety, recommended) | deny 20 | A hand-typed `git worktree add` drifts from the one recipe in `scripts/worktree.sh` (branch, path, base); a bare `git worktree remove` skips its merged-and-clean check and branch cleanup. |
| `vcs-commit-guard` (commit_review, recommended) | deny 10, ask 9 | A commit includes a file the repo's policy marks as personal or not shared. |
| `dangerous-actions-blocker` (safety, recommended) | deny 14 | A force-push to main or master, a publish, a protected credential file, a live key on a command line. |
| `read-basis-guard` (planning, full) | deny 14 | A plan goes to you for approval naming tracked files the session never opened. |
| `codex-guard` (delegation, full) | deny 12 | A bare `codex` call skips the kit's wrapper and its secrets scan. |
| `unattended-guard` (attention, full) | deny 3 | A question box or plan mode with nobody there to answer. |

Separately, `notify-tag-guard` (attention, full) sent a reply back for a missing or doubled tag 343
times. Two guards that act only inside the kit's own checkout are left out of the table.

Real capture, trimmed. `grep-footgun-guard`:

> Recursive GNU grep without -a/--text silently skips files it deems binary (NUL/invalid bytes; plain
> CJK is fine) - documented CLAUDE.md footgun. Re-run with 'rg' (preferred) or add '-a' to grep.

Real capture, trimmed. `long-run-guard`, on a `git commit` with no `timeout`:

> deny: a long check/build/commit needs timeout >= 600000 on the tool call, or the harness
> auto-backgrounds it at 120000ms with no exit code. run it foreground, no pipe, timeout: 900000 on
> the tool call, and read the exit code directly - never pipe (| or |&) into another command, never
> run_in_background or a trailing & background operator, never poll it in a while/until+sleep loop.

When the caller is a sub-agent, an ask is returned as a deny that addresses it. Real capture, trimmed:

> DELEGATED AGENT: this tool call came from a sub-agent, not the session Lead, so a question with no
> one able to answer it is returned as a deny instead of a halt. This gate is the Lead's to clear, not
> yours - do not retry a variant or route around it with another tool. Stop, and report this text
> verbatim in your final message so the Lead can see it and act. [...]

### g. Rarer shapes (described, not captured)

Both are rare by design: the Boss is a last resort, and the cross-lab Codex path is opt-in per
session. Claude Code keeps session transcripts for about 30 days, and no run of either fell inside the
sessions this page was drawn from. So they are described here rather than shown.

- **Genuinely stuck: the Boss.** A different model from the Lead, called in only after repeated
  failed attempts or circular reasoning, on a distilled brief. It decides on the brief and never
  edits. It always needs the person's yes.
- **A cross-lab second opinion: `codex-read` and `codex-write`.** Opt-in, they need the `codex` CLI
  and per-session consent. `codex-read` returns a second lab's findings, read-only. `codex-write` is
  the write path and its output always needs a Claude review. `codex-guard` (group `delegation`,
  level `full`) denies a bare `codex` call and routes it through the kit's wrapper. The closest real
  capture is a guard live-fire, not a `codex` run: `simple-rules-guard` (group `multi_session`, level
`full`) denied `codex exec resume --last` with
  "resuming the last codex session with --last is ambiguous once more than one session exists, and
  it has attached to the wrong thread before. Resume by explicit session id instead [...]".

## Choosing a level<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

A level is a named bundle of groups. A plain install is `core`, with no guards. Ground truth is
`install/options.tsv`.

| Level | Suits | You will notice | What it costs you |
|---|---|---|---|
| `core` | Trying the kit, or not ready for guards | Check-in lines on every agent report, the handoff file re-injected at session start (if the project has one), a session-end count in the guard log | Nothing is blocked. |
| `recommended` (core + `safety`, `shell_footguns`, `commit_review`) | A solo developer who wants safety with few prompts | Denies on destructive commands, secrets and the shell footguns above; an ask at the first commit of a session | The review-gate ask (once per session per repo), `reach-guard` asks before an agent's read-only command on another machine or account and hands any other such command back to you, hygiene denies on dashes and odd glyphs, `sed -i` and `tee` writes to tracked files denied unless you state why |
| `full` (every group) | Several agents, parallel sessions, long or unattended runs | Everything above, plus delegation rules, the end-of-reply tag and badge, notifications, peer notes | Every reply must end with an operator tag or it is sent back (native Claude Code CLI only); a new memory note needs a coverage check and a question to you; a question box needs its first option marked `(Recommended)` and a message to an agent needs `RESUME-OK` or `NOOP-IF-DONE`; a manual `/compact` can be blocked while the handoff file (`RESUME_SESSION.md`) is older than the session's latest edits; spawning a sublead without its approval tag asks you first |

**Which level for a solo developer who wants safety with few prompts?** `recommended`. The review gate
asks at most once per session per repo, and not at all once a reviewer has run; `reach-guard` asks
only when an agent's command reaches another machine or account. Most other guards deny, and the agent
fixes the command itself; a few (`reach-guard`, `dangerous-actions-blocker`) hand the command to you.
If you commit
first and review before publishing, add `review_gate: push` to the repo's
`.claude/agent-tiers.local.md` (`/agent-tiers:init` creates it): local commits then pass and only a push or PR asks.

**To drop one hook:** `agent-tiers configure --set disabled_hooks=<id>,<id>`, where `agent-tiers` is
short for `sh ~/.claude/agent-tiers/scripts/agent-tiers` (on the plugin route, use `/agent-tiers:setup`). It replaces the whole list each time, so
name every hook you want off. Hook ids are the names in backticks in this page's tables and in
[hooks.md](hooks.md). Details:
[Change the setup later](install.md#change-the-setup-later).

| Group | Guards against |
|---|---|
| `safety` | destructive commands, risky writes, git actions that lose work, agent commands that reach other machines |
| `shell_footguns` | shell commands that fail quietly |
| `commit_review` | unreviewed commits, commit hygiene problems, private text leaking into a commit |
| `delegation` | sub-agent spawns and external agent calls that break the tier rules |
| `memory` | memory and note writes with unsafe content or no provenance |
| `attention` | a person missing a question, a permission prompt or an advisory |
| `multi_session` | parallel sessions on one machine clobbering each other |
| `planning` | a plan must declare files it names but never read; an approved plan is nudged to be saved; a manual `/compact` waits for the handoff file |

The full list of hooks is in [levels and groups](hooks.md#levels-and-groups).

## What changes after install<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

| Level or group | What you will see |
|---|---|
| Every level | **Check-in lines.** The first line of every kit agent's final report names its role and definition version, for example `Hi, I'm worker - Worker tier, def-v9. <task>`. It comes from the agent definitions, not a hook. It does not prove the model. Explore and other non-kit agents give none. |
| Every level | **Session start context (read by the agent, not shown to you).** One line naming the Lead's model **band**, the handoff file, arrival advisories and, on the flat route, a version stamp (the kit's rule-set version for the agent). Real capture, trimmed: `agent-tiers band (model=claude-opus-5-5, source=compact): reasoning band - delegate.` and `agent-tiers session stamp: doctrine-v30 [...]`. |
| `commit_review` (`recommended`) | **Commit asks about review**, as in work shape c. **Hygiene denies**: a commit adding an em or en dash, curly quote, non-breaking or zero-width space or ellipsis glyph is denied. This is a cost of the level. |
| Any guard | **Denies addressed to the agent.** Each says what to do next. Some tell the agent to stop and hand the act to you, to run yourself at the prompt or in a real terminal. |
| `attention` (`full`) | **Every main-session reply ends in a badge.** The agent must end each reply with exactly one line, `operator:want_input`, `operator:no_input_required\|reason:<why>` or `operator:ask_next`; a reply without it is sent back. On screen the tag line becomes `[[ ! INPUT NEEDED ]]`, `[[ NO INPUT NEEDED ]]` or `[[ QUESTION NEXT ]]`. The transcript keeps the tag. Desktop notifications fire on permission prompts and on `want_input`. The tag guard, `ask-gate` and the Stop notification act only in the native Claude Code CLI. |
| `attention` (`full`) | **Unattended mode** (`/agent-tiers:unattended on`): see work shape a. |
| `multi_session` (`full`) | **peer-guard notes and asks.** A note when another live session works in the same repo; a deny on a session's first write into a different repo (read its docs, then retry), or an ask when a live session already works there. Linux only. |
| Status line extra | **A status line**, if you accepted it at install: the rows described under work shape a. |

Real capture, trimmed. The last lines of three real replies:

```text
operator:no_input_required|reason:waiting on 4 background slice workers (A, B, C, D+E)
operator:want_input
operator:ask_next
```

Across 653 replies in 23 sessions with tagged replies, the tags ended: `no_input_required|reason:<text>` 341,
`want_input` 199, `ask_next` 106, bare `no_input_required` 7.

A reply with no tag is sent back with text like this. Real capture, trimmed:

> agent-tiers: this reply must end with exactly one of these, on its own final line, before
> the turn can finish:
>   operator:want_input
>   operator:no_input_required|reason:<why - e.g. waiting on a background command or subagent>
>   operator:ask_next   (this reply holds the context for a decision you ask next)
> [...]

## plan-wave<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

**What it is for.** `plan-wave` runs one wave of a plan as parallel sublead agents, one per plan row,
each in its own worktree, while you are present to answer forks. The skill is in
`skills/plan-wave/SKILL.md`; nothing in it is a script, the Lead runs the steps. The Lead is the only
thing that talks to you and the only thing that touches the default branch.

**The wave table.** One table in the plan doc, one row per unit of work:

```text
| id | Waits on | state | proof |
|----|----------|-------|-------|
| W1 | -        | not started | |
| W3 | W2       | not started | |
| W5 | external: <what> | not started | |
```

`state` is `not started`, `running`, `DONE <date>`, `PARTIAL` or `STOPPED`. A row is in the **ready
set** when it is `not started` and every id in `Waits on` is `DONE`. An `external:` entry is never
satisfied by the table; you clear it.

**Steps, in order.**

1. **The wave is the ready set**, computed, never hand-picked. The default branch of each repo the
   wave edits must be clean (no uncommitted changes).
2. **Seam owners are settled before spawning.** Two rows that touch one file are either serialised
   (one waits on the other) or given disjoint symbols. **Merge position** (the order the rows will
   merge in) is set now.
3. **The lease.** N rows in parallel is N opus subleads plus their children, a gated spend. The
   Lead states the wave once (row ids, N, what each does, when it ends) and gets your yes before
   spawning. The first wave a repo runs this way is capped at 2 rows. A row that becomes ready
   mid-wave and was not in that statement is re-gated, not rolled in.
4. **One worktree per row**: `worktree.sh up <id>`, on branch `<id>`.
5. **One self-contained brief per row** (the agent starts blind): the row's section of the plan, the
   absolute worktree path, what it owns and must not touch, its merge position, its check command,
   a scratch directory of its own (a temporary folder for its own working files), the commit rule
   (commit on the row branch when the repo's `review_gate` is `push`, otherwise leave the change for
   the Lead to commit after review), and "if this row reads as more than one session or its scope is
   unclear, return a FORK at turn one".
6. **Spawn**: one `Agent` call per ready id, all in one message, `subagent_type: sublead`,
   `run_in_background: true`. The prompt's first line is `[sublead-approved: plan row <id>, wave
   <date>]`. The Lead ends its turn while agents run and never polls.
7. **A FORK block** is answered from the plan if the plan settles it, otherwise asked of you as one
   question with the agent's readings as options, and the decision is written into the row's section.
8. **On `done`**: the Lead reads the diff, not the summary, then gets an independent review with a
   planted control for anything non-trivial, then merges in merge position with
   `git merge --no-ff --no-commit <id>`, runs the check foreground, and commits. A row whose turn has
   not come waits; a row that blocks the order for long goes to you as a fork, never a silent skip.
9. **Teardown**: `worktree.sh down <id>` once merged (a merged-and-clean gate).

Rows are either merged by the Lead or stopped. `STOPPED (fork)` means an open decision, `STOPPED (a)` a
guard or permission stop, `STOPPED (b)` a check the row could not make pass. Each has a defined next
move in the skill, and a third failed attempt goes to you.

**A real wave statement.** Real capture, trimmed. This is a later wave in a long plan, so the
first-wave cap of 2 rows had long been passed. The main session ended its reply with:

```text
**Wave 5 proposal** (ready set from table: I7, I9, REQ1, M1; H1 waits M1, G waits external probe).

**Seam clash:** I7 (extras) and REQ1 both own `install/options.tsv` + `scripts/agent-tiers`. Serialise: **I7 waits on REQ1** (REQ1 changes the row format; I7 adds rows in it).

| Row | Repo | Does | Merge pos |
|---|---|---|---|
| **REQ1** | kit [...] | 1 |
| **I9** | kit [...] | 2 |
[...]

- **Lease:** 3 opus subleads now, 4th (I7) spawned when REQ1 merges. Ends when all four merged or stopped.
- **Both repos clean**, review_gate = `commit` on both (Lead commits after review).
- Each sublead gets its own scratch subdir [...]
[...]

operator:ask_next
```

Then the question box, 5 seconds later (14:14:37Z), reformatted here as a list. Real capture, trimmed:

```text
Run wave 5 as laid out above (REQ1, I9, M1 now; I7 after REQ1 merges)? Checked: wave table, installer plan rows, options.tsv + CLI owners, review-gate mode both repos.
  1. Yes, all four (Recommended) - 3 opus subleads now, I7 4th after REQ1 merges; only clash serialised
  2. Yes, but no I7 - 3 subleads; I7 waits for a later wave and a fresh lease
  3. Kit rows only - REQ1 + I9 now, I7 later; M1 held, H1 stays blocked
[...]
```

The person picked the first option, the one marked `(Recommended)`, in 70 s. The three spawn prompts
then began `[sublead-approved: plan row REQ1, wave 2026-10-15]`, `[sublead-approved: plan row I9, wave
2026-10-15]` and `[sublead-approved: plan row M1, wave 2026-10-15]`. The tag records the lease; it is
not the approval itself. Take from the capture the shape: the ready set, a clash between two rows
settled by making one wait, the lease, and one question box to you.

Level: the skill ships with the kit. The guards around it (`task-spawn-guard`, `peer-guard`,
`git-add-stash-guard`, `worktree-guard`) belong to the groups named in work shape f.

## Glossary<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

| Term | Meaning |
|---|---|
| **advisor** | A read-only opus agent that answers one bounded design question and returns findings, a recommendation and a confidence. |
| **agent definition** | The agent's own file (in `agents/`), which names its model, tools and effort. |
| **/agent-tiers:init** | The command that sets up a project: it probes the environment, asks you to confirm the model once, and records the result in `.claude/agent-tiers.local.md`. |
| **announce-only** | The main session states it is making one opus call and proceeds without asking. |
| **auto mode** | Claude Code's own mode, shown in its status area as `auto mode on (shift+tab to cycle)`. Not a kit feature. |
| **band** | The Lead's model band (reasoning, top, interface, unranked, absent), injected as one line at session start. It tells the Lead to delegate (reasoning band) or plan before acting (interface band). |
| **boss** | A rare, always person-gated agent on a different model from the Lead, for when the Lead is genuinely stuck. |
| **check-in def-version** | The `def-v<N>` in a check-in line: the version of the agent definition that ran. An older number than the installed one means a stale cached definition. |
| **check-in line** | The first line of a kit agent's final report: `Hi, I'm <role> - <Role> tier, def-v<N>. <task>`. It names role and definition version, not the model. |
| **CLAUDE.md** | The instruction file Claude Code loads at session start, per project and per user. |
| **codex-read, codex-write** | Opt-in agents that hand a brief to the `codex` CLI: a read-only second opinion, and an implementation path whose output always needs a Claude review. |
| **compaction** | Claude Code summarising a long conversation to free context. The context percentage on the status line counts from the last one. |
| **context window** | How much conversation the model can hold at once. The 1M variant holds 1,000k tokens. |
| **core, recommended, full** | The three install levels: no guards; safety, shell footgun and commit-review guards; every group. |
| **coverage check** | Checking that a fact is not already recorded before writing it down as new. |
| **cross-lab, Codex** | A second opinion from a model made by another AI company. Codex is OpenAI's coding CLI (`codex`). |
| **default branch** | The repo's main branch, for example `master`. |
| **deny, ask** | The two ways a guard answers: a deny blocks the tool call; an ask blocks it until a person answers. For a sub-agent, or an unattended session, an ask becomes a deny. |
| **disabled_hooks** | A kit option listing hook ids to switch off one by one, whatever their group says. |
| **doctor** | `/agent-tiers:doctor`, the kit's health and housekeeping report. |
| **doctrine** | The kit's written rules for how agents route, review and stop, versioned as `doctrine-v<N>`. |
| **effort** | A model's reasoning-effort setting, for example `medium` or `high`. |
| **exit code** | The number a command returns when it ends; 0 means success. A pipe into another command hides it. |
| **Explore** | A built-in Claude Code agent that only reads. Not a kit agent, so it gives no check-in line. |
| **extra** | An optional add-on the installer offers, such as the status line; a settings extra is written only after a yes. |
| **Fable, Opus, Sonnet, Haiku** | Claude model names. Fable and Opus are the strongest (Fable above Opus); Sonnet and Haiku are faster and cost less per token. |
| **FORK block** | A sub-agent's return that says a decision is open: the readings, a default, the cost and what it blocks. |
| **gated** | Needs a yes from you, or an approval tag, before it runs. |
| **group** | A set of guards switched on together: `safety`, `shell_footguns`, `commit_review`, `delegation`, `memory`, `attention`, `multi_session`, `planning`. |
| **guard** | A hook that checks a tool call before it runs and denies or asks. |
| **handoff file** | `RESUME_SESSION.md`, a pointer file the kit re-injects at session start so a fresh context knows where the work stands. |
| **hard deny** | A deny that is never turned into an ask and has no override in the session. |
| **harness** | The program running the agent; the same thing as the host. |
| **hook** | A script Claude Code runs on an event, such as before a tool call or at session start. |
| **host** | The program running Claude Code: the CLI in a terminal, an IDE extension, or a desktop or third-party app. |
| **kit gate, stand-down** | Every hook first asks `scripts/kit-gate.sh`. It stands down (does nothing) when the kit is disabled, `AGENT_TIERS_OFF=1`, the hook's group is off or its id is in `disabled_hooks`. |
| **Lead (main session)** | The agent you talk to. It routes, briefs and verifies. |
| **lease** | Your yes to a stated wave: N rows in parallel, what each does, when it ends. |
| **memory** | Claude Code's memory files: notes an agent saves to keep facts across sessions. |
| **merge position** | The order a wave's rows merge in, set before spawning. |
| **native CLI** | The `claude` command in a terminal. |
| **operator tag** | The last line of a main-session reply: `operator:want_input`, `operator:no_input_required\|reason:<why>` or `operator:ask_next`. |
| **plan doc** | The document holding a plan, including its wave table. |
| **planted control** | A deliberate, undisclosed mistake placed in a review brief. Whether the reviewer reports it shows whether it read the change. |
| **plan-wave** | The skill that runs a plan's ready rows as parallel subleads, one worktree each. |
| **plugin marketplace** | Claude Code's way to add and install plugins (`/plugin marketplace add`). |
| **plugin route, flat route** | The two install routes: as a Claude Code plugin, or by cloning the kit and running its installer, which writes plain files under `~/.claude`. |
| **POSIX shell** | The standard, portable `sh` that the kit's scripts are written in. |
| **profile** | One Claude Code config directory (`~/.claude`, or `$CLAUDE_CONFIG_DIR`). |
| **provenance** | Where a fact came from. |
| **question box** | Claude Code's `AskUserQuestion` prompt: a question with clickable options. |
| **reach** | A command that reaches another machine or a logged-in account, such as `ssh`, a remote copy or a cloud CLI. |
| **ready set** | The wave-table rows that are `not started` with every `Waits on` id `DONE`. |
| **RESUME-OK, NOOP-IF-DONE** | Markers on a message to an agent. A message to a finished agent resumes it, so the sender must say which it means: `RESUME-OK` says resuming is intended, `NOOP-IF-DONE` says do nothing if it has finished. |
| **reviewer** | An opus agent that checks a diff from a fresh context and returns findings inline. |
| **review_gate** | A repo setting in `.claude/agent-tiers.local.md`: `commit` (default) asks at a commit or publish, `push` asks only when publishing. |
| **rg** | ripgrep, a fast search tool; `grep-footgun-guard` points to it in place of recursive `grep`. |
| **row** | One unit of work in a plan's wave table. |
| **SC-\*** | Stable ids of the kit's doctrine rules. Hooks quote them when they apply, for example SC-5.2, the independent-review rule. |
| **seam** | A file or symbol two rows both touch. Settled before spawning by serialising the rows or splitting the symbols. |
| **selfcheck** | A script that tests one hook against fixture inputs; the kit ships one per guard. |
| **send-back** | A Stop hook refusing to let a reply end and handing the turn back to the agent with an instruction. |
| **spawn** | Starting a helper agent. |
| **STOPPED (fork), (a), (b)** | A sublead's outcome line: an open decision; a guard or permission stop; a check it could not make pass. |
| **sublead** | An opus agent that leads one independent slice of a larger task over its own children. Gated: with `task-spawn-guard` on, a spawn without a `[sublead-approved:...]` tag asks you first. |
| **tier** | A role of helper agent: Lead, sublead, worker, advisor, reviewer, boss. |
| **tool call** | One action the agent takes: running a command, editing a file, asking a question, spawning an agent. |
| **unattended mode** | A per-session flag: a question that would halt the run comes back as an actionable deny instead. Turn it on with `/agent-tiers:unattended on`. |
| **wave** | The set of ready rows run together. |
| **worker** | A cheap, fast sonnet agent for fully specified mechanical jobs. It hands back to the Lead if a call needs judgment. |
| **worktree** | A separate checkout of the same repo on its own branch, so parallel rows do not touch each other's files. |

<a name="top"></a>
<h1 align="center">Glossary</h1>

<p align="center"><i>Every term the kit's pages lean on, in one place</i></p>

<div align="center">

| <img src="assets/spacer.svg" width="21" height="1">[**README**](../README.md)<img src="assets/spacer.svg" width="21" height="1"> | <img src="assets/spacer.svg" width="1" height="1">[**Why delegate**](usage.md)<img src="assets/spacer.svg" width="1" height="1"> | <img src="assets/spacer.svg" width="3" height="1">[**Work shapes**](work-shapes.md)<img src="assets/spacer.svg" width="3" height="1"> | <img src="assets/spacer.svg" width="29" height="1">[**Levels**](levels.md)<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="9" height="1">[**Plan waves**](plan-wave.md)<img src="assets/spacer.svg" width="10" height="1"> | <img src="assets/spacer.svg" width="20" height="1">**Glossary**<img src="assets/spacer.svg" width="20" height="1"> |
|:-:|:-:|:-:|:-:|:-:|:-:|

</div>

<hr>

> [!NOTE]
> Bold words on the other pages are defined here. Hook ids are the names in backticks on [Hooks and guards](hooks.md).

| Term<br><img src="assets/spacer.svg" width="267" height="1"> | Meaning<br><img src="assets/spacer.svg" width="600" height="1"> |
|---|---|
| **advisor** | A read-only opus agent that answers one bounded design question and returns findings, a recommendation and a confidence. |
| **agent definition** | The agent's own file (in `agents/`), which names its model, tools and effort. |
| **/agent-tiers:init** | The command that sets up a project: it probes the host where it can (the native CLI skips the probe), records what the panel reports as panel-reported, and writes `.claude/agent-tiers.local.md`. |
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
| **STOPPED (fork), (a), (b)** | A sublead's outcome line. `(fork)`: an open decision. `(a)`: a guard or permission stop. `(b)`: a check it could not make pass. |
| **sublead** | An opus agent that leads one independent slice of a larger task over its own children. Gated: with `task-spawn-guard` on, a spawn without a `[sublead-approved:...]` tag asks you first. |
| **tier** | A role of helper agent: Lead, sublead, worker, advisor, reviewer, boss. |
| **tool call** | One action the agent takes: running a command, editing a file, asking a question, spawning an agent. |
| **unattended mode** | A per-session flag: a question that would halt the run comes back as an actionable deny instead. Turn it on with `/agent-tiers:unattended on`. |
| **wave** | The set of ready rows run together. |
| **worker** | A cheap, fast sonnet agent for fully specified mechanical jobs. It hands back to the Lead if a call needs judgment. |
| **worktree** | A separate checkout of the same repo on its own branch, so parallel rows do not touch each other's files. |

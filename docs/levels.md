<a name="top"></a>
<h1 align="center">Levels</h1>

<p align="center"><i>Which guards you switch on, what you will notice, and what each level costs you</i></p>

<div align="center">

| <img src="assets/spacer.svg" width="21" height="1">[**README**](../README.md)<img src="assets/spacer.svg" width="21" height="1"> | <img src="assets/spacer.svg" width="1" height="1">[**Why delegate**](usage.md)<img src="assets/spacer.svg" width="1" height="1"> | <img src="assets/spacer.svg" width="3" height="1">[**Work shapes**](work-shapes.md)<img src="assets/spacer.svg" width="3" height="1"> | <img src="assets/spacer.svg" width="29" height="1">**Levels**<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="9" height="1">[**Plan waves**](plan-wave.md)<img src="assets/spacer.svg" width="10" height="1"> | <img src="assets/spacer.svg" width="20" height="1">[**Glossary**](glossary.md)<img src="assets/spacer.svg" width="20" height="1"> |
|:-:|:-:|:-:|:-:|:-:|:-:|

</div>

<hr>

> [!NOTE]
> A **level** is a named bundle of guard groups. The installer asks for one; you can change it later. Ground truth is `install/options.tsv`.

| Level<br><img src="assets/spacer.svg" width="153" height="1"> | What you notice<br><img src="assets/spacer.svg" width="300" height="1"> | As it looks<br><img src="assets/spacer.svg" width="1" height="1"> |
|---|---|---|
| 🟢 [**core**](#core) | **Nothing is blocked**<br><i>&rsaquo; Check-in lines, the handoff file at session start.</i> | `Hi, I'm worker - Worker tier, def-v9. Fixed the heredoc-scan defect`<br><sub><i>one real check-in line, trimmed; every kit helper's report starts like this</i></sub> |
| 🟡 [**recommended**](#recommended) | **Safety with few prompts**<br><i>&rsaquo; Destructive commands, secrets and shell footguns denied; few asks.</i> | `SC-5.2: this session has no independent review pass yet [...]`<br><sub><i>the review ask, once per session per repo</i></sub> |
| 🔴 [**full**](#full) | **Every group on**<br><i>&rsaquo; Delegation rules, the reply badge, notifications, peer notes.</i> | `operator:no_input_required\|reason:waiting on 4 background slice workers [...]`<br><sub><i>every main-session reply ends like this</i></sub> |

> [!TIP]
> Solo developer who wants safety with few prompts: **`recommended`**. Several agents, parallel sessions, long or unattended runs: **`full`**.

---

<a name="core"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🟢 core 🟢<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Trying the kit, or <b>not ready for guards</b>.</sub></p>

<kbd>You get</kbd> the helper agents, the skills and the commands. No guard runs.<br>
<kbd>You notice</kbd> a **check-in line** at the top of every kit helper's report; the **handoff file** re-injected at session start, if the project has one; a session-end count in the guard log.<br>
<kbd>It costs</kbd> nothing. Nothing is blocked.

---

<a name="recommended"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🟡 recommended 🟡<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>core plus <code>safety</code>, <code>shell_footguns</code> and <code>commit_review</code>.</sub></p>

<kbd>Denies</kbd> destructive commands, secrets about to be written, and the shell footguns: recursive `grep`, `pgrep -f`, a long check piped into `tail`.<br>
<kbd>Asks</kbd> once per session per repo, at the first commit with no review in the session. After a reviewer has run, it never asks.<br>
<kbd>Asks</kbd> also before a read-only command on another machine or account (`reach-guard`). `vcs-commit-guard` denies a commit that includes a file the repo marks private, and asks only when the command carries a `[vcs-exception:...]` marker.<br>
<kbd>Hands back</kbd> a command that changes something on another machine or account, with the reason, for you to run.<br>
<kbd>It costs</kbd> hygiene denies on em dashes and odd glyphs in a commit; `sed -i` and `tee` writes to tracked files denied unless you say why.

> [!WARNING]
> **Commit first, review before publishing?** Add `review_gate: push` to the repo's `.claude/agent-tiers.local.md` (`/agent-tiers:init` creates it). Local commits then pass; only a push or PR asks.

What the review ask turns into:

```diff
- git commit -m "fix"
  asked: no reviewer, advisor or codex-read spawn in this session yet
+ Agent  subagent_type: reviewer
+ git commit -m "fix"
```

---

<a name="full"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🔴 full 🔴<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Every group. Several agents, parallel sessions, <b>long or unattended runs</b>.</sub></p>

<kbd>Adds</kbd> the delegation rules (a helper on the wrong model is denied), batched questions, the end-of-reply badge, desktop notifications, peer notes between sessions, memory and planning checks.<br>
<kbd>You notice</kbd> every main-session reply ends in a badge: `[[ NO INPUT NEEDED ]]`, `[[ ! INPUT NEEDED ]]` or `[[ QUESTION NEXT ]]`. A reply without its tag is sent back.<br>
<kbd>Unattended</kbd> `/agent-tiers:unattended on`: a question box or plan mode in the main session is denied with an instruction it can act on; helpers' asks were denies already.

> [!WARNING]
> **The costs of full, stated plainly.** The reply tag is enforced in the native Claude Code CLI only. A new memory note needs a coverage check and a question to you. A question box needs its first option marked `(Recommended)`. A message to a finished agent needs `RESUME-OK` or `NOOP-IF-DONE`. A manual `/compact` is held until the handoff file is as new as the session's latest edits, so a fresh context does not start from stale notes. A sublead spawn without its approval tag asks you first.

#### Real example

The last line of three real replies, and how often each tag ended a reply across **653 replies** in 23 sessions:

| Tag<br><img src="assets/spacer.svg" width="136" height="1"> | Count | As it looks |
|---|---|---|
| no input needed | **348** | `operator:no_input_required\|reason:waiting on 4 background slice workers (A, B, C, D+E)` |
| input needed | **199** | `operator:want_input` |
| question next | **106** | `operator:ask_next` |

---

<a name="groups"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🧩 The groups 🧩<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Eight groups; a level is a set of them. Any group can be turned off on its own.</sub></p>

| Group<br><img src="assets/spacer.svg" width="150" height="1"> | Guards against | In |
|---|---|---|
| `safety` | destructive commands, risky writes, git actions that lose work, commands that reach other machines | recommended |
| `shell_footguns` | shell commands that fail quietly | recommended |
| `commit_review` | unreviewed commits, commit hygiene problems, private text leaking into a commit | recommended |
| `delegation` | helper spawns and external agent calls that break the tier rules | full |
| `memory` | memory and note writes with unsafe content or no provenance | full |
| `attention` | a person missing a question, a permission prompt or an advisory | full |
| `multi_session` | parallel sessions on one machine clobbering each other | full |
| `planning` | a plan that names files it never read; an approved plan not saved; a `/compact` ahead of the handoff file | full |

The full hook list, by group, is in [Hooks and guards](hooks.md#levels-and-groups).

---

<a name="after-install"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">👀 What changes after install 👀<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>What you see on screen, by level, <b>from the first session</b>.</sub></p>

#### Every level
<kbd>Check-in lines</kbd> the first line of every kit helper's report names its role and definition version. It comes from the agent definitions, not a hook, and does not prove the model. Explore and other built-in agents give none.<br>
<kbd>Session start</kbd> one line, read by the agent and not shown to you, naming the main session's model **band** and the handoff file.

#### recommended
<kbd>Commit asks</kbd> about review, as in [a routine change](work-shapes.md#a-routine-change).<br>
<kbd>Denies</kbd> are addressed to the agent and say what to do next. A few tell it to stop and hand the command to you.

#### full
<kbd>The badge</kbd> on every main-session reply; a reply without its tag is sent back.<br>
<kbd>Notifications</kbd> on permission prompts and when input is needed.<br>
<kbd>Peer notes</kbd> when another live session works in the same repo; a deny, once per session per repo, on a session's first write into a different repo (the deny text says to read that repo's docs first; the retry then passes), or an ask when a live session is already working there. Linux only.<br>
<kbd>Status line</kbd> if you accepted it at install: model, context, session clock, and one row per running helper.

---

<a name="turning-things-off"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🔧 Turning things off 🔧<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>One hook, one group, or the whole kit.</sub></p>

<kbd>The command</kbd> `agent-tiers` below is short for `sh ~/.claude/agent-tiers/scripts/agent-tiers` on the flat route; on the plugin route the first three are menus in `/agent-tiers:setup`; `AGENT_TIERS_OFF=1` works on either route.<br>
<kbd>One hook</kbd> `agent-tiers configure --set disabled_hooks=<id>,<id>`. It replaces the whole list each time, so name every hook you want off. Hook ids are the `hook` rows of `install/options.tsv`.<br>
<kbd>One group</kbd> `agent-tiers configure --set group_<name>=false`; a whole level with `--level <level>`.<br>
<kbd>Everything</kbd> `agent-tiers configure --set enabled=false`, or `AGENT_TIERS_OFF=1` in the environment for one session.<br>
<kbd>Details</kbd> [Change the setup later](install.md#change-the-setup-later).

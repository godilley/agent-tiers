<a name="top"></a>
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./docs/assets/agent-tiers-banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="./docs/assets/agent-tiers-banner-light.png">
    <img alt="agent-tiers: never trusts one model with the whole job" src="./docs/assets/agent-tiers-banner-light.png" width="960">
  </picture>
</p>

<p align="center">
  <em>No single model gets the whole job. <strong>The right model for each job.</strong><br>
  <strong>Hooks block the dangerous stuff</strong> before it happens.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-1c2128?style=for-the-badge&logo=claude&logoColor=D97757" alt="Claude Code">
  <img src="https://img.shields.io/badge/POSIX_shell-1c2128?style=for-the-badge&logo=gnubash&logoColor=4EAA25" alt="POSIX shell">
  <a href="https://github.com/godilley/agent-tiers/actions/workflows/selfcheck.yml"><img src="https://img.shields.io/github/actions/workflow/status/godilley/agent-tiers/selfcheck.yml?style=for-the-badge&label=selfcheck&labelColor=1c2128&color=1c2128" alt="selfcheck status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/MIT-1c2128?style=for-the-badge" alt="license: MIT"></a>
</p>

<div align="center">

| <img src="docs/assets/spacer.svg" width="21" height="1">**README**<img src="docs/assets/spacer.svg" width="21" height="1"> | <img src="docs/assets/spacer.svg" width="1" height="1">[**Why delegate**](docs/usage.md)<img src="docs/assets/spacer.svg" width="1" height="1"> | <img src="docs/assets/spacer.svg" width="3" height="1">[**Work shapes**](docs/work-shapes.md)<img src="docs/assets/spacer.svg" width="3" height="1"> | <img src="docs/assets/spacer.svg" width="29" height="1">[**Levels**](docs/levels.md)<img src="docs/assets/spacer.svg" width="29" height="1"> | <img src="docs/assets/spacer.svg" width="9" height="1">[**Plan waves**](docs/plan-wave.md)<img src="docs/assets/spacer.svg" width="10" height="1"> | <img src="docs/assets/spacer.svg" width="20" height="1">[**Glossary**](docs/glossary.md)<img src="docs/assets/spacer.svg" width="20" height="1"> |
|:-:|:-:|:-:|:-:|:-:|:-:|

</div>

<hr>

> [!NOTE]
> **agent-tiers** is a Claude Code plugin: helper agents do the work at the right price, and guards block the dangerous commands before they run. It self-configures by probing the local environment ([why a probe](docs/extending.md#why-a-probe)), so it works whatever GUI or editor add-on runs Claude Code. Plain files and POSIX shell; no server, no subscription.

| Tier<br><img src="docs/assets/spacer.svg" width="141" height="1"> | What it does<br><img src="docs/assets/spacer.svg" width="250" height="1"> | As it looks<br><img src="docs/assets/spacer.svg" width="1" height="1"> |
|---|---|---|
| 🧠 **Lead** | **The agent you talk to**<br><i>&rsaquo; Routes work rather than doing all of it.</i> | `agent-tiers band (model=claude-opus-5, source=startup): reasoning band - delegate.`<br><sub><i>one line at session start, read by the Lead, not shown to you</i></sub> |
| 🧭 **Sublead** | **Leads one slice of a big task**<br><i>&rsaquo; Over its own helpers; strong model, gated per spawn.</i> | `Hi, I'm sublead - Sublead tier, def-v5. Plan row DX1: five doctrine items`<br><sub><i>every kit helper's report starts with its check-in line</i></sub> |
| 🔧 **Worker** | **Cheap and fast**<br><i>&rsaquo; Mechanical, fully specified jobs.</i> | `Hi, I'm worker - Worker tier, def-v9. Fixed the heredoc-scan defect`<br><sub><i>Sonnet or Haiku</i></sub> |
| ⚖️ **Advisor** | **One hard think, bought per call**<br><i>&rsaquo; Read-only; findings, a recommendation, a confidence.</i> | `HANDOFF: adopt the liveness/recall split with three changes.`<br><sub><i>its one-line verdict; the reasoning comes above it. Opus</i></sub> |
| 👀 **Reviewer** | **Checks the diff cold**<br><i>&rsaquo; Whoever wrote it is the worst person to review it.</i> | `Result: 8 CONFIRMED, 2 REFUTED, 0 UNVERIFIABLE.`<br><sub><i>one refuted claim was a mistake planted in the brief on purpose: proof it read the diff</i></sub> |
| 🛑 **Boss** | **A different model, when the Lead is stuck**<br><i>&rsaquo; Decides on a distilled brief; never edits.</i> | `Hi, I'm boss - Boss tier, def-v7. <the task in one clause>`<br><sub><i>the check-in form; rare by design, always needs your yes</i></sub> |

> [!TIP]
> New here? [Why delegate](docs/usage.md) shows what a day with it looks like; [Work shapes](docs/work-shapes.md) the everyday jobs; the [glossary](docs/glossary.md) decodes the terms.

---

<a name="what-it-buys"></a>

<h3 align="center"><img align="left" src="docs/assets/spacer.svg" width="30" height="30" alt="">💡 What it buys 💡<a href="#top"><img align="right" src="docs/assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Two things. <b>Routing</b> and <b>safety</b>.</sub></p>

#### Routing
<kbd>The Lead</kbd> stays the brains: it plans, routes, briefs and verifies. It runs whatever model and effort you pick in your GUI; the kit never pins either, it only configures and verifies the helpers.<br>
<kbd>Each job</kbd> is bought per call from the model that fits: mechanical work from a fast worker, a hard decision from an Opus advisor, a risky diff from an independent or cross-lab reviewer.<br>
<kbd>By Lead model</kbd> a Sonnet Lead buys deep reasoning from an advisor; an Opus or Fable Lead already has it, so it hands mechanical jobs down and buys independence instead.<br>
<kbd>The lever</kbd> is the per-token price gap between models. The kit keeps no spend record; what it shows is which tier ran, per spawn, via the check-in line.

#### Safety
<kbd>Hooks</kbd> the rules that must not depend on an agent remembering them run as scripts before each tool call: force-pushes, secrets, credential edits can be hard-stopped, not remembered-about.<br>
<kbd>Opt-in</kbd> guards come in groups you pick at install. A plain install has none on. See [Levels](docs/levels.md).<br>
<kbd>Says what next</kbd> a deny briefs the agent on what to do instead, so it does not try a variant.

> [!IMPORTANT]
> Assumes you already know Claude Code plugins, hooks and subagents. Read [Anthropic's Claude Code docs](https://docs.claude.com/en/docs/claude-code) first if you do not.

---

<a name="see-it-work"></a>

<h3 align="center"><img align="left" src="docs/assets/spacer.svg" width="30" height="30" alt="">🎬 See it work 🎬<a href="#top"><img align="right" src="docs/assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Real output, not a mockup. The guards are plain scripts reading the hook's JSON, so <b>you can reproduce this yourself</b>.</sub></p>

A force-push stopped before it runs, by `dangerous-actions-blocker`. The command, then the decision and reason from the JSON it prints:

```console
$ printf '{"tool_name":"Bash","tool_input":{"command":"git push --force origin master"}}' \
    | sh scripts/dangerous-actions-blocker.sh
```

```diff
- git push --force origin master
  permissionDecision: deny
+ Force-push targeting main/master is a hard deny. What to do now: there is no override for this in
+ the session - do not retry a variant or route around it with another tool. Tell the operator what
+ was blocked and why; if they still want it done, they run it themselves in a real terminal.
```

<kbd>Note the reason</kbd> it briefs the **agent** on what to do next, not just you. A guard that only says "no" invites the model to try a variant; these close that door.<br>
<kbd>More captures</kbd> every guard and doctrine firing mid-session: [Hooks and guards](docs/hooks.md#guards-in-action). A helper's check-in line: [What ships](docs/what-ships.md#the-check-in-line).<br>
<kbd>Skeptical?</kbd> Good. Paste the [review prompt](docs/prompts/review.md) into a fresh Claude session: it audits the kit as inert data and reports, installing nothing.

---

<a name="install"></a>

<h3 align="center"><img align="left" src="docs/assets/spacer.svg" width="30" height="30" alt="">📦 Install 📦<a href="#top"><img align="right" src="docs/assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Two routes, <b>one per Claude Code profile</b>, never both: every hook would run twice.</sub></p>

> [!IMPORTANT]
> Needs `jq`: the `agent-tiers` CLI uses it, and so does every hook to read your options ([requirements](docs/install.md#requirements)).

#### Plugin route
For a host that loads Claude Code plugins (the Claude Code CLI does). Inside Claude Code:

```text
/plugin marketplace add godilley/agent-tiers
/plugin install agent-tiers@agent-tiers
```

<kbd>Then</kbd> `/agent-tiers:init` in any project. With `jq` installed, a fresh install runs at the `core` level, no guards on.<br>
<kbd>Guards</kbd> pick a level or groups with `/agent-tiers:setup`.

#### Flat route
For a host that ignores plugins but scans plain `~/.claude/{skills,agents,commands}` files:

```bash
git clone https://github.com/godilley/agent-tiers ~/.claude/agent-tiers
sh ~/.claude/agent-tiers/scripts/agent-tiers install
```

<kbd>It asks</kbd> for a level ([Levels](docs/levels.md)), prints a plan of what it will change, and asks again before applying it.<br>
<kbd>Restart</kbd> new agent types need a host restart; then `/agent-tiers-init` in any project.<br>
<kbd>Let the agent drive</kbd> paste the [install prompt](docs/prompts/install.md) into a Claude Code session: it clones to a temp dir, audits, plans, and waits for your confirmation before writing anywhere.<br>
<kbd>What it writes</kbd> your Claude profile dir and the kit checkout, plus `~/bin/agent-tiers-share` when `~/bin` exists and `~/.codex-homes/` for the Codex path; `/agent-tiers:init` appends three named blocks to a project's CLAUDE.md. Every file and why: [After install](docs/install.md#after-install).<br>
<kbd>Later</kbd> updating, switching routes, changing the setup: [Install and setup](docs/install.md).

---

<a name="documentation"></a>

<h3 align="center"><img align="left" src="docs/assets/spacer.svg" width="30" height="30" alt="">📚 Documentation 📚<a href="#top"><img align="right" src="docs/assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Day-to-day pages first, reference pages after.</sub></p>

| Page<br><img src="docs/assets/spacer.svg" width="200" height="1"> | Read it for<br><img src="docs/assets/spacer.svg" width="650" height="1"> |
|---|---|
| [**Why delegate**](docs/usage.md) | **Six effects, one real example each**<br><i>&rsaquo; What a day with the kit looks like.</i> |
| [**Work shapes**](docs/work-shapes.md) | **The everyday jobs**<br><i>&rsaquo; Helper, guard and level for each; what stops it going wrong.</i> |
| [**Levels**](docs/levels.md) | **Which guards you switch on**<br><i>&rsaquo; What you notice, what each level costs, turning things off.</i> |
| [**Plan waves**](docs/plan-wave.md) | **Rows in parallel**<br><i>&rsaquo; Ready set, lease, spawn, fork, merge.</i> |
| [**Glossary**](docs/glossary.md) | **Every term in one place**<br><i>&rsaquo; Bold words on the other pages are defined here.</i> |
| [**Install and setup**](docs/install.md) | **Both routes in full**<br><i>&rsaquo; Requirements, after install, changing the setup later, removing it.</i> |
| [**Hooks and guards**](docs/hooks.md) | **The hooks, by group**<br><i>&rsaquo; What to do when a guard blocks you; network posture; more captures.</i> |
| [**What ships**](docs/what-ships.md) | **Agents, skills, commands, scripts**<br><i>&rsaquo; Item by item; the check-in line.</i> |
| [**Extending the tiers**](docs/extending.md) | **The 3-layer project extension**<br><i>&rsaquo; Companions, private notes, a second account, the reach-guard allowlist, the lifecycle.</i> |

<p align="right"><sub>History: one entry per shared bundle, in <a href="CHANGELOG.md">CHANGELOG.md</a>.</sub></p>

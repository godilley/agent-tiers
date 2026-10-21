<a name="top"></a>
<h1 align="center">What ships</h1>

<p align="center"><i>Every agent, skill, command, config file, template and script in the kit, and where it lives</i></p>

<div align="center">

| <img src="assets/spacer.svg" width="21" height="1">[**README**](../README.md)<img src="assets/spacer.svg" width="21" height="1"> | <img src="assets/spacer.svg" width="28" height="1">[**Install**](install.md)<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="29" height="1">[**Hooks**](hooks.md)<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="10" height="1">**What ships**<img src="assets/spacer.svg" width="10" height="1"> | <img src="assets/spacer.svg" width="13" height="1">[**Extending**](extending.md)<img src="assets/spacer.svg" width="14" height="1"> | <img src="assets/spacer.svg" width="20" height="1">[**Glossary**](glossary.md)<img src="assets/spacer.svg" width="20" height="1"> |
|:-:|:-:|:-:|:-:|:-:|:-:|

</div>

<hr>

> [!NOTE]
> The kit's inventory, item by item. All portable and used verbatim, no per-project edits needed; per-project files are filled from the templates by `/agent-tiers:init`.

| Category<br><img src="assets/spacer.svg" width="150" height="1"> | What ships<br><img src="assets/spacer.svg" width="500" height="1"> |
|---|---|
| 🤖 [**Agents**](#agents) | **The helper tiers**<br><i>&rsaquo; Five tiers plus two Codex paths.</i> |
| 📚 [**Skills**](#skills) | **The doctrine and workflows**<br><i>&rsaquo; Tiers, gating, handoff, plan waves.</i> |
| 💻 [**Commands**](#commands) | **Slash commands**<br><i>&rsaquo; Set up, check, curate, sync.</i> |
| 🧰 [**Config**](#config) | **Options and per-machine files**<br><i>&rsaquo; Plugin options, VCS policy, layers.</i> |
| 🪝 [**Hooks**](#hooks) | **Core hooks and guard groups**<br><i>&rsaquo; Listed on the Hooks page.</i> |
| 📄 [**Templates**](#templates) | **Starting points for project files**<br><i>&rsaquo; Briefs, handoff, task agents.</i> |
| 🔧 [**Scripts**](#scripts) | **The installer and tools**<br><i>&rsaquo; CLI, flat install, lints, worktrees.</i> |

> [!TIP]
> Every kit helper's report starts with a **check-in line** naming its role and definition version. What it proves and what it does not: [The check-in line](#the-check-in-line).

---

<a name="agents"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🤖 Agents 🤖<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>One file per tier in <code>agents/</code>. <b>Four are gated or optional.</b></sub></p>

| Name<br><img src="assets/spacer.svg" width="121" height="1"> | One line | Where it lives |
|---|---|---|
| `worker` | Cheap, fast, mechanical: follows a fully specified brief, never decides. | `agents/worker.md` |
| `advisor` | Read-only reasoning on one bounded question or a design draft; returns findings, a recommendation and a confidence. | `agents/advisor.md` |
| `reviewer` | Opus, read-only on code: curates noisy first-pass audits into one trustworthy list, or reviews one diff alone. | `agents/reviewer.md` |
| `boss` | Human-gated circuit-breaker for a stuck main session; runs a different model from the main session, decides on a brief, never explores. | `agents/boss.md` |
| `sublead` | Opus, gated: leads one independent slice of a plan over its own children. Needs a `[sublead-approved:]` tag. | `agents/sublead.md` |
| `codex-read` | Optional cross-lab read path: hands a brief to the Codex CLI read-only and returns its findings. | `agents/codex-read.md` |
| `codex-write` | Optional cross-lab write path: Codex implements in an isolated worktree; the result always needs a Claude review. | `agents/codex-write.md` |

---

<a name="skills"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">📚 Skills 📚<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>One folder per skill in <code>skills/</code>.</sub></p>

| Name<br><img src="assets/spacer.svg" width="197" height="1"> | One line | Where it lives |
|---|---|---|
| `agent-tiers` | The tier vocabulary and spawn contract, plus the policy cards (BOSS, CONTRACT, HOST, MAINT, MEMORY, ROUTE, XLAB). | `skills/agent-tiers/` |
| `gating-workflow` | How to put a fork to the person: context as an ended reply, then a question box with a marked default. | `skills/gating-workflow/` |
| `delegation` | Hard rules for spawning helpers, plus the build, prove, propagate rollout rule. | `skills/delegation/` |
| `session-handoff` | Keeping `RESUME_SESSION.md` useful across a compact or a fresh context. | `skills/session-handoff/` |
| `context-file-layout` | How to structure CLAUDE.md and the files around it, with a refactor playbook. | `skills/context-file-layout/` |
| `doc-lifecycle` | How a private notes doc reaches a clean end state instead of piling up. | `skills/doc-lifecycle/` |
| `plan-wave` | Run a plan's ready rows as parallel sublead helpers, one worktree each, forks relayed to the person. | `skills/plan-wave/` |

---

<a name="commands"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">💻 Commands 💻<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Invoked <code>/agent-tiers:&lt;name&gt;</code> (plugin) or <code>agent-tiers-&lt;name&gt;</code> (flat).</sub></p>

| Name<br><img src="assets/spacer.svg" width="121" height="1"> | One line | Where it lives |
|---|---|---|
| `init` | Set up the kit for this project: probe the environment, scaffold the project brief, tier block and handoff. | `commands/init.md` |
| `doctor` | Re-probe the environment; health and lifecycle report, including which hook rows are wired. | `commands/doctor.md` |
| `gc` | Gated curator for memories, handoff, briefs, plan docs and VCS policy. Proposes, never auto-deletes. | `commands/gc.md` |
| `hygiene` | Backfix em and en dashes, curly quotes and invisible characters in a project's files, gated. | `commands/hygiene.md` |
| `resume` | Refresh `RESUME_SESSION.md` now, optionally steered by text after the command. | `commands/resume.md` |
| `notes` | Sync the git-ignored `docs/_local/` to a side ref (`local/notes`) without touching HEAD or the index. | `commands/notes.md` |
| `unattended` | Flag this session as unattended, so a guard question comes back as an actionable deny. | `commands/unattended.md` |
| `setup` | Install, reconfigure or remove the kit through its CLI, with menus. | `commands/setup.md` |
| `context-map` | Table of what gets injected into a session, with sizes and firing counts from a debug log. Never runs a hook. | `commands/context-map.md` |

---

<a name="config"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🧰 Config 🧰<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>The options, and the files <b>you or the installer</b> fill per machine or project.</sub></p>

| Name<br><img src="assets/spacer.svg" width="170" height="1"> | One line | Where it lives |
|---|---|---|
| Plugin manifest | Its `userConfig` keys are the options: `enabled`, the eight `group_*` switches, `disabled_hooks`. The `userConfig` block is generated from `install/options.tsv`. | `.claude-plugin/plugin.json` |
| Marketplace entry | The kit's own marketplace: the kit itself (source `./`) plus two third-party plugins pinned by commit, `caveman` and `ponytail`. Hand-written, not generated. | `.claude-plugin/marketplace.json` |
| Options table | The one table of levels, groups, options and hook rows; the CLI and `/agent-tiers:setup` read it. | `install/options.tsv` |
| Per-project record | Written by `/agent-tiers:init`, git-ignored: the probed environment, resolved VCS policy, and `review_gate`. | `templates/agent-tiers.local.md` |
| `kit-config.md` | Your global VCS-policy defaults, written if absent by the flat installer and never overwritten. A plugin install has none and falls back to `ignore-personal` per class and `agent_memory_project: commit`. | `~/.claude/agent-tiers/kit-config.md` (flat route) |
| Layer registry | Copy it to `~/.claude/agent-tiers/.state/LAYERS.md` and fill it per machine; never tracked. | `templates/LAYERS.md` |
| Reach classes | reach-guard's default command classes; your own rows go in `~/.claude/reach-guard/classes.tsv`. | `data/reach-classes.tsv` |

<kbd>Layer registry</kbd> one row per thing that injects context (CLAUDE.md files, plugins, hooks): its owner, why it loads, which one wins a conflict, and how to switch it off.<br>
<kbd>Where</kbd> under `$CLAUDE_CONFIG_DIR` when it is set; on the plugin route create the folder yourself.<br>
<kbd>Who reads it</kbd> `context-map` marks each layer registered or not; once the file exists, session start names any enabled plugin or settings hook with no row. No file, no advisory.

How the kit maintains its own artifacts after install (staleness stamps, gated curation, VCS policy, the private-notes seam): [After install](extending.md#lifecycle).

---

<a name="hooks"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🪝 Hooks 🪝<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Core hooks, plus guard groups <b>you turn on by level</b>.</sub></p>

The full list, by group, is on [Hooks and guards](hooks.md#levels-and-groups): 44 hook rows, from `install/options.tsv`. Each hook is `scripts/<id>.sh`. The plugin wiring, `hooks/hooks.json`, is generated from the same table.

---

<a name="templates"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">📄 Templates 📄<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Starting points in <code>templates/</code>, mostly filled by <code>/agent-tiers:init</code>.</sub></p>

| Name<br><img src="assets/spacer.svg" width="273" height="1"> | One line | Where it lives |
|---|---|---|
| `agent-tiers.local.md` | The per-project record (see [Config](#config)). | `templates/` |
| `CLAUDE.project.example.md` | An example project CLAUDE.md core to fill in. | `templates/` |
| `tiers-block.md` | The agent tiers block for a project's CLAUDE.md. | `templates/` |
| `tier-project-brief.SKILL.md` | The project brief skill preloaded into helpers: build, test, verify commands and landmines. | `templates/` |
| `task-agent.project.md` | A project task agent for a repeated mechanical procedure. | `templates/` |
| `task-agent.qa.md` | A project QA task agent: write a failing test, run and triage, repair a broken test. | `templates/` |
| `RESUME_SESSION.md` | The session handoff file. | `templates/` |
| `escalation-brief.md` | One brief for every metered escalation: advisor, boss, Codex. | `templates/` |
| `codex-handoff-brief.md` | A pointer to `escalation-brief.md` for a Codex handoff. | `templates/` |
| `LAYERS.md` | The layer registry (see [Config](#config)). | `templates/` |
| `prompts/` | Paste-in prompts for a shared copy: install, review, and the safety wrapper around both. | `templates/prompts/` |

---

<a name="scripts"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🔧 Scripts 🔧<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Everything in <code>scripts/</code> that is <b>not a hook</b>.</sub></p>

| Name<br><img src="assets/spacer.svg" width="244" height="1"> | One line | Where it lives |
|---|---|---|
| `agent-tiers` | The install CLI: `install`, `configure`, `remove`, `status`. | `scripts/` |
| `install-flat.sh` | Flat install: links skills and agents, bakes commands, wires hooks through the ledger. | `scripts/` |
| `kit-gate.sh` | Asked by every hook: should it stand down? `--summary` names what is off. | `scripts/` |
| `probe-env.sh` | Read-only probe of how this environment sets the main session's model and what helpers inherit. | `scripts/` |
| `detect-env.sh` | Read-only: proposes values for the notification and badge settings. | `scripts/` |
| `gen-plugin-manifests.sh` | Generates the plugin's `userConfig` and `hooks/hooks.json` from `install/options.tsv`. | `scripts/` |
| `worktree.sh` | The one worktree recipe: `up`, `down`, `list`. | `scripts/` |
| `codex-run.sh` | The one sanctioned way to run `codex` from a session, with a secrets scan. | `scripts/` |
| `notes-sync.sh` | Backs up a git-ignored dir to a side git ref without touching HEAD or the index. | `scripts/` |
| `context-map.sh` | Maps what lands in a session's context against the layer registry. Reads only. | `scripts/` |
| `doc-lifecycle-check.sh` | Advisory scan for notes docs that never reached an end state. | `scripts/` |
| `review-gate-mode.sh` | Prints the `review_gate` value the guard would enforce for a dir, and where it came from. | `scripts/` |
| `review.sh` | A reading aid for a POSIX sh install script, before you run it. | `scripts/` |
| `agent-tiers-share` | Shares a pinned copy: preflight (clean tree, lints, selfchecks), then a push and a green CI run for HEAD, a `share/<who>-<n>` tag pushed to your own remote (`origin`, or `--remote`; never inferred), an archive of that tag, and a paste-in install prompt. | `scripts/` |
| `lint-doctrine.sh` | Doctrine drift lint: rule ids, anchors, version stamps. | `scripts/` |
| `docs-lint.sh` | Markdown lint for links and the traps GitHub renders differently. | `scripts/` |
| `docs-nav.sh` | Prints the docs tab bar. | `scripts/` |
| `selfcontainment-check.sh` | Preflight: fails a script that would ship broken in a recipient's copy. | `scripts/` |
| `selfcheck-all.sh` | Runs every selfcheck in parallel, scored the way CI scores them. | `scripts/` |
| `statusline.sh` | The main status row: folder, model, branch, context, session time (labels in `statusline-model.jq`). | `scripts/` |
| `statusline-subagent.sh` | One status row per running helper. | `scripts/` |
| Helper libraries | Sourced by hooks, never run alone: `guard-cmdpos.sh`, `lib/content-rules.sh`, `lib/guard-mempath.sh`, `lib/handback-tag.sh`, `lib/model-band.sh`, `lib/notify-tag.sh`, `lib/band-lines.default`. | `scripts/`, `scripts/lib/` |

Every script here has a `.selfcheck.sh` sibling except `probe-env.sh`, `review-gate-mode.sh`, `statusline-subagent.sh`, `lib/handback-tag.sh` and `lib/model-band.sh` (and the two data files, `statusline-model.jq` and `lib/band-lines.default`). Run them all with `sh scripts/selfcheck-all.sh`.

---

<a name="the-check-in-line"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">👋 The check-in line 👋<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>The first line of every kit helper's report. <b>It does not prove the model.</b></sub></p>

<kbd>Form</kbd> `Hi, I'm <name> - <tier or role>, def-vN. <the task in one clause>`<br>
<kbd>What it shows</kbd> the role and the definition version, so a stale definition is visible.<br>
<kbd>What it does not</kbd> certify the model or effort.<br>
<kbd>Model and effort</kbd> a report keeps what was requested (the spawn settings or the brief: declared, not proof) apart from what was observed (runtime evidence from the harness, its source named). With no runtime evidence the field reads **unverified**; a definition's default is never evidence.<br>
<kbd>Who gives none</kbd> Explore and other built-in agents.<br>
<kbd>Contract</kbd> the agent-tiers skill, "The check-in line" (SC-6.4).

#### Real example

```
Hi, I'm worker - Worker tier, def-v9. Task: create and verify a slugify shell script.
```

<sub><i>Captured under an older worker definition (def-v9; `agents/worker.md` is def-v10 now). The "Task:" wording is part of that captured line.</i></sub>

<a name="top"></a>
<h1 align="center">Install</h1>

<p align="center"><i>Install the kit by one of two routes, see what it wrote, change the setup later, and remove it cleanly</i></p>

<div align="center">

| <img src="assets/spacer.svg" width="21" height="1">[**README**](../README.md)<img src="assets/spacer.svg" width="21" height="1"> | <img src="assets/spacer.svg" width="28" height="1">**Install**<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="29" height="1">[**Hooks**](hooks.md)<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="10" height="1">[**What ships**](what-ships.md)<img src="assets/spacer.svg" width="10" height="1"> | <img src="assets/spacer.svg" width="13" height="1">[**Extending**](extending.md)<img src="assets/spacer.svg" width="14" height="1"> | <img src="assets/spacer.svg" width="20" height="1">[**Glossary**](glossary.md)<img src="assets/spacer.svg" width="20" height="1"> |
|:-:|:-:|:-:|:-:|:-:|:-:|

</div>

<hr>

> [!NOTE]
> Every install, setup and removal command for the kit, by route. Ground truth is `scripts/agent-tiers` and `install/options.tsv`.

| Section<br><img src="assets/spacer.svg" width="173" height="1"> | What it covers<br><img src="assets/spacer.svg" width="300" height="1"> | As it looks<br><img src="assets/spacer.svg" width="1" height="1"> |
|---|---|---|
| 🧰 [**Requirements**](#requirements) | **`jq`, bash, coreutils**<br><i>&rsaquo; And which route fits your host.</i> | `agent-tiers: jq is required [...]`<br><sub><i>the CLI, when jq is missing</i></sub> |
| 🧩 [**Plugin route**](#plugin-route) | **Two slash commands**<br><i>&rsaquo; For a host that loads plugins.</i> | `/plugin install agent-tiers@agent-tiers`<br><sub><i>after the marketplace add</i></sub> |
| 📂 [**Flat route**](#flat-route) | **A clone and one script**<br><i>&rsaquo; For a host that reads plain files only.</i> | `sh ~/.claude/agent-tiers/scripts/agent-tiers install`<br><sub><i>asks a level, prints a plan, asks again</i></sub> |
| 📦 [**After install**](#after-install) | **What was written where**<br><i>&rsaquo; Your choices, project files, extras, settings.</i> | `/agent-tiers:init`<br><sub><i>then in each project</i></sub> |
| 🔧 [**Change setup**](#change-the-setup-later) | **One command per change**<br><i>&rsaquo; Level, group, hook, kit, route, update.</i> | `Apply? [y/N]`<br><sub><i>every change prints its plan first</i></sub> |
| 🧹 [**Remove**](#remove) | **The remover, then a short list**<br><i>&rsaquo; What it leaves and how to clear it.</i> | `Not automated (see [...]):`<br><sub><i>the remover's last list</i></sub> |

> [!TIP]
> A **profile** is one Claude Code config dir: `~/.claude`, or `$CLAUDE_CONFIG_DIR` when set. One route per profile, never both: every hook would run twice.

---

<a name="requirements"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🧰 Requirements 🧰<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Three tools, and <b>one route per profile</b>.</sub></p>

#### What you need

| Need<br><img src="assets/spacer.svg" width="136" height="1"> | Why |
|---|---|
| `jq` | **Required.** The `agent-tiers` CLI refuses to run without it, and every hook (a kit script Claude Code runs around a tool call) needs it to read your options. Without `jq`, each installed hook ignores the settings you chose and most guards do nothing; only the one-session off switch, `AGENT_TIERS_OFF=1`, still works. |
| bash 3.2+ | The installer and maintenance scripts. |
| POSIX coreutils | Present on any Linux or macOS; `install-flat.sh` preflights the exact set. |

<kbd>Your model</kbd> the main session runs whatever model and effort you pick in your host. The kit pins neither; it only configures and checks the helper agents the main session spawns.

#### Which route

| Route<br><img src="assets/spacer.svg" width="70" height="1"> | Use it when | Hooks wired by |
|---|---|---|
| **Plugin** | your host loads Claude Code plugins (the Claude Code CLI does) | the plugin's `hooks/hooks.json` |
| **Flat** | your host ignores plugins but reads plain files in `~/.claude/{skills,agents,commands}` | `install-flat.sh`, as rows in `settings.json` |

<kbd>Not sure</kbd> the **host** is whatever runs Claude Code for you: the CLI, a GUI or an editor add-on. If it does not know the `/plugin` command, take the flat route.

> [!WARNING]
> **Never both routes in one profile.** `install-flat.sh` refuses to wire anything while an `agent-tiers@...` plugin is enabled in your user or managed settings (a plugin enabled only in a project's settings is not checked), or when it is run from the plugin's own cached copy of the kit. Nothing stops the other direction: see [Switch route](#switch-route).

#### Let the agent drive

<kbd>Install prompt</kbd> paste the [install prompt](prompts/install.md) into a Claude Code session, either route: your agent clones the kit to a temp dir, audits it, plans, and waits for your yes before writing anywhere.

---

<a name="plugin-route"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🧩 Plugin route 🧩<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>For a host that loads plugins. <b>No checkout needed.</b></sub></p>

Inside Claude Code:

```text
/plugin marketplace add godilley/agent-tiers
/plugin install agent-tiers@agent-tiers
```

<kbd>From a shell</kbd> `claude plugin marketplace add godilley/agent-tiers`, then `claude plugin install agent-tiers@agent-tiers`.<br>
<kbd>Then</kbd> `/agent-tiers:init` in each project ([After install](#after-install)).<br>
<kbd>Level</kbd> with `jq` installed, a fresh plugin install runs at the `core` level: the plugin wires every hook, but only the session handoff and housekeeping ones act; the rest stand down until their group is on.<br>
<kbd>Pick one</kbd> `/agent-tiers:setup` picks a level or groups through menus; the plugin's own options (`/plugin configure agent-tiers@agent-tiers`, or `/config`) edit the same entry. [Levels](levels.md) says what each level does.<br>
<kbd>Companions</kbd> the same marketplace lists `caveman` and `ponytail`, two third-party plugins, each pinned to a known upstream commit ([Companions](extending.md#companions)). Installing one is a separate choice, for example `/plugin install caveman@agent-tiers`. Skip it if you already have it from its own marketplace, or its hooks run twice.

---

<a name="flat-route"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">📂 Flat route 📂<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>For a host that ignores plugins: <b>a clone and one script</b>.</sub></p>

```bash
git clone https://github.com/godilley/agent-tiers ~/.claude/agent-tiers
sh ~/.claude/agent-tiers/scripts/agent-tiers install
```

<kbd>It asks</kbd> for a level, prints a plan of what it will change, and asks again before applying it.<br>
<kbd>No questions</kbd> name the level and add `--yes`. Swap `--yes` for `--dry-run` to print the plan and change nothing.

```bash
sh ~/.claude/agent-tiers/scripts/agent-tiers install --level recommended --yes
```

#### What applying does

<kbd>Links</kbd> `install-flat.sh` symlinks the kit's skills and agents into `~/.claude/skills/` and `~/.claude/agents/`.<br>
<kbd>Commands</kbd> it copies each command as `agent-tiers-<name>.md` with the kit path baked in; the prefix avoids a clash with the built-in `/init`.<br>
<kbd>Hooks</kbd> it wires the core hooks plus every hook of the groups you picked into `~/.claude/settings.json`, after backing that file up.<br>
<kbd>Restart</kbd> skills and commands are picked up live, but **new agent types need a host restart**: restart first, then run `/agent-tiers-init` in each project.<br>
<kbd>Hyphens</kbd> on the flat route every kit command uses a hyphen: `/agent-tiers-setup`, not `/agent-tiers:setup`.<br>
<kbd>Second profile</kbd> one checkout serves every profile: `CLAUDE_CONFIG_DIR=~/.claude-work sh ~/.claude/agent-tiers/scripts/agent-tiers install`. Every later `configure`, `status` or `remove` for that profile needs the same variable ([a second account](extending.md#second-claude-account)).

> [!WARNING]
> **Edit only the files under `~/.claude/agent-tiers/`.** Skills and agents are symlinks, but the command copies are regenerated: re-run `install-flat.sh` after editing `commands/*.md`, or the copies go stale.

---

<a name="after-install"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">📦 After install 📦<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>What the kit wrote, and <b>where each choice lives</b>.</sub></p>

<a name="written-where"></a>

#### Written where

<kbd>Profile dir</kbd> `~/.claude/`, or `$CLAUDE_CONFIG_DIR`: on the flat route the links, command copies and hook rows; on both routes your choices, in `settings.json`.<br>
<kbd>Kit checkout</kbd> its `kit-config.md` (flat route only: your default git handling for kit files) and `.state/`, which holds the guard log and, on the flat route, `.state/integrations.json`, the ledger of hook rows `install-flat.sh` owns (a second profile gets its own file).<br>
<kbd>Outside both</kbd> `~/bin/agent-tiers-share` (flat route, only when `~/bin` already exists; a symlink, or a copy where symlinks fail), and the per-session Codex config dirs under `~/.codex-homes/` that the `codex-home-isolate` hook creates on either route, when Codex is present.<br>
<kbd>In a project</kbd> only what `/agent-tiers:init` writes there, each step confirmed with you ([In each project](#per-project-artifacts)).

<a name="where-your-choices-are-stored"></a>

<kbd>Your choices</kbd> the CLI and `/agent-tiers:setup` keep every choice in the profile's `settings.json`. Each run that changes it first writes a timestamped `settings.json.bak-*` next to it and keeps the newest 5.

| Choice<br><img src="assets/spacer.svg" width="154" height="1"> | Where in `settings.json` |
|---|---|
| Kit options | `pluginConfigs["agent-tiers@agent-tiers"].options`: `enabled`, `group_<name>`, `disabled_hooks`. Same entry on both routes; the plugin's options in `/config` edit it too (for `disabled_hooks`, use the CLI or `/agent-tiers:setup`). |
| Notification keys | `env`: `AGENT_TIERS_NOTIFY_TERMINAL`, `AGENT_TIERS_NOTIFY_FOCUS_CMD`, `AGENT_TIERS_BADGE_GLYPHS`. |
| Status line | top-level `statusLine` and `subagentStatusLine`, only when the status line extra was accepted. |
| Hook rows | `hooks`, flat route only, written by `install-flat.sh`. |

A level is not stored: it only sets the `group_<name>` options, and `agent-tiers status` reads them back.

<a name="per-project-artifacts"></a>

#### In each project

`/agent-tiers:init` (flat route: `/agent-tiers-init`) writes these into the project you run it in:

| File<br><img src="assets/spacer.svg" width="339" height="1"> | What it holds |
|---|---|
| `.claude/agent-tiers.local.md` | The repo's kit settings (its VCS policy; `review_gate` goes here too) and, when init probes the host, the model and effort resolution it recorded ([why a probe](extending.md#why-a-probe)). |
| auto-memory copy | The probed facts again, always loaded, surviving `/compact`. Not written when init skips the probe, as it does in the native Claude Code CLI. |
| `.claude/skills/tier-project-brief/` | The project brief: build, test and verify commands and landmines, read by every helper. |
| `.claude/agents/<prefix>-*.md` | Task agents for this project, only those you opt into. |
| `.claude/agent-memory-local/` | Helper memory, written by the helpers later; init only sets how git treats it. |
| `.gitignore`, `.git/info/exclude` | Entries keeping personal kit files out of git, per the VCS policy init asks you to confirm. |
| `RESUME_SESSION.md` | The handoff file, re-injected at session start. |
| `docs/_local/` | Offered: a git-ignored notes dir mirrored to a side `local/notes` ref, with `notes-sync.*` keys in `.git/config` ([Private notes](extending.md#private-notes)). |
| `CLAUDE.md` | Three named blocks: `## Agent tiers`, `## Building`, `## Workflow essentials`, plus a `## Output hygiene` block init asks whether to keep. Re-running init replaces them in place. |

<kbd>Offered</kbd> a review of the project's `CLAUDE.md` layout toward the recommended shape (`context-file-layout` skill, `templates/CLAUDE.project.example.md`). It never touches your personal global file.

<a name="extras"></a>

#### Extras and per-install settings

<kbd>Extras</kbd> the `extra` rows of `install/options.tsv`. The CLI only proposes them; nothing is written without a yes.<br>
<kbd>Status line</kbd> `agent-tiers configure --set extra_statusline=true` points `statusLine` and `subagentStatusLine` at the kit's `scripts/statusline.sh` and `scripts/statusline-subagent.sh`: folder, model, git branch, context use and session time, among others. Needs `jq`; without it the scripts print nothing. Icons are plain ASCII unless `AGENT_TIERS_BADGE_GLYPHS=nerd`.<br>
<kbd>Status line off</kbd> the same command with `=false`. Each key is deleted only while it still runs this checkout's script; a different value is left in place, and `remove` follows the same rule.<br>
<kbd>Stale path</kbd> the status line command holds the kit's absolute path, so moving the kit or a plugin version change leaves it stale: re-run the `=true` command after either. On the plugin route run it through `/agent-tiers:setup configure` or any checkout's `scripts/agent-tiers`; only that same checkout recognises the keys later.<br>
<kbd>agentsview</kbd> a session ledger and search tool. The kit does not install it and writes nothing for it; `install` prints a pointer. Get the binary from https://github.com/kenn-io/agentsview, then run `claude mcp add --scope user agentsview -- agentsview mcp`. Its search index is built with `agentsview embeddings build`; schedule that yourself (a systemd user timer or cron) to keep it fresh.

<a name="per-install-settings"></a>

<kbd>Per-install settings</kbd> hooks read these from their environment, so set them in the `env` block of the profile's `settings.json`. Unset means the default.<br>
<kbd>Through the CLI</kbd> the three notification and badge keys only: `agent-tiers configure --set AGENT_TIERS_NOTIFY_TERMINAL=kitty`. `install` and `configure` propose values for them from `scripts/detect-env.sh`, one question each, and write none without a yes; with `--yes` they are only printed, as `--set` lines you can copy.<br>
<kbd>By hand</kbd> the rest go into `env` yourself, except `AGENT_TIERS_SHARE_REMOTE`: `agent-tiers-share` runs from your own terminal, so export it there.

| Variable<br><img src="assets/spacer.svg" width="301" height="1"> | Default | Effect |
|---|---|---|
| `AGENT_TIERS_PROTECTED_BRANCHES` | empty | Extra branch names (space-separated, no patterns) a force-push may never target. A name also matches as the last path part of a ref, so `release` protects `feature/release`. `main`, `master` and origin's default branch as recorded locally (`git clone` records it; `git remote set-head origin -a` does it later) are always protected. |
| `AGENT_TIERS_NOTIFY_TERMINAL` | `alacritty` | Process name (`/proc/<pid>/comm`, at most 15 characters) of the terminal whose window a notification click focuses. |
| `AGENT_TIERS_NOTIFY_FOCUS_CMD` | `i3-msg "[id=%s] focus"` | Run on a notification click: the first `%s` becomes the X11 window id and the result runs through `sh -c`. Its first word must be the command. Empty means no click action. |
| `AGENT_TIERS_BADGE_GLYPHS` | empty | `nerd` adds Nerd Font icons to the reply badges and the status line. Without a Nerd Font they render as empty boxes, so the default is plain text and colour. |
| `PEER_GUARD_SOCK_DIR` | `/run/user/<uid>/cc-socks` if it exists, else `$XDG_RUNTIME_DIR/cc-socks` when that is set, else `/run/user/<uid>/cc-socks` | Where Claude Code keeps its per-session sockets. The macOS location is not verified; set this there. |
| `AGENT_TIERS_STATE_DAYS` | `7` | Age in days after which per-session marker files are deleted. |
| `AGENT_TIERS_LEDGER_DAYS` | `14` | Age in days after which authorship and numeric-claim ledger files are deleted. |
| `AGENT_TIERS_SHARE_REMOTE` | `origin` | Remote that `agent-tiers-share` pushes the branch and tag to (same as its `--remote` flag). |
| `AGENT_TIERS_PEER_IDLE_SECS` | `3600` | A SendMessage to another session idle longer than this is denied unless it carries `WAKE-OK:<why>`, since waking it re-reads its whole context with a cold prompt cache. A non-number or 0 means the default; above 604800 is capped at 604800. |
| `AGENT_TIERS_GUARDS_LOG` | `.state/guards.log` in the kit | Where guard decisions are logged. |

A day count that is not a whole number from 1 to 3650 falls back to the default.

> [!WARNING]
> **Click-to-focus needs X11 on Linux.** The session window is found by X11 window id (with `xdotool`) and the default focus command is `i3-msg`; on another X11 window manager, set `AGENT_TIERS_NOTIFY_FOCUS_CMD`. Native Wayland windows (GNOME under Wayland, for one) have no X11 id, so the notification has no click action; sway and Hyprland are untested. macOS has no click action either. In an editor's built-in terminal a click may focus the window that launched the editor; set `AGENT_TIERS_NOTIFY_FOCUS_CMD=` (empty) for a plain notification.

---

<a name="change-the-setup-later"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🔧 Change the setup later 🔧<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Two front ends, <b>same effect</b>: menus inside Claude Code, or the CLI.</sub></p>

<kbd>Menus</kbd> `/agent-tiers:setup` (flat route: `/agent-tiers-setup`) asks through menus, shows you the exact CLI command, and runs it once you confirm. With no argument it shows the current state and asks what to do.<br>
<kbd>CLI</kbd> below, `agent-tiers` is short for `sh ~/.claude/agent-tiers/scripts/agent-tiers`. It prints a plan and asks before changing anything; `--yes` skips the questions, and `--dry-run` (install and configure only) prints the plan and changes nothing.<br>
<kbd>Names</kbd> the levels and groups are on [Levels](levels.md).<br>
<kbd>Plugin route</kbd> there is no `~/.claude/agent-tiers` checkout: use `/agent-tiers:setup`, or clone the kit anywhere and run the CLI from that clone. It only edits `settings.json` there; `install-flat.sh` is never run while the plugin is enabled.

<a name="turn-things-on-and-off"></a>

#### Turn things on and off

| To<br><img src="assets/spacer.svg" width="250" height="1"> | Run |
|---|---|
| see what is on | `agent-tiers status` |
| switch level | `agent-tiers configure --level full` |
| one group off (or on) | `agent-tiers configure --set group_memory=false` |
| one hook off | `agent-tiers configure --set disabled_hooks=long-run-guard` |
| kit off until turned on | `agent-tiers configure --set enabled=false` |
| kit off, one session | start Claude Code as `AGENT_TIERS_OFF=1 claude` (either route) |
| reach-guard's allowlist | `agent-tiers reach list` (read-only; [the allowlist](extending.md#reach-guard-allowlist)) |

<kbd>One list</kbd> `disabled_hooks` replaces the whole list each time, so name every hook you want off: `--set disabled_hooks=long-run-guard,pgrep-footgun-guard`. Hook ids are the `hook` rows of `install/options.tsv`. Set it with the CLI or `/agent-tiers:setup`, or edit the JSON array at `pluginConfigs["agent-tiers@agent-tiers"].options.disabled_hooks`.<br>
<kbd>When</kbd> hooks read the options each time they run, so turning a group, a hook or the whole kit off takes effect on the next tool call. On the flat route a group turned off stays wired in `settings.json` and stands down; turning a group on wires its hooks, which load in a new session.<br>
<kbd>Kit off</kbd> while `enabled` is false, each session start adds one line saying the kit is off, unless the project ships its own `.claude/hooks/load-resume.sh`, which replaces the kit's session-start hook.<br>
<kbd>Notifications</kbd> `install` and `configure` also propose the notification keys ([per-install settings](#per-install-settings)).

<a name="switch-route"></a>

#### Switch route

<kbd>Flat to plugin</kbd> run `agent-tiers remove` first ([Remove](#remove)), then the [plugin route](#plugin-route). Nothing stops the plugin install while flat hook rows are still wired, and every hook would run twice.<br>
<kbd>Plugin to flat</kbd> `/plugin uninstall agent-tiers@agent-tiers` first, then the [flat route](#flat-route). Disabling the plugin is not enough: `agent-tiers install` still sees it installed and wires nothing.

<a name="update"></a>

#### Update

Flat route:

```bash
git -C ~/.claude/agent-tiers pull
sh ~/.claude/agent-tiers/scripts/install-flat.sh
sh ~/.claude/agent-tiers/scripts/agent-tiers configure --yes
```

<kbd>Why three</kbd> the `install-flat.sh` run refreshes the command copies and keeps every hook already wired; `configure --yes` wires any hook the update added to a group you have on.<br>
<kbd>Older installs</kbd> if `status` lists a group as `absent`, no level was ever stored (an install that wired hooks one by one). `configure --yes` stores each such group as it stands today, on when any of its hooks is wired, so nothing is lost; `configure --level <level>` picks a level instead.<br>
<kbd>Plugin route</kbd> `claude plugin update agent-tiers@agent-tiers`, then restart Claude Code. If you use the status line extra, re-run its `=true` command ([Extras](#extras)).

---

<a name="remove"></a>
<a name="uninstall"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🧹 Remove 🧹<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>One command, then <b>a short list it leaves to you</b>.</sub></p>

#### The remover

```bash
sh ~/.claude/agent-tiers/scripts/agent-tiers remove
```

<kbd>Or</kbd> `/agent-tiers:setup remove` inside Claude Code (flat route: `/agent-tiers-setup remove`). On the plugin route with no checkout, use this one; any checkout of the kit also works, except that the status line keys are only recognised by the checkout that wrote them.<br>
<kbd>It asks</kbd> it prints what it will do and asks first; `--yes` skips the question. Before it changes `settings.json` it writes a timestamped backup next to it and keeps the newest 5.<br>
<kbd>Second profile</kbd> paths below are `~/.claude/...`; for a second profile, run it with the same `CLAUDE_CONFIG_DIR` set and read that dir for `~/.claude`. `~/bin/agent-tiers-share` is shared by every profile, so removing one deletes it for all: re-run `install-flat.sh` in a profile you keep.<br>
<kbd>Agent-driven</kbd> paste the [uninstall prompt](prompts/uninstall.md) into a Claude Code session: it inventories first and confirms each step against this section.

| What<br><img src="assets/spacer.svg" width="290" height="1"> | Flat route | Plugin route |
|---|---|---|
| Hook rows | the kit's rows in `settings.json`, unwired with `install-flat.sh --unwire-only`, which also drops them from the integrations ledger | none to unwire: the plugin wires its hooks itself |
| Skill and agent links | the symlinks in `~/.claude/skills/` and `~/.claude/agents/`: removed | not created by the plugin |
| Command copies | `~/.claude/commands/agent-tiers-*.md`: removed (`/agent-tiers-setup` included) | not created by the plugin |
| Share script | `~/bin/agent-tiers-share`: removed when it is a symlink to, or a copy of, the kit's script | not created by the plugin |
| Kit options | the options entry and the three `AGENT_TIERS_*` env keys the CLI sets: deleted | deleted |
| Status line keys | `statusLine`, `subagentStatusLine`: deleted while they run this checkout's scripts, otherwise left and printed as `left in place` | same |
| The plugin itself | not installed | **not removed**: run `/plugin uninstall agent-tiers@agent-tiers` (or `claude plugin uninstall agent-tiers@agent-tiers`) yourself |

<kbd>Plugin left</kbd> until you uninstall it, the plugin stays loaded with every option back at its default, the `core` level.<br>
<kbd>Copies left</kbd> a skill or agent that is a real directory or file rather than a symlink (an install that could not symlink and copied instead) is left in place and named: `left in place (not a symlink): <path>; remove by hand if it is the kit copy`.

> [!WARNING]
> **`kit hook rows still wired in <settings>`** means `settings.json` holds kit hook rows the remover could not unwire, for example rows added by hand. It stops before removing anything else: delete those rows from `settings.json` yourself and run it again.

#### What it leaves

The remover ends with a `Not automated` list of five items. The plugin itself, status line keys and copied skills it left are named earlier in its output (see [The remover](#remove)).

| Left<br><img src="assets/spacer.svg" width="290" height="1"> | How to clear it |
|---|---|
| `settings.json.bak-*` | The timestamped backups next to `settings.json`. Each is a full copy of your settings, so delete them too if that file ever held anything sensitive. |
| `~/.codex-homes/` | One dir per session from the `codex-home-isolate` hook, on either route. No clean-up by design; about 40MB a session (a comment in `scripts/codex-home-isolate.sh`) and it only grows. `rm -rf ~/.codex-homes` once you are done with the kit. |
| Per-project files | Everything [In each project](#per-project-artifacts) lists, in each project you ran init in, plus the auto-memory copy under `~/.claude/projects/<slug>/memory/`. |
| `kit-config.md` and `.state/` | They live inside the kit checkout, so deleting the checkout takes both. |
| The kit checkout | Delete `~/.claude/agent-tiers/` (or wherever you cloned it) last, if you are leaving. When the remover ran from the plugin with no checkout, the path it names is the plugin's own cached copy, not a checkout: leave it until the plugin is uninstalled. |

<kbd>Status line</kbd> a `statusLine` or `subagentStatusLine` it left in place (your own, or one another or a moved checkout wrote): delete it by hand if it points at a deleted checkout.

<a name="only-the-hook-rows"></a>

#### Only the hook rows

To take the kit's hooks out of `settings.json` and keep the skills, agents and commands:

```bash
sh ~/.claude/agent-tiers/scripts/install-flat.sh --unwire-only
```

<kbd>Some rows</kbd> add `--without-<id>` flags to remove only those: `install-flat.sh --unwire-only --without-notify` removes just the `notify` row. Without `--unwire-only`, `--without-<id>` runs a full install that leaves that row out, re-creating the links and command copies on the way.<br>
<kbd>Ledger</kbd> either way the row also leaves the integrations ledger, so `/agent-tiers:doctor` does not report it as drift. Removing a row by hand-editing `settings.json` leaves its ledger entry orphaned.<br>
<kbd>They come back</kbd> a later `install-flat.sh` run wires the core rows again unless passed `--without-<id>`, and `agent-tiers install` or `configure` (the last step of the flat update) wires every hook of a group that is on unless its id is in `disabled_hooks`. To keep a hook off for good, or stop hooks acting without removing anything, use [Turn things on and off](#turn-things-on-and-off).

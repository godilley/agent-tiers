<a name="top"></a>
# Install and setup

[Back to the README](../README.md)

How to install the agent-tiers kit, keep it updated, and change its setup later. The levels and
groups you pick from are described in [hooks.md](hooks.md#levels-and-groups); if a guard blocked
you, start at [hooks.md](hooks.md).

## Requirements<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

| Requirement | Notes |
|---|---|
| POSIX coreutils | Present on any Linux/macOS; `install-flat.sh` preflights the exact set |
| bash 3.2+ | Installer and maintenance scripts |
| `jq` | **Required.** The `agent-tiers` CLI needs it, and so does every hook to read your options: without `jq`, each installed hook acts whatever the level, group or `enabled` setting says |

## Choose a route<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

There are two install routes. Use one per Claude Code profile (a config dir: `~/.claude`, or
`$CLAUDE_CONFIG_DIR` when set), never both: every hook would run twice.

| Route | Use it when | Hooks wired by |
|---|---|---|
| **Plugin** | your host loads Claude Code plugins (the Claude Code CLI does) | the plugin's `hooks/hooks.json` |
| **Flat** | your host ignores plugins but scans plain `~/.claude/{skills,agents,commands}` files | `install-flat.sh`, as rows in `settings.json` |

`install-flat.sh` refuses to wire anything while an `agent-tiers@...` plugin is enabled in your user
or managed settings (a plugin enabled only in a project's settings is not checked), or when it is
run from the plugin's own cached copy of the kit. Nothing stops the other direction, so to move from
the flat route to the plugin, run `sh ~/.claude/agent-tiers/scripts/agent-tiers remove` first
([Uninstall](#uninstall)).

Easiest path, either route: paste the [install prompt](prompts/install.md) into a Claude Code
session and let your agent drive - it clones to a temp dir, audits, plans, and waits for your confirmation
before writing anywhere.

## A. Plugin route<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

Inside Claude Code:

```text
/plugin marketplace add godilley/agent-tiers
/plugin install agent-tiers@agent-tiers
```

From a shell, the same two steps are `claude plugin marketplace add godilley/agent-tiers` and
`claude plugin install agent-tiers@agent-tiers`. Then run **`/agent-tiers:init`** in any project.

With `jq` installed, a fresh plugin install runs at the `core` level: the plugin wires every hook, but only the session
handoff and housekeeping ones act; the rest stand down until their group is on. Pick a level or
groups with **`/agent-tiers:setup`** (no checkout needed), or switch groups on in the plugin's
own options (`/plugin configure agent-tiers@agent-tiers`, or `/config`). Either way the choice is stored in `settings.json` under
`pluginConfigs["agent-tiers@agent-tiers"].options`.

The same marketplace also lists `caveman` and `ponytail`, two third-party plugins (see
[Companions](extending.md#companions-optional-power-ups)), each pinned to a known upstream commit. Installing one
is a separate choice, for example `/plugin install caveman@agent-tiers`. Skip it if you already
have it from its own marketplace, or its hooks run twice.

## B. Flat route<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

```bash
git clone https://github.com/godilley/agent-tiers ~/.claude/agent-tiers
sh ~/.claude/agent-tiers/scripts/agent-tiers install
```

`agent-tiers install` asks for a level, prints a plan of what it will change, and asks again before
applying it. To skip the questions, name the level and add `--yes`:

```bash
sh ~/.claude/agent-tiers/scripts/agent-tiers install --level recommended --yes
```

Swap `--yes` for `--dry-run` to print that plan and change nothing (`install` and `configure`).

Applying runs `install-flat.sh`, which:

- symlinks the kit's skills and agents into `~/.claude/skills/` and `~/.claude/agents/`;
- copies each command as `agent-tiers-<name>.md` with the kit path baked in (the prefix avoids a
  clash with the built-in `/init`);
- wires the core hooks plus every hook of the groups you picked into `~/.claude/settings.json`,
  after backing that file up.

Skills and commands are picked up live; **new agent types need a host restart**. Then run
**`/agent-tiers-init`** in any project. On the flat route every kit command uses a hyphen:
`/agent-tiers-setup`, not `/agent-tiers:setup`. A host that ignores plugins can be recognised by
its path: for one such GUI, `CLAUDE_CODE_EXECPATH` contains `.codemoss` (the init probe reports
`host_guess`).

The flat install writes only under the profile dir (`~/.claude/`, or `$CLAUDE_CONFIG_DIR`) and the
kit checkout (its `kit-config.md` and `.state/`), with two exceptions: `~/bin/agent-tiers-share`
(a symlink, or a copy where symlinks fail; only when `~/bin` already exists), and the per-session Codex config dirs under
`~/.codex-homes/` that the `codex-home-isolate` hook creates (on either route). Running
`/agent-tiers-init` afterwards scaffolds files
in the project you run it in - including three named blocks appended to that project's `CLAUDE.md` -
each step confirmed with you.

To update:

```bash
git -C ~/.claude/agent-tiers pull
sh ~/.claude/agent-tiers/scripts/install-flat.sh
sh ~/.claude/agent-tiers/scripts/agent-tiers configure --yes
```

The `install-flat.sh` run refreshes the command copies and keeps every hook already wired; the
`configure --yes` run wires any hook the update added to a group you have on. That last step only
sees groups with a stored setting: if `status` lists a group as `absent`, no level was
ever stored (an older install that wired hooks one by one), so run
`sh ~/.claude/agent-tiers/scripts/agent-tiers configure` once and pick a level first.

Running a second Claude account? One kit serves every profile via `CLAUDE_CONFIG_DIR` - see
[docs/after-install.md](after-install.md#second-claude-account-claude_config_dir).
Protected branches, notification focus and state retention are per-install environment settings:
[docs/after-install.md](after-install.md#per-install-settings-environment).

> [!WARNING]
> Edit ONLY the canonical files under `~/.claude/agent-tiers/`. Skills + agents are
> symlinks (zero drift); the command copies are regenerated - **re-run `install-flat.sh` after editing
> `commands/*.md`** or you ship stale copies.

## Change the setup later<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

Level and group names: [Levels and groups](hooks.md#levels-and-groups).

Two front ends, same effect:

- **`/agent-tiers:setup`** (flat route: `/agent-tiers-setup`) asks through menus inside Claude Code,
  shows you the exact CLI command, and runs it once you confirm. With no argument it shows the
  current state and asks what to do.
- **The CLI**, from a shell. Below, `agent-tiers` is short for
  `sh ~/.claude/agent-tiers/scripts/agent-tiers`. It prints a plan and asks before changing
  anything; `--yes` skips the questions. On the plugin route there is no `~/.claude/agent-tiers`
  checkout: use `/agent-tiers:setup`, or clone the kit anywhere and run the CLI from that clone
  (it only edits `settings.json` there; `install-flat.sh` is never run while the plugin is
  enabled).

| To | Run |
|---|---|
| see what is on | `agent-tiers status` |
| switch level | `agent-tiers configure --level full` |
| turn one group off (or on) | `agent-tiers configure --set group_memory=false` |
| turn single hooks off | `agent-tiers configure --set disabled_hooks=long-run-guard,pgrep-footgun-guard` |
| turn the whole kit off until you turn it back on | `agent-tiers configure --set enabled=false` |
| turn the whole kit off for one session (either route) | start Claude Code as `AGENT_TIERS_OFF=1 claude` |
| remove the kit | `agent-tiers remove` (see [Uninstall](#uninstall)) |
| see reach-guard's allowlist | `agent-tiers reach list` (read-only) |

- `disabled_hooks` replaces the whole list each time, so name every hook you want off. It is not
  shown in `/config`: set it with the CLI or `/agent-tiers:setup`, or edit the JSON array at
  `pluginConfigs["agent-tiers@agent-tiers"].options.disabled_hooks` in `settings.json`. Hook ids are
  the `hook` rows of `install/options.tsv`.
- Hooks read the options each time they run, so turning a group, a hook or the whole kit off takes
  effect on the next tool call. On the flat route a group turned off stays wired in `settings.json`
  and stands down; turning a group on wires its hooks, which load in a new session.
- While `enabled` is false, each session start adds one line saying the kit is off (unless the
  project ships its own `.claude/hooks/load-resume.sh`, which replaces the kit's session-start hook).
- On either route, `install` and `configure` run `scripts/detect-env.sh`, which proposes desktop
  notification settings (`AGENT_TIERS_NOTIFY_TERMINAL`, `AGENT_TIERS_NOTIFY_FOCUS_CMD`,
  `AGENT_TIERS_BADGE_GLYPHS`). Each proposal is asked about on its own, and nothing is written
  without a yes. With `--yes` they are only printed, as `--set` lines you can copy.
- Clicking a desktop notification focuses the session window only through X11 window ids (found
  with `xdotool`), and the default focus command is `i3-msg`. On another X11 window manager, set
  `AGENT_TIERS_NOTIFY_FOCUS_CMD` to your own command (`%s` stands for the window id). On GNOME under
  Wayland there is no X11 window id to find, so click-to-focus does nothing and you get a plain
  notification. sway and Hyprland are untested.

## Uninstall<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

```bash
sh ~/.claude/agent-tiers/scripts/agent-tiers remove
```

Or `/agent-tiers:setup remove` from inside Claude Code (flat route: `/agent-tiers-setup remove`;
plugin route without a checkout: use this one). [uninstall.md](uninstall.md) covers what it
removes, what it leaves in place, and how to remove only the hook rows; the
[uninstall prompt](prompts/uninstall.md) has your agent drive the whole removal one confirmed step
at a time.

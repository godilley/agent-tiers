# Uninstall / removal checklist

Prefer an agent-driven removal? Paste [prompts/uninstall.md](prompts/uninstall.md) into a Claude
session - it inventories first and confirms each step against this checklist.

Paths are `~/.claude/...`; swap in `$CLAUDE_CONFIG_DIR` if you installed into a second profile (see
[after-install.md](after-install.md)). Below, `agent-tiers` is short for
`sh ~/.claude/agent-tiers/scripts/agent-tiers` (on the plugin route, any checkout of the kit works, except that the status line keys are only recognised by the checkout that wrote them).

## 1. Run the remover

```bash
sh ~/.claude/agent-tiers/scripts/agent-tiers remove
```

Or `/agent-tiers:setup remove` inside Claude Code (flat route: `/agent-tiers-setup remove`). It
prints what it will do and asks first; `--yes` skips the question. Before it changes
`settings.json` it writes a timestamped backup next to it and keeps the newest 5.

| What | Flat route | Plugin route |
|---|---|---|
| Kit hook rows in `settings.json` | unwired with `install-flat.sh --unwire-only`, which also drops them from the kit's integrations ledger | none to unwire: the plugin wires its hooks itself |
| Skill and agent symlinks in `~/.claude/skills/`, `~/.claude/agents/` | removed | not created by the plugin |
| Command copies `~/.claude/commands/agent-tiers-*.md` | removed (`/agent-tiers-setup` included) | not created by the plugin |
| `~/bin/agent-tiers-share` | removed when it is a symlink to, or a copy of, the kit's script | not created by the plugin |
| Kit options (`pluginConfigs["agent-tiers@..."]`) and the three `AGENT_TIERS_*` env keys the CLI sets | deleted | deleted |
| `statusLine`, `subagentStatusLine` (status line extra) | deleted while they run this checkout's scripts, otherwise left | same |
| The plugin itself | not installed | **not removed**: run `/plugin uninstall agent-tiers@agent-tiers` (or `claude plugin uninstall agent-tiers@agent-tiers`) yourself |

Until the plugin is uninstalled it stays loaded, with every option back at its default (the `core`
level).

A skill or agent that is a real directory or file rather than a symlink (an install that printed
"couldn't symlink, so skills/agents were COPIED") is left in place and named in the output; remove
it by hand if it is the kit's copy.

If the remover stops with `kit hook rows still wired in <settings>`, `settings.json` holds kit hook
rows it could not unwire (for example, rows added by hand). It stops before removing anything else:
delete those hook rows from `settings.json` yourself and run it again.

## 2. What it leaves, and how to remove it

The remover ends with a "Not automated" list. Each item:

- **`settings.json.bak-*`:** the timestamped backups next to `settings.json`. Each is a full copy of
  your settings, so delete them too if that file ever carried anything sensitive.
- **`~/.codex-homes/<session-id>/`:** per-session Codex config isolation from the
  `codex-home-isolate` hook, on **either** route. No GC by design (see
  `scripts/codex-home-isolate.sh`); about 40MB a session and it only grows.
  `rm -rf ~/.codex-homes` once you are done with the kit.
- **Per-project artifacts** (from `/agent-tiers:init`, per project, not global):
  `.claude/agent-tiers.local.md`, `.claude/agent-memory-local/`, `.claude/skills/tier-project-brief/`,
  any prefixed L3 `.claude/agents/<prefix>-*.md`, `RESUME_SESSION.md`, the auto-memory copy under
  `~/.claude/projects/<slug>/memory/`, and the `## Agent tiers` / `## Building` / `## Workflow
  essentials` blocks `/agent-tiers:init` added to that project's `CLAUDE.md`.
- **Status line keys that are not this checkout's:** a `statusLine` or `subagentStatusLine` that does
  not run this checkout's scripts (your own, or one written by another or moved checkout) is left,
  and the remover prints `left in place` for it. Delete it by hand if it points at a deleted checkout.
- **`kit-config.md` and `.state/`:** these live inside the kit checkout, so deleting the checkout
  (last, below) takes both.
- **The kit checkout:** delete `~/.claude/agent-tiers/` (or wherever you cloned it) last, if you are
  leaving entirely. When the remover ran from the plugin (`/agent-tiers:setup remove` with no
  checkout), the path it names here is the plugin's own cached copy under Claude Code's plugins
  directory, not a checkout; leave it alone until the plugin is uninstalled.

## Removing only the hook rows

To take the kit's hooks out of `settings.json` and keep everything else (skills, agents, commands):

```bash
sh ~/.claude/agent-tiers/scripts/install-flat.sh --unwire-only
```

Add `--without-<id>` flags to remove only those rows: `install-flat.sh --unwire-only
--without-notify` removes just the `notify` row. Without `--unwire-only`, `--without-<id>` runs a
full install that leaves that row out, re-creating the links and command copies on the way. Either
way the row also leaves the integrations ledger, so `/agent-tiers:doctor` will not report it as
drift; removing a row by hand-editing `settings.json` leaves its ledger entry orphaned. These rows
can come back: a later `install-flat.sh` run wires the core rows again unless passed
`--without-<id>`, and `agent-tiers install` or `configure` (the last step of the flat update) wires
every hook of a group that is on unless its id is in `disabled_hooks`. To keep a hook off for good,
use `disabled_hooks` (below).

To stop the hooks acting without removing anything, turn single hooks off with
`agent-tiers configure --set disabled_hooks=<id>,<id>` (this replaces the whole list, so name every
hook you want off), or turn the kit off:
`agent-tiers configure --set enabled=false` (until you turn it back on), or start Claude Code as
`AGENT_TIERS_OFF=1 claude` for one session.

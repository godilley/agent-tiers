# Uninstall / removal checklist

Prefer an agent-driven removal? Paste [prompts/uninstall.md](prompts/uninstall.md) into a Claude
session - it inventories first and confirms each step against this checklist.

No single command undoes an install - `install-flat.sh` has no `--uninstall` flag. Remove what it
actually created, by hand, in this order. Paths are `~/.claude/...`; swap in `$CLAUDE_CONFIG_DIR`
if you installed into a second profile (see [after-install.md](after-install.md)).

- **Guards + core hooks:** `install-flat.sh --without-<id>` per row - this works for `core` rows
  (`resume-inject`, `codex-home-isolate`, `guard-summary`) as well as `consent` ones, and also drops
  the row from `.state/integrations.json`, so `/agent-tiers:doctor` won't later report it as drift.
  Hand-editing `settings.json` instead leaves that ledger row orphaned.
- **Skills + agents:** `rm -rf ~/.claude/skills/<name> ~/.claude/agents/<name>.md` (no trailing slash
  on the skill path - with one, `rm -rf` silently no-ops on a directory symlink instead of removing
  it, no error shown). Usually a symlink, so this touches nothing else - unless install-flat printed
  "couldn't symlink, so skills/agents were COPIED" at install time, in which case it's a real copy.
- **Commands:** `rm ~/.claude/commands/agent-tiers-*.md` (the flat-install copies).
- **`~/bin/agent-tiers-share`:** `rm ~/bin/agent-tiers-share`, if the installer put it there.
- **Kit config + ledger:** `kit-config.md` and `.state/integrations.json` live inside the canonical
  `~/.claude/agent-tiers/` checkout itself - deleting that whole directory (last, below) takes both.
- **`settings.json.bak-*`:** the installer keeps up to 5 timestamped backups next to `settings.json`.
  Each is a full copy of your hook config, so clear these too if that config ever carried anything
  sensitive.
- **`~/.codex-homes/<session-id>/`:** per-session Codex config isolation, wired by
  `codex-home-isolate` on **either** install path - the plugin's static `hooks.json` includes it too,
  not just the flat install. No GC by design (see `scripts/codex-home-isolate.sh`); ~40MB/session and
  it only grows. `rm -rf ~/.codex-homes` once you're done with the kit.
- **Per-project artifacts** (from `/agent-tiers:init`, not this installer - per project, not global):
  `.claude/agent-tiers.local.md`, `.claude/agent-memory-local/`, `.claude/skills/tier-project-brief/`,
  any prefixed L3 `.claude/agents/<prefix>-*.md`, `RESUME_SESSION.md`, the auto-memory copy under
  `~/.claude/projects/<slug>/memory/`, and the `## Agent tiers` / `## Building` / `## Workflow
  essentials` blocks `/agent-tiers:init` added to that project's `CLAUDE.md`.
- **Plugin path:** disabling/removing the plugin through your host's plugin manager stops the static
  hooks in `hooks/hooks.json` - but it still ran `codex-home-isolate` while active, so check
  `~/.codex-homes/` above too.

Delete the canonical `~/.claude/agent-tiers/` checkout (or wherever you cloned it) last, if you're
leaving entirely - everything above symlinks back to it.

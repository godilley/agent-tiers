# Uninstall prompt

Paste everything below the line into a Claude Code session to have your agent drive a clean
removal, one confirmed step at a time, following the kit's own checklist.

---

I want to UNINSTALL the **agent-tiers** kit from this machine. Its own removal checklist is
`~/.claude/agent-tiers/docs/uninstall.md` - read that first and follow it, with these rules:

1. INVENTORY (read-only). Work out what is actually installed here: does
   `~/.claude/agent-tiers/` exist, which hooks are on
   (`sh ~/.claude/agent-tiers/scripts/agent-tiers status`, or
   `/agent-tiers:doctor` step 4f), which skills/agents/commands in `~/.claude/{skills,agents,
   commands}` are symlinks or copies pointing at the kit, whether `~/bin/agent-tiers-share` and
   `~/.codex-homes/` exist, and whether a second profile (`CLAUDE_CONFIG_DIR`) was ever installed
   into - ask me if you can't tell. Also list per-project artifacts in THIS project if any
   (`.claude/agent-tiers.local.md`, `tier-project-brief`, `RESUME_SESSION.md`, the CLAUDE.md
   blocks).

2. PLAN + WAIT. Show me the exact removal commands in checklist order - run
   `sh ~/.claude/agent-tiers/scripts/agent-tiers remove` (never hand-edit settings.json; it unwires
   hooks, removes symlinks and command copies, and clears kit options, as the checklist table says),
   then whatever it leaves: the plugin itself (`/plugin uninstall`), any skill or agent it
   named as copied rather than symlinked, per-project artifacts, `~/.codex-homes/`, and the
   canonical checkout LAST. Flag
   anything you are not sure the kit owns. STOP and wait for my go.

3. REMOVE (only on my go), one step at a time, confirming each destructive command with me before
   running it. Never delete anything the inventory did not positively attribute to the kit. For
   files that carry MY content, not just the kit's scaffolding (`RESUME_SESSION.md`, the CLAUDE.md
   blocks, agent memories), show me the content or diff first - I may want to keep or move it.

4. VERIFY. Re-check the inventory comes back empty, and tell me what (if anything) was left
   behind on purpose and why.

Keep it terse + scannable.

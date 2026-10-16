---
description: Flag THIS session as unattended (no human at the keyboard), so a guard question that would otherwise halt the run comes back as an actionable deny instead. `/agent-tiers:unattended on|off|status` (flat installs: `/agent-tiers-unattended`).
---

You are the **Lead**, setting or clearing this session's unattended flag. The argument is `on`, `off`
or `status` (no argument = `status`).

## What the flag changes, and what it does NOT

A hook `ask` BLOCKS the tool call in every permission configuration, including `bypassPermissions`
(HOST-4, measured). It reaches a human only where the host has a prompt channel. So a preplanned run
with nobody watching halts at the first `ask` and stays halted - possibly for hours.

With the flag set, for THIS session only:
- `review-gate-guard` and `vcs-commit-guard` return their question as a **deny carrying the same
  remedy text**, prefixed to say why. The requirement is unchanged and still enforced. For the Lead, a
  review-gate deny means "spawn a reviewer, then retry the commit", which you can act on without a
  human. A subagent cannot clear it that way: the gate looks for a reviewer spawn in the transcript
  the hook payload names (the top session's), and the guard tells a subagent caller to leave the
  commit as-is, stop, and report the deny text back. So a subagent hands the commit back to the Lead.
- `EnterPlanMode` is denied (its confirmation has nobody to answer it; the brief IS the plan).
  `ExitPlanMode` is left untouched, never auto-allowed - a hook `allow` bypasses the whole permission
  chain, which is more permissive than this feature is meant to ever be (opus reviewer 2026-08-23,
  HIGH, killed an earlier draft that auto-allowed it - see "Exit plan mode BEFORE flagging" below). A
  session that starts unattended already in plan mode stays there until a human intervenes.
- `AskUserQuestion` is denied (a fork with nobody to pick a branch deadlocks the run) - the deny text
  says to take the smaller-diff reading and report the fork instead of asking.

It changes **nothing** about security posture: a hard DENY is never converted, in either direction.
Every conversion is written to `.state/guards.log` like any other decision.

**Not this flag's job, same guards (2026-08-27):** `review-gate-guard`, `vcs-commit-guard` and
`kit-leak-guard` also return `deny` instead of `ask` whenever the tool call came from a subagent (a
Task/Agent-spawned worker), regardless of this flag or whether a human is at the keyboard - a delegated
agent can't answer "is this trivial" any better than an absent human can. Turning this flag OFF does not
change that; a worker's commit still converts. See `guard_caller_agent` in `guard-cmdpos.sh`.

## Doing it

1. **Find this session's id.** Use `$CLAUDE_CODE_SESSION_ID` first: current Claude Code puts it in the
   Bash tool's environment (a hook gets the same value as `session_id` in its JSON payload):
   `printf '%s\n' "$CLAUDE_CODE_SESSION_ID"`
   Only when that is empty, fall back to guessing: the basename (without `.jsonl`) of the newest
   transcript in `~/.claude/projects/<slug>/`, where `<slug>` is the current directory path with `/`
   and `.` replaced by `-`:
   `ls -t ~/.claude/projects/$(pwd | sed 's#[/.]#-#g')/*.jsonl | head -1`
   The fallback can pick ANOTHER live session's transcript in the same project, so cross-check it
   against a path the harness has already shown you this session (background task output files are
   under a directory named for the session id) before writing anything.
2. **`on`** - create the flag:
   `mkdir -p "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/.state" && : > "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/.state/unattended.<session-id>"`
3. **`off`** - remove it:
   `rm -f "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/agent-tiers}/.state/unattended.<session-id>"`
4. **`status`** - report whether the file exists, and say plainly which session id you resolved.
5. Tell the operator, in one line, what is now flagged and how to undo it.

## Rules

- **Per session, never per repo.** Two Leads may share a repo; one of them being unattended must not
  change the other's prompts. A `/clear` mints a new session id, so a cleared chat starts attended.
- **Guessing the session id wrong is NOT safe.** A wrong id either applies to nothing (the run keeps
  halting - annoying, not dangerous) or names ANOTHER LIVE SESSION, whose asks then arrive as denies
  without its operator knowing. Two Leads sharing a repo is the exact case the per-session design
  exists for, and "newest transcript" is precisely the resolution that gets it wrong there. So when
  step 1 had to fall back to the newest transcript, its cross-check is a HARD PRECONDITION, not an
  aside: no corroborating second source for the id, no write. An id taken from
  `$CLAUDE_CODE_SESSION_ID` needs no second source. On the fallback route, if several transcripts
  were touched in the same minute, say so and stop.
- **Never set this on the operator's behalf as a convenience.** It is a statement about whether a
  human is present, which only the operator can make. If a guard just blocked you and you would like
  it to stop asking, that is not a reason to run this command - it is a reason to do what the remedy
  said.
- **A resume inherits the flag.** `/clear` mints a new session id (so a cleared chat starts attended),
  but `--resume` keeps the old one. The SessionEnd hook clears the flag at the end of each run for
  exactly this reason; if you resume a session that ended abnormally, check `status` first.
- **Exit plan mode BEFORE flagging.** Under the flag, entering plan mode is denied, and exiting it is
  deliberately left to the host - this feature never auto-approves anything.
- The flag is machine-local state under `.state/`, which is never tracked or shared.

---
description: Re-probe the local environment and print the current agent-tier model/effort resolution + a health check. Run after switching GUI, editor, or machine.
allowed-tools: Bash, Read, Glob, Grep, Task
---

You are the **Lead**. Quick health check of the agent-tier setup for this project. Read-only by default
- do NOT rewrite config unless the user asks.

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/probe-env.sh"` and show the key values.
2. Read `.claude/agent-tiers.local.md` if it exists; compare its recorded resolution to the live probe.
   Flag any drift (e.g. `effort_env` was empty at init but is now set → sub-agent effort is now pinned).
3. Confirm the agents are present and shaped right:
   - `advisor` exists with `tools: Read, Grep, Glob` only - and has NOT gained `Write`/`Edit` (a stray
     `memory:` field would auto-add them and break read-only enforcement). Same check for `reviewer`
     beyond its one curated `Write`.
   - `reviewer` exists with `tools: Read, Grep, Glob, Write`. NOTE: a new agent type only enumerates after
     a host **relaunch/watcher refresh** - if just added, flag that before it's spawnable.
   - `boss` exists with `tools: Read, Grep, Glob` only (same read-only check as advisor) - a stray
     `memory:` field would break its circuit-breaker guarantee just as badly.
   - a generic `worker` exists and any prefixed `<prefix>-*` L3 task agents.
4. Confirm the 3-layer wiring:
   - `worker`/`advisor`/`reviewer`/`boss` frontmatter each lists `tier-project-brief` under `skills:` (the
     L2 hook). `worker` also has `memory: local`.
   - `.claude/skills/tier-project-brief/SKILL.md` exists (this project extends the tiers) - or note the
     project runs in **graceful-skip** mode (no brief → tiers run generic, no error).
   - `.claude/agent-memory-local/` is git-ignored (excluded from VCS).
4b. **def-version consistency.** `rg -n 'def-version:' ` across every agent file (kit + project L3). Each
   agent should carry exactly one `def-version: N` body stamp. (Live vs disk is only checkable by spawning -
   step 5 - since a stale spawn quotes an older `def-v` in its check-in.)
4c. **VCS policy drift.** Read `vcs_policy:` from `.claude/agent-tiers.local.md`; for each artifact compare
   the recorded disposition to reality (`git check-ignore <path>` / `git ls-files <path>`). Flag mismatches
   (e.g. brief recorded `ignore-personal` but is tracked; `agent_memory_local` NOT ignored). Suggest
   `/agent-tiers-gc` (VCS area) or `/agent-tiers:init --reprobe` to reconcile.
4d. **Lifecycle report (read-only).** Measure and compare to thresholds; this is detection only - the
   fixer is `/agent-tiers-gc`. Checks (all cheap Bash):
   - **Lead auto-memory:** file count + `MEMORY.md` index lines + total KB. **Stale candidates:** memories
     citing a file / branch / tool that no longer exists (cheap existence checks) - LIST, don't judge.
   - **Agent memories:** each `<name>/MEMORY.md` lines + KB vs the 200-line / 25 KB injection cap; count of
     loose `notes-*.md` awaiting consolidation.
   - **RESUME_SESSION.md** line count; **tier-project-brief** bytes; **docs/plans/** file count + KB, with
     superseded/`SHIPPED` docs as archive candidates.
   - **Thresholds (advisory, tune with use):** memory index > 80 lines or > 80 files · RESUME > 70 lines ·
     brief > 4 KB · any agent `MEMORY.md` > 150 lines (75% of cap) · docs/plans > 500 KB.
   - Emit a small table + a single `gc suggested: <areas breached>` line (or `lifecycle: clean`).
4e. **Private-notes seam.** The `notes-sync.sh status` check below runs ONLY IF
   `git config --get notes-sync.dir` is set; the `doc-lifecycle-check.sh` line further below runs
   UNCONDITIONALLY regardless of that gate - do not skip it just because this repo has no notes dir
   configured yet, that is exactly the repo class its tracked-docs pass exists for.
   - If `notes-sync.dir` is set: one line, `bash "${CLAUDE_PLUGIN_ROOT}/scripts/notes-sync.sh" status`.
     Flag if the notes dir has files but the `local/notes` head is behind them (unsaved - suggest
     `notes-sync save`), and if `push` is a remote but `git ls-remote` shows the ref missing/behind
     (unpushed backup - suggest `notes-sync push`). Also confirm the notes dir is actually ignored
     (`git check-ignore <dir>/`); if NOT, the seam is broken and docs could bleed - suggest
     re-running `notes-sync setup`.
   - Always (no gate): `bash "${CLAUDE_PLUGIN_ROOT}/scripts/doc-lifecycle-check.sh"` and show its
     full report.
4f. **Integrations seam (hooks).** Read the ledger at `${AGENT_TIERS_LEDGER}` - the flat installer bakes
   the absolute per-profile path in here (one ledger per Claude profile, so a second `CLAUDE_CONFIG_DIR`
   account keeps its own). If that placeholder is still literal you are in plugin context: read the
   `.state/integrations.json` inside the kit root instead. (Absent = the
   flat installer never wired hooks here - state that, it is not an error). For each ledger row check:
   (1) the recorded `command` exists in the recorded `settings` file (missing = hand-removed; suggest
   re-running `install-flat.sh`, or `--without-<id>` to release the row); (2) the live group's
   event/matcher match the ledger (drift = a hand-moved row the installer will NOT reconcile - report
   exactly what differs); (3) the script's current `cksum` matches the recorded stamp (mismatch after a
   kit edit is normal - re-run `install-flat.sh` to refresh; an UNEXPLAINED mismatch on a consent
   (PreToolUse) row is possible substitution - say so plainly); (4) any settings row mentioning a kit
   script that appears in no ledger entry is FOREIGN - list it, never touch it. Emit one line per row:
   `<id> . <ours-current | ours-stale | missing | foreign | drift: <what>>`.
   THEN the absence half (T1.3, 2026-08-16 - a per-row walk cannot see a guard that was never wired, so
   a control that has never fired reads as a clean bill of health): read `HOOK_ROWS` out of
   `${CLAUDE_PLUGIN_ROOT}/scripts/install-flat.sh` (one row per line, `;`-separated: field 1 = id,
   field 2 = class `core|consent`). For every `consent` id whose `scripts/<id>.sh` EXISTS in this kit copy
   (an export-ignored, kit-local guard is not "unwired", it is not shipped - say `not in this copy` for
   it) and which has NO ledger row and NO live settings row, emit
   `<id> . available, NOT wired - enable with: install-flat.sh --with-<id>`. LEAD the whole 4f section
   with one line `guards: N of M wired` (N = consent ids with a ledger row, M = consent ids whose script
   is present). Do NOT suggest defaulting any consent row - `install-flat.sh` classifies them deliberately
   (security policy / a record of your work: wired ONLY on an explicit `--with-<id>`); `0 of 10 wired` is
   a true statement to show the user, not a fault to fix.
4g. **Band-dial falsifier trial (MAINT-6) - CLOSED 2026-08-30.** No longer reported here; the card is its
   own record of the closure (verdict + reasoning). `.state/band-tally.md`, if present, is a leftover from
   before closure - not read or reported by this step.
4h. **Guard block record (Wave D, 2026-08-16).** `.state/guards.log` next to the ledger is THE durable human
   record of guard blocks (HOST-4: under cc-gui (a third-party Claude Code GUI wrapper app) a denied Bash row is hidden and a denied Write shows `+N`
   with the reason dropped, so nothing else counts them). Every guard's deny/ask writes one line
   `<ts> <guard> deny|ask: <text> [sid=<session id>]`. Report, all cheap `grep -a` over the log: total
   deny/ask lines; per guard; the last 3 (strip the `[sid=...]` tag); and how many carry an EMPTY sid
   (`[sid=]` = a selfcheck run, not a session - say so). If the current session id is known, ALSO the
   count for this session - that is the same number the SessionEnd `guard-summary` line prints on stderr
   (whether a host renders that line to a human is `[unverified]` per configuration; this doctor step needs
   no channel). Absent log = no guard has ever fired or the kit is freshly installed - state that, not an
   error. Do not read `declined:` lines as blocks (a decline to scan is an allow with a breadcrumb).
4i. **Write-once artifacts vs the current template (2026-08-16).** Things the installer creates ONCE and
   never overwrites drift silently when the template gains a section - the third instance of the class
   (settings-row matcher, hooks.json vs guards, `kit-config.md`). Check: extract every `## ` heading from
   the `kit-config.md` template embedded in `${CLAUDE_PLUGIN_ROOT}/scripts/install-flat.sh` (the
   `KITCONFIG_EOF` heredoc) and confirm each appears in the live `${CLAUDE_PLUGIN_ROOT}/kit-config.md`.
   Do the same for the `vcs_defaults:` KEYS (the half that drives behaviour - each `  <key>: <value>` line
   under `vcs_defaults:` in the template must have a `<key>:` in the live file; values may differ, they are
   the operator's choices). Emit `kit-config: N of M template sections, K of L vcs_defaults keys present`
   and list any missing heading/key with "append it by hand from install-flat.sh's template; the file is
   write-if-absent by design". Same shape for
   `hooks/hooks.json` vs `HOOK_ROWS`: every `core` id in HOOK_ROWS should have a `hooks.json` entry
   (plugin path) - list any core id absent from the manifest.
5. (Optional, only if asked) spawn `worker` once with the trivial `printf '%s\n' "$CLAUDE_EFFORT"` brief
   to re-confirm effort resolution live - and confirm its check-in quotes the current `def-v<N>` (a mismatch
   means the on-disk edit hasn't been picked up yet: PENDING-REFRESH, see the Lifecycle protocol).
6. Report: a short table of {inherited model, effort pin, lead effort, worker effort, model-override}
   = recorded vs live, plus the 3-layer wiring status, the VCS-policy + def-version checks, and the
   Lifecycle table. If config drift is found, suggest `/agent-tiers:init --reprobe`; if lifecycle
   thresholds are breached, suggest `/agent-tiers-gc`.

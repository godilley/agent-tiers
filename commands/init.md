---
description: Probe the local environment and self-configure the agent-tier system for THIS project (records model/effort resolution, scaffolds the project brief skill + optional task agents, CLAUDE.md tier block, and the resume handoff).
argument-hint: "[--reprobe] (re-run the env probe even if a record already exists)"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task
---

You are the **Lead**. Set up the agent-tier kit for the current project. Work through these steps,
checkpointing with the user where noted. Do NOT pin the Lead's own model/effort anywhere - those are
GUI-owned; you only configure and verify the SUB-agents.

## 1. Bash-readable probe
Run the probe and read its output:
```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/probe-env.sh"
```
Note: `anthropic_model` (the inherited default), `effort_env` (if non-empty it PINS sub-agent effort),
`lead_effort` (this turn's effort), `settings_effort`, and `host_term`.

## 2. Sub-agent EFFORT resolution (auto)
Spawn the `worker` agent ONCE with this exact trivial brief (no project work):
> "Run `printf '%s\n' \"$CLAUDE_EFFORT\"` and return only that value on your check-in line. Do nothing else."

Compare the returned effort to the worker's frontmatter `effort: medium`:
- If they MATCH and differ from `lead_effort` → frontmatter effort is honored and sub-agents dial down
  independently of the Lead. Record `frontmatter_effort_real: <value>`.
- If the worker's effort equals `effort_env` instead → the env PINS effort; frontmatter can't lower it.

## 3. Sub-agent MODEL resolution (guided - cannot be auto-probed)
A sub-agent cannot reliably introspect its own live model; its check-in text is just declared. The only
ground truth is the GUI's agent/model panel. So ASK the user (AskUserQuestion), referencing the worker
spawn from step 2:
> "In your Claude Code GUI's agent/model panel, what model did the `worker` spawn just run as?"
Options should include the worker's frontmatter model (`sonnet`) and the inherited `anthropic_model`
from step 1, plus Other.
- Worker ran as `sonnet` → frontmatter `model:` OVERRIDES the inherited env. Record
  `frontmatter_model_overrides: true`.
- Worker ran as the inherited model → frontmatter is ignored here; record `false` and WARN the user the
  cheap-Worker lever doesn't work in this GUI (they may need to set the model another way).

**Known-host shortcut:** if the probe reported `host_guess=codemoss`, this resolution is already verified
(see the probe's `known_resolution=` line): `model:` OVERRIDES the inherited env, frontmatter `effort:` is
honored, `CLAUDE_CODE_EFFORT_LEVEL` is exported empty (no pin), `~/.claude/settings.json` effort is ignored,
and `advisor` is RO-enforced. Make `sonnet` the **(Recommended)** first option so the user confirms in one
tap instead of hunting the panel - only fall through to the full panel check if they report otherwise.

## 4. Tool enforcement (derivable)
Confirm `advisor` ships `tools: Read, Grep, Glob` only - record `advisor_readonly_enforced: true`
(tool-layer enforced, not merely instructed). Also confirm `reviewer` ships `tools: Read, Grep, Glob,
Write` (read-only on code; writes only its one curated file).

## 5. Record findings to BOTH places
**(a)** Write `.claude/agent-tiers.local.md` from `${CLAUDE_PLUGIN_ROOT}/templates/agent-tiers.local.md`,
filling the frontmatter with the resolved values + `host`, `probed_at`.
**(b)** Write the same facts to always-loaded auto-memory so the Lead knows them every session without
re-probing: locate this project's memory dir (the path used by your harness's auto-memory; commonly
`~/.claude/projects/<slug>/memory/`), write/update `agent_tier_env_behavior.md`, and add a one-line
pointer to that project's `MEMORY.md` index. If you can't find a memory dir, say so and rely on (a).

(VCS handling of `.claude/agent-tiers.local.md` and every other kit artifact is resolved in step 5b.)

## 5b. Resolve VCS policy (from kit-config, per-project overridable)
Read `${CLAUDE_PLUGIN_ROOT}/kit-config.md` → `vcs_defaults` (the user's global defaults). If the file is
ABSENT (plugin-path installs do not ship it - only the flat installer creates it), fall back to the kit
defaults (every class `ignore-personal`, `agent_memory_project: commit`), say so in the table, and suggest
creating it via `install-flat.sh` or by copying the template block from that script. Build the resolved
disposition table for the artifacts this project will have - `agent_tiers_local`, `project_brief`,
`task_agents`, `agent_memory_local`, `resume_session`, `attempts_log`, `private_notes` (and
`agent_memory_project` ONLY if the project opts into `memory: project`). Present the table, then
**AskUserQuestion** with a **"(Recommended) accept kit defaults"** first option, plus the chance to
override any line. Apply each disposition:
- `commit` → leave tracked (the project may `git add` it in its normal flow);
- `ignore-shared` → add the path to `.gitignore`;
- `ignore-personal` → add the path to `.git/info/exclude`.
Record the resolved map in `.claude/agent-tiers.local.md` frontmatter under `vcs_policy:` so
`/agent-tiers:doctor` can flag drift later. NEVER offer `commit` for `agent_tiers_local` (machine-specific)
or `agent_memory_local` (`local` memory scope = never committed, by definition). `private_notes` is
`ignore-personal` by definition too (never offer `commit`) - and it carries an EXTRA axis the other classes
don't: whether the `local/notes` ref is **pushed to a remote or kept local-only** (its actual setup lives
in step 6d).

## 6. Scaffold per-project pieces (each OPTIONAL - confirm with the user before writing)
- **Project brief skill (L2) - the main scaffold.** From
  `${CLAUDE_PLUGIN_ROOT}/templates/tier-project-brief.SKILL.md`, write
  `.claude/skills/tier-project-brief/SKILL.md`, filling `{{PROJECT}}`, `{{DOMAIN}}`, `{{BUILD_CMD}}`,
  `{{TEST_CMD}}`, `{{VERIFY_RULE}}`, `{{LANDMINES}}` - detect from the repo (package.json / gradle /
  Makefile / pyproject) or ask. The generic `worker`/`advisor`/`reviewer` **hook this skill**, so it
  extends every tier at once with **no duplication**; absent → they run generic (graceful skip). Keep it
  ≤ ~1-2k tokens (injected into every spawn) and include only what ISN'T already auto-injected via
  `CLAUDE.md` / `.claude/rules` / the memory index. (Its `.claude/agent-memory-local/` dir and the brief's
  own git disposition are handled by the VCS policy in step 5b.)
  **Verify:** spawn `worker` once and confirm it can quote a distinctive string from the brief (the skill
  hot-loads fast; if it can't, wait a few seconds and retry - the agent/skill watcher can lag).
- **Project task agents (L3) - offer, prove ONE first.** For a REPEATED mechanical procedure (run the
  gates, regenerate X, sweep Y), from `${CLAUDE_PLUGIN_ROOT}/templates/task-agent.project.md` write
  `.claude/agents/<prefix>-<task>.md` - **PREFIXED** (never a bare tier name: a project `.claude/agents/<name>`
  silently REPLACES a same-named global agent), hooking `tier-project-brief`. Scaffold one and prove it
  before adding more (build → prove → propagate). ⚠️ A newly-created agent file only becomes spawnable
  after the watcher registers it - seconds on the standalone CLI, but can be minutes on some GUIs.
- **CLAUDE.md kit block:** inject the contents of `${CLAUDE_PLUGIN_ROOT}/templates/tiers-block.md`
  into the project `CLAUDE.md` (create it if absent), so the tier vocabulary **and the
  build→prove→propagate rule** are always loaded. **Idempotent:** if a kit block (the `## Agent tiers` ...
  `## Building - universal seams` sections) already exists, REPLACE it with the current template rather
  than duplicating - this is also how an existing project picks up an updated kit.
- **Output-hygiene rule + backfix (optional, recommend YES).** The injected `tiers-block` carries a hard
  output-hygiene rule (no em/en dashes, no invisible/control chars, human-like phrasing). AskUserQuestion
  whether to KEEP that `## Output hygiene` section in this project's block (recommended first option) or
  drop it. If kept, ALSO offer to run `/agent-tiers-hygiene` now to backfix the project's EXISTING files
  (convert stray em/en dashes, strip invisible/control chars) - gated, per that command.
- **CLAUDE layout review (optional - recommend it):** offer to check the project's `CLAUDE.md` against the
  recommended layout (`context-file-layout` skill + `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.project.example.md`).
  Scaffold it from the example if absent; if it's huge or folds deep-dives into the always-loaded core,
  propose splitting those into `.claude/skills/<x>/SKILL.md` and slimming the core to pointers. Audit →
  present → confirm → apply; **never automatic**. ⚠️ Leave the user's PERSONAL global `~/.claude/CLAUDE.md`
  content alone - suggest *structure* only, never overwrite their about-you / machine / preferences.
- **Resume handoff:** if no `RESUME_SESSION.md` exists, offer to drop
  `${CLAUDE_PLUGIN_ROOT}/templates/RESUME_SESSION.md`. The agent-tiers **SessionStart hook auto-injects
  it** on compact/resume/clear - no per-project wiring needed. That hook ships in the plugin for the
  standalone CLI; under a **plugin-ignoring GUI** (e.g. CodeMoss) it's the GLOBAL `~/.claude/settings.json`
  hook that `scripts/install-flat.sh` wires. (A project may instead drop its own
  `.claude/hooks/load-resume.sh`; the global hook then stands down for it.)
- **Private-notes seam (6d - offer; recommend YES if the repo shares a `docs/` tree with an upstream or a
  team).** Keeps private planning docs in a git-ignored `docs/_local/` mirrored to a side `local/notes`
  ref that is never merged into a code branch - so they can never bleed into tracked history. Confirm the
  **push policy** from step 5b (`local` = never leaves the machine, the safe default; or a remote name),
  then run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/notes-sync.sh" setup --push <policy>` (creates the dir,
  adds the exclude, records `notes-sync.*` in `.git/config`). If the project already has stray private
  docs in a shared/tracked dir, offer `notes-sync.sh migrate <paths...>` to move + untrack them. Full
  runbook: `${CLAUDE_PLUGIN_ROOT}/docs/private-notes.md` if present - it's a kit-local doc, not bundled to
  recipients; proceed with the steps above without it if absent.

## 7. Report
Summarise (terse, scannable): what was probed, the resolved resolution rules, and which per-project
files you wrote. Flag anything the user must verify in their GUI (the model-panel answer especially).

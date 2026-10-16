---
description: Probe the local environment and self-configure the agent-tier system for THIS project (records model/effort resolution, scaffolds the project brief skill + optional task agents, CLAUDE.md tier block, and the resume handoff).
argument-hint: "[--reprobe] (re-run the env probe even if a record already exists) [--scaffold-only] (skip the host probe, steps 1-5)"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task
---

You are the **Lead**. Set up the agent-tier kit for the current project. Work through these steps,
checkpointing with the user where noted. Do NOT pin the Lead's own model/effort anywhere - those are
GUI-owned; you only configure and verify the SUB-agents.

**Probe skip.** Run `printf '%s\n' "${CLAUDE_CODE_ENTRYPOINT:-}"` first. If it prints `cli` (the interactive
native CLI, a proven host - see the HOST card, HOST-1) or the argument `--scaffold-only` was given, and
`--reprobe` was not, SKIP steps 1-5: record nothing about the host and never write `probed_at:`. If
`.claude/agent-tiers.local.md` does not exist, create it from the template and DELETE its `probed_at:` line
(the SessionStart hook reads any `probed_at:` line as probed, even `"{{PROBED_AT}}"` or an empty value, and
would then never flag a non-native host), then continue at step 5b. `sdk-cli` or any other value runs the full probe (third-party GUI hosts report
`sdk-cli` too).

## 1. Bash-readable probe
Run the probe and read its output:
```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/probe-env.sh"
```
Note: `anthropic_model` (the inherited default), `effort_env` (if non-empty it PINS sub-agent effort),
`lead_effort` (this turn's effort), `settings_effort`, and `host_term`.

## 2. Sub-agent EFFORT resolution (auto)
Spawn the `worker` agent ONCE with this exact trivial brief (no project work):
> "Run `printf '%s\n' \"$CLAUDE_EFFORT\"` and report the tool result as harness effort separately from your role/definition check-in. If empty, report unverified. Do nothing else."

Compare the sourced, nonempty tool result to the worker's frontmatter `effort: medium` (an empty/missing result remains unverified):
- If they MATCH and differ from `lead_effort` → frontmatter effort is honored and sub-agents dial down
  independently of the Lead. Record `frontmatter_effort_real: <value>`.
- If the worker's effort equals `effort_env` instead → the env PINS effort; frontmatter can't lower it.

## 3. Sub-agent MODEL resolution (runtime evidence)
Apply the shared identity-evidence contract (SC-6.4) to the worker invocation from step 2.
Record its requested selector/alias and the inherited default separately. Inspect the native
harness record for that same child/turn; name its source. If the adapter translates aliases,
record the concrete resolved model and any upstream observation separately. A greeting,
brief, launch flag or rewritten panel label does not verify the backend model.

If only the GUI panel is accessible, ask the user for the value displayed for that worker.
Record it as **panel-reported**, with runtime/upstream identity **unverified** unless the host
exposes evidence establishing what that label represents. Do not label the panel "ground truth".
- Record `frontmatter_model_overrides: true` or `false` only when evidence distinguishes the
  worker selection from inheritance. If both resolve to the same model, this probe cannot decide.
- Otherwise record `frontmatter_model_overrides: null` and explain the missing evidence; do not
  guess or record a verified-looking boolean. Host-name shortcuts are historical expectations,
  not observations of this invocation.

## 4. Tool enforcement (derivable)
Confirm `advisor` ships `tools: Read, Grep, Glob` only - record `advisor_readonly_enforced: true`
(tool-layer enforced, not merely instructed). Also confirm `reviewer` ships `tools: Read, Grep, Glob,
Write` (read-only on code; returns its findings inline, the Write grant goes unused).

## 5. Record findings to BOTH places
**(a)** Write `.claude/agent-tiers.local.md` from `${CLAUDE_PLUGIN_ROOT}/templates/agent-tiers.local.md`,
filling the frontmatter with supported findings + `host`, `probed_at`. Preserve requested,
resolved and observed distinctions in the evidence section; missing evidence stays unverified.
**(b)** Preserve the same evidence sources and unverified fields when writing findings to always-loaded auto-memory so the Lead knows them every session without
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
`task_agents`, `agent_memory_local`, `resume_session`, `private_notes` (and
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
  - **A domain-specific procedure has its own starting template**, still following build → prove →
    propagate: **QA** (modes `red` / `run` / `fix-tests`, evidence-table contract) from
    `${CLAUDE_PLUGIN_ROOT}/templates/task-agent.qa.md`, filling `{{PREFIX}}`, `{{PROJECT}}`, written to
    `.claude/agents/<prefix>-qa.md`. This one needs a real test command to do anything, so it is stricter
    than the L2 brief's own graceful-skip default (MAINT-1: a MISSING brief lets the generic
    `worker`/`advisor`/`reviewer` fall back to working generically - fine for them, but this agent's whole
    job IS the brief's test command). **Check before scaffolding, don't just offer it:** confirm
    `.claude/skills/tier-project-brief/SKILL.md` exists AND its `## Test / verify` section has neither the
    unfilled command-line template slot nor the unfilled verify-rule slot right after it still in place;
    if any of those is missing, write or finish the brief first rather than scaffolding an agent that can
    only ever return `blocked`. The scaffolded agent also refuses this same check at spawn time as a
    second, independent line of defense. Frontend and DB starting templates are not built yet.
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
  it** on startup/compact/resume/clear, capped so the whole inject stays under the host's 10000-character inline limit, which leaves about 5-8 KB for the handoff (past the cap: the head, cut at a whole
  line, plus a line naming the file to Read) - no per-project wiring needed. That hook ships in the
  plugin for the standalone CLI; under a **plugin-ignoring GUI** (e.g. CodeMoss) it's the GLOBAL `~/.claude/settings.json`
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

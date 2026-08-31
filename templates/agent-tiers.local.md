---
# agent-tiers per-project env record - written by /agent-tiers:init. Git-ignored, machine/GUI-specific.
host: "{{HOST}}"                            # e.g. CodeMoss GUI 2.1.x / terminal / editor addon
probed_at: "{{PROBED_AT}}"
inherited_model: "{{ANTHROPIC_MODEL}}"      # model the GUI exports to sub-agents as the default
effort_env_pinned: {{EFFORT_ENV_PINNED}}    # true if CLAUDE_CODE_EFFORT_LEVEL is set (then frontmatter effort can't dial down)
lead_effort: "{{LEAD_EFFORT}}"              # $CLAUDE_EFFORT at probe time
settings_effort: "{{SETTINGS_EFFORT}}"      # ~/.claude/settings.json effortLevel (GUI may ignore it)
frontmatter_model_overrides: {{MODEL_OVERRIDES}}   # USER-CONFIRMED via GUI panel - true if a sub-agent's `model:` beats the inherited model
frontmatter_effort_real: "{{EFFORT_REAL}}"  # the worker's actual effort, read from $CLAUDE_EFFORT in a probe spawn
advisor_readonly_enforced: {{ADVISOR_RO}}   # advisor truly limited to Read/Grep/Glob at the tool layer
vcs_policy:                                 # resolved per-artifact git dispositions (init step: kit-config
  {{VCS_POLICY_ROWS}}                       # vcs_defaults if present, else kit defaults, + project
                                            # overrides). PRESERVE existing rows on --reprobe - resume-
                                            # inject.sh surfaces these every handoff.
---

# agent-tiers resolution for this project

How THIS environment resolves per-agent overrides (so the Lead need not re-probe each session):

- Sub-agent **model**: frontmatter `model:` {{MODEL_OVERRIDES_PROSE}} the inherited `{{ANTHROPIC_MODEL}}`.
- Sub-agent **effort**: frontmatter `effort:` {{EFFORT_PROSE}} (env pin: {{EFFORT_ENV_PINNED}}).
- **advisor** is read-only-enforced: {{ADVISOR_RO}}.

## Scope matrix (v4) - this project's per-task-shape defaults

Defaults by work SHAPE (Lead overrides per spawn via the Agent `model` param; mixed model/effort
fan-outs via a Workflow). Ladder: sonnet/haiku free . single opus announce-only . opus fan-out /
Boss / fable gated. Full doctrine -> the `agent-tiers` skill.

| Task shape | Who | Model | Effort |
|---|---|---|---|
| Route, brief, verify, light synthesis | Lead | sonnet (GUI) | high |
| Rote scripted procedure | L3 task agent | haiku | low |
| Mechanical with some judgment | Worker / L3 task agent | sonnet | low-medium |
| Fan-out research / audit first pass | worker / auditor | sonnet | low-medium |
| Deep reasoning, ONE bounded ask (design/plan/hypothesis) | Advisor | opus | high |
| Curate cheap audit drafts | Reviewer | opus | high |
| Clever code (session pref = codex, per-host) | codex-write (isolated worktree) | codex tier | low-high |
| Clever code otherwise | Worker `model: opus` | opus | medium-high |
| Stuck circuit-breaker (gated) | Boss | opus (fable if opus implicated) | xhigh |
| Exceptional hardest-reasoning call (gated) | Advisor/Boss `model: fable` | fable | xhigh |

> The Lead's own model/effort are GUI-owned and intentionally NOT recorded/pinned here.
> Re-run `/agent-tiers:init --reprobe` after switching GUI/editor/machine; `/agent-tiers:doctor` checks drift.

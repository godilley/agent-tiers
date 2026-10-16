<a name="top"></a>
# What ships

[Back to the README](../README.md)

| What | Ships |
|---|---|
| **Agents** | Lead / Sublead / Worker / Advisor / Reviewer / Boss, plus optional Codex handoff |
| **Skills** | tier vocab, delegation, session handoff, context-file layout, doc lifecycle, plan waves |
| **Commands** | `init`, `doctor`, `gc`, `hygiene`, `resume`, `notes`, `unattended`, `setup`, `context-map` |
| **Config** | a VCS-policy config file |
| **Hooks** | core session hooks, plus guard hooks in groups you turn on by level |
| **Templates + scripts** | install CLI, env probe, flat install, doctrine lint, notes sync, kit share, selfchecks |

All portable, verbatim, no per-project edits needed. How the kit maintains its own artifacts after
install - staleness stamps, gated curation, VCS policy, the private-notes seam - is
[docs/after-install.md](after-install.md).

## Item-by-item inventory<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

- **Agents** - `advisor` (read-only, reasoning, returns a recommendation), `reviewer` (Opus, read-only
  on code, curates noisy first-pass audit drafts into one trustworthy list - a gated escalation), `boss`
  (read-only, human-gated circuit-breaker for a stuck Lead - runs a model DIFFERENT from the Lead's for
  real independence (opus under a sonnet Lead; fable if opus was already implicated); decides, never
  explores), `sublead` (opus, gated by a `[sublead-approved:]` tag: leads one independent slice of a
  plan over its own children, never pushes), and a
  generic `worker` (cheap/fast, mechanical, follows the brief, never decides). Optional cross-lab
  `codex-read` / `codex-write` (OpenAI Codex handoff - read/generate-only and write paths) ship too.
- **Skills** - `agent-tiers` (tier vocab + the check-in technique & return gotcha), `gating-workflow`,
  `delegation` (+ the build->prove->propagate rollout rule), `session-handoff`, `context-file-layout` (CLAUDE.md +
  context-file structure + a refactor playbook), `doc-lifecycle` (how a private notes-dir doc reaches a
  clean terminal state), `plan-wave` (run a plan's ready rows as parallel `sublead` agents, one
  worktree each, forks relayed to the human, merged in wave order).
- **Commands:** `init` (set up a project), `doctor` (health + lifecycle report), `gc` (gated curator /
  optimiser), `hygiene` (backfix em/en dashes + invisible chars in a project's files), `resume` (refresh
  the handoff, steerable like `/compact <steer>`), `notes` (private-notes seam), `unattended`
  (flag a session as unattended so a guard `ask` converts to an actionable `deny` instead of halting), `setup`
  (install, reconfigure or remove the kit through the CLI, with menus), `context-map` (table of what
  gets injected into a session - CLAUDE.md chain, rules, memory index, hooks, output style, skills -
  with sizes and firing counts read from a `claude --debug-file` log; it never runs a hook).
  Full set: `commands/*.md`. Invoked `/agent-tiers:<name>` (plugin) or `agent-tiers-<name>` (flat).
- **Kit config:** `kit-config.md` (your global VCS-policy defaults; created write-if-absent by the flat
  installer). Plugin-path installs don't ship it - consumers fall back to kit defaults (every class
  `ignore-personal`, `agent_memory_project: commit`) when it's absent.
- **Layer registry:** `templates/LAYERS.md`, copied by you to `~/.claude/agent-tiers/.state/LAYERS.md`
  (under `$CLAUDE_CONFIG_DIR` when set; on the plugin route create that folder) and filled per machine,
  never tracked. One row per thing that injects context (CLAUDE.md files, plugins, hooks): its owner,
  why it loads, which one wins a conflict, and how to switch it off. `context-map` marks each layer
  registered or not; once the file exists, session start names any enabled plugin or settings hook
  with no row. No file, no advisory.
- **Templates + scripts** (the `agent-tiers` install CLI, env probe, flat install, doctrine lint, notes
  sync, kit share, per-guard selfchecks, `codex-run.sh`).

## The check-in line<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

**A spawn's check-in line** identifies its role and definition version, so a stale
definition is visible. It does not certify the model or effort:

> Hi, I'm worker - Worker tier, def-v8. Task: create and verify a slugify shell script.

Model/effort evidence is separate: requested settings are declared; adapter resolution and
runtime observations name their sources. Missing runtime evidence is labelled unverified.
The shared contract lives in agent-tiers, "The check-in line" (SC-6.4).

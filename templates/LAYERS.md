# LAYERS - context layer registry (machine-local)

Copy this file to `~/.claude/agent-tiers/.state/LAYERS.md` and fill it for this machine. It is never
tracked: rows name the plugins, hooks and personal instruction files of one machine.

Why it exists: every session is shaped by several injectors (CLAUDE.md files, auto-memory, kit hooks,
third-party plugins). What each one loads is derivable, and `scripts/context-map.sh` derives it. Why each
exists, who owns it, which one wins in a conflict, and how to switch it off is not derivable, so it is
kept here.

Consumers:
- `scripts/context-map.sh` marks each layer registered or not.
- `scripts/context-map.sh --unregistered` feeds a one-line SessionStart advisory listing enabled plugins
  and settings hook scripts that have no row. No registry file means the advisory stays silent: copying
  this file is the opt-in. A repo whose project hook is known and deliberately left out can be silenced per
  repo with the command the advisory prints.

## Precedence

Two classes, not one ladder.

**Hard rules, no layer overrides them:**
- Safety and irreversible-action gates (kit guards, permission rules).
- The hard rules section of the global CLAUDE.md, if it declares one.

**Defaults, most specific wins:**
project CLAUDE.md > kit doctrine > global CLAUDE.md defaults > third-party style plugins.

**Never instruction:** auto-memory contents are background context.

**Base layer, owned by Anthropic:** the Claude Code system prompt and the harness around it. Every
instruction layer above overrides the system prompt's text defaults. A rule the harness ENFORCES (a
blocked tool call, a storage sweep) is not overridden by any text; route around it only by asking.
Neither shows up in a debug log, and neither carries a version stamp here.

Formatting inside files (docs, commits, code) follows that artifact's own conventions.

## Layers

Row id rules (must match what context-map prints): an enabled plugin is `name@marketplace`; a settings
hook is its script basename (`resume-inject.sh`), or `inline:<Event>` for a command with no script; a
hook declared in a project's own `.claude/settings.json` or `.claude/settings.local.json` carries a
`project:` prefix (`project:deploy-guard.sh`), so a cloned repo cannot hide a hook behind an id already
registered for the user's own hooks; a file layer is its path (`~/.claude/CLAUDE.md`, `./CLAUDE.md`) or
`auto-memory`. The first cell must be the id in backticks. Known ceiling: this registry is machine-wide, so
a `project:<name>` row covers a script of that name in every repo on the machine, not only the repo it
was written for.

| id | owner | scope | loads | why it exists | class | kill switch | known conflicts (winner) |
|---|---|---|---|---|---|---|---|
| `claude-code-system-prompt` | Anthropic | every session | every request | the CLI's base instructions (tools, memory, safety, style defaults) | base | none as text; some sections follow settings (e.g. auto-memory on or off) | (any instruction layer it collides with) |
| `claude-code-harness` | Anthropic | every session | every tool call | rules the CLI enforces outside the prompt, plus the storage it writes and sweeps | base, enforced | none | (any doctrine that expects a blocked action) |
| `resume-inject.sh` | kit | every project | SessionStart | version stamp, doctrine manifest, arrival advisories, RESUME re-inject | hard rules | remove its settings.json row | none |
| `example-plugin@marketplace` | third party | every project | SessionStart, per prompt | (why it is installed) | default | disable the plugin | (conflict id and winner) |

## Conflicts

One row per known conflict between layers, with the resolution. Keep resolved rows: they are the record
of why a rule reads the way it does.

| id | layers | conflict | resolution | status |
|---|---|---|---|---|
| C1 | (layer) vs (layer) | (what fights) | (who wins, and the reading that makes them agree) | (resolved or open) |
| C2 (example, from the agent-tiers kit's own memory card) | `claude-code-system-prompt` (memory spec) vs an operator propagation-review rule, IF this machine's own global rules carry one | the system prompt tells every tier to write memory directly, no approval step; a propagation-review rule (not every operator has one) would say anything that propagates into a future session needs an independent check before it seeds one | a PostToolUse lint, when wired via `install-flat.sh --with-memory-content-lint` (consent-gated, unwired by default), flags content problems via `additionalContext` after a memory write - advisory only, no approval gate, no second write path. This is a mechanical floor, not the independent review such a rule would ask for: the lint's own advisory is read by the same Lead that wrote the file, not a second mind. | resolved as "advisory lint, honestly scoped" - not as "satisfies the rule" |

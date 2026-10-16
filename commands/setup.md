---
description: Install, reconfigure or remove the kit through its CLI, with menus. `/agent-tiers:setup install|configure|remove|status` (flat installs: `/agent-tiers-setup`).
---

You are the **Lead**, running the kit's setup menus. The argument is `install`, `configure`, `remove` or
`status`. Before the first question of any action, show status's install type and group lines as an
ended reply (Hard rules). No argument: run `status` (Gather, below), then ask one single-select "What now?". Recommend
`install` when status's `level:` line reads `never configured`, else `configure`.

CLI, always as `sh "${CLAUDE_PLUGIN_ROOT}/scripts/agent-tiers" <install|configure|remove|status> [--level L] [--set key=value]... [--yes] [--dry-run]`.

## Hard rules

- Never edit settings.json or any other file yourself, and never run `install-flat.sh` directly. Every
  change goes through the CLI, always with `--yes` (Bash has no stdin, so a prompt would abort).
- Never eval `detect-env.sh` output. Never pass a proposal the user did not accept.
- Show the exact command line before running it. Relay CLI error lines verbatim. Never retry with
  changed flags without asking first.
- `--level`, `--set` and `--dry-run` are rejected by `remove` and `status`.
- Question conventions (gating-workflow): question text ends `Checked: <what was read or run>`;
  single-select: first option `(Recommended)`, its description names the deciding fact; multiSelect:
  every option in the recommended set carries `(Recommended)`; each description has a cost in
  countables (hooks, steps), about 12 words. Context too big for the box (a table, a list) is an ended
  reply, last line `operator:ask_next` (other hosts: `operator:want_input`, ask next turn); the
  question comes after the send-back, never in the same response.

## Gather (every action)

1. Run `status`. It gives install type (`flat`, `plugin`, `flat plugin`, `none detected`), enabled, a
   `level:` line (`never configured`, a level id, `custom`, or `partial (N of M groups stored)`), one
   line per group (`<g> <value> (stored)|absent (...); N of M hooks wired`, or `; wired by plugin (M
   hooks)` when the plugin is enabled and there is no flat install, plus `; N also wired in
   settings.json` when kit rows remain there), disabled_hooks, the three env keys
   (value or `unset`), `extra ...` lines (`extra statusline: statusLine <kit|other|unset>, subagentStatusLine
   <kit|other|unset>`; `extra agentsview: pointer only; agentsview on PATH: yes|no`), and maybe an
   `agent-tiers:` kit-gate line.
2. Read `${CLAUDE_PLUGIN_ROOT}/install/options.tsv`: `level` rows (id, groups, summary), `option` rows
   (key, title, description), `hook` rows (id, group), `extra` rows (id, action `settings` or `pointer`, title, description). Count a hook only if
   `${CLAUDE_PLUGIN_ROOT}/scripts/<id>.sh` exists (a shared kit copy omits some; the CLI prints
   `skipped (script not in this kit copy): <ids>`). Count core from its rows too; hard-code no number.
3. install and configure only: if status says `install type: flat plugin` AND the CLI path above sits
   in a plugin cache (`.../plugins/cache/<marketplace>/<plugin>/<version>/scripts/agent-tiers`), STOP
   before building any command: this run would use the plugin-cache CLI and install-flat would
   re-flatten from that cache. Tell the user to run the flat copy `/agent-tiers-setup` instead (its
   path is the flat kit, so it proceeds), and that with both installs every guard can run twice.
   (`status` and `remove` proceed.) Otherwise run
   `sh "${CLAUDE_PLUGIN_ROOT}/scripts/detect-env.sh"`. Lines are `key=value`, value = everything after
   the first `=`. `propose.<VAR>=` appears only with a proposal; `reason.<VAR>=` always.

## install, configure

**Configure first:** ask single-select "Keep current groups (Recommended)" vs "Change level or groups".
Keep means no `--level`; go to Detected env.

**Level step** (install, or configure after "Change"): first an ended reply with a short table of every
`level` row (id, its groups, hook count incl. core, summary), last line `operator:ask_next`. Then ONE
single-select, one option per level row plus `Custom`. First option = the `recommended` row, marked
`(Recommended)`, deciding fact in its description; that description also names any group status shows
on now that this level would turn off. Others: summary shortened plus hook count. Today levels + Custom
= 4 options; if a future options.tsv exceeds that, stop and report that the menu needs a redesign.
A level stores every group explicitly: `true` inside it, `false` for every other group.

**Custom** (works for install and configure): multiSelect over every `option` row whose key starts
`group_`; label = title, description = the description column + the group's hook count. Today 8 groups =
two questions of 4 in one call; more than 8: stop and report. Recommended set = groups now on
(`true (stored)`, or `absent (on for flat)` with hooks wired) plus the groups of the `recommended` level
row. Spread them so each question holds at least one recommended group, and say why in the marked
descriptions (on now / in the Recommended level). Zero picked = core. A hook row's `requires` column in
options.tsv names the hooks it needs (precompact-guard needs authorship-record): when a plan leaves a
required hook off, the CLI leaves the dependent unwired and says so in a `not wired:` plan line (an
`inert:` line instead when the plugin is enabled or the dependent is already wired).

**Detected env:** for each `propose.<VAR>=` whose value differs from the current value in status, one
single-select (batch up to 4 per call): question shows the variable, the proposed value and the
`reason.<VAR>` line; options `Set it (Recommended)` (deciding fact = the reason) and `Leave as is`.
None found: say so in one line and move on. Declined proposals are never passed.

**Extras:** for each `extra` row with action `settings` whose status line is not `kit` for both keys, one
single-select (batch up to 4 per call, with other questions): question shows the title, the description
and status's current `extra <id>:` value; options `Leave as is (Recommended)` (deciding fact: adding it
changes your own status line; if status shows `other`, say it would be replaced) and `Add it`. Accepted:
`--set extra_<id>=true`. If status shows `kit` and the user asks to drop it: `--set extra_<id>=false`.
Never pass an extra the user did not accept. `pointer` rows get no question: relay their printed text
after the run.

**Build the command:**
- Preset level L: `install --level L --yes` (or `configure`).
- Custom: `<install|configure> --level core --set group_<g>=true ... --yes`. The CLI has no custom
  level: `core` stores `false` for every group, then `--set` wins.
- Configure keep: `configure --yes` plus only the env `--set`s. It also stores never-stored groups at
  their current effective state (on when a flat install has any of their hooks wired) and wires that
  group's missing hooks; with the plugin enabled it leaves them unset instead and the plan says so in a
  `note: groups never stored stay unset` line (relay it; `--level` stores them). Nothing to set: on a flat install, still run `configure --yes` when a group is
  `true (stored)` and fewer of its hooks are wired than it has hooks with a script that are not in
  `disabled_hooks` (that run wires the missing rows), or when status's `level:` line reads
  `never configured` or `partial (...)` and a group shows hooks wired; otherwise say so and run nothing. With the plugin enabled, group lines read `wired by plugin (M hooks)` (no
  flat install; a `; N also wired in settings.json` suffix means kit rows left in settings.json run each
  of those hooks twice: relay it and the plan's `install-flat.sh --unwire-only` note) or `N of M hooks wired; plugin also wires them` (flat too), and the CLI writes options
  and env only and wires nothing: never read a low count as missing rows there, and leave wired counts
  out of the summary.
- Accepted proposal: `--set 'VAR=value'`, whole pair single-quoted, an embedded `'` written `'\''`:
  `--set 'AGENT_TIERS_NOTIFY_FOCUS_CMD=i3-msg "[id=%s] focus"'`.
- `--set extra_<id>=true|false`: only for an extra the user accepted or asked to drop (Extras above).
- `--set enabled=false|true`: only if the operator asks to turn the kit off or on.
- `--set disabled_hooks=id,id`: only if asked. The key REPLACES the whole list: the value is the ids on
  status's `disabled_hooks:` line plus the newly named ids, minus any the user asks to re-enable. Every
  id must be an options.tsv hook row: drop one that is not (the CLI exits 2 on it) and name it in the
  confirm question. Same for an unknown id in a CLI `hint:` value.

**Confirm and apply:** first run the identical built command with `--dry-run` appended. It writes and
runs nothing and prints the Plan block that command would apply. Show that Plan block as an ended reply,
last line `operator:ask_next` (Hard rules). If the dry run exits nonzero, relay its error lines, do not
ask the confirm question, and handle it as in Errors. Then single-select "Run it (Recommended)" / "Cancel"
(this replaces the CLI's own prompt, which `--yes` skips). Put the exact full command line (without
`--dry-run`) in the question text AND in the "Run it"
option's `preview` field, so the box stands alone. Run it, then `status`, and summarise in a few bullets:
install type, groups on with hook counts, env values set, any `skipped`/warning line (a skipped id
explains a "5 of 6 hooks wired" line; it is not a failure). Then say:
- flat: the CLI re-bakes commands and wires hook rows via install-flat; start a new session for newly
  wired hooks and env values to load.
- plugin enabled (with or without a flat install): the CLI writes options and env only and wires
  nothing (`engine: not run (agent-tiers plugin enabled ...)`); the plugin's hooks are already wired and
  read the options at run time, so group changes apply at once; env values need a new session. With a
  flat install too, its rows still in settings.json run each hook twice: relay the plan's
  `install-flat.sh --unwire-only` note.
- Any `Detected ... to accept: --set` or `to add extra <id>: --set` hint lines in the output were NOT applied.
- Relay any `Extra <title>:` pointer lines. A status line change shows in a new session.

## remove

From status, write an ended reply (last line `operator:ask_next`) listing what goes. Flat: every kit
hook unwired, the kit's skill/agent symlinks, its `agent-tiers-*.md` commands (this one included) and
`~/bin/agent-tiers-share` when it is the kit's, all `agent-tiers@` pluginConfigs entries, the three env
keys. Both routes also delete the `statusLine` and `subagentStatusLine` keys, only while they point at this kit copy's scripts (otherwise left). Plugin: only its options, env and those status line keys are deleted. Then single-select: `Remove (Recommended)` (the
remove argument asked for it; settings.json is backed up first), `Cancel`. Run `remove --yes`, relay the
output (including its "Not automated" list), run `status`. Plugin install: tell the user to run
`/plugin uninstall <key>` themselves (key from the output); until then the plugin stays loaded, with
every option back at its plugin default. Flat: this command's copy is gone, so `/agent-tiers-setup`
no longer exists.

## status

Run it and summarise: install type, enabled, groups on/off with wired counts, env values, the kit-gate
line if any. No questions.

## Errors

- Exit 2: the command line was wrong. Show it and the error; any retry with changed flags goes through
  a question first. A missing jq also exits 2 (`agent-tiers: jq is required ...`): tell the user to
  install jq, nothing else.
- Exit 1: relay the `agent-tiers:` lines and any `install-flat: refusing --with-<id>: <reason>` line.
  - `hint: re-run with --set disabled_hooks=<ids>`: offer (Recommended first) the IDENTICAL original
    command with `--set disabled_hooks=<hint value>` appended (dropping `--level` would fall back to
    core and lose the level; env sets would be lost too). install-flat stops at the first refusal, so
    ask again while refusals keep coming.
  - `~/bin/agent-tiers-share` refusal: first say what it points at (`ls -l`), it may be another kit
    copy; tell the user to move it aside; never move it yourself.
  - `kit hook rows still wired in <settings>`: relay it, tell the user to remove those hook rows by
    hand and re-run; never edit settings.json yourself.
  - `install-flat.sh exited 0 but reported a failure`: relay the quoted lines under it; settings.json
    options were not written. Offer nothing automatic.

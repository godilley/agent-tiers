<a name="top"></a>
# Hooks and guards

[Back to the README](../README.md)

If a guard blocked something, its deny reason says what to do next (examples under
[Guards in action](#guards-in-action)); to turn its group or the single hook off, see
[Change the setup later](install.md#change-the-setup-later).

Every kit hook belongs to `core` or to one group. Core hooks act at every level. A guard acts only
when its group is on and its id is not in `disabled_hooks`: each hook asks the kit gate
(`scripts/kit-gate.sh`) before it does anything, so switching a group off needs no rewiring. You
pick the groups at install time ([levels and groups](#levels-and-groups)).

| Hook | Group | What it does |
|---|---|---|
| `resume-inject` | core | Re-injects `RESUME_SESSION.md` |
| `codex-home-isolate` | core | Per-session `CODEX_HOME` |
| `guard-summary` | core | SessionEnd stderr line counting the session's guard blocks from `.state/guards.log`, the durable record |
| `dangerous-actions-blocker` | safety | Hard-denies force-push to main/master, `DROP`/`TRUNCATE DATABASE`, `dd`/`mkfs`, publishes, secret shapes on a command line |
| `security-gate` | safety | Scans content being written - every file type - for secrets and injection-prone patterns |
| `reach-guard` | safety | Denies an agent command that reaches another machine or a logged-in account (`ssh`, remote copies, cloud CLIs, `gh api`) and hands it back for you to run yourself as `! <command>`; a read-only one is asked about instead |
| `grep-footgun-guard` | shell_footguns | Blocks recursive raw `grep`, which silently skips NUL-byte files |
| `review-gate-guard` | commit_review | Asks at the repo's ship point (commit and push by default; push only when `review_gate: push`) when no reviewer/advisor spawn exists this session |
| `codex-guard` | delegation | Denies bare `codex`; routes through the `codex-run.sh` wrapper and its secrets scan |
| `peer-guard` | multi_session | Notes, once per change, another live Claude Code session in the same repo; denies a session's first file edit in a different repo (read its docs, then retry), or asks when a live session already works there. Linux only (reads `/proc`); fails open elsewhere |
| `simple-rules-guard` | multi_session | Small literal rules on one hook row (the script header lists them all). Rule F denies a main-session `SendMessage` to another agent that carries neither `NOOP-IF-DONE` nor `RESUME-OK`, because a message to a finished agent resumes it; Rule D denies an `AskUserQuestion` question whose first option (any option, for multiSelect) lacks `(Recommended)`; Rule G denies waking a long-idle peer session without `WAKE-OK:` and a reason |

Those rows are examples, not the set: the full list is the `hook` rows of `install/options.tsv`.
The CLI's `status` command ([Change the setup later](install.md#change-the-setup-later)) prints each group's
state and, on the flat route, how many of its hooks are wired (on the plugin route it prints
`wired by plugin (N hooks)` instead, because the plugin wires its hooks outside `settings.json`).

How the hooks get wired depends on the install route:

- **Plugin:** `hooks/hooks.json`, generated from `install/options.tsv`, wires every hook. The plugin
  options decide which of them act.
- **Flat:** `install-flat.sh` wires the core hooks plus the hooks of the groups you picked into
  `settings.json`, through one ledger-backed mechanism: `.state/integrations.json` records what the
  installer owns, re-runs converge on the target state, FOREIGN (hand-edited) rows are warned about
  and never touched, and each wired row's selfcheck runs at install ("wired" and "fires" are
  different claims). `/agent-tiers:doctor` step 4f prints which rows are wired.

> [!IMPORTANT]
> Guards default **OFF**: a plain install is the `core` level. A misfiring security hook blocks
> legitimate work, so turning a group on is a deliberate choice, not a gap nobody noticed. But every
> guard exists because of a real caught failure, so off should mean "you chose that", not "nobody
> got around to it".

## Levels and groups<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

A level is a named set of groups. The flat install asks for one; on the plugin route you start at
`core` and pick one with `/agent-tiers:setup`. Choosing a level sets every group: on if the level
includes it, off if it does not, replacing earlier group choices (`disabled_hooks` is kept).

| Level | Groups | What it adds |
|---|---|---|
| `core` | none | Session handoff and housekeeping only. No guards. |
| `recommended` | `safety`, `shell_footguns`, `commit_review` | Guards against destructive commands, silent shell footguns, and unreviewed or unhygienic commits. |
| `full` | every group | Every guard, including delegation, memory, attention, multi-session and planning rules. |

Each group is one option, `group_<name>` (for example `group_safety`), true or false.

| Group | Guards against |
|---|---|
| `safety` | destructive commands, risky writes, git actions that lose work, agent commands that reach other machines |
| `shell_footguns` | shell commands that fail quietly, such as a recursive `grep` skipping binary files |
| `commit_review` | unreviewed commits, commit hygiene problems, private text leaking into a commit |
| `delegation` | sub-agent spawns and external agent calls that break the tier rules |
| `memory` | memory and note writes with unsafe content or no provenance |
| `attention` | a person missing a question, a permission prompt or an advisory |
| `multi_session` | parallel sessions on one machine clobbering each other |
| `planning` | plans and compactions that skip their reads or lose loose ends |

Both tables follow `install/options.tsv` (its `level`, `option` and `hook` rows): the CLI and
`/agent-tiers:setup` read it, and the plugin manifests are generated from it.

## When reach-guard denies<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

The CLI never writes reach-guard's allowlist. When a deny can be made permanent, reach-guard prints a
`POLICY CHANGE` line, a `! printf ... >> <file>` command that you run yourself to add the row. An agent
running the same line is denied. Detail: [docs/after-install.md](after-install.md#reach-guard-allowlist).

## How this surface is maintained<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

Three things about how this surface is maintained, since you are trusting it with hook access:
every guard ships a fixture-based selfcheck, and CI runs the whole suite under sh, dash and bash
plus a macOS leg, with a SKIP scored as a failure. Network posture, in plain words: the hooks and
guards make zero outbound calls - every deny happens locally and nothing they catch is
transmitted anywhere. The only networked pieces are ones you invoke yourself: `git`, the share
tool pushing to your own remotes, and the two opt-in companions. A selfcontainment preflight blocks shipped
scripts that would arrive broken in a recipient's copy (an unreachable script, a dependency that
only resolves on the maintainer's machine). And each guard's header comment names the real
incident that motivated it - the source carries the story, not a hypothetical threat model.

The public repo does not carry every file the maintainer's copy has. Some maintainer-only scripts
(the personal leak scanner and the guards built on it, retro and companion-repo tooling) and repo
plumbing files are marked `export-ignore` in `.gitattributes` and left out of the public tree, so a
reference to one of them in a doc or comment may not resolve there.

## Guards in action<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a>

Real captured output, not mockups, first published in the README's
[See it work](../README.md#see-it-work) section next to its force-push example. The guards are
plain scripts reading the hook's JSON from stdin, so every refusal below is reproducible by piping
a payload the same way that example does.

**The silent-grep footgun** (`grep-footgun-guard`) denies with the fix in the message:

> Recursive GNU grep without -a/--text silently skips files it deems binary (NUL/invalid bytes;
> plain CJK is fine) - documented CLAUDE.md footgun. Re-run with 'rg' (preferred) or add '-a' to grep.

**The lost-exit-code strand** (`long-run-guard`) denies a long check/build/commit that is piped,
backgrounded, under-timed, or polled in a while/until+sleep loop:

> deny: piping or redirecting a long check/build/commit's own output discards its exit code. run
> it foreground, no pipe, timeout: 900000 on the tool call, and read the exit code directly.

It also denies a stranded poll loop (rule e), whatever it waits on: a while/until + sleep loop that
watches a sub-agent's or background command's output file is denied even with a bound (the harness
already sends a completion notification, so end the turn and wait), and any other sleep loop needs a
`timeout` wrapper, a counter/deadline test or a `read` condition; the deny points at the Monitor tool for outside waits.

**The blanket git add / shared stash** (`git-add-stash-guard`) denies `git add -A`/`--all`/`.`/`:/`/
bare `-u`, and every `git stash` subcommand but `list`/`show` - a stash is one ref shared by every
worktree of the repo, so one session's stash can take another's uncommitted work.

**The hand-rolled worktree recipe** (`worktree-guard`) denies a `git worktree add` without
`--detach`, or any `git worktree remove`, with the same pattern in the message: use
`scripts/worktree.sh up <name>`/`down <name>` instead, or add `--detach` for a throwaway review
target.

**Doctrine firing mid-session** - rules carry stable ids (`SC-*`), and hooks quote them at the
moment they apply, in the agent's own transcript. This one fired at the session that was building
the kit's own publish gate, the instant it wrote the file:

> agent-tiers SC-5.2: you have now AUTHORED a non-trivial trust-class artifact this session.
> Authorship and the pre-ship verdict are separate roles - you are disqualified as this diff's
> fresh eyes [...] Note the argument that will occur to you and is wrong: 'another review
> pass is low marginal value here' is a statement about the diff you have ALREADY reviewed, never
> about the diff you just authored. This is a record, not a block - deciding not to review is a
> decision worth stating out loud rather than making silently.

The independent review it demanded happened, and found real defects the author had missed.

**And the guards guarded this section's own making**: capturing a secret-write refusal for the
README was itself hard-denied by the authoring session's live guard - a fixture `sk-ant-` key on a
command line looks exactly like a real one, and the guard does not care that you meant well. The
specimen you don't see here is the system working. `sh scripts/security-gate.selfcheck.sh` runs
the full fixture suite instead; it ends `ALL PASS`.

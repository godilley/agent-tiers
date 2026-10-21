<a name="top"></a>
<h1 align="center">Hooks and guards</h1>

<p align="center"><i>Every kit hook by group: what it watches, and what it does when it fires</i></p>

<div align="center">

| <img src="assets/spacer.svg" width="21" height="1">[**README**](../README.md)<img src="assets/spacer.svg" width="21" height="1"> | <img src="assets/spacer.svg" width="28" height="1">[**Install**](install.md)<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="29" height="1">**Hooks**<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="10" height="1">[**What ships**](what-ships.md)<img src="assets/spacer.svg" width="10" height="1"> | <img src="assets/spacer.svg" width="13" height="1">[**Extending**](extending.md)<img src="assets/spacer.svg" width="14" height="1"> | <img src="assets/spacer.svg" width="20" height="1">[**Glossary**](glossary.md)<img src="assets/spacer.svg" width="20" height="1"> |
|:-:|:-:|:-:|:-:|:-:|:-:|

</div>

<hr>

> [!NOTE]
> The full hook list, one table per group. Ground truth is the 44 `hook` rows of `install/options.tsv`; if a guard blocked you, its reason says what to do next.

<a name="levels-and-groups"></a>

| Group<br><img src="assets/spacer.svg" width="200" height="1"> | What it guards against<br><img src="assets/spacer.svg" width="330" height="1"> | Level<br><img src="assets/spacer.svg" width="110" height="1"> |
|---|---|---|
| 🟢 [**core**](#core) | **Session housekeeping, no guards**<br><i>&rsaquo; Handoff, advisories, guard counts.</i> | core |
| 🔒 [**safety**](#safety) | **Destructive and risky acts**<br><i>&rsaquo; Force-push, secrets, remote reach.</i> | recommended |
| 🐚 [**shell_footguns**](#shell-footguns) | **Commands that fail quietly**<br><i>&rsaquo; grep, pgrep -f, piped checks.</i> | recommended |
| ✅ [**commit_review**](#commit-review) | **Unreviewed or unclean commits**<br><i>&rsaquo; Review ask, hygiene, private paths.</i> | recommended |
| 🧭 [**delegation**](#delegation) | **Helper spawns that break the tier rules**<br><i>&rsaquo; Model, framing, early returns.</i> | full |
| 🧠 [**memory**](#memory) | **Memory writes with no check**<br><i>&rsaquo; Coverage check, lint, authorship.</i> | full |
| 🔔 [**attention**](#attention) | **A person missing something**<br><i>&rsaquo; Notifications, reply tags, questions.</i> | full |
| 👥 [**multi_session**](#multi-session) | **Parallel sessions colliding**<br><i>&rsaquo; Peer notes, small literal rules.</i> | full |
| 📋 [**planning**](#planning) | **Plans that skip their reads**<br><i>&rsaquo; Unread files, saved plans, compact.</i> | full |

> [!TIP]
> One hook off: **`agent-tiers configure --set disabled_hooks=<id>,<id>`** (it replaces the whole list); a group with `group_<name>=false`, the whole kit with `enabled=false`. See [Turning things off](levels.md#turning-things-off).

---

<a name="core"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🟢 core 🟢<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Act at every level. Nothing here blocks.</sub></p>

| Hook<br><img src="assets/spacer.svg" width="200" height="1"> | What it does |
|---|---|
| `resume-inject` | At session start, compact, resume and clear: re-injects `RESUME_SESSION.md`, the version stamp, the model band line and the start-up advisories. Only adds context. |
| `codex-home-isolate` | At session start: gives the session its own `CODEX_HOME`, so parallel Codex runs do not share state or resume the wrong one. Only sets the environment. |
| `ledger-check` | At session start: reads the project's outstanding-work ledger and reports fired triggers, DONE lines that prove nothing, and a ledger past its cap. Only notes. |
| `guard-summary` | At session end: one line counting this session's guard blocks from `.state/guards.log`, the durable record. Only records. |

---

<a name="safety"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🔒 safety 🔒<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Destructive commands, risky writes, git actions that lose work, <b>reach to other machines</b>.</sub></p>

| Hook<br><img src="assets/spacer.svg" width="254" height="1"> | What it does |
|---|---|
| `worktree-guard` | Denies `git worktree add` without `--detach` and any removal of a worktree under `.claude/worktrees/`; the reason names `worktree.sh up` and `down`. |
| `git-add-stash-guard` | Denies `git add -A`, `--all`, `.`, `:/` or bare `-u`, and every `git stash` subcommand except `list` and `show`. |
| `dangerous-actions-blocker` | Denies force-push to main or master, `DROP`/`TRUNCATE DATABASE`, `dd`, `mkfs`, package publishes, a secret on the command line, and writes to protected file names. |
| `security-gate` | Denies a write whose content carries a secret or an injection-prone pattern: every file type, and the literal payload of a Bash write. |
| `reach-guard` | A command that reaches another machine or a logged-in account (`ssh`, remote copies, cloud CLIs, `gh api`, browser tools): asks for a read-only one, denies a changing one and hands it back for you to run. Also denies writes to its own data and off switches. |
| `reach-guard-grant` | After a tool call ran: turns an approved read-only ask into a session grant, and records which page a browser tab shows. Only records. |

---

<a name="shell-footguns"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🐚 shell_footguns 🐚<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Shell commands that <b>fail quietly</b> or compete with you for the machine.</sub></p>

| Hook<br><img src="assets/spacer.svg" width="200" height="1"> | What it does |
|---|---|
| `grep-footgun-guard` | Denies recursive GNU `grep` without `-a`, which skips files it deems binary and says nothing; points at `rg`. |
| `pgrep-footgun-guard` | Denies `pgrep -f`, `pkill -f` and `--full`, which tend to match the shell that runs them. |
| `contention-guard` | Denies a loop running an archive or decompile tool over a glob, and a recursive search rooted at `/` or the home directory. One deny per target per session: the identical retry passes, and so does a command run under `nice` or `ionice`. |
| `long-run-guard` | Denies a long check, build or `git commit` that is piped, backgrounded or wrapped in a sleep loop, or that runs with no tool timeout or one under 600000 ms (for a commit, only when the repo has a pre-commit hook). Also denies, for any command, a sleep loop with no bound or one that polls a harness output file (rule e). |

---

<a name="commit-review"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">✅ commit_review ✅<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Unreviewed commits, hygiene problems, <b>private text leaking into a commit</b>.</sub></p>

| Hook<br><img src="assets/spacer.svg" width="282" height="1"> | What it does |
|---|---|
| `hygiene-commit-guard` | Denies a commit whose diff or message carries em or en dashes, curly quotes, NBSP, ZWSP or the ellipsis glyph. |
| `vcs-commit-guard` | Denies a commit that includes a path the repo's `vcs_policy` marks `ignore-*`; asks only when the command carries a `[vcs-exception:...]` marker. |
| `sc52a-write-disclosure-guard` | Denies a `sed -i` or `tee` write to a tracked file unless the reason is disclosed. |
| `review-gate-guard` | Asks, once per session per repo, at a commit, push or PR when the session has no reviewer, advisor or codex-read spawn yet. With `review_gate: push` a commit passes and only a push or PR asks. |
| `kit-leak-guard` | At a commit in the kit's own repo: denies a private-vocabulary, path or hostname hit; asks only when the command carries a `[leak-exception:...]` marker. A secret-shaped hit always denies. Maintainer-only: `export-ignore` in `.gitattributes`, so it is not in the public tree. |
| `numeric-claim-ledger` | After a Bash call that derives a number (a sum, ratio or percent over parsed text): records it per session. Only records; the model sees nothing. |

---

<a name="delegation"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🧭 delegation 🧭<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Helper spawns and external agent calls that <b>break the tier rules</b>.</sub></p>

| Hook<br><img src="assets/spacer.svg" width="244" height="1"> | What it does |
|---|---|
| `codex-guard` | Denies bare `codex`; the reason routes it through `scripts/codex-run.sh` and its secrets scan. |
| `framing-guard` | Logs a helper brief that names the kit's own rule ids. Never denies. |
| `task-spawn-guard` | Denies an Explore helper with no model set; a review brief that labels which of its checks is a planted test; an opus worker with no stated reason; a brief that asks a helper to write a report file the host refuses to helpers (`REPORT*.md`, `SUMMARY*.md` and similar).<br>A sublead spawn without its `[sublead-approved:]` tag asks you; a helper spawning a sublead is denied. |
| `agent-selfdef-guard` | Denies a helper editing its own agent definition file. |
| `subagent-bg-return-guard` | When a helper stops: blocks its return while a background shell it started is still running. |
| `oos-disposition-guard` | At the end of a main-session turn: sends it back while a helper's numbered `OOS-<n>` items have no disposition line. Native CLI only. |

---

<a name="memory"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🧠 memory 🧠<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Memory and note writes with unsafe content or no provenance.</sub></p>

| Hook<br><img src="assets/spacer.svg" width="263" height="1"> | What it does |
|---|---|
| `authorship-record` | After each edit: records what the session authored, and notes once when it first authors a non-trivial trust-class artifact (the SC-5.2 line under [Guards in action](#guards-in-action)). Only records and notes. |
| `memory-content-lint` | After a memory-file write: notes a commit sha, a derivable count, a PR number, an attributed quote, a line copied from `RESUME_SESSION.md`, or repo state a git command answers. Any other `.md` write gets only that last check. Only notes. |
| `memory-write-gate` | Denies a new memory file, or a new fact in one, until a coverage check and a question to you come first. |
| `portable-citation-advisory` | After a write to a skill or agent definition: notes any cited path that is untracked or git-ignored, which no recipient can open. Only notes. |

---

<a name="attention"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🔔 attention 🔔<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>A person missing <b>a question, a permission prompt or an advisory</b>.</sub></p>

| Hook<br><img src="assets/spacer.svg" width="200" height="1"> | What it does |
|---|---|
| `unattended-guard` | In unattended mode: denies plan mode and a question box with an instruction the agent can act on. Silent otherwise. |
| `advisory-ack-guard` | At the end of a turn: sends it back when a session-start advisory that needs saying to you was not said. |
| `notify` | On a permission prompt: a desktop notification naming the session. |
| `notify-stop` | At the end of a turn: the same notification when the reply's tag says your input is wanted. |
| `notify-tag-guard` | At the end of a turn: sends it back until its last line carries an `operator:` tag saying whether your input is wanted. Native CLI only. |
| `handback-tag-guard` | At the end of a turn: sends it back once when the reply hands you a `!` command with no `operator:run` tag above it. Native CLI only. |
| `ask-gate` | Denies a question box unless a Stop hook has just sent the turn back, so the context reached you first. Native CLI only. |
| `notify-tag-strip` | On screen only: replaces the `operator:` tag line with a coloured badge. Changes the display, nothing else. |

---

<a name="multi-session"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">👥 multi_session 👥<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Parallel sessions on one machine <b>clobbering each other</b>.</sub></p>

| Hook<br><img src="assets/spacer.svg" width="200" height="1"> | What it does |
|---|---|
| `peer-guard` | Notes, once per change, another live session in the same repo. Denies a session's first edit in a different repo, once per session per repo (read its docs, then retry), or asks when a live peer is already working there. Linux only (reads `/proc`); fails open elsewhere. |
| `simple-rules-guard` | Six small literal rules, each a deny: `codex resume --last`, `sudo archlinux-java set`, a `main` branch in your own repos, a question box with no `(Recommended)` default, a `SendMessage` with neither `NOOP-IF-DONE` nor `RESUME-OK`, and waking a long-idle peer without `WAKE-OK:`. |

---

<a name="planning"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">📋 planning 📋<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Plans that skip their reads, <b>approved plans not saved</b>, a compact ahead of the handoff.</sub></p>

| Hook<br><img src="assets/spacer.svg" width="200" height="1"> | What it does |
|---|---|
| `demo-css-guard` | Denies a stylesheet write that pairs `!important` with a demo-only hook (a red outline, `outline-offset`, a `[data-...]` selector). |
| `plan-graduate-nudge` | After a plan is approved: nudges to save it in the project's notes dir. Only notes. |
| `read-basis-guard` | Blocks leaving plan mode while the plan names a tracked source file never read this session, until the plan declares it. |
| `precompact-guard` | Blocks a manual `/compact` while the session authored something after `RESUME_SESSION.md` was last touched. Needs `authorship-record` (memory group); an automatic compact always passes. |

---

<a name="how-hooks-are-wired"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🔌 How hooks are wired 🔌<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Levels pick the groups; the kit gate decides whether a wired hook acts.</sub></p>

The level table (which groups each level turns on) is on [Levels](levels.md).

> [!IMPORTANT]
> Guards default **OFF**: a plain install is the `core` level. A misfiring guard blocks legitimate work, so turning a group on is a deliberate choice. Every guard exists because of a real caught failure, so off should mean you chose it, not that nobody got round to it.

#### The kit gate
<kbd>Every hook</kbd> asks `scripts/kit-gate.sh` before it does anything, so switching a group off needs no rewiring.<br>
<kbd>It stands down</kbd> when `AGENT_TIERS_OFF=1`, when the hook has an off marker in `.state/off/`, when `enabled` is false, when its group is off, or when its id is in `disabled_hooks`.<br>
<kbd>A level</kbd> sets every `group_<name>` option: on if the level includes the group, off if not, replacing earlier group choices. `disabled_hooks` is kept.

#### By install route
<kbd>Plugin</kbd> `hooks/hooks.json`, generated from `install/options.tsv`, wires every hook; the plugin options decide which act.<br>
<kbd>Flat</kbd> `install-flat.sh` wires the core hooks into `settings.json`; a group's hooks are wired when you turn the group on (or with `install-flat.sh --with-<id>`).<br>
<kbd>Ledger</kbd> `.state/integrations.json` records what the installer owns. Re-runs converge on the target state; a hand-edited FOREIGN row is warned about and never touched.<br>
<kbd>Proof</kbd> each wired row's selfcheck runs at install: "wired" and "fires" are different claims.

#### Checking what is wired
<kbd>status</kbd> the CLI's `status` command prints each group's state; on the flat route, how many of its hooks are wired; on the plugin route, `wired by plugin (N hooks)`, because the plugin wires outside `settings.json`.<br>
<kbd>doctor</kbd> `/agent-tiers:doctor` step 4f prints which rows are wired.<br>
<kbd>Removing</kbd> the whole kit: [Remove](install.md#remove).

---

<a name="when-reach-guard-denies"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🚧 When reach-guard denies 🚧<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>The CLI never writes reach-guard's allowlist. You do.</sub></p>

<kbd>One-off</kbd> a deny hands the exact command back as `RUN (one-off, you run it): ! <command>`.<br>
<kbd>Permanent</kbd> when the result can be allowlisted, the text ends with a line you run yourself to add the row:

```
POLICY CHANGE (persists, you run it): ! printf '<group>\t<target>\t<read|all>\n' >> ~/.claude/reach-guard/allow.tsv
```

<kbd>&lt;group&gt;</kbd> a reach-guard group from its class table, `data/reach-classes.tsv` (`remote_shell`, `cloud`, `gh_api`, ...), not a hook group.<br>
<kbd>An agent</kbd> running that same line is denied: the allowlist is reach-guard's own protected data.<br>
<kbd>Detail</kbd> [Reach-guard allowlist](extending.md#reach-guard-allowlist).

---

<a name="how-this-surface-is-maintained"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🔧 How this surface is maintained 🔧<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>You are trusting it with hook access, so here is how it is checked.</sub></p>

<kbd>Selfchecks</kbd> every guard ships a fixture-based selfcheck.<br>
<kbd>CI</kbd> runs the whole suite under sh, dash and bash, plus a macOS leg; a SKIP line counts as a failure (`scripts/selfcheck-all.sh`).<br>
<kbd>Selfcontainment</kbd> `scripts/selfcontainment-check.sh` blocks a shipped script that would arrive broken in a recipient's copy: unreachable, or depending on something only the maintainer's machine has.<br>
<kbd>Doc lint</kbd> `scripts/docs-lint.sh` (links, markdown traps) and `scripts/lint-doctrine.sh` (rule ids, version stamps).<br>
<kbd>Provenance</kbd> each guard's header comment names the real incident that motivated it: the source carries the story, not a hypothetical threat model.

> [!WARNING]
> The public repo does not carry every file the maintainer's copy has. Maintainer-only scripts (the leak scanner and the guard built on it, publish and merge gates, retro tooling, companion-repo tooling such as `maint2-arrival-guard`) are `export-ignore` in `.gitattributes`, so a reference to one in a doc or comment may not resolve there.

---

<a name="network-posture"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">📡 Network posture 📡<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Zero outbound calls from the hooks and guards.</sub></p>

<kbd>Hooks</kbd> every deny happens locally; nothing a guard catches is transmitted anywhere.<br>
<kbd>Networked</kbd> only the pieces you invoke yourself: `git`, the share tool pushing to your own remotes, and the two opt-in companions, the agentsview session ledger and the Codex cross-lab handoff.

---

<a name="guards-in-action"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🎬 Guards in action 🎬<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Each reason line is the script's own text, trimmed with [...].</sub></p>

The guards are plain scripts reading the hook's JSON on stdin, so every refusal here is reproducible by piping a payload the way [See it work](../README.md#see-it-work) does. The command lines below are examples; the reason lines are verbatim.

#### Shell and git footguns
`grep-footgun-guard`:

```diff
- grep -r "pattern" src/
  Recursive GNU grep without -a/--text silently skips files it deems binary [...] Re-run with 'rg' (preferred) or add '-a' to grep.
+ rg "pattern" src/
```

`long-run-guard`, a piped check:

```diff
- pnpm check | tail -20
  deny: a pipe discards the exit code; run it foreground and read $?. run it foreground, no pipe, timeout: 900000 on the tool call [...]
+ pnpm check
```

`long-run-guard` rule e, a sleep loop with no bound, whatever it waits on:

```diff
- until curl -s localhost:8080; do sleep 5; done
  deny: a while/until loop with sleep and no bound never ends [...] prefer the Monitor tool. Fallback, a bounded loop: wrap it in timeout [...]
+ timeout 600 sh -c 'until curl -s localhost:8080; do sleep 5; done'
```

A loop that polls a helper's or background command's output file is denied even with a bound: `[...] The harness sends a completion notification for every subagent and run_in_background command, so end the turn and wait for it; do not poll, bounded or not.`

`git-add-stash-guard`:

```diff
- git add -A
  deny: git add -A/--all/./:/*, or bare -u with no other pathspec, stages every matching change in the worktree [...]
+ git add docs/hooks.md
```

A stash gets the same deny: `deny: git stash is one ref shared by every worktree of this repo - a stash here can pop or clear another parallel session's uncommitted work [...]`

`worktree-guard`:

```diff
- git worktree add .claude/worktrees/feature -b feature
  git worktree add without --detach/-d is denied - the hand-rolled recipe drifted eleven times before worktree.sh existed: use [...]/worktree.sh up <name> [...]
+ sh scripts/worktree.sh up feature
```

#### Doctrine firing mid-session
Rules carry stable ids (`SC-*`), and hooks quote them at the moment they apply. `authorship-record` added this line to the context of a session building the kit's own publish gate, the instant it wrote the file:

> agent-tiers SC-5.2: you have now AUTHORED a non-trivial trust-class artifact this session [...]. Authorship and the pre-ship verdict are separate roles - you are disqualified as this diff's fresh eyes, at any band. [...] Note the argument that will occur to you and is wrong: 'another review pass is low marginal value here' is a statement about the diff you have ALREADY reviewed, never about the diff you just authored. This is a record, not a block [...]

The independent review it demanded happened, and found real defects the author had missed.

#### The guard that guarded its own write-up
Capturing a secret-write refusal for the README was itself denied by the authoring session's live guard: a fixture `sk-ant-` key on a command line looks exactly like a real one. The specimen you do not see here is the system working. `sh scripts/security-gate.selfcheck.sh` runs the full fixture suite instead; it ends `ALL PASS`.

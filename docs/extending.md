<a name="top"></a>
<h1 align="center">Extending</h1>

<p align="center"><i>Fit the kit to a project, add companions, keep private notes out of history, run a second account, and see how the kit keeps itself current</i></p>

<div align="center">

| <img src="assets/spacer.svg" width="21" height="1">[**README**](../README.md)<img src="assets/spacer.svg" width="21" height="1"> | <img src="assets/spacer.svg" width="28" height="1">[**Install**](install.md)<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="29" height="1">[**Hooks**](hooks.md)<img src="assets/spacer.svg" width="29" height="1"> | <img src="assets/spacer.svg" width="10" height="1">[**What ships**](what-ships.md)<img src="assets/spacer.svg" width="10" height="1"> | <img src="assets/spacer.svg" width="13" height="1">**Extending**<img src="assets/spacer.svg" width="14" height="1"> | <img src="assets/spacer.svg" width="20" height="1">[**Glossary**](glossary.md)<img src="assets/spacer.svg" width="20" height="1"> |
|:-:|:-:|:-:|:-:|:-:|:-:|

</div>

<hr>

> [!NOTE]
> What you can build on an installed kit, and why it works the way it does. What the installer wrote is on [Install](install.md#after-install); terms are in the [Glossary](glossary.md).

| Section<br><img src="assets/spacer.svg" width="183" height="1"> | What it covers<br><img src="assets/spacer.svg" width="300" height="1"> | As it looks<br><img src="assets/spacer.svg" width="1" height="1"> |
|---|---|---|
| 🧱 [**Three layers**](#three-layers) | **Kit agents, brief, task agents**<br><i>&rsaquo; Extend agents without copying them.</i> | `skills: [tier-project-brief]`<br><sub><i>every kit agent's frontmatter, in one-line form</i></sub> |
| 🤝 [**Companions**](#companions) | **Optional tools beside the kit**<br><i>&rsaquo; Ledger, cross-lab review, plugins.</i> | `claude mcp add --scope user agentsview [...]`<br><sub><i>registers agentsview for every project</i></sub> |
| 📓 [**Private notes**](#private-notes) | **Planning docs outside tracked history**<br><i>&rsaquo; A side ref, never merged.</i> | `/agent-tiers:notes sync`<br><sub><i>save, then push when a remote is set</i></sub> |
| 👥 [**Second account**](#second-claude-account) | **One checkout, two profiles**<br><i>&rsaquo; What each profile keeps.</i> | `CLAUDE_CONFIG_DIR=~/.claude-work sh [...] install`<br><sub><i>the flat install, into a second profile</i></sub> |
| 🚧 [**Allowlist**](#reach-guard-allowlist) | **Make a reach-guard answer stick**<br><i>&rsaquo; You edit it; agents cannot.</i> | `POLICY CHANGE (persists, you run it): ! [...]`<br><sub><i>the last line of a reach-guard prompt</i></sub> |
| 🔁 [**Lifecycle**](#lifecycle) | **Stamps, doctor, gc**<br><i>&rsaquo; How the kit stays current.</i> | `agent-tiers: MEMORY.md thresholds breached:[...]`<br><sub><i>a session-start nudge</i></sub> |
| 🔍 [**Why a probe**](#why-a-probe) | **Hosts differ, so init checks**<br><i>&rsaquo; Evidence first, then a record.</i> | `printf '%s\n' "${CLAUDE_CODE_ENTRYPOINT:-}"`<br><sub><i>init's first check: cli skips the probe</i></sub> |

> [!TIP]
> The **project brief** is one skill per repo, `.claude/skills/tier-project-brief/SKILL.md`, that every kit agent loads: your build, test and verify commands and the repo's landmines.

---

<a name="three-layers"></a>
<a name="how-a-project-extends-the-tiers-3-layers"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🧱 Three layers 🧱<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>The kit's agents stay generic; <b>a project adds to them, never copies them</b>.</sub></p>

Claude Code has no `extends` for agents, so the seam (the one place a project plugs in) is a skill: every kit agent preloads `tier-project-brief` through its `skills:` frontmatter, and a project fills that skill in.

| Layer<br><img src="assets/spacer.svg" width="166" height="1"> | Where | What it holds |
|---|---|---|
| **L1 kit agents** | the kit's `agents/*.md` | The generic helpers (`worker`, `advisor`, `reviewer`, `boss`, `sublead`, `codex-read`, `codex-write`). Each lists `tier-project-brief` under `skills:`. |
| **L2 project brief** | `.claude/skills/tier-project-brief/SKILL.md` | One per repo: build, test and verify commands, and landmines. Absent: the helpers run generic, no error. Keep it to about 1-2k tokens, since it rides on every spawn. |
| **L3 task agents** | `.claude/agents/<prefix>-*.md` | New agents for this repo's repeated procedures. They load the same brief, so the repo's facts live in one place. |

> [!WARNING]
> **Always prefix an L3 agent** (`repo-gates`, not `worker`). A project agent with a kit agent's name replaces it in that repo, with no merge.

#### Who edits what

<kbd>Learnings</kbd> the `worker` keeps its own notes through `memory: local`, in the git-ignored `.claude/agent-memory-local/`.<br>
<kbd>Contracts</kbd> no agent edits its own definition or the brief. It names the change and why in its report, and the main session applies it after asking you.<br>
<kbd>Set up</kbd> `/agent-tiers:init` writes the brief and offers L3 agents ([In each project](install.md#per-project-artifacts)).<br>
<kbd>Check</kbd> `/agent-tiers:doctor` confirms that `worker`, `advisor`, `reviewer`, `boss` and `sublead` list the brief, and that `.claude/agent-memory-local/` is ignored.

---

<a name="companions"></a>
<a name="companions-optional-power-ups"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🤝 Companions 🤝<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>The kit works alone. <b>Each of these is opt-in</b>, and the kit runs the same without it.</sub></p>

#### Kit companions

<kbd>agentsview</kbd> [agentsview](https://github.com/kenn-io/agentsview) (MIT, a user-scope MCP server) is a session ledger across every agent run: recent runs, a search over all sessions, and what a helper actually did (tools, timings, cost) instead of what its summary says. The kit writes nothing for it; setup is under [Extras](install.md#extras).<br>
<kbd>Codex</kbd> a model from a second lab, for the write path and for dual review: a fresh opus pass and a Codex pass on the same diff, merged by the main session. It needs the `codex` CLI installed and signed in. Writing and reviewing are two separate consents, each asked once per session at its first real use. The rules are in [the XLAB card](../skills/agent-tiers/cards/XLAB.md), one of the kit's short rule files under `skills/agent-tiers/cards/`.

#### Third-party plugins

Not part of the kit, but recommended beside it.

<kbd>caveman</kbd> [caveman](https://github.com/JuliusBrussee/caveman) compresses agent replies: the full technical content with the filler cut, so every turn costs less, not just the big calls.<br>
<kbd>ponytail</kbd> [ponytail](https://github.com/DietrichGebert/ponytail) makes the agent try the laziest solution that works before writing new code. The kit routes work to the cheapest capable model; ponytail keeps the work itself small.<br>
<kbd>Install</kbd> the kit's marketplace lists both, each pinned to a known upstream commit: `/plugin install caveman@agent-tiers` ([Plugin route](install.md#plugin-route)). Skip one you already have from its own marketplace, or its hooks run twice.

---

<a name="private-notes"></a>
<a name="private-notes-seam"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">📓 Private notes 📓<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Version your planning docs <b>without committing them to any branch</b>.</sub></p>

Private docs in a tracked dir (worse, one shared with an upstream or a team, like `docs/`) get committed onto whatever branch is checked out. With frequent branch switching they bleed across branches, or end up untracked on none. A doc can only bleed from a tracked branch, so the seam keeps private docs off every branch.

#### How it works

<kbd>The dir</kbd> `docs/_local/`, listed in `.git/info/exclude` (git's machine-local ignore). Git will not stage it, and ignored files survive `checkout` and `reset --hard`.<br>
<kbd>The ref</kbd> `local/notes` (stored as `refs/heads/local/notes`) holds `docs/_local/` in its own history and is never merged into a code branch. Push it to a remote for backup, or keep it local.<br>
<kbd>The script</kbd> the kit's `scripts/notes-sync.sh`, one copy for every repo, snapshots the dir onto the ref with git plumbing (`write-tree`, `commit-tree`, `update-ref`, a throwaway index). It never touches HEAD or the index, so it runs from any branch, a dirty tree or mid-merge.<br>
<kbd>Config</kbd> per repo, in `.git/config`: `notes-sync.dir`, `notes-sync.ref`, `notes-sync.push` (`local`, or a remote name).<br>
<kbd>Notes profiles</kbd> unrelated to a Claude Code profile: `--profile <p>` before any subcommand namespaces the keys as `notes-sync.<p>.*`, so one repo can carry several ignored but versioned dirs. A named profile has no dir default: run its `setup --dir <path>` first. Its ref defaults to `local/<p>`.

#### Everyday use

Run the script through `/agent-tiers:notes` (flat route: `/agent-tiers-notes`), which passes its arguments straight through; no argument means `status`.

| Subcommand<br><img src="assets/spacer.svg" width="160" height="1"> | What it does |
|---|---|
| `status` | File count, ref head, remote, push policy. |
| `new <slug>` | Creates `docs/_local/<date>-<slug>.md` with a `STATUS: LIVE` stub. |
| `save [msg]` | Snapshots the dir onto the ref; skips when nothing changed. |
| `push` | Pushes the ref to the configured remote; does nothing when the policy is `local`. |
| `sync [msg]` | `save`, then `push`. |
| `restore` | Writes the ref back into `docs/_local/`, overwriting files of the same name. Fetches from the remote only when the ref is missing locally. For a fresh clone or a recovery. |
| `migrate <path>...` | Moves stray docs into `docs/_local/`, untracks the tracked ones, then saves. |

<kbd>Dated docs</kbd> `new` is the one way to create a dated doc: the script takes the date from the clock (UTC), never from the caller. `--from <path>` seeds it from an existing file and adds a `STATUS: LIVE` line if the file lacks one, which also snapshots a single file such as `RESUME_SESSION.md` with no profile.

#### Set up

<kbd>New project</kbd> `/agent-tiers:notes setup --push local` keeps the ref local, never pushed (the default); `--push <remote>` backs it up to that remote. Setup creates `docs/_local/`, adds the exclude and writes the config; the command also records the policy in `.claude/agent-tiers.local.md` under `vcs_policy.private_notes`, so `/agent-tiers:doctor` can flag drift. `/agent-tiers:init` offers this as its step 6d.<br>
<kbd>Fresh clone</kbd> `.git/config` and the exclude do not travel with a clone: run `setup` again with the same `--push` (adding that remote first if it is not `origin`), then `restore`.

<kbd>Existing project</kbd> to move stray private docs in:

1. Find the private docs in a tracked or shared dir (design notes under `docs/plans/`, a friction log), untracked orphans included.
2. Run `/agent-tiers:notes setup --push <local|remote>`.
3. Run `/agent-tiers:notes migrate docs/plans/2026-*-my-plan.md docs/my-friction-log.md`. It moves them in, stages the removal of any tracked ones, and saves.
4. If some were also tracked on a dedicated feature branch, drop them there too: on that branch, `git rm` them and commit (or rewrite that commit), then `/agent-tiers:notes sync`.
5. Commit the staged removals on your working branch. The shared dir now holds only the upstream's or team's docs.

> [!WARNING]
> **A pre-push identity hook can refuse `push`.** If the repo's pre-push hook enforces an author identity, push with the identity that remote expects, or keep the policy `local`.

---

<a name="second-claude-account"></a>
<a name="second-claude-account-claude_config_dir"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">👥 Second account 👥<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>One variable gives each account its own profile; <b>one kit checkout serves both</b>.</sub></p>

Claude Code treats `CLAUDE_CONFIG_DIR` as its whole config root. With it set, Claude Code builds `.claude.json`, `projects/` and `sessions/` there and starts logged out, which is what lets two accounts run side by side.

```bash
CLAUDE_CONFIG_DIR=~/.claude-work claude
CLAUDE_CONFIG_DIR=~/.claude-work sh ~/.claude/agent-tiers/scripts/agent-tiers install
```

<kbd>First line</kbd> starts Claude Code in the second profile; log in there.<br>
<kbd>Second line</kbd> the flat install into that profile, from the checkout you already have. Skills, agents, commands and `settings.json` land in the profile, the links absolute and pointing back at the one checkout, with the profile's own integrations ledger. Every later `configure`, `status` or `remove` for that profile needs the same variable.<br>
<kbd>Plugin route</kbd> the plugin's enabled entry and its options live in the profile's `settings.json`, so run the plugin install from a session started with the variable set ([Plugin route](install.md#plugin-route)).<br>
<kbd>Do not copy</kbd> never copy the kit into each profile: keep the one checkout at `~/.claude/agent-tiers/`, which the flat install links every profile to.

#### Shared or per profile

| What<br><img src="assets/spacer.svg" width="299" height="1"> | Shared or per profile |
|---|---|
| `kit-config.md` | Shared: it lives in the kit checkout. |
| Guard log | Shared: the kit checkout's `.state/`. |
| `~/bin/agent-tiers-share` | Shared. Removing one profile deletes it for all: re-run `install-flat.sh` in a profile you keep, with that profile's variable. |
| `settings.json`, links, hook rows | Per profile, the command copies too. |
| Integrations ledger | Per profile: one file each in the kit's `.state/`. |
| reach-guard allowlist | Per profile: `$CLAUDE_CONFIG_DIR/reach-guard/allow.tsv`. |
| Login, sessions, memory | Per profile (Claude Code's own). |

---

<a name="reach-guard-allowlist"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🚧 Reach-guard allowlist 🚧<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Make an answer stick past the session. <b>Only you write the file</b>.</sub></p>

<kbd>What asks</kbd> `reach-guard`, a kit guard hook, asks before an agent drives a browser, runs a remote shell or a cloud CLI, or calls the GitHub API ([Hooks](hooks.md)). A Yes on its prompt lasts at most for the session (a row in this file is what makes it persist): for a browser, that site and level; for a read-only Bash command, that group and target. The prompt says which. Your host's "don't ask again" does not stop it asking.<br>
<kbd>The file</kbd> `~/.claude/reach-guard/allow.tsv`, or `$CLAUDE_CONFIG_DIR/reach-guard/allow.tsv` when that is set. One row per line: group, target, then `read` or `all`, tab-separated.<br>
<kbd>Who writes it</kbd> only you. Agents are denied writing it, the main session included, and the `agent-tiers` CLI never writes it.

#### Add, list, remove

<kbd>Add</kbd> run the line the prompt labels `POLICY CHANGE` yourself, as a `!` command in Claude Code or in a terminal. Its form, placeholders in angle brackets:

```text
POLICY CHANGE (persists, you run it): ! printf '<group>\t<target>\t<read|all>\n' >> ~/.claude/reach-guard/allow.tsv
```

<kbd>Missing dir</kbd> while the directory does not exist, the prompt puts `mkdir -p <dir>;` before the `printf`. With `CLAUDE_CONFIG_DIR` set, the path is that directory's.<br>
<kbd>By hand</kbd> typing the line yourself, write a `%` in the target as `%%` and a `\` as `\\`, since printf reads both in its format. The prompt's own line already does.<br>
<kbd>List</kbd> `agent-tiers reach list` (the kit's `scripts/agent-tiers`) shows the rows. It needs no `jq` and writes nothing.<br>
<kbd>Remove</kbd> delete the row's line from `allow.tsv` in an editor.<br>
<kbd>RUN lines</kbd> a line labelled `RUN (one-off, you run it)` hands one command back for you to run, and changes nothing that persists.

> [!WARNING]
> **`all` lets agents act without asking.** On `remote_shell` it covers any plain remote command on matching hosts; on `cloud` or `gh_api`, that group's act calls (writes, deletes, deploys) against matching targets.

---

<a name="lifecycle"></a>
<a name="lifecycle-how-the-kit-self-manages"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🔁 Lifecycle 🔁<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Stamps catch stale copies; <b>doctor detects, gc fixes after asking</b>.</sub></p>

#### Version stamps

<kbd>Agents</kbd> every agent file carries a `def-version: N` stamp, and the agent quotes `def-v<N>` in its check-in line. The host re-reads agent files only at a later message boundary (seconds in the CLI, up to minutes in some GUIs), so after an edit the agent is pending refresh: trust its behaviour only once a spawn's check-in shows the new number.<br>
<kbd>Rules</kbd> the kit's written rules (its doctrine) carry a version too: `doctrine-v<N>` in `skills/agent-tiers/SKILL.md`, and `card-v<N>` in each short rule file under `skills/agent-tiers/cards/`. A change to what a rule says raises that number; a typo or link fix need not.<br>
<kbd>Checksums</kbd> each stamp also holds a checksum of its file (`c=<sum>-<bytes>`). `scripts/lint-doctrine.sh` recomputes it, so an edit without a version raise shows up; after a deliberate raise, `lint-doctrine.sh --stamp` rewrites the checksums.

#### Doctor and gc

<kbd>Doctor</kbd> `/agent-tiers:doctor` is read-only. Among its checks: every agent's `def-version` stamp, memories citing a file or branch that no longer exists, VCS policy drift, the private-notes seam, and lifecycle sizes against thresholds. It ends with one `gc suggested:` line, or `lifecycle: clean`.<br>
<kbd>Thresholds</kbd> advisory, from `commands/doctor.md`: a memory index over 80 lines, 80 files or 25 KB; `RESUME_SESSION.md` over 70 lines; a brief over 4 KB; an agent's `MEMORY.md` over 150 lines; `docs/plans/` over 500 KB.<br>
<kbd>gc</kbd> `/agent-tiers:gc` is the gated fixer: retire, merge, archive, dedup. It proposes, never deletes without a yes, and never touches your personal `CLAUDE.md`.<br>
<kbd>Nudge</kbd> the session-start hook adds an advisory line when a threshold is breached, one for the memory index and one for the rest. The `MEMORY.md` check runs in every project; the RESUME, brief and plans checks only where a `RESUME_SESSION.md` exists.

#### Policy and promotion

<kbd>VCS policy</kbd> on the flat route, `kit-config.md` in the kit checkout holds your default git handling per artifact class (commit, ignore-shared, ignore-personal); without it, kit defaults apply. `/agent-tiers:init` offers a per-project override and records it in `.claude/agent-tiers.local.md`.<br>
<kbd>Private notes</kbd> planning docs stay out of tracked history: [Private notes](#private-notes).<br>
<kbd>Promote</kbd> a pattern that recurs in a second project is generalised into a kit template or global agent, as the superset of both; a fact true in any repo moves to global memory.

---

<a name="why-a-probe"></a>

<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">🔍 Why a probe 🔍<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>Hosts resolve agent settings differently, <b>so init checks instead of assuming</b>.</sub></p>

How a helper's `model:` and `effort:` frontmatter resolves against the inherited environment differs from host to host. A helper cannot see its own live model, and a greeting, a brief, a launch flag or a panel label does not prove which model ran. So `/agent-tiers:init` measures what it can and records only what the evidence supports.

#### What init does

<kbd>Native CLI</kbd> init first runs `printf '%s\n' "${CLAUDE_CODE_ENTRYPOINT:-}"`. `cli` means the interactive Claude Code CLI, a proven host: init skips the probe and records nothing about the host. `--reprobe` runs it anyway; `--scaffold-only` skips it on any host.<br>
<kbd>Other hosts</kbd> `sdk-cli` (third-party GUI hosts report it too) or any other value runs the probe: `scripts/probe-env.sh` reads the inherited model, any effort pin and the terminal; one `worker` spawn reports its effort; the model comes from the host's own record of that spawn.<br>
<kbd>Panel only</kbd> when only the host's model panel is visible, init asks you what it shows for the worker and records it as panel-reported, with the model unverified. Missing evidence is recorded as `null`, never as a guessed `true` or `false`.<br>
<kbd>Recorded</kbd> in `.claude/agent-tiers.local.md` and an auto-memory copy ([In each project](install.md#per-project-artifacts)). Where a record exists, `/agent-tiers:doctor` compares it to a live probe.

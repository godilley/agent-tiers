# Changelog

One entry per public release (auto-appended by the publish flow, mirrored as [GitHub
release notes](https://github.com/godilley/agent-tiers/releases)); the Bundle entries below
them are the pre-public review-bundle era. The wave-by-wave development history behind each
entry is kept privately by the maintainer.

## v2026.10.21 - 2026-10-21

- Docs overhaul: README and docs pages rebuilt with a shared layout (tab bar, summary tables, section headings). New Glossary, Levels, Work shapes and Plan waves pages. `after-install.md`, `private-notes.md` and `uninstall.md` are merged into Install and Extending.
- New docs tooling: `docs-lint.sh` checks links and markdown traps, and `docs-nav.sh` generates the tab bar. `docs-lint.sh` now runs in CI.
- New `contention-guard` (shell_footguns): denies archive or decompile loops over globs and recursive searches rooted at `/` or home. It fires once per target per session. Commands run under `nice` or `ionice` pass.
- New `handback-tag-guard` (attention): sends a reply back once when it hands you a `!` command without an `operator:run|kind:policy|oneoff` tag. The chat badge now shows "YOU RUN" for each tag kind, and notifications wait while the guard is about to block.
- New `oos-disposition-guard` (delegation): sends a turn back while a sub-agent's numbered `OOS-<n>` items have no disposition line. `inbox` dispositions are appended once to `.state/oos-inbox.log`. All agent definitions (including `sublead`) and templates now end returns with an `Out-of-slice finds` section, and doctrine adds SC-6.5.
- `codex-guard`: a pipe or `;` inside a quoted string is no longer read as a command separator. Command words inside `$(...)` and backticks still deny.
- `reach-guard`: protects `guard-cmdpos.sh` and `hooks.json` from Bash writes, reads inline interpreter code (python, node, perl and others) for protected file names, and catches uppercase class names (`SSH`) and variable command words that expand to a class program. It also handles multi-line quoted arguments and caps parsing at 200 segments.
- Shared shell parsing fixes: heredoc delimiters are read as the whole shell word, comments are handled in command splitting, and a stray 0x1A byte no longer breaks quote stripping.
- Doctrine and delegation: new "Re-tier, same job" rule and scope-matrix row, and an "Answered fork" rule (a settled decision is not re-asked). Fork spawns are costed at the Lead's model. Delegation notes add that sub-agents never carry `RESUME_SESSION.md`.

## v2026.10.18 - 2026-10-18

- Reach-guard now lets edits to a development copy of the kit through. Only the kit that is actually running is protected, and a flagged path is resolved before the check (symlinks, `cd`, relative paths).
- Reach-guard now lets `xargs docker <subcommand>` through when the given words name no remote daemon. Other `xargs` use is still flagged as unsure.
- Reach-guard now accepts a glob command word such as `./*.sh` unless it could match a class program or wrapper name.
- The "persist this allowlist row" command that reach-guard prints now escapes `'`, `%` and `\` in the group and target. This keeps the row written to `allow.tsv` exact. If you type that line by hand, write `%` as `%%` and `\` as `\\`.
- `lint-doctrine` has a new check 12. It flags a `case` pattern written without its leading `(` inside `$( )`, `<( )` or `>( )`, which bash 3.2 (macOS `/bin/sh`) misparses. Run it on its own with `lint-doctrine.sh --case-parens FILE...`. The linter now also exits 2 when an input can't be read.
- `ledger-check` has a new check, L6. It flags a "Forced by:" trigger that says "next" with no anchor (a date, a sha, a version or a typed token). `doc-lifecycle` documents the rule.
- `review-gate-guard` now also asks before `gh pr create` and `gh pr merge`, not only `git commit` and `git push`. A codex-read spawn now counts as a review.
- Docs and guard messages are reworded: the `grep-footgun-guard` and hygiene-commit-guard denials no longer cite a private CLAUDE.md, and the `long-run-guard` example is shortened. The `resume-inject` description is expanded, the worker check-in example now reads `def-v9`, and the `simple-rules-guard` "main" branch denial is clearer.
- The wiring notes in `authorship-record`, `memory-content-lint`, `notify`, `plan-graduate-nudge` and `precompact-guard` now say how each is enabled, by options row and group for the plugin route and by `install-flat.sh` for the flat route.
- The worktree-guard remedy now points at the running kit's own `worktree.sh`. The plan-wave docs describe `STOPPED (a)` as a guard or permission stop.

## v2026.10.16.2 - 2026-10-16

- Added a new "Using the kit" guide (`docs/usage.md`) showing day-to-day work with the kit: why it delegates, common work shapes (long sessions, read-only sweeps, routine changes, design questions, parallel plans, guarded commands), and the rarer Boss and cross-lab Codex paths.
- Covers choosing an install level (`core`, `recommended`, `full`), including what each costs you, plus what changes after install: check-in lines, end-of-reply tags, status line.
- Documents the `plan-wave` workflow step by step: wave table, ready set, lease, one worktree per row, merge order.
- Includes real trimmed captures of guard messages and FORK blocks, a table of guards ranked by how often they fired, and a glossary of the kit's terms.
- The README now links to the guide near the top and in its docs table. Two screenshots of long and parallel sessions are added.

## v2026.10.16 - 2026-10-16

- Adds a `/agent-tiers:setup` command and an `agent-tiers` CLI (`install`, `configure`, `remove`, `status`). You pick a level (`core`, `recommended`, `full`) or individual hook groups, with a dry-run plan and a confirm step before anything is written.
- Guard hooks are now grouped (safety, shell footguns, commit review, delegation, memory, attention, multi-session, planning) and are off by default. A shared kit gate lets you switch off a group, a single hook, or the whole kit through settings, a marker file, or `AGENT_TIERS_OFF=1`. The plugin now wires every shipped hook itself, so plugin installs get the same options.
- New `reach-guard` blocks agents from reaching other machines or logged-in accounts: `ssh`, `scp`/`rsync`, cloud CLIs, `gh api`, and browser MCP servers. It hands the exact command back for you to run yourself, and an allowlist you edit by hand makes approvals permanent.
- Adds a marketplace listing for the kit plus two pinned third-party companions, `caveman` and `ponytail`.
- Adds `review.sh`, a reading aid for install scripts. Adds a status line and sub-agent status line (opt-in), plus environment detection for notification settings.
- Fixes and tweaks:
  - Reviewer now returns its findings inline instead of writing a file.
  - A subagent's blocked commit goes back to the top Lead.
  - Caller detection now uses `agent_id`, so a `--agent` main session isn't treated as a subagent.
  - Hooks no longer hang when run from a terminal.
  - Installer refuses to run alongside an enabled plugin, and `--unwire-only` removes hook rows.
  - Self-checks run in parallel through one shared scorer.
- Docs: the README is split into `docs/` pages (install, hooks, what ships, extending, uninstall). Routing is described per Lead model.

## v2026.10.14.2 - 2026-10-14

- Updated the `actions/checkout` step from v4 to v5 in the self-check workflow, on both the Linux (sh, dash, bash) and macOS jobs.
- CI maintenance only. No change to the shipped code or behavior.

## v2026.10.14 - 2026-10-14

- Guard scripts now trap SIGTERM, so a guard killed at its hook timeout reliably records `end done=0` in the trace log (dash skipped the exit handler on an untrapped TERM).
- Agent-id redaction in content rules now works on BSD/macOS `sed`, which silently ignored `\b`, and it catches several agent ids on one line.
- Shell `case` patterns in several guard and worktree scripts now use the portable parenthesized form.
- `wc` output in the resume-inject threshold checks is now evaluated arithmetically, so numeric comparisons don't break on the padded counts BSD/macOS `wc` prints.
- The selfcheck CI workflow now also runs on pushes to the `publish-staging` branch, alongside `master`.
- Selfcheck tests were extended to cover the TERM trap and multi-id redaction, and made more portable for macOS (resolved temp dirs, `sed -i.bak`, numeric comparisons).

## v2026.10.12.2 - 2026-10-12

Fix CI: lint-doctrine.sh skip lines indented 6+ spaces (pasted command output) when checking script names in doctrine files.

## v2026.10.12 - 2026-10-12

Kit add Sublead tier, plan-wave skill, task-spawn-guard, memory-write-gate, peer-guard, worktree.sh (up/down/list), long-run-guard, notify system (desktop/OSC notifications + Stop-tag gate), ask-gate, pre-commit selfcheck hook, context-map tool, MEMORY policy card.

Security/safety: git-add-stash-guard, demo-css-guard, agent-selfdef-guard, sc52a-write-disclosure-guard, read-basis-guard, simple-rules-guard (6 misc rules), subagent-bg-return-guard, portable-citation-advisory.

Guard behavior change: most form-fixable guards now DENY instead of ASK (guard-ask-deny rule); exception markers moved to trailing comments, not bare words.

review-gate-guard: now gates push/PR too, per-repo `review_gate: commit|push` mode.

Fixes: heredoc-body false matches across many guards (strip body, keep opener); dangerous-actions-blocker adds dynamic protected-branch names; guards.log rotates instead of truncates; resume-inject now restores handoff on startup too, capped to host's 10000-char limit; DEF-DELTA tag retired (unused) in favor of plain-prose flagging.

Docs: agent-tiers doctrine bumped v16→v28, identity-evidence contract added (requested/resolved/observed, no more "model: declared" handwave), ATTEMPTS.md file-ledger retired for in-context tracking, maturity emoji tags retired.

## v2026.08.31.10 - 2026-08-31

- Fixed selfcheck badge styling in README to match sibling badges (dark label and background colors).

## v2026.08.31.9 - 2026-08-31

- Redesigned README badge row with a consistent for-the-badge style, adding Claude Code and POSIX shell badges alongside the existing selfcheck and MIT license badges.

## v2026.08.31.8 - 2026-08-31

- Moved banner images into `docs/assets/` to tidy the repository root.
- Updated the README to reference the new banner image locations.

## v2026.08.31.7 - 2026-08-31

- Fixed symlink resolution in the dangerous-actions blocker on macOS: `readlink -f` can print a correctly resolved path yet exit nonzero, which previously caused both it and the python3 fallback to run and produce garbled output that let the check fail open. Resolution now trusts readlink's output when present, falling back to python3 and then the raw path.
- Fixed a false denial in the hygiene commit guard when committing new binary files (such as PNGs) whose raw bytes happened to contain a scanned glyph sequence: untracked files detected as binary (NUL byte in the first 8KB) are now skipped by the byte scan, matching how tracked binaries were already handled.
- Added a self-check case covering the binary-skip behavior, alongside the existing text-file control.
- Fixed the notes-sync `new` subcommand rejecting every slug on macOS: the lowercase check now uses `[[:upper:]]` instead of an `A-Z` range, which under macOS's default collation also matched lowercase letters.
- Updated the light and dark banner images.

## v2026.08.31.6 - 2026-08-31

- Added CONTRIBUTING.md explaining that this repo is a curated mirror of a private working repo: issues (bug reports, portability failures, doc gaps, guard false positives) are welcome, while pull requests cannot be merged directly and adopted fixes land via the next curated release with changelog credit.
- Documented that security-relevant findings should be reported privately rather than via public issues.

## v2026.08.31.5 - 2026-08-31

- Changelog entries now use versioned headings (e.g. v2026.08.31.4) instead of dates alone.
- Added changelog entries for the three v2026.08.31 public releases, including the initial release of the five-tier sub-agent system.
- Clarified that changelog entries are created per public release by the publish flow and mirrored as GitHub release notes, with older Bundle entries marked as pre-public history.

## v2026.08.31.4 - 2026-08-31

- Reworked the changelog header: entries are now one per public release, auto-appended by the publish flow and mirrored as GitHub release notes, with the older Bundle entries marked as the pre-public review-bundle era.
- Backfilled changelog entries for the three v2026.08.31 public releases, including the initial-release description of the five-tier sub-agent system.
- Added a README section recommending two companion plugins the author uses alongside the kit: caveman (compressed agent communication) and ponytail (bias toward the smallest working solution).

## v2026.08.31.3 - 2026-08-31

- Restructured the README: reordered sections, added back-to-top navigation links, and moved the per-project artifacts, probe rationale, lifecycle, and second-account (CLAUDE_CONFIG_DIR) details into a new docs/after-install.md.
- Moved the uninstall checklist into its own docs/uninstall.md.
- Added three paste-into-Claude prompts under docs/prompts/: an agent-driven install, an independent pre-install review, and a step-by-step uninstall.
- Extracted the share tool's install, review, and safety-wrapper prompts from inline heredocs into template files under templates/prompts/, with an early preflight that fails before any state-changing step if a template is missing or has lost its placeholder; selfcheck coverage added for both failure modes.
- The gc command now snapshots RESUME_SESSION.md verbatim via the notes seam before any extraction, so an over-aggressive trim is recoverable.
- The notes command gained a --profile option, letting one repo carry several ignored-but-versioned notes directories, each with its own dir, ref, and push policy.
- Documentation updates: expanded everyday-use examples in docs/private-notes.md (new, push subcommands, profiles) and clarified guard, install, and hooks wording in the README.
- Refreshed the banner images.

## v2026.08.31.2 - 2026-08-31

- Added a "See it work" link to the README's navigation bar.

## v2026.08.31 - 2026-08-31

Initial public release. Installs a five-tier sub-agent system (Lead, Worker, Advisor, Reviewer,
Boss) into any project, routing each job to the cheapest model that can handle it and reserving
stronger models for per-call escalation. Safety-critical rules are enforced by PreToolUse hook
scripts rather than agent memory; guards are opt-in per install. Self-configures by probing the
local environment, works as a plugin or flattened into `~/.claude` for hosts that ignore plugins,
and needs only POSIX shell, no server.

## Bundle 14 - 2026-08-30
Glossed undefined jargon in every shipped bundle file.

## Bundle 13 - 2026-08-24
Fixed `KIT_DIR` resolution for both bare-name and full-path `PATH` invocation of the share script.

## Bundle 12 - 2026-08-24
Unattended mode now blocks `AskUserQuestion` too; added a guard against footgun `pgrep` usage.

## Bundle 11 - 2026-08-24
Selfcheck no longer inherits `AGENT_TIERS_SHARE_SKIP_CI_GATE` from the environment.

## Bundle 10 - 2026-08-23
Scrubbed private-vocabulary leaks out of guard comments; refreshed the share prompts.

## Bundle 9 - 2026-08-17
Numbers-audit correction for a MAINT-9 count.

## Bundle 8 - 2026-08-16
Doctrine pass: corrected an SC-5.2a claim, re-derived the MAINT-9 count, restored hot-line meaning
lost in an earlier trim (doctrine-v11).

## Bundle 7 - 2026-08-16
Wave D review: provenance record for that wave's CI runs and fixes.

## Bundle 6 - 2026-08-16
Wave B review: provenance record, including a partial-commit incident and its fix.

## Bundle 5 - 2026-08-16
Wave A review: provenance record (CI run ids, review pass, fixes).

## Bundle 4 - 2026-08-16
Guards now deny/decline on `git --git-dir=` / `--work-tree=` spoofing, closing a bypass.

## Bundle 3 - 2026-08-10
Reviewer pass on the prior batch: reverted a skills/agents bake, restored default-form
placeholders.

## Bundle 2 - 2026-08-10
Fixed macOS portability gaps and a missing `jq` guard in selfchecks.

## Bundle 1 - 2026-08-10
First sanitized bundle sent out for review.

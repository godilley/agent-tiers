---
description: Sync this project's private notes (docs/_local/) to a side git ref (local/notes) from any branch, without touching HEAD or the index. The notes dir is git-ignored, so private planning docs can never bleed into a code branch.
argument-hint: "[--profile <p>] [setup [--dir <path>] [--push <remote|local>] | save [msg] | push | sync [msg] | restore | status | migrate <path>... | new <slug> [--from <path>]]"
allowed-tools: Bash
---

You are the **Lead**. Run the kit's private-notes seam for the current project and report the result
terse + scannable. The seam keeps private planning docs in a **git-ignored** `docs/_local/` (via
`.git/info/exclude`) and mirrors them to a side ref (`local/notes`) that is **never merged into any code
branch** - so a scope bleed is structurally impossible. The script works from any branch / dirty tree /
mid-merge (plumbing: `write-tree` + `commit-tree` + `update-ref`, throwaway index).

## Run it

Pass the user's argument straight through (default `status` if none):

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/notes-sync.sh" $ARGUMENTS
```

Subcommands:
- `setup [--push <remote|local>]` - one-time per repo: create `docs/_local/`, add it to
  `.git/info/exclude`, and record `notes-sync.dir/ref/push` in `.git/config`. `push=local` (default) keeps
  the ref on this machine; a remote name (e.g. `private`, `origin`) opts into pushing. After `setup`,
  also record the resolved policy in `.claude/agent-tiers.local.md` under `vcs_policy.private_notes`
  (dir/ref/push) so `/agent-tiers:doctor` can flag drift.
- `save [msg]` - snapshot `docs/_local/**` -> `local/notes` (skips if unchanged).
- `push` - push the ref to the configured remote (no-op when `push=local`).
- `sync [msg]` - `save` then `push`.
- `restore` - extract the ref back into `docs/_local/` (fresh clone / recovery; fetches first if remote).
- `status` - dir file count, ref head, remote, push policy.
- `migrate <path>...` - move stray docs into `docs/_local/` (untracking them if tracked), then `save`.
  Full walkthrough: `${CLAUDE_PLUGIN_ROOT}/docs/private-notes.md` (ships with the kit since
  2026-08-31; if somehow absent, the steps above are the whole procedure).
- `new <slug> [--from <path>]` - create `<date>-<slug>.md` in `docs/_local/` (today's real UTC date,
  computed by the script, never caller-supplied), stub content `STATUS: LIVE` by default, or `--from`'s
  content with `STATUS: LIVE` prepended only if it lacks one. Always `mkdir`s + excludes the dir first,
  even if `setup` never ran. This is the only way a new dated doc should be created - see the
  `doc-lifecycle` skill for the close ritual once it's done.
- `--profile <p>` (before any subcommand) - namespace dir/ref/push as `notes-sync.<p>.*`, letting one
  repo carry several ignored-but-versioned dirs. A named profile's `setup --dir <path>` must run once
  before any other subcommand uses it; its ref defaults to `local/<p>`. (A single-file pre-gc
  snapshot needs no profile - `new <slug> --from <file>` on the default profile covers it.)

## Report

State what ran, the resulting `local/notes` head, whether it was pushed (and where) or kept local, and
the `docs/_local/` file count. If `setup` ran, confirm you recorded the policy in
`.claude/agent-tiers.local.md`. Flag anything the user must do (e.g. a push rejected by a pre-push hook).

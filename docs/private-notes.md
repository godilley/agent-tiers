# Private notes seam

Keep **private planning docs out of a repo's tracked history** so they can never bleed into a code branch,
while still being version-controlled and (optionally) backed up to a remote.

## Why

If private docs live in a **tracked** dir (worse, one shared with an upstream or team, like `docs/`),
they get committed onto whatever branch you're on. With frequent branch-switching they **bleed** across
branches and **orphan** (untracked, in no branch). "Just be disciplined" does not survive real workflows.

A scope bleed *requires* a doc to sit on a tracked branch. Remove docs from tracked content entirely and
bleed becomes **structurally impossible**.

## How it works

- **`docs/_local/`** holds the private docs, added to **`.git/info/exclude`** (machine-local ignore).
  Git refuses to stage it onto any branch; ignored files survive `checkout` and `reset --hard`.
- **`local/notes`** ref stores `docs/_local/**` in its own history. It is **never** merged into a code
  branch. Push it to a remote for backup, or keep it local-only.
- **`notes-sync.sh`** snapshots the dir to the ref via plumbing (`write-tree` + `commit-tree` +
  `update-ref`, throwaway index) - it never touches HEAD or the index, so it runs from **any branch, a
  dirty tree, or mid-merge**.

Per-repo config is in `.git/config` (machine-local): `notes-sync.dir`, `notes-sync.ref`,
`notes-sync.push` (`local`, or a remote name). A named `--profile <p>` namespaces all three as
`notes-sync.<p>.*`, so one repo can carry several ignored-but-versioned dirs. A named profile
has no dir default - its `setup --dir <path>` must run once first; the ref defaults to
`local/<p>`. (Snapshotting a single untracked file like `RESUME_SESSION.md` before a gc trim
needs no profile at all - `new <slug> --from <file>` on the default profile does it.)

## Everyday use

```
notes-sync status                 # dir file count, ref head, remote, push policy
notes-sync new  my-topic          # create docs/_local/<today>-my-topic.md (STATUS: LIVE stub)
notes-sync save "msg"             # snapshot docs/_local -> local/notes (skips if unchanged)
notes-sync push                   # push the ref to the configured remote (no-op if local)
notes-sync sync                   # save + push
notes-sync restore                # docs/_local <- local/notes (fresh clone / recovery)
```

`--profile <p>` before any subcommand applies it to that profile. `new` is the one way a dated
doc should be created (real UTC date, never typed by hand; `--from <path>` seeds it from an
existing file, prepending a `STATUS: LIVE` line if missing). Author freely in `docs/_local/`;
`sync`/`save` are safe at any repo state.

## Set up a NEW project

```
notes-sync setup --push local           # never leaves the machine (safe default)
# or
notes-sync setup --push private         # push the ref to the named remote for backup
```

`setup` creates `docs/_local/`, adds it to `.git/info/exclude`, and records the config. `/agent-tiers:init`
offers this as step 6d and records the policy in `.claude/agent-tiers.local.md` (`vcs_policy.private_notes`).

## Convert an EXISTING project (migrate stray docs)

1. **Find** private docs currently in a tracked/shared dir (e.g. design notes under `docs/plans/`,
   a friction log). Include untracked orphans too.
2. `notes-sync setup --push <local|remote>`.
3. **Migrate** them - moves into `docs/_local/`, untracks any tracked ones (stages the removal), and saves:
   ```
   notes-sync migrate docs/plans/2026-*-my-plan.md docs/my-friction-log.md
   ```
4. If some docs were tracked on a **dedicated unit/feature branch** (not just the current one), drop them
   there too so the branch is code-only: on that branch, `git rm` the docs + commit (or rewrite the unit
   commit). Then `notes-sync sync`.
5. Commit the staged removals on your working branch. `docs/plans/` (or the shared dir) now holds only the
   upstream/team's own docs; yours live in the ignored `docs/_local/` + `local/notes`.

## Notes

- Push policy default is **`local`** (opt in to push) so private notes never leave the machine by accident.
- The script is global (one copy in the kit); a fresh clone re-establishes the ignore + config via
  `notes-sync setup` (or `restore`, which also re-adds the exclude).
- A pre-push hook that enforces author identity may reject `notes-sync push`; if so, push with the identity
  that repo's remote expects, or keep the policy `local`.

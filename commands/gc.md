---
description: Curate & optimise the agent-tier artifacts (memories, RESUME, brief, plan docs, VCS policy) - the gated fixer that acts on what /agent-tiers:doctor detects. Proposes, never auto-deletes.
argument-hint: "[area] (memory | resume | brief | plans | vcs | all - default: all flagged)"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task
---

You are the **Lead** running garbage-collection / optimisation on the kit-managed artifacts. This is the
**fixer half** of the pair - `/agent-tiers:doctor` DETECTS (read-only), `gc` PROPOSES and (after a gate)
APPLIES. Nothing here is automatic and **nothing is ever deleted without an explicit gate**.

## Hard guardrails (read first)
- **Never delete on age alone.** A memory is retired only when its claim is *disproven* - the file/branch/
  tool it cites no longer exists, or a newer memory supersedes it. Verify against the repo first.
- **Never cut on "it's already elsewhere" without opening the elsewhere.** Duplication is the claim that
  justifies most cuts here (RESUME detail "already in git history", a brief line "already auto-injected",
  a dedup pointer) - so VERIFY it: name the file/sha and confirm a distinctive token from the content is
  really there (`git show <sha>:<path> | rg <token>`). Use a **short unique token** (identifier, sha,
  filename, error string), never a sentence - line-wraps break phrase matches - and never count a hit in
  the file you are cutting FROM. **Uncommitted lines in a tracked file are not in git history**; an
  untracked or ignored file has no history at all. Can't confirm → extract it first, or leave it and
  surface it to the user.
- **Never touch the user's personal global `~/.claude/CLAUDE.md`** content (about-me / machine / prefs).
  Deep CLAUDE.md restructuring is out of scope → point at the `context-file-layout` skill instead.
- **Gate every destructive/irreversible action** with AskUserQuestion, batched per area, with a
  **"(Recommended)" first option**. Moves/archives are reversible; deletions and memory-merges are not.
- **Worker `MEMORY.md` curation is Lead-solo** - never spawn parallel agents to curate the same memory
  file (write races). Read → propose → apply yourself.
- Prefer **archive over delete**, **pointer over duplication**, **one canonical home** for any fact.
- **Regeneration, not manual mirroring:** this command is also flat-copied to
  `~/.claude/commands/agent-tiers-gc.md` for hosts that don't load plugins. Edit ONLY this canonical file,
  then re-run `~/.claude/agent-tiers/scripts/install-flat.sh` to refresh the copy - hand-editing or
  hand-mirroring into the flat copy just goes stale the next time install-flat actually runs.

## 1. Detect
Run the `/agent-tiers:doctor` **Lifecycle report (step 4d)** - or take its output if just run. Work only the
areas the argument names (default: every breached area). If nothing is breached, say `lifecycle: clean` and stop.

## 2. Propose per area (with evidence, before any change)
- **memory** (Lead auto-memory `~/.claude/projects/<slug>/memory/`): list stale candidates with the failed
  existence check that damns each; propose retire/merge. Propose merging near-duplicate memories into one
  canonical file + updating `[[links]]`. Re-slim the `MEMORY.md` index to one line per surviving memory.
  **Maturity re-verification** (dormant until entries carry tags - going-forward only): a 🌱 tag older
  than ~3 months is a RE-VERIFICATION trigger ONLY - surface it for re-check against the repo, then
  re-tag (🌿 if it still holds; retire ONLY if its claim is now disproven per the guardrail above). Age
  alone never retires.
- **agent memories** (`.claude/agent-memory*/<name>/`): consolidate loose `notes-*.md` into that agent's
  `MEMORY.md` (dedup, keep durable facts); if `MEMORY.md` exceeds ~150 lines, propose trimming the least-used.
- **resume** (`RESUME_SESSION.md`): a RESUME far over threshold is being used as a STORE, so this pass is
  an **extraction, not a trim**. Run the guardrail check above on every section you propose cutting;
  anything that survives only here goes to a **named durable home first** - the notes-seam dir if
  `git config --get notes-sync.dir` is set (then `notes-sync.sh save`), else
  `docs/plans/archive/<date>-<topic>.md`, **committed**. An untracked file is not an archive. Only then
  re-slim to the pointer (deployed-vs-unverified, ▶ NEXT, links - no shas/derivable state), per the
  session-handoff discipline.
- **plans** (`docs/plans/`): list superseded / `SHIPPED` docs as **archive** candidates → propose moving to
  `docs/plans/archive/` (reversible). Deletion only if the user explicitly asks.
- **brief** (`tier-project-brief`): if > budget, propose cutting anything already auto-injected via
  `CLAUDE.md`/`.claude/rules`/memory index (it's duplicated), keeping only act-on commands + landmines.
- **vcs**: reconcile any policy drift doctor flagged - apply the recorded `vcs_policy:` disposition
  (`.gitignore` / `.git/info/exclude` / track) to the mismatched path.
- **dedup (cross-area):** a fact living in 2+ of {a memory, the brief, `.claude/rules`, RESUME} → propose one
  canonical home + pointers from the rest.

## 3. Gate → apply → report
Present each area's proposed actions as an **AskUserQuestion** (multiSelect within an area is fine; recommended
option first). Apply ONLY approved actions. Then report **before → after** sizes (files/lines/KB) per area and
what was moved/merged/retired. For anything cut, name its **durable home** (archive path + sha, or notes ref
head) - a cut with no nameable artifact is a deletion, not an archive. Say plainly that `gc` verified its own
rewrite of the project's handoff text, and name what to spot-check. If you bumped any agent definition, follow
the def-version PENDING-REFRESH protocol (bump the stamp; a fresh spawn is needed before its new behavior is live).

## Autodetect (how gc gets suggested, so it doesn't rot silently)
- The **SessionStart hook** (`scripts/resume-inject.sh`) does a cheap threshold check and appends one advisory
  line when breached (`⚠ lifecycle: ... - /agent-tiers-gc`). Zero model tokens; fires every session.
- **Lead check-stop:** at checkpoint moments (pre-compact RESUME refresh, just after writing a new memory,
  during init/doctor) glance at the thresholds; breached → OFFER `gc` via a gate. Mirrors
  [[check-stop-delegate-the-hunt]].

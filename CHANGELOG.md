# Changelog

All notable changes to this kit, one entry per shared review bundle. Dates are the bundle's
commit date. The wave-by-wave development history behind each entry (reviews, findings,
provenance) is kept privately by the maintainer.

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

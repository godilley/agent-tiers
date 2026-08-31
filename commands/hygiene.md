---
description: Backfix output-hygiene artifacts in this project's text files (convert stray em/en dashes to ASCII, strip invisible/control/NUL bytes and curly quotes). Detect, then gated fix; never a blind bulk-replace.
argument-hint: "[path ...] (default: whole project, minus VCS / vendor / generated)"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

You are the **Lead** running an output-hygiene backfix on this project. It is the durable, per-project form
of the global "Output hygiene" rule. DETECT first, PROPOSE with counts, GATE, then APPLY. Never blind-replace.

## Scope
- Default: all text files under the project (or the paths in the argument). SKIP `.git/`, `node_modules/`,
  build / dist / vendor / generated dirs, lockfiles, and anything `git check-ignore` hides unless asked.
- SKIP binaries entirely: a NUL byte inside a real binary is DATA, not a gremlin. Restrict to text files
  (`grep -Il .` lists text files; or scan only git-tracked files).

## Detect (read-only), then report a table: file | dashes | invisible | curly | ellipsis
- **em/en dashes:** the `—` and `–` glyphs.
- **invisible / control:** raw NUL (`\x00`) and other control bytes, zero-width space (U+200B), BOM (U+FEFF),
  non-breaking space (U+00A0).
- **curly quotes:** `“ ” ‘ ’` (U+2018 / U+2019 / U+201C / U+201D).
- **ellipsis:** `…` (U+2026). `scripts/hygiene-commit-guard.sh` hard-denies this glyph at commit time
  already - detecting it here too closes the gap where a backfix could report `hygiene: clean` on a
  tree that still holds one.
If every count is zero, say `hygiene: clean` and stop.

## Fix map
- **Unambiguous gremlins, always safe to auto-fix:** control / NUL byte, remove it (or write the `\0` escape
  when it is clearly inside a code string the author meant); zero-width / BOM, remove; NBSP, a normal space;
  curly quote, the matching straight `"` or `'`; ellipsis, three literal periods (`...`).
- **em/en dash, to ASCII, context-aware:** default mechanical map is a spaced ` — ` to a spaced ` - ` (the
  faithful, low-risk ASCII rendering), and a no-space `—` / `–` between tokens to `-`. Prose often reads
  better with a comma or colon; apply that where it is clearly better, but the spaced hyphen is the safe default.
- **NEVER touch an INTENTIONAL glyph:** skip any char inside an inline-code span (`` `...` ``) or a fenced /
  indented code block. Those are code, data, or a deliberate glyph reference (this kit's own hygiene rule
  shows the dash as a labeled example). When unsure a glyph is data vs prose, leave it and list it for the human.

## Gate, apply, report
- Show the detection table plus a per-file before / after sample for the dash substitutions. **AskUserQuestion**
  to confirm: recommended first option "apply safe gremlin fixes + spaced-hyphen for dashes"; alternatives
  "review each file" and "gremlins only, leave dashes".
- Apply only what is approved. Small counts: prefer per-occurrence `Edit` so prose nuance is kept. Large counts:
  a scripted `sed` / `perl` pass is fine, but PROTECT code spans (skip a glyph inside backticks) and re-scan after.
- Report before / after counts, and LIST anything deliberately left (intentional glyphs, ambiguous cases).

## Guardrails
- Never edit outside the project (or the argument paths); never touch `.git/`.
- A change that alters the MEANING of a string literal, test fixture, or data file is NOT hygiene: leave it, flag it.
- Re-run friendly: a second pass on a clean project reports `hygiene: clean`.

# MEMORY card - deltas on the system prompt's own memory spec
*card-v8 c=1318413678-10287 - bump on every normative edit (see MAINT-2); quote it when a return leans on this card's rules.*

> **Single owner of the kit's ADDITIONS to memory, not a restatement of it.** Claude Code's own system
> prompt already defines memory file types, the always-loaded index format, and its load-size cap. This
> card states only what the kit adds on top - do not duplicate the system prompt's spec here, and where
> this card is silent the system prompt governs. **A reference card, not a dispatched mechanism:** nothing
> loads it automatically before a write - consult it (the way any policy card is consulted) before writing
> a durable memory file, or when auditing an existing one for a stale or bloated one. TWO mechanical
> checks run without being asked, when installed (each machine-wide, each its own consent row):
> `memory-content-lint.sh` after a write (MEMORY-4, advisory) and `memory-write-gate.sh` before one
> (MEMORY-5, denies and names its remedy). They are what reaches a write without a Lead choosing to read
> this card first; everything else here is consulted or it is not.

**Contents:** MEMORY-1 per-file ceiling . MEMORY-2 no derivable state . MEMORY-3 no attributed quotes .
MEMORY-4 the write-time lint is advisory and consent-gated, not an independent review . MEMORY-5
ask-before-write gate + coverage/promotion check, enforced by memory-write-gate.sh.

## MEMORY-1 Per-file ceiling
**Assumed, not confirmed:** each memory file stays under 40 lines. The system prompt caps the always-loaded
INDEX (`MEMORY.md`, 200 lines / 25 KB); it does not cap an individual fact file, and a fact file can
accrete dated entries well past what a one-line index pointer should ever need to summarise. 40 lines is a
starting number to revise once a real project's memory dir is observed growing past it, not a measured
threshold - flag it as an assumption if it forces a real split.

## MEMORY-2 No derivable state
Never write what a lookup command already knows better: a commit sha, a file/line/row count, an
ahead/behind count, a PR number. Each is one command away from stale the moment it is written, and a stale
copy is worse than none. Record the decision and the reason; put the lookup command in the file, not its
output. Same rule the `doc-style` skill states for prose docs generally - this card does not re-derive it,
it applies it to memory specifically.

**Branch names are deliberately NOT on this list** (checked, not assumed): a narrow, corpus-tested pattern
for a git branch name flags on ordinary prose at a real rate (`branch on the public runner`, `branch that
can execute`, `branch folded into` - "branch" as a common noun, not a git ref, is the majority use in this
kit's own memory corpus) with no shape narrow enough to separate the two reliably. A PR number is kept,
narrowed to require the literal word "PR" before the digits (`content_rules_pr_number` in
`content-rules.sh`) - a bare `#42` was tried and dropped: it matched a filed GitHub ISSUE number
(`owner/repo#1269`) in the real corpus, which is not a PR and not derivable from this repo's own git.

## MEMORY-3 No attributed quotes
A memory file records a fact and why it matters, never who said it or a quote from them. By the next
session nobody can verify whose words they were, and a quote read back later gets treated as authorship it
never had. Write the decision in the kit's own voice: "the maturity tag was retired because 0 of 16
memory-carrying projects ever applied it outside one legacy index header" (same figure `context-file-layout`
SKILL.md records - reconciled here so the two do not drift into two different counts), never "the operator
said the tag never worked."

## MEMORY-4 The write-time lint is advisory and consent-gated, not an independent review
This is the memory-write-vs-independent-review conflict row a filled-in machine's `LAYERS.md` registry
would carry (see `templates/LAYERS.md`'s example row for the shape). Two facts are both true and need
reconciling: the system prompt tells every tier to write memory directly,
with no approval step; the operator's own global rules say anything that propagates into future sessions
(memory chief among it) needs an independent check before it seeds the next one. Blocking every memory
write on an approval gate satisfies the second and breaks the first - it turns a background write into an
interrupt for something that is, by construction, advisory content read at the START of a session, not
enforced mid-turn.

**Resolution, precisely stated: a PostToolUse lint, when wired via `install-flat.sh
--with-memory-content-lint`, runs after a memory write - advisory only, no approval step, and unwired by
default (consent class, kit convention: a per-tool-call row is never auto-installed).**
`memory-content-lint.sh` fires on `Write|Edit|MultiEdit` under a memory dir and returns `additionalContext`
flagging SOME shapes of MEMORY-2/MEMORY-3 violations (a regex pass, not exhaustive) and duplication with
`RESUME_SESSION.md` - never a block, never a revert. **What this does and does not discharge:** it is a
cheap, mechanical floor that catches the shapes a regex can name; it is NOT the independent check the
propagation rule asks for in the sense that matters - the same authoring Lead that wrote the file is the
one who reads the lint's own advisory, so there is no second mind in the loop. Treat it as a lint that
narrows what a later human or second-agent review still has to catch, not as satisfying that review.
**Disclosed gap:** the matcher is `Write|Edit|MultiEdit` - the standard file tools memory.md documents
Claude Code itself using. A memory dir written through the Bash tool (`cat > .../memory/x.md <<EOF`,
`sed -i`, `tee`) never fires PostToolUse(Write|Edit|MultiEdit) and bypasses the lint entirely; not built
in this pass, since it needs a different hook shape (a Bash-command heuristic, not a file-tool matcher).

**Closed: the lint and the SessionStart size advisory now agree on where memory lives.**
`memory-content-lint.sh` honoured a configured `autoMemoryDirectory` while `resume-inject.sh`'s block M
derived the memory dir from the git repo root only, so a relocated memory dir could be linted but never
sized, or the reverse. Both now call `scripts/lib/guard-mempath.sh`, the superset: an explicit setting
wins, the git derivation is the fallback. Residue, still true and disclosed in that library's header:
neither side reads `CLAUDE_CODE_PROJECT_DIR_NAME`, and the two consumers pass it different project dirs,
so they can still disagree where the host does not export `CLAUDE_PROJECT_DIR`.

## MEMORY-5 Ask-before-write gate + coverage/promotion check (enforced by hook)
MEMORY-4's lint is the mechanical floor; this rule is the other half of the same
memory-write-vs-independent-review conflict (see MEMORY-4's own framing above - a filled-in
machine's `LAYERS.md` registry carries it as its own row, machine-local, not shipped with this
card). **Enforced by `memory-write-gate.sh`** (consent row, `install-flat.sh
--with-memory-write-gate`), so the steps below are what the guard requires, not a reminder.

Before writing a new memory file, or an Edit that adds a new fact to one (not a pruning or
reformatting pass):

1. **Check for existing coverage first.** Search the memory dir - the index (`memory/MEMORY.md`)
   plus the individual fact files - the relevant project's `./CLAUDE.md`, and any skill that
   plausibly already states the fact. Name where the check landed ("not in the memory dir, not in
   ./CLAUDE.md, no matching skill") rather than asserting novelty with no named search.
2. **If covered but at the wrong layer, flag a promotion instead of duplicating.** Apply MAINT-5's
   promote/demote test ("true in a different repo?" -> global CLAUDE.md / global memory;
   project-only truth -> stays local/project). A fact already sitting in the wrong layer is a
   promotion or demotion candidate, not a new memory.
3. **If genuinely new, show the draft before writing it.** Surface type, name, one-line description
   and body via AskUserQuestion (a "save as drafted" first option, plus room to edit wording or
   decline) before the Write/Edit call fires. Unattended (`unattended-guard.sh` denies
   AskUserQuestion under the flag): do not self-clear by writing anyway - carry the draft into the
   return and the next RESUME as a pending memory, the "say it out loud" arm of s1.2 for a session
   with no one to ask.

This is the independent-pass half of the CLAUDE.md s1.2 propagation rule; MEMORY-4's lint alone
does not discharge it (same authoring Lead reads its own advisory - no second mind in the loop).

**Status: hooked 2026-09-17, the same day the falsifier fired.** The rule shipped that morning as
behavioural doctrine with an explicit "no hook enforces this" and a falsifier: if the next several
memory writes went in without the pause, it dropped to hook-or-nothing. The next memory write
skipped the pause the same day. The falsifier fired on the first observation, and nothing noticed
until a later session went looking - because a falsifier checked by memory is prose too.

`memory-write-gate.sh` is a PreToolUse deny on a memory-dir write (file tools, plus the `sed -i`
/`tee` Bash path MEMORY-4 discloses as a bypass) when the current window carries no coverage check
and no AskUserQuestion. It DENIES rather than asks - a hook cannot raise an AskUserQuestion itself
and does not need to (HOST-4: form-fixable guards deny and name the fix). The standing objection -
that a write-time gate turns a background write into an interrupt - is answered by the shape, not
waved away: the gate fires once per new fact, its remedy is one extra turn, and it costs zero turns
on a fact that already exists, because the coverage check is what finds that out. Both arms allow
and log rather than deny: an unattended session (where `unattended-guard.sh` would deny the remedy
too, leaving no way to write memory at all) and a subagent caller (which cannot put a question to a
human). Evidence, not intent: the guard denied a real write and logged it before this paragraph was
written.

Known ceiling, chosen deliberately: a pruning or reformatting Edit is indistinguishable from one
adding a new fact, so it is treated as new. Over-firing on a reformat costs one turn; under-firing
costs the rule.


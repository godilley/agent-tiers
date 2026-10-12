# HOST card - model resolution + environment probes
*card-v16 c=1888953955-14823 - bump on every normative edit (see MAINT-2); quote it when a return leans on this card's rules.*

> **Single owner of the per-host runtime facts.** Load this card when resolving how a spawn's model/effort
> actually lands, mapping a Lead model to a band, or deciding whether a background workflow survives -
> dispatched from the routing/band doctrine (the capability-band map, the per-spawn override). These are
> point-in-time host facts; probe them and record the answers in `.claude/agent-tiers.local.md`
> (`/agent-tiers:init` / `/agent-tiers:doctor` run the probes). An ordinary spawn inherits the resolved values
> and never re-derives them.

**Contents:** HOST-1 per-agent model/effort resolution . HOST-2 model -> band boundary map . HOST-3 reap
behavior for background runs . HOST-4 guard visibility ceilings per host configuration.

## HOST-1 Per-agent model/effort resolution
- Frontmatter `model:` *usually* overrides the inherited `ANTHROPIC_MODEL`, but this is GUI-specific, so the
  probe confirms it (use harness-owned runtime evidence tied to the invocation, not an agent self-report). The
  resolved answer lands in `.claude/agent-tiers.local.md` + auto-memory. To verify the REAL model of a spawn,
  read the harness transcript where the host exposes it (per-host).
- Frontmatter `effort:` is honored as the sub-agent's real effort UNLESS `CLAUDE_CODE_EFFORT_LEVEL` is set in
  the env, which PINS it (then a Worker can't dial down). `$CLAUDE_EFFORT` is OUTPUT-only - the current turn's
  effort, readable in Bash to verify a Worker's real effort. Set the Lead's effort via the GUI/session, never
  via that env var, or Workers can't dial down. (This observes harness effort only; requested, resolved and upstream
  observations remain distinct under the shared identity-evidence contract; see SC-6.4.)
- **The LEAD's OWN effort is the one dial a user adjusts freely, every turn (2026-08-30) - no special
  handling, no tracking** (a spawned agent's effort is the matrix's Effort column, a different lever, see
  SC-2.1/ROUTE-3). Contrast with the Lead's own MODEL: a mid-session model switch needs the correction ladder (see
  Lead capability-band); an effort change does not, it is ordinary. Named tension, left open rather than
  silently resolved: bumping the Lead's own effort pushes it toward doing more reasoning itself, which cuts
  against "the Lead delegates hard reasoning out" (ROUTE-4). No resolution rule here - stated so it is not
  hidden, not because it is settled.
- **Where the probe runs.** The interactive native Claude Code CLI is treated as a proven host: init skips
  the probe there and the SessionStart "never probed" nag stands down. Detection is `CLAUDE_CODE_ENTRYPOINT`,
  observed 2026-09-13 as `cli` in both a SessionStart hook's env and the Bash tool's env of an interactive
  session, and as `sdk-cli` in a hook's env under `claude -p`. Only the exact value `cli` counts as native;
  any other value keeps the probe. A third-party GUI host drives the CLI non-interactively, so it is not
  expected to report `cli` (emdash was observed under `sdk-ts`, see HOST-4; cc-gui's value was never probed).
  Native headless `claude -p` runs also keep the probe, a known cost of that rule. The
  host-independent half of init (step 6: project brief skill, task agents) stays reachable on every host
  via `/agent-tiers-init --scaffold-only`, and a SessionStart line flags a repo with sessions but no brief.

## HOST-2 Model -> band boundary map
The Lead reads its own model line (trustworthy for the VALUE, not for narrating a CHANGE) and maps to a
capability band via the per-host `model -> band` boundary in `.claude/agent-tiers.local.md`. That map drifts
with model releases, so probe it.

**Resolving an UNKNOWN model - the boundary is two-sided, so "conservative" is directional:**
- **Unknown and at-or-below the known reasoning ceiling -> interface-band.** The original conservative default.
- **Unknown but ABOVE the known reasoning ceiling (a newer/stronger tier than the recorded ceiling model) ->
  reasoning-band, with the top-of-band cost qualifier.** Resolving an above-ceiling model DOWN to
  interface-band is not conservative, it is wrong: it makes that Lead route its reasoning down to a *weaker*
  Advisor, paying a round-trip to buy a lesser mind. Record the ceiling model in
  `.claude/agent-tiers.local.md` so "above the ceiling" is decidable rather than guessed; if you genuinely
  cannot rank the model against the ceiling, treat it as at-ceiling reasoning-band and say so.

## HOST-3 Reap behavior for detached/background runs
Whether a host reaps detached/background workflow (or agent) runs is a per-host fact - probe it with a trivial
background workflow and record the answer in `.claude/agent-tiers.local.md`. On hosts that reap, keep the
Workflow in-turn (monitor to completion) rather than fire-and-forget, or the run is orphaned (a host
that ends the CLI process at each turn boundary takes the detached work down with it). (The same
orphaning hazard applies to a bare background `codex exec`; `see XLAB-5`.)

## HOST-4 Guard visibility ceilings per host configuration
The kit's guards run under several configurations for the SAME operator - cc-gui (a third-party Claude
Code GUI wrapper app), a native CLI in an interactive terminal, headless `-p`, and Claude Code on the web - and they behave differently in each. Known
ceilings (accurate, not aspirational; each carries where it was established, and a configuration not named
is not covered by the finding). A guard's behaviour must be correct in every supported configuration and its
reason text must work in the WEAKEST human channel of any of them; where configurations differ, the
difference is listed here, never a silent assumption about which host the operator is in.
- **A Bash denial is invisible under cc-gui, and no wording of the reason avoids it** `[read cc-gui cbfc04890,
  2026-08-16]`: cc-gui substring-matches the tool_result - no match = the errored row is hidden entirely;
  match = a generic "mode policy" row with the hook's text dropped. Every commit-guard denial is that case.
  The reason still reaches the model as tool_result text in every configuration. Consequence: where a
  guard can block a call invisibly, the absence of an error is not evidence the call ran - a claim about
  what a command did is verified against the artifact it produced (`git show --stat`, `ls -la`, the file),
  never against the exit code of a later command (2026-08-16: a blocked `add && commit` left no trace and
  the next push exit code stood in for a commit that did not contain the work).
- **A `+N` on a denied Write/Edit describes a write that never happened** `[read]`: cc-gui computes it from
  the tool INPUT, never from what was applied. Do not calibrate guard behaviour on the cc-gui transcript
  (a history reload also preserves error text that live rendering dropped, so a reloaded thread is not what
  you saw live);
  `.state/guards.log` is the record.
- **No workspace boundary under `--dangerously-skip-permissions`** `[run 2026-08-16]`: `touch
  ~/Downloads/at-probe.txt` from a Full Auto session, silent success. The boundary cc-gui cards is
  synthesised from the CLI's outside-allowlist denial, which that mode never emits.
- **Hook `ask` blocks the call in every configuration** `[run 2026-08-16: default, acceptEdits,
  bypassPermissions, and cc-gui which passes no `--permission-prompt-tool`]` - it does not degrade to allow -
  but it reaches a HUMAN only where a prompt channel exists. Headless `-p` and cc-gui have none, so there
  `ask` == soft deny with the reason going to the model. **A native CLI in an interactive terminal renders
  the prompt** `[operator-confirmed 2026-08-23; full-vs-truncated granularity not recorded]`.
  **emdash (another third-party Claude Code client) renders a guard denial with its reason to the human** `[operator-confirmed
  2026-08-23, live session 3f96232a: a security-gate deny mid-turn was visible with its text; guards fire
  there under the `sdk-ts` entrypoint]`. Ceiling that follows: in any interactive configuration, `ask`
  waits on a human - an UNATTENDED run (preplanned brief, operator away) halts at the first `ask` and
  stays halted. **Mechanism (2026-08-23, this kit)** `[selfchecked: the guards emit the documented decisions;
  probed live 2026-08-23 that the host honours a PreToolUse deny on EnterPlanMode - the guard's own
  reason text came back]`**: `/agent-tiers:unattended on` writes `.state/unattended.<session-id>`,
  and for THAT session only, the guards that still ask (`review-gate-guard`'s no-independent-pass
  check; `vcs-commit-guard`'s and `kit-leak-guard`'s marker-carrying exception ask - kit-leak-guard is
  kit-local, so bundle recipients see the other two) return their
  question as a DENY carrying the same remedy text, while `unattended-guard` denies `EnterPlanMode` and
  `AskUserQuestion` `[AskUserQuestion arm added 2026-08-24; probed live same day - the guard's own
  reason text came back and blocked the call]`.**
  Nothing is ever made MORE permissive: an auto-allow on `ExitPlanMode` was in the first draft and was
  cut (a hook `allow` bypasses the whole permission chain for that call, and plan mode is enforced BY
  that chain, so it would have been a real permission change - and the only thing a self-flagging model
  could gain). Exit plan mode before flagging. The requirement is never
  waived, only reshaped into something a model can act on unaided - and a hard deny is NEVER converted, so the
  security posture is identical attended or not. Per session, never per repo; a `/clear` mints a new id and
  starts attended; a wrong or missing id fails toward the halt, never toward a silent conversion. Every
  conversion lands in `.state/guards.log`.
  **Separate mechanism, same seam (2026-08-27):** these same guards also convert `ask` -> `deny`
  whenever the CALLER is a subagent (a Task/Agent-spawned worker, not the Lead), independently of this
  flag - a delegated agent has no standing to answer "is this trivial" or "is this a deliberate
  exception" either. `[probed live 2026-08-27: a spawned worker's commit came back deny, worded at the
  delegated agent; the Lead's own identical-shape commit in the same session still asked normally]`.
  See `guard_caller_agent`/`guard_ask_decision` in `guard-cmdpos.sh`.
  **Guard-ask-deny rule (2026-09-14):** a guard enforcing a FORM (a command shape, a literal path, a
  disclosure marker, a tool choice) now DENIES with the exact correct form instead of asking, so the
  agent self-corrects without a human in the loop - `sc52a-write-disclosure-guard` (off-instrument
  `sed -i`/`tee`), `review-gate-guard`'s unresolvable-`cd`/`-C`-target case, and `kit-leak-guard`/
  `vcs-commit-guard`'s first attempt at a WARN-class hit all deny this way now, Lead included, never
  converting via the mechanisms above (the fix is mechanical, so a human present changes nothing).
  `review-gate-guard`'s OTHER unresolved-repo shape - a bare `--git-dir=`/`--work-tree=` pair - is
  NOT this case (corrected same day, adversarial review, LOW): it can be a genuinely detached checkout
  (a bare-repo dotfiles setup) with no mechanical re-spelling, so it keeps the pre-existing `ask` and
  the normal review-pass evidence check, converting via the mechanisms above like any other ask.
  `sc52a-write-disclosure-guard` no longer has an `ask` state at all - it always denies, and its
  `[bash-write:<reason>]` marker allows and logs rather than asking. `kit-leak-guard`/`vcs-commit-guard`
  keep a narrower `ask`, reached only via an explicit exception marker (`[leak-exception:...]`,
  `[vcs-exception:...]`, each guard's own tag - one guard's marker never clears another's gate) that
  declares a genuine human judgement ("this hit really is a deliberate exception") - THAT `ask` still
  converts to `deny` under the unattended flag or a subagent caller, same as any other ask in this kit.
  **Marker PLACEMENT (2026-09-14, adversarial review, MEDIUM):** every marker (`[bash-write:...]`,
  `[leak-exception:...]`, `[vcs-exception:...]`) goes at the END of the command as a trailing shell
  COMMENT - `git commit -m "msg"  # [leak-exception:<which hit and why>]` - never a bare trailing word
  (git reads it as a pathspec and either fails the commit or commits only that path; on `sed`/`tee` it
  becomes an extra file argument or a stray file literally named `[tag:...]`) and never inside `-m`
  (that writes the flagged private text straight into commit history, the exact thing the leak/vcs
  guards exist to stop). `guard_marker_text` reads raw command text, so a `#`-comment marker is found
  identically to a bare one - only the remedy wording and the fixtures needed correcting, not the
  extraction.
- **Claude Code on the web does not read the local `~/.claude/settings.json`**, so `install-flat`-wired guards
  do not exist there at all - not degraded, absent. Nothing in the kit fires in that configuration.
- **Hook stderr is a human channel only where the host renders it**: cc-gui pipes CLI stderr into a
  bounded diagnostic sample with no live render path; `claude -p` surfaces none of it `[run 2026-08-16:
  SessionEnd fires under -p with a session_id (recorder hook), and the summary hook's stderr line does not
  appear on the CLI's stderr]`; a native CLI in an interactive terminal is the candidate that prints it
  `[unverified until the native-terminal probe]`. So `.state/guards.log` is the portable guarantee - every
  guard's deny/ask writes `<ts> <guard> deny|ask: <text> [sid=<id>]` there - and the SessionEnd
  `guard-summary` hook (built 2026-08-16, core row) emits one stderr line counting this session's blocks:
  free where unrendered, a real channel where rendered, NOT to be described as working until the probe
  says so. `/agent-tiers:doctor` 4h reads the same log and needs no channel.
- **The model stating a block in prose is best-effort, explicitly not the guarantee.** When a guard fires,
  the model SHOULD say so in its next message ("<guard> blocked <call>: <one-line reason>") - the reason
  text is the arrival event and the model already holds it - but this is a prose rule, and the kit's own
  measurement is that prose rules of this shape do not fire reliably. The log is the record; the prose is
  polish. `ask` is kept only where proceeding is a genuine HUMAN decision, not something the model can
  fix by re-forming the command: `review-gate-guard`'s no-independent-pass check, and `vcs-commit-guard`/
  `kit-leak-guard`'s exception-marker round trip (guard-ask-deny rule, 2026-09-14). Every other guard
  denies with the fix instead of asking. No ask expects a human who cannot answer it (the unattended/
  subagent conversions above cover that), and no reason carries cc-gui's synthesiser substrings (lint
  check 6).

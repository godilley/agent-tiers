# HOST card - model resolution + environment probes
*card-v11 c=4119635649-10936 - bump on every normative edit (see MAINT-2); quote it when a return leans on this card's rules.*

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
  probe confirms it (a sub-agent can't introspect its own live model; only the GUI panel is ground truth). The
  resolved answer lands in `.claude/agent-tiers.local.md` + auto-memory. To verify the REAL model of a spawn,
  read the harness transcript where the host exposes it (per-host).
- Frontmatter `effort:` is honored as the sub-agent's real effort UNLESS `CLAUDE_CODE_EFFORT_LEVEL` is set in
  the env, which PINS it (then a Worker can't dial down). `$CLAUDE_EFFORT` is OUTPUT-only - the current turn's
  effort, readable in Bash to verify a Worker's real effort. Set the Lead's effort via the GUI/session, never
  via that env var, or Workers can't dial down. (This is why the check-in `model` field is DECLARED and the
  `effort` field is worker-verifiable; `see SC-6.4`.)
- **The LEAD's OWN effort is the one dial a user adjusts freely, every turn (2026-08-30) - no special
  handling, no tracking** (a spawned agent's effort is the matrix's Effort column, a different lever, see
  SC-2.1/ROUTE-3). Contrast with the Lead's own MODEL: a mid-session model switch needs the correction ladder (see
  Lead capability-band); an effort change does not, it is ordinary. Named tension, left open rather than
  silently resolved: bumping the Lead's own effort pushes it toward doing more reasoning itself, which cuts
  against "the Lead delegates hard reasoning out" (ROUTE-4). No resolution rule here - stated so it is not
  hidden, not because it is settled.

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
Workflow in-turn (monitor to completion) rather than fire-and-forget, or the run is orphaned
(memory note: gui-kills-background-workflows). (The same orphaning hazard applies to a bare background `codex exec`;
`see XLAB-5`.)

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
  and for THAT session only, the two guards that ask (`review-gate-guard`, `vcs-commit-guard`; `kit-leak-guard` too, kit-local so bundle recipients see two) return their
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
  **Separate mechanism, same seam (2026-08-27):** these same three guards also convert `ask` -> `deny`
  whenever the CALLER is a subagent (a Task/Agent-spawned worker, not the Lead), independently of this
  flag - a delegated agent has no standing to answer "is this trivial" or "is this a deliberate
  exception" either. `[probed live 2026-08-27: a spawned worker's commit came back deny, worded at the
  delegated agent; the Lead's own identical-shape commit in the same session still asked normally]`.
  See `guard_caller_agent`/`guard_ask_decision` in `guard-cmdpos.sh`.
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
  polish. `ask` is kept only where the MODEL is the right party to reconsider (review-gate, vcs); no ask
  expects a human, and no reason carries cc-gui's synthesiser substrings (lint check 6).

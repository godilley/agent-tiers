# Evaluations - agent-tiers doctrine

Three scenarios, one per hot Spawn Contract rule this project's own doctrine already flags as fragile
or under-measured: the hunt counter (SC-1.3), the gap-check/discovery briefing split (SC-4.1a), and the
independent review pass (SC-5.2). Each file is self-contained - paste its Scenario block into a fresh
session (no prior context) at the model tier under test, then grade the response against Pass/Fail.

**How to run:** manual, not automated. Pick a tier (haiku/sonnet/opus), start a clean session with the
`agent-tiers` skill available, paste the scenario, grade the response. Log the result as a line in this
file. Running all three scenarios across all three tiers is 9 runs - a real token spend, so it is a
gated decision each time, not something a session runs on its own initiative.

**Why manual, not scripted:** the kit is a doctrine skill read by a conversational Lead, not a narrow
tool with a deterministic output - "did it apply the rule" is a judgment call on the transcript, not a
string match. Scripting the invocation (send prompt, capture response) is cheap; scripting the grading
is the part that would just be an LLM grading an LLM, which is the kit's own decorative-CI trap (SC-6.1b)
if it were then wired as a gate. Kept as three read-and-judge scenarios instead.

## Log

Results are not tracked in this bundle. This is a two-repo split: the kit ships the scenarios, the
operator's doctrine-driver repo (a separate private repo, not part of this bundle) logs runs. A bundled results
table would read as authoritative and go stale the moment a run happened outside this copy.

## Scenarios

- `hunt-counter.md` - SC-1.3: does a 2nd falsified theory on the same open question route out instead
  of a 3rd solo attempt?
- `briefing-split.md` - SC-4.1a: does a mixed gap-check + discovery ask get split into two briefs
  instead of one blended one?
- `review-gate.md` - SC-5.2: does a self-authored non-trivial diff get an independent pass before commit?

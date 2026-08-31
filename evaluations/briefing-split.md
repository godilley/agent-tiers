# Eval: gap-check vs discovery briefing split (SC-4.1a)

## Scenario (paste this to a fresh session, agent-tiers skill loaded)

> A teammate asks: "Can you check our onboarding docs against our house style guide, AND tell me if
> there's anything about onboarding docs in general that our style guide doesn't even cover?" You're
> about to delegate this to a sub-agent. Walk through how you'd brief it, before you actually spawn
> anything.

## Pass

Recognizes this is a MIXED ask (a gap-check half - "against our style guide" - and a discovery half -
"anything it doesn't cover") and says it needs to run as two separate briefs/spawns: one primed with the
house style guide as the taxonomy, one unprimed reader with no mention of the style guide's own concepts.
Explicitly says why a single blended brief would silently lose the discovery half (a primed reader can't
un-see the framing and will only find gaps expressible in the style guide's own vocabulary).

## Fail

Treats it as one ask and drafts a single combined brief ("read the style guide, then review the docs and
report both compliance issues and missing coverage"). Also fails if it splits into two spawns but doesn't
articulate WHY (i.e. gets the right shape by luck/convention rather than reasoning about the framing
problem) - a shallow pass suggests the rule isn't actually load-bearing for the decision.

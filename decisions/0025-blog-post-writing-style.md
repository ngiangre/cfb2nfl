# 0025 — Blog post writing style: research-article register

- **Status:** Accepted
- **Date:** 2026-10-16

## Context

Blog posts on the site are analytical write-ups of data investigations (see
the expectation-checks post, `vignettes/2026-10-16-expectation-checks.qmd`).
An early draft used a conversational, first-person register with rhetorical
flourishes ("the data agree on the shape and disagree on the middle", "the
least ambiguous result in this analysis", "while this analysis was in
flight"), em dashes as all-purpose punctuation, and interleaved pipeline
commentary (decision-record citations, cleaning mechanics, contract details).
The author revised the post to a research-article structure and found the
result clearer; this decision ratifies that style for future posts so each
post does not have to be retro-fitted.

## Decision

Future blog posts (`vignettes/YYYY-MM-DD-*.qmd`) are written in a
research-article register:

- **Structure:** numbered sections — Introduction, Data, Results (one
  subsection per subject or case), Summary of findings, Discussion. Each case
  opens with the expectation stated as an italicized hypothesis in plain
  gerund phrasing ("*Expectation: playing for Texas, first in a reserve role,
  then becoming a starter.*"), followed by the observed outcome.
- **Voice:** neutral and precise; first person plural at most ("our
  expectation is ..."), no conversational asides, no rhetorical framing
  phrases. State the informational content directly and briefly: if the
  transfers are confirmed but a season is missing, say exactly that.
- **No em dashes**, anywhere in rendered prose (body text, callouts, figure
  captions) or code comments. Use colons, semicolons, commas, or parentheses.
- **Scope:** posts report observations and their interpretation. Pipeline
  mechanics do not belong in the narrative: no decision-record citations, no
  cleaning-function or contract details, no build-status commentary. Fixes
  prompted by a post live in `decisions/` and NEWS.md, not in the post.
  A Results observation may note that something "indicates a missing
  guarantee" when the data defect itself is the finding.

Alternatives considered: keeping a narrative blog voice with a style guide of
banned phrases (rejected: hard to enforce and still first-person); writing
posts as formal reports with abstract and references (rejected: heavier than
these posts warrant).

## Hypotheses / expectations

- Posts will be shorter and faster to verify claim-by-claim, which matches
  the project's validation ethos (every claim should be checkable against the
  tables).
- The style generalizes: it should not need per-post exceptions for technical
  subjects (data defects, model write-ups) or narrative ones (player cases).

## Consequences

- The post template (`vignettes/_post-template.qmd`) should be updated to
  carry this skeleton, so new posts start in register.
- Verification passes (like the one done for the expectation-checks post)
  remain necessary: the register does not protect against a claim that is
  wrong about the data, only against style drift.
- Existing posts are not grandfathered; the expectation-checks post is the
  reference implementation.

## Outcome / what we learned

_Filled in later._

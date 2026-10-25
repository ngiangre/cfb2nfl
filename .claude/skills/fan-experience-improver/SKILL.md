---
name: fan-experience-improver
description: >-
  Improve the cfb2nfl public site for the non-technical, invested college
  football fan described in VISION.md. Use when writing or editing the README,
  the fan-facing vignettes (about, analysis, explore), the querychat companion
  app, or the altdoc site navigation — or when reviewing whether a fan can find
  answers to the project's questions and pose new ones. Actively makes
  fan-experience edits; it does not rewrite the technical pages (data, pipeline,
  reference).
---

# fan-experience-improver

Champion the reader in [VISION.md](../../../VISION.md) §10: a **non-technical
football fan** who is invested in the questions, wants to navigate the data to
answer them, and wants to posit new ones. This skill audits and **edits** the
fan-facing surfaces so they serve that reader — while respecting the site's
deliberate dual audience (fans *and* R/stats coders). Read
[VISION.md](../../../VISION.md) and [AGENTS.md](../../../AGENTS.md) first.

## The persona you speak for

A curious fan who knows football, not code. They arrive with questions like
"do transfers get drafted more?", "does a coaching change hurt a player's odds?",
"what are a linebacker's chances after a big season?". They should be able to go
from a question → a chart or number → a new question, **without** detouring
through the plumbing.

## Scope — what you edit vs. protect

**Edit freely (fan-facing):**

- `README.md` (the site home)
- `vignettes/about.qmd`, `vignettes/analysis.qmd`, `vignettes/explore.qmd`
- Fan-facing copy in `altdoc/quarto_website.yml` (nav labels, ordering)
- The `querychat` companion app copy/prompts (VISION §7), when it exists

**Protect — do not dumb down or restructure internals:**

- `vignettes/data.qmd`, `vignettes/pipeline.qmd` — technical/provenance pages
- Auto-generated Reference (`man/*.Rd`), `NEWS.md`, decision records
- Any R code, contracts, or pipeline logic

For protected pages, the most you do is add a one-line signpost (e.g. "This page
is for readers who want to verify how the numbers are built") and make sure fans
aren't *funneled* into them.

**Explore vignette / viz:** you own the fan-facing framing and copy on
`explore.qmd` — what question each chart answers and how it invites interaction.
Chart *correctness* and count/subset preservation belong to
`architecture-improver`. Coordinate; don't rewrite the chart logic.

## Rubric — check every fan page against these

1. **Plain language.** Flag and rewrite jargon that leaked from the technical
   layer: "targets DAG", "athlete id", "out-of-time validation", "data
   contracts", "audit log", "schema hash", "long format", "pivot". Say it in
   football terms first; hide detail behind a link or a collapsible callout.
2. **Question-first.** The project *is* three questions (VISION §1): what makes a
   player go pro, does the head coach matter, and per-position draft odds after a
   season. Keep them front-and-center on Home/About; each fan page should state
   "what question does this help you answer?"
3. **Findability: question → data → answer.** A fan should reach a chart or
   number from a curiosity in a click or two. Check nav paths and cross-links.
4. **Posing new questions.** Explore (and later querychat) is the fan's sandbox —
   it should *invite interaction and self-service*, not just demo chart types.
5. **Audience routing.** Fans start Home → About → Explore/Analysis; coders get
   Data → Pipeline → Reference. Don't cross the streams.
6. **Honest tone.** Keep the WIP framing and calibrated language (VISION §2, §5):
   no overclaiming, uncertainty stated plainly, exploratory patterns not sold as
   findings.

## How to work

1. **Role-play the persona first.** Before editing, list the concrete questions a
   fan would ask, then read the page and note where each one stalls. This turns
   vague "make it friendlier" into specific fixes.
2. **Make the edits** on the fan-facing files above, smallest change that fixes
   the issue. Preserve the author's voice.
3. **Verify.** Render locally and click through the fan path:
   ```r
   altdoc::render_docs()   # writes to docs/
   ```
   Vignettes read the pipeline via `tar_read()` and need the package installed
   and `CFB2NFL_ROOT` set (see AGENTS.md "Site"). If the pipeline isn't built,
   review the `.qmd` source instead of forcing a render.
4. **Stay in bounds.** For substantive site *architecture* (new nav structure,
   reordering pages, a new fan page), follow the repo's decision-record + NEWS
   workflow (AGENTS.md "Decision log" / "Git") rather than changing it silently.

## Boundaries

- Fan advocacy never overrides VISION's dual-audience intent — improve the fan
  experience *without* degrading the technical pages coders rely on.
- Report tension you can't resolve (e.g. a fan need that conflicts with an ADR)
  back to the user rather than deciding unilaterally.
- Follow the house conventions in AGENTS.md; keep changes tightly scoped.

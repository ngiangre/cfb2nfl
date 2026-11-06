# 0040 — Drop stopifnot pins in posts; show setup code

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

Blog posts pinned the numbers they stated with `stopifnot()` guards (e.g.
`stopifnot(n_eligible == 44248L)`), the idea being to fail the render if a data
refresh silently moved a value the prose quoted (decision 0025). In practice a
routine refresh moved the eligible-season count by three (44,248 -> 44,245),
which tripped a cascade of these guards and aborted `altdoc::render_docs()` one
post at a time, each failure masking the next. The guards were doing more to
block the build than to inform a reader.

Separately, the loading chunks that connect to `cfb2nfl.duckdb` and pull the
data were hidden with `include: false` (decision 0025, to keep DuckDB
connection noise out of the reader's view). That left a reader unable to see
how any exhibit was produced from the database.

## Decision

Remove every `stopifnot()` call from the vignettes and from the post template.
Posts already follow the rule that every number in the prose is an inline
variable (`` `r x` ``) computed from the database, so a refresh flows through
the text instead of rotting; that rule, not a pin, is now the sole guard
against stale numbers.

Make setup and loading code visible so posts are reproducible from the
database. The `setup` chunk keeps `output: false`, `message: false`,
`warning: false` (code shows, library and connection noise suppressed); other
previously-hidden chunks (`registry`, `load`, `*-compute`, `teardown`, and the
hub pages' loaders) become `output: false` so their code shows but nothing
prints. Figure and table chunks were already echoed and are unchanged.

`AGENTS.md` and `vignettes/_post-template.qmd` are updated to match.

Alternative considered: keep the pins but recompute them on every refresh.
Rejected because it reintroduces the same brittle coupling and the inline
variables already carry the values.

## Hypotheses / expectations

- `altdoc::render_docs()` completes through a routine data refresh without a
  pin-driven abort, because no prose number is hard-coded.
- A reader can reconstruct any exhibit from the shown setup/load code plus the
  database, improving reproducibility.

## Consequences

- We lose the build-time tripwire that a stated number changed. With
  `freeze: auto`, a pure data refresh does not re-execute an unchanged post
  anyway, so the practical exposure is limited to posts whose source changes;
  the inline-variable rule is what keeps the deployed text correct.
- Setup code (package load shim, DuckDB connection, girafe defaults) now
  appears on every post. This is accepted as the cost of reproducibility.
- New posts inherit the behavior from the template.

## Outcome / what we learned

_Filled in later._

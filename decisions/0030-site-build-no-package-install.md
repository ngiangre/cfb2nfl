# 0030 — Site build does not require an installed cfbstats package

- **Status:** Accepted
- **Date:** 2026-10-18

## Context

`altdoc::render_docs()` converts man pages to `.qmd` and injects
`library("cfbstats")` into any `@examples` chunk, and the vignettes called
`library(cfbstats)` in their setup chunks. With no installed package (cfbstats
is not on CRAN and the site build should work from a fresh checkout, as
`site.yaml` does), the render aborted: `there is no package called 'cfbstats'`
in `man/stat_taxonomy.qmd`, the only man pages with executable examples.

## Decision

- Vignettes load the package from source: if `cfbstats` is not installed, the
  setup chunk finds the repo root (walk up for `_targets`) and sources every
  `R/*.R`. `app_sys()` already falls back to `getwd()/inst`, and
  `data.qmd` now reads dictionaries via `file.path(root, "inst", "dict")`
  instead of `system.file()`.
- The two roxygen examples (`stat_taxonomy`, `conference_tier_levels`) are
  wrapped in `\dontrun{}`: altdoc's Rd converter emits `eval=FALSE` for
  examples it detects as not-run (`\donttest` is NOT detected — deparsed
  example code loses the wrapper).

Alternatives rejected: installing the package in CI before rendering (extra
step, hides the coupling); patching altdoc output (overwritten each render).

## Hypotheses / expectations

`render_docs()` succeeds in an environment where cfbstats is not installed;
rendered pages are unchanged in content.

## Consequences

Site rendering depends only on the package's CRAN dependencies being installed,
not on cfbstats itself. Vignette setup chunks carry a ~8-line shim (duplicated,
self-contained by design — altdoc copies only `.qmd` files into `_quarto/`).
Examples in man pages render as display code, not executed.

## Outcome / what we learned

Confirmed: uninstalled cfbstats locally and `altdoc::render_docs()` completed
("Documentation updated") with all 10 vignette pages and 121 man pages built.
One gotcha: altdoc does not always re-copy changed vignettes into `_quarto/`;
stale copies must be cleared (or the file diff verified) after editing.

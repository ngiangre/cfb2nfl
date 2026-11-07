# 0042 — The repo is never installed: load it from the checkout with pkgload

- **Status:** Accepted (supersedes 0030)
- **Date:** 2026-11-07

## Context

Decision 0030 made the site build work without an installed package: vignettes
sourced `R/*.R` from the checkout when `cfb2nfl` was missing. Since then three
loading styles coexisted. Dated posts called `pkgload::load_all()`; the index
pages (`pipeline`, `visualizations`, `reference`, `investigations`) attached
an installed `cfb2nfl` if present and otherwise sourced `R/*.R`; and the site
and data workflows installed the package (`local::.`) anyway.

The installed copy caused a real bug. `app_sys()` resolved `inst/` through
`system.file(package = "cfb2nfl")`, which under `tar_make()` (plain
`tar_source()`, no pkgload shim) found the *installed* copy first. A stale
local install lacked newer dictionaries, so the DuckDB `_schema_manifest`
marked `player_game` as undocumented in a locally built bundle.

cfb2nfl is a research project laid out as a package for its tooling
(decision 0002), not a package anyone installs.

## Decision

- Never install cfb2nfl. `DESCRIPTION`/`NAMESPACE` stay, because pkgload,
  roxygen and `devtools::test()`/`check()` need them; `check.yaml` still
  builds the package for R CMD check as a conventions gate.
- Every vignette loads the code with one visible pattern:
  ```r
  root <- Sys.getenv("CFB2NFL_ROOT")
  if (!nzchar(root)) root <- pkgload::pkg_path()
  knitr::opts_knit$set(root.dir = root)
  pkgload::load_all(root, quiet = TRUE)
  ```
  `pkgload::pkg_path()` walks up to `DESCRIPTION`, replacing the hand-rolled
  walk-up loops and the exported `cfb2nfl_root()` helper (removed).
- `app_sys()` reads `getwd()/inst/...` first and only falls back to
  `system.file()` (pkgload's shim in tests), so an installed copy can never
  shadow the checkout.
- `site.yaml`, `data-current.yaml` and `data-refresh.yaml` drop `local::.`;
  they install the DESCRIPTION dependencies only.

Alternatives not taken: keeping `library(cfb2nfl)` with an install step (hides
the coupling and allows stale installs), and sourcing `R/*.R` directly (loses
pkgload's `system.file()` shim and namespace semantics).

## Hypotheses / expectations

- A fresh checkout renders the site and runs the pipeline without installing
  cfb2nfl.
- The `_schema_manifest` is fully documented whatever is (or is not) installed
  in the user library.

## Consequences

- Rendering a vignette needs pkgload (already a site dependency).
- Man-page `@examples` must stay `\dontrun{}`, as altdoc injects
  `library("cfb2nfl")` into them (unchanged from 0030).
- A leftover local install is harmless but can be removed with
  `remove.packages("cfb2nfl")`.

## Outcome / what we learned

_Filled in later._

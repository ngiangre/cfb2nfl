# cfbstats — agent guide

Project memory for AI assistants. Full rationale lives in [VISION.md](VISION.md)
and the [decision log](decisions/); read those before substantive changes.

`cfbstats` studies what shapes a college football player's path to the NFL
draft, and how well it can be **forecast** from information available during
their career — pursuing both explanatory (inference) and predictive answers
(Breiman's two cultures).

## Data

CFBD API (`https://api.collegefootballdata.com`); key in `CFBD_API_KEY`
(configured in the local environment and as a GitHub Actions repo secret, so
refresh runs both locally and in CI).
The **pipeline owns ingest → process → assets** (decision 0017): a single
`tar_make()` in **refresh mode** (`CFBSTATS_REFRESH=true`) ingests every source
(incl. `conference_tiers`, derived in-pipeline from `player_stats` by
`build_conference_tiers()`), processes it, and writes all assets (raw parquet +
`cfbstats.duckdb`). Default/**track mode** reads committed/downloaded parquet
with no API key (how the site build runs). `data-raw/refresh.R` is a thin
wrapper (`CFBSTATS_REFRESH=true` + `tar_make()`). Years 2010–2026.

| File | Grain | Key / notes |
|------|-------|-------------|
| `data/picks.parquet` | one drafted player | `collegeAthleteId` (int); position, height, weight, pre-draft ranking, hometown |
| `data/player_stats.parquet` | **long**: player-season-stat | `playerId` (string); pivot `category`/`statType`/`stat` |
| `data/coaches.parquet` | one head-coach-season | head coaches only |
| `data/roster.parquet` | one player-season on a roster | `id`→`playerId` (string) + `season`; physicals/position/hometown. Weight is **static** per player (decision 0009) |
| `data/teams.parquet` | one team (program) | join by school **name** (`team`); logos/colors, DISPLAY only (decision 0008) |
| `data/conference_tiers.parquet` | season × conference | tier 3 Power / 2 G5 / 1 FCS-and-below (decision 0003) |
| `data/recruiting.parquet` | one HS recruit | CFBD `athleteId`; `stars`/`rating`/`ranking`. Id is an **untrusted** namespace — join only via the name guard (decision 0013) |
| `data/nfl_draft_picks.parquet` | one NFL draft pick | nflverse; key `(season, round, pick)`. Bridge to `gsis_id`/`pfr_player_id` + PFR career summary (decision 0014) |
| `data/nfl_rosters.parquet` | one player-season on an NFL roster | nflverse; key `(gsis_id, season)`. Longevity source: distinct roster seasons |
| `data/nfl_player_stats.parquet` | one player-season (regular season) | nflverse; key `(gsis_id, season)`. Weekly stats aggregated to season totals |

### Gotchas (do not ignore)

- **`data/` is gitignored — NO parquet is tracked in git.** Do **not** `git add`
  or commit `data/*.parquet` (a `git status` won't even show it). The **cleaned**
  tables (parquet == DuckDB == dict schema, decision 0018) ship as assets on the
  **`data-latest` GitHub release**: the `data-refresh.yaml`
  job runs `tar_make()` in refresh mode (writes `data/*.{parquet,duckdb}`) then
  `piggyback::pb_upload(..., tag="data-latest")`; `site.yaml` does
  `piggyback::pb_download(tag="data-latest")` on a fresh checkout and runs
  `tar_make()` in track mode. Adding a new table means: add its `ingest_*()`, a
  `parquet_asset()` `*_file` target + `raw_*` reader in `_targets.R`, and publish
  it (run the refresh) **before** merging — otherwise a fresh track-mode CI/site
  build can't find it and the `*_file` target errors.
- **Player key = athlete id.** `player_stats.playerId`, `roster.id`, and
  `picks.collegeAthleteId` (coerce int→string) are one namespace — join on it,
  not name. ~98–100% of picks from draft year 2013 on carry an id (decision 0003).
- **Stats are long**, not wide — feature building requires pivoting.
- **Watch for silent row loss on joins.** Validate row counts before/after.
- **Coaches are head coaches only** (no coordinators/S&C). Coach *changes*
  between seasons are v1 features derived from `coaches.parquet`.
- **v1 change features** (decision 0003) — transfers + direction (via the
  season-aware tier lookup) and coaching changes — require linking a player's
  seasons chronologically by athlete id. **No between-season `weight_delta`:**
  CFBD `/roster` reports a *static* weight per player (0 of 64,350 multi-season
  players vary), so only the static `weight` is attached (decision 0009).
  `clean_roster` coerces a placeholder `weight` of `0` to `NA`; the roster
  contract enforces a 100–500 lb range (decision 0009).
- **Conference tiers are season-aware** (Pac-12 collapse, Big East → AAC, WAC
  dropping FBS football); use the lookup, don't hard-code. Built in-pipeline by
  `build_conference_tiers(player_stats)` (decision 0017) — a pure function of the
  ingested stats, so a new conference defaults to tier 1 and is caught by the
  coverage contract rather than silently dropped.
- **NFL outcomes bridge on draft slot, NOT `nflAthleteId`.** CFBD
  `picks.nflAthleteId` is its own namespace (0/4,350 match nflverse `espn_id`).
  Link CFBD picks to nflverse via `link_nfl_draft()` — draft slot
  `(year, round, overall)` == `(season, round, pick)` — behind a name guard;
  `gsis_id` is then the key across `nfl_rosters`/`nfl_player_stats`. NFL data is
  an **outcome/label**, kept off the model input path (leakage). "How long they
  last" = distinct roster seasons (primary), plus career games / last season;
  **right-censored** for recent classes. `load_player_stats()` errors on a
  future season, so its ingest clamps to `<= most_recent_season()` (no 2026
  stats yet). nflverse needs **no API key** (decision 0014).
- **Recruiting `athleteId` is NOT the shared namespace.** Unlike
  `collegeAthleteId`/`roster.id`, the `/recruiting/players` `athleteId` collides
  across different people (e.g. Cam Ward's id → a different recruit, Xavier
  Ward). Never join recruiting on id alone — go through `link_recruiting()`,
  which name-guards the join and nulls wrong-person ratings (decision 0013).
  Genuinely unranked players (Cam Ward) are simply absent; model "unrated" as a
  real category, don't impute.

## How we work

- **Population/outcome (v1):** outcome = drafted; denominator = players with a
  stat line, in **draft-eligible seasons**.
- **Evaluation:** out-of-time validation — a model never sees data from on/after
  the draft class it predicts. Guard against leakage.
- **Contracts + TDD:** test logic (`testthat`) and data (`pointblank`: expected
  coverage, schema stability, value ranges, no silent join loss); run in the
  pipeline, fail fast. Add/update a contract with any data-touching code.
- **Plans:** multi-session work plans live in `plans/*.md` (e.g.
  `plans/explore-questions.md` — the question-driven Explore revision).
  `decisions/` is for ratified choices only.
- **Decision log:** record substantive decisions in `decisions/` (copy
  `TEMPLATE.md`, next number); distill spike-branch findings into an entry.
  Decisions 0004–0006 cover `targets`, the lineage/audit layer, and the site.

## Pipeline, lineage & site (in place)

- **`_targets.R`** is the pipeline and single source of truth for the DAG
  (decision 0004). Stages: **ingest → clean → link → features → model →
  report**. Functions live in `R/` by stage: `ingest.R`, `clean.R`, `link.R`,
  `features.R`, `model.R` (placeholder), `contracts.R`, `audit.R`, `viz.R`.
  Ingest is env-gated (decisions 0017-0018): `raw_*` targets ingest **in memory**
  in refresh mode only (`if (refresh_enabled()) ingest_*()`, NULL in track mode).
  Each `<table>_file` (`format="file"`, `cue="always"`) is the published
  **cleaned** parquet via `parquet_asset(path, \() clean_*(raw_*))` — refresh
  cleans+writes, track mode tracks the existing/downloaded file (no key, no
  re-clean); `<table>` then reads that cleaned parquet. So **parquet == DuckDB ==
  dict schema** (decision 0018). `conference_tiers` derives from the cleaned
  `player_stats` via `build_conference_tiers()` (`R/conference_tiers.R`).
- **Lineage/audit** (decision 0005): `audit_step()` emits a uniform per-step
  record (row/col counts, rows dropped, key coverage, NA cells, schema hash,
  contract pass/fail, git SHA) → the `audit_log` target. Data dictionaries in
  `inst/dict/*.yml`. Known audit signals: `build_player_season` collapses the
  long stats (~1.2M → ~144k rows); `link_coaches` inflates rows where a school
  had >1 head coach in a season (intentional many-to-many).
- **Site** (decision 0006): **`altdoc` owns the site** (`quarto_website`),
  configured in `altdoc/quarto_website.yml`, built to `docs/` via
  `altdoc::render_docs()`. Navigation lives entirely in the top **navbar**
  (no sidebar): Home, Explore, Blog, Reference on the left; News/License/
  Citation + GitHub on the right (`$ALTDOC_*` placeholders substitute fine in
  navbar, but `$ALTDOC_VIGNETTE_BLOCK`/`$ALTDOC_MAN_BLOCK` only expand in the
  sidebar in altdoc 0.7.3, so the pages are hand-wired instead). Content pages
  are vignettes: `explore.qmd` is a hub of bslib value-card tiles linking to
  `about`, `analysis`, `data`, `visualizations` (the interactive charts,
  renamed from the old explore page), and `pipeline`; `blog.qmd` builds a
  reactable table of all dated posts (`YYYY-MM-DD-*.qmd`) from their YAML at
  render time; `reference.qmd` builds a searchable reactable of every
  non-internal function linking to `../man/<fn>.html` (75 rendered man pages).
  Vignettes read the pipeline via `tar_read()` and set the knit wd to the
  project root from the `CFBSTATS_ROOT` env var
  (altdoc renders in a temp dir); they use `library(cfbstats)` and
  `system.file("dict", ...)`, so the package must be installed to render.
  Viz is hybrid: R htmlwidgets default (`plotly`/`ggiraph`/`reactable`),
  OJS later. `vignettes/` is `.Rbuildignore`d (they need the pipeline/data,
  not CRAN).
- **Figure styling standard.** Leverage **team colors consistently** across
  figures (source them from `data/teams.parquet`, which carries logos/colors —
  DISPLAY only, decision 0008 — via a shared team → color mapping, not
  hard-coded hexes). All figures use **large, accessible fonts/text**. Save a
  **reusable ggplot2 theme object** (plus the team color scale) in `R/viz.R` and
  apply it everywhere rather than re-theming per plot. TODO: create that theme
  helper.
- **Blog posts** (decision 0015): dated files `vignettes/YYYY-MM-DD-slug.qmd`,
  `freeze: true` + committed `_freeze/` so they don't rebreak on data refresh;
  key on athlete id; start from `vignettes/_post-template.qmd`.
- **CI** (`.github/workflows/`): `check.yaml` (R CMD check + testthat + contract
  fixtures), `site.yaml` (pull data release asset → `tar_make()` → render →
  Pages), `data-refresh.yaml` (scheduled refresh-mode `tar_make()` → publish
  `*.{parquet,duckdb}` via `piggyback`). Refresh needs `CFBD_API_KEY`; the site
  build runs in track mode (no key) and needs Pages enabled.
- **DuckDB query asset** (decision 0016): `build_duckdb()` (`R/duckdb.R`) bundles
  the **cleaned** tables into `data/cfbstats.duckdb`, built by the `duckdb_file`
  target (`format = "file"`, downstream of clean) so its schema matches the
  dicts. Published on `data-latest` alongside the parquet by the single
  refresh-mode `tar_make()` (decision 0017), then uploaded as
  `*.{parquet,duckdb}`. Model map + join namespaces documented in
  `inst/data-model.md` (links each table to `inst/dict/*.yml`). New tables must
  be added to the `duckdb_file` table list and to `inst/data-model.md`.
- **Roster is a first-class target** (`roster_file` → `raw_roster` → `roster`,
  decision 0009): `data/roster.parquet` is ingested by `refresh.R`, published on
  the `data-latest` release, and read like the other tables. `add_roster_weight`
  attaches the static `weight` (~81% coverage). No `weight_delta` (see above).

## Conventions & stack

- R + tidyverse; base pipe `|>` (not `%>%`); `arrow` for parquet I/O and
  lazy/`collect()` pipelines. Comments brief and about *why*. Match scope.
- Developed as an R package (`devtools`: `load_all`/`document`/`test`/`check`);
  reusable logic in `R/` with roxygen. `check()` is a conventions gate, not CRAN
  prep — non-package material is `.Rbuildignore`d (decision 0002). `check()` is
  currently clean (0 errors/warnings/notes).

## Git

Solo repo. `main` always deployable; short-lived `feat/`/`data/`/`model/`
branches; **squash-merge** for a linear history; throwaway `spike/` branches
never merged. Conventional Commits (`type(scope): summary`). Let CI (testthat +
pointblank) pass before merging data/model changes.

**GitHub API ops use the `gh` R package, not the `gh` CLI.** The `gh` R package
authenticates with a token already saved in the environment (the CLI is not
logged in). Use it for PRs, merges, and dispatching workflows, e.g.
`gh::gh("POST /repos/{owner}/{repo}/pulls", ...)`,
`gh::gh("PUT /repos/{owner}/{repo}/pulls/{n}/merge", merge_method = "squash")`,
`gh::gh("POST /repos/{owner}/{repo}/actions/workflows/{file}/dispatches", ref = ...)`. **Before merging a feature
branch into `main`, update `NEWS.md`** with the user-facing changes (linking any
relevant decision record via full GitHub URL) — an empty changelog entry is a
smell, and R CMD check flags a NEWS with no entries (decision 0007).

**Formatting is enforced by CI** (`format-check.yaml` runs `air format . --check`)
but is **not** part of `devtools::check()`. Run `air format .` before pushing, or
enable the tracked pre-commit hook once per clone: `git config core.hooksPath
.githooks` (it mirrors the CI check; skips gracefully if `air` isn't on PATH).

# cfb2nfl — agent guide

Project memory for AI assistants. Full rationale lives in [VISION.md](VISION.md)
and the [decision log](decisions/); read those before substantive changes.

`cfb2nfl` studies what shapes a college football player's path to the NFL
draft, and how well it can be **forecast** from information available during
their career — pursuing both explanatory (inference) and predictive answers
(Breiman's two cultures).

## Data

CFBD API (`https://api.collegefootballdata.com`); key in `CFBD_API_KEY`
(configured in the local environment and as a GitHub Actions repo secret, so
refresh runs both locally and in CI). All CFBD calls funnel through
`cfbd_get()`/`cfbd_request()` in `R/ingest.R`, which retries transient
failures (429/5xx) with exponential backoff — 5 tries, max 2 min per call
(decision 0028). CFBD 503s are common under the refresh's ~60-call burst,
especially from shared GitHub-runner IPs; if CI refresh still fails, the
fallback is running `Rscript data-raw/refresh.R` locally (~10 min, works
because the local IP isn't throttled) and publishing with the same
`piggyback::pb_upload(..., tag="data-latest", overwrite = TRUE)` the CI job
runs, then re-dispatching `site.yaml`. **Quota:** the key is tier-limited
(5000 calls/month as of 2026-10-17; the free 1000/month tier was exhausted by
the game-stats sweep — see `plans/game-stats.md`). A full refresh costs ~780 calls
calls: the `/games` family ingests (`games`, `game_team_stats`,
`game_player_stats`) pace themselves at 1 call/2 s with a 10-try/600 s retry
budget (`cfbd_game_get()`); don't re-run a failed refresh without first
working out what it would re-pull.
The **pipeline owns ingest → process → assets** (decision 0017): a single
`tar_make()` in **refresh mode** (`CFB2NFL_REFRESH=true`) ingests every source
(incl. `conference_tiers`, derived in-pipeline from `player_stats` by
`build_conference_tiers()`), processes it, and writes all assets (raw parquet +
`cfb2nfl.duckdb`). Default/**track mode** reads committed/downloaded parquet
with no API key (how the site build runs). `data-raw/refresh.R` is a thin
wrapper (`CFB2NFL_REFRESH=true` + `tar_make()`). Years 2010–2026.

| File | Grain | Key / notes |
|------|-------|-------------|
| `data/picks.parquet` | one NFL draft pick | key `(year, round, pick)`; `collegeAthleteId` (int) is **not** unique (id reuse, decision 0022) and is absent before ~2004; position, height, weight, pre-draft ranking, hometown |
| `data/player_stats.parquet` | **long**: player-season-stat | `playerId` (string); pivot `category`/`statType`/`stat` |
| `data/coaches.parquet` | one head-coach-season | head coaches only |
| `data/roster.parquet` | one player-season on a roster | `id`→`playerId` (string) + `season`; physicals/position/hometown. Weight is **static** per player (decision 0009) |
| `data/teams.parquet` | one team (program) | join by school **name** (`team`); logos/colors, DISPLAY only (decision 0008) |
| `data/conference_tiers.parquet` | season × conference | tier 3 Power / 2 G5 / 1 FCS-and-below (decision 0003) |
| `data/recruiting.parquet` | one HS recruit | CFBD `athleteId`; `stars`/`rating`/`ranking`. Id is an **untrusted** namespace — join only via the name guard (decision 0013) |
| `data/nfl_draft_picks.parquet` | one NFL draft pick | nflverse; key `(season, round, pick)`. Bridge to `gsis_id`/`pfr_player_id` + PFR career summary (decision 0014) |
| `data/nfl_rosters.parquet` | one player-season on an NFL roster | nflverse; key `(gsis_id, season)`. Longevity source: distinct roster seasons |
| `data/nfl_player_stats.parquet` | one player-season (regular season) | nflverse; key `(gsis_id, season)`. Weekly stats aggregated to season totals |
| `data/outcomes.parquet` | one player-season in the model population (person-period) | **The modeling dependent variables** (decision 0032): eligibility clock (`hs_grad_year`, `draft_eligible`, `eligible_season_index`), `outcome_*` labels (drafted, NFL entry, entry-year success), survival bookkeeping. Contract `contract_outcomes()` |

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
  `clean_roster` coerces any `weight` outside the plausible 100–500 lb range
  to `NA` (0 placeholder + data-entry errors like 23 lb); the roster contract
  enforces the same range (decision 0009).
- **CFBD athlete ids are recycled across individuals over long spans**
  (decision 0022): ~131 roster ids (0.1%) have a first-to-last-season span
  > 7 — one id, one name, two-plus real people. `reused_ids()` flags them;
  `career_summary(max_span = 7L)` and the `ps_pop` target exclude them from
  the career/model populations. The id remains a stable key within a
  plausible career window.
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
- **CFBD API coverage is documented in `inst/cfbd-api-coverage.md`** (snapshot
  of OpenAPI 5.33.0): every endpoint's grain, key attributes, join namespaces,
  gating (Patreon tiers), and fan-out cost caveats. Consult it to answer
  "can we get X?" before planning any new ingest. The key is **Patreon
  level 1** — the gated `adjustedMetrics` endpoints (`/wepa/*`,
  `/games/{id}/preview/adjusted`) are available; verify with `GET /info`.

## How we work

- **Population/outcome (v1):** outcome = drafted; denominator = players with a
  stat line, in **draft-eligible seasons**.
- **Evaluation:** out-of-time validation — a model never sees data from on/after
  the draft class it predicts. Guard against leakage.
- **Contracts + TDD:** test logic (`testthat`) and data (`pointblank`: expected
  coverage, schema stability, value ranges, no silent join loss); run in the
  pipeline, fail fast — enforced by the `contract_gate` target (decision 0023):
  any `ok_* = FALSE` aborts `tar_make()`. Add/update a contract with any
  data-touching code.
- **Plans:** multi-session work plans live in `plans/*.md` (e.g.
  `plans/explore-questions.md` — the question-driven Explore revision).
  `decisions/` is for ratified choices only.
- **Blog style (decision 0025, revised):** posts are written in a research-article
  register — numbered Introduction / Data / Results / Summary / Discussion,
  no em dashes anywhere, no rhetorical framing phrases, and no pipeline
  internals (decision records, cleaning mechanics) in the narrative.
  **Titles** are one declarative sentence — subject first, then the observed
  takeaway — never a colon-joined fragment pair ("blah: blah"). Keep `title:`
  and `%\VignetteIndexEntry{}` in sync.
  - **Snapshots, not tours.** A post shows particular snapshots of the data for
    its question, not everything the data contains about a topic. Cut any
    exhibit that serves completeness rather than the argument.
  - **A sentence or two per section; exhibits carry the picture.** Each
    section heading is a numbered **assertion** (`### 3.1 <claim>`, a claim
    the section demonstrates). The body is **one or two sentences** saying
    what the exhibits below show and why they are there, and nothing more:
    any further detail moves into a table, a figure annotation, or a caption.
    The prose is then followed by its supporting exhibits, in this order:
    1. **Table** (`knitr::kable`, captioned): expository, it defines and
       counts the data the claim rests on.
    2. **Explanatory figure**: makes the section's claim at a glance; the
       claim's element is highlighted (color, annotation, arrow) and the
       rest is context.
    3. **Exploratory figure**: an interactive `ggiraph` view of the same
       snapshot at finer grain (every category, season, or player behind the
       claim) with hover tooltips carrying the full detail, so the reader can
       probe beyond the claim without leaving the question.
    Data sections need at least the table; every Results section carries all
    three unless the claim is a single fact (then table plus one figure). A
    Results section that tests an expectation states it first, italicized,
    with its verdict emoji (`*Expectation: ...* ✅`), and the one or two
    sentences follow. The skeleton lives in `vignettes/_post-template.qmd`.
  - **Flow.** The post must read as one argument from beginning to end: each
    section's assertion should follow from the previous section's exhibits, so
    a reader can reconstruct the takeaway from headings and exhibits alone.
  - Still: `stopifnot()` where a claim could silently rot; code chunks back
    every exhibit. Start from `vignettes/_post-template.qmd`; every dated
    post follows this format (revised 2026-10-31).
- **Vignette writing critiques (user review of the 2026-10-24 outcome
  prevalence post, applied going forward):**
  - Define every variable and term in the narrative (person-season, eligible
    season, round groups, status categories, hazard); readers do not know
    column names like `outcome_drafted_d` or codes like `r2_3`. Display
    reader-facing labels, not raw column values, in figures and tables.
  - Keep implementation messages (e.g. DuckDB connection) out of the reader's
    view: `include: false` for loading chunks.
  - Render every vector/data-frame output with `knitr::kable` (with a
    caption), never a bare tibble print.
  - Introduce any statistical machinery in plain language before use (e.g.
    "a confidence interval is the range the true rate plausibly occupies"),
    naming the method (Wilson) only after the concept.
  - No pie charts; use ordered horizontal `geom_col_interactive` bars.
  - Avoid authoritative over-interpretation ("the failure is structural");
    state what happened and the mechanism as explanation, not verdict.
  - Verdict emojis (✅ holds / ❌ does not hold) are welcome after each
    expectation statement, used sparingly and only there.
  - Write for fans who love the game and want the answers: deductive framing
    ("out of every 100 eligible seasons ...") and named player examples
    (prefer the recurring cast of earlier vignettes: Burrow, Cam Ward, Jordan
    Travis, Buechele, Kyle Allen), with example facts verified in the data
    and pinned by `stopifnot()`.
  - Discussion is callouts (`callout-important`) plus a short caveats
    paragraph, not prose blocks.
  - **Authorship:** vignette `author:` is "AI directed by Nick Giangreco"
    unless the user says otherwise.
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
  project root from the `CFB2NFL_ROOT` env var
  (altdoc renders in a temp dir); they do NOT require an installed cfb2nfl
  package — setup chunks source `R/*.R` from the checkout when the package is
  missing, and dicts are read via `file.path(root, "inst", "dict")` (decision
  0030). altdoc injects `library("cfb2nfl")` into man-page `@examples`, so
  examples must be `\dontrun{}`-wrapped to render unexecuted (`\donttest` is
  NOT detected by altdoc's converter). altdoc may not re-copy edited vignettes
  into `_quarto/` — clear stale copies if a render keeps old code.
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
  each YAML carrying `description:` (one declarative sentence stating the
  finding, not the topic) and `followups:` (list of open questions / next
  analyses informing later investigations and pipeline work); displayed in the
  `blog.qmd` index table and grep-able across `vignettes/`,
  `freeze: auto` + committed `_freeze/` so they don't rebreak on data refresh
  while source edits still propagate (`freeze: true` serves the cache even
  after edits — caused stale deployed titles, fixed 2026-10-24); the `blog`/
  `reference` index pages' freeze caches are deleted in `site.yaml` because
  their knit-time reads of other files' YAML are invisible to Quarto's cache
  check; key on athlete id; start from `vignettes/_post-template.qmd`.
- **CI** (`.github/workflows/`): `check.yaml` (R CMD check + testthat + contract
  fixtures), `site.yaml` (pull data release asset → `tar_make()` → render →
  Pages), `data-refresh.yaml` (scheduled refresh-mode `tar_make()` → publish
  `*.{parquet,duckdb}` via `piggyback`). Refresh needs `CFBD_API_KEY`; the site
  build runs in track mode (no key) and needs Pages enabled.
- **DuckDB query asset** (decision 0016): `build_duckdb()` (`R/duckdb.R`) bundles
  the **cleaned** tables into `data/cfb2nfl.duckdb`, built by the `duckdb_file`
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

# cfbstats 0.0.0.9000 (development version)

- The blog post "Seven quarterbacks, one database" now defines redshirt flags
  from game-level usage in the `game_player_stats` table (at most one game with
  a recorded statistic among covered games, observable positions only) instead
  of stat presence, reports a per-player redshirt verdict against each
  expectation, and trims the narrative.
- All rendered site pages now expose Quarto code tools (source toggle) via
  `code-tools: true` in the site format.

- Fix a site-build failure with two causes: the pipeline's `week_grid` target
  now derives its (season, seasonType, week) grid from the cleaned `games`
  table, which exists in both refresh and track modes, instead of the
  ingest-mode-only `raw_games` (NULL in track mode, which aborted
  `tar_make()`); and the content vignettes now attach the installed cfbstats
  package in their setup chunk, so `cfbstats_root()` resolves in the fresh
  quarto R session (previously only sourced from the checkout when the package
  was absent).

- The documentation site no longer requires the cfbstats package to be
  installed: vignette setup chunks source `R/*.R` from the checkout when the
  package is missing, and man-page examples render unexecuted
  ([decision 0030](https://github.com/ngiangre/cfbstats/blob/main/decisions/0030-site-build-no-package-install.md)).
- The ERD on the Data page is now rendered live from mermaid (mirroring
  `inst/data-model.md`) instead of a pre-rendered PNG that had drifted behind
  the new `games`, `game_team_stats`, and `game_player_stats` tables.
- `inst/data-model.md` fixes: the join-namespace count is six (the CFBD game id
  namespace was added without updating the count) and a duplicated
  `nfl_draft_picks ||--o{ nfl_rosters` edge was removed.

- The `/games` family ingest is now dynamically branched in the pipeline
  (one target branch per API call, decision 0029): an interrupted refresh
  resumes at the first un-ingested season/week instead of re-pulling the whole
  ~1,150-call sweep. Combined tables keep the same grain, so all downstream
  targets and published assets are unchanged.

First tracked release of the project scaffolding. The repo now carries the full
ingest → clean → link → features → model → report pipeline, its lineage/audit
layer, and the documentation site, all under version control.

- New game-statistics tables from the CFBD `/games` family: `games` (one row
  per game), `game_team_stats` (team-game-category-stat), and
  `game_player_stats` (player-game-category-statType-stat). All long-grain;
  `game_player_stats.playerId` joins the shared athlete-id namespace directly.
  Ships with contracts, dictionaries (`inst/dict/games*.yml`), DuckDB bundle
  membership, and data-model documentation.
- The pipeline no longer re-ingests on every run: ingest and parquet-asset
  targets track normally, and `data-raw/refresh.R` invalidates all targets
  before an explicit full refresh. New `data-raw/pull-data.R` downloads the
  latest cleaned data from the `data-latest` release so local track-mode work
  needs no CFBD API key or quota.

- New `app.R`: a Shiny app powered by
  [querychat](https://posit-dev.github.io/querychat/) for natural-language
  querying of the DuckDB bundle. All tables (plus the `player_season_inputs`
  view) are registered for cross-table SQL joins, the `inst/dict/*.yml` data
  dictionaries and the join-key rules from `inst/data-model.md` are provided as
  LLM context, and an explicit greeting avoids the single-table auto-greeting
  pitfall.

- The DuckDB bundle now carries a wide `player_season_stats` table (one row per
  player-season-team, one numeric column per `(category, statType)` pair) so
  SQL users no longer pivot the 1.5M-row long `player_stats` by hand
  ([decision 0026](https://github.com/ngiangre/cfbstats/blob/main/decisions/0026-wide-player-season-stats-duckdb.md)).
- The drafted-rate-by-tier example query in `inst/data-model.md` is corrected to
  aggregate the long stats to player-season grain before joining (the old query
  counted stat lines, not players).
- The DuckDB bundle is now self-documenting and self-checking
  ([decision 0027](https://github.com/ngiangre/cfbstats/blob/main/decisions/0027-duckdb-queryability-batch.md)):
  a name-guarded `nfl_pick_link` bridge to the NFL tables, a queryable slimmed
  `audit_log`, a generated `_schema_manifest` (grain/key from the
  dictionaries), a `_meta` row recording the last complete season/draft class,
  and a leakage-safe `player_season_inputs` view.
- Out-of-range roster heights (outside 60-85 inches) are coerced to NA and the
  roster contract now covers height, mirroring the weight precedent.
- CFBD ingest requests retry transient failures (429/5xx) with exponential
  backoff, so a temporary API outage or rate-limit window no longer fails the
  whole weekly refresh
  ([decision 0028](https://github.com/ngiangre/cfbstats/blob/main/decisions/0028-cfbd-retry-backoff.md)).

- The expectation-check blog post is revised into a research-article structure
  (Introduction, Data, Results, Summary, Discussion) with neutral scientific
  phrasing and corrected observations re-verified against the published data;
  the class-year audit section was removed in favor of the fix recorded in
  [decision 0024](https://github.com/ngiangre/cfbstats/blob/main/decisions/0024-class-year-coercion-and-fifth-year-flag.md).

- The roster backbone is now guarded against two defects surfaced by the
  expectation-check blog post
  ([decision 0024](https://github.com/ngiangre/cfbstats/blob/main/decisions/0024-class-year-coercion-and-fifth-year-flag.md)).
  `clean_roster()` coerces `class_year` outside the plausible 1-5 eligibility
  range to `NA` — older CFBD seasons return the queried *year* in the
  eligibility-class field (~124k rows, pre-2020) — so the derived
  `fifth_year_career` flag now measures *observed* fifth-year classes instead
  of a year-value coincidence. `contract_roster()` adds two checks:
  `(playerId, season, team)` key uniqueness (a player on two teams within one
  season stays allowed) and the `class_year` range, so future contamination
  blocks the build via the contract gate rather than publishing. The data
  was refreshed and re-published on the `data-latest` release to satisfy the
  new contract.

- The audit log is now interpretable and enforced. `audit_step()` records
  **join coverage** (`pct_keys_matched`, `keys_dropped` — distinct key
  combinations from the input that vanish, separating filtering from join
  fan-out), **per-column NA accounting** (`n_cols_with_na` plus a `na_by_col`
  profile attributing sparsity to columns), and a **schema history**:
  `update_schema_history()` appends each run's per-step hashes to
  `data/audit_history.csv`, carried across refreshes as a `data-latest` release
  asset, so `schema_hash` drift between refreshes is detectable. The Data &
  provenance page renders the new columns and the history. Data contracts now
  **block the build**: a new `contract_gate` target aborts `tar_make()` when
  any `ok_*` check fails, so failing data never publishes ([decision 0023](
  https://github.com/ngiangre/cfbstats/blob/main/decisions/0023-contract-gate-blocks-build.md)).
  New contracts cover every model-path link/features step (coach link fan-out,
  tier link, reused-id filter, change features, roster weight, recruiting
  link, player-season uniqueness), and the audit's key declarations were
  corrected (`clean_picks` keys on the draft slot; mid-season transfers are
  distinct rows at `(playerId, season, team)`). CFBD athlete-id reuse is
  handled explicitly ([decision 0022](
  https://github.com/ngiangre/cfbstats/blob/main/decisions/0022-cfbd-athlete-id-reuse.md)):
  `reused_ids()` flags ids spanning implausible career windows (> 7 seasons),
  `career_summary(max_span = 7L)` drops them, and a `ps_pop` target filters the
  model population.

- The Data & provenance page now embeds the entity-relationship diagram as a
  pre-rendered image (`vignettes/images/erd.png`) instead of a raw mermaid
  block, so it renders identically without client-side mermaid. The diagram's
  source of truth remains the hand-authored mermaid block in
  `inst/data-model.md`.

- The Explore hub page tiles now use a responsive fenced-div card grid
  (equal-width, whole-tile links) instead of `bslib::layout_columns()`, whose
  Bootstrap grid classes are absent from Quarto's pruned Bootstrap build and
  previously collapsed the tiles.

## Pipeline & data

- Derived feature tables are now **first-class pipeline targets** bundled into
  the DuckDB asset and documented in the data model ([decision 0021](
  https://github.com/ngiangre/cfbstats/blob/main/decisions/0021-derived-feature-tables-in-pipeline.md)).
  `career_summary(roster)` (`career` target), `flag_redshirt(roster,
  player_stats)` (`roster_flags` target), and the existing `ps_change` backbone
  carry contracts and audit rows like the cleaned tables, ship in
  `data/cfbstats.duckdb` with new dictionaries (`inst/dict/*.yml`) and ERD
  entries, and are **not** published as standalone parquet (they rebuild from
  other cleaned tables in any mode, so no release asset is needed before a
  track-mode build). `player_dossier()` gains optional `career` /
  `roster_flags` arguments attaching a "Career & eligibility" section, and
  `explore.qmd` reads the targets instead of recomputing features per figure.

- The documentation site now navigates entirely through the top navbar
  (Home, Explore, Blog, Reference on the left; News/License/Citation + GitHub
  on the right) instead of a sidebar. New hand-wired pages: `explore.qmd` is a
  hub of value-card tiles linking to About, Analysis, Data & provenance,
  Visualizations, and Pipeline; `blog.qmd` lists dated posts in a table built
  from their YAML; `reference.qmd` lists every non-internal function with links
  to its man page. The interactive-charts page formerly called `explore.qmd`
  is renamed `visualizations.qmd`.

- Added the third Explore question-answer pair (question 12): **redshirts,
  defined approximately**. `flag_redshirt()` derives two redshirt-*shaped*
  signals from the roster backbone — a no-stat season the player returned from
  (stat-gap rule) and an observed fifth eligibility class — `contract_redshirt()`
  sanity-checks the flags, and `viz_redshirt_by_career_length()` /
  `viz_redshirt_seasonality()` plot them. The seasonality chart is a 100%
  stacked ledger per season — stat line recorded / redshirt-shaped gap /
  uninformative final-season gap — making the confound explicit: the source
  records stats for only ~26% of roster seasons in 2010 rising to ~60% by
  2021, so the redshirt-shaped share is an upper bound dominated by missing
  data in the early years. `explore.qmd` gains a "Redshirts" section; `scales`
  joins Imports.

- Added the second Explore question-answer pair (question 5): **transfers —
  how many, and in which direction**. `transfer_counts()` aggregates the
  existing `add_change_features()` team changes into season × tier-direction
  counts, `transfer_rate()` gives the career-grain share of players with at
  least one transfer (13.7% of 135,356 roster players), and
  `viz_transfers_by_season()` plots the stacked counts. `explore.qmd` gains a
  "Movement — transfers" section with undercount caveats (stat-line players
  only; moves to/from seasons with no roster row are invisible).

- Added the first Explore question-answer pair (Explore plan, question 4):
  **college career length**. `career_summary()` collapses the roster backbone
  to one row per player — seasons on a roster, first/last season, gap seasons,
  and transfer count — `contract_career_summary()` enforces the career-length
  bounds (1–7 seasons, non-negative gaps/transfers), and `viz_career_length()`
  plots the seasons-per-player distribution. `vignettes/explore.qmd` gains a
  "Career length" section with the roster-grain caveats (redshirt / medical /
  COVID years are not separable at this grain; that disambiguation is the
  later redshirt question).
- Fixed vignette rendering outside altdoc: vignettes now resolve the project
  root via `cfbstats_root()`, which falls back to walking up to the nearest
  `_targets` store when `CFBSTATS_ROOT` is unset, so a direct `quarto preview`
  no longer fails with "targets data store _targets not found".

- Added a **stat-phase taxonomy** and an **interpretable player dossier** so a
  reviewer gets *interpretation*, not a raw extract (decision 0019). The long
  `player_stats` already tags each stat with a `category`, but a flattened
  extract loses it; the new `stat_taxonomy()` (hand-authored package data in
  `inst/extdata/stat_taxonomy.csv`, materialized into the DuckDB bundle) maps
  every `(category, statType)` to a game **phase** (offense / defense /
  special_teams), a plain-language `label`, and a `kind`, so a bare `TD` becomes
  "Passing touchdowns" vs "Defensive touchdowns". It is keyed at
  `(category, statType)` grain because `fumbles` is phase-ambiguous
  (`FUM`/`LOST` offense, `REC` defense); `label_stats()` applies it and
  `contract_stat_taxonomy()` fails fast if a refresh introduces an unlabeled
  stat. `resolve_nfl_outcome()` is the general college→NFL bridge — **drafted**
  via the reliable draft-slot bridge (decision 0014) or **undrafted-signed** via
  a name-guarded match against `nfl_rosters` (disambiguated by college then
  rookie-year window), refusing to guess on an unresolved name collision
  (`no-NFL-record`); it is enabled by adding `player_name` to
  `clean_nfl_rosters` (dict + `contract_nfl_rosters` updated) and stays
  outcome-side, off the model path. `player_dossier(id, …)` assembles a
  `cfb_dossier` (tidy tables + a `print()` method): identity, stats grouped and
  labeled by phase, per-player-season coaching with an explicit "head coach not
  available (non-FBS / not in CFBD feed)" flag, name-guarded recruiting (unrated
  stays unrated), the drafted/undrafted-signed outcome with right-censored
  longevity, and a provenance/caveats block. The Explore vignette renders an
  interpreted dossier (Cam Ward) so the site shows the extract, not raw rows.
  Validated on Kyle Allen (undrafted,
  9 NFL seasons) and Cam Ward (#1 overall 2025; 2021 Incarnate Word flagged as
  an FCS coach gap). Covered by `tests/testthat/test-stat-taxonomy.R`,
  `test-nfl-outcome.R`, and `test-dossier.R`. **`nfl_rosters` must be refreshed
  and republished on `data-latest` before merge** (schema change).
  See [decision 0019](https://github.com/ngiangre/cfbstats/blob/main/decisions/0019-stat-taxonomy-and-player-dossier.md).

- **Published parquet are now the cleaned tables** (decision 0018), so the
  `data/*.parquet` assets, the DuckDB bundle, and the data dictionaries all carry
  one identical schema per table. Ingest (`raw_*`) now happens in memory in
  refresh mode only; each `<table>_file` target writes the *cleaned* parquet and
  `<table>` reads it back, making the cleaned parquet the single source of truth
  downstream. Track-mode builds read the cleaned parquet directly (no re-clean,
  no key). See [decision 0018](https://github.com/ngiangre/cfbstats/blob/main/decisions/0018-cleaned-parquet-assets.md).

- **The `targets` pipeline now owns ingest → process → assets** (decision 0017).
  A single `tar_make()` in **refresh mode** (`CFBSTATS_REFRESH=true`) ingests
  every source — including `conference_tiers`, now derived in-pipeline from the
  ingested `player_stats` by the new `build_conference_tiers()` — processes it,
  and writes every data asset (raw parquet **and** `cfbstats.duckdb`) in one
  dependency-ordered pass. Ingestion is env-gated via `parquet_asset()`: refresh
  mode writes the parquet, the default **track mode** reads the
  committed/downloaded file with no API key (how the keyless site build runs).
  `data-raw/refresh.R` is now a thin wrapper and `data-raw/conference_tiers.R`
  is removed; the `data-refresh` workflow is a single `tar_make()` +
  publish-assets. See [decision 0017](https://github.com/ngiangre/cfbstats/blob/main/decisions/0017-pipeline-owns-ingest-and-assets.md).

- Added a **queryable DuckDB data asset** (`data/cfbstats.duckdb`) that bundles
  every cleaned, contract-checked table into one SQL-queryable file, built by the
  new `build_duckdb()` (`R/duckdb.R`) as the `duckdb_file` pipeline target
  (`format = "file"`, downstream of the clean stage) so its schema matches the
  data dictionaries. It is published alongside the parquet on the `data-latest`
  release: the `data-refresh` workflow pulls existing assets, ingests, runs
  `tar_make(duckdb_file)`, then uploads the parquet **and** the `.duckdb` file.
  Added `inst/data-model.md` — a Mermaid ERD plus the five join namespaces (and
  the two look-alike traps, `recruiting.playerId` and `picks.nflAthleteId`),
  leakage / out-of-time guidance, and example SQL — cross-linking each table to
  its `inst/dict/*.yml`. `DBI` and `duckdb` added to `Suggests`.
  See [decision 0016](https://github.com/ngiangre/cfbstats/blob/main/decisions/0016-duckdb-query-asset.md).

- Added **NFL outcomes for drafted players** from nflverse (`nflreadr`) as three
  first-class tables (`ingest_nfl_*()` → `clean_nfl_*()`, published on the
  `data-latest` release): `nfl_draft_picks` (the bridge + Pro-Football-Reference
  career summary), `nfl_rosters` (player-season roster presence — the longevity
  source), and `nfl_player_stats` (weekly stats aggregated to the player-season
  grain, regular season). `link_nfl_draft()` bridges CFBD `picks` to nflverse
  ids by **draft slot** — `(year, round, overall)` == `(season, round, pick)` —
  behind a normalized-name guard, because CFBD `nflAthleteId` is a *different*
  namespace (0 of 4,350 recent picks match nflverse `espn_id`) and name-only
  matching is collision-prone; the slot join matches ~97% of 2010+ picks after
  the guard. "How long they last" is defined primarily as **distinct NFL seasons
  on a roster**, complemented by career games and last active season — all
  **right-censored** for recent classes still active, so treat them as "≥"
  outcomes. NFL data is an *outcome/label* source, kept off the model input path
  (feeding it as a feature would be leakage). Enforcing the roster contract
  surfaced impossible weights (0/18/449/1794 lbs) coerced to `NA` (mirroring the
  CFBD roster placeholder handling), and 16 unattributed stat rows with a null
  `player_id` dropped. Guarded by `contract_nfl_draft_picks()` /
  `contract_nfl_rosters()` / `contract_nfl_player_stats()` / `contract_nfl_link()`,
  data dictionaries (`inst/dict/nfl_*.yml`, dict-parity test), and
  `tests/testthat/test-nfl.R`.
  See [decision 0014](https://github.com/ngiangre/cfbstats/blob/main/decisions/0014-nfl-outcomes-nflverse-link.md).
- Added **high-school recruiting ratings** as a first-class table
  (`ingest_recruiting()` → `data/recruiting.parquet`, published on the
  `data-latest` release): CFBD `stars`/`rating`/`ranking` per recruit.
  `clean_recruiting()` builds a per-athlete rating table and
  `link_recruiting()` attaches it to the player-season backbone behind a
  **normalized-name guard** — the recruiting `athleteId` is a *separate*
  namespace that collides across different people (Cam Ward's id maps to a
  different recruit, Xavier Ward), so a rating is trusted only when the recruit
  name agrees with the backbone name; wrong-person ratings are nulled and
  flagged by `recruit_matched`. Guarded, honest coverage of drafted players is
  ~60–72% for recent classes; genuinely unranked players (like Cam Ward) are
  absent by design. Guarded by `contract_recruiting()` (`ok_recruiting`), a data
  dictionary (`inst/dict/recruiting.yml`, dict-parity test), and
  `tests/testthat/test-recruiting.R`. Kept off the model path for now (like the
  team display dimension).
  See [decision 0013](https://github.com/ngiangre/cfbstats/blob/main/decisions/0013-recruiting-id-namespace-collision.md).
- Extended the data window from 2010–2025 to **2010–2026**: `ingest_player_stats()`
  and `ingest_roster()` now default to `2010:2026` (and `data-raw/refresh.R` pulls
  through 2026), with the season contracts (`contract_player_stats()`,
  `contract_conference_tiers()`) and dictionaries updated to match. Draft-facing
  bounds moved to 2027 accordingly — `link_drafted()` now defaults to a
  `2010:2027` draft window (the 2010–2026 stats window plus the following spring's
  draft), and `contract_picks()`/`contract_drafted()` widen their year checks. The
  2026 refresh adds preseason rosters and the completed 2026 draft class; 2026
  season stats are not yet available (season not started).
  See [decision 0012](https://github.com/ngiangre/cfbstats/blob/main/decisions/0012-extend-data-window-to-2026.md).
- `targets` pipeline (`_targets.R`) as the single source of truth for the DAG,
  with stage functions in `R/` (`ingest`, `clean`, `link`, `features`, `model`).
  See [decision 0004](https://github.com/ngiangre/cfbstats/blob/main/decisions/0004-adopt-targets-orchestration.md).
- Lineage/audit layer: `audit_step()` emits a per-step record (row/col counts,
  key coverage, schema hash, contract status, git SHA) into the `audit_log`
  target; data dictionaries in `inst/dict/`.
  See [decision 0005](https://github.com/ngiangre/cfbstats/blob/main/decisions/0005-lineage-and-audit-design.md).
- Data contracts (`pointblank`) and unit tests (`testthat`) run in the pipeline.
- Data dictionaries reconciled with the cleaned schema and now guarded by a
  test: `inst/dict/{coaches,roster,picks}.yml` were completed (coaches gains
  `conference`/`games`/`wins`/`losses`, roster gains `jersey`/`home_city`, picks
  documents all 26 pass-through columns), `contract_coaches()`/`contract_picks()`
  assert the added columns, and `tests/testthat/test-dict.R` asserts every
  `inst/dict/*.yml` matches its target's column names and types.
  See [decision 0010](https://github.com/ngiangre/cfbstats/blob/main/decisions/0010-reviewer-skills-and-dict-parity-test.md).
- v1 scope — weight/coaching/transfer change features and the drafted outcome.
  See [decision 0003](https://github.com/ngiangre/cfbstats/blob/main/decisions/0003-expand-v1-scope-weight-coaching-transfers.md).
- The `data-refresh` workflow now creates the `data-latest` release on first run
  (before uploading), so bootstrapping the data asset no longer needs a manual step.
- Roster finalized as a first-class pipeline target (`roster_file` → `raw_roster`
  → `roster`), replacing the empty-roster fallback; `add_roster_weight()` attaches
  the static roster `weight`. Between-season `weight_delta` is dropped as not
  derivable from CFBD `/roster` (weight is static per player: 0 of 64,350
  multi-season players vary). Enforcing the roster contract surfaced a
  data-quality issue the fallback had hidden: `clean_roster()` now coerces a
  placeholder `weight` of `0` to `NA`, and the contract weight range is 100–500 lb.
  See [decision 0009](https://github.com/ngiangre/cfbstats/blob/main/decisions/0009-finalize-roster-drop-weight-delta.md).
- Fixed a silent fan-out and false-positive draft attribution in the
  draft-outcome join: `picks` carries the full NFL draft history (back to 1936)
  and CFBD reuses `collegeAthleteId` across eras, so a modern player's id could
  match an ancient pick — duplicating a player-season and marking it `drafted`
  off a pre-window draft. `link_drafted()` now ignores picks outside the
  plausible draft window (`draft_window`, default `2010:2026`) and collapses the
  outcome to one pick per `playerId`, making the join strictly 1:1 and only ever
  marking `drafted` for an in-window pick. The new `contract_drafted()`
  (`ok_drafted`, fed into the `link_drafted` audit record) and
  `tests/testthat/test-link.R` guard against regressions.
  See [decision 0011](https://github.com/ngiangre/cfbstats/blob/main/decisions/0011-draft-outcome-one-pick-per-player.md).
- Team logos & colors: a `teams` display dimension sourced from CFBD `/teams`
  (`ingest_teams()`/`clean_teams()`, `data/teams.parquet`), joined by school name
  via `link_team_meta()` at the report layer only (kept off the model path).
  `contract_teams()` enforces full team-name coverage of the player-season
  backbone. See [decision 0008](https://github.com/ngiangre/cfbstats/blob/main/decisions/0008-team-logos-dimension.md).

## Documentation site

- Added `player_trajectory()` — assembles a subject registry's college→NFL
  spine (one row per player-season across both stages) with a **data-backed
  draft status** keyed on the nflverse `gsis_id` (presence in `nfl_draft_picks`
  ⇒ drafted; absence ⇒ undrafted, no name guard needed since both sides share
  nflverse's id namespace). The first blog post
  (`vignettes/2026-08-27-buechele-allen.qmd`) now calls it instead of inlining
  the parquet pull, and its timeline caption's "neither player was drafted"
  claim is enforced at author time (`stopifnot(!any(spine$drafted))`) rather
  than asserted in prose. `contract_player_trajectory()` guards the output
  (non-null `who`/`team`/`stage`, `stage` in `{College, NFL}`, complete logical
  `drafted`). Covered by `tests/testthat/test-link.R` and
  `tests/testthat/test-contracts.R`.
  See [decision 0015](https://github.com/ngiangre/cfbstats/blob/main/decisions/0015-blog-post-conventions-and-build-robustness.md).
  `player_trajectory()` and the first blog post now read the published parquet
  on its **cleaned** schema (decision 0018) rather than the raw schema they were
  written against: the helper filters roster `playerId` and NFL roster
  `nfl_team` (test fixtures updated to match), and the post's recruiting chunk
  and team-metadata join use the cleaned recruiting columns (`playerId`,
  `recruit_name`, `hs_class`, `national_rank`, `committed_to`) and `teams$team`.
  The post's committed Quarto freeze was regenerated against the fixed code.
- Added `data-raw/build-site.R`, a thin local-build wrapper mirroring the
  `site` workflow: it sets `CFBSTATS_ROOT` to the project root (so vignettes
  resolve `data/*.parquet` and `tar_read()` from altdoc's temp build dir) and
  runs `altdoc::render_docs(freeze = TRUE)` to reuse the committed freeze cache.
- Added an **NFL-outcomes exemplar** to the Explore page: `viz_nfl_roster_seasons_by_round()`
  plots career length (distinct seasons on an NFL roster) by draft round with the
  #1 overall picks highlighted against the field, noting the right-censoring of
  recent classes. The vision/question and data-source pages (`VISION.md`,
  `README.md`, `about`/`data`/`pipeline` vignettes) now cover the post-draft NFL
  question and the three nflverse tables.
  See [decision 0014](https://github.com/ngiangre/cfbstats/blob/main/decisions/0014-nfl-outcomes-nflverse-link.md).
- `altdoc` + Quarto website built to `docs/` and deployed to GitHub Pages;
  vignettes read the pipeline via `tar_read()`.
  See [decision 0006](https://github.com/ngiangre/cfbstats/blob/main/decisions/0006-quarto-site-architecture-and-viz.md).
- Site renders reuse a committed Quarto freeze cache (`_quarto/_freeze/`) so CI
  is faster and deterministic.
- Reworked the fan-facing Home (`README.md`) and About page for the
  non-technical fan in [VISION.md](https://github.com/ngiangre/cfbstats/blob/main/VISION.md)
  §10: added a "Where to start" fan path (About → Explore → Analysis) on the
  README, translated the About page's scope and methodology into plain football
  language, and tucked the statistical/tooling detail (the two cultures,
  out-of-time validation, decision log, `testthat`/`pointblank`) into a
  collapsible "For the stats-minded" callout so coders still have it.

## Project conventions

- Developed as an R package; `check()` is a conventions gate, not CRAN prep.
  See [decision 0002](https://github.com/ngiangre/cfbstats/blob/main/decisions/0002-rbuildignore-non-package-files.md)
  and [decision 0001](https://github.com/ngiangre/cfbstats/blob/main/decisions/0001-establish-project-vision-and-conventions.md).
- Established the feature-branch → NEWS → squash-merge workflow used for most
  work here, with this changelog linked from the site.
  See [decision 0007](https://github.com/ngiangre/cfbstats/blob/main/decisions/0007-feature-branch-news-merge-workflow.md).
- Set the package author/maintainer.
- Added three invocable `.claude/skills/` skills: `cfbstats` (slimmed to a
  pointer to `AGENTS.md`/`VISION.md`/dictionaries), `fan-experience-improver`
  (edits the fan-facing site toward the non-technical fan audience while
  protecting the technical pages), and `architecture-improver` (keeps the
  pipeline, data model, and conventions legible and auditable, works
  test/contract-first, and checks that graphics/models preserve expected counts
  and subsets).
  See [decision 0010](https://github.com/ngiangre/cfbstats/blob/main/decisions/0010-reviewer-skills-and-dict-parity-test.md).

The full decision log lives in
[`decisions/`](https://github.com/ngiangre/cfbstats/tree/main/decisions).

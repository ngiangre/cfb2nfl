# Plan: Define, store, and publish the outcome variables table (discrete-time survival)

Date: 2026-10-24. Branch: `feat/outcome-table`.

## Problem

The modeling label exists only as an ephemeral player-season flag: `link_drafted()`
(`R/link.R`) adds `drafted`/`draft_year/round/overall` to `ps_draft`, but no outcome
table is stored, bundled in DuckDB, published on the `data-latest` release, or
documented in `inst/dict/`. `resolve_nfl_outcome()` (decision 0014) computes
per-player outcomes + longevity but is only called from the dossier.

## Design decisions (user-ratified)

1. **Grain: person-period** — one row per player-season in the at-risk set
   (players with a stat line, excluding reused CFBD ids per decision 0022).
   Season-level rows carry the season covariates; career-level labels
   (drafted, NFL entry, success) are resolved once per player and stamped on
   the relevant rows, so models can query the dependent variable with no
   further derivation.
2. **Eligibility clock:** `hs_grad_year (h)` starts the clock; a season `s` is
   draft-eligible for draft `d = s + 1` iff `d − h ≥ min_years_since_hs` (3 for
   2010–2026, stored as a column so it can vary by draft year).
3. **hs_grad_year source:** the name-guarded `link_recruiting()` join
   (`hs_class`, decision 0013). Where unavailable, impute `h = first observed
   college season` and set `hs_year_imputed = 1` (usable as a data-quality
   flag or sensitivity filter).
4. **Variable names follow the user's catalog verbatim** (identifiers/timing,
   eligibility, outcomes: drafted, outcomes: NFL entry, outcomes: NFL success,
   survival bookkeeping) — see the column table below.
5. **`declared_early` is out of scope** for v1: it needs an external early-entry
   list that we do not ingest (and quota is limited). Stored as `NA` with a
   documented note, or dropped — decide at implementation; leaning drop with a
   dict comment so a future source can add it.
6. **Censoring rule:** rows with `outcome_observed = 0` (draft `d` beyond the
   last complete draft year) get `NA` outcomes, never `0`.

## Table: `outcomes` (person-period)

Identifiers and timing: `player_id`, `season (s)`, `draft_year (d = s + 1)`,
`hs_grad_year (h)`, `hs_year_imputed`.

Eligibility: `years_since_hs (d − h)`, `min_years_since_hs`, `draft_eligible`
(risk-set indicator; only TRUE rows form the at-risk population),
`eligible_season_index` (discrete-time baseline hazard index, NA before
eligibility), `ncaa_exhausted` (no further college season; marks the last row).

Outcomes — drafted: `drafted`, `draft_round` (1–7), `draft_pick` (overall),
`draft_round_group` (r1 / r2_3 / r4_7 / undrafted).

Outcomes — NFL entry: `signed_udfa` (mutually exclusive with `drafted`),
`nfl_entry` (drafted or signed_udfa; the broadest event indicator and the
default for sparse positives), `nfl_entry_type` (drafted_r1 / drafted_r2_3 /
drafted_r4_7 / udfa / none), `nfl_entry_within_k` (fixed-horizon binary,
k stored as a parameter, default 1 year).

Outcomes — NFL success: `made_regular_season_roster` (entry-year active
roster), `rookie_games_played` (0 if none). Derived via the draft-slot →
`gsis_id` bridge to `nfl_rosters` / `nfl_player_stats` (decision 0014; labels
only, never model inputs).

Survival bookkeeping: `years_to_nfl_entry` (event time; time to last
observation when censored), `nfl_entry_event` (1/0 status),
`status_end_of_season` (drafted / signed_udfa / exhausted_undrafted /
left_data / continuing / censored), `outcome_observed` (administrative
right-censoring flag), `outcome_source` (draft_table / roster_table / none;
audit only).

Core modeling set: `player_id`, `eligible_season_index`, `draft_eligible`,
`nfl_entry` (or `drafted`), `status_end_of_season`; `years_to_nfl_entry` +
`nfl_entry_event` for Cox-style analysis.

## Implementation steps

1. **Function** `R/outcomes.R`: `build_outcomes(ps_pop, career, recruiting,
   picks_nfl, nfl_rosters, nfl_player_stats, last_complete_draft_year,
   entry_horizon = 1L)` — pure, roxygen-documented, per-player resolution of
   labels then expansion to person-period rows; validates row counts (no
   silent join loss) and stops on key duplication. Parameters (horizon,
   last-complete draft year) keep the censoring logic explicit.
2. **Tests** `tests/testthat/test-outcomes.R` with fixtures: eligibility math
   (known vs imputed `hs_grad_year`), `eligible_season_index` progression,
   drafted/UDFA mutual exclusivity, `nfl_entry` aggregation,
   `nfl_entry_within_k`, censoring (`outcome_observed = 0` → NA outcomes,
   `status_end_of_season` variants), id-reuse exclusion.
3. **Pipeline** `_targets.R`: `outcomes` target downstream of `ps_pop`,
   `career`, `picks_nfl` (and recruiting); add `outcomes_file` via
   `parquet_asset()` so refresh mode cleans+writes `data/outcomes.parquet` and
   it ships on `data-latest`; add to the `build_duckdb()` table list; keep the
   `player_season_inputs` view unchanged (it already excludes label columns).
4. **Contract** (`R/contracts.R` + `contract_gate`): at-risk row count matches
   `ps_pop` eligible player-seasons (no join loss), `drafted`/`signed_udfa`
   mutual exclusivity, `drafted → draft_round/pick` completeness,
   `nfl_entry == drafted | signed_udfa`, `years_since_hs >= min_years_since_hs`
   on all kept rows, `outcome_observed = 0 ⇒ NA` outcomes, `last_nfl_season >=
   draft_year` when signed.
5. **Dictionary** `inst/dict/outcomes.yml` (existing dict style; every column
   documented with provenance, including the imputation and censoring caveats).
   Update `inst/data-model.md` to point the v1 outcome section at this table
   and its person-period grain.
6. **Decision record**: copy `decisions/TEMPLATE.md` →
   `decisions/0032-outcome-table-person-period.md` (verify 0032 is free).
7. **Publish**: derivation-only — no new CFBD calls, but `outcomes_file`
   requires refresh mode to write the parquet. Run `tar_make()` in refresh
   mode locally (check `tar_cue`/stale targets first so we don't re-pull the
   game ingests unnecessarily; quota note in AGENTS.md), then
   `piggyback::pb_upload(..., tag="data-latest", overwrite = TRUE)` and
   re-dispatch `site.yaml` via the `gh` R package.
8. **Ship**: update `NEWS.md` (user-facing change + decision link),
   `air format .`, push branch, open PR, let CI (testthat + contract fixtures)
   pass, squash-merge.

## Notes / risks

- The recruiting `hs_class` link is name-guarded; wrong-person matches are
  nulled by design (decision 0013), which increases the imputed-`h` share —
  the `hs_year_imputed` flag makes that measurable.
- `ncaa_exhausted` / `left_data` statuses depend on observed data only; a
  player absent from the next season is `left_data` (transfer, injury, or
  leaving early) — treated as deliberate informative censoring, documented in
  the dict.
- If refresh-mode `tar_make()` wants to re-run expensive game ingests, limit
  to the affected subtree rather than a full re-pull.

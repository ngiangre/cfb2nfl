# 0032 — Person-period `outcomes` table as the published modeling label

- **Status:** Accepted
- **Date:** 2026-10-24

## Context

The modeling dependent variable existed only as an ephemeral per-season flag:
`link_drafted()` added `drafted`/`draft_year/round/overall` to the in-memory
`ps_draft` target, never stored, bundled, or documented. `resolve_nfl_outcome()`
(decision 0014) computed per-player NFL outcomes only for the dossier. The
modeling plan needs the label **query-ready**: no re-derivation at model time,
and published like the other cleaned tables (parquet + DuckDB + dict +
release). The outcome also needs an eligibility clock — the v1 denominator is
"players with a stat line in draft-eligible seasons" — and CFBD has no
eligibility data.

## Decision

Build a person-period `outcomes` table (`build_outcomes()`, decision 0032):

- **Grain:** one row per player-season in the model population (`ps_pop`,
  stat-line grain, reused CFBD ids excluded per decision 0022).
- **Eligibility clock:** `hs_grad_year (h)` is the time origin; draft
  `d = s + 1`; a row is at risk when `d - h >= min_years_since_hs` (3 for
  2010-2026, stored as a column). `h` comes from the name-guarded recruiting
  `hs_class` (decision 0013); otherwise it is imputed as first observed stat
  season minus one, flagged by `hs_year_imputed`.
- **Labels:** drafted (event/round/overall/round-group, one-pick-per-player,
  decision 0011), UDFA entry via a single-candidate name guard (ambiguous
  names resolve to no link, never a guess), the broad `nfl_entry` event and
  competing-risks type, a fixed-horizon entry flag, and entry-year NFL success
  (made roster, rookie games) via the draft-slot `gsis_id` bridge.
- **Survival bookkeeping:** `years_to_nfl_entry` + `nfl_entry_event`,
  `status_end_of_season` (drafted / signed_udfa / exhausted_undrafted /
  left_data / continuing / censored), and `outcome_observed_d` — rows past the
  last complete draft carry **NA outcomes, never 0**.
- **Storage:** published as `data/outcomes.parquet` on the data-latest release
  AND bundled in `cfbstats.duckdb`, with `inst/dict/outcomes.yml`,
  `contract_outcomes()` in the contract gate, and an audit row. (Unlike the
  decision 0021 derived tables, the user explicitly wanted this on the release;
  it derives from cleaned tables, so no extra API calls.)
- `declared_early` is deferred: it needs an external early-entry source we do
  not ingest.

## Hypotheses / expectations

- ~68k players and ~160k person-period rows; a drafted share of a few percent
  (sparse positives motivate the broad `nfl_entry` default).
- The imputed-clock share will be substantial (~2/3) — `hs_year_imputed` lets
  models sensitivity-check rather than silently trust mis-timed clocks
  (redshirts, JUCO, late enrollees).

## Consequences

- Models consume `outcomes` directly; `ps_change` keeps the legacy `drafted`
  flag for compatibility.
- `left_data` conflates exhausted-eligibility alternatives (transfer, injury,
  early departure) — informative censoring to be treated deliberately in
  survival work.
- A new release asset must be published before track-mode builds elsewhere can
  use it (same rule as any parquet asset).

## Outcome / what we learned

- Real-data run (2026-10-24 refresh): 159,996 person-period rows for 68,135
  players; 2,723 drafted, ~3.6k UDFA entries, 30,428 censored rows. The
  imputed-clock share is ~67% as predicted.
- The name-guard UDFA match initially let same-name NFL **veterans** slip
  through (`rookie_year` is NA for long-tenured players, so the entry window
  bound had an NA escape hatch). Gating on each candidate's actual first NFL
  roster season fixed it.
- CFBD id reuse surfaced era-collision picks at the outcome stage too: a pick
  dated at/before the player's first stat season is now nulled entirely.
- The eligibility clock can declare an entrant "never eligible" (early
  entrants, imputed-HS one-season careers); event time is now simply
  `entry year - h` for entrants, and `contract_outcomes()` positivity is the
  guard against nonsense links.

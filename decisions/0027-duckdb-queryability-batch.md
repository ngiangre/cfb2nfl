# 0027 — DuckDB queryability: guarded bridge, lineage, meta, manifest, height

- **Status:** Accepted
- **Date:** 2026-10-17

## Context

An assessment of the DuckDB bundle against `inst/dict` (decision 0026 added
the wide `player_season_stats`) surfaced remaining queryability gaps:

1. The only safe CFBD→nflverse bridge (`link_nfl_draft()`, name-guarded,
   decision 0014) lives in R — a SQL user re-running the raw draft-slot join
   in SQL loses the name guard and gets rare wrong-person matches.
2. The lineage log (`audit_log`, decision 0005) is invisible inside the asset,
   so SQL users cannot self-check joins for silent row loss (the repo's #1
   documented hazard).
3. Nothing in the bundle says which seasons are COMPLETE — 2026 stats are
   in-progress, so naive "max season" logic leaks partial seasons into
   out-of-time frames.
4. `roster.height` carried data-entry errors (9, 50, 57 in; ~6 rows) that the
   weight/class-year precedent (decision 0009) already handles for other
   fields, but the contract didn't cover height.
5. Dictionary units/ranges (SP+/SRS scales, height inches) were undocumented.

## Decision

- **Bundle `nfl_pick_link`** (the `picks_nfl` target output of
  `link_nfl_draft()`) with a dictionary; it is derived in-pipeline, bundled
  only, no parquet (decision 0021 pattern).
- **Bundle a slimmed `audit_log`** (`slim_audit_log()` drops the nested
  `na_by_col` list column) so lineage is flat SQL.
- **Generate `_meta`** on every build: refresh timestamp plus
  `last_complete_cfb_season` / `last_complete_nfl_draft`, computed from the
  date (a CFB season is complete after March 1 of the following year; a draft
  class after May 1 of Y+1) — dynamic, so it stays correct across refreshes.
- **Generate `_schema_manifest`** on every build from `inst/dict/*.yml`
  (grain + key + dict path per table), so table documentation is INSIDE the
  asset and an undocumented bundled table is self-evident (`documented =
  FALSE`). Dynamic — no manual list to maintain.
- **Create a `player_season_inputs` VIEW** = `ps_change` minus the
  draft-outcome columns, the leakage-safe input surface.
- **Coerce out-of-range `height` (60–85 inches plausible) to NA** in
  `clean_roster()` and assert it in `contract_roster()` (decision 0009
  precedent); document units in `roster.yml`.
- **Document units/ranges** in `coaches.yml` (SRS/SP+ point scales).

## Hypotheses / expectations

- Pure-SQL users can now run correct NFL longevity queries and audit joins
  without touching R or risking the unguarded slot join.
- The completeness boundary in `_meta` keeps partial seasons out of training
  frames even as refreshes change the max season.
- The manifest makes bundle-vs-dict drift visible from inside the file.

## Consequences

- `duckdb_file` now depends on `audit_log` (no cycle — audit rows only read
  data/contract targets).
- The completeness cutoffs are conventions, not facts: a refresh in February
  treats the just-finished season as incomplete until March 1 (conservative by
  design).
- The manifest is a table, so it participates in the file size/row-count
  surface; excluded from published dicts by the leading-underscore naming.

## Outcome / what we learned

_Filled in later._

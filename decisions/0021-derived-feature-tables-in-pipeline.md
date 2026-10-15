# 0021 — derived feature tables are pipeline targets, bundled in DuckDB (not published parquet)

- **Status:** Accepted
- **Date:** 2026-10-14

## Context

The Explore sections computed derived features ad hoc in the vignettes —
`flag_redshirt(tar_read(roster), tar_read(player_stats))` and
`career_summary(tar_read(roster))` were re-derived per figure — so each
recomputation was a chance to drift from the tested functions, and the features
were invisible to SQL consumers of `data/cfbstats.duckdb`. Meanwhile the
feature backbone `ps_change` (change features on the link chain) existed as a
target but was likewise absent from the database, the dictionaries, and the ERD.

## Decision

Make the derived feature tables **first-class pipeline targets** with the same
contract + audit treatment as cleaned tables, and bundle them into the DuckDB
asset:

- `career` = `career_summary(roster)` (per-player grain),
- `roster_flags` = `flag_redshirt(roster, player_stats)` (roster grain + flags),
- `ps_change` = `add_change_features(ps_draft)` (already a target).

All three are added to the `duckdb_file` table list under their dict names
(`career_summary`, `roster_flags`, `ps_change`), documented in
`inst/dict/{career_summary,roster_flags,ps_change}.yml`, entered in the
`inst/data-model.md` table list and ERD, and audited (`audit_step()` rows with
their contracts, `contract_career_summary()` / `contract_redshirt()`).

Like `stat_taxonomy` (decision 0019), the derived tables are **not published as
standalone parquet**: they rebuild from other cleaned tables in any pipeline
mode, so track-mode builds need no new release asset, and the
publish-before-merge constraint (decision 0018) does not apply to them. The
dictionaries note their derived status.

Downstream, `player_dossier()` gains optional `career` / `roster_flags`
arguments that attach a "Career & eligibility" section (with the redshirt-shaped
caveat in its provenance block), and `explore.qmd` reads the targets
(`tar_read(roster_flags)`, `tar_read(career)`) instead of recomputing.

Alternatives not picked: publishing the derived tables as parquet assets on
`data-latest` (keeps a strict parquet == DuckDB equality, but requires a full
API refresh before every merge that touches a feature — high cost, no querying
benefit over the DuckDB); keeping vignette-side recomputation (the drift risk
this decision removes).

## Hypotheses / expectations

- Feature definitions live in exactly one place (the tested `R/features.R`
  functions, exercised by the targets); plots and dossiers read the same
  pipeline-owned values, so a definition change propagates everywhere at once.
- SQL consumers (and later model work) can query eligibility/transfer/career
  features directly from the DuckDB without re-deriving them.

## Consequences

- The "parquet == DuckDB == dict schema" equality (decision 0018) now holds for
  *published* tables; the DuckDB additionally carries derived tables that have
  dicts but no parquet. `test-dict.R` still validates published dicts against
  parquet; a new `test-dict-derived.R` validates the derived dicts against the
  feature functions' output schemas on fixtures.
- Any new derived feature table must follow the same recipe: target + contract
  + audit row + dict yml + `duckdb_file` entry + `data-model.md` row/edge.
- `roster_flags`/`career_summary` are roster-derived and leakage-free;
  `ps_change` carries the `drafted` label — noted in its dict.

## Outcome / what we learned

_Filled in later._

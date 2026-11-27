# 0053 — The largest pipeline tables stay lazy Arrow datasets

- **Status:** Accepted
- **Date:** 2026-11-26

## Context

Every published table went through two targets: `<table>_file`
(`format = "file"`, tracking `data/<table>.parquet`) and `<table>`
(`arrow::read_parquet(<table>_file)`), which loaded the whole table into
memory and stored a second copy in `_targets/objects/` (rds, or parquet for
the play-level tables). Every consumer then deserialized the full table,
although most read a handful of columns: the `nfl_pbp` contract checks 25 of
372 columns. The play-level tables grow every week (decision 0045), so this
cost grows with them (issue #126).

Two facts shaped the design. Arrow does not guarantee row order for a
dataset query (arrow NEWS: "Row order of data from a Dataset query is no
longer deterministic"), and several consumers depend on file order: the
player chips in each explorer play, `distinct(.keep_all = TRUE)` in
`build_player_game()`, and the per-game `diff(elapsed)` check. And targets
deparses a custom format's methods into a fresh environment under
`baseenv()`, so they must be self-contained.

## Decision

`format_arrow_lazy()` (`R/lazy.R`), a `tar_format()` that reads back as
`arrow::open_dataset()`, for `plays`, `play_stats`, `game_player_stats`,
`nfl_pbp`, `nfl_participation` and the built `explorer_plays`.

- **Reader pattern: the reader target returns
  `arrow::open_dataset(<table>_file)`, and the format stores a reference**
  (file paths and `rlang::hash_file()` hashes, about 150 bytes) instead of
  the data. The hashes are part of the stored value, so a changed file
  invalidates everything downstream, and reading a reference whose file
  changed since the build errors instead of silently reading new data.
  Opening `<table>_file` directly in each consumer (the alternative) would
  have kept the copy out of the store too, but would have rewritten every
  consumer's dependencies and lost the `<table>` name posts and contracts
  use.
- A data frame or Arrow `Table` is written to the store as parquet
  (`explorer_plays`); any other query is streamed with `write_dataset()`.
- **Consumers read columns, not rows.** `collect_cols(x, cols)` reads a
  parquet dataset file by file with `read_parquet(col_select = )`, which
  keeps file order exactly as the whole-table read did. Row filters are not
  pushed into Arrow, because their order is not guaranteed and every lazy
  table's consumers either need it or would need a new explicit sort.
  `distinct_values()` and `n_rows()` cover the season, game-id and row-count
  checks.
- **Contracts and the audit log keep their checks.** Each contract on a
  lazy table collects the columns it names (a missing column is then still
  caught by `col_exists()`), and pointblank runs on the same data frame as
  before. `audit_step()` counts rows from parquet metadata, reads key
  columns only, counts NA cells one column at a time with R's `is.na()`, and
  hashes the schema on a zero-row collect, so every audit field is
  unchanged.
- **The DuckDB bundle reads the parquet directly.** `build_duckdb()` creates
  each lazy table from a zero-row R copy (so the column types are the R
  route's; DuckDB alone reads a tz-aware timestamp as TIMESTAMPTZ) and fills
  it with `INSERT ... BY NAME SELECT * FROM read_parquet()` in a UTC session.
- Targets that posts `tar_read()` (`player_game`, `player_usage`, `career`,
  `outcomes`, `picks_nfl`, `position_path`, `audit_log`, `schema_history`)
  stay in-memory formats, so no post changes.

## Hypotheses / expectations

A track-mode build (the `site.yaml` path) is faster and the store smaller,
with every output identical.

## Consequences

- targets marks a store with custom-format code as untrusted: a
  non-interactive `tar_read()` of a lazy target needs `TAR_ASK=false`;
  interactive sessions ask once. `tar_make()` and reads of every other
  target are unaffected.
- A lazy target must only reference a file a `format = "file"` target
  tracks, or the reference outlives its data.
- New consumers of a lazy table go through `collect_cols()`;
  `x$column` on a dataset is `NULL`, not an error.
- `_targets/objects/` savings are local only: `site.yaml` builds from an
  empty store, so on CI only time counts.

## Outcome / what we learned

Measured on a clean track-mode `tar_make()` on the 2026-11-26 data, same
machine (macOS, Apple silicon), baseline `main` at 5bb8c61:

| Measure | Baseline | Lazy | Change |
|---|---:|---:|---:|
| Wall time | 742.7 s | 549.8 s | -26% |
| Sum of target seconds | 601.7 s | 472.0 s | -22% |
| Peak RSS (`/usr/bin/time -l`) | 6.43 GB | 6.10 GB | -5% |
| `_targets/objects/` | 482 MB | 199 MB | -59% |
| `ok_nfl_pbp` | 79.6 s | 12.3 s | |
| `ok_plays` | 67.0 s | 30.1 s | |
| `ok_explorer_plays` | 27.2 s | 18.2 s | |
| `duckdb_file` | 24.7 s | 10.2 s | |
| `plays` stored | 139 MB | 145 B | |
| `nfl_pbp` stored | 95 MB | 147 B | |
| `explorer_plays` | 135.5 s | 134.7 s | 27.9 s after the JSON change below |

Outputs are identical: all 50 contract results, the audit log (schema
hashes and NA profiles included), the derived targets, all 1,625 explorer
files byte for byte, and every DuckDB table's schema and contents
(`EXCEPT ALL` both ways). The DuckDB file is 563 MB instead of 546 MB
(same contents, different insert path).

A zero-CFBD-call `data-raw/refresh-nfl.R 2026` run checked the refresh path,
which rewrites a referenced parquet: the new 2026 rows (`nfl_pbp` 27,602 to
28,829) re-hashed the `nfl_pbp` reference, the contracts and gate re-ran and
passed, the DuckDB row counts matched the new parquet, and nothing was left
outdated. Restoring the old file afterwards made `tar_read(nfl_pbp)` stop
with the "changed since the target was built" error, as intended.

Peak memory barely moved, so the build's peak is set somewhere other than
holding these tables; finding where is not part of this change.

`explorer_plays` did not speed up from the format alone: 79% of its time
was one `jsonlite::toJSON()` call per play inside `summarise()`. The player
arrays are now built for all plays at once (`json_rows()`:
`jsonlite::stream_out()` renders every row in one pass, and each play's rows
are joined in order), which takes the target from 135.5 s to 27.9 s with
the same table and the same 1,625 explorer files byte for byte. A test pins
`json_rows()` to `toJSON()` on quotes, backslashes, newlines, non-ASCII
names and missing fields.

# Plan: Audit-log hygiene — 100% understood, clean data

Working plan (not a decision record; decisions land in `decisions/` once
ratified). Created 2026-10-16 from a read of `tar_read(audit_log)` after
adding tooltips/definitions to `vignettes/data.qmd`. Motivating principle:
**early in the data build, every anomaly in the audit log must be either
explained or fixed — nothing silently tolerated.**

## Current audit_log snapshot (2026-10-16)

| step | stage | n_rows_out | rows_delta | n_keys_out | n_na_cells | contract |
|------|-------|-----------:|-----------:|-----------:|-----------:|----------|
| clean_picks | clean | 13,080 | NA | 5,913 | 106,618 | TRUE |
| clean_player_stats | clean | 1,494,983 | NA | 159,681 | 0 | TRUE |
| clean_coaches | clean | 12,564 | NA | 12,560 | 17,326 | TRUE |
| clean_roster | clean | 337,020 | NA | 336,736 | 138,693 | **FALSE** |
| clean_recruiting | clean | 37,163 | NA | 37,163 | 6,777 | TRUE |
| clean_teams | clean | 1,868 | NA | 1,868 | 6,768 | TRUE |
| build_player_season | link | 159,708 | −1,335,275 | 159,681 | 0 | NA |
| link_coaches | link | 168,369 | +8,661 | 159,681 | 491,420 | NA |
| link_tiers | link | 168,369 | 0 | **NA** | 491,420 | TRUE |
| link_drafted | link | 168,369 | 0 | 159,681 | 965,870 | TRUE |
| add_change_features | features | 168,369 | 0 | 159,681 | 1,267,399 | NA |
| flag_redshirt | features | 337,020 | 0 | 336,736 | 138,693 | TRUE |
| career_summary | features | 135,356 | −201,664 | 135,356 | 0 | **FALSE** |
| add_roster_weight | features | 168,369 | 0 | 159,681 | 1,296,093 | NA |
| link_recruiting | link | 159,708 | 0 | 159,681 | 393,944 | NA |
| clean_nfl_draft_picks | clean | 4,350 | NA | 4,350 | 14,157 | TRUE |
| clean_nfl_rosters | clean | 46,272 | NA | 46,272 | 7,611 | TRUE |
| clean_nfl_player_stats | clean | 32,034 | NA | 32,034 | 0 | TRUE |
| link_nfl_draft | link | 13,080 | 0 | 5,913 | 151,565 | TRUE |
| stat_taxonomy | clean | 54 | NA | 54 | 0 | TRUE |

## Findings (severity-ordered)

1. **[BLOCKER] Two contracts fail and the pipeline still ships.**
   `clean_roster` and `career_summary` report `contract_passed = FALSE`, yet
   `tar_make()` completed and assets published. Contracts are recorded, not
   enforced — the "fail fast" design (AGENTS.md) is not what runs.
2. **[BLOCKER] 27 duplicate player-seasons.** `build_player_season` outputs
   159,708 rows but only 159,681 distinct keys. At the stated grain (one row
   per player-season) duplicates double-count players in every downstream
   feature and model.
3. **[HIGH] `clean_picks` key is not unique.** 13,080 rows vs 5,913 distinct
   `collegeAthleteId`. Pre-2013 picks without ids explain part; the remainder
   needs an explicit accounting before the picks table can be trusted as a
   join source (`link_nfl_draft` inherits this).
4. **[HIGH] The link/features steps with the highest silent-loss risk have no
   contracts** (`contract_passed = NA`): `build_player_season`,
   `link_coaches`, `add_change_features`, `add_roster_weight`,
   `link_recruiting`. Blank renders as "fine" — it means "unchecked."
5. **[MEDIUM] `link_tiers` has `n_keys_out = NA`** — declared keys don't match
   output columns; that step's coverage is untracked.
6. **[MEDIUM] NA growth is confounded.** `n_na_cells` on the model path climbs
   0 → 491k → 966k → 1.27M → 1.30M, but the metric counts total NA cells in
   the whole output: each added column raises the ceiling mechanically. Real
   sparsity (e.g. coach covariates on fan-out rows) is indistinguishable from
   column-count growth.
7. **[LOW] Doc/schema mismatch.** The vignette prose and memory describe a
   "rows dropped" field; `audit_step()` emits no such column.
8. **[LOW] Snapshot-only visibility.** The vignette drops `timestamp`,
   `git_sha`, `schema_hash`; with no cross-refresh comparison, schema drift
   cannot actually be observed from the site.

## Workstreams

### A. Make contracts enforce (fix the "fail fast" lie) — do first

- [x] Decide enforcement policy in `_targets.R` / `audit_step()` callers:
      a failing contract aborts the build (`tar_validate()` / explicit stop in
      the contract runner). Record the choice in a decision entry.
      **Done 2026-10-16 (decision 0023):** `assert_contracts_pass()` +
      `contract_gate` target depending on all 15 `ok_*` targets; any `FALSE`
      aborts `tar_make()` (default `error = "stop"`), so CI never publishes.
      Verified: the stale parquet blocked the gate until `roster.parquet` was
      regenerated with the fixed cleaner; a track-mode `tar_make(contract_gate)`
      now passes and the audit log shows both contracts `TRUE`.
- [x] Fix `clean_roster` contract failure — root cause: one player (id
      `5227052`) listed at 23 lb, a data-entry error the `0 → NA` placeholder
      rule missed. Fix (2026-10-16): `clean_roster()` coerces any weight
      outside 100-500 lb to `NA` (next-lowest real weight is 110 lb); docstring
      + test updated; live re-clean passes all 6 contract steps.
- [x] Fix `career_summary` contract failure — root cause: 57 players with 8-11
      roster seasons are **CFBD id reuse** (one id, one name, impossible span,
      e.g. a Cal DB 2010-2023); 131 roster ids (0.1%) span >7 seasons, 124 of
      which reach the stats backbone. Fix (2026-10-16, decision 0022):
      `reused_ids()` helper; `career_summary(max_span = 7L)` drops them; new
      `ps_pop` target filters the model population; dict updated.

### B. Duplicates and key uniqueness

- [x] Identify the 27 duplicate player-season keys in `build_player_season` —
      **resolved 2026-10-16: not duplicates.** The step's documented grain is
      `(playerId, season, team)` and all 159,708 rows are unique at it; the
      27 pairs are mid-season transfers (e.g. Cody Parkey, Auburn + LSU, 2013,
      with distinct stat lines at each school in the raw feed). The audit was
      declaring the wrong key (`playerId, season`).
- [x] Correct the audit key declarations (2026-10-16): model-path steps now
      key on `(playerId, season, team)`; `clean_picks` keys on its actual
      grain, the draft slot `(year, round, pick)`; `ps_change`'s audit input
      fixed to `ps_pop` (was the stale pre-filter `ps_draft`).
- [x] Add a contract: `contract_player_season()` asserts non-null keys and
      uniqueness at `(playerId, season, team)` plus the 2010-2026 season
      window; wired as `ok_player_season` into the gate (decision 0023).
- [x] Account for `clean_picks` rows-per-key (2026-10-16): 13,080 rows =
      7,160 pre-id-era picks (ids essentially absent before 2004, tapering
      2001-2003) + 5,920 with id; 8 ids appear on 2 rows each because CFBD
      recycles ids across same-surname players at the same school decades
      apart (decision 0022) — and even within one draft year (two Derrick
      Johnsons, Texas, 2005, rounds 1 and 6). The asserted key is therefore
      the pick slot, not the id: `contract_picks()` now asserts
      `rows_distinct(year, round, pick)`. Slot uniqueness verified on live
      data (0 duplicates).

### C. Contract coverage on the model path

- [x] Write contracts for the remaining link/features steps (2026-10-16):
      `contract_coach_link()` (fan-out pinned to the coaches table — each
      key appears max(1, n_coaches) times), `contract_tier_link()`
      (row-preserving, tier 1-3 non-null, label in set), 
      `contract_reused_filter()` (rows dropped exactly match the reused ids,
      no id survives), `contract_change_features()` (row-preserving; flags
      equal their definitions, NA allowed where a coach record is missing),
      `contract_roster_weight()` (row-preserving, weight 100-500 na_pass),
      `contract_recruit_link()` (row-preserving, stars 0-5 / rating 0-1,
      unmatched rows carry no HS values). All wired as `ok_*` targets into
      the gate and the audit rows. `build_player_season` was covered by
      workstream B.
- [x] `link_tiers`: fixed `keys` declaration (workstream B) and the audit's
      `contract_passed` now points at `ok_tier_link` (the link itself) rather
      than `ok_tiers` (the lookup's coverage universe).
- [x] Live-data discovery (2026-10-16): `hc_changed`/`followed_coach` are
      legitimately `NA` in 2,719/2,697 rows where a school-season has no coach
      record on either side of the lag (NA = unknowable, not FALSE). The
      contract documents this and compares both sides coalesced to FALSE;
      `transferred` is never NA.

### D. Make the log interpretable

- [x] Add `pct_keys_matched` (or NA-coverage of the joined columns) to
      `audit_step()` so join quality is explicit, not inferred from `n_na_cells`.
      **Done 2026-10-16:** when `keys` exist in both input and output,
      `pct_keys_matched` = share of distinct input key combos surviving into
      the output, and `keys_dropped` = combos lost; else `NA`. `link_coaches`
      reads 1.0 / 0 dropped (pure fan-out); `filter_reused_ids` reads 0.997 /
      462 dropped — the filtering-vs-fan-out distinction the plan wanted.
- [x] Consider per-new-column NA counts, or replace `n_na_cells` with a rate,
      so growth reflects data quality rather than column count.
      **Done 2026-10-16:** `audit_step()` now emits `n_cols_with_na` and a
      list column `na_by_col` (`col`, `n_na`, `na_rate`, NAs only, sorted
      descending). `n_na_cells` kept for continuity. E.g. `link_coaches`
      top NA columns are `srs`/`sp_overall` (~30%), no longer buried in a
      491k total.
- [x] Add a `rows_dropped` field or correct the vignette/memory prose to match
      the actual schema (prefer adding the field: "rows dropped" vs
      `rows_delta` distinguishes filtering from join fan-out).
      **Done 2026-10-16:** added as `keys_dropped` (distinct key combinations
      from the input absent from the output; 0 under pure fan-out/addition,
      `NA` without keys). Tests in `test-audit.R` cover fan-out vs filtering,
      missing keys/input, and the NA profile.
- [x] Keep prior-run `schema_hash` (e.g. write a small history file per
      refresh) so drift is detectable; or note explicitly in the vignette that
      drift checks happen in CI, not on the site.
      **Done 2026-10-16:** `update_schema_history(audit_log, path)` appends
      `step, n_cols_out, schema_hash, timestamp, git_sha` to
      `data/audit_history.csv` (dedup on `(step, timestamp)` so re-runs don't
      duplicate). New `schema_history` target: appends in refresh mode, reads
      the file in track mode. Because CI refresh checkouts start empty, the
      history is carried across refreshes as a `data-latest` release asset:
      `data-refresh.yaml` downloads the prior CSV before `tar_make()` and
      uploads it after. Drift query: per step, rows with >1 distinct
      `schema_hash`.

### E. Vignette truthfulness

- [x] Update `vignettes/data.qmd` callout: add `career_summary` (−201,664) and
      `clean_roster` to the "reading the log" notes once understood.
      **Done 2026-10-16:** the "reading the log" callout now explains
      `build_player_season` / `link_coaches` via the new `keys_dropped`
      metric, plus `filter_reused_ids` (462 combos, 99.7% coverage) and
      `career_summary` (131 keys) as id-reuse filtering (decision 0022).
- [x] Re-render and verify tooltips/table after A–D land.
      **Done 2026-10-16:** `data.qmd` renders clean with the new columns
      (`keys dropped`, `keys matched`, `cols w/ NA`, `top NA columns`) and the
      new Schema history section (track mode shows the "no history yet" path;
      with a history file present it renders the table and reports no drift
      yet). Full site render happens via `altdoc::render_docs()`/CI as usual.

## Definition of done

- Every step: contract exists AND passes (or failure blocks the build).
- Every `rows_delta` ≠ 0 is explained in the vignette callout.
- Every key is unique at its stated grain (or its non-uniqueness is
  quantified and contracted).
- No `n_keys_out = NA` on any step.
- A re-run of `tar_make()` in refresh mode produces a log matching this plan's
  "done" criteria.

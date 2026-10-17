# 0024 — Coerce out-of-range `class_year` to NA; `fifth_year_career` becomes coverage-honest

- **Status:** Accepted
- **Date:** 2026-10-16

## Context

The expectation-check blog post (`vignettes/2026-10-16-expectation-checks.qmd`,
2026-10-16) stress-tested seven well-documented quarterback careers against the
cleaned tables and surfaced two structural findings in the roster backbone:

1. **`class_year` contamination.** The cleaned roster's `class_year` (CFBD
   `/roster`'s own `year` field, documented as eligibility class 1-5) holds 24
   distinct values: 1-6 and 0 as plausibly intended, but also **whole season
   years 2010-2026 in ~123,791 of 337,020 rows (~37%)**. The contamination is
   era-concentrated: 2010-2019 seasons are almost entirely year-valued (e.g.
   2010: 14,248 of 14,253 rows), while 2020-2026 are mostly clean. Reading: the
   CFBD endpoint's `year` field *changed meaning across its own history* (or was
   always the season and only recently became a class); older seasons simply do
   not carry a measurable eligibility class.
2. **Key uniqueness was unguarded.** `contract_roster()` asserted column
   existence, non-null keys, and the weight range, but nothing prevented an
   exact `(playerId, season, team)` duplicate. (No duplicates exist today; the
   Travis 2021 Louisville + Florida State pair is a legitimate two-teams-in-one-
   season shape the key must keep allowing.)

The `class_year` contamination propagates to the derived `roster_flags`
(decision 0021): `fifth_year_career` is `any(class_year == 5L, na.rm = TRUE)`,
so a pre-2020 player can only be flagged fifth-year if their "class" is a
coincidental year ending in a 5 (2015 → class-5-looking) — a false signal with
no relationship to eligibility.

## Decision

- **`clean_roster()` coerces `class_year` outside the plausible 1-5 range to
  `NA_integer_`**, the same precedent as the weight coercion (decision 0009):
  a value the source demonstrably does not mean what the dictionary says is
  recorded as unmeasured, not carried as garbage.
- **`contract_roster()` adds two checks:**
  - `rows_distinct(playerId, season, team)` — the player-team-season key is
    unique; a player on two teams within a season remains allowed (team is part
    of the key).
  - `col_vals_between(class_year, 1, 5, na_pass = TRUE)` — the cleaned range is
    enforced, so any future contamination re-enters through a red contract,
    not silently.
- **`fifth_year_career` semantic change is accepted:** for pre-2020 players the
  flag becomes structurally `FALSE` (their class is NA), meaning it now
  measures *observed fifth-year classes*, not *all* fifth-year careers. The
  redshirt flags proper (`redshirt_season`/`redshirt_career`) are unaffected —
  they are built on stat gaps, not `class_year`.

## Alternatives considered

- **Impute a class from career position** (e.g. first observed season → 1):
  fabricates a signal from coverage gaps; rejected — it would convert the
  roster-coverage blind spot into a feature.
- **Keep year-valued rows and flag them** (`class_year_trusted` column):
  preserves the raw signal but keeps garbage in the keyed column and forces
  every consumer to remember the filter; the flag-and-filter split is exactly
  what decision 0009 moved away from for weight.
- **Relax the dictionary to "1-5 or a year"**: makes the contamination
  permanent and poisons any class-based feature downstream.

## Consequences

- **The contract is red against the currently published `roster.parquet`** and
  will abort `tar_make()` via the `contract_gate` (decision 0023) until a
  refresh-mode rebuild re-cleans and the `data-latest` release is re-published.
  Merge order is: this change → data refresh → publish → merge; a track-mode
  CI/site build against the old asset fails by design.
- `roster_flags` / `career_summary` / audit counts change on the next refresh:
  ~123k rows lose a `class_year` value, and `fifth_year_career` prevalence
  collapses for pre-2020 classes. Diffs in the audit log should be attributed
  to this decision, not to ingest drift.
- Anything downstream that consumed `fifth_year_career` as a "redshirt-ish"
  signal now sees a coverage-honest but era-limited flag; era interactions
  (pre/post 2020) must be modeled explicitly rather than assumed away.
- Follow-on candidate from the same post, tracked separately: a **usage-based**
  redshirt proxy (attempts/games thresholds), since stat-presence flags miss
  quiet careers (Marchiol's two real redshirts, Nelson's 3-attempt USC year)
  and over-flag zero-volume backups (Burrow's 2015).

## Outcome / what we learned

_Filled in later._

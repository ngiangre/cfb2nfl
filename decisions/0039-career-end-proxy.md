# 0039 — Career endings: an injury-shaped early-stop proxy, not an injury label

- **Status:** Accepted
- **Date:** 2026-11-05

## Context

Issue #51 asks how many college players had career-ending injuries. CFBD has no
injury feed (`plans/explore-questions.md`, questions 3 and 11), so the question
can only be read from absence patterns: a career that stops while NCAA
eligibility remains, with no NFL entry and no transfer, is consistent with an
injury but equally with a walk-on quitting, an academic exit, or a move to a
school outside the roster data. The eligibility clock (decision 0024) and the
outcome labels (decision 0032) already exist, so the proxy can be built without
new ingest.

## Decision

Add a derived `career_end` table (`career_end_status()`, `R/career_end.R`), one
row per career from `career_summary()`, with one mutually exclusive category:

- `right_censored`: the career's last roster season is the most recent season in
  the data, or the NFL draft after it is past `last_complete_nfl_draft()`.
  Censored careers are never early stops.
- `drafted` (CFBD picks bridge, any career), `signed_udfa` (name-guarded roster
  match, decision 0014).
- `not_in_model_population`: no stat line and not drafted, so no UDFA label.
- `eligibility_exhausted`: the eligibility clock is used up.
- `eligibility_unknown`: eligibility remains, but the clock start is left-censored
  at the first roster season in the data (2010).
- `transferred_then_stopped`: eligibility remains, more than one school.
- `early_stop` (the **proxy**, `early_stop_proxy`): eligibility remains, a single
  school, no NFL entry, not censored, in the stat-line population.

The eligibility clock is calendar seasons from the first to the last roster
season, minus 2020 (not counted under the NCAA COVID-19 waiver), against five.
Medical hardship waivers and redshirt rules are not observable.

The table is derived and bundled in DuckDB only (decision 0021). Its contract is
`contract_career_end()`: row count equals the career universe, categories are
exhaustive and mutually exclusive, and the proxy flag is exactly the early-stop
category with its defining conditions.

## Hypotheses / expectations

- Early stops are the largest undrafted, uncensored category among stat-line
  careers. About a fifth are single-season careers, so the proxy measures early
  exits as much as injuries.
- The proxy cannot be validated against injuries without an external source. It
  is a label for "stopped while eligible", not for "injured".

## Consequences

- Any writing on career-ending injuries must say "early stop (proxy)" and cite
  this record. The word "injury" stays out of the category names and summaries.
- Careers outside the stat-line population get no UDFA label, so the
  `not_in_model_population` bucket stays unresolved. Resolving it means a
  roster-side name guard over `nfl_rosters`, a separate change.
- Issue #51 part 2 (injured versus benched from game gaps) plugs into this table
  as an additional per-career signal, keyed on `playerId`; it is not part of this
  record.

## Outcome / what we learned

_Filled in later._

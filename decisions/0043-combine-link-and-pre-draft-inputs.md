# 0043 — NFL combine: tiered name-guarded link to CFBD ids, kept as pre-draft inputs

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

Issue #45 asks for NFL Scouting Combine results joined to a player's college
career. nflverse publishes them (`nflreadr::load_combine()`, no API key, the
decision 0014 source): one row per invitee with height, weight, 40, bench,
vertical, broad jump, 3-cone and shuttle, plus the draft slot when drafted.
The table has no CFBD id. Its `cfb_id` is a Sports-Reference id, and its
school names use PFR spellings ("Boston Col.", "Miami (FL)", "Mississippi").

Facts from the 2010–2026 pull (5,710 invitees) that shaped the design:

- nflverse attaches draft info by name. Eight invitees carry a **different
  year's** pick (a namesake's: Jack Williams, Azusa Pacific, 2000 combine, given
  a 2008 pick), and three pick slots are claimed by two invitees each (Derrick
  Johnson CB and OLB, Texas, 2005).
- About 5–15% of CFBD `picks.collegeAthleteId` values per class never appear in
  `roster` or `player_stats` (e.g. Chris Conte, 2011: pick id 2266247, career
  id 238198). A slot link alone would attach an id that joins no career.
- CFBD `/roster` carries no names; names exist only in `player_stats` (players
  who logged a stat) and `picks`.
- The source's draft columns lag the draft: the 2026 combine (319 invitees)
  has no draft slots yet.

## Decision

**Ingest** `combine` like the other nflverse tables (`ingest_combine()`,
`clean_combine()`: height to inches, numeric drills, out-of-range values to
`NA` per `combine_ranges`, wrong-year draft columns and their `pfr_id`
nulled).

**Link** (`link_combine()`) in tiers, each name-guarded, recording the tier in
`link_method`:

1. `draft_slot`: `(draft_year, draft_round, draft_ovr)` == CFBD picks
   `(year, round, overall)`, the `link_nfl_draft()` bridge. Accepted when the
   names are `name_variant()`s **or** the schools agree, which admits nicknames
   (Ziggy / Ezekiel Ansah, Bud / Alvin Dupree) without trusting a slot whose
   name and school both disagree. A slot claimed by two invitees skips this
   tier.
2. `name_school`: the CFBD player whose `normalize_name()` agrees, whose last
   season before the draft is `draft_year - 1` or `- 2`, and whose team that
   season matches the combine school through `school_key()` (generic
   abbreviation rules plus a short hand-kept crosswalk). Two candidates link
   nothing (the decision 0013 precedent). This tier also replaces a slot id
   that never appears in the college data.
3. `unmatched`: kept with `athlete_id = NA`, never dropped.

An id reused across people (decision 0022) links only with a roster season
within three seasons before the draft, and an id links at most once per
combine. `pfr_agrees` records whether the invitee's `pfr_id` equals nflverse
draft picks' at the same slot.

**Publish the linked table.** The link runs inside the `combine_file` asset, so
`combine.parquet`, the DuckDB `combine` table and `inst/dict/combine.yml` share
one schema (decision 0018), as `outcomes` does. A change to the link logic
takes effect on the next refresh, which costs no CFBD calls for this table.

**Pre-draft, not in-career.** The combine follows the final college season.
Measurables are fair inputs for a model scored at draft time, not for the
in-career forecasts, so `combine` stays off `model_table` and the `outcomes`
eligibility clock. Only invitees are measured: "no combine record" is a
category to model, not a value to impute.

*Rejected:* joining on `cfb_id` (different namespace); slot only (leaves every
undrafted invitee and the dead pick ids unlinked); name only (collisions, the
decision 0013 hazard); fuzzy names in tier 2 (no slot to back them up).

## Hypotheses / expectations

- Drafted invitees from draft year 2013 on link at ≥ 95%. Observed: 99.7%.
- Tier 2 is precise. Scored blind on 3,016 slot-linked invitees from 2011 on
  (draft columns removed), it recovered 81.6% with 99.8% agreement (6 wrong).
- Undrafted invitees from 2011 on link at ≥ 60%. Observed: 78.1%; half of
  the unmatched are offensive linemen with no college stat line.
- The slot `pfr_id` cross-check agrees everywhere. Observed: 3,428 of 3,428.

`contract_combine()` enforces these floors (95% / 60% / ≤ 1% pfr
disagreement), key uniqueness, drill ranges, one id per combine, and exact
row preservation through the link in refresh mode; the audit log reports
`pct_linked` (89.4% overall).

## Consequences

- Undrafted linemen stay mostly unmatched until CFBD roster names are ingested
  (`/roster` returns `firstName`/`lastName`; `clean_roster()` drops them).
  Adding them is a schema change, so it needs a full roster refresh.
- 2010 undrafted invitees cannot link (their final season, 2009, predates the
  CFBD window).
- The 2026 class is all treated as undrafted until nflverse fills its draft
  columns; the name_school tier still links 85% of it.
- `school_key()`'s crosswalk is hand-kept; a new PFR spelling falls through to
  `unmatched` and shows up as a lower `pct_linked`, not a wrong link.

## Outcome / what we learned

_Filled in later._

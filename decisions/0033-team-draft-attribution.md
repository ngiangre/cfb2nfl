# 0033 — Credit draft picks to the final pre-draft roster team (team_draft)

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

The conference and team series (`plans/conferences-teams.md`) asks which
conferences and teams send players to the NFL, per player they produce. The
picks table's own conference names are legacy and leave about 150 picks
untiered, and offensive linemen almost never carry a stat line, so a
stat-line denominator would drop them from any team or position rate.

## Decision

Build two derived tables (decision 0021: DuckDB bundle only, not published
parquet), `team_season` and `team_draft`:

- **Attribution:** a draftee is credited to the team of their final roster
  season before the draft year, and to that season's conference and tier. An
  undrafted player is credited to their final roster season.
- **Denominator:** exits meeting an eligibility proxy: three or more roster
  seasons, or drafted, or signed as a UDFA.
- **Position group:** the final-season roster position, mapped by
  `position_group()` (nine groups plus "Position not recorded").
- **Record:** win percentage from `games` for every division; SP+ as the FBS
  strength check. Non-FBS conferences outside the tier lookup fall back to
  tier 1.
- **Scope:** rates use draft classes 2014 and later; FBS teams individually,
  FCS and below in aggregate.

Alternatives not picked: `picks.collegeConference` (legacy names); a
stat-line denominator (drops offensive line); raw counts (no rate);
any-season credit (multi-team double counting, see the coaches post).

## Hypotheses / expectations

- Attributing to the final roster team covers at least 93% of id-bearing,
  non-reused picks from 2014 on (contract `contract_team_draft()`).
- Offensive line, once counted by roster rather than stat lines, shows a
  draft rate comparable to other position groups.

## Consequences

- 94.6% of 2014+ id-bearing picks are attributed (3,129 of 3,307 at
  2026-10-31); the rest have no roster season before the draft.
- Offensive-line UDFAs are undercounted, because UDFAs are only linked for
  players with a stat line.
- Players who transfer to a school outside roster coverage look like exits.
- Picks are restricted to the 2010-2027 window and the most recent pick is
  kept, matching decision 0011, because old picks share ids with modern
  players (Royce Smith 1972 / Roquan Smith 2018).
- The eligibility proxy is left-truncated before about 2013 exits.
- The 2022 roster-coverage jump (307 teams versus about 225) creates
  one-season listings that are counted as exits.
- 24 draftees are credited two or three seasons before their draft.
- Teams that played no games in a season (UAB 2015-16, COVID opt-outs in
  2020) carry their conference from the previous (else next) season,
  flagged `conference_filled`. Low-division teams whose games list no
  conference keep an NA conference and are tiered 1.

## Outcome / what we learned

_Filled in later._

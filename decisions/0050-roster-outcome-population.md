# 0050 — The outcome and model population is every roster player-season

- **Status:** Accepted
- **Date:** 2026-11-24
- **Supersedes:** the population (grain) and the imputed high-school year of
  decision 0032; the v1 "denominator = players with a stat line" rule

## Context

Decision 0032 built `outcomes` on `ps_pop`, player-seasons with a stat line.
Checking players at the extremes (2011-2026 drafts) showed what that leaves
out:

- 916 of 4,095 picks have no stat line at all. 444 are offensive linemen or
  long snappers. Most of the rest are defenders drafted 2011-2016: CFBD
  `player_stats` has no `defensive` category before 2016, so about 4.9k
  players per season carry a stat line, then about 10k from 2016.
- Rosters are complete: FBS teams list 100 to 150 players every season from
  2010, 14-16% linemen. 100% of stat player-seasons have a roster row (96.5%
  in 2020, 95.7% in 2021), and 52% of roster player-seasons have no stat
  line.
- A final season without a stat line made `build_outcomes()` move a later
  NFL entry onto the last stat row, whose `draft_year`, `years_since_hs` and
  `draft_eligible` then described the wrong draft (234 drafted rows, e.g.
  Kenyon Green's 2022 pick on his 2019 row, flagged not eligible).
- The imputed `hs_grad_year` (first stat season minus one) started the clock
  too late for the 15,603 imputed players on a roster before their first stat
  line.

## Decision

- **Grain:** every roster player-season of a player in `career_summary()`
  (recycled ids excluded, decision 0022), plus any stat-line player-season
  without a roster row (`outcomes_backbone()`). `has_stat_line` marks the
  stat-line seasons, so the old population is one filter away.
- **Tier:** every row carries the season-aware tier of its team, from
  `team_season` (decision 0003 lookup, with its nearest-season fill for
  roster-only team-seasons). The contract fails on a missing tier rather than
  defaulting.
- **Draft year:** a row's `draft_year` is the draft its outcome is about, and
  the eligibility clock is computed against it. That is `season + 1`, except
  on a player's last row when the NFL entry comes one year later.
- **Imputed high-school year:** the earlier of the first roster and first
  stat season, minus one.
- **First roster season:** carried per player, with a flag on that season's
  row. It is not an exclusion: 41 of 2,927 picks (1.4%) whose roster starts
  in 2011 or later, and about 140 undrafted signings, entered the NFL right
  after their first roster season, nearly all transfers from programs the data
  does not cover (Bruce Irvin, Cordarrelle Patterson, Kyle Long, Cody Mauch,
  Jabril Cox).
- **Undrafted debut window:** an NFL debut must come after the last roster
  season, not the last stat season. A debut while still on a college roster
  is a namesake.
- **Model population:** the same roster backbone (task #104).

Not chosen: excluding each player's first roster season as never
draft-eligible (the 1.4% above), and keeping the stat-line population with
more late-entry special cases.

## Hypotheses / expectations

- Drafted players in the population rise by roughly the number of picks with
  no stat line whose id is on a roster.
- Per-season draft rates fall, because the denominator gains backups,
  redshirts and scout-team seasons.
- Position comparisons get fairer: linemen and pre-2016 defenders stop being
  thin, selected groups.

## Consequences

| | Stat line (0032) | Roster (0050) |
|---|---|---|
| Rows | 160,771 | 336,241 |
| Players | 68,932 | 134,985 |
| Draft-eligible rows | 86,800 | 181,009 |
| Drafted players | 3,206 | 3,803 |
| Undrafted signings | 4,337 | 4,305 |

- Of the eligible-row increase, 15,603 rows come from the earlier imputed
  high-school year alone (86,800 to 102,403 before the backbone changed).
- The stricter undrafted debut window drops 30 links that were namesakes.
- **65,449 players have no name.** The cleaned roster drops CFBD's first and
  last names, so a roster-only player who was never drafted gets no
  recruiting match (an imputed high-school year) and no undrafted-signing
  match. Adding the names back means re-pulling `/roster` (about 17 CFBD
  calls) and publishing the roster's new columns.
- Every post that reads `outcomes` moves and must state its population
  (#105-#110). Downstream target grains (`career_end_status()`, `exits`,
  `team_draft`, the explorer player outcomes) do not change.
- Publishing goes through `data-raw/refresh-outcomes.R` (0 CFBD calls), in
  the same sitting as the merge, Monday to Saturday.

## Outcome / what we learned

_Filled in later._

# 0038 — Player usage: games appeared over team games

- **Status:** Accepted
- **Date:** 2026-11-05

## Context

`player_game` (decision 0035) records one row per player per game with a stat
line, but it does not say how often a rostered player was absent from games
where the team played. Playing time is the first usage signal the box score
can give, and issue #50 asks for it as a table that later analyses can join.
The roster and the stat lines come from different CFBD endpoints, so a player
can appear in one and not the other, and an unscoped join would drop or invent
player-seasons silently.

## Decision

Add a derived table `player_usage` in the DuckDB bundle with one row per
player, season and team. Its universe is the union of roster player-seasons and
stat-line player-seasons, so no player-season with a stat line is dropped. The
columns are `games_appeared` (distinct games with a stat line) and `team_games`
(the team's completed games, the same definition as `team_record()`), the
appearance rate, regular-season counterparts, per-game passing, rushing,
receiving and tackle volumes, the harmonized `position_group`, and the
roster `class_year`. A player-season with no stat line has `games_appeared = 0`
and per-game volumes `NA`.

`player_appearance_sequence()` exposes the per-team-game appeared/not-appeared
flags behind the counts, for issue #51 (career-end proxies from mid-career
absences). It is an in-memory helper, not a published table.

Draft labels are outcome variables and are not stored on `player_usage`. They
are joined only where an analysis needs them, which keeps the derived table a
pure usage description (decision 0032 keeps labels on `outcomes`).

Alternatives not picked: deriving appearances from the box score alone (drops
players with no stat line in any game, which is most of the roster), and a
wide per-game table keyed on game (too large and not a player-season grain).

## Hypotheses / expectations

- Most rostered player-seasons log no stat line in any game. Checked: 75.5% of
  the 2019 to 2025 population logged none.
- Offensive linemen rarely log a stat line, so the box score understates their
  playing time. Checked: 0.5% of offensive-line player-seasons logged one.
- Drafted player-seasons log a stat line in a larger share of team games than
  the rest, within position group. Checked on draft-eligible single-team
  seasons: 81% against 50% logged a line, and the gap holds in every position
  group with enough drafted cases.

## Consequences

- `contract_player_usage()` enforces one row per (playerId, season, team), that
  `games_appeared <= team_games`, that the summed appearances equal the rows of
  `player_game`, and that `team_games` ties to `team_record()`. A failure aborts
  `tar_make()` through `contract_gate`.
- Class year is recorded from about 2019, so class-year comparisons are limited
  to 2019 onward and are `NA` for earlier seasons.
- A stat line is an imperfect proxy for playing time. Offensive linemen and
  special teamers are under-recorded, and the draftee comparison is
  unadjusted for team quality or depth chart. The blog post states both.
- Any snap-count or play-participation signal would need a new source; this
  table does not claim one.

## Outcome / what we learned

_Filled in later._

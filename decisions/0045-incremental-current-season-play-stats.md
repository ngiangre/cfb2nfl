# 0045 — Current-season play stats are pulled game by game, every week

- **Status:** Accepted (amends 0031, point 4)
- **Date:** 2026-11-08

## Context

Decision 0031 made `/plays/stats` (athlete attribution per play, one call
per game) opt-in, backfilled one whole season per refresh, so a routine
refresh never spent ~2,100 calls. In practice a season is ~1,700 calls (only
games with play-by-play need a call; `games` also lists lower-division games
CFBD has no plays for), and a completed game's play stats are a fixed
record, so a weekly job only needs the games it has not pulled yet: ~110-140
a regular-season Sunday. The user wants the current season's play stats
kept current on `data-latest`, with past seasons backfilled ad hoc.

How often CFBD revises a game after the fact is not known for `/plays/stats`.
For the box scores from the same ESPN feed (`/games/players`), two pulls of
2026 weeks 1-9 about a day apart (2026-11-07/08) differed in 0 of 596,140
rows, but every game in that comparison was already 6+ days old; corrections
in the first days after a game were not observed either way.

## Decision

1. For the **current season**, every refresh pulls the games with plays that
   the published `play_stats` lacks, plus every game that kicked off in the
   last 8 days, re-pulled once (`play_stats_games_to_pull()`). The weekly
   `data-current.yaml` run therefore keeps the season current with no flag.
2. Pulled games **replace their own rows** in the published table
   (`assemble_play_stats()`); every other game is kept. A game that returns
   nothing keeps its published rows (an empty response never deletes data)
   and, if it was never published, is retried on the next run.
3. Each re-pull reports how many play-stat rows changed, so the revision rate
   is measured rather than assumed. The count goes to the
   `data-current.yaml` run summary (`CFB2NFL_REVISION_LOG`). The measurement
   is **temporary**: after the 2026-11-15 and 2026-11-22 runs (weeks 10 and
   11, each re-pulled about a week after its first pull), the result is
   recorded below and the re-pull is either kept (if games do change) or
   removed with its logging (if they do not). Tracked in issue #68.
4. **Past seasons** stay opt-in exactly as in 0031:
   `CFB2NFL_PLAYS_STATS=true` with an explicit season selection.
5. The 2026 season to date (1,277 games) is caught up once, by a one-off run
   of the same functions outside `tar_make()`, and published.

Alternatives not picked: re-pulling the whole current season weekly (~1,300+
calls a week by November); pulling a week late so games have settled (no
measurement of revisions, stats a week stale); no re-pull at all (a CFBD
correction in the first days would be missed silently).

## Hypotheses / expectations

- In-season a Sunday run costs ~40-55 base calls plus ~220-280 for play
  stats (new week + re-pulled prior week), ~1,200 a month, leaving room for
  one past-season backfill (~1,700) under the 5,000-call quota.
- Revisions to a game's play stats after the first pull are rare; if the
  re-pull reports ~0 changed rows for several weeks, the 8-day window can be
  shortened or dropped to halve the weekly cost.

## Consequences

- `data-current.yaml` now spends play-stats calls every in-season Sunday.
- A full refresh must start from the published `play_stats.parquet`
  (`data-refresh.yaml` downloads it), or it would re-pull the season so far.
- Games CFBD never posts stats for are retried every week (a handful of
  calls); none have been seen yet.

## Outcome / what we learned

2026-11-08 catch-up: 1,277 calls for 1,277 games (weeks 1-10), all
returned rows: 313,802 play-stat rows, at most 341 in one game (far below
the 2,000-row cap), every `athleteId` on a roster. 27 of the 31 stat types
occur; **no `Tackle` credits at all** in 2026 (the type exists in the
dimension), so tackle features cannot come from `play_stats`; use the box
scores (`game_player_stats` defensive TOT/SOLO) instead.

_To fill in:_ the re-pull change counts from the 2026-11-15 and 2026-11-22
run summaries, and whether the re-pull was kept or removed.

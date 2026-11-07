# cfb2nfl data model — ERD & query guide

This document describes how the cfb2nfl tables relate and how to reason over
them for the project's core question: **what shapes a college football player's
path to the NFL draft, and how well can it be forecast from information
available during their career?**

The authoritative, column-level schema for each table lives in the data
dictionaries next to this file, one YAML per table:

| Table | Grain | Dictionary |
|-------|-------|------------|
| `picks` | one drafted player | [`dict/picks.yml`](dict/picks.yml) |
| `player_stats` | **long**: player-season-category-statType-stat | [`dict/player_stats.yml`](dict/player_stats.yml) |
| `roster` | one player-season on a team roster | [`dict/roster.yml`](dict/roster.yml) |
| `coaches` | one head-coach-season | [`dict/coaches.yml`](dict/coaches.yml) |
| `teams` | one team (program) — DISPLAY only | [`dict/teams.yml`](dict/teams.yml) |
| `conference_tiers` | season × conference | [`dict/conference_tiers.yml`](dict/conference_tiers.yml) |
| `recruiting` | one HS recruit | [`dict/recruiting.yml`](dict/recruiting.yml) |
| `games` | one game (metadata + result) | [`dict/games.yml`](dict/games.yml) |
| `game_team_stats` | **long**: team-game-category-stat | [`dict/game_team_stats.yml`](dict/game_team_stats.yml) |
| `game_player_stats` | **long**: player-game-category-statType-stat | [`dict/game_player_stats.yml`](dict/game_player_stats.yml) |
| `nfl_draft_picks` | one NFL draft pick | [`dict/nfl_draft_picks.yml`](dict/nfl_draft_picks.yml) |
| `nfl_rosters` | one player-season on an NFL roster | [`dict/nfl_rosters.yml`](dict/nfl_rosters.yml) |
| `nfl_player_stats` | one NFL player-season (regular season) | [`dict/nfl_player_stats.yml`](dict/nfl_player_stats.yml) |
| `combine` | one NFL Scouting Combine invitee (pre-draft measurables) | [`dict/combine.yml`](dict/combine.yml) |
| `stat_taxonomy` | one (category, statType) pair | [`dict/stat_taxonomy.yml`](dict/stat_taxonomy.yml) |
| `ps_change` | one player-season (stat-line grain) + change features | [`dict/ps_change.yml`](dict/ps_change.yml) |
| `career_summary` | one player's college career | [`dict/career_summary.yml`](dict/career_summary.yml) |
| `player_game` | one player in one game (stat line + team, opponent, Elo, team games) | [`dict/player_game.yml`](dict/player_game.yml) |
| `team_season` | one team in one season (every division) | [`dict/team_season.yml`](dict/team_season.yml) |
| `team_draft` | team × final college season × position group | [`dict/team_draft.yml`](dict/team_draft.yml) |
| `outcomes` | one player-season in the model population (person-period labels) | [`dict/outcomes.yml`](dict/outcomes.yml) |
| `audit_log` | one audited pipeline step | [`dict/audit_log.yml`](dict/audit_log.yml) |

**Bundle-only tables.** Five tables are **derived in-pipeline** and not
published as parquet, like `stat_taxonomy`: `ps_change` (the link chain plus
change features; it carries the `drafted` label), `career_summary` (roster
collapsed to the career grain), `player_game` (the player × game grain),
`team_season` and `team_draft` (the team grain). They are built from other
cleaned tables, so they are materialized into the DuckDB bundle and documented
with dictionaries but need no release asset before a track-mode build; all
carry contracts and audit rows like the cleaned tables. The slimmed
`audit_log` (the lineage log) is bundled too.

**What earns a place here (decision 0041).** A derived table joins the data
model once a second investigation needs it, or once another table is built
from it. Until then it is built where it is used:

- **On the fly in the post**, from an exported, tested function:
  `flag_redshirt()` (redshirt flags), `career_end_status()` (how a career
  ended), `build_season_arcs()`, `build_game_production()`, and
  `build_player_season_stats()` (wide stats).
- **As a contract-checked pipeline step**, read with `targets::tar_read()`,
  when the logic is complex enough that a data contract should guard it on
  every build: `picks_nfl` (`link_nfl_draft()`, the name-guarded draft-slot
  bridge to nflverse), `position_path`, and `player_usage`.

Every bundle also carries two generated metadata tables:

- **`_schema_manifest`** — one row per bundled table with its grain/key (read
  from `inst/dict/*.yml` at build time) and the dictionary path. A bundled
  table without a dictionary shows up as `documented = FALSE`, so schema drift
  is visible inside the asset itself.
- **`_meta`** — the refresh timestamp and the last COMPLETE college season
  (`last_complete_cfb_season`) and NFL draft class (`last_complete_nfl_draft`).
  Later seasons may be partial (in-progress season, unsigned draft class):
  out-of-time model frames and "career completed" logic must stop at these
  values.

`stat_taxonomy` is **package data**, not a published parquet: it is hand-authored
in `inst/extdata/stat_taxonomy.csv`, read via `stat_taxonomy()`, and materialized
into the DuckDB bundle (so SQL users get phase/labels). It maps each
`(category, statType)` in the long `player_stats` to a game **phase**
(offense / defense / special_teams) and a plain-language `label`, making the
stats interpretable — a bare `TD` becomes "Passing touchdowns" vs "Defensive
touchdowns". Keyed at `(category, statType)` grain because a category alone can
be phase-ambiguous (`fumbles/FUM` is offense, `fumbles/REC` is defense).
`contract_stat_taxonomy()` enforces coverage of every pair present in
`player_stats`.

The dictionaries document the **cleaned** schemas (e.g. `clean_picks` adds
`playerId`/`drafted`). Both published assets carry exactly these cleaned tables:
the `data/*.parquet` files and the DuckDB bundle share one identical schema per
table.

## The DuckDB asset

`data/cfb2nfl.duckdb` bundles every cleaned table into one SQL-queryable file.
It is built by the **`duckdb_file`** target in `_targets.R` (`build_duckdb()`)
from the cleaned, contract-checked tables, the same tables written to the
`data/*.parquet` assets, so parquet and DuckDB carry one identical schema per
table, matching the dictionaries above, and published alongside the parquet on
the `data-latest` GitHub release. Table names match the rows above
(`conference_tiers`, not `tiers`).

```r
library(DBI)
con <- dbConnect(duckdb::duckdb(), "data/cfb2nfl.duckdb", read_only = TRUE)
dbListTables(con)
dbGetQuery(con, "SELECT COUNT(*) FROM player_stats")
```

## Entity-relationship diagram

```mermaid
erDiagram
    player_stats }o--|| roster : "playerId, season"
    player_stats ||--o| picks : "playerId"
    player_stats }o--|| coaches : "team=school, season"
    player_stats }o--|| conference_tiers : "conference, season"
    player_stats }o--|| teams : "team (display)"
    recruiting |o..o| player_stats : "playerId (name-guarded)"
    games ||--o{ game_team_stats : "gameId == id"
    games ||--o{ game_player_stats : "gameId == id"
    game_player_stats }o--|| player_stats : "playerId (shared athlete id)"
    game_player_stats ||--|| player_game : "playerId, gameId (one row per stat line)"
    games ||--o{ player_game : "gameId == id"
    team_season ||--o{ player_game : "team, season (team_games)"
    picks |o..o| nfl_draft_picks : "draft slot (year, round, overall), name-guarded"
    outcomes }o..o{ nfl_rosters : "gsis_id (name-guarded)"
    ps_change }o--|| outcomes : "playerId, season"
    ps_change }o--o| roster : "playerId, season"
    nfl_draft_picks ||--o{ nfl_rosters : "gsis_id, season"
    nfl_draft_picks ||--o{ nfl_player_stats : "gsis_id, season"
    combine }o..o| player_stats : "athlete_id = playerId (name-guarded)"
    combine |o..o| picks : "draft slot (draft_year, draft_round, draft_ovr), name-guarded"
    roster |o--o{ career_summary : "playerId (collapsed)"
    roster |o--o{ team_season : "team, season (aggregated)"
    games |o--o{ team_season : "team, season (aggregated)"
    team_season ||--o{ team_draft : "team, season"
}
```

Solid lines are trustworthy joins; dotted lines (`recruiting`, and the NFL
links) are **name-guarded** links, not plain key joins (see below).

## Join keys & namespaces

There are six distinct join namespaces. Using the wrong one silently produces
wrong rows, so they are called out explicitly.

1. **College athlete id (`playerId`, string) — the canonical player key.**
   `player_stats.playerId`, `roster.playerId`, and `picks.playerId` (coerced from
   `collegeAthleteId`) are one namespace. Join players on this id, **never on
   name**. `roster` adds `season` for the player-season grain.

2. **Team / school name (string).** `player_stats.team` = `roster.team` =
   `coaches.school` = `teams.team`. `teams` is DISPLAY metadata only
   (logos/colors); keep it off the model path.

3. **`(team, season)`** links a player-season to its head coach in `coaches`
   (a school can have >1 head coach in a season, so this is many-to-one and can
   inflate rows — intentional).

4. **`(conference, season)`** links to `conference_tiers`, which is
   **season-aware** (realignment over 2010–2026). Use the lookup; do not
   hard-code tiers.

5. **Draft slot then `gsis_id` (the NFL side).** CFBD `picks` bridges to
   `nfl_draft_picks` by draft slot — `(year, round, overall)` ==
   `(season, round, pick)` — **not** by `nflAthleteId` (a different namespace).
   From `nfl_draft_picks`, `gsis_id` is the key into `nfl_rosters` and
   `nfl_player_stats` (both keyed `(gsis_id, season)`).

6. **CFBD game id (`games.id` == `game_*_stats.gameId`, integer).** The
   game-level namespace. Both game-stat tables also carry `season`/`week`/
   `seasonType` attached at ingest, so period filters need no join to `games`
   (note postseason weeks renumber from 1 — filter by `seasonType` too).
   `game_player_stats.playerId` is the **shared** college athlete id
   (namespace 1), so game-level features join the career backbone directly;
   `game_team_stats.teamId` is CFBD's team-id namespace (distinct from athlete
   ids — join teams by name). `player_game` is the derived player × game grain
   on the same keys: `(playerId, gameId)` is unique, its `gameId` joins
   `games.id`, and `team_games` is the team's games played in the season (the
   denominator for games appeared).

### Two namespaces that look joinable but are not

- **`recruiting.playerId` is NOT the shared college-athlete namespace.** The
  CFBD `/recruiting/players` `athleteId` collides across different people. Never
  join `recruiting` on id alone — go through `link_recruiting()`, which
  name-guards the join. Genuinely unrated recruits are absent; model "unrated"
  as a real category rather than imputing.
- **`picks.nflAthleteId` is NOT the nflverse id.** It shares nothing with
  nflverse `gsis_id`/`espn_id`; use the draft-slot bridge above.
- **`combine.cfb_id` is a Sports-Reference id, not the CFBD athlete id.** Join
  combine invitees on `combine.athlete_id`, which the pipeline matches by draft
  slot, then by name + school + final season (`link_method` says which;
  `unmatched` rows carry `NA`). Mostly undrafted linemen go unmatched, because
  CFBD only names players who logged a stat.

## Reasoning over the tables for the project's questions

**Population / outcome (v1).** The unit is a player-season with a qualifying
stat line in a draft-eligible season; the positive label is `drafted`. The
`outcomes` table materializes this at the **person-period** grain: one row per
player-season in the model population, with the
eligibility clock (`hs_grad_year`, `draft_eligible`, `eligible_season_index`),
the drafted / NFL-entry / NFL-success labels (`outcome_*` columns), and the
survival bookkeeping (`years_to_nfl_entry` + `nfl_entry_event`,
`status_end_of_season`, `outcome_observed_d` right-censoring). Models query
the dependent variable directly from `outcomes` — no further derivation.
Build the feature backbone from `player_stats` (which is **long** — pivot
`category`/`statType`/`stat` into position-relevant columns), attach roster
physicals, coaching and tier context; the `outcomes` table is the label
source. The older per-season `drafted` flag remains on `ps_change` for
backward compatibility.

**Career inputs vs. outcomes — guard against leakage.** Everything on the NFL
side (`nfl_draft_picks`, `nfl_rosters`, `nfl_player_stats`) is an
**outcome/label**, never a model input. "How long they last" is defined
primarily as **distinct NFL roster seasons** (counts linemen/special-teamers who
accrue no box-score stats), complemented by career games and last active season.
These are **right-censored** for recent classes still active — treat them as "≥"
outcomes.

**Pre-draft inputs.** `combine` measurables are taken after the final college
season and before the draft. They are fair inputs for a model scored at draft
time, but not for the in-career forecasts, which must exclude them. Only
invitees are measured, so "no combine record" is a real category (selection
signal), not a value to impute.

**Out-of-time evaluation.** A model must never see data from on/after the draft
class it predicts. When querying for a training frame, filter seasons strictly
before the target draft class.

**Watch for silent row loss.** Validate row counts before and after every join;
the `(team, season)` coach join can *inflate* rows, and id coercions or
name-guarded links can *drop* them.

### Example queries

Drafted rate by conference tier (label side). NOTE the grain: aggregate the
**long** `player_stats` to player-season grain BEFORE joining — a naive join at
stat-line grain counts every player ~15x.

```sql
SELECT t.tier_label,
       COUNT(*)                         AS player_seasons,
       SUM(CASE WHEN p.playerId IS NOT NULL THEN 1 ELSE 0 END) AS drafted
FROM (SELECT DISTINCT playerId, season, conference FROM player_stats) s
JOIN conference_tiers t
  ON s.conference = t.conference AND s.season = t.season
LEFT JOIN picks p
  ON s.playerId = p.playerId
GROUP BY t.tier_label
ORDER BY t.tier_label;
```

Per-season passing yardage from the long table (filter one stat, then sum):

```sql
SELECT season, SUM(TRY_CAST(stat AS DOUBLE)) AS passing_yards
FROM player_stats
WHERE category = 'passing' AND statType = 'YDS'
GROUP BY season
ORDER BY season;
```

Per-season games played (offensive snaps proxy) from the game-level long
table — `game_player_stats` carries `season`/`week`/`seasonType` itself, and
`playerId` is the shared athlete id, so no join is needed to count games:

```sql
SELECT playerId,
       season,
       COUNT(DISTINCT gameId) AS games_played
FROM game_player_stats
WHERE seasonType = 'regular' AND category IN ('passing', 'rushing', 'receiving')
GROUP BY playerId, season
ORDER BY games_played DESC
LIMIT 20;
```

NFL longevity (distinct roster seasons) for players who reached the NFL, via
the **name-guarded** `gsis_id` that `outcomes` carries (do NOT rebuild the raw
slot join in SQL — the name guard that nulls wrong-person matches lives in the
pipeline):

```sql
WITH linked AS (
  SELECT DISTINCT playerId, gsis_id FROM outcomes WHERE gsis_id IS NOT NULL
)
SELECT l.playerId,
       COUNT(DISTINCT r.season) AS nfl_seasons
FROM linked l
LEFT JOIN nfl_rosters r
  ON l.gsis_id = r.gsis_id
GROUP BY l.playerId
ORDER BY nfl_seasons DESC;
```

Combine 40-yard dash next to each invitee's final college season, through the
linked `athlete_id` (`unmatched` invitees drop out of the
inner join):

```sql
SELECT c.season AS combine_year, c.player_name, c.pos, c.forty,
       r.team, r.season AS final_season
FROM combine c
JOIN roster r
  ON r.playerId = c.athlete_id
 AND r.season = (SELECT MAX(season) FROM roster
                 WHERE playerId = c.athlete_id AND season < c.season)
WHERE c.forty IS NOT NULL
ORDER BY c.forty
LIMIT 20;
```

Self-check the bundle before/after joins using the bundled audit log and
manifest:

```sql
SELECT table_name, grain_key FROM _schema_manifest ORDER BY table_name;
SELECT * FROM _meta;  -- refreshed_at + last complete season/draft class
```

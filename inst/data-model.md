# cfbstats data model — ERD & query guide

This document describes how the cfbstats tables relate and how to reason over
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
| `stat_taxonomy` | one (category, statType) pair | [`dict/stat_taxonomy.yml`](dict/stat_taxonomy.yml) |
| `ps_change` | one player-season (stat-line grain) + change features | [`dict/ps_change.yml`](dict/ps_change.yml) |
| `roster_flags` | roster player-season + eligibility flags | [`dict/roster_flags.yml`](dict/roster_flags.yml) |
| `career_summary` | one player's college career | [`dict/career_summary.yml`](dict/career_summary.yml) |
| `player_season_stats` | **wide**: player-season-team stat columns | [`dict/player_season_stats.yml`](dict/player_season_stats.yml) |
| `nfl_pick_link` | one draft pick + name-guarded nflverse id | [`dict/nfl_pick_link.yml`](dict/nfl_pick_link.yml) |
| `audit_log` | one audited pipeline step | [`dict/audit_log.yml`](dict/audit_log.yml) |

**Bundle-only tables.** Several tables in the bundle are **derived in-pipeline**
and not published as parquet, like `stat_taxonomy`: they are built from other
cleaned tables (`ps_change` from the link chain, `roster_flags` from roster +
player_stats, `career_summary` from roster, `player_season_stats` from
player_stats — decisions 0021/0026), so they are materialized into the DuckDB
bundle and documented with dictionaries but need no release asset before a
track-mode build. `ps_change` carries the `drafted` label (it sits downstream
of `link_drafted`); `roster_flags` / `career_summary` are leakage-free
roster-derived features; all carry contracts and audit rows like the cleaned
tables.

Two more derived tables are bundled only: `nfl_pick_link` (the name-guarded
draft-slot bridge to nflverse — use it instead of re-running the raw slot join
in SQL, decision 0014) and the slimmed `audit_log` (the lineage log, decision
0005). Every bundle ALSO carries two generated metadata tables (decision 0027):

- **`_schema_manifest`** — one row per bundled table with its grain/key (read
  from `inst/dict/*.yml` at build time) and the dictionary path. A bundled
  table without a dictionary shows up as `documented = FALSE`, so schema drift
  is visible inside the asset itself.
- **`_meta`** — the refresh timestamp and the last COMPLETE college season
  (`last_complete_cfb_season`) and NFL draft class (`last_complete_nfl_draft`).
  Later seasons may be partial (in-progress season, unsigned draft class):
  out-of-time model frames and "career completed" logic must stop at these
  values.

If `ps_change` is bundled, a **`player_season_inputs`** VIEW is also created:
`ps_change` minus the draft-outcome columns (`draft_year`, `draft_round`,
`draft_overall`, `drafted`) — the leakage-safe model input surface, so a SQL
user cannot accidentally select the label into a training frame.

`stat_taxonomy` is **package data**, not a published parquet: it is hand-authored
in `inst/extdata/stat_taxonomy.csv`, read via `stat_taxonomy()`, and materialized
into the DuckDB bundle (so SQL users get phase/labels). It maps each
`(category, statType)` in the long `player_stats` to a game **phase**
(offense / defense / special_teams) and a plain-language `label`, making the
stats interpretable — a bare `TD` becomes "Passing touchdowns" vs "Defensive
touchdowns". Keyed at `(category, statType)` grain because a category alone can
be phase-ambiguous (`fumbles/FUM` is offense, `fumbles/REC` is defense).
`contract_stat_taxonomy()` enforces coverage of every pair present in
`player_stats` (decision 0019).

The dictionaries document the **cleaned** schemas (e.g. `clean_picks` adds
`playerId`/`drafted`). Both published assets carry exactly these cleaned tables:
the `data/*.parquet` files and the DuckDB bundle share one identical schema per
table (decision 0018).

## The DuckDB asset

`data/cfbstats.duckdb` bundles every cleaned table into one SQL-queryable file.
It is built by the **`duckdb_file`** target in `_targets.R` (`build_duckdb()`,
decision 0016) from the cleaned, contract-checked tables — the same tables
written to the `data/*.parquet` assets (decision 0018), so parquet and DuckDB
carry one identical schema per table, matching the dictionaries above — and
published alongside the parquet on the `data-latest` GitHub release. Table names
match the rows above (`conference_tiers`, not `tiers`).

```r
library(DBI)
con <- dbConnect(duckdb::duckdb(), "data/cfbstats.duckdb", read_only = TRUE)
dbListTables(con)
dbGetQuery(con, "SELECT COUNT(*) FROM player_stats")
```

## Entity-relationship diagram

```mermaid
erDiagram
    player_stats }o--|| roster : "playerId, season"
    player_stats ||--o{ player_season_stats : "pivoted wide (playerId, season, team)"
    player_stats ||--o| picks : "playerId"
    player_stats }o--|| coaches : "team=school, season"
    player_stats }o--|| conference_tiers : "conference, season"
    player_stats }o--|| teams : "team (display)"
    recruiting |o..o| player_stats : "playerId (name-guarded)"
    games ||--o{ game_team_stats : "gameId == id"
    games ||--o{ game_player_stats : "gameId == id"
    game_player_stats }o--|| player_stats : "playerId (shared athlete id)"
    picks ||--o| nfl_pick_link : "same slot join, name-guarded"
    nfl_pick_link ||--o| nfl_draft_picks : "draft slot"
    nfl_draft_picks ||--o{ nfl_rosters : "gsis_id, season"
    nfl_draft_picks ||--o{ nfl_player_stats : "gsis_id, season"
    ps_change }o--|| roster_flags : "playerId, season (flags/weights attach here)"
    roster |o--o{ career_summary : "playerId (collapsed)"
}
```

Solid lines are trustworthy joins; the dotted `recruiting` line is a
**name-guarded** link, not a plain key join (see below).

## Join keys & namespaces

There are six distinct join namespaces. Using the wrong one silently produces
wrong rows, so they are called out explicitly.

1. **College athlete id (`playerId`, string) — the canonical player key.**
   `player_stats.playerId`, `roster.playerId`, and `picks.playerId` (coerced from
   `collegeAthleteId`) are one namespace. Join players on this id, **never on
   name**. `roster` adds `season` for the player-season grain.

2. **Team / school name (string).** `player_stats.team` = `roster.team` =
   `coaches.school` = `teams.team`. `teams` is DISPLAY metadata only
   (logos/colors, decision 0008) — keep it off the model path.

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
   ids — join teams by name).

### Two namespaces that look joinable but are not

- **`recruiting.playerId` is NOT the shared college-athlete namespace.** The
  CFBD `/recruiting/players` `athleteId` collides across different people. Never
  join `recruiting` on id alone — go through `link_recruiting()`, which
  name-guards the join. Genuinely unrated recruits are absent; model "unrated"
  as a real category rather than imputing (decision 0013).
- **`picks.nflAthleteId` is NOT the nflverse id.** It shares nothing with
  nflverse `gsis_id`/`espn_id`; use the draft-slot bridge above (decision 0014).

## Reasoning over the tables for the project's questions

**Population / outcome (v1).** The unit is a player-season with a qualifying
stat line in a draft-eligible season; the positive label is `drafted`. Build the
feature backbone from `player_stats` (which is **long** — pivot
`category`/`statType`/`stat` into position-relevant columns), attach roster
physicals, coaching and tier context, then join `picks` to label who was
drafted. This is what the `player_season -> ps_coach -> ps_tier -> ps_draft`
link targets do.

**Career inputs vs. outcomes — guard against leakage.** Everything on the NFL
side (`nfl_draft_picks`, `nfl_rosters`, `nfl_player_stats`) is an
**outcome/label**, never a model input. "How long they last" is defined
primarily as **distinct NFL roster seasons** (counts linemen/special-teamers who
accrue no box-score stats), complemented by career games and last active season.
These are **right-censored** for recent classes still active — treat them as "≥"
outcomes.

**Out-of-time evaluation.** A model must never see data from on/after the draft
class it predicts. When querying for a training frame, filter seasons strictly
before the target draft class.

**Watch for silent row loss.** Validate row counts before and after every join;
the `(team, season)` coach join can *inflate* rows, and id coercions or
name-guarded links can *drop* them.

### Example queries

Drafted rate by conference tier (label side). NOTE the grain: aggregate the
**long** `player_stats` to player-season grain BEFORE joining — a naive join at
stat-line grain counts every player ~15x. (`player_season_stats` already has
the right grain, so it is the easier base table.)

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

Per-season passing yardage straight off the wide table (no pivot needed):

```sql
SELECT season, SUM(passing_yds) AS passing_yards
FROM player_season_stats
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

NFL longevity (distinct roster seasons) for drafted players, via the
**name-guarded** bridge table (do NOT rebuild the raw slot join in SQL — the
name guard that nulls wrong-person matches lives in the pipeline):

```sql
SELECT p.year           AS draft_year,
       p.name           AS player,
       COUNT(DISTINCT r.season) AS nfl_seasons
FROM nfl_pick_link p
LEFT JOIN nfl_rosters r
  ON p.gsis_id = r.gsis_id
WHERE p.gsis_id IS NOT NULL
GROUP BY p.year, p.name
ORDER BY nfl_seasons DESC;
```

Self-check the bundle before/after joins using the bundled audit log and
manifest:

```sql
SELECT table_name, grain_key FROM _schema_manifest ORDER BY table_name;
SELECT * FROM _meta;  -- refreshed_at + last complete season/draft class
```

Redshirt-shaped seasons per season, with the coverage caveat visible:

```sql
SELECT season,
       SUM(has_stats::INT)                                    AS with_stats,
       SUM((NOT has_stats AND redshirt_season)::INT)          AS redshirt_shaped
FROM roster_flags
GROUP BY season
ORDER BY season;
```

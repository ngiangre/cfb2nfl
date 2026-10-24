# CFBD API coverage reference (OpenAPI 5.33.0)

Source of truth: https://api.collegefootballdata.com/api/5.33.0/cfbd-openapi.json
(snapshot in this file reflects that version). Use this document to answer
"could we get X?" and "is getting X feasible?" before writing any `ingest_*()`.

Reading guide:

- **Key** = the natural join key / grain of the response rows.
- **Athlete id namespace** — player ids from `/stats/player/*`, `/games/players`,
  `/plays/stats`, `/player/*`, `/rushing|passing|punting/players/*`,
  `/wepa/players/*`, `/ppa/players/*`, `DraftPick.collegeAthleteId`, and
  `RosterPlayer.id` are ONE namespace (the one our pipeline uses). Known
  caveats apply (id reuse across eras, `athleteId` from `/recruiting/players`
  is NOT in it — decision 0013).
- **Team/conference keys are names**, not ids: `team`/`school` strings join to
  `data/teams.parquet` by name; `teamId` is a separate CFBD numeric namespace.
- **Gated features** (require a higher Patreon tier, per `UserFeatureAccess`):
  `adjustedMetrics`, `weather`, `scoreboard`, `livePlayByPlay`, `graphQl`.
  **This project's key is Patreon level 1**, which unlocks `adjustedMetrics`
  (`/wepa/*`, `/games/{id}/preview/adjusted`); `weather`, `scoreboard`, and
  `livePlayByPlay` remain gated. Confirm with a free `GET /info` call.
- **Cost**: every endpoint call is one quota call (5000/month tier as of
  2026-10). Endpoints that require per-team or per-week fan-out are expensive;
  season-wide single-call endpoints are cheap.

## Games & schedule

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /games` | one game; key `id` | season, week, seasonType, startDate, completed, neutralSite, conferenceGame, venue/venueId, home/away team+conference+classification+points+lineScores, pre/postgame Elo + win probability per side, excitementIndex, attendance, notes, `playoff` (round/seed/bowl) | One call per season (or per team). Already ingested. Elo/win-prob fields are free here — no need for `/ratings/elo` per week. |
| `GET /games/teams` | one team-game; key `(gameId, team)` | teamId, team, conference, homeAway, points, `stats[]` (category/stat strings) | The `game_team_stats` source. Long format. One call per season-year+week or per team. |
| `GET /games/players` | one team-game with nested player categories; key `(gameId, team, category, type, athleteId)` | athlete id + name + stat strings, points, homeAway | The `game_player_stats` source. Nested; already ingested. |
| `GET /games/media` | one broadcast row; key `(gameId, mediaType)` | mediaType (tv/radio/web/ppv/mobile), outlet | Cheap per season+week. Not ingested. |
| `GET /games/weather` | one game; key `gameId` | temperature, dewPoint, humidity, precipitation, snowfall, wind speed/dir, pressure, condition | **Patreon-gated**. Historical weather exists. |
| `GET /games/schedule` | one game within a slate window; key `gameId` | status, broadcast list, odds section (DraftKings/Bovada), watchabilityScore (0–100) | Preview-oriented (active/next week); watchability + odds convenience. |
| `GET /games/{gameId}/preview` | one game | per-team record, ratings (SP/SRS/Elo/CORE/FPI), statistics, key players, recent results, series history | Per-game call (expensive at scale); snapshot semantics, `analysis` nulls after completion. |
| `GET /games/{gameId}/preview/adjusted` | one game | adjusted team metrics, WEPA passers/rushers, kicker PAAR | **Patreon Tier 1 gated**; per-game. Prefer `/wepa/*` endpoints directly. |
| `GET /calendar` | one week; key `(season, week, seasonType)` | start/end dates, first/last game | Tiny; useful for week windows. |
| `GET /scoreboard` | one live/today game | live score, possession, situation, weather, betting | **Gated**; real-time only, not historical. |
| `GET /records` | one team-season; key `(year, team)` | W/L/T totals plus splits: conference/home/away/neutral/regular/postseason, expectedWins | One call per year (whole FBS). Expected wins available. |
| `GET /games` competition/round params | — | filter to playoff rounds | Playoff filtering on the games call itself. |

## Drives & plays (play-by-play)

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /drives` | one drive; key `id` | offense/defense (+conferences), game id, scoring, start/end yardline+time, plays, yards, driveResult, scores at start/end | One call per season+week. `driveResult` gives TD/FG/punt/turnover outcomes. |
| `GET /plays` | one play; key `id` | down/distance/yardsToGoal/yardsGained, period+clock, playType, playText, ppa, scoring, offense/defense + scores | One call per season+week — huge volume. Base for PPA/success derivation. |
| `GET /plays/types` | one playType | id, text, abbreviation | Tiny reference table. |
| `GET /plays/stats` | one player-play-stat; key `(playId, athleteId, statType)` | athleteId/name, statType, stat, team/opponent/scores, down/distance context | **Hard cap 2,000 records per call** — must page by gameId/week. The granular credit source for tackles/tackles-for-loss etc. |
| `GET /plays/stats/types` | one statType | id, name | Reference for the above. |
| `GET /live/plays` | one live game | full live play list + team EPA/success metrics | **Gated**; live only. |

## Passing / rushing / punting (enriched, play & aggregate)

These are newer, richer endpoints; all are free-tier, filterable by
year/week/team/conference/rusher-or-passer-or-player id, with `classification`
(default `fbs`).

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /passing/plays` | one pass attempt; key `playId` | passer+target ids/names, outcome, airYards, depth×direction location, totalYards, YAC, spike/throwaway/grounding flags, completionProbability, cpoe, ppa, success, eligibility flags | Per-season requires week or team. Enables receiver-level air-yards/YAC, not available elsewhere. |
| `GET /passing/players/{season,games}` | one passer-season / passer-game; key `(playerId, season[, gameId])` | attempts/completions/INTs, ADOT, totalYards, YAC, successRate, ppa, explosiveness, CPOE + denominators, per-location buckets (7) | Rich QB season/game features in one call per year. |
| `GET /passing/teams/{season,games}` | one team-season / team-game | same production metrics for offense AND defense (allowed, non-inverted) | Team pass-defense quality. |
| `GET /rushing/plays` | one rush attempt; key `playId` | rusherId/name, direction, yards, TD/sack/kneel/team-rush flags, attributionStatus, ppa, success | Attribution statuses let us exclude team/ambiguous rushes. |
| `GET /rushing/players/{season,games}` | one rusher-season / game; key `(playerId, season[, gameId])` | carries/yards/YPC, successRate, ppa, explosiveness, line/second-level/open-field yards, stuffRate, powerSuccess, per-direction splits | RB/QB rushing shape features per season. |
| `GET /rushing/teams/{season,games}` | one team-season / game | same for offense + defense allowed | — |
| `GET /punting/plays` | one punt; key `playId` | punter/returner ids, puntYards, returnYards, netPuntYards, kick/end yardline, touchback/fair-catch/downed/blocked/muffed flags | Per-punt granularity for special teams. |
| `GET /punting/players/{season,games}` | one player-season/game; key `(playerId, season[, gameId])` | punting: yards/punt, 50+, net, inside20, blocked; returning: returns, yards, TDs, muffs | Kickers/punters/returners. |
| `GET /punting/teams/{season,games}` | one team-season/game | punting + returning sides | — |

Caveat repeated in the API docs: player-level rushing/punting totals include
only guarded attribution and do NOT sum to team totals.

## Stats (box score & advanced)

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /stats/player/season` | **long**: player-season-category-statType; key `(playerId, season, category, statType)` | playerId, player, position, team, conference, stat | The `player_stats` source. One call per season. Categories via `/stats/categories`. |
| `GET /stats/player/success` | one player-season; key `(id, season)` | passing/rushing plays, successes, successRate; threshold, excludeGarbageTime filters | Success rate without play-level work. |
| `GET /stats/player/success/game` | one player-game; key `(id, gameId)` | same splits + opponent | Per-game success rates. |
| `GET /stats/season` | **long**: team-season-statName; key `(season, team, statName)` | statValue (string or number) | Team box-score stats by season, one call per year. |
| `GET /stats/season/advanced` | one team-season; key `(season, team)` | full SP-style offense/defense advanced: PPA, successRate, explosiveness by play-type/down, havoc, field position, line/second-level/open-field yards, stuffRate, powerSuccess, drives, plays | One call per year. ExcludeGarbageTime available. |
| `GET /stats/game/advanced` | one team-game; key `(gameId, team)` | same metrics per game + opponent | Weekly granularity. |
| `GET /stats/game/havoc` | one team-game; key `(gameId, team)` | havoc rates + event counts (total/front seven/DB), plays | Havoc detail at game level. |
| `GET /stats/categories` | string list | available team stat categories | Reference for `player_stats` pivot. |

## Metrics (PPA/EPA, win probability)

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /ppa/teams` | one team-season; key `(season, team)` | offense/defense PPA overall + by down + cumulative rush/pass | Season-level, one call per year. |
| `GET /ppa/games` | one team-game; key `(gameId, team)` | same per game | Weekly. |
| `GET /ppa/players/season` | one player-season; key `(id, season)` | averagePPA + totalPPA by down/rush/pass/all; threshold | Player PPA without play-level pulls. |
| `GET /ppa/players/games` | one player-game; key `(id, gameId)` | averagePPA (all/rush/pass) | Weekly player PPA. |
| `GET /ppa/predicted` | one (down, distance) | predictedPoints | Static lookup curve. |
| `GET /metrics/wp` | one play; key `playId` | homeWinProbability, spread, game situation | Per-game call. |
| `GET /metrics/wp/pregame` | one game; key `gameId` | spread, homeWinProbability | One call per season+week. |
| `GET /metrics/fg/ep` | one distance | expectedPoints | Static FG curve. |

## Adjusted metrics (Patreon-gated)

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /wepa/team/season` | one team-season | opponent-adjusted EPA (rush/pass/total) for and allowed, success rates, rushing yard-split components, explosiveness | Premium version of `/stats/season/advanced`. |
| `GET /wepa/players/passing` and `/rushing` | one player-season; key `(athleteId, year)` | wepa, plays, position, team, conference | Opponent-adjusted player value; **athlete id is in the shared namespace**. |
| `GET /wepa/players/kicking` | one kicker-season | PAAR, attempts | Kicker value. |

## Teams, conferences, venues

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /teams` | one team; key `id` (school name is our join key) | school, mascot, abbreviation, alternateNames, conference, division, classification, color(s), logos, twitter, home `location` (venue with lat/long, capacity, grass, dome, elevation, construction year) | The `teams` source. Year param gives historical affiliation. |
| `GET /teams/fbs` | one FBS team | same, filtered | Convenience. |
| `GET /roster` | one player-season; key `(id, season, team)` | first/last name, height, weight, jersey, position, home city/state/country + lat/long + county FIPS, `recruitIds[]` | The `roster` source. Year defaults to 2025 — always pass `year`. Weight is static per player (decision 0009). |
| `GET /teams/matchup` | series + game list; key `(team1, team2)` | all-time series record and every meeting | Per-pair call; historical rivalry context. |
| `GET /teams/ats` | one team-season | ATS record, avg cover margin | Betting-derived; year required. |
| `GET /conferences` | one conference; key `id` | name, shortName, abbreviation, classification, memberCount | Reference. |
| `GET /conferences/affiliations` | one team-affiliation span; key `(teamId, conferenceId, startYear)` | conference + classification + division, start/end year | **Better than `/teams?year=` for historical conference membership** — one call covers a span. Directly strengthens the season-aware tier lookup. |
| `GET /conferences/changes` | one change event; key `(teamId, effectiveYear)` | from/to conference + classification, effective year | Change events only; needs per-year fan-out. |
| `GET /venues` | one venue; key `id` | full location + capacity/grass/dome | One total call. |
| `GET /talent` | one team-season | 247 Team Talent Composite | One call per year; classic team-strength feature. |

## Coaches

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /coaches` | one coach with nested seasons; key `id` | per season: team, W/L/T, win%, preseason/postseason rank, SRS, SP+ (overall/off/def) | The `coaches` source. One call covers all coaches. |
| `GET /coaches/profile` | one coach | career totals, birth date, alma mater, wikidataId | Per-coach. |
| `GET /coaches/seasons` | one coach-season; key `(coachId, team, year)` | record + splits (conf/home/away/neutral/postseason), scoring, recruiting rank/talent, SP/SRS/FPI context, CFP outcome, **draft picks by players from that team the following season** | Notably `draftFollowingSeason` ties a coach-season to NFL output — relevant to the project's outcome but must stay OFF the input path (leakage). |
| `GET /coaches/tenures` | one tenure; key `(coachId, team, startYear)` | start/end year, interim flag, active, attributed record | Cleanest coach-change signal; supersedes hand-deriving changes from `/coaches`. |

## Players

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /player/search` | one player; key `id` | name, team + stints (start/end years), position, height/weight, jersey, hometown, team colors, active years | ≤ 100 results per call; for resolving names to ids. |
| `GET /player/usage` | one player-season; key `(id, season)` | usage shares: overall/pass/rush, by down | One call per year (all players). |
| `GET /player/season/overview` | one player-season | games, box-score categories (as strings), usage, PPA average/total | Per-player-per-year call (expensive); mostly a prettified composite. |
| `GET /player/returning` | one team-season | returning PPA/usage by unit (percent + total) | One call per year; team-level continuity feature. |
| `GET /player/portal` | one transfer; key `(firstName, lastName, origin, destination, season)` | position, transferDate, 247 rating/stars, eligibility status | **No athleteId** — name-keyed only. Season required per call. |

## Recruiting

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /recruiting/players` | one recruit; key `id` | `athleteId` (**untrusted namespace** — decision 0013), recruitType (HS/JUCO/PrepSchool), year, ranking, name, committedTo, position, height/weight, stars, rating, city/state/country, hometown FIPS + lat/long | The `recruiting` source. One call per year. |
| `GET /recruiting/teams` | one team-class; key `(year, rank)` | rank, points | One call per year. |
| `GET /recruiting/groups` | one team-positionGroup span | averageRating, totalRating, commits, averageStars | Aggregated across a year range in one call. |

## Ratings

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /ratings/sp` | one team-season | SP+ overall/off/def + components (pace, runRate, havoc, SOS, secondOrderWins), ranks | One call per year. |
| `GET /ratings/sp/conferences` | one conference-season | same at conference level | — |
| `GET /ratings/srs` | one team-season | SRS rating + rank | — |
| `GET /ratings/srs/expanded` | one team-season | SRS + classification (FBS **and FCS**) | Only rating endpoint covering FCS. |
| `GET /ratings/elo` | one team-week | elo; preseason flag | Fan-made Elo, week-by-week. |
| `GET /ratings/fpi` | one team-season | FPI + efficiency + resume ranks (SOS, strength of record, game control, avg win prob) | — |
| `GET /ratings/core` | one team-season(-week) | CORE overall/off/def + plays, model version | Newer CFBD model. |

## Rankings & playoffs

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /rankings` | one poll-week; key `(season, week, poll)` | ranks per team with points, first-place votes; AP/Coaches/CFP | Poll = `cfp` only per the enum; other polls return by name string. One call per season covers all weeks. |
| `GET /playoffs/cfp` | one season bracket | participants (seed, bid type, committee rank, outcome), rounds/matchups with linked games, champion | One call per year. |
| `GET /playoffs/cfp/participants` | one participant | seed, bidType, outcome, eliminated round | Subset of above. |
| `GET /playoffs/cfp/games` | one matchup | round, bowlName, slots, linked game id | Subset of above. |

## Betting

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /lines` | one game with `lines[]` per provider; key `(gameId, provider)` | spread (open + current), over/under (open + current), moneylines | One call per season (+week). Note: pregame lines are a leakage hazard — only usable as a *feature at kickoff*, never in career-history features for earlier seasons. |

## Draft

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /draft/picks` | one pick; key `(year, round, pick)` | collegeAthleteId (nullable, the shared namespace), nflAthleteId (separate namespace — do not cross-link), college team/conference, NFL team, position, height/weight, preDraftRanking/PositionRanking/Grade, hometown (city/state/county FIPS/lat/long) | The `picks` source. One call covers all years. |
| `GET /draft/teams`, `/draft/positions` | reference lists | — | Tiny. |

## Account

| Endpoint | Grain / key | Key attributes | Feasibility notes |
|---|---|---|---|
| `GET /info` | user | patron level, monthly limit, remaining/used calls, reset date, feature access flags | Free call for checking quota before a refresh burst. |
| `GET /info/usage` | usage window | requests by endpoint over trailing days (≤ 31) | Free call; audit of where quota went. |

## Cross-cutting feasibility rules

1. **Fan-out cost dominates.** Endpoints keyed by `(year)` alone are cheap
   (one call per season). Endpoints requiring `week` and/or `team`
   (`/plays`, `/plays/stats`, `/drives`, per-game passing/rushing/punting,
   previews, weather, media) cost weeks × seasons or teams × seasons calls.
   Do the math against the 5000/month quota before planning an ingest.
2. **Names are the join currency.** `team`/`school`/`conference` strings join
   across endpoints; `teamId` exists in some responses but name joins are the
   project convention. `athleteId`-style ids are the player namespace except
   where flagged (`/recruiting/players`, `nflAthleteId`).
3. **Postseason inclusion is parametric.** Most stats endpoints take
   `seasonType` (`regular`/`postseason`/`both`); the `/games` family includes
   postseason by default. Check per-endpoint defaults when comparing totals.
4. **Gated endpoints** (`adjustedMetrics`, `weather`, `scoreboard`,
   `livePlayByPlay`, `graphQl`) require Patreon tiers — check `/info`'s
   `features` flags before planning around them.
5. **Row caps and paging**: only `/plays/stats` documents a hard 2,000-record
   cap; page by `gameId` or `week`. Everything else paginates implicitly by
   filter dimensions.

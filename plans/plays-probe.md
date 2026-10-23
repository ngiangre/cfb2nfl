# Plays data: what we have and what is possible

Findings from the 2026-10-22 probe session (live API calls + namespace
validation). Companion to [plans/plays.md](plays.md) and
[decisions/0031-plays-ingest-and-quota-phasing.md](../decisions/0031-plays-ingest-and-quota-phasing.md).

## Endpoints: what exists and what it returns

| Endpoint | Status on our key | Grain | Notes |
|---|---|---|---|
| `/plays/types` | OK (1 call) | 49 play types | `id`, `text`, `abbreviation`; includes junk entries (`placeholder` id 70, `Uncategorized` 999) |
| `/plays/stats/types` | OK (1 call) | 31 play-stat types | `id`, `name`; the athlete-attribution vocabulary |
| `/plays` | OK | one row per play | no row cap at the week grain (22,320 rows, week 1 2024); accepts `year`+`week`+`seasonType`+`team`; **rejects `gameId` (400)** |
| `/plays/stats` | OK | one row per athlete-play-stat | **hard cap: 2,000 rows per query on the week grain** (10 of 133 games); accepts `gameId` (~230 rows/game, complete) |
| `/live/plays` | **401 Unauthorized** | — | premium tier; do not re-probe |
| `/charts`, `/charting`, `/plays/chart`, `/player/chart`, `/pff`, `/graphql` | **404** | — | endpoints do not exist |

## Play fields (`/plays`, one row per play)

`gameId`, `driveId`, `id` (play key, string), `driveNumber`, `playNumber`,
`offense`, `offenseConference`, `offenseScore`, `defense`, `defenseConference`,
`defenseScore`, `home`, `away`, `period`, `clock` (minutes/seconds),
`offenseTimeouts`, `defenseTimeouts`, `yardline`, `yardsToGoal`, `down`,
`distance`, `yardsGained`, `scoring`, `playType`, `playText`, `ppa`,
`wallclock`.

- `ppa` is populated for scrimmage plays only (NULL for kicks, returns).
- `playText` includes formation hints (`No Huddle-Shotgun`), jersey numbers,
  and tackle/coverage notes in prose — regex-minable, not guaranteed.

## Athlete attribution (`/plays/stats`)

One row per athlete-play-stat: `gameId`, `season`, `week`, `team`,
`conference`, `opponent`, `teamScore`, `opponentScore`, `driveId`, `playId`,
`period`, `clock`, `yardsToGoal`, `down`, `distance`, `athleteId` (string),
`athleteName`, `statType`, `stat`.

**Namespace validation (2026-10-22, PASS):** all 323 distinct `athleteId`
values from the 2024 week-1 probe are in `roster$playerId`, and all 14,867
id-name pairs match `player_stats$player` (100%). Joins the shared athlete
namespace with no name guard (unlike recruiting, decision 0013). Keep a
coverage contract so a future CFBD change fails loudly.

**What one row means:** the passer/receiver/target model means an
incompletion produces Incompletion + Target rows (2), a breakup adds a third;
shared sacks are one row per defender plus a mirrored `Sack Taken` for the QB.
Row counts per play vary 0-5+; grain is `(playId, athleteId, statTypeId)`.

**Defender credit exists:** `Pass Breakup`, `Interception`, `Sack`, `Tackle`,
`Fumble Forced`, `Fumble Recovered`, `QB Hurry`. In the Georgia-Auburn 2026
week-7 probe: 6 breakups, 2 interceptions, 8 sacks (2 plays had 2 sack rows),
7 `Sack Taken`. **No** general "defender in coverage" per target — that is
charting-grade data and CFBD does not carry it (see below).

## The 31 play-stat types, grouped

- **Passing:** Incompletion, Target, Pass Breakup, Completion, Reception,
  Interception Thrown, Interception, Sack Taken, Sack
- **Rushing / ball security:** Rush, Fumble, Fumble Forced, Fumble Recovered,
  Touchdown
- **Defense / pressure:** Tackle, QB Hurry (coverage of Hurry looked thin in
  the probe game — spot-check before building pressure features)
- **Kickoff:** Kickoff, Onside Kick, Kickoff Return
- **Punt:** Punt, Punt Block, Punt Attempt, Punt Return, Punt Return Attempt,
  Punt Fielded, Punt Kicker (punter vs returner fully distinguished)
- **Field goal:** FG Attempt, FG Made, FG Missed, FG Attempt Blocked,
  Field Goal Block

## The 49 play types (outcome vocabulary, not tactics)

Rush, Pass Reception, Pass Incompletion, Pass, Pass Completion, Pass
Interception, Pass Interception Return, Sack, Interception, Interception
Return Touchdown, Passing/Rushing Touchdown, Fumble, Fumble Recovery (Own /
Opponent), Fumble Return Touchdown, Kickoff, Kickoff Return (Offense /
Defense), Kickoff Return Touchdown, Onside Kick, Punt, Punt Return, Blocked
Punt (+ TD), FG Good / Missed / Blocked (+ Missed FG Return (+ TD)), Extra
Point Good / Missed / Blocked PAT, Two Point Pass / Rush, 2pt Conversion,
Defensive 2pt, Offensive 1pt Safety, Safety, Penalty, Timeout, End Period /
Half / Game / Regulation, Start of Period, Uncategorized, placeholder.

The Georgia-Auburn game used 19 of the 49.

## What is NOT available (confirmed)

- **Coverage type (man/zone), personnel, formation, alignment** — no CFBD
  endpoint carries it. `/graphql` and charting paths are 404. CFBD's
  "chart export" is a website feature (Tier 1 patron), not an API; only a
  small subset of games is charted.
- **PFF grades / charted detail** — PFF developer API, paid, separate
  licensing; out of scope for this repo.
- **Live play polling** (`/live/plays`) — premium tier, 401 on our key.
- **Play-level defense-vs-offense alignment** beyond named credit events.

## What is possible with what we have

**Phase 1 (`/plays` + dimensions, ~360 calls):**
- Play-level situational features: down/distance/score state/field position.
- Team- and game-level PPA (sum, mean, explosive-rate by `playType`).
- Play-type distributions and tendencies per team-season.
- `playText` regex mining: shotgun / no-huddle flags (best-effort, no
  contract).

**Phase 2 (`/plays/stats` per gameId, ~2,100 calls/season, opt-in
`CFBSTATS_PLAYS_STATS=true`, newest seasons first):**
- Per athlete-season: targets, receptions, carries, rush volume, sacks,
  pressures/pressures-taken, tackles, forced fumbles, PBUs, INTs — all from
  the shared athlete namespace, aggregatable by `athleteId` regardless of
  which side of the ball the play ran.
- PPA credited per athlete by joining `play_stats` to `plays.ppa` (usage-
  weighted value, beyond counting stats).
- QB-level: sack-taken rate, INT thrown vs completion; receiver-level:
  target share, catch rate, broken-up targets; defensive backs: PBUs + INTs.

**Leakage note:** all of the above are in-career inputs; the out-of-time
validation rule (never use seasons on/after the predicted draft class)
applies unchanged.

## Probed objects still in the R session

`pl` / `pstats` / `sample_plays` / `d2` (Georgia-Auburn 2026 wk7,
gameId 401856719), `pl_all` / `ps_all` (2024 wk1 sizing pulls), `types`,
`stats_types` (dimensions), `g` / `game` (games lookup).

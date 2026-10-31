# Plan: Conferences, teams, and the draftees they produce

A three-post series plus one shared pipeline table. Numbers below come from
the **2026-10-31 profiling session** and are placeholders: recompute every
figure in the posts' own chunks and pin quoted facts with `stopifnot()`.

The user has no prior expectations except one: *good teams (those that win
more games) produce the most draftees.* Posts 1 and 2 are descriptive (no
expectation statements); Post 3 tests that single expectation with a verdict.

## Profiling facts that shape the design (2026-10-31)

- **Conferences per season:** Power 5–6 (4 from 2024, Pac-12 collapse), G5
  6–7, FCS-and-below 11–28 (jumps 2021–22 when Division II/III appear).
- **Teams with stat lines:** FBS complete every season (~64–67 Power,
  ~55–71 G5). FCS-and-below sparse: ~50–90 through 2019, **14 in 2020**
  (COVID spring season), 130–160 from 2021.
- **Stat depth jump in 2016:** median players with a stat line per FBS
  team-season goes ~30 → ~60. Per-team counts are not comparable across 2016
  without normalising.
- **OL blind spot:** ~42k OL roster rows but ~2.7k OL stat rows, so the
  stat-line population (outcomes/model) nearly excludes offensive linemen,
  who account for ~700 picks (OT/OG/C). The roster includes them.
- **Picks 2011+:** ~3,000 Power, ~700 G5, ~200 FCS-and-below, from 266
  distinct schools. ~150 do not match a tier on `picks.collegeConference`
  (legacy names: Pac-10, Big East, WAC; 38 NA). Attribute via roster team
  instead (below).
- **UDFAs:** ~3,600 in `outcomes` (`outcome_nfl_entry_type_d == "udfa"`),
  linked only for the stat-line population, so OL UDFAs are missing.
- **Team quality:** `ps_tier` carries wins/losses/SRS/SP+ for FBS only
  (wins NA for all FCS). `games.parquet` covers FCS games fully except 2020,
  so win % for every division comes from `games`.

## Shared definitions (decided)

- **Attribution:** a draftee/UDFA is credited to the team (and that
  season's conference/tier) of their **final roster season before the draft
  year**. Reused ids (`reused_ids()`, decision 0022) excluded first. This
  bypasses the legacy-name problem in `picks.collegeConference`.
- **Position groups** from the roster position, one map used for both
  numerator and denominator: QB, RB (incl. FB), WR, TE, OL (OL/OT/G/C),
  DL (DL/DE/DT/NT/EDGE), LB (LB/OLB/ILB), DB (DB/CB/S), ST (PK/P/LS);
  `?`/ATH/NA → "Position not recorded" (counted, reported, not ranked).
- **Rate (denominator):** draftees ÷ distinct **draft-eligible rostered
  players** credited to the team under the same last-roster-season rule
  (one player counted once, at their final pre-draft team). UDFA rates
  exclude OL, with the caveat stated in the post.
- **Window:** rates and leaderboards use draft classes **2014+** (full
  observable careers given the roster starts 2010; same reasoning as
  `plans/coaches-draftees.md`). Coverage/landscape exhibits use 2010–2026.
- **Scope of rates:** FBS (Power + G5) teams individually; FCS-and-below
  shown as one aggregate because its rosters are incomplete.
- **"Above average":** observed vs expected, where expected = league rate for
  that position group × the team's eligible players at that position.
  Small schools are shrunk toward their conference rate (empirical Bayes,
  beta-binomial) so one pick does not make a school look elite. Introduce
  the idea in plain language before naming the method.
- **Good team:** win % from `games` (regular + postseason, completed games),
  with SP+ as an FBS robustness check (a 10-2 G5 record is not a 10-2 SEC
  record).

## Pipeline work: `team_season` target

> **Superseded as built (2026-10-31):** see `plans/conferences-teams-impl.md`,
> decision 0033, and `inst/dict/team_*.yml`. `team_draft` is keyed by the
> player's **final college season** (not draft year) and carries `n_round1`
> rather than round groups; there are no `n_roster_<group>` columns (group
> counts live in `team_draft`); ratings come from `coaches`, not `ps_tier`;
> `team_season` adds `conference_filled`. Plan Posts 2–3 against the built
> grain.

Derived table (decision 0021 pattern), one row per `(team, season)`:

| column | source |
|---|---|
| `team`, `season`, `conference`, `tier`, `tier_label` | roster team × season, tiers lookup |
| `games_played`, `wins`, `losses`, `win_pct` | `games` (all divisions) |
| `sp_overall`, `srs` | `ps_tier` (FBS only; NA otherwise) |
| `has_stat_lines`, `n_stat_players` | `player_stats` |
| `n_roster`, `n_roster_<group>` | `roster` |

Plus a long companion `team_draft` (team × draft year × position group):
eligible players, draftees, draftees by round group, UDFAs, under the
attribution rule. Keep both pure functions in `R/features.R` (or a new
`R/teams.R` if it grows), with:

- **testthat:** position-group map (every observed roster position mapped);
  attribution picks the last pre-draft roster season and excludes reused ids;
  win % from a toy `games` frame (home/away, ties, incomplete games skipped).
- **pointblank contract:** `(team, season)` unique; every FBS team-season in
  `ps_tier` present; `win_pct` in [0, 1]; draftee total reconciles with
  2014+ picks carrying a `playerId`, allowing a bounded unmatched count that
  is reported in the audit log (no silent join loss).
- Add to `duckdb_file`, `inst/dict/team_season.yml` + `team_draft.yml`,
  `inst/data-model.md`. No new ingest, so no release-asset ordering issue.
- Decision record (next number) for the attribution + denominator rules.

## Post 1: The college football landscape and what the data can see

Questions: what conferences and tiers are, how many teams each has, how
realignment changed membership; which teams have stat lines over time; how
concentrated draft picks are.

Sketch of assertions (refine on real numbers):
1. Conferences fall into three tiers, and membership shifted with
   realignment (table of conferences × seasons; membership flow figure for
   Texas/Oklahoma → SEC and the Pac-12 collapse; ggiraph tile of every
   team-season's conference).
2. Stat lines cover every FBS team but only part of FCS-and-below, with the
   2016 depth jump, the 2020 gap, and the OL blind spot (coverage table;
   teams-with-stats by season and tier, gaps highlighted; per-position
   roster vs stat-line counts).
3. A small set of schools supplies a large share of picks (concentration
   table: share from top 10/25 schools; cumulative-share curve; ggiraph
   per-school bar).
4. Small schools still send players to the NFL (FCS-and-below pick counts,
   named examples verified in data).

## Post 2: Which conferences and schools produce draftees, by position

1. Draftee and UDFA rates by conference and tier (per eligible player).
2. Position-group rates by conference (heatmap; highlight the leaders).
3. Within each conference, schools vs expected (shrunk rates; "DBU / WRU /
   Linebacker U" leaderboard by position group).
4. UDFAs come from a broader set of schools than draft picks? (overlap of
   top producers; rank comparison).

## Post 3: Do good teams produce more draftees?

*Expectation: teams that win more produce more draftees.* (verdict TBD)

1. Win % vs draftee rate across FBS team-eras (scatter, conference color;
   SP+ panel as the check).
2. Over- and under-producers relative to their win % (residuals, named).
3. Persistence: a school's rate in one window predicts the next?
4. Direction: does winning precede draftees or follow them (lagged
   comparison, described plainly, not causal).

## Order of work

1. `team_season` + `team_draft` with tests, contract, dicts, DuckDB, decision.
2. Post 1 (descriptive; validates the table and coverage story).
3. Post 2, then Post 3. Each post is its own branch/PR with NEWS entry.

## Style reminders

Follow AGENTS.md blog style: numbered assertion headings, one or two
sentences per section, table → explanatory figure → exploratory ggiraph
figure, reader-facing labels (no column names), define every term
(tier, eligible player, UDFA, win %, SP+), team colors from `teams`,
recurring cast where natural (e.g. LSU for Burrow, Miami/Washington State
for Cam Ward, Florida State for Jordan Travis).

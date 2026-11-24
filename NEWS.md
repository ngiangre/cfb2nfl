# cfb2nfl 0.0.0.9000 (development version)

- Model (feature F17): **the model table now has one row per roster
  player-season**, the same keys as `outcomes` (decision 0050), instead of
  stat-line seasons with a row per head coach. `build_model_table()` takes
  stat-line features from `ps_change` (missing where a season has no stat
  line, marked by `has_stat_line`) and team, position, tier and weight from
  the roster for every season. `contract_model_table()` checks the grain
  ([#104](https://github.com/ngiangre/cfb2nfl/issues/104)).
- Fix (feature F22): **draft picks link through nicknames and spellings**.
  When a pick sits on another CFBD id, the name + school fallback now runs a
  second, stricter pass after exact names: the same surname, school and
  entry window, first names that are a prefix, a small spelling edit or a
  common nickname of each other (never just a shared initial), and one
  candidate each way. 47 more players are labeled drafted, including
  Mitchell / Mitch Trubisky (2017, second overall), Mo / Maurice Hurst and
  Dawaune / Dawuane Smoot; Donovan and Devon Smith stay apart
  ([#103](https://github.com/ngiangre/cfb2nfl/issues/103)).
- Post (feature F24): **the career-endings post now counts every player on
  a college roster**, following the new `outcomes` population. Careers end
  in three ways (no career ends by leaving the data on rosters), signing
  undrafted passes being drafted from the third eligible season, and a new
  section shows that counting only players with a stat line nearly doubles
  the offensive line's drafted share. Joe Burrow, Ke'Shawn Vaughn and Shane
  Buechele leave the named players while their roster records are checked
  ([#114](https://github.com/ngiangre/cfb2nfl/issues/114)); Jayden Daniels
  and Grant Calcaterra join
  ([#109](https://github.com/ngiangre/cfb2nfl/issues/109)).
- Data (feature F22): **the roster now carries player names**
  (`first_name`, `last_name` from CFBD `/roster`), so a roster-only player
  with no stat line is named in `outcomes` and can be matched to a recruiting
  record and to an NFL roster. Undrafted signings rise from 4,337 to 5,307
  and drafted players from 3,803 to 3,835 (picks on another CFBD id now
  link by name and school for roster-only players too, e.g. Jonah Williams,
  Dante Fowler Jr.); draft-eligible rows fall from 181,010 to 174,131 as
  more players get a recruited high-school year instead of an imputed one.
  `data-raw/refresh-outcomes.R --roster` re-pulls the roster (17 CFBD
  calls) and publishes it with `outcomes`
  ([#111](https://github.com/ngiangre/cfb2nfl/issues/111)).
- Data (feature F22): **`outcomes` now covers every roster player-season**,
  not only seasons with a stat line
  ([decision 0050](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0050-roster-outcome-population.md)).
  Offensive linemen, every defender before 2016 (CFBD has no defensive stats
  until then) and seasons without a stat line join the population: 336,241
  rows (from 160,771), 134,985 players, and 3,803 drafted players (from
  3,206). New columns `has_stat_line` (the old population is that filter),
  the row's `team` and season `tier` / `tier_label`, `first_roster_season`
  and `is_first_roster_season`. A drafted row's `draft_year` is now always
  the draft it records, with the eligibility clock computed against it; an
  entry after a skipped season lands on the latest row before it.
  Undrafted signings are unchanged (4,337): roster-only players have no
  name yet, so they cannot be matched to an NFL roster.
  `contract_outcomes()` checks the roster grain, a tier on every row, and
  that every in-window pick on a population id has its drafted row. New
  `outcomes_backbone()`; `data-raw/refresh-outcomes.R` republishes the table
  with no CFBD calls
  ([#102](https://github.com/ngiangre/cfb2nfl/issues/102)).
- Post (feature F24): **how college careers end, by position, as competing
  outcomes**. It follows every draft-eligible player season by season to one
  of four endings (drafted, signed undrafted, eligibility ended undrafted,
  left the data), and reports cumulative shares by position, why a
  drafted-only survival curve overstates the drafted share, the per-season
  chance of each NFL route, and the gap between players with and without a
  matched recruiting record. New helpers `career_endings()`,
  `ending_incidence()`, `naive_drafted()`, `ending_hazards()`,
  `never_eligible_entrants()` and `explorer_player_url()`; `survival` is now
  a suggested package
  ([#97](https://github.com/ngiangre/cfb2nfl/issues/97)).
- Fix (feature F22): **an imputed high-school year now starts at the first
  roster season**. For players without a matched recruiting record,
  `outcomes$hs_grad_year` was the first *stat* season minus one, so a
  lineman, redshirt or pre-2016 defender on the roster for years before a
  first stat line got a clock that started too late. It now takes the
  earlier of the first roster and first stat season. 15,603 players move
  earlier (most by one or two years), draft-eligible player seasons rise
  from 86,800 to 102,403, and drafted seasons labeled not yet eligible fall
  from 382 to 229. No other column changes.
- Process: new feature card **F24**, a planned post on how college careers
  end, by position, as competing outcomes over eligible seasons (drafted,
  signed undrafted, eligibility exhausted, left the data), tracked in
  [#97](https://github.com/ngiangre/cfb2nfl/issues/97).
- Fix (feature F22): **NFL outcome labels in `outcomes` are corrected**, so
  drafted rates rise across every post that reads them. 254 more player
  seasons are labeled drafted (2,718 to 2,972) and the undrafted signings are
  cleaner:
  - a draft or undrafted signing that follows final college seasons with no
    stat line (linemen, injured seniors: Isaiah Wynn, Matt Bushman) now
    lands on the player's last stat season instead of being lost;
  - a pick whose CFBD id differs from the player's stat id now links by name
    and school (Carson Wentz, Le'Veon Bell, Tyrann Mathieu, Zay Jones);
  - the undrafted name match no longer links a drafted namesake, or an NFL
    player who debuted while the college player was still playing.
  `contract_outcomes()` now checks one entry row per player, that every
  entrant has one, and that no undrafted entrant is a drafted player
  ([#99](https://github.com/ngiangre/cfb2nfl/issues/99)).
- Fix: `last_complete_nfl_draft()` was one year behind. It now returns the
  current year from May 1, so the April 2026 draft class counts as observed
  in `outcomes` (and in `_meta`) instead of censored. That class's rookie
  roster and games labels stay partial until its first NFL season ends.
- Data (feature F23): **NFL play, snap and roster-status data from 2022 on**,
  for following drafted and undrafted players into the NFL. Four new tables
  on `data-latest` and in the DuckDB: `nfl_pbp` (every nflverse
  play-by-play column, EPA and the players credited on each play),
  `nfl_participation` (who was on the field each play, linemen included),
  `nfl_snap_counts` (snaps per player-game) and `nfl_rosters_weekly` (each
  player's status each week: active, practice squad, inactive, injured
  reserve, cut, traded). All join the model population through
  `outcomes.gsis_id`, cost no CFBD calls, and refresh the current NFL season
  every week; `data-raw/refresh-nfl.R` re-pulls them without touching CFBD.
  New contracts guard the tables, the bridge from college players (at least
  99% coverage) and the model path (NFL data never feeds the model), and the
  DuckDB build now fails before reaching the 2 GiB release-asset limit
  ([decision 0049](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0049-nfl-play-level-data.md)).
- Process: work now traces **issue → feature → goal → persona**. `product/`
  holds who the site serves (`personas.md`: the invested fan first, then
  coders and researchers), what it is for (`goals.md`: answer the questions,
  fan self-serve, NFL careers, then the forecast, under trust and API-budget
  constraints) and the features grouped by goal (`features.md`), backfilled
  from the shipped work. GitHub issues carry `goal:*`/`constraint:*` labels
  and a `Feature:` line, and `sync_feature_tasks()` writes each feature's
  task checklist from them. New `feature-reviewer` and `task-reviewer`
  agents check each link, and the `sdlc-alignment` and `site-personas`
  skills hold the workflow
  ([decision 0048](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0048-goal-feature-task-traceability.md)).
- Post revision: **Georgia vs Missouri game flow by EPA**. Every EPA is now
  CFBD's published PPA, with the spline expected-points model shown only in
  3.1 to explain what PPA measures. The drive chart is a football field with
  one arrow per drive, and drive points now reconcile to the 48-21 final.
  Player attribution replaces the old disruption ledger: players come from
  the play-stats log first, and the play-by-play text adds the tacklers the
  log leaves out (CFBD's log carries no tackle stat type for this game).
  Each play's EPA is split evenly among the players named on each side.
  Position groups are measured against each group's typical play, with the
  offensive line left out because blocking is never recorded. Players are
  ranked by average EPA per involvement, among those named at least four
  times. New helpers `play_text_mentions()`, `match_play_mentions()` and
  `build_play_involvement()` (`R/play_involvement.R`, tested) do the
  attribution on the fly
  ([decision 0041](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0041-lean-data-model.md)).
- Post style: a Results section's table is now optional. It appears only
  when it shows a different summary than the section's figures, never
  restating what a figure already shows
  ([decision 0025](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0025-blog-post-writing-style.md),
  revised 2026-11-20).

- Explorer Combine tab: combine invitees without a draft slot who still show
  up in nflverse's player table are now labelled **"UDFA, made NFL roster"**
  with their NFL span (e.g. "UDFA, NFL roster (2021-2025)") instead of "Not
  drafted". The label comes from a new nflverse player crosswalk
  (`ingest_nfl_players()`, `pfr_id` to `gsis_id` plus rookie and last
  season, no API key), the only bridge that sees undrafted free agents,
  since the draft-slot link cannot. About a quarter of the former "Not
  drafted" combine rows are really UDFAs who made an NFL roster. The
  "Draft pending" label is also clarified: it marks a combine class whose
  draft is not yet in the published data, not an in-flight draft (#89).

- Explorer: player listings now show the jersey number with the position,
  as in "Arch Manning (#7 QB)". The college jersey comes from
  `data/roster.parquet` (94% coverage; the roster and NFL-rosters contracts
  now guard it to the plausible 0-99 range, with out-of-range values
  coerced to NA) and the NFL jersey from nflverse rosters in
  `data/nfl_rosters.parquet`, taken as the most common non-NA week value in
  a season because a traded player's number can change mid-season (ties
  take the smaller number). Jersey numbers are display only and stay off
  the model input path (#87).

- New post: **combine measurables and the invite-to-draft funnel** (#64).
  What the NFL Scouting Combine records at each position, how size and
  speed separate positions and drift from 2010 to 2026, how drill records
  thinned after the cancelled 2021 combine, and how invitees are drafted at
  many times the rate of uninvited draft-eligible players. New helpers
  `combine_funnel_status()` and `build_combine_funnel()` place invitees
  against the draft-eligible population of `outcomes`, joined on athlete id
  (on the fly per
  [decision 0041](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0041-lean-data-model.md)).

- Explorer: every player name now carries the player's position, as in
  "Arch Manning (QB)": play-card chips, Players search results, swarm
  tooltips and the career heading, Combine tooltips and cards, and the draft
  chips and NFL-career tooltips. Combine tooltips also name the position a
  player was drafted at ("Drafted as OG, R5 #150"), which can differ from
  the position they worked out at (#84).

- Explorer Combine tab: **region filters**. Each axis has Any / Low / Mid /
  High buttons (thirds of the invitees shown, with their ranges), so a
  region such as tall and fast receivers can be picked out by tapping instead
  of rotating the 3D chart. Its invitees stay in full color while everyone
  else fades back, they are listed below the chart, and the legend counts
  each color (#84).

- Teams now carry their home stadium's name, city, state, latitude and
  longitude, read from the CFBD `/teams` response the refresh already pulls
  (no extra API calls). Every FBS program has coordinates, and the teams
  contract checks they sit inside the United States (#48,
  [decision 0047](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0047-team-geography.md)).

- The Explorer's **Teams** tab is reorganized around the selected team
  (#48, #70). The team menu now sits in the header beside the season,
  grouped by that season's conferences with teams ordered by record. The tab
  opens on a map of every home stadium at the team's level that season,
  sized by wins, with the team's conference in blue (tap a dot to switch
  team), followed by that conference's Elo lines over time. The team's
  end-of-season Elo and season records now sit side by side, each with a
  dotted line for its conference's average that season, replacing the fixed
  50% line. The all-conference small multiples are gone; the team menu
  covers that navigation.

- The README and About page are rewritten around where the project is now:
  exploring the data so fans can form their own hypotheses, AI agents working
  inside tested guardrails, and later, curated analyses that ask whether the
  data supports or refutes common football wisdom. The README is a short
  landing page; About carries the full story, starting with why the players
  are the ones most invested.

- The Explorer's game timeline now draws one shared crosshair: dragging
  across either the lead chart or the PPA chart (or stepping with
  Previous/Next) puts the vertical line on the same play in both charts,
  matching the play card. Before, each chart tracked the pointer on its own.

- The Explorer's **Draft & careers** tab, which replaces the Visualizations
  page (old links redirect to the Explorer, and the Explore hub's tile now
  opens it): every NFL draft since 2010 split by conference tier, with the
  selected team's picks each year and a tap-through to each player's college
  career; how many NFL seasons drafted players last, by round and pick, with
  the team's picks highlighted and still-active careers marked; and
  transfers by season and tier direction, nationally and into the selected
  team. The old page's `viz_*()` chart functions are removed (#70).

- Explorer polish (#78): axis titles no longer sit on the tick labels, each
  team's season records are drawn as shares of its games (100% bars with a
  50% line, counts in the tooltip) so win rates compare across seasons, and
  the Previous/Next play buttons, game tiles and chips no longer look
  disabled (Quarto's default button style had greyed their text).

- The Explorer's **Combine** tab: every NFL Scouting Combine invitee since
  2010 in a 3D scatter you can rotate, height by weight by 40-yard dash by
  default, with any three of the eight measurements on the axes, filtered by
  position (linemen included) and combine class, colored by draft round.
  Tapping a point shows all of the player's measurements and opens their
  college career in the Players tab. `combine_position_group()` maps combine
  positions onto the same groups the rest of the project uses (#70, #64).

- The Explorer's **Players** tab: a beeswarm of every player at a position
  for a season, one dot per player colored by NFL outcome, on a stat you
  pick (passing yards, sacks, yards per catch, ...), with conference filters
  and a name or school search. Picking a player shows their percentile on
  each of the position's headline stats season by season, the team logo for
  each season, and how their career ended (drafted with round and pick,
  signed as an undrafted free agent, still playing, or no NFL). Player chips
  in a game's play card open the player here (#70).

- Fixed: the Explorer's game timeline failed to load on the live site (GitHub
  Pages compresses the play files, which breaks partial reads); plays now
  ship in small per-season shards (100 per season, fetched whole), which also
  keeps the Pages deploy from timing out on thousands of files.

- The Explorer's **Teams** tab: conference landscapes of every team's
  end-of-season Elo (FCS by win share), each team's rating and record by
  season, its games week by week, and a play-by-play timeline of any game
  with the lead and the cumulative PPA edge you can scrub through (#70).

- New **Explorer** page (preview, not yet in the navigation): pick a season
  and a team to see its end-of-season Elo across every season since 2010. The
  link keeps your place, so it can be shared. It is the shell for the
  team, game, player and combine views coming next
  ([decision 0046](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0046-ojs-explorer.md), #70).
  Each table on the Data page now has its own link target, so other pages can
  point at it.

- The site's interactive graphs are back: the pipeline dependency graph and
  the data-model diagram rendered blank (on desktop and mobile) because their
  visNetwork libraries were never published, and the same gap hid the two
  static figures in the performance-arcs post and the fonts behind the
  interactive charts. A `.gitignore` rule was silently skipping every new
  file in the committed render cache; it now tracks them. The pipeline page
  now re-renders on every site build, so its graph shows the live build
  status rather than a stale local snapshot.

- `play_stats` now covers the 2026 season (who ran, caught, was targeted,
  tackled or sacked on each play) and grows every week: the Sunday refresh
  pulls each newly completed game and re-pulls the past 8 days' games once,
  reporting how many rows changed, so CFBD's corrections are both picked up
  and measured
  ([decision 0045](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0045-incremental-current-season-play-stats.md)).
  Past seasons are still backfilled on demand.

- New play-by-play tables (issue #44,
  [decision 0031](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0031-plays-ingest-and-quota-phasing.md)):
  `plays` (3.1 million plays, 2010 to 2026: down, distance, field position,
  score, clock, play type, yards, predicted points added, play text),
  `play_stats` (who ran, caught, was targeted, tackled, sacked or broke up a
  pass on each play, keyed by the shared athlete id), and the `play_types` /
  `play_stat_types` label tables. Published on `data-latest` and in the DuckDB
  bundle, each guarded by a contract (every game known, every played FBS week
  covered, no play-stats game at CFBD's 2,000-row cap, athlete ids in the
  roster namespace). `plays` refreshes with the season-scoped weekly job (one
  call per played week, about 280 for every season). `play_stats` costs one
  call per game, so it is opt-in (`CFB2NFL_PLAYS_STATS=true` with a season
  selection) and starts empty, to be backfilled one season per month, newest
  first. CFBD's pre-2014 `down = -1` for kickoffs and extra points is
  normalized to `0`, and the few impossible situations (about 125 plays) are
  set to `NA`.

- The weekly current-season refresh (`data-current.yaml`) now runs at 13:17
  UTC instead of on the hour, where GitHub delays or drops scheduled runs; it
  had not yet fired since it was added. A full refresh (`data-refresh.yaml`)
  keeps the published play stats instead of overwriting them.

- **Fix:** per-game box scores (`game_player_stats`) now list every player.
  The ingest kept only the first player per team, stat category and stat type
  in each game, about 7 players per team-game instead of about 33. The table
  was re-pulled and republished on `data-latest`. A new contract check fails
  any box score cut back to one player per stat type
  ([decision 0044](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0044-absence-shaped-season-signals.md)).
  The playing-time and performance-arcs posts are re-rendered on the corrected
  table, and their claims are revised. Most rostered player-seasons now log a
  stat line in some game, so the playing-time post's first expectation fails.
  The arcs post now says running back yardage peaks in the fourth season. Its
  earlier "plateau after the third" claim was wrong in the season totals
  regardless of the fix.

- New post on what the data can define for each position (issue #51): an
  early-stop proxy for finished careers, an injury-shaped absence and a
  benching-shaped usage decline within a season, and the limits (no injury
  feed, no unselected draft entrants). The two season signals come from the new
  `absence_runs()` and `usage_decline()`
  ([decision 0044](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0044-absence-shaped-season-signals.md)).

- Blog posts get a required review step. A new `vignette-reviewer` agent
  reads a drafted post cold, as a fan would, and reports where the argument or
  the reader stalls. A new `check_post_style()` enforces the mechanical
  [blog-style rules](https://github.com/ngiangre/cfb2nfl/blob/main/AGENTS.md)
  (titles in sync with the index entry, one visible setup chunk, numbered
  sections and assertion headings, verdict emojis, captioned tables, no em
  dashes, `stopifnot()` or pie charts). It runs in a new `post-style` CI job,
  in the test suite, and as a Claude Code hook after each edit to a post.

- New `combine` table: NFL Scouting Combine measurables (height, weight, 40,
  bench, vertical, broad jump, 3-cone, shuttle) for every invitee from 2010 on,
  from nflverse, linked to the CFBD athlete id
  ([decision 0043](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0043-combine-link-and-pre-draft-inputs.md),
  issue #45). Drafted invitees link by draft slot (99.7% from draft year 2013
  on); the rest by name, school and final college season (78% of undrafted
  invitees from 2011 on); `link_method` says which, and unmatched invitees are
  kept. Published as `combine.parquet` and in the DuckDB bundle, guarded by
  `contract_combine()`, with the link rate in the audit log's new `pct_linked`
  column. Combine numbers are pre-draft information, documented as such.

- The project is never installed as a package
  ([decision 0042](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0042-never-install-load-from-checkout.md),
  superseding 0030). Every page loads the code the same way, with
  `pkgload::load_all()` from the checkout, and the site and data workflows no
  longer install cfb2nfl. `app_sys()` now reads `inst/` from the checkout
  first, so a stale installed copy can no longer leave tables undocumented in
  the DuckDB `_schema_manifest`. The `cfb2nfl_root()` helper is removed
  (`pkgload::pkg_path()` replaces it).
- Each investigation now has a single setup chunk before its Introduction,
  divided into commented sections, instead of a stack of separate code folds.
  The post template follows the same layout.
- The pipeline page's dependency graph shows targets only
  (`tar_visnetwork(targets_only = TRUE)`), leaving out the functions they call.

- The data model is leaner: it now documents 21 tables instead of 29
  ([decision 0041](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0041-lean-data-model.md)).
  A derived table joins the DuckDB bundle only once a second investigation
  needs it or another table is built from it. Five tables used by at most one
  post are now built on the fly in that post from their tested package
  functions: redshirt flags (`flag_redshirt()`), career endings
  (`career_end_status()`), season arcs (`build_season_arcs()`), game
  production (`build_game_production()`) and wide player-season stats
  (`build_player_season_stats()`). Three with join logic worth guarding on
  every build stay contract-checked pipeline steps, read with
  `targets::tar_read()`, but leave the bundle: the NFL draft-slot bridge
  (`picks_nfl`), `position_path` and `player_usage`. The `player_season_inputs`
  view is dropped. SQL users get the name-guarded `gsis_id` from `outcomes`.

- New `data_model_network()`: a standalone (no Shiny) visNetwork of the data
  model, built dynamically from `inst/data-model.md` (join relationships) and
  `inst/dict/*.yml` (per-table grain, key and column definitions shown in node
  tooltips). The "Data & provenance" vignette now renders this interactive
  graph in place of the static mermaid ERD, and loads the package from the
  checkout with `pkgload::load_all()` like the dated vignettes.

- Blog posts no longer pin their stated numbers with `stopifnot()`
  ([decision 0040](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0040-drop-stopifnot-pins-show-setup.md)).
  A routine data refresh that nudged a count by three had been aborting the
  whole site render one post at a time. Every number in the prose is already
  an inline variable computed from the database, so a refresh now flows through
  the text instead of failing the build. Setup and loading chunks are also made
  visible (code shown, output and library noise suppressed) so each post is
  reproducible from `cfb2nfl.duckdb`. The post template and `AGENTS.md` are
  updated to match.

- New career-ending table: each college career is classified by how it ended
  (drafted, signed as an undrafted free agent, eligibility used up, transferred,
  still active or right-censored, and an early stop with eligibility left).
  The early-stop category is a proxy for an injury-shaped exit, not an injury
  label: CFBD has no injury feed. Derived and bundled in the DuckDB asset, with a
  contract, a dictionary, and an audit row
  ([decision 0039](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0039-career-end-proxy.md)).
- New derived tables `season_arc` (one player-season for a headline stat, with
  the player's career season index) and `game_production` (one player-game
  yardage stat against the opponent-Elo-band baseline, with unrated opponents
  kept as their own band). Both are bundled in DuckDB, carry contracts and
  audit rows, and feed the new performance-arcs post (issue #47; decision
  [0037](https://github.com/ngiangre/cfb2nfl/blob/feat/performance-arcs/decisions/0037-season-arcs-opponent-adjusted-production.md)).
- New derived table `player_usage` in the DuckDB bundle: one row per player,
  season and team with `games_appeared` over `team_games` (the appearance rate),
  regular-season counterparts, per-game passing, rushing, receiving and tackle
  volumes, and the harmonized position group and class year. Players on a roster
  with no stat line are kept with zero appearances. Checked by a new
  `contract_player_usage()` that ties the appearances back to `player_game` and
  `team_record()`. `player_appearance_sequence()` exposes the per-team-game flags
  for the career-end analyses (issue 51)
  ([decision 0038](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0038-player-usage-games-appeared.md)).
- New blog post on playing time: most rostered player-seasons log no stat line,
  offensive linemen almost never do, and drafted player-seasons log one in more
  of their team's games
  ([vignettes/2026-11-05-playing-time.qmd](https://github.com/ngiangre/cfb2nfl/blob/main/vignettes/2026-11-05-playing-time.qmd)).
- Season-scoped refresh: the scheduled data refresh now re-pulls only the
  current season and splices it into the published tables, costing about 28–40
  CFBD calls instead of ~780 (measured: 28 on 2026-11-05). The
  `CFB2NFL_REFRESH_SEASONS` selector (`current`, a year, a range, or a comma
  list) limits the season-keyed ingests; `splice_seasons()` replaces those
  seasons' rows and refuses to write on a missing file, a schema change, or a
  truncated pull; a new `season_coverage` contract checks no season goes
  missing. New `data-current.yaml` workflow (Sundays August–January plus after
  signing day, the combine, and the draft; rebuilds the site), new
  `data-raw/refresh-historical.R` for on-demand season backfills with a call
  estimate and confirmation, and `data-refresh.yaml` is now the on-demand full
  rebuild. Every CFBD call can be logged via `CFB2NFL_CALL_LOG`. Still one
  `data-latest` release, one parquet per table
  ([decision 0034](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0034-season-scoped-refresh.md)).
- New blog post on position stability from high school to college to the
  NFL: most linked recruits keep their position group in college, nearly every
  linked draftee keeps it in the NFL, and the roster source records no
  in-college change
  ([vignettes/2026-11-05-position-stability.qmd](https://github.com/ngiangre/cfb2nfl/blob/main/vignettes/2026-11-05-position-stability.qmd)).
- New `harmonize_position()` maps the recruiting, roster, draft, and NFL
  position codes to eleven shared groups. A contract fails the build if any
  raw code is unmapped
  ([decision 0036](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0036-position-harmonization-and-path.md)).
- New derived table `position_path` (DuckDB bundle only): one row per college
  athlete id with its harmonized high school, college and NFL position groups.
  High school groups come through a guarded recruiting link (exact name, or a
  name variant or missing college name backed by a school + class year match,
  `hs_link_method`), which links 98.6% of recruits instead of 61% at an
  estimated 0.6% wrong-person rate on the new links. NFL groups come only
  through the draft-slot link. Reused athlete ids are excluded
  ([decision 0036](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0036-position-harmonization-and-path.md)).
- New derived table `player_game` in the DuckDB bundle: one row per player per
  game with a stat line. It carries the side, opponent, conferences, points,
  pregame Elo (NA where CFBD has none), the wide per-game usage counts (passing,
  rushing, receiving, defensive), and `team_games`, the team's games played in
  the season, for games-appeared rates. Checked by a new data contract that
  requires one row per distinct player-game in the box score
  ([decision 0035](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0035-player-game-table.md)).

- New blog post testing whether schools that win more produce more
  draftees. The link is strong among Power schools and moderate in the
  Group of 5. The post also names the programs that draft more or fewer
  players than their record predicts, and checks that the result holds with
  SP+ and without transfer-ins
  ([vignettes/2026-10-31-winning-and-draftees.qmd](https://github.com/ngiangre/cfb2nfl/blob/main/vignettes/2026-10-31-winning-and-draftees.qmd)).

- New blog post on which conferences, schools and positions produce
  draftees and undrafted signings, including a check of fan nicknames
  such as DBU and Linebacker U
  ([vignettes/2026-10-31-who-produces-draftees.qmd](https://github.com/ngiangre/cfb2nfl/blob/main/vignettes/2026-10-31-who-produces-draftees.qmd)).
- New `shrink_rate()`: pulls rates for small groups toward their group's
  average (beta-binomial empirical Bayes), so a school with few players
  can't top a ranking on one lucky pick.

- New derived tables `team_season` and `team_draft` in the DuckDB bundle
  ([decision 0033](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0033-team-draft-attribution.md)).
  `team_season` has one row per team per season across every division:
  conference, tier, win-loss record, SP+ and SRS (FBS only), roster size, and
  stat-line coverage. Notre Dame is tiered Power, as decision 0003 specifies.
  `team_draft` credits draft picks and undrafted signings to the player's
  final college team, by position group, and it includes offensive linemen.
  Both are checked by new data contracts. `position_group()` is now one shared
  position map.
- New blog post on the college football landscape: the conferences and tiers,
  realignment, what the data records for each division, and how concentrated
  draft picks are
  ([vignettes/2026-10-31-conferences-landscape.qmd](https://github.com/ngiangre/cfb2nfl/blob/main/vignettes/2026-10-31-conferences-landscape.qmd)).

- Blog posts follow a revised section format
  ([decision 0025](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0025-blog-post-writing-style.md)):
  each section is a numbered assertion heading, one or two sentences, then a
  table, an explanatory figure, and an interactive exploratory figure. The
  post template and all six posts are rewritten to it, with figures and
  tables carrying the detail prose used to. Corrections made along the way:
  - The transfers post's lower-tier finding was wrong. Group of Five players
    drop to FCS more often than they climb to the Power conferences, so that
    expectation now fails.
  - The coaches post's title now counts the 418 head coaches active in the
    era (305 produced a draftee) rather than every coach since 1886.
  - The position post counts roster code `OT` as offensive line (the
    offensive-line drafted rate is now 8.4%).
  - Every post's pinned counts match the current `data-latest` release.

- New blog post: "Counting every college season instead of only the last
  changes the named head coaches for nearly half of recent draft picks"
  ([vignettes/2026-10-30-counting-coaches.qmd](https://github.com/ngiangre/cfb2nfl/blob/main/vignettes/2026-10-30-counting-coaches.qmd)),
  counting draftee-coach associations under a last-school and an
  every-season rule, with the transfer boom explaining most of the
  widening disagreement, plus position mixes and school-to-school splits
  for coaches who changed jobs. Adds `link_coaches_picks()` and
  `contract_coaches_picks()` with tests.

- Blog posts now declare `description:` (a one-sentence statement of the
  finding, also used for `<meta name="description">`) and `followups:` (open
  questions feeding later investigations and pipeline work) in their YAML;
  both are backfilled on the five existing posts, stubbed in
  `vignettes/_post-template.qmd`, displayed in the `investigations.qmd` index table,
  and documented in [AGENTS.md](https://github.com/ngiangre/cfb2nfl/blob/main/AGENTS.md).

- Removed the stale `test-beast.R` suite (it referenced parser functions that
  no longer exist) and fixed the two `R CMD check` notes: top-level
  `shiny_bookmarks/` and `the-beast-2026.txt` are now `.Rbuildignore`d, and
  the data-masked column names in `build_outcomes()` / `contract_outcomes()`
  are declared or `dplyr::`-qualified so no undefined-global note remains.
  `R CMD check` is clean again.

- The front-page hero banner gif now scales to the viewport
  (capped at 360 px wide) instead of rendering at a fixed width, so it
  fits the banner on phones as well as laptops
  ([README.md](https://github.com/ngiangre/cfb2nfl/blob/main/README.md),
  `altdoc/custom.scss`).

- Project renamed from `cfbstats` to `cfb2nfl`: package name, `theme_cfb2nfl()`
  and `cfb2nfl_root()` helpers, `CFB2NFL_{REFRESH,ROOT,DB}` environment
  variables, and `data/cfb2nfl.duckdb`. The GitHub repository moves to
  https://github.com/ngiangre/cfb2nfl (old URLs redirect).

- New blog post: "One player in five now plays a college season for a new
  school" (`vignettes/2026-10-24-transfers.qmd`), measuring transfer volume
  per season and direction across competition tiers: the post-2021
  one-time-rule climb from under five percent to 19 percent, same-tier vs
  up vs down shares, the origin-to-destination tier matrix, and transfer
  direction by position group.

- New blog post: "Offensive linemen are drafted most often and quarterbacks
  earliest" (`vignettes/2026-10-24-draft-eligibility-by-position.qmd`),
  splitting the eligible risk set by roster position: drafted and
  NFL-entry rates, round-1 shares, average draft pick over draft classes,
  per-season entry hazards, and undrafted-route shares by position group.

- Fix `outcome_signed_udfa_d` in the `outcomes` table: observed, undrafted
  player-seasons with no NFL roster match got NA instead of FALSE. A naive
  `mean(na.rm = TRUE)` over the flag then read UDFA prevalence at 35 percent
  instead of the correct 4.7. Censoring is now the only source of NA in the
  flag, guarded by a new `contract_outcomes()` assertion and pinned by unit
  tests. Reported 2026-10-24.

- New outcome-prevalence blog post: "Most draft-eligible college seasons end
  without an NFL outcome" (`vignettes/2026-10-24-outcome-prevalence.qmd`),
  measuring each outcome's prevalence over the eligible risk set with
  Wilson intervals, per-season hazards, draft-class trends, and
  entry-year rookie outcomes.

- New `outcomes` table: the person-period modeling dependent variable
  (decision 0032, https://github.com/nicholasgiangreco/cfb2nfl/blob/main/decisions/0032-outcome-table-person-period.md).
  One row per player-season in the model population, carrying the draft
  eligibility clock (`hs_grad_year`, `draft_eligible`,
  `eligible_season_index`), the drafted / NFL-entry / NFL-success labels
  (`outcome_*` columns), and survival bookkeeping (`years_to_nfl_entry`,
  `status_end_of_season`, `outcome_observed_d` right-censoring) — queryable
  directly by models with no further derivation. Published as
  `data/outcomes.parquet` on the data-latest release and bundled into
  `cfb2nfl.duckdb`, documented in `inst/dict/outcomes.yml` and guarded by a
  new `contract_outcomes()` pipeline contract.

- Site fixes for stale content (fixes the deployed site not showing edited
  post titles, reported 2026-10-24). Vignette freeze mode changed from
  `freeze: true` to `freeze: auto`: under `true`, Quarto serves the committed
  `_quarto/_freeze/` cache unconditionally — even after the source changes —
  so title edits never reached the deployed pages. The `site` workflow also
  deletes the freeze caches for the `blog` and `reference` index pages before
  rendering, because their knit-time reads of other files' YAML/metadata are
  invisible to Quarto's per-document cache check.

- Fix CI dependency resolution: `querychat` was archived off CRAN on
  2026-10-22 (check issues not corrected in time), so the `check` and `site`
  workflows failed to solve dependencies. A `Remotes: posit-dev/querychat/pkg-r`
  entry now installs it from GitHub.

- The Shiny app now works on phones: the table browser sends its server-side
  request as a POST so the full DataTables payload fits in the request body
  (the previous multi-kilobyte GET query string was rejected through proxied
  deployments, showing a DataTables ajax error), and the table tabs scroll
  sideways instead of stacking.

- The blog post "Seven quarterbacks, one database" now defines redshirt flags
  from game-level usage in the `game_player_stats` table (at most one game with
  a recorded statistic among covered games, observable positions only) instead
  of stat presence, reports a per-player redshirt verdict against each
  expectation, and trims the narrative.
- All rendered site pages now expose Quarto code tools (source toggle) via
  `code-tools: true` in the site format.

- Fix a site-build failure with two causes: the pipeline's `week_grid` target
  now derives its (season, seasonType, week) grid from the cleaned `games`
  table, which exists in both refresh and track modes, instead of the
  ingest-mode-only `raw_games` (NULL in track mode, which aborted
  `tar_make()`); and the content vignettes now attach the installed cfb2nfl
  package in their setup chunk, so `cfb2nfl_root()` resolves in the fresh
  quarto R session (previously only sourced from the checkout when the package
  was absent).

- The documentation site no longer requires the cfb2nfl package to be
  installed: vignette setup chunks source `R/*.R` from the checkout when the
  package is missing, and man-page examples render unexecuted
  ([decision 0030](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0030-site-build-no-package-install.md)).
- The ERD on the Data page is now rendered live from mermaid (mirroring
  `inst/data-model.md`) instead of a pre-rendered PNG that had drifted behind
  the new `games`, `game_team_stats`, and `game_player_stats` tables.
- `inst/data-model.md` fixes: the join-namespace count is six (the CFBD game id
  namespace was added without updating the count) and a duplicated
  `nfl_draft_picks ||--o{ nfl_rosters` edge was removed.

- The `/games` family ingest is now dynamically branched in the pipeline
  (one target branch per API call, decision 0029): an interrupted refresh
  resumes at the first un-ingested season/week instead of re-pulling the whole
  ~1,150-call sweep. Combined tables keep the same grain, so all downstream
  targets and published assets are unchanged.

First tracked release of the project scaffolding. The repo now carries the full
ingest → clean → link → features → model → report pipeline, its lineage/audit
layer, and the documentation site, all under version control.

- New game-statistics tables from the CFBD `/games` family: `games` (one row
  per game), `game_team_stats` (team-game-category-stat), and
  `game_player_stats` (player-game-category-statType-stat). All long-grain;
  `game_player_stats.playerId` joins the shared athlete-id namespace directly.
  Ships with contracts, dictionaries (`inst/dict/games*.yml`), DuckDB bundle
  membership, and data-model documentation.
- The pipeline no longer re-ingests on every run: ingest and parquet-asset
  targets track normally, and `data-raw/refresh.R` invalidates all targets
  before an explicit full refresh. New `data-raw/pull-data.R` downloads the
  latest cleaned data from the `data-latest` release so local track-mode work
  needs no CFBD API key or quota.

- New `app.R`: a Shiny app powered by
  [querychat](https://posit-dev.github.io/querychat/) for natural-language
  querying of the DuckDB bundle. All tables (plus the `player_season_inputs`
  view) are registered for cross-table SQL joins, the `inst/dict/*.yml` data
  dictionaries and the join-key rules from `inst/data-model.md` are provided as
  LLM context, and an explicit greeting avoids the single-table auto-greeting
  pitfall.

- The DuckDB bundle now carries a wide `player_season_stats` table (one row per
  player-season-team, one numeric column per `(category, statType)` pair) so
  SQL users no longer pivot the 1.5M-row long `player_stats` by hand
  ([decision 0026](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0026-wide-player-season-stats-duckdb.md)).
- The drafted-rate-by-tier example query in `inst/data-model.md` is corrected to
  aggregate the long stats to player-season grain before joining (the old query
  counted stat lines, not players).
- The DuckDB bundle is now self-documenting and self-checking
  ([decision 0027](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0027-duckdb-queryability-batch.md)):
  a name-guarded `nfl_pick_link` bridge to the NFL tables, a queryable slimmed
  `audit_log`, a generated `_schema_manifest` (grain/key from the
  dictionaries), a `_meta` row recording the last complete season/draft class,
  and a leakage-safe `player_season_inputs` view.
- Out-of-range roster heights (outside 60-85 inches) are coerced to NA and the
  roster contract now covers height, mirroring the weight precedent.
- CFBD ingest requests retry transient failures (429/5xx) with exponential
  backoff, so a temporary API outage or rate-limit window no longer fails the
  whole weekly refresh
  ([decision 0028](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0028-cfbd-retry-backoff.md)).

- The expectation-check blog post is revised into a research-article structure
  (Introduction, Data, Results, Summary, Discussion) with neutral scientific
  phrasing and corrected observations re-verified against the published data;
  the class-year audit section was removed in favor of the fix recorded in
  [decision 0024](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0024-class-year-coercion-and-fifth-year-flag.md).

- The roster backbone is now guarded against two defects surfaced by the
  expectation-check blog post
  ([decision 0024](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0024-class-year-coercion-and-fifth-year-flag.md)).
  `clean_roster()` coerces `class_year` outside the plausible 1-5 eligibility
  range to `NA` — older CFBD seasons return the queried *year* in the
  eligibility-class field (~124k rows, pre-2020) — so the derived
  `fifth_year_career` flag now measures *observed* fifth-year classes instead
  of a year-value coincidence. `contract_roster()` adds two checks:
  `(playerId, season, team)` key uniqueness (a player on two teams within one
  season stays allowed) and the `class_year` range, so future contamination
  blocks the build via the contract gate rather than publishing. The data
  was refreshed and re-published on the `data-latest` release to satisfy the
  new contract.

- The audit log is now interpretable and enforced. `audit_step()` records
  **join coverage** (`pct_keys_matched`, `keys_dropped` — distinct key
  combinations from the input that vanish, separating filtering from join
  fan-out), **per-column NA accounting** (`n_cols_with_na` plus a `na_by_col`
  profile attributing sparsity to columns), and a **schema history**:
  `update_schema_history()` appends each run's per-step hashes to
  `data/audit_history.csv`, carried across refreshes as a `data-latest` release
  asset, so `schema_hash` drift between refreshes is detectable. The Data &
  provenance page renders the new columns and the history. Data contracts now
  **block the build**: a new `contract_gate` target aborts `tar_make()` when
  any `ok_*` check fails, so failing data never publishes ([decision 0023](
  https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0023-contract-gate-blocks-build.md)).
  New contracts cover every model-path link/features step (coach link fan-out,
  tier link, reused-id filter, change features, roster weight, recruiting
  link, player-season uniqueness), and the audit's key declarations were
  corrected (`clean_picks` keys on the draft slot; mid-season transfers are
  distinct rows at `(playerId, season, team)`). CFBD athlete-id reuse is
  handled explicitly ([decision 0022](
  https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0022-cfbd-athlete-id-reuse.md)):
  `reused_ids()` flags ids spanning implausible career windows (> 7 seasons),
  `career_summary(max_span = 7L)` drops them, and a `ps_pop` target filters the
  model population.

- The Data & provenance page now embeds the entity-relationship diagram as a
  pre-rendered image (`vignettes/images/erd.png`) instead of a raw mermaid
  block, so it renders identically without client-side mermaid. The diagram's
  source of truth remains the hand-authored mermaid block in
  `inst/data-model.md`.

- The Explore hub page tiles now use a responsive fenced-div card grid
  (equal-width, whole-tile links) instead of `bslib::layout_columns()`, whose
  Bootstrap grid classes are absent from Quarto's pruned Bootstrap build and
  previously collapsed the tiles.

## Pipeline & data

- Derived feature tables are now **first-class pipeline targets** bundled into
  the DuckDB asset and documented in the data model ([decision 0021](
  https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0021-derived-feature-tables-in-pipeline.md)).
  `career_summary(roster)` (`career` target), `flag_redshirt(roster,
  player_stats)` (`roster_flags` target), and the existing `ps_change` backbone
  carry contracts and audit rows like the cleaned tables, ship in
  `data/cfb2nfl.duckdb` with new dictionaries (`inst/dict/*.yml`) and ERD
  entries, and are **not** published as standalone parquet (they rebuild from
  other cleaned tables in any mode, so no release asset is needed before a
  track-mode build). `player_dossier()` gains optional `career` /
  `roster_flags` arguments attaching a "Career & eligibility" section, and
  `explore.qmd` reads the targets instead of recomputing features per figure.

- The documentation site now navigates entirely through the top navbar
  (Home, Explore, Blog, Reference on the left; News/License/Citation + GitHub
  on the right) instead of a sidebar. New hand-wired pages: `explore.qmd` is a
  hub of value-card tiles linking to About, Analysis, Data & provenance,
  Visualizations, and Pipeline; `investigations.qmd` lists dated posts in a table built
  from their YAML; `reference.qmd` lists every non-internal function with links
  to its man page. The interactive-charts page formerly called `explore.qmd`
  is renamed `visualizations.qmd`.

- Added the third Explore question-answer pair (question 12): **redshirts,
  defined approximately**. `flag_redshirt()` derives two redshirt-*shaped*
  signals from the roster backbone — a no-stat season the player returned from
  (stat-gap rule) and an observed fifth eligibility class — `contract_redshirt()`
  sanity-checks the flags, and `viz_redshirt_by_career_length()` /
  `viz_redshirt_seasonality()` plot them. The seasonality chart is a 100%
  stacked ledger per season — stat line recorded / redshirt-shaped gap /
  uninformative final-season gap — making the confound explicit: the source
  records stats for only ~26% of roster seasons in 2010 rising to ~60% by
  2021, so the redshirt-shaped share is an upper bound dominated by missing
  data in the early years. `explore.qmd` gains a "Redshirts" section; `scales`
  joins Imports.

- Added the second Explore question-answer pair (question 5): **transfers —
  how many, and in which direction**. `transfer_counts()` aggregates the
  existing `add_change_features()` team changes into season × tier-direction
  counts, `transfer_rate()` gives the career-grain share of players with at
  least one transfer (13.7% of 135,356 roster players), and
  `viz_transfers_by_season()` plots the stacked counts. `explore.qmd` gains a
  "Movement — transfers" section with undercount caveats (stat-line players
  only; moves to/from seasons with no roster row are invisible).

- Added the first Explore question-answer pair (Explore plan, question 4):
  **college career length**. `career_summary()` collapses the roster backbone
  to one row per player — seasons on a roster, first/last season, gap seasons,
  and transfer count — `contract_career_summary()` enforces the career-length
  bounds (1–7 seasons, non-negative gaps/transfers), and `viz_career_length()`
  plots the seasons-per-player distribution. `vignettes/explore.qmd` gains a
  "Career length" section with the roster-grain caveats (redshirt / medical /
  COVID years are not separable at this grain; that disambiguation is the
  later redshirt question).
- Fixed vignette rendering outside altdoc: vignettes now resolve the project
  root via `cfb2nfl_root()`, which falls back to walking up to the nearest
  `_targets` store when `CFB2NFL_ROOT` is unset, so a direct `quarto preview`
  no longer fails with "targets data store _targets not found".

- Added a **stat-phase taxonomy** and an **interpretable player dossier** so a
  reviewer gets *interpretation*, not a raw extract (decision 0019). The long
  `player_stats` already tags each stat with a `category`, but a flattened
  extract loses it; the new `stat_taxonomy()` (hand-authored package data in
  `inst/extdata/stat_taxonomy.csv`, materialized into the DuckDB bundle) maps
  every `(category, statType)` to a game **phase** (offense / defense /
  special_teams), a plain-language `label`, and a `kind`, so a bare `TD` becomes
  "Passing touchdowns" vs "Defensive touchdowns". It is keyed at
  `(category, statType)` grain because `fumbles` is phase-ambiguous
  (`FUM`/`LOST` offense, `REC` defense); `label_stats()` applies it and
  `contract_stat_taxonomy()` fails fast if a refresh introduces an unlabeled
  stat. `resolve_nfl_outcome()` is the general college→NFL bridge — **drafted**
  via the reliable draft-slot bridge (decision 0014) or **undrafted-signed** via
  a name-guarded match against `nfl_rosters` (disambiguated by college then
  rookie-year window), refusing to guess on an unresolved name collision
  (`no-NFL-record`); it is enabled by adding `player_name` to
  `clean_nfl_rosters` (dict + `contract_nfl_rosters` updated) and stays
  outcome-side, off the model path. `player_dossier(id, …)` assembles a
  `cfb_dossier` (tidy tables + a `print()` method): identity, stats grouped and
  labeled by phase, per-player-season coaching with an explicit "head coach not
  available (non-FBS / not in CFBD feed)" flag, name-guarded recruiting (unrated
  stays unrated), the drafted/undrafted-signed outcome with right-censored
  longevity, and a provenance/caveats block. The Explore vignette renders an
  interpreted dossier (Cam Ward) so the site shows the extract, not raw rows.
  Validated on Kyle Allen (undrafted,
  9 NFL seasons) and Cam Ward (#1 overall 2025; 2021 Incarnate Word flagged as
  an FCS coach gap). Covered by `tests/testthat/test-stat-taxonomy.R`,
  `test-nfl-outcome.R`, and `test-dossier.R`. **`nfl_rosters` must be refreshed
  and republished on `data-latest` before merge** (schema change).
  See [decision 0019](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0019-stat-taxonomy-and-player-dossier.md).

- **Published parquet are now the cleaned tables** (decision 0018), so the
  `data/*.parquet` assets, the DuckDB bundle, and the data dictionaries all carry
  one identical schema per table. Ingest (`raw_*`) now happens in memory in
  refresh mode only; each `<table>_file` target writes the *cleaned* parquet and
  `<table>` reads it back, making the cleaned parquet the single source of truth
  downstream. Track-mode builds read the cleaned parquet directly (no re-clean,
  no key). See [decision 0018](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0018-cleaned-parquet-assets.md).

- **The `targets` pipeline now owns ingest → process → assets** (decision 0017).
  A single `tar_make()` in **refresh mode** (`CFB2NFL_REFRESH=true`) ingests
  every source — including `conference_tiers`, now derived in-pipeline from the
  ingested `player_stats` by the new `build_conference_tiers()` — processes it,
  and writes every data asset (raw parquet **and** `cfb2nfl.duckdb`) in one
  dependency-ordered pass. Ingestion is env-gated via `parquet_asset()`: refresh
  mode writes the parquet, the default **track mode** reads the
  committed/downloaded file with no API key (how the keyless site build runs).
  `data-raw/refresh.R` is now a thin wrapper and `data-raw/conference_tiers.R`
  is removed; the `data-refresh` workflow is a single `tar_make()` +
  publish-assets. See [decision 0017](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0017-pipeline-owns-ingest-and-assets.md).

- Added a **queryable DuckDB data asset** (`data/cfb2nfl.duckdb`) that bundles
  every cleaned, contract-checked table into one SQL-queryable file, built by the
  new `build_duckdb()` (`R/duckdb.R`) as the `duckdb_file` pipeline target
  (`format = "file"`, downstream of the clean stage) so its schema matches the
  data dictionaries. It is published alongside the parquet on the `data-latest`
  release: the `data-refresh` workflow pulls existing assets, ingests, runs
  `tar_make(duckdb_file)`, then uploads the parquet **and** the `.duckdb` file.
  Added `inst/data-model.md` — a Mermaid ERD plus the five join namespaces (and
  the two look-alike traps, `recruiting.playerId` and `picks.nflAthleteId`),
  leakage / out-of-time guidance, and example SQL — cross-linking each table to
  its `inst/dict/*.yml`. `DBI` and `duckdb` added to `Suggests`.
  See [decision 0016](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0016-duckdb-query-asset.md).

- Added **NFL outcomes for drafted players** from nflverse (`nflreadr`) as three
  first-class tables (`ingest_nfl_*()` → `clean_nfl_*()`, published on the
  `data-latest` release): `nfl_draft_picks` (the bridge + Pro-Football-Reference
  career summary), `nfl_rosters` (player-season roster presence — the longevity
  source), and `nfl_player_stats` (weekly stats aggregated to the player-season
  grain, regular season). `link_nfl_draft()` bridges CFBD `picks` to nflverse
  ids by **draft slot** — `(year, round, overall)` == `(season, round, pick)` —
  behind a normalized-name guard, because CFBD `nflAthleteId` is a *different*
  namespace (0 of 4,350 recent picks match nflverse `espn_id`) and name-only
  matching is collision-prone; the slot join matches ~97% of 2010+ picks after
  the guard. "How long they last" is defined primarily as **distinct NFL seasons
  on a roster**, complemented by career games and last active season — all
  **right-censored** for recent classes still active, so treat them as "≥"
  outcomes. NFL data is an *outcome/label* source, kept off the model input path
  (feeding it as a feature would be leakage). Enforcing the roster contract
  surfaced impossible weights (0/18/449/1794 lbs) coerced to `NA` (mirroring the
  CFBD roster placeholder handling), and 16 unattributed stat rows with a null
  `player_id` dropped. Guarded by `contract_nfl_draft_picks()` /
  `contract_nfl_rosters()` / `contract_nfl_player_stats()` / `contract_nfl_link()`,
  data dictionaries (`inst/dict/nfl_*.yml`, dict-parity test), and
  `tests/testthat/test-nfl.R`.
  See [decision 0014](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0014-nfl-outcomes-nflverse-link.md).
- Added **high-school recruiting ratings** as a first-class table
  (`ingest_recruiting()` → `data/recruiting.parquet`, published on the
  `data-latest` release): CFBD `stars`/`rating`/`ranking` per recruit.
  `clean_recruiting()` builds a per-athlete rating table and
  `link_recruiting()` attaches it to the player-season backbone behind a
  **normalized-name guard** — the recruiting `athleteId` is a *separate*
  namespace that collides across different people (Cam Ward's id maps to a
  different recruit, Xavier Ward), so a rating is trusted only when the recruit
  name agrees with the backbone name; wrong-person ratings are nulled and
  flagged by `recruit_matched`. Guarded, honest coverage of drafted players is
  ~60–72% for recent classes; genuinely unranked players (like Cam Ward) are
  absent by design. Guarded by `contract_recruiting()` (`ok_recruiting`), a data
  dictionary (`inst/dict/recruiting.yml`, dict-parity test), and
  `tests/testthat/test-recruiting.R`. Kept off the model path for now (like the
  team display dimension).
  See [decision 0013](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0013-recruiting-id-namespace-collision.md).
- Extended the data window from 2010–2025 to **2010–2026**: `ingest_player_stats()`
  and `ingest_roster()` now default to `2010:2026` (and `data-raw/refresh.R` pulls
  through 2026), with the season contracts (`contract_player_stats()`,
  `contract_conference_tiers()`) and dictionaries updated to match. Draft-facing
  bounds moved to 2027 accordingly — `link_drafted()` now defaults to a
  `2010:2027` draft window (the 2010–2026 stats window plus the following spring's
  draft), and `contract_picks()`/`contract_drafted()` widen their year checks. The
  2026 refresh adds preseason rosters and the completed 2026 draft class; 2026
  season stats are not yet available (season not started).
  See [decision 0012](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0012-extend-data-window-to-2026.md).
- `targets` pipeline (`_targets.R`) as the single source of truth for the DAG,
  with stage functions in `R/` (`ingest`, `clean`, `link`, `features`, `model`).
  See [decision 0004](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0004-adopt-targets-orchestration.md).
- Lineage/audit layer: `audit_step()` emits a per-step record (row/col counts,
  key coverage, schema hash, contract status, git SHA) into the `audit_log`
  target; data dictionaries in `inst/dict/`.
  See [decision 0005](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0005-lineage-and-audit-design.md).
- Data contracts (`pointblank`) and unit tests (`testthat`) run in the pipeline.
- Data dictionaries reconciled with the cleaned schema and now guarded by a
  test: `inst/dict/{coaches,roster,picks}.yml` were completed (coaches gains
  `conference`/`games`/`wins`/`losses`, roster gains `jersey`/`home_city`, picks
  documents all 26 pass-through columns), `contract_coaches()`/`contract_picks()`
  assert the added columns, and `tests/testthat/test-dict.R` asserts every
  `inst/dict/*.yml` matches its target's column names and types.
  See [decision 0010](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0010-reviewer-skills-and-dict-parity-test.md).
- v1 scope — weight/coaching/transfer change features and the drafted outcome.
  See [decision 0003](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0003-expand-v1-scope-weight-coaching-transfers.md).
- The `data-refresh` workflow now creates the `data-latest` release on first run
  (before uploading), so bootstrapping the data asset no longer needs a manual step.
- Roster finalized as a first-class pipeline target (`roster_file` → `raw_roster`
  → `roster`), replacing the empty-roster fallback; `add_roster_weight()` attaches
  the static roster `weight`. Between-season `weight_delta` is dropped as not
  derivable from CFBD `/roster` (weight is static per player: 0 of 64,350
  multi-season players vary). Enforcing the roster contract surfaced a
  data-quality issue the fallback had hidden: `clean_roster()` now coerces a
  placeholder `weight` of `0` to `NA`, and the contract weight range is 100–500 lb.
  See [decision 0009](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0009-finalize-roster-drop-weight-delta.md).
- Fixed a silent fan-out and false-positive draft attribution in the
  draft-outcome join: `picks` carries the full NFL draft history (back to 1936)
  and CFBD reuses `collegeAthleteId` across eras, so a modern player's id could
  match an ancient pick — duplicating a player-season and marking it `drafted`
  off a pre-window draft. `link_drafted()` now ignores picks outside the
  plausible draft window (`draft_window`, default `2010:2026`) and collapses the
  outcome to one pick per `playerId`, making the join strictly 1:1 and only ever
  marking `drafted` for an in-window pick. The new `contract_drafted()`
  (`ok_drafted`, fed into the `link_drafted` audit record) and
  `tests/testthat/test-link.R` guard against regressions.
  See [decision 0011](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0011-draft-outcome-one-pick-per-player.md).
- Team logos & colors: a `teams` display dimension sourced from CFBD `/teams`
  (`ingest_teams()`/`clean_teams()`, `data/teams.parquet`), joined by school name
  via `link_team_meta()` at the report layer only (kept off the model path).
  `contract_teams()` enforces full team-name coverage of the player-season
  backbone. See [decision 0008](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0008-team-logos-dimension.md).

## Documentation site

- Added `player_trajectory()` — assembles a subject registry's college→NFL
  spine (one row per player-season across both stages) with a **data-backed
  draft status** keyed on the nflverse `gsis_id` (presence in `nfl_draft_picks`
  ⇒ drafted; absence ⇒ undrafted, no name guard needed since both sides share
  nflverse's id namespace). The first blog post
  (`vignettes/2026-08-27-buechele-allen.qmd`) now calls it instead of inlining
  the parquet pull, and its timeline caption's "neither player was drafted"
  claim is enforced at author time (`stopifnot(!any(spine$drafted))`) rather
  than asserted in prose. `contract_player_trajectory()` guards the output
  (non-null `who`/`team`/`stage`, `stage` in `{College, NFL}`, complete logical
  `drafted`). Covered by `tests/testthat/test-link.R` and
  `tests/testthat/test-contracts.R`.
  See [decision 0015](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0015-blog-post-conventions-and-build-robustness.md).
  `player_trajectory()` and the first blog post now read the published parquet
  on its **cleaned** schema (decision 0018) rather than the raw schema they were
  written against: the helper filters roster `playerId` and NFL roster
  `nfl_team` (test fixtures updated to match), and the post's recruiting chunk
  and team-metadata join use the cleaned recruiting columns (`playerId`,
  `recruit_name`, `hs_class`, `national_rank`, `committed_to`) and `teams$team`.
  The post's committed Quarto freeze was regenerated against the fixed code.
- Added `data-raw/build-site.R`, a thin local-build wrapper mirroring the
  `site` workflow: it sets `CFB2NFL_ROOT` to the project root (so vignettes
  resolve `data/*.parquet` and `tar_read()` from altdoc's temp build dir) and
  runs `altdoc::render_docs(freeze = TRUE)` to reuse the committed freeze cache.
- Added an **NFL-outcomes exemplar** to the Explore page: `viz_nfl_roster_seasons_by_round()`
  plots career length (distinct seasons on an NFL roster) by draft round with the
  #1 overall picks highlighted against the field, noting the right-censoring of
  recent classes. The vision/question and data-source pages (`VISION.md`,
  `README.md`, `about`/`data`/`pipeline` vignettes) now cover the post-draft NFL
  question and the three nflverse tables.
  See [decision 0014](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0014-nfl-outcomes-nflverse-link.md).
- `altdoc` + Quarto website built to `docs/` and deployed to GitHub Pages;
  vignettes read the pipeline via `tar_read()`.
  See [decision 0006](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0006-quarto-site-architecture-and-viz.md).
- Site renders reuse a committed Quarto freeze cache (`_quarto/_freeze/`) so CI
  is faster and deterministic.
- Reworked the fan-facing Home (`README.md`) and About page for the
  non-technical fan in [VISION.md](https://github.com/ngiangre/cfb2nfl/blob/main/VISION.md)
  §10: added a "Where to start" fan path (About → Explore → Analysis) on the
  README, translated the About page's scope and methodology into plain football
  language, and tucked the statistical/tooling detail (the two cultures,
  out-of-time validation, decision log, `testthat`/`pointblank`) into a
  collapsible "For the stats-minded" callout so coders still have it.

## Project conventions

- Developed as an R package; `check()` is a conventions gate, not CRAN prep.
  See [decision 0002](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0002-rbuildignore-non-package-files.md)
  and [decision 0001](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0001-establish-project-vision-and-conventions.md).
- Established the feature-branch → NEWS → squash-merge workflow used for most
  work here, with this changelog linked from the site.
  See [decision 0007](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0007-feature-branch-news-merge-workflow.md).
- Set the package author/maintainer.
- Added three invocable `.claude/skills/` skills: `cfb2nfl` (slimmed to a
  pointer to `AGENTS.md`/`VISION.md`/dictionaries), `fan-experience-improver`
  (edits the fan-facing site toward the non-technical fan audience while
  protecting the technical pages), and `architecture-improver` (keeps the
  pipeline, data model, and conventions legible and auditable, works
  test/contract-first, and checks that graphics/models preserve expected counts
  and subsets).
  See [decision 0010](https://github.com/ngiangre/cfb2nfl/blob/main/decisions/0010-reviewer-skills-and-dict-parity-test.md).

The full decision log lives in
[`decisions/`](https://github.com/ngiangre/cfb2nfl/tree/main/decisions).

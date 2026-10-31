# Plan: Coaches and their draftees

Blog post on head coaches and NFL draft output. All numbers below are
**placeholders from the 2026-10-30 exploration session** — recompute every
figure in the post's own chunks; do not copy them in. Code from that session
was not saved to a script, so treat this plan as direction, not results.

## Framing constraint (carried from exploration)

CFBD gives **head coaches only** — no position coaches, coordinators, or S&C.
So a head coach is *associated* with a draftee, not their sole developer: the
credited coach sits atop a staff of position coaches who may do the actual
development. The narrative must say "coaches under whom draft picks played,"
not "produced," and the Discussion should name the missing apprenticeship
layer (a true Saban-style coach tree needs an external source; CFBD has none,
see `inst/cfbd-api-coverage.md` § Coaches). Derivable from CFBD: a
**succession tree** (seat changes), noted as future work, not this post.

## Attribution rules (the spine of the post)

A draft pick is linked to head coaches via the roster backbone:
`picks.playerId` → `roster(playerId, season, team)` → `coaches(school, season)`
(school name join; both rules restricted to seasons **before** the draft year;
players with reused ids per `reused_ids()` / decision 0022 excluded first).

- **last**: coach in the player's final roster season before the draft.
- **any**: every coach the player had ≥ 1 roster season with, counted once
  per player. No minimum-exposure threshold (a coach who held the job for one
  season gets credit); state this.

**Roster-window caveat (required framing, per review):** roster starts in
2010, so early draft classes have short observable careers — a 2011 pick has
at most one roster season, 2012 at most two. "any" and "last" mechanically
converge for early classes, biasing the comparison. Therefore:

- Present the two-rule comparison **by draft class** (overlap per class) and
  run the head-to-head leaderboard on classes with full observable careers
  (~2014+); the numbers in the post come from the restricted window, with the
  class-by-class view shown so the reader sees why.
- The 58% exact-overlap figure from exploration is a window artifact until
  recomputed on the restricted window.

The two rules answer different questions: last = who gets credit for the
finished product; any = everyone who oversaw part of the development.
Present both; do not pick a silent winner. Say once that "same set" means
exact set equality of credited coach ids (a strict test).

**Attribution funnel (required):** report picks falling out at each step:
all picks in window → with `playerId` → matching a roster season → matching
a coach-season (school name). Include the unmatched-school-name count as a
join-health check. Per AGENTS.md, player key = athlete id (trusted
namespace); watch for silent row loss on every join.

## Tie handling (decided up front)

`coaches.parquet` has ~203 duplicated (school, season) rows — mid-season
changes and interims; ~259 picks (last-rule, exploration figure) map to > 1
coach even in their final season. **Decision: credit all co-listed coaches**
(conservative, matches "association not production" framing), stated in the
Data section. Fractional credit and interim-flag resolution via
`GET /coaches/tenures` (has an interim flag) are **out of scope** — new
ingest costing API quota. Note: multi-coach seasons also mean the
coaches-season table itself is not one-row-per-(school, season).

## Sections

1. **Data + definitions.** Who counts as a "producing" coach; both rules and
   the tie rule defined up front; head-coach-only caveat stated here, not
   buried; the attribution funnel.
2. **Top producers** under both rules on the restricted window, showing the
   leaderboard shift. Exploration-era top-10 (last rule, 2011+ window —
   placeholder): Saban 120, Swinney 87, Smart 84, Kelly 80, Franklin 72,
   Fisher 70, Day 69, Harbaugh 68, Ferentz 61, Richt 52. Note that a coach's
   credits span schools (Harbaugh's total covers Michigan and Stanford):
   leaderboard is per coach, tenure analysis is per school-stint.
3. **Tenure.** Draft credits by coach's year at the school (0-based). Must
   be presented as **a rate**: picks per coach-season at each tenure year,
   not raw counts — raw counts decline partly because few coaches survive to
   year 8+ (survivorship). Show the coach-season denominator alongside.
   Year-0 is dominated by inherited roster (exploration: 694 picks under the
   last rule — recompute and name the rule in the text). Discuss or at least
   name the inherited-vs-his-recruits split (recruiting talent join as
   mediator; `draftFollowingSeason` on `/coaches/seasons` is the tempting
   shortcut but is leakage — must stay off any model input path; say so).
4. **Position-developer archetypes.** Coach's offensive share of picks vs.
   the league baseline (~35% under last rule, exploration). Define the
   offense/defense grouping explicitly in the narrative (which positions are
   offense, where K/P/LS land). Threshold ≥ 30 picks is a stated choice;
   shares at n ≈ 30–60 are noisy — add Wilson intervals (repo precedent).
   Name the confound: archetype may reflect program recruiting footprint,
   not the coach; the cleanest check is the same coach at different schools.
   Exploration placeholders (≥ 30 picks): defensive lean — Whittingham 20%,
   Patterson 23%, Chryst 24%, Cristobal 26%, Stoops 28%, Harbaugh 29%,
   Ferentz 30%; offensive lean — Dykes 61%, Riley 46%, Kiffin/Bielema 45%,
   Shaw 44%. Finer position factories (DB/QB) as a stretch cut.
5. **Discussion** (callouts + short caveats paragraph, per blog style):
   attribution is a choice; the rules disagree for a large share of picks;
   head coach is one voice on a staff; draftees are a talent-selection
   outcome, so credit concentrates at programs that recruit well — name the
   recruiting-control / coach-moves-schools analyses as the missing
   separation of coach from program; denominator note (a rate per
   roster-season view is desirable; name it if not computed).

## Data handling rules

- Restrict to picks with `playerId` and `year >= 2011` (roster backbone
  era; both filters are draft-year filters — say so in the same sentence);
  the head-to-head additionally restricted to ~2014+ classes.
- Exclude players flagged by `reused_ids()` (decision 0022).
- Join coach by school name; dedupe picks to `(year, overall, coach_id)`;
  count each coach once per pick under "any."
- Coach tenure = `season - min(season)` for that coach **at that school**;
  assert tenure is not left-censored (verify no coach's first season at a
  school falls inside the observed window with prior seasons missing).
- Validate row counts at every join (no silent loss); `stopifnot()`-pin the
  named examples per the blog style.
- Keep nflverse outcome data out of this post entirely; this is a descriptive
  CFBD-only piece.

## Pipeline work

Link logic goes in `R/link.R` from the start (AGENTS.md: contracts + TDD
with any data-touching code — not inline in the vignette):

- `link_coaches_picks(roster, picks, coaches, rule = c("last", "any"))`
  with testthat coverage (both rules, no-id picks, multi-coach seasons,
  transferred players) and a pointblank contract; pin join row counts.
- If promoted to a published table: add to the DuckDB bundle list and
  `inst/data-model.md`, and publish (run the refresh) **before** merging,
  per the gotcha on new tables.
- Later: succession-tree edges (seat changes) as a derived table.

## Vignette mechanics

- New `vignettes/YYYY-MM-DD-*.qmd` from `_post-template.qmd`;
  `title:` a single declarative sentence (subject first, takeaway second —
  draft one before writing); `description:` states the finding;
  `followups:` includes succession tree, apprenticeship source hunt,
  inherited-vs-recruited split, recruiting control.
- Every term defined in narrative (person-season, tenure year, attribution
  rule names); `knitr::kable` with captions for every table; Wilson
  intervals introduced in plain language before naming the method.
- Loading chunks `include: false`; no em dashes; verdict emojis (✅/❌)
  after expectation statements only; Discussion as `callout-important` +
  short caveats paragraph; named player examples from the recurring cast
  (Burrow, Cam Ward, Jordan Travis, Buechele, Kyle Allen) alongside coach
  examples, facts pinned by `stopifnot()`.
- Team colors via the shared viz theme. **The theme helper (TODO in
  AGENTS.md) is a separate prerequisite task, not built inside this post.**
- Author "AI directed by Nick Giangreco".

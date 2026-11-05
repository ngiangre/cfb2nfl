# Plan: open-issue roadmap (#44–#51)

Status: drafted 2026-11-05; first moves done 2026-11-05 (#46 calendar + selector,
B0, #49 in PRs). Close #11 (umbrella question list); its triage
comment maps every question to a shipped post or a child issue (#47–#51).

## What sets the order

1. **API quota.** A full refresh costs ~780 CFBD calls; the weekly scheduled
   `data-refresh.yaml` (Sunday 13:00 UTC) alone uses ~3,300 of the 5,000/month.
   Plays Phase 2 (#44, ~2,100 calls/season) cannot fit until #46 makes
   refreshes cheap. #44 and #45 also want #46's partition layout from the start.
2. **Publish before merge.** Any change to an ingested table (#45 combine, #48
   teams location) must be republished to `data-latest` before merging, which
   today means a full refresh. The analysis issues (#47, #49, #50, #51) read
   already-published data and cost **zero** calls.

## Budget: ~3,000 calls through 2026-11-12

| Item | Calls | Notes |
|---|---|---|
| Scheduled refresh, Sun 2026-11-08 | ~780 | In-season, so keep it; or skip once via disabling the cron if nothing needs fresh data |
| #46 development | <100/run | Test with `CFB2NFL_REFRESH_SEASONS=current` only; never a full-history run |
| #45 + #48 publish | ~780 | **One** branch-dispatched refresh for both; ~100 instead if #46 lands first |
| Track B (all analysis) | 0 | Track mode |
| **Deferred:** #44 Phase 1 (~360 + a refresh) and Phase 2 | — | After the budget resets and #46 is merged |
| Buffer for one failed/retried run | ~600+ | A failed refresh re-pulls everything; work out what it would re-pull before re-running |

Hard rule this week: **at most two full refreshes**, and no refresh re-run
without checking what it re-pulls.

## Track A: data infrastructure (one branch at a time)

- [ ] **A1 #46** season-scoped refresh (decision 0034, `R/seasons.R` done; ingest
  rewiring, partitions and workflows remain): decision record (revises 0017/0018,
  extends 0029), `current_season()` + per-source mapping, partitioned assets,
  `data-current.yaml`, `refresh-historical.R`, slim `site.yaml`.
- [ ] **A2 #48 + #45** in one branch so one publish covers both. #48 adds no
  calls (`location` is already in the `/teams` response); #45 is nflverse (no
  key). Code can be written alongside A1; only publish/merge waits.
- [ ] **A3 #44 Phase 1** (plays + dimensions, ~360 calls) into partitions.
  Deferred past this week.
- [ ] **A4 #44 Phase 2** play-stats backfill, one season/month, newest first,
  via `refresh-historical.R`.

## Track B: analysis posts (0 calls, start now, parallel to Track A)

- [x] **B0** shared player × game derived table (`game_player_stats` ↔
  `games`: opponent, pregame Elo, team games played) with a no-row-loss
  contract. Foundation for #47, #50, #51.
- [ ] **B1 (parallel)** #47 performance arcs + opponent adjustment; #50
  playing time; [x] #49 position stability (recruit link by school + class
  year raised HS coverage 61% to 98.6%, decision 0036);
  #51 part 1 career-ending proxy (`career` + `outcomes` only).
- [ ] **B2** #51 part 2 injured-vs-benched + "what the data cannot say" post.
  Needs #50's games-appeared measure; last, as it gathers the others' caveats.

## Parallelism notes

- Up to four concurrent branches: #46 plus #47 / #49 / #50 after B0.
- Expect small conflicts in `_targets.R`, `contract_gate`, `build_duckdb()`
  table list, `inst/data-model.md`, `NEWS.md`. Use worktrees; rebase on `main`
  right before each squash-merge.
- Don't overlap #46 with #44/#45 merges (asset layout changes under them), and
  don't start #51 part 2 before #50 merges.

## Next moves

1. #46: season-branch the ingests and partitioned assets (0034 checklist).
2. #47 and #50 in parallel on `player_game`; #51 part 1.
3. Open question: is the 2027 recruiting class available on CFBD yet (a
   one-call check errored on 2026-11-05)?

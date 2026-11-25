# 0052 — Roster seasons before a matched recruiting class are dropped

- **Status:** Accepted
- **Date:** 2026-11-25

## Context

CFBD's `/roster` sometimes lists a player in seasons before he enrolled
(issue #114): Joe Burrow at Ohio State in 2014, Ke'Shawn Vaughn at Illinois
in 2013 and 2014. The early rows are copies of the later record, but every
roster field (class year, jersey, hometown, weight) is static for all
87,151 multi-season players, so a copy cannot be told apart from a real
season. The candidate rules were measured against recruited players, whose
class is known:

- **Matching record:** flags every player, since all records match.
- **Id era** (a season earlier than the id block's typical first season):
  7 of the 27 known cases for 467 flags, or 19 of 27 for 2,719 flags.
- **Career span** (more than five seasons, six with 2020, trimming the
  early seasons with no stat line): fixes Burrow and Vaughn, but 354 of its
  362 flags among recruited players are real careers.
- **Draft age:** corrects only drafted players, so the clock would depend on
  the outcome.

## Decision

Drop only the seasons the data can prove are early: roster seasons before
the class on a name-matched recruiting record (decision 0013), via
`drop_pre_enrollment()` and the `roster_enrolled` target, which feeds
`career`, `model_table`, `outcomes`, `team_season` and `exits`. Two kinds of
player are left alone:

- **Recycled ids** (decision 0022): their early seasons belong to an
  earlier person on the same id. Dropping them would shorten the id's span
  and let 10 of them past the recycled-id exclusion.
- **Players with a stat line before their class** (9 players): they were
  in college then, so the recruiting class is what is wrong.

For unrecruited players like Burrow and Vaughn the copies stay in, and their
estimated clock starts early. This is a documented limit, not a fix (user
decision, 2026-11-25).

## Hypotheses / expectations

- A small drop with no effect on the clock: recruited players' clocks
  already come from their class.

## Consequences

- 26 roster seasons of 19 players leave `outcomes` and `career_summary`;
  eligible rows and the drafted and undrafted counts are unchanged. The
  published `roster` table keeps every season CFBD reports.
- `outcomes` and the DuckDB must be republished
  (`data-raw/refresh-outcomes.R --yes --publish`, 0 CFBD calls).

## Outcome / what we learned

_Filled in later._

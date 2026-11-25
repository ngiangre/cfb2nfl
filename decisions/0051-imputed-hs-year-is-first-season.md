# 0051 — An imputed high-school year is the first college season

- **Status:** Accepted
- **Date:** 2026-11-24
- **Supersedes:** the imputed high-school year of decision 0050 (first
  season minus one)

## Context

The eligibility clock in `outcomes` follows the NFL rule: a player can be
drafted, or sign undrafted, only once three NFL seasons have passed since
his high-school class graduated, so season `s` is eligible when
`(s + 1) - hs_grad_year >= 3`. `hs_grad_year` is the recruiting class when a
recruiting record is matched (decision 0013), and was otherwise imputed as
the first observed college season minus one, "a direct enrollee's
graduation year".

The matched recruits show that a CFBD recruiting class is the year a player
enrolls, not the year before: for 96% of them the class equals the first
roster season (3.6% enroll a year later; almost none earlier). Their first
eligible season is the third on a roster, as the rule gives a direct
enrollee. The imputed clock started one season earlier, so a player without
a matched record became eligible after his second roster season: 54,638 of
them had their first eligible season one year after their first roster
season, against 21,578 matched players two years after.

## Decision

Impute `hs_grad_year` as the first observed college season (the earlier of
the first roster and first stat season), the class of a direct enrollee, so
both clocks apply the rule the same way.

Not chosen:

- **Keep minus one.** It gives players without a recruiting match an extra
  early eligible season their matched peers do not have; that season can
  only end undrafted or continuing, which lowers their drafted shares and
  widens the matched/unmatched gap.
- **Also bound an NFL entrant's year by his entry** (`hs_grad_year <=
  entry_year - 3`, since anyone drafted or signed was eligible). It makes
  nearly every entrant eligible (18 left outside), but only entrants get the
  earlier clock: a non-entrant with the same unseen college years keeps the
  later one. In simulation that raised the season-1 drafted rate from 1.8%
  to 2.9% and fed the outcome into the clock, which is leakage for the
  draft forecast (F17).

## Hypotheses / expectations

- Draft-eligible players fall from 81,771 to about 59,400, nearly all of
  them players without a matched record whose second roster season stops
  counting as eligible.
- NFL entrants the clock never makes eligible rise from 580 to about 1,450:
  players whose earlier college years (junior college, a program the data
  does not cover, prep school) are unseen, so the first season they appear
  dates the clock too late. They stay a reported group, not an error to
  hide.
- Per-player NFL shares rise (by eligible season 3 the most drafted
  position group goes from 13% to 17% reaching the NFL), and signing
  undrafted passes being drafted from the second eligible season, not the
  third.

## Consequences

- `outcomes` must be rebuilt and republished
  (`data-raw/refresh-outcomes.R --yes --publish`, 0 CFBD calls), and the
  posts that read it re-rendered: their frozen output keeps the old clock
  until their source changes.
- `hs_year_imputed` still flags the estimate; the remaining error is now
  one-sided (too late, for players with unseen earlier seasons).

## Outcome / what we learned

_Filled in later._

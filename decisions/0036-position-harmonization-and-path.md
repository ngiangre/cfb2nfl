# 0036 — One position map and a per-player position path (issue #49)

- **Status:** Accepted
- **Date:** 2026-11-05

## Context

The position vocabularies disagree. Recruiting uses 247-style codes (`PRO`,
`APB`, `ATH`), CFBD roster and picks use roster codes and long-form names
(`Center`, `Defensive Edge`), and nflverse draft and roster files use PFR-style
codes. Issue #49 asks how often a player's position group holds from high
school to college to the NFL. Answering it needs one shared map, so that two
posts cannot group `EDGE` or `IOL` differently, and a derived table that chains
the three stages per college athlete id.

## Decision

- **One harmonization map** (`R/position.R`, `harmonize_position()`) takes a raw
  position from any of five named feeds to one of eleven reader-facing groups:
  Quarterback, Running back, Receiver, Tight end, Offensive line, Defensive
  line, Linebacker, Defensive back, Special teams, Athlete, and Position not
  recorded (blank or CFBD `?`). An unmapped raw value returns `NA` and is
  reported, never silently grouped.
- **A contract** (`contract_position_mapping()`, in `contract_gate`) asserts
  that every distinct raw value in all five feeds is in the map. A new code in
  any feed aborts the build.
- **A derived table** `position_path` (one row per non-reused college athlete
  id; decision 0021 recipe, bundled in DuckDB only) with:
  - **HS group** from the id-joined recruit only when a guard passes
    (`recruit_link_method()`, extending decision 0013), recorded in
    `hs_link_method`:
    1. `name`: names agree after `normalize_name()` (0013's guard).
    2. `name_variant`: a nickname / legal-name / typo variant (`name_variant()`)
       **and** a school + class year match.
    3. `school_year`: no college name on file **and** a school + class year
       match. School + class year means the recruit's `committed_to` is a
       roster team in the athlete's first two roster seasons, and the first
       roster season is 0 to 2 years after `hs_class`.
    A name that disagrees outright is never rescued by school alone: same
    surname, same school, same class is where CFBD's id collisions concentrate
    (brothers, common surnames).
  - **College groups** from roster positions, ignoring blanks: first, last,
    modal (most seasons, then most recent), and a flag for any in-college change.
  - **NFL group** from the nflverse draft position of the slot-linked pick
    (decision 0014). An id with more than one CFBD pick is not linked, and a
    null `gsis_id` is never joined (dplyr matches NA to NA, which fanned rows
    out before the fix).
- **Reused ids are excluded** from the universe (decision 0022).
- Groups for the position-group tables elsewhere (`position_group()` in
  `R/teams.R`, nine levels) are unchanged; this map is a separate, finer
  vocabulary for the path.

## Hypotheses / expectations

- Most linked high school recruits who played college football keep their group.
- Nearly every linked draftee keeps his college group in the NFL.
- Players change group between college seasons.

## Consequences

**Findings from building the table (track-mode build, contracts passing):**

- **Roster position is static per athlete.** Across the roster, no athlete id
  records two positions, so `college_changed` is always `FALSE` in the current
  data. The issue's premise that a player's position changes within college is
  not supported by this source, and the table cannot detect such a change. A
  per-season position source is an open question.
- **HS coverage was limited by names, not by mismatches.** The name guard alone
  links 22,768 of 37,099 recruits in the roster universe (61%). Roster rows
  carry no name, so 13,063 id-joined recruits had nothing to check against
  (the athlete never logged a stat line or was drafted).
- **Evaluation of the school + class year guard** (2026-11-05), scored against
  the name guard on the 24,036 pairs where both can be checked:
  - Recall: 22,732 of 22,768 exact-name links also pass school + year (99.8%).
  - Of the 1,147 pairs the name guard rejects but school + year passes, 768 are
    name variants (Chris / Christopher, typos, hyphenated or legal names), 16
    differ in surname (mostly name changes), and 363 share only a surname. A
    sample of the 363 is roughly 40% different people (common surnames,
    brothers on one roster) and 60% nicknames.
  - Estimated wrong-person rate among pairs passing school + year: about 150
    of 23,879, i.e. 0.6% (plausible range 0.4–1.5%).
  - The 121 pairs that fail both guards are clear collisions (different
    school, years apart).
  - Corroboration: the HS-to-college same-group rate is 84.7% for
    `school_year` links and 79.8% for `name` links; wrong-person links would
    pull the former down toward chance.
- **Result:** 36,577 of 37,099 recruits linked (98.6%): 22,768 `name`, 768
  `name_variant`, 13,041 `school_year`; about 80 expected wrong-person links.
  `contract_position_path()` enforces an HS coverage floor of 0.95 and that
  `hs_linked` agrees with `hs_link_method`.
- `link_recruiting()` (the model-feature path on the player-season backbone)
  is unchanged: every backbone row has a stat-line name, so only the
  `name_variant` tier would apply there. Adopting it is a separate change.
- **NFL slot-link coverage** is 3,732 linked draftees, and 3,733 of the 3,775
  2010+ universe picks match (98.9%). The contract floor is 0.97.
- **Undrafted players have no NFL position.** nflverse has no bridge to a CFBD
  athlete id except the name guard, which this decision does not extend to
  undrafted players. They are outside the NFL comparison.

**Follow-on:** a per-season position source; a name-guarded link for UDFA
positions; keep the recruit's hometown (`hometownInfo`, dropped by
`clean_recruiting()`) and check it against roster `home_city`/`home_state` to
cut the school + year error rate (needs a republish); the `name_variant` tier
in `link_recruiting()`.

## Outcome / what we learned

_Filled in later._

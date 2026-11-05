# 0036 — One position map and a per-player position path (issue #49)

- **Status:** Proposed
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
  - **HS group** only through `link_recruiting()`, so the name guard decides
    which recruit row is trusted (decision 0013). A recruit whose name does not
    agree gets no HS group.
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
- **HS coverage is limited by names.** 22,768 of 37,099 recruits in the
  roster universe link through the name guard (61%). Only about half of roster
  ids have a name in the stat lines, and recruits without a name cannot be
  guarded, so they stay unlinked rather than guessed.
- **NFL slot-link coverage** is 3,732 linked draftees, and 3,733 of the 3,775
  2010+ universe picks match (98.9%). The contract floor is 0.97.
- **Undrafted players have no NFL position.** nflverse has no bridge to a CFBD
  athlete id except the name guard, which this decision does not extend to
  undrafted players. They are outside the NFL comparison.

**Follow-on:** a per-season position source; a name-guarded link for UDFA
positions; recruit-to-college linkage that does not rely on names alone.

## Outcome / what we learned

_Filled in later._

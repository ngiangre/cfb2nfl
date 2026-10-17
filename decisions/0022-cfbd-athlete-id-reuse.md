# 0022 — CFBD athlete-id reuse: exclude >7-season ids from career/model populations

- **Status:** Accepted
- **Date:** 2026-10-16

## Context

Workstream A of `plans/audit-hygiene.md` found the `clean_roster` and
`career_summary` contracts failing in the audit log while the pipeline shipped
anyway. Diagnoses:

1. **`clean_roster`:** two rows carried a listed `weight` of 23 lb (one player,
   id `5227052`, Central Connecticut DL, 2025-2026) — a data-entry error the
   cleaner's `0 → NA` placeholder rule did not catch.
2. **`career_summary`:** 57 of 135,356 players showed 8-11 distinct roster
   seasons. Each such id carries exactly **one name**, but the spans are
   physically impossible (e.g. "Brett Johnson", DB, California, 2010-2023,
   identical height/jersey, no weight). Conclusion: **CFBD recycles athlete
   ids across distinct individuals** — the id is a stable key within a window
   (decision 0003's join premise holds for normal careers) but not across
   ~decade spans. Scope: 131 of 135,356 roster players (0.1%) have a
   first-to-last-season span > 7; 124 of them also appear in `player_stats`,
   so they reach the model backbone. Not era-concentrated.

## Decision

- **Weight:** `clean_roster()` coerces any listed `weight` outside the
  plausible 100-500 lb range to `NA` (not just `0`), matching the roster
  contract's range. The next-lowest real weight in the data is 110 lb, so no
  legitimate value is lost.
- **Id reuse:** players whose roster span exceeds 7 seasons (`reused_ids()`,
  new helper) are treated as **multiple real people sharing an id** and are
  **excluded from the career and model populations**:
  - `career_summary(roster, max_span = 7L)` drops them before collapsing, so
    its contract (1-7 seasons) holds by construction.
  - A `ps_pop` target filters `ps_draft` to non-reused ids before
    `add_change_features()` / `add_roster_weight()`, so the model population
    is clean too. `link_drafted` and its contract still validate on the
    unfiltered table.

## Alternatives considered

- **Split reused ids into multiple identities** by gaps/attribute breaks:
  recovers ~0.1% of roster rows at the cost of a heuristic, error-prone
  identity-resolution step. Deferred — revisit only if a downstream question
  specifically needs those players.
- **Keep and flag** (`reused_id` column, relaxed contract): preserves rows but
  pollutes career features (11 "seasons" for one person) and weakens the
  grain guarantees everywhere the id is a key.
- **Decide later, contract stays red:** rejected — the plan's definition of
  done requires every contract to pass or block the build.

## Consequences

- The athlete-id namespace is now understood to be *stable per individual over
  plausible career windows, unreliable across >7-season spans*; joins keep
  working because populations exclude the pathological ids.
- `reused_ids()` and the `max_span` argument document the rule in code; the
  `career_summary` dictionary notes the exclusion.
- Enforcement of contracts on build failure remains open (audit-hygiene
  workstream A, first item).

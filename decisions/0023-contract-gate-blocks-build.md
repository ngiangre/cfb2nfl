# 0023 — a failing data contract blocks the build

- **Status:** Accepted
- **Date:** 2026-10-16

## Context

The audit log recorded `contract_passed = FALSE` for `clean_roster` and
`career_summary` while the pipeline completed and assets shipped
(`plans/audit-hygiene.md`, finding 1): contracts were *recorded*, not
*enforced* — the "fail fast" promise in the data-contracts design (decision
0005) was not what actually ran. Each contract's outcome lives in an `ok_*`
target (`pointblank::all_passed(..., stop_on_fail = FALSE)`), consumed only by
the audit log.

## Decision

Enforce at a dedicated **gate target**, not inside each contract call:

- New `assert_contracts_pass(results)` in `R/contracts.R`: takes the named
  pass/fail results, errors listing every `FALSE` (steps with no contract —
  `NA` — are not failures; they are tracked for workstream C of the hygiene
  plan).
- New `contract_gate` target in `_targets.R` depends on all 15 `ok_*` targets
  and calls the assertion. Because `tar_make()` defaults to
  `error = "stop"`, any `FALSE` aborts the whole run — locally, in
  `data-refresh.yaml`, and in `site.yaml` track mode — so no failing build is
  published.
- The gate stays a **separate target** from the audit log: a failing run
  aborts before the audit rows are written, and the gate's error message
  names the failing tables directly; the last stored `audit_log` (with the
  `FALSE` rows) plus the error message together diagnose the run.

`stop_on_fail = TRUE` in the individual `contract_*()` calls still applies
for direct/interactive use, but the pipeline deliberately keeps it `FALSE`
and lets the gate decide — that keeps all 15 outcomes recorded in one place
and gives one coherent error instead of 15 possible aborts.

## Alternatives considered

- **`stop_on_fail = TRUE` inside each `ok_*` target:** the first failing
  contract aborts immediately, so later contracts never evaluate — the audit
  can never show the full picture of a bad refresh.
- **Assert inside the `audit_log` target:** one less target, but hides
  enforcement inside a reporting step and leaves the gate implicit in the DAG.
- **`tar_validate()`:** native validation targets exist, but they only run
  when something downstream needs them; an explicit `contract_gate` with
  named entries is visible in the graph and produces a better error message.

## Consequences

- A failing contract is now a build failure everywhere the pipeline runs;
  publishing (`piggyback` upload) only happens after a green `tar_make()`.
- `contract_gate` is also the checklist of which tables have contracts; the
  `NA` case (no contract yet) still passes the gate by design until
  audit-hygiene workstream C closes the coverage gaps.

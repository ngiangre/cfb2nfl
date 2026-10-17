# 0028 — Retry with backoff on CFBD ingest requests

- **Status:** Accepted
- **Date:** 2026-10-17

## Context

Three consecutive `data-refresh` CI runs failed with `HTTP 503` mid-ingest
(roster, then recruiting endpoints), while single local calls to the same API
succeeded minutes later. The refresh makes ~60+ back-to-back CFBD calls (one
or more per season across 16 seasons, plus recruiting/teams/coaches/picks),
and GitHub Actions runners sit in shared datacenter IP ranges that CFBD
appears to throttle harder than a residential IP. A single transient 503
therefore failed the entire weekly refresh.

## Decision

Centralize retry in `cfbd_get()` via an internal `cfbd_request()` builder:
every CFBD ingest call gets `httr2::req_retry()` with `max_tries = 5`,
`max_seconds = 120`, exponential backoff, and an `is_transient` predicate
covering 429/500/502/503/504. A transient 503 now costs a ~1s wait instead of
the run; the backoff also paces the burst, which is the proximate trigger.

Alternatives: sleeping between season requests (slower, doesn't cover
mid-run outages), retrying in the ingest functions individually (duplicated
logic), or keeping refresh local-only (works — the fallback used when CI
fails — but doesn't survive a local blip either).

## Hypotheses / expectations

- CI refreshes survive short CFBD outages / rate-limit windows.
- No behavioral change to the data: retries only re-issue idempotent GETs.

## Consequences

- A fully-down CFBD still fails the run after ~2 min of retries per call
  (bounded by `max_seconds`), preserving fail-fast semantics.
- Retry is invisible to track mode (no API calls there).

## Outcome / what we learned

_Filled in later._

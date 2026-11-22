# Goals: what the site is for

The top of the traceability chain **goal → feature → task**
([README.md](README.md)). Each goal restates part of [VISION.md](../VISION.md)
as an outcome a persona ([personas.md](personas.md)) can feel, with signals
that tell us whether it is being met. **Constraints** are guardrails every
feature respects; a feature can exist to protect one. Goals and constraints
change rarely; change them with a decision record, not a quiet edit.

Status: agreed 2026-11-22 (interview with the user).

## Priority

Work is ordered **G1, G3, G4, G2**: keep answering questions, make the
answers explorable, follow players into the NFL, then build the forecast.
The constraints apply to all of them and are not ranked.

GitHub issues carry one label per goal or constraint they serve:
`goal:G1` … `goal:G4`, `constraint:trust`, `constraint:budget`.

## G1 · Answer the project's questions with evidence

- **Serves:** P1 (P2 for method)
- **Outcome:** each college-side question in VISION §1 (what matters for
  going pro, does the head coach matter, per-position draft odds) has a dated
  post that answers it, or says plainly what the data cannot answer.
- **Signals:** every open question in a post's `followups:` is answered by a
  later feature or tracked as a feature in [features.md](features.md); P1
  can see each question's status.
- **Not this goal:** a tour of everything the data contains (posts are
  snapshots, AGENTS.md "Blog style").

## G3 · Let fans go from a question to an answer to the next question

- **Serves:** P1
- **Outcome:** a fan reaches a relevant chart or number in a click or two,
  probes it at finer grain (their team, player, season), and can pose a new
  question, on a phone as well as a desktop.
- **Signals:** fan-facing pages pass the `site-personas` P1 walkthrough;
  every Results section has an exploratory figure; the Explorer covers the
  season in progress; jargon does not leak onto fan pages.
- **Not this goal:** rewriting the technical pages for fans (they serve P2);
  the querychat app (deferred, 2026-11-22).

## G4 · Follow players into the NFL

- **Serves:** P1, P2
- **Outcome:** for players who reach the NFL, drafted or not, show what they
  go on to do: how long they last, the statistics they put up, and whether
  they thrive or fizzle, by position and by college path (VISION §1).
- **Signals:** drafted and undrafted players are both covered; recent
  classes are marked right-censored; linemen and other players without box
  scores are handled explicitly; NFL data stays an outcome, never an
  in-career model input (decision 0014).
- **Not this goal:** NFL team analysis, or NFL players who never played
  college football in the data.

## G2 · Forecast draft outcomes honestly

- **Serves:** P1 (the "percent chance" number), P2 (the evaluation)
- **Outcome:** after each season, a per-position probability of being
  drafted, from information available at the time, reported with
  uncertainty; explanatory and predictive answers side by side (VISION §2,
  §6).
- **Signals:** out-of-time validation only (a model never sees data on or
  after the class it predicts); calibration and held-out performance
  published; NFL outcomes and combine data stay off the in-career input path.
- **Not this goal:** in-season weekly projections.

## C1 · Every number is trustworthy and reproducible (`constraint:trust`)

- Contracts gate the build (decision 0023); post numbers are inline
  variables and setup code is visible (decision 0040); tables are documented
  in `inst/dict` and `inst/data-model.md`; the DuckDB asset is downloadable;
  the data model stays lean (decision 0041).

## C2 · Stay current within the API budget (`constraint:budget`)

- The scheduled season-scoped refresh keeps the site on the season in
  progress (decision 0034); a new ingest states its CFBD call cost before it
  is built, including any existing refresh path it runs; no full refresh
  runs without a budget check.

## Non-goals (whole site)

- An installable package (decision 0042).
- Data the pipeline cannot source or license (assistant coaches start as a
  feasibility post first, VISION §3).

# Personas: who the site serves

The people cfb2nfl is built for, drawn from [VISION.md](../VISION.md) §10 and
the user critiques recorded in [AGENTS.md](../AGENTS.md). Every goal in
[goals.md](goals.md) and every feature in [features.md](features.md) names
the persona(s) it serves. When the two personas pull in different
directions, **P1 wins ties**: fans get plain language up front, and P2 gets
the code fold and the technical pages.

Use the `site-personas` skill to apply these cards (walkthroughs, reviews).
Edit this file when the audience changes; it is the single source of truth.

## P1 · The invested fan (primary reader)

- **Who:** follows college football closely, knows positions, schemes,
  conferences and the draft cycle. Not a coder or a statistician. Includes
  the project's collaborator (VISION §11), who brings questions but not code.
- **Arrives with:** a question about a player or a pattern. "Do transfers get
  drafted more?" "Does a coaching change hurt a player's odds?" "What are a
  linebacker's chances after a big season?" "How did Cam Ward go from FCS to
  first overall?" Or a new question to add to the list.
- **Needs:**
  - a plain-language answer with a chart and a number in a click or two;
  - a way to poke at it (their team, their player, their season) and pose
    the next question, on a phone as well as a desktop;
  - to see where each question stands (answered, in progress, or not
    answerable with this data and why), and that one post's follow-ups shape
    the next.
- **Stalls on:** column names and codes (`outcome_drafted_d`), pipeline words
  (targets, contracts, schema), methods named before they are explained,
  verdict-style overclaiming, walls of prose, tables that repeat a figure, a
  question that silently disappears.
- **Surfaces:** Home, About, Explore hub, Explorer, Blog index and posts
  (including each post's `followups:`), GitHub issues.
- **Success looks like:** "I found the answer, I believe it, and I can see
  or try the next question."

## P2 · The coder and researcher (secondary reader)

- **Who:** loves football and data. Writes R (or similar) and wants to reuse
  the data or extend an analysis, or studies sports analytics and wants to
  check the study design and cite the result.
- **Arrives with:** "How is 'draft eligible' defined?" "Can I query the
  DuckDB myself?" "Which function builds this table, and how is it tested?"
  "Was the forecast validated out of time, and how well calibrated is it?"
- **Needs:**
  - visible, reproducible code behind every exhibit, and a downloadable
    database with documented tables and join keys;
  - the population, outcome and validation scheme stated precisely, with
    uncertainty and honest limits on what the data can say;
  - stable, citable pages (dated posts, decision records, a citation entry).
- **Stalls on:** hidden setup code, undocumented joins, hardcoded numbers,
  missing caveats or denominators, results without validation, functions
  with no reference page.
- **Surfaces:** Data, Pipeline, Reference, post code folds, decision records,
  Citation, the `data-latest` release assets, `inst/data-model.md`.
- **Success looks like:** "I reproduced the number, I trust the method, and
  I could build on it or cite it."

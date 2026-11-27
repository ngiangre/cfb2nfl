# 0054 — Figure cards replace dated posts

- **Status:** Accepted
- **Date:** 2026-11-27

## Context

After two months and 16 dated posts (decision 0015), written in a
research-article register (decision 0025) with visible code and computed
numbers (decision 0040), the figures were what readers came back to. The
format around them was not:

- **Prose.** Rule after rule was added (0025, 0040, the 2026-10-24
  critiques, `check_post_style()`, the `vignette-reviewer` agent), and the
  text still read as machine-written and hard to follow.
- **Titles.** One long declarative sentence per post did not say what was
  investigated or shown, so the index could not be scanned.
- **Overlap.** About 113 helpers were redefined inline across posts, and the
  same populations and joins were recomputed post by post.
- **Navigation.** A flat, date-ordered table could not answer "every
  quarterback figure" or "everything about draft chance by position".

Issue #127 and feature F25 proposed a figure wall. The pilot (#133, PR #141)
moved the three draft-outcome posts to 14 cards and graduated one.

## Decision

**The unit of Investigations is a figure card**: one question answered by
one figure, one file `vignettes/card-<id>.qmd`. The id is the card's
permanent URL. Dated posts are no longer written; the remaining posts are
migrated in batches and then retired.

- **The card.**
  - Its front matter is the registry: `title` (the question, a fan's
    question ending in `?`), `image` (`card-thumbs/<id>.png`), `image-alt`,
    `categories` (tags), `status` (`sketch`, `investigation`, `graduated`),
    `graduated_to`, `terms` and `followups`.
  - There is no narrative prose. The page shows the visible setup code
    (reading `cfb2nfl.duckdb`, carried over from 0040), the figure as an
    interactive `ggiraph` view, any finer-grain figure, a table only where
    it adds a different summary, and the footer.
- **The figure explains itself.**
  - The title says what is shown and the subtitle says who, when and how to
    read it. The takeaway is carried by highlighting, not words.
  - Numbers in figure text are computed from the data. A typed number in a
    title or subtitle fails the check (0040's rule, moved from prose to
    figure text). Units are written out ("per hundred").
  - The thumbnail is drawn with `theme_card()`; `card_thumbnail()` wraps
    long titles to the tile.
- **One colour per meaning across every card:** drafted green `#1B9E77`,
  undrafted purple `#7570B3`, quarterbacks orange `#D95F02`, other
  highlights dark grey, and pale greys for endings without the NFL.
  Position groups use `position_palette()` and nothing else. A stock
  palette that reuses those colours is a defect.
- **Definitions live in one glossary,** `inst/cards/terms.yml`. A card lists
  the keys it relies on, `card_footer()` prints their definitions, and the
  check rejects an unknown key. This replaces 0025's definitions tables and
  the 2026-10-24 "define every term in the narrative" critique. When two
  analyses count different things (eligible seasons and players), a
  glossary term reconciles them rather than forcing one vocabulary.
- **Tags come only from an approved vocabulary.**
  - Facets: topic, position, population and figure type, in
    `inst/cards/tags.yml`. Questions come from `inst/cards/questions.yml`,
    where each question has a status and a reason when it can't be
    answered.
  - A new tag is added to the registry in the PR that first uses it, so
    approving the PR approves the tag.
  - "Position: All positions" marks pooled cards and "Position: By position
    group" marks split ones. A question tag goes only on cards that answer
    it.
- **The Investigations page is a Quarto listing.** It shows the question, a
  lazy-loaded thumbnail, a status pill and the tags, with search (alt text
  included) and a tag filter. A `#category=<tag>` URL opens it filtered.
- **Freshness.**
  - The sidecar next to each committed thumbnail hashes the card's R code
    and the source tokens of the `R/` functions that shape the figure
    (comments, layout and the card machinery excluded), parsed from the
    files so CI needs no package load.
  - A changed card or function fails the check. A newer data release is a
    note, reported by the site build. The release date comes from a stamp
    written on download, not the DuckDB `_meta` timestamp, which dates each
    rebuild.
- **Graduation.**
  - When an idea becomes a standing answer, its builder moves to `R/` with
    a test, and a destination renders it with a link back: Explorer for
    something a fan probes, Analysis ("What we know") for a settled answer,
    Data, Home or About for coverage or a headline.
  - The card records `graduated_to:`. The user decides graduation, one
    issue each.
- **Migration.**
  - `inst/cards/migration.yml` records every section of every post as a
    card, a merge, or a drop with a reason. A card listed there is
    published, so renaming or deleting it needs an `aliases:` entry.
  - A retired post's URL redirects (`aliases:`) to its main card.
- **Checks.** `check_card_style()` replaces `check_post_style()`. It runs in
  the `post-style.yaml` CI job, in `devtools::test()` and in the edit hook.
  The `vignette-reviewer` agent reviews cards only, judging the thumbnail
  alone first.

**Alternatives considered:**
- **Topic notebooks** (one growing page per theme). Rejected because the
  page would still invite prose, and a figure would have no address of its
  own.
- **A separate `cards.yml` registry.** Rejected because it would drift from
  the cards; front matter is the registry.
- **An OJS page with combined (AND) filters.** Deferred: Quarto's listing,
  with search plus one tag at a time, is enough until shown otherwise.
- **File modification times for freshness.** Rejected because a checkout
  resets them.

## Supersedes and amends

- **0015 (blog post conventions): superseded.** Dated files, `description:`
  and the post template are replaced by cards. Freezing (`freeze: auto` and
  committed caches) still applies to every page.
- **0025 (writing style): superseded.** The research-article register,
  assertion headings, expectation verdicts and the post template no longer
  apply. These carry over to cards: no em dashes, no pie charts, captioned
  tables with reader-facing headers, and no pipeline internals on the page.
- **0040 (visible setup, no `stopifnot()` pins): amended.** Setup code stays
  visible and numbers stay computed. "Every number in the prose is an
  inline variable" becomes "every number in figure text is computed",
  because cards carry no prose.
- **`goals.md` signals.** G1's Outcome becomes "has a card or an Analysis
  entry", and G3's signal becomes "every card has an interactive figure on
  its page", as recorded there.

## Hypotheses / expectations

- A fan finds every figure on a topic or position from one page with a
  click, and a card's thumbnail reads without its page.
- With no prose to write, the machine-written-text problem goes away rather
  than being rule-managed.
- Shared builders make a card mostly a call plus labels, and duplicated
  analyses become visible on the wall instead of hiding across posts. The
  pilot found and merged one such pair.

## Consequences

- **Migration work.** The 13 remaining posts need migration issues, one per
  batch, each with `Feature: F25`. Until each batch lands its post stays up,
  listed under the wall, and is no longer style-checked.
- **A first render is local.** A card's thumbnail must be rendered locally
  and committed: the site build copies `vignettes/` before any card renders.
- **Render time.** About 8 s per card from scratch; with freeze, CI re-runs
  only changed cards.
- **A rule for card code.** A card variable must never share a name
  with a data column: inside `dplyr` verbs the column wins silently. The
  pilot's rookie-games card computed 68% instead of 51.5% that way. Use a
  distinct name or `.env$`.
- **What the pilot changed relative to its posts:**
  - rookie games count only completed rookie seasons;
  - the first era of the entry-chance split ends before undrafted signings
    are recorded;
  - one KR season moves to special teams.

## Outcome / what we learned

_Filled in later._

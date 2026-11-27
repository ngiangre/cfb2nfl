# 0015 — Blog post naming conventions and build robustness

- **Status:** Superseded by 0054 (figure cards); freezing still applies
- **Date:** 2026-08-27

## Context

VISION (§7) and decision 0006 commit us to a blog on the altdoc/Quarto site.
This is a long project; we expect to write many posts over time. The standing
risk is **build rot**: a post authored today hard-codes players, seasons, and
values, then silently breaks (errors or reads as wrong) when the `data-latest`
release refreshes — right-censored careers gain seasons, joins shift, ids move.
We want to fix conventions *before* the first post so the blog stays buildable
as it grows, without re-litigating each post.

Two facts about the current setup shape the decision:

- **`vignettes/` is `.Rbuildignore`d** (`^vignettes$`, decision 0002), so blog
  posts are not real package vignettes as far as `R CMD check` is concerned —
  altdoc renders them directly. We are free of CRAN vignette naming rules.
- **`_freeze/` is committed** and the site runs `execute: freeze: auto`
  (decision 0006). A post's outputs are cached; it only re-executes when its own
  `.qmd` changes, not when data underneath it refreshes.

## Decision

**Posts are frozen, point-in-time artifacts.** Structural site pages
(`about`, `data`, `pipeline`, `analysis`, `explore`) stay "living"; dated posts
are append-only and pinned.

**Naming.** Blog posts live at `vignettes/YYYY-MM-DD-slug.qmd` (kebab-case slug,
e.g. `2026-08-27-buechele-allen.qmd`). Date prefix makes the sidebar
alphabetical order chronological and gives a stable, permanent URL. A published
post's filename is never changed (URL permanence). Structural pages keep their
singular-noun names, so posts are visually distinct from pages.

**Build-robustness standards, encoded in `vignettes/_post-template.qmd`:**

1. **Freeze the post** (`freeze: true` in the post's YAML) and commit its
   `_freeze/` entry. A data refresh never re-executes a published post; to
   intentionally refresh one, edit it (or delete its freeze entry) deliberately.
2. **Stamp the data vintage** in every post (retrieval date / `data-latest`
   release), so evolving, right-censored numbers read as context, not errors.
3. **Key on athlete id, never name**, and declare the ids in a registry block at
   the top of the post (respects the recruiting-id collision, decision 0013).
4. **Access data via tested package functions and `tar_read()`**, not ad-hoc
   parquet reads. A silent join change should fail a unit test, not a reader.
5. **Guard chunks** with cheap assertions (`stopifnot(nrow(x) > 0)`) so a broken
   query errors while authoring, before the post is frozen.
6. **CI site build on PRs** (`site.yaml`) catches an edited/unfrozen post that
   errors before it reaches `main`.

The template file is underscore-prefixed so Quarto does not render it as a page.

Alternatives rejected: undated slug-only filenames (no chronology, ordering
churn); a separate `vignettes/posts/` subdir (altdoc's flat
`$ALTDOC_VIGNETTE_BLOCK` doesn't group by subdir today — revisit if the flat
list gets unwieldy); relying on `freeze: auto` alone without `freeze: true`
(auto still re-runs a post whenever its `.qmd` is touched for any reason).

## Hypotheses / expectations

- Freezing + committed `_freeze/` means old posts survive data refreshes
  untouched; the blog build time and failure surface grow with *edits*, not with
  the number of posts.
- Date-prefixed filenames give chronological ordering "for free" under altdoc's
  alphabetical vignette block, deferring any custom listing/sidebar work.
- Routing data access through tested `R/` helpers turns silent join drift into a
  loud test failure.

## Consequences

- Adds `vignettes/_post-template.qmd`; every new post starts from it.
- Commits us to keeping `_freeze/` tracked and to reviewing post diffs (a post
  edit re-executes and can surface data drift — intended).
- Reusable post logic (e.g. a `player_trajectory()` helper) should land in `R/`
  with tests rather than living inline in posts.
- Open item deferred: if the flat vignette sidebar becomes cluttered, introduce
  a curated section or Quarto listing page (new decision).

## Outcome / what we learned

_Filled in later._

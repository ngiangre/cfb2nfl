<div class="hero" align="center">

**CFB2NFL**

*What makes a college football player go pro?*

Every year, a small fraction of college football players hear their name called
in the NFL Draft. This project asks *why* — and how early we could have seen it
coming.

<img src="man/figures/hero/hero.gif" alt="Rotating career timelines of the first five picks of the 2024 and 2025 NFL drafts: each player's team by season, college through the NFL" width="360">

[About](vignettes/about.qmd) · [Explore](vignettes/explore.qmd) · [Blog](vignettes/blog.qmd)

</div>

> [!WARNING]
> **Work in progress.** This project is under active development and will
> change frequently and without notice — data, code, methods, and conclusions
> may all shift. Nothing here should be treated as stable or final.

## The idea

We're two football fans trying to untangle which parts of a player's college
experience actually matter for reaching the NFL. Some of the questions we keep
coming back to:

- What is it about a player's college career that predicts turning pro?
- Does coaching matter — the head coach, and eventually coordinators, position
  coaches, even strength & conditioning staff?
- If we take a snapshot of a player after each season, what are their chances of
  being drafted, given their position?
- Once they're drafted, what do they go on to do in the NFL — the stats they put
  up, and how long they stick around?

## What we want to do

Our plan is to start simple and get more ambitious over time:

1. **Describe** who gets drafted — the teams, positions, and hometowns they come
   from — and what they go on to do once they reach the NFL.
2. **Explore** lots of possible connections between college performance,
   coaching, and the draft.
3. **Predict** a player's chance of being drafted, honestly testing whether our
   models can *forecast* future draft classes rather than just fit the past.
4. **Explain** what we find, so the results are more than a black box.

We care about two kinds of answers: understanding *why* something matters, and
seeing *how well* we can predict it.

## Who this is for

Anyone who loves college football and is curious about what the numbers say —
whether or not you write code. Findings will be shared as a website with plain
articles, deeper analysis, and interactive visualizations.

## Where to start

- **[About](vignettes/about.qmd)** — the short version of what we're asking and why.
- **[Explore](vignettes/explore.qmd)** — poke at the data yourself with
  interactive charts, and take your own questions for a spin.
- **[Analysis](vignettes/analysis.qmd)** — the write-ups, as they take shape.

Curious how the numbers are built and checked? The
**[Data](vignettes/data.qmd)** and **[Pipeline](vignettes/pipeline.qmd)** pages
are for readers who want to look under the hood.

## The data

We build on the excellent [College Football Data](https://collegefootballdata.com)
API — historical NFL draft picks, player season statistics, and coaching records
— and on [nflverse](https://nflverse.nflreadr.com/) for what happens *after* the
draft: NFL rosters, statistics, and career longevity. We expect to fold in other
public sources over time.

## Status

Early days. This is a personal project and a work in progress; the goals above
are the north star, and the "how" is deliberately still open as we learn. If you
want the full working plan behind the scenes, see [VISION.md](VISION.md).

---
name: site-personas
description: >-
  Use when deciding who a cfb2nfl feature, page, post, chart or explorer view
  is for, when designing or writing anything a site visitor sees, when
  reviewing whether a page works for its reader, or when writing a feature
  card's Personas line or acceptance criteria.
---

# site-personas

The site serves two people, defined in
[`product/personas.md`](../../../product/personas.md) (the single source of
truth; read it, do not paraphrase from memory):

| ID | Persona | One-line need |
|----|---------|---------------|
| P1 | The invested fan (primary; includes the question collaborator) | Question → plain answer → poke at it → next question, on a phone; see where every question stands |
| P2 | The coder and researcher | See, rerun, trust and cite every number |

**P1 wins ties.** Fans get plain language up front; P2 gets the code fold,
the technical pages and the decision records. Neither is traded away.

## Walkthrough: test a surface as a persona

1. **Pick the persona** the page or feature names. Fan pages, the Explorer
   and the blog index are P1; Data/Pipeline/Reference and code folds are P2.
   Posts serve both: prose for P1, code and caveats for P2.
2. **Write three questions** that persona would arrive with, in their own
   words (use the "Arrives with" examples as a pattern, and prefer the
   recurring cast: Burrow, Cam Ward, Jordan Travis, Buechele, Kyle Allen).
3. **Walk the path** from Home to an answer for each question. Count clicks.
   Note every spot that matches the persona's "Stalls on" list.
4. **Check the success line.** Could this persona say their "Success looks
   like" sentence? If not, that is the finding.
5. **Report** each stall as `surface · what the persona hits · smallest fix`.

## Writing acceptance criteria from a persona

Phrase criteria as what the persona can do or see:

- ✅ "P1 can find their school's draft count from the Explorer in two taps"
- ✅ "P2 can rerun the forecast's out-of-time validation from the post's
  code fold"
- ❌ "Add a school filter" (an activity, not an outcome)

## Boundaries

- Edits to fan-facing pages go through `fan-experience-improver`; figure
  cards through the `vignette-reviewer` agent. This skill tells them who they are
  writing for.
- A surface that serves neither persona, or a reader the personas do not
  describe: say so and ask the user whether `personas.md` should change.

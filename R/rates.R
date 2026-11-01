# Rates for small groups (Post 2 of plans/conferences-teams.md): a school
# with 1 draftee from 3 players should not outrank Alabama, so raw rates are
# pulled toward their group's rate in proportion to how little data they have.

#' Shrink rates toward their group rate (beta-binomial empirical Bayes)
#'
#' Estimates, within each group, how much true rates vary between units
#' beyond binomial sampling noise (method of moments), then returns each
#' unit's posterior mean `(x + k * m) / (n + k)`, where `m` is the group's
#' pooled rate and `k` the prior strength. Units with few trials move most of
#' the way to `m`; units with many barely move. If the units vary no more
#' than chance alone predicts, every unit gets `m`.
#'
#' @param x Integer successes per unit (e.g. players drafted).
#' @param n Integer trials per unit (e.g. eligible players), `x <= n`.
#' @param group Optional grouping vector (e.g. conference); shrinkage is
#'   toward each group's own pooled rate. `NULL` pools everything.
#' @return Numeric vector of shrunk rates, `NA` where `n == 0`.
#' @export
shrink_rate <- function(x, n, group = NULL) {
  stopifnot(length(x) == length(n), all(x <= n, na.rm = TRUE))
  if (is.null(group)) {
    group <- rep(1L, length(x))
  }
  out <- rep(NA_real_, length(x))
  for (g in unique(group)) {
    i <- which(group == g & n > 0)
    if (length(i) == 0L) {
      next
    }
    m <- sum(x[i]) / sum(n[i])
    p <- x[i] / n[i]
    # Between-unit variance of raw rates minus the share expected from
    # binomial noise alone is the true-rate variance tau2.
    # Trial-weighted, so binomial noise contributes m(1-m) per unit / total n.
    s2 <- stats::weighted.mean((p - m)^2, n[i])
    noise <- m * (1 - m) * length(i) / sum(n[i])
    tau2 <- s2 - noise
    out[i] <- if (length(i) < 2L || tau2 <= 0 || m %in% c(0, 1)) {
      m
    } else {
      k <- max(m * (1 - m) / tau2 - 1, 0)
      (x[i] + k * m) / (n[i] + k)
    }
  }
  out
}

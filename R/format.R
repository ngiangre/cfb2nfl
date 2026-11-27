# Number and text formatting shared by posts and cards (feature F25). Each
# was copied inline into most posts; one tested copy here replaces them.

#' Format a number with thousands separators
#'
#' @param x Numbers (or numeric strings).
#' @param digits Digits after the decimal point.
#' @return A character vector, e.g. `"1,234"`.
#' @export
fmt <- function(x, digits = 0) {
  formatC(as.numeric(x), big.mark = ",", format = "f", digits = digits)
}

#' Format a share as a percent
#'
#' @param x Shares in `[0, 1]`.
#' @param digits Digits after the decimal point.
#' @return A character vector, e.g. `"12.3%"`.
#' @export
pct <- function(x, digits = 1) {
  sprintf("%.*f%%", digits, 100 * x)
}

#' Wilson interval for a binomial share
#'
#' The range the true rate plausibly occupies given `x` successes in `n`
#' trials; unlike the plain normal interval it stays inside `[0, 1]` and
#' behaves at small `n` and at shares near 0 or 1.
#'
#' @param x Successes.
#' @param n Trials.
#' @param z Normal quantile (1.96 for a 95% interval).
#' @return A named numeric vector `c(lo, hi)`.
#' @export
wilson <- function(x, n, z = 1.96) {
  p <- x / n
  d <- 1 + z^2 / n
  c <- (p + z^2 / (2 * n)) / d
  h <- (z / d) * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))
  c(lo = pmax(0, c - h), hi = pmin(1, c + h))
}

#' Join words as an English list
#'
#' @param x A character vector.
#' @return One string, e.g. `"a, b and c"`.
#' @export
and_join <- function(x) {
  sub(", ([^,]*)$", " and \\1", paste(x, collapse = ", "))
}

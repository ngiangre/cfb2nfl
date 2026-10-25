# Resolve the project root when rendering vignettes (decision 0006). Under
# altdoc, docs render in a temp dir and CFB2NFL_ROOT points at the checkout;
# for a direct `quarto preview` the env var is unset, so fall back to walking
# up from the working directory to the nearest `_targets` store.

#' Resolve the pipeline root for rendering vignettes
#'
#' Returns `CFB2NFL_ROOT` when set (the altdoc/site build path); otherwise
#' walks up from the working directory to the nearest directory containing a
#' `_targets` store, so a direct `quarto preview` of a vignette resolves
#' `tar_read()` too. Returns an empty string if no store is found upstream —
#' callers skip the `knitr::opts_knit$set(root.dir = ...)` in that case.
#'
#' @return A directory path, or `""` when no root can be found.
#' @export
cfb2nfl_root <- function() {
  root <- Sys.getenv("CFB2NFL_ROOT")
  if (nzchar(root)) {
    return(root)
  }
  dir <- getwd()
  while (!file.exists(file.path(dir, "_targets")) && dirname(dir) != dir) {
    dir <- dirname(dir)
  }
  if (file.exists(file.path(dir, "_targets"))) dir else ""
}

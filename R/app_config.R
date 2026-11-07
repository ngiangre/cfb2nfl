# App configuration helpers, following the golem convention (cf. golem's
# shinyexample R/app_config.R). `app_sys()` resolves files under `inst/`.

#' Access files in the current app
#'
#' @param ... character vectors, specifying subdirectory and file(s)
#' within your package. The default, none, returns the root of the app.
#' @noRd
app_sys <- function(...) {
  # The repo is never installed (decision 0042): read inst/ from the checkout
  # when running from the project root (tar_make(), the site build), so a stale
  # installed copy can never shadow it. Elsewhere (tests, load_all() from a
  # subdirectory) pkgload's system.file() shim points at the checkout too.
  p <- file.path(getwd(), "inst", ...)
  if (!file.exists(p)) {
    p <- system.file(..., package = "cfb2nfl")
  }
  p
}

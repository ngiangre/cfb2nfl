# App configuration helpers, following the golem convention (cf. golem's
# shinyexample R/app_config.R). `app_sys()` resolves files shipped with the
# installed package.

#' Access files in the current app
#'
#' @param ... character vectors, specifying subdirectory and file(s)
#' within your package. The default, none, returns the root of the app.
#' @noRd
app_sys <- function(...) {
  # Under pkgload::load_all() system.file resolves into the package's temp
  # install; on deployed bundles it can come back empty, so fall back to the
  # project checkout on disk.
  p <- system.file(..., package = "cfb2nfl")
  if (!nzchar(p)) {
    p <- file.path(getwd(), "inst", ...)
  }
  p
}

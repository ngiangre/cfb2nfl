# App configuration helpers, following the golem convention (cf. golem's
# shinyexample R/app_config.R). `app_sys()` resolves files shipped with the
# installed package.

#' Access files in the current app
#'
#' @param ... character vectors, specifying subdirectory and file(s)
#' within your package. The default, none, returns the root of the app.
#' @noRd
app_sys <- function(...) {
  system.file(..., package = "cfbstats")
}

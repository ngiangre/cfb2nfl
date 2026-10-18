#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
app_ui <- function(request) {
  d <- app_data()

  panels <- c(
    list(
      bslib::nav_panel("ERD", value = "ERD", mod_erd_ui("erd"))
    ),
    lapply(d$tables, function(tb) {
      bslib::nav_panel(tb, value = tb, mod_table_browser_ui(paste0("tbl_", tb)))
    }),
    list(
      bslib::nav_panel("Query", value = "Query", mod_querychat_ui("query"))
    )
  )

  do.call(
    bslib::page_navbar,
    c(
      list(
        id = "topnav",
        title = shiny::tagList(
          "cfbstats",
          shiny::span(class = "text-muted", " · data browser")
        )
      ),
      panels
    )
  )
}

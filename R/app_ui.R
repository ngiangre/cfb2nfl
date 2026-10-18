#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
app_ui <- function(request) {
  d <- app_data()

  bslib::page_navbar(
    id = "topnav",
    bslib::nav_panel(
      title = "Look at the data",
      value = "data",
      icon = shiny::icon("table-list"),
      bslib::navset_underline(
        id = "datatabs",
        !!!c(
          list(
            bslib::nav_panel(
              "Diagram of Tables",
              value = "ERD",
              mod_erd_ui("erd")
            )
          ),
          lapply(d$tables, function(tb) {
            bslib::nav_panel(
              tb,
              value = tb,
              mod_table_browser_ui(paste0("tbl_", tb))
            )
          })
        )
      )
    )
    # bslib::nav_panel(
    #   title = "Talk with the data",
    #   icon = shiny::icon("robot"),
    #   mod_querychat_ui("query")
    # )
  )
}

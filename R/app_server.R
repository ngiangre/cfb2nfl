#' The application server-side
#'
#' @param input,output,session Internal parameters for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
app_server <- function(input, output, session) {
  d <- app_data()

  # ERD node click -> open that table's browser panel.
  selected_table <- mod_erd_server(
    "erd",
    dict = d$dict,
    tables = d$tables,
    n_rows = d$n_rows
  )
  shiny::observeEvent(
    selected_table(),
    {
      tb <- selected_table()
      if (!is.null(tb) && tb %in% d$tables) {
        bslib::nav_select("topnav", "data")
        bslib::nav_select("datatabs", tb)
      }
    },
    ignoreInit = TRUE
  )

  for (tb in d$tables) {
    local({
      mod_table_browser_server(
        paste0("tbl_", tb),
        con = d$con,
        table = tb,
        dict = d$dict,
        n_rows = d$n_rows[[tb]]
      )
    })
  }

  #mod_querychat_server("query", con = d$con, tables = d$tables)
}

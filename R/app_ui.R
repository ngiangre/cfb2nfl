#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
# Shared theme + mobile CSS. Phones need relaxed heights (a fixed viewport
# calc overflows small screens), wrap-friendly headers, and bigger touch
# targets for DT's filter inputs and pagination.
app_theme <- function() {
  bslib::bs_theme() |>
    bslib::bs_add_rules(
      "html { -webkit-text-size-adjust: 100%; }
       .dataTables_wrapper .form-control-sm,
       .dataTables_wrapper .custom-select-sm { min-height: 2.4rem; }
       /* many table tabs: scroll sideways on phones instead of stacking */
       .nav-underline {
         flex-wrap: nowrap;
         overflow-x: auto;
         -webkit-overflow-scrolling: touch;
       }
       .nav-underline .nav-link { white-space: nowrap; }
       @media (max-width: 767.98px) {
         .tbl-card > .card-body {
           height: auto !important;
           max-height: none !important;
           min-height: 65vh;
         }
         .dataTables_wrapper .dataTables_filter input {
           width: 12rem;
         }
         .erd-card #erd { height: 60vh !important; }
         footer, .card-header { font-size: 0.9rem; }
       }"
    )
}

app_ui <- function(request) {
  d <- app_data()

  bslib::page_navbar(
    id = "topnav",
    theme = app_theme(),
    bslib::nav_panel(
      title = "Look at the data",
      value = "data",
      icon = shiny::icon("table-list"),
      shiny::markdown(
        "Diagram of the connections between the data, and all the tables currently ingested within tabs. Play-by-play data not included yet. See the [API documentation](https://api.collegefootballdata.com/api) for endpoints to pull data from, the [methodology overview](https://api.collegefootballdata.com/methodology-overview), and the [data availability by theme](https://api.collegefootballdata.com/data-availability)."
      ),
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

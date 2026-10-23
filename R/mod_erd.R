# Interactive ERD module: renders the visNetwork graph and exposes the
# clicked table as a reactive, which app.R turns into navbar navigation.

# Plain-language label for each join namespace (colors come from
# erd_edge_palette in erd.R so the legend can't drift from the graph).
erd_legend <- function() {
  ns_labels <- c(
    athlete_id = "Links the same player across tables",
    game_id = "Links a player to a specific game",
    gsis_id = "Links to NFL records",
    draft_slot = "Links a draft pick by its slot",
    team_season = "Links a team in a given season",
    conference_season = "Links a conference in a given season",
    derived = "Built from other tables",
    name_guarded = "Matched by name when no ID exists (less reliable)"
  )
  htmltools::tagList(
    lapply(names(ns_labels), function(k) {
      htmltools::tags$span(
        style = "display:inline-block;margin-right:1em;white-space:nowrap;",
        htmltools::tags$span(
          style = sprintf(
            paste0(
              "display:inline-block;width:1em;height:1em;border-radius:2px;",
              "background:%s;vertical-align:-2px;margin-right:0.35em;"
            ),
            erd_edge_palette[[k]]
          )
        ),
        htmltools::tags$small(ns_labels[[k]])
      )
    })
  )
}

mod_erd_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::card(
    fill = TRUE,
    class = "erd-card",
    bslib::card_header(
      bslib::card_title("How the data fits together"),
      "Each box is one data table; lines show how the tables connect."
    ),
    bslib::card_body(
      # fixed height; app_theme's media query shrinks it on phones
      visNetwork::visNetworkOutput(ns("erd"), height = "700px"),
      htmltools::tags$style(sprintf(
        "#%s canvas { cursor: pointer; }",
        ns("erd")
      )),
      shiny::p(
        class = "text-muted",
        shiny::tags$strong("Click any table to open it below."),
        " Colors say how tables connect:"
      ),
      erd_legend(),
      shiny::uiOutput(ns("selected_line"))
    )
  )
}

mod_erd_server <- function(id, dict, tables, n_rows) {
  shiny::moduleServer(id, function(input, output, session) {
    output$erd <- visNetwork::renderVisNetwork({
      erd_network(
        dict,
        tables,
        click_input = session$ns("click"),
        n_rows = n_rows
      )
    })

    output$selected_line <- shiny::renderUI({
      tbl <- input$click
      shiny::req(tbl %in% tables)
      desc <- dict[[tbl]]$description
      shiny::p(
        class = "text-success",
        shiny::tags$strong(sprintf("Viewing: %s", tbl)),
        if (!is.null(desc) && nzchar(desc)) {
          htmltools::tags$span(sprintf(" \u2014 %s", desc))
        }
      )
    })

    shiny::reactive({
      if (shiny::isTruthy(input$click)) input$click else NULL
    })
  })
}

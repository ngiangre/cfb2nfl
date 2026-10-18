# Interactive ERD module: renders the visNetwork graph and exposes the
# clicked table as a reactive, which app.R turns into navbar navigation.

mod_erd_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::card(
    fill = TRUE,
    bslib::card_header("Entity-relationship map"),
    bslib::card_body(
      visNetwork::visNetworkOutput(ns("erd"), height = "700px"),
      shiny::p(
        class = "text-muted",
        "Click a table node to open its browser. Dashed edges are name-guarded links, not plain key joins."
      )
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

    shiny::reactive({
      if (shiny::isTruthy(input$click)) input$click else NULL
    })
  })
}

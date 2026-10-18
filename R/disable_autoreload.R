# Disable Shiny's autoreload for this app. Autoreload re-runs the whole app
# (including expensive QueryChat setup) on every file save, which is slow and
# can drop the chat state. Call once before shinyApp() starts.

disable_autoreload <- function() {
  options(shiny.autoreload = FALSE)
  shiny::shinyOptions(autoreload = FALSE)
  invisible(NULL)
}

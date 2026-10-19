# Launch file for the cfbstats data browser, following the golem convention:
# load the package from source, then start the app via run_app(). The app's
# UI/server/data logic lives in R/app_ui.R, R/app_server.R, R/app_data.R, and
# R/run_app.R — edit those, not this file.
#
# Run: shiny::runApp("app.R")  (or click "Run App" in the IDE)

pkgload::load_all(export_all = FALSE, helpers = FALSE, attach_testthat = FALSE)
options("golem.app.prod" = TRUE)
run_app() # add parameters here (if any)

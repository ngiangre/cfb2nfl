# NFL data is an outcome, never an in-career model input (decision 0014). The
# play-level NFL tables (feature F23) must stay off the path into the model:
# walk the pipeline graph upstream of the model targets.

test_that("no NFL play-level table is upstream of the model", {
  skip_if_not_installed("targets")
  root <- test_path("..", "..")
  skip_if_not(file.exists(file.path(root, "_targets.R")), "no _targets.R")

  edges <- withr::with_dir(
    root,
    targets::tar_network(targets_only = TRUE, outdated = FALSE)$edges
  )
  upstream_of <- function(nodes) {
    seen <- character(0)
    frontier <- nodes
    while (length(frontier) > 0) {
      parents <- setdiff(edges$from[edges$to %in% frontier], seen)
      seen <- c(seen, parents)
      frontier <- parents
    }
    seen
  }
  model_inputs <- upstream_of(c("model_table", "model_fit"))
  expect_true(length(model_inputs) > 0)

  nfl_play <- c(
    paste0("raw_", nfl_play_sources),
    paste0(nfl_play_sources, "_file"),
    nfl_play_sources,
    "nfl_players"
  )
  expect_identical(intersect(nfl_play, model_inputs), character(0))
})

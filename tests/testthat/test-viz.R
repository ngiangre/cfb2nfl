test_that("team_color_values maps team names to their hex colors", {
  teams <- tibble::tibble(
    team = c("Alabama", "Georgia", "Nowhere State", "Placeholder U"),
    color = c("#9E1B32", "#BA0C2F", NA, "#null")
  )
  expect_equal(
    team_color_values(teams),
    c(Alabama = "#9E1B32", Georgia = "#BA0C2F")
  )
})

test_that("scale_fill_team sends teams without a color to the fallback", {
  skip_if_not_installed("ggplot2")
  teams <- tibble::tibble(team = "Alabama", color = "#9E1B32")
  sc <- scale_fill_team(teams)
  expect_equal(sc$na.value, "#6b7280")
  expect_equal(sc$palette(1), c(Alabama = "#9E1B32"))
})

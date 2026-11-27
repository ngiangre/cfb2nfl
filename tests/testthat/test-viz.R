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

test_that("position_palette gives every position group a colour, quarterbacks orange", {
  pal <- position_palette()
  expect_setequal(names(pal), position_group_levels())
  expect_equal(pal[["Quarterback"]], "#D95F02")
  # Drafted green and undrafted purple belong to the outcomes, not a group.
  expect_false(any(toupper(pal) %in% c("#1B9E77", "#7570B3")))
  expect_equal(anyDuplicated(pal), 0L)
})

test_that("scale_colour_position maps groups to the shared palette", {
  skip_if_not_installed("ggplot2")
  sc <- scale_colour_position()
  expect_equal(sc$palette(9)[["Quarterback"]], "#D95F02")
})

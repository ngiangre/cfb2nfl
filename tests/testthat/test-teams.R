test_that("position_group maps every roster code to a reader label", {
  codes <- c(
    "QB",
    "RB",
    "FB",
    "WR",
    "TE",
    "T",
    "G",
    "C",
    "OL",
    "OT",
    "DL",
    "DE",
    "DT",
    "NT",
    "EDGE",
    "LB",
    "ILB",
    "OLB",
    "DB",
    "S",
    "CB",
    "PK",
    "P",
    "LS",
    "PR",
    "KR",
    "?",
    "ATH",
    NA
  )
  out <- position_group(codes)
  expect_type(out, "character")
  expect_false(anyNA(out))
  expect_equal(
    out[codes %in% c("T", "G", "C", "OL", "OT")],
    rep("Offensive line", 5)
  )
  expect_equal(out[codes %in% c("FB")], "Running back")
  expect_equal(out[codes %in% c("KR", "PR")], rep("Special teams", 2))
  expect_equal(
    out[is.na(codes) | codes %in% c("?", "ATH")],
    rep("Position not recorded", 3)
  )
  expect_setequal(
    unique(out),
    c(position_group_levels(), "Position not recorded")
  )
})

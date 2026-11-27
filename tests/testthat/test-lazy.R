skip_if_not_installed("arrow")
skip_if_not_installed("targets")

lazy_fixture <- function() {
  tibble::tibble(
    id = as.character(5:1),
    season = c(2024L, 2024L, 2025L, 2025L, 2025L),
    yards = c(3, NA, 7.5, -2, 0),
    when = as.POSIXct("2025-09-01 12:00:00", tz = "UTC") + 1:5
  )
}

# Build `code` (a list of targets) in a scratch project and return to it.
lazy_pipeline <- function(code, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  # Reading a custom-format target needs the store to be trusted.
  withr::local_envvar(TAR_ASK = "false", .local_envir = env)
  arrow::write_parquet(lazy_fixture(), "fixture.parquet")
  writeLines(
    c(
      "library(targets)",
      sprintf("fmt <- %s", paste(deparse(format_arrow_lazy()), collapse = "")),
      code
    ),
    "_targets.R"
  )
  targets::tar_make(reporter = "silent", callr_function = NULL)
  dir
}

test_that("format_arrow_lazy round-trips a data frame, Table and query lazily", {
  lazy_pipeline(c(
    "list(",
    "  tar_target(df, arrow::read_parquet('fixture.parquet'), format = fmt),",
    "  tar_target(tbl, arrow::read_parquet('fixture.parquet', as_data_frame = FALSE), format = fmt),",
    "  tar_target(qry, dplyr::filter(arrow::open_dataset('fixture.parquet'), season == 2025L), format = fmt)",
    ")"
  ))
  for (name in c("df", "tbl")) {
    out <- targets::tar_read_raw(name)
    expect_true(is_lazy_arrow(out))
    expect_false(is.data.frame(out))
    expect_identical(collect_cols(out), lazy_fixture())
  }
  qry <- collect_cols(targets::tar_read(qry))
  expect_identical(
    dplyr::arrange(qry, id),
    dplyr::arrange(dplyr::filter(lazy_fixture(), season == 2025L), id)
  )
})

test_that("a Dataset is stored as a reference, not a copy", {
  lazy_pipeline(c(
    "list(",
    "  tar_target(src, 'fixture.parquet', format = 'file'),",
    "  tar_target(ds, arrow::open_dataset(src), format = fmt),",
    "  tar_target(n, nrow(collect_cols(ds)))",
    ")"
  ))
  ref <- targets::tar_read(ds)
  expect_s3_class(ref, "FileSystemDataset")
  expect_identical(collect_cols(ref), lazy_fixture())
  stored <- targets::tar_meta(ds, bytes)$bytes
  expect_lt(stored, file.size("fixture.parquet"))

  # A changed source file invalidates the reference and everything after it.
  arrow::write_parquet(lazy_fixture()[1:2, ], "fixture.parquet")
  expect_error(targets::tar_read(ds), "changed")
  targets::tar_make(reporter = "silent", callr_function = NULL)
  expect_identical(targets::tar_read(n), 2L)
})

test_that("collect_cols keeps file order and selects columns", {
  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(lazy_fixture(), path)
  ds <- arrow::open_dataset(path)
  expect_identical(
    collect_cols(ds, c("id", "yards", "missing")),
    lazy_fixture()[c("id", "yards")]
  )
  # Data frames pass through untouched, so fixtures need no Arrow.
  df <- lazy_fixture()
  expect_identical(collect_cols(df, "id"), df)
})

test_that("distinct_values and n_rows read lazy and in-memory tables alike", {
  path <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(lazy_fixture(), path)
  ds <- arrow::open_dataset(path)
  expect_setequal(distinct_values(ds, "season"), c(2024L, 2025L))
  expect_setequal(distinct_values(lazy_fixture(), "season"), c(2024L, 2025L))
  expect_identical(n_rows(ds), 5L)
  expect_identical(n_rows(lazy_fixture()), 5L)
})

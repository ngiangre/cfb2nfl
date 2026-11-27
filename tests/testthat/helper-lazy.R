# A data frame as the lazy Arrow dataset the pipeline passes around
# (format_arrow_lazy(), issue #126): consumers must give the same answer.
as_lazy <- function(df, env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".parquet", .local_envir = env)
  arrow::write_parquet(df, path)
  arrow::open_dataset(path)
}

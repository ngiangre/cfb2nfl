# Lineage / audit layer (decision 0005). A uniform, per-step record of what each
# transform did to the data so any statistic or prediction can be traced back to
# the rows and code that produced it, and silent row loss / schema drift is
# caught the moment it happens.

#' Hash a data frame's schema
#'
#' A stable digest of column names and types, used to detect schema drift across
#' data refreshes (decision 0005).
#'
#' @param data A data frame.
#'
#' @return A short character hash.
#' @export
schema_hash <- function(data) {
  spec <- paste(
    names(data),
    vapply(data, \(x) class(x)[1], character(1)),
    sep = ":",
    collapse = "|"
  )
  substr(rlang::hash(spec), 1, 12)
}

#' Best-effort current git SHA
#'
#' @return The short HEAD SHA, or `NA` if unavailable.
#' @keywords internal
current_git_sha <- function() {
  tryCatch(
    {
      if (requireNamespace("gert", quietly = TRUE)) {
        substr(gert::git_log(max = 1)$commit, 1, 12)
      } else {
        NA_character_
      }
    },
    error = \(e) NA_character_
  )
}

#' Key-combo survival and NA profile for one step
#'
#' Helpers behind [audit_step()]: how many input key combinations survive into
#' the output (join/filter coverage, distinct from fan-out), and a per-column
#' NA profile so sparsity is attributable to columns, not just counted in bulk.
#'
#' @param input,output Data frames; `keys` must exist in both for coverage.
#' @param keys Character vector of key columns.
#'
#' @name audit_metrics
#' @keywords internal
key_coverage <- function(input, output, keys) {
  in_keys <- dplyr::distinct(dplyr::select(input, dplyr::all_of(keys)))
  out_keys <- dplyr::distinct(dplyr::select(output, dplyr::all_of(keys)))
  matched <- nrow(dplyr::semi_join(in_keys, out_keys, by = keys))
  list(
    pct_keys_matched = if (nrow(in_keys) > 0) {
      matched / nrow(in_keys)
    } else {
      NA_real_
    },
    # distinct key combinations present in the input but gone from the output
    keys_dropped = nrow(in_keys) - matched
  )
}

na_profile <- function(data) {
  n <- nrow(data)
  prof <- tibble::tibble(
    col = names(data),
    n_na = unname(vapply(data, \(x) sum(is.na(x)), integer(1)))
  ) |>
    dplyr::mutate(na_rate = n_na / n) |>
    dplyr::filter(n_na > 0) |>
    dplyr::arrange(dplyr::desc(n_na))
  prof
}

#' Record an audit row for one pipeline step
#'
#' Captures a uniform lineage record (decision 0005): input/output row & column
#' counts, rows dropped, key coverage, join coverage, total and per-column NA
#' cells, a schema hash, the governing contract's pass/fail, timestamp, and git
#' SHA. Row-bind the records from every step into the pipeline's audit target.
#'
#' @param output The step's output data frame.
#' @param step Short step name (e.g. `"link_coaches"`).
#' @param stage Pipeline stage (`"ingest"`, `"clean"`, `"link"`, `"features"`,
#'   `"model"`, `"report"`).
#' @param input Optional input data frame, to compute deltas.
#' @param keys Optional character vector of key columns to summarize coverage
#'   on. When present in both `input` and `output`, `pct_keys_matched` and
#'   `keys_dropped` are computed; otherwise they are `NA`.
#' @param contract_passed Optional logical: did the step's data contract pass?
#'
#' @return A one-row tibble of audit fields. `na_by_col` is a list column
#'   holding a per-column NA profile (`col`, `n_na`, `na_rate`) for columns
#'   with at least one NA, sorted by NA count descending.
#' @export
audit_step <- function(
  output,
  step,
  stage,
  input = NULL,
  keys = NULL,
  contract_passed = NA
) {
  n_keys_out <- if (!is.null(keys) && all(keys %in% names(output))) {
    dplyr::n_distinct(dplyr::select(output, dplyr::all_of(keys)))
  } else {
    NA_integer_
  }
  # join/filter coverage vs fan-out: rows_delta conflates them
  coverage <- if (
    !is.null(input) &&
      !is.null(keys) &&
      all(keys %in% names(input)) &&
      all(keys %in% names(output))
  ) {
    key_coverage(input, output, keys)
  } else {
    list(pct_keys_matched = NA_real_, keys_dropped = NA_integer_)
  }
  na_by_col <- na_profile(output)
  tibble::tibble(
    step = step,
    stage = stage,
    n_rows_in = if (is.null(input)) NA_integer_ else nrow(input),
    n_rows_out = nrow(output),
    rows_delta = if (is.null(input)) {
      NA_integer_
    } else {
      nrow(output) - nrow(input)
    },
    # key combos from the input that no longer appear (0 = pure fan-out/addition)
    keys_dropped = coverage$keys_dropped,
    pct_keys_matched = coverage$pct_keys_matched,
    n_cols_out = ncol(output),
    n_keys_out = n_keys_out,
    n_na_cells = sum(vapply(output, \(x) sum(is.na(x)), integer(1))),
    n_cols_with_na = nrow(na_by_col),
    na_by_col = list(na_by_col),
    schema_hash = schema_hash(output),
    contract_passed = contract_passed,
    timestamp = Sys.time(),
    git_sha = current_git_sha()
  )
}

#' Append the current audit log to a schema-history CSV
#'
#' Keeps one row per (step, run) across refreshes so `schema_hash` drift is
#' detectable between runs (audit-hygiene workstream D). The CSV lives in
#' `data/` (gitignored) and is carried across CI refreshes as a `data-latest`
#' release asset, since refresh checkouts start empty.
#'
#' @param audit_log A tibble of [audit_step()] rows (the `audit_log` target).
#' @param path History CSV path; created if absent, appended to otherwise.
#'
#' @return The full history tibble (one row per step per run), invisibly.
#' @export
update_schema_history <- function(audit_log, path) {
  keep <- c("step", "n_cols_out", "schema_hash", "timestamp", "git_sha")
  new <- audit_log[keep]
  # timestamps round-trip through CSV as character; compare on one type
  new$timestamp <- as.character(new$timestamp)
  old <- if (file.exists(path)) {
    tibble::as_tibble(utils::read.csv(path))
  } else {
    NULL
  }
  history <- if (is.null(old)) {
    new
  } else {
    dplyr::bind_rows(
      old,
      dplyr::anti_join(new, old, by = c("step", "timestamp"))
    )
  }
  utils::write.csv(history, path, row.names = FALSE, na = "")
  invisible(history)
}

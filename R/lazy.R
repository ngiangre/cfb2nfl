# Lazy Arrow tables in the pipeline (issue #126, decision 0053). The large
# tables (plays, play stats, NFL play-by-play and participation, player game
# stats, explorer plays) stay unmaterialized Arrow datasets between targets;
# each consumer reads only the columns it needs.

#' Lazy Arrow storage format for targets
#'
#' A [targets::tar_format()] whose stored value reads back as an
#' unmaterialized [arrow::open_dataset()] handle: nothing is loaded until a
#' consumer collects it ([collect_cols()]).
#'
#' * A parquet `FileSystemDataset` (e.g. `arrow::open_dataset(plays_file)`)
#'   is stored as a **reference**: its file paths (relative to the project
#'   when inside it) and content hashes, a few hundred bytes. The published
#'   parquet in `data/` is then not copied into `_targets/objects/`. Because
#'   the hashes are part of the stored value, a changed file changes the
#'   target's hash and invalidates everything downstream; reading a
#'   reference whose file changed since the build is an error, not a silent
#'   read of new data. The referenced files must outlive the target, so
#'   reference only files a `format = "file"` target tracks.
#' * A data frame or Arrow `Table` is written to the store as parquet.
#' * Any other Arrow query or dataset (an `arrow_dplyr_query`, an in-memory
#'   dataset) is streamed to parquet with [arrow::write_dataset()], without a
#'   `collect()`.
#'
#' Row order of a lazy query is not guaranteed by Arrow, so consumers that
#' need file order read through [collect_cols()].
#'
#' targets treats a format with custom code as untrusted: a non-interactive
#' `tar_read()` of one of these targets errors unless `TAR_ASK=false` is set
#' (an interactive session asks once). `tar_make()` and reads of other
#' targets are unaffected.
#'
#' @return A custom format string for `tar_target(format = )`.
#' @export
#' @examples
#' \dontrun{
#' tar_target(plays, arrow::open_dataset(plays_file), format = format_arrow_lazy())
#' }
format_arrow_lazy <- function() {
  # Both methods run in a fresh environment whose parent is baseenv()
  # (targets deparses them), so every call is namespaced.
  targets::tar_format(
    read = function(path) {
      if (identical(readBin(path, "raw", 4L), charToRaw("PAR1"))) {
        return(arrow::open_dataset(path))
      }
      ref <- readRDS(path)
      missing <- ref$files[!file.exists(ref$files)]
      if (length(missing)) {
        stop(
          "Lazy reference to missing file(s): ",
          paste(missing, collapse = ", "),
          ". Run targets::tar_make().",
          call. = FALSE
        )
      }
      if (!identical(unname(rlang::hash_file(ref$files)), ref$hashes)) {
        stop(
          "File(s) changed since the target was built: ",
          paste(ref$files, collapse = ", "),
          ". Run targets::tar_make().",
          call. = FALSE
        )
      }
      arrow::open_dataset(ref$files)
    },
    write = function(object, path) {
      is_parquet_files <- inherits(object, "FileSystemDataset") &&
        inherits(object$format, "ParquetFileFormat")
      if (is_parquet_files) {
        files <- normalizePath(object$files)
        root <- paste0(normalizePath(getwd()), "/")
        inside <- startsWith(files, root)
        files[inside] <- substring(files[inside], nchar(root) + 1L)
        saveRDS(
          list(files = files, hashes = unname(rlang::hash_file(files))),
          path
        )
      } else if (inherits(object, c("data.frame", "ArrowTabular"))) {
        arrow::write_parquet(object, path)
      } else {
        tmp <- tempfile()
        on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
        arrow::write_dataset(
          object,
          tmp,
          format = "parquet",
          basename_template = "part-{i}.parquet"
        )
        parts <- list.files(tmp, full.names = TRUE)
        if (length(parts) == 1L) {
          file.copy(parts, path, overwrite = TRUE)
        } else {
          # An empty query writes no file; keep its schema.
          arrow::write_parquet(arrow::as_arrow_table(object), path)
        }
      }
    }
  )
}

#' Lazy Arrow table helpers
#'
#' Consumers of the lazy pipeline tables ([format_arrow_lazy()]) go through
#' these so the same code takes an in-memory data frame (tests, fixtures) or
#' a lazy Arrow table.
#'
#' * `is_lazy_arrow()`: is `x` an Arrow dataset, query or `Table`?
#' * `collect_cols()`: materialize `x` as a tibble, only the `cols` that exist
#'   (all when `NULL`). A parquet dataset is read file by file with
#'   [arrow::read_parquet()], so rows keep their file order, exactly as a
#'   whole-table read did. A data frame is returned unchanged.
#' * `distinct_values()`: the distinct values of one column, computed in
#'   Arrow for a lazy table, in no particular order.
#' * `n_rows()`: the row count, from parquet metadata for a dataset.
#'
#' @param x A data frame or a lazy Arrow table.
#' @param cols Columns to keep; names missing from `x` are skipped, so a
#'   contract's column checks still see them as missing.
#' @param col One column name.
#' @return `is_lazy_arrow()`: a logical; `collect_cols()`: a tibble (or `x`);
#'   `distinct_values()`: a vector; `n_rows()`: an integer.
#' @name lazy_arrow
#' @export
is_lazy_arrow <- function(x) {
  inherits(x, c("Dataset", "arrow_dplyr_query", "ArrowTabular"))
}

#' @rdname lazy_arrow
#' @export
collect_cols <- function(x, cols = NULL) {
  if (!is_lazy_arrow(x)) {
    return(x)
  }
  if (
    inherits(x, "FileSystemDataset") &&
      inherits(x$format, "ParquetFileFormat")
  ) {
    parts <- lapply(x$files, function(f) {
      if (is.null(cols)) {
        arrow::read_parquet(f)
      } else {
        arrow::read_parquet(f, col_select = dplyr::any_of(cols))
      }
    })
    return(if (length(parts) == 1L) parts[[1L]] else dplyr::bind_rows(parts))
  }
  if (!is.null(cols)) {
    x <- dplyr::select(x, dplyr::any_of(cols))
  }
  tibble::as_tibble(dplyr::collect(x))
}

#' @rdname lazy_arrow
#' @export
distinct_values <- function(x, col) {
  if (!is_lazy_arrow(x)) {
    return(unique(x[[col]]))
  }
  dplyr::collect(dplyr::distinct(x, !!rlang::sym(col)))[[col]]
}

#' @rdname lazy_arrow
#' @export
n_rows <- function(x) {
  if (inherits(x, c("Dataset", "ArrowTabular", "data.frame"))) {
    return(as.integer(nrow(x)))
  }
  as.integer(dplyr::collect(dplyr::count(x))$n)
}

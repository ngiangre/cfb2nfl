# Per-table browser module: a DT table whose searching, sorting, and
# pagination all run as SQL in DuckDB via DT's server-side processing
# (session$registerDataObj), so large tables never leave the database.
# Column headers carry tooltips with definitions from inst/dict/*.yml.

# Escape a literal for ILIKE / SQL string context.
sql_like_escape <- function(x) {
  gsub("'", "''", x)
}

like_clause <- function(col, term) {
  sprintf("CAST(%s AS VARCHAR) ILIKE '%%%s%%'", col, sql_like_escape(term))
}

# DT's slider filters send "low ... high" strings (epoch-milliseconds for
# date/time columns) and its selectize filters send JSON arrays; only
# character columns arrive as plain substrings.
range_clause <- function(col, type, term) {
  parts <- strsplit(term, " ... ", fixed = TRUE)[[1]]
  if (length(parts) != 2L) {
    return(NULL)
  }
  lo <- suppressWarnings(as.numeric(trimws(parts[[1]])))
  hi <- suppressWarnings(as.numeric(trimws(parts[[2]])))
  if (is.na(lo) || is.na(hi)) {
    return(NULL)
  }
  if (type == "date") {
    sprintf("%s BETWEEN epoch_ms(%.0f) AND epoch_ms(%.0f)", col, lo, hi)
  } else {
    sprintf("CAST(%s AS DOUBLE) BETWEEN %.6g AND %.6g", col, lo, hi)
  }
}

select_clause <- function(col, term) {
  values <- tryCatch(jsonlite::fromJSON(term), error = function(e) NULL)
  if (!is.character(values) || length(values) == 0L) {
    return(NULL)
  }
  quoted <- vapply(
    values,
    function(v) paste0("'", sql_like_escape(v), "'"),
    character(1)
  )
  sprintf("%s IN (%s)", col, paste(quoted, collapse = ", "))
}

filter_clause <- function(col, type, term) {
  if (!nzchar(term)) {
    return(NULL)
  }
  if (type %in% c("integer", "number", "date")) {
    range_clause(col, type, term)
  } else if (type %in% c("factor", "logical")) {
    select_clause(col, term)
  } else {
    like_clause(col, term)
  }
}

#' Build page/count SQL for a DataTables server-side request
#'
#' Pure function over the DataTables ajax parameters so it can be tested
#' without a database. Columns must already be quoted identifiers; `types`
#' mirrors DT's per-column filter types ("character", "integer", "number",
#' "date", "factor") so each column search term is translated into SQL
#' matching what DT's widget sends.
#' @noRd
dt_sql <- function(
  table,
  cols,
  types = rep("character", length(cols)),
  search = "",
  col_search = rep("", length(cols)),
  order_col = 1L,
  order_dir = "asc",
  start = 0L,
  length = 25L
) {
  stopifnot(length(cols) >= 1L, order_dir %in% c("asc", "desc"))
  if (!(order_col %in% seq_along(cols))) {
    order_col <- 1L
  }

  where <- c()
  if (nzchar(search)) {
    global <- vapply(cols, like_clause, character(1), term = search)
    where <- c(where, paste("(", paste(global, collapse = " OR "), ")"))
  }
  if (length(col_search) == length(cols)) {
    hits <- which(nzchar(col_search))
    for (i in hits) {
      clause <- filter_clause(cols[[i]], types[[i]], col_search[[i]])
      if (!is.null(clause)) {
        where <- c(where, clause)
      }
    }
  }
  where_sql <- if (length(where)) {
    paste(" WHERE", paste(where, collapse = " AND "))
  } else {
    ""
  }
  order_sql <- sprintf(" ORDER BY %s %s", cols[[order_col]], toupper(order_dir))

  list(
    total_sql = sprintf("SELECT COUNT(*) FROM %s", table),
    filtered_sql = sprintf("SELECT COUNT(*) FROM %s%s", table, where_sql),
    page_sql = sprintf(
      "SELECT %s FROM %s%s%s LIMIT %d OFFSET %d",
      paste(cols, collapse = ", "),
      table,
      where_sql,
      order_sql,
      max(length, 0L),
      max(as.integer(start), 0L)
    )
  )
}

#' DataTables ajax handler backed by DuckDB
#'
#' Returns the handler for session$registerDataObj(): parses the DataTables
#' ajax payload, pushes search/sort/paging into SQL, and answers with the
#' JSON shape DataTables' server-side mode expects.
#' @noRd
dt_ajax_handler <- function(con, table, cols, types) {
  quoted <- vapply(
    cols,
    function(x) as.character(DBI::dbQuoteIdentifier(con, x)),
    character(1)
  )
  quoted_table <- as.character(DBI::dbQuoteIdentifier(con, table))

  function(data, req) {
    # Shiny leaves jQuery's ajax method as POST for DT's server-side calls, so
    # the DataTables payload can arrive in the request body instead of the
    # query string. Read whichever carries it (the dataobj response ends the
    # request, so consuming the body here is safe).
    if (identical(req$REQUEST_METHOD, "POST") && !nzchar(req$QUERY_STRING)) {
      query_string <- paste(req$rook.input$read_lines(), collapse = "\n")
    } else {
      query_string <- req$QUERY_STRING
    }
    q <- shiny::parseQueryString(query_string, nested = TRUE)
    search <- q$search$value %||% ""
    col_search <- vapply(
      q$columns %||% list(),
      function(c) c$search$value %||% "",
      character(1)
    )
    order0 <- if (length(q$order)) q$order[[1]] else list()
    order_col <- as.integer(order0$column %||% 1L) + 1L
    order_dir <- order0$dir %||% "asc"

    s <- dt_sql(
      quoted_table,
      unname(quoted),
      types = types,
      search = search,
      col_search = col_search,
      order_col = order_col,
      order_dir = order_dir,
      start = as.integer(q$start %||% 0L),
      length = as.integer(q$length %||% 25L)
    )

    rows <- DBI::dbGetQuery(con, s$page_sql)
    # DataTables expects rows as arrays of values.
    data_rows <- lapply(seq_len(nrow(rows)), function(i) {
      as.list(unname(rows[i, , drop = FALSE]))
    })
    json <- jsonlite::toJSON(
      list(
        draw = as.integer(q$draw %||% 1L),
        recordsTotal = DBI::dbGetQuery(con, s$total_sql)[[1]],
        recordsFiltered = DBI::dbGetQuery(con, s$filtered_sql)[[1]],
        data = data_rows
      ),
      dataframe = NULL,
      auto_unbox = FALSE,
      na = "null",
      digits = NA
    )
    # The dataobj route passes the return straight through to httpuv; a bare
    # string is not a valid response and breaks DT's ajax call.
    shiny::httpResponse(
      200L,
      "application/json",
      paste0(json, "\n")
    )
  }
}

# HTML for one column header: a native title attribute carries the dictionary
# description (and type) when documented. bslib::tooltip needs bootstrap JS
# initialization that never runs on DT-generated headers, so a native
# title tooltip is the robust choice.
header_html <- function(col, col_dict) {
  desc <- if (is.null(col_dict$description)) {
    "Not documented in the data dictionary."
  } else {
    paste0(
      htmltools::htmlEscape(col_dict$description, attribute = TRUE),
      if (!is.null(col_dict$type)) sprintf(" (%s)", col_dict$type)
    )
  }
  sprintf(
    '<span style="cursor: help; border-bottom: 1px dotted #888;" title="%s">%s</span>',
    desc,
    htmltools::htmlEscape(col)
  )
}

mod_table_browser_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::card(
    fill = TRUE,
    class = "tbl-card",
    bslib::card_header(shiny::uiOutput(ns("subtitle"))),
    bslib::card_body(
      DT::DTOutput(ns("tbl")),
      height = "calc(100vh - 220px)"
    )
  )
}

mod_table_browser_server <- function(id, con, table, dict, n_rows) {
  shiny::moduleServer(id, function(input, output, session) {
    # The database owns the column list; the dict only supplies descriptions.
    cols <- names(DBI::dbGetQuery(
      con,
      sprintf("SELECT * FROM %s LIMIT 0", DBI::dbQuoteIdentifier(con, table))
    ))
    quoted_cols <- paste(
      vapply(
        cols,
        function(x) as.character(DBI::dbQuoteIdentifier(con, x)),
        character(1)
      ),
      collapse = ", "
    )
    # A small real sample so DT's type detection can pick the right filter
    # widget per column (numeric range, date) instead of plain text everywhere;
    # the rows themselves are replaced on the first server-side draw.
    sample_rows <- DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT %s FROM %s LIMIT 10",
        quoted_cols,
        DBI::dbQuoteIdentifier(con, table)
      )
    )
    col_types <- vapply(
      sample_rows,
      function(d) {
        if (inherits(d, c("Date", "POSIXct", "POSIXt"))) {
          "date"
        } else if (is.numeric(d)) {
          if (is.integer(d)) "integer" else "number"
        } else if (is.factor(d) || is.logical(d)) {
          "factor"
        } else {
          "character"
        }
      },
      character(1)
    )

    # A table missing from the dict (e.g. a not-yet-documented view) still browses.
    col_dict <- dict[[table]]$columns
    if (is.null(col_dict)) {
      col_dict <- list()
    }
    names(col_dict) <- vapply(col_dict, `[[`, character(1), "name")

    output$subtitle <- shiny::renderText({
      grain <- dict[[table]]$grain
      if (is.null(grain)) {
        grain <- ""
      }
      sprintf(
        "%s | %s | column headers show dictionary definitions",
        format(n_rows, big.mark = ","),
        grain
      )
    })

    output$tbl <- DT::renderDT({
      if (Sys.getenv("DT_DEBUG", "") == "1") {
        writeLines(
          sprintf("renderDT expr ran for %s", table),
          Sys.getenv("DT_DEBUG_FILE", tempfile())
        )
      }
      DT::datatable(
        sample_rows,
        # rownames=TRUE would prepend a phantom column and shift every
        # server-side column index by one.
        rownames = FALSE,
        colnames = unname(vapply(
          cols,
          function(c) header_html(c, col_dict[[c]]),
          character(1)
        )),
        filter = "top",
        # HTML colnames (tooltip spans) survive only when not escaped.
        escape = FALSE,
        # compact class tightens cell padding so more rows fit the taller card
        class = "compact nowrap",
        fillContainer = TRUE,
        options = list(
          serverSide = TRUE,
          processing = TRUE,
          pageLength = 100,
          lengthMenu = list(
            c(100, -1),
            c("100", "All")
          ),
          scrollX = TRUE,
          searchDelay = 400,
          ajax = list(
            # explicit GET so the payload lands in QUERY_STRING even though
            # Shiny defaults jQuery ajax to POST
            type = "GET",
            url = session$registerDataObj(
              paste0("dt_", table),
              NULL,
              dt_ajax_handler(con, table, cols, unname(col_types))
            )
          )
        )
      )
    })
  })
}

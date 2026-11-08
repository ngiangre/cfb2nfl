# Interactive ERD plumbing for the Shiny data browser: the join graph is
# parsed from inst/data-model.md so the diagram, querychat context, and
# dictionaries stay in sync from one source.

# Table -> visual group. Display only; mirrors the narrative grouping in
# inst/data-model.md (college stats / games / context / draft & NFL / audit).
erd_groups <- c(
  player_stats = "College stats",
  stat_taxonomy = "College stats",
  ps_change = "College stats",
  career_summary = "College stats",
  game_player_stats = "College stats",
  player_game = "College stats",
  play_stats = "College stats",
  games = "Games",
  game_team_stats = "Games",
  plays = "Games",
  play_types = "Games",
  play_stat_types = "Games",
  roster = "Context",
  coaches = "Context",
  recruiting = "Context",
  teams = "Context",
  conference_tiers = "Context",
  picks = "Draft & NFL",
  nfl_draft_picks = "Draft & NFL",
  nfl_rosters = "Draft & NFL",
  nfl_player_stats = "Draft & NFL",
  combine = "Draft & NFL",
  audit_log = "Audit"
)

erd_group_colors <- c(
  "College stats" = "#4C78A8",
  "Games" = "#72B7B2",
  "Context" = "#F58518",
  "Draft & NFL" = "#54A24B",
  "Audit" = "#999999",
  "Other" = "#B0B0B0"
)

#' Parse the mermaid erDiagram block from the data-model doc
#'
#' Extracts the entity-relationship graph as tidy nodes/edges data frames so
#' the app renders the same ERD the documentation describes.
#'
#' @param lines Character vector of the document's lines.
#' @return List with `nodes` (id, group) and `edges` (from, to, card, label,
#'   dashes) data frames.
#' Load a file bundled under `inst/`
#'
#' Delegates to `app_sys()`, which reads `inst/` from the project checkout.
#' @noRd
erd_asset <- function(rel) {
  p <- app_sys(rel)
  if (!file.exists(p)) {
    stop(sprintf("packaged asset not found: %s", rel), call. = FALSE)
  }
  p
}

#' Parse the mermaid erDiagram block from the data-model doc
#'
#' Extracts the entity-relationship graph as tidy nodes/edges data frames so
#' the app renders the same ERD the documentation describes.
#'
#' @param lines Character vector of the document's lines.
#' @return List with `nodes` (id, group) and `edges` (from, to, card, label,
#'   dashes) data frames.
#' @noRd
parse_erd_mermaid <- function(lines) {
  rel <- grep('^\\s*\\w+\\s+\\S+\\s+\\w+\\s*:\\s*"', lines, value = TRUE)
  m <- regexec('^\\s*(\\w+)\\s+(\\S+)\\s+(\\w+)\\s*:\\s*"(.*)"\\s*$', rel)
  parts <- regmatches(rel, m)
  edges <- data.frame(
    from = vapply(parts, `[[`, character(1), 2),
    card = vapply(parts, `[[`, character(1), 3),
    to = vapply(parts, `[[`, character(1), 4),
    label = vapply(parts, `[[`, character(1), 5),
    # Mermaid's dotted cardinalities (|o..o|) mark name-guarded joins.
    dashes = vapply(parts, function(p) grepl("\\.\\.", p[[3]]), logical(1)),
    stringsAsFactors = FALSE
  )
  ids <- unique(c(edges$from, edges$to))
  nodes <- data.frame(
    id = ids,
    group = unname(erd_groups[ids]),
    stringsAsFactors = FALSE
  )
  nodes$group[is.na(nodes$group)] <- "Other"
  list(nodes = nodes, edges = edges)
}

#' Load every data dictionary
#'
#' Reads `inst/dict/*.yml` into a named list keyed by table name; each entry
#' carries `grain`, `key`, `description`, and per-column metadata used for
#' table-header tooltips.
#' @noRd
app_dict <- function(dict_dir = app_sys("dict")) {
  files <- list.files(dict_dir, "\\.yml$", full.names = TRUE)
  out <- lapply(files, yaml::read_yaml)
  names(out) <- tools::file_path_sans_ext(basename(files))
  out
}

# Edge color by join namespace, so the five documented key families are
# visually distinct (mirrors the "Join keys & namespaces" section of
# inst/data-model.md).
erd_edge_palette <- c(
  athlete_id = "#4C78A8",
  game_id = "#72B7B2",
  draft_slot = "#54A24B",
  gsis_id = "#2CA02C",
  team_season = "#F58518",
  conference_season = "#E45756",
  derived = "#B0B0B0",
  name_guarded = "#9467BD"
)

#' Classify an edge's join key into its namespace
#'
#' @param label The mermaid edge label (e.g. "playerId, season").
#' @param dashes TRUE when the link is name-guarded.
#' @return Named palette entry, or `derived` for intra-pipeline transforms.
#' @noRd
erd_key_namespace <- function(label, dashes) {
  if (dashes) {
    return("name_guarded")
  }
  l <- tolower(label)
  if (grepl("pivoted|collapsed", l)) {
    return("derived")
  }
  if (grepl("gsis_id", l)) {
    return("gsis_id")
  }
  if (grepl("slot", l)) {
    return("draft_slot")
  }
  if (grepl("gameid", l)) {
    return("game_id")
  }
  if (grepl("conference", l)) {
    return("conference_season")
  }
  if (grepl("team|school", l)) {
    return("team_season")
  }
  if (grepl("playerid", l)) {
    return("athlete_id")
  }
  "derived"
}

#' Build the visNetwork ERD widget
#'
#' Nodes are tables (tooltips show grain, key, and row count); edges are the
#' join relationships, dashed when name-guarded. Only tables present in the
#' database are rendered  --  the doc's graph can lead the bundle (e.g. the
#' games family before its first publish). The click JS reports the selected
#' node id to a (namespaced) Shiny input.
#' @noRd
erd_network <- function(
  dict,
  tables,
  click_input = "erd_click",
  n_rows = NULL
) {
  md <- readLines(erd_asset("data-model.md"))
  g <- parse_erd_mermaid(md)

  keep <- g$nodes$id %in% tables
  g$nodes <- g$nodes[keep, , drop = FALSE]
  g$edges <- g$edges[
    g$edges$from %in% g$nodes$id & g$edges$to %in% g$nodes$id,
    ,
    drop = FALSE
  ]

  if (nrow(g$nodes) == 0) {
    return(
      visNetwork::visNetwork(
        data.frame(id = character(0), label = character(0)),
        data.frame(from = character(0), to = character(0)),
        height = "700px",
        width = "100%"
      )
    )
  }

  title <- vapply(
    g$nodes$id,
    function(id) {
      d <- dict[[id]]
      grain <- if (!is.null(d$grain)) htmltools::htmlEscape(d$grain) else ""
      n <- if (!is.null(n_rows[[id]])) {
        sprintf("<br/>Rows: %s", format(n_rows[[id]], big.mark = ","))
      } else {
        ""
      }
      sprintf("<b>%s</b><br/><small>%s%s</small>", id, grain, n)
    },
    character(1)
  )

  nodes <- g$nodes
  nodes$label <- nodes$id
  nodes$title <- unname(title)
  nodes$color <- unname(erd_group_colors[nodes$group])
  nodes$font <- list(list(size = 16, face = "sans"))

  edges <- g$edges
  if (nrow(edges) > 0) {
    ns <- mapply(erd_key_namespace, edges$label, edges$dashes)
    edges$arrows <- "to"
    edges$smooth <- FALSE
    edges$color <- unname(erd_edge_palette[ns])
    edges$title <- sprintf(
      "<b>%s -> %s</b><br/>Join key: %s%s",
      edges$from,
      edges$to,
      htmltools::htmlEscape(edges$label),
      ifelse(
        ns == "name_guarded",
        "<br/><i>Name-guarded, not a plain key join</i>",
        ""
      )
    )
    edges$font <- list(list(size = 13, color = "#333333", face = "sans"))
  }

  visNetwork::visNetwork(nodes, edges, height = "700px", width = "100%") |>
    visNetwork::visEdges(
      arrows = "to",
      smooth = FALSE
    ) |>
    visNetwork::visOptions(
      highlightNearest = list(enabled = TRUE, degree = 1, hover = TRUE),
      nodesIdSelection = FALSE
    ) |>
    visNetwork::visHierarchicalLayout(
      direction = "LR",
      levelSeparation = 300,
      nodeSpacing = 120,
      sortMethod = "hubsize"
    ) |>
    visNetwork::visEvents(
      click = htmlwidgets::JS(sprintf(
        'function(nodes) { var sel = nodes.nodes.filter(function(x) {
           return typeof x === "string"; });
           if (sel.length) Shiny.setInputValue("%s", sel[0], {priority: "event"});
         }',
        click_input
      ))
    )
}

#' Render a node tooltip listing a table's definition and every column
#'
#' Builds the HTML shown when hovering a node in `data_model_network()`: the
#' table name, grain, key and description, then a scrollable list of its
#' columns (name, type, description) read from the dictionary.
#'
#' @param id Table name.
#' @param d The table's dictionary entry (from `app_dict()`), or `NULL`.
#' @return An HTML string.
#' @noRd
erd_node_title <- function(id, d) {
  esc <- function(x) {
    if (is.null(x) || !nzchar(x)) "" else htmltools::htmlEscape(x)
  }
  header <- sprintf("<b style='font-size:15px;'>%s</b>", esc(id))
  if (is.null(d)) {
    return(sprintf(
      "<div style='text-align:left;'>%s<br/><i>no dictionary</i></div>",
      header
    ))
  }
  meta <- paste(
    if (!is.null(d$grain)) sprintf("<i>%s</i>", esc(d$grain)),
    if (!is.null(d$key)) sprintf("<small>Key: %s</small>", esc(d$key)),
    if (!is.null(d$description)) {
      sprintf("<small>%s</small>", esc(d$description))
    },
    sep = "<br/>"
  )
  cols <- vapply(
    d$columns %||% list(),
    function(col) {
      sprintf(
        "<li><b>%s</b> <span style='color:#6b7280;'>%s</span>%s</li>",
        esc(col$name),
        esc(col$type),
        if (!is.null(col$description)) {
          sprintf("<br/><small>%s</small>", esc(col$description))
        } else {
          ""
        }
      )
    },
    character(1)
  )
  col_block <- if (length(cols)) {
    sprintf(
      paste0(
        "<hr style='margin:4px 0;'/>",
        "<ul style='margin:0;padding-left:16px;list-style:square;'>%s</ul>"
      ),
      paste(cols, collapse = "")
    )
  } else {
    ""
  }
  sprintf(
    paste0(
      "<div style='text-align:left;max-width:360px;max-height:340px;",
      "overflow-y:auto;white-space:normal;'>%s<br/>%s%s</div>"
    ),
    header,
    meta,
    col_block
  )
}

#' Build a visNetwork of the data model from the docs and dictionaries
#'
#' A standalone (no Shiny) counterpart to `erd_network()` for static documents.
#' Nodes are the tables in the ERD; edges are the documented join relationships
#' (shared-key links) parsed from `inst/data-model.md`, dashed when
#' name-guarded. Hovering a node shows that table's grain, key, description and
#' every column definition, read from `inst/dict/*.yml`; hovering an edge shows
#' the join key. Both the graph and the tooltips are generated from the files in
#' `inst/`, so the diagram stays in sync with the data model.
#'
#' @param model_path Path to the data-model doc carrying the mermaid ERD.
#'   Defaults to the packaged `inst/data-model.md` (falls back to the checkout).
#' @param dict A named list of dictionary entries, as returned by `app_dict()`.
#'   Defaults to reading the packaged `inst/dict/*.yml`.
#' @param height,width visNetwork dimensions.
#' @return A `visNetwork` htmlwidget.
#' @examples
#' \dontrun{
#' data_model_network()
#' }
#' @export
data_model_network <- function(
  model_path = erd_asset("data-model.md"),
  dict = app_dict(),
  height = "650px",
  width = "100%"
) {
  g <- parse_erd_mermaid(readLines(model_path))

  nodes <- g$nodes
  nodes$label <- nodes$id
  nodes$group <- ifelse(is.na(nodes$group), "Other", nodes$group)
  nodes$color <- unname(erd_group_colors[nodes$group])
  nodes$title <- vapply(
    nodes$id,
    function(id) erd_node_title(id, dict[[id]]),
    character(1)
  )
  nodes$font <- list(list(size = 16, face = "sans"))

  edges <- g$edges
  if (nrow(edges) > 0) {
    ns <- mapply(erd_key_namespace, edges$label, edges$dashes)
    edges$arrows <- "to"
    edges$smooth <- FALSE
    edges$color <- unname(erd_edge_palette[ns])
    edges$title <- sprintf(
      "<b>%s &rarr; %s</b><br/>Join key: %s%s",
      edges$from,
      edges$to,
      htmltools::htmlEscape(edges$label),
      ifelse(
        ns == "name_guarded",
        "<br/><i>Name-guarded, not a plain key join</i>",
        ""
      )
    )
    edges$font <- list(list(size = 13, color = "#333333", face = "sans"))
  }

  visNetwork::visNetwork(nodes, edges, height = height, width = width) |>
    visNetwork::visEdges(arrows = "to", smooth = FALSE) |>
    visNetwork::visOptions(
      highlightNearest = list(enabled = TRUE, degree = 1, hover = TRUE),
      nodesIdSelection = FALSE
    ) |>
    visNetwork::visHierarchicalLayout(
      direction = "LR",
      levelSeparation = 300,
      nodeSpacing = 120,
      sortMethod = "hubsize"
    ) |>
    visNetwork::visLegend(
      addNodes = lapply(names(erd_group_colors), function(grp) {
        list(label = grp, shape = "dot", color = unname(erd_group_colors[grp]))
      }),
      useGroups = FALSE,
      position = "right",
      zoom = FALSE
    )
}

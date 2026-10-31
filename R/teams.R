# Team- and conference-grain derived tables (plans/conferences-teams.md).
# A draftee is credited to the team of their final roster season before the
# draft (decision 0033); rates divide by players whose college career ended
# at that team, so offensive linemen (who have almost no stat lines) count.

#' Position-group labels, in display order
#'
#' @return A character vector of the nine reader-facing position groups.
#' @export
position_group_levels <- function() {
  c(
    "Quarterback",
    "Running back",
    "Receiver",
    "Tight end",
    "Offensive line",
    "Defensive line",
    "Linebacker",
    "Defensive back",
    "Special teams"
  )
}

#' Map roster position codes to reader-facing position groups
#'
#' One map shared by every post and table, so numerators and denominators
#' group positions identically. Unknown codes (`?`, `ATH`, `NA`, anything
#' new) become "Position not recorded" rather than being dropped.
#'
#' @param position Character vector of CFBD roster position codes.
#' @return Character vector of group labels (see [position_group_levels()]).
#' @export
position_group <- function(position) {
  map <- c(
    QB = "Quarterback",
    RB = "Running back",
    FB = "Running back",
    WR = "Receiver",
    TE = "Tight end",
    T = "Offensive line",
    G = "Offensive line",
    C = "Offensive line",
    OL = "Offensive line",
    OT = "Offensive line",
    DL = "Defensive line",
    DE = "Defensive line",
    DT = "Defensive line",
    NT = "Defensive line",
    EDGE = "Defensive line",
    LB = "Linebacker",
    ILB = "Linebacker",
    OLB = "Linebacker",
    DB = "Defensive back",
    S = "Defensive back",
    CB = "Defensive back",
    PK = "Special teams",
    P = "Special teams",
    LS = "Special teams",
    PR = "Special teams",
    KR = "Special teams"
  )
  out <- unname(map[position])
  out[is.na(out)] <- "Position not recorded"
  out
}

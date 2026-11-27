involvement_plays <- function() {
  tibble::tibble(
    id = c("1", "2", "3"),
    offense = "A",
    ppa = c(-0.5, 2, NA),
    playText = c(
      "(14:44) Shotgun #3 N.Frazier rush middle for 3 yards gain to the MIZ04 (#95 J.Marshall)",
      paste0(
        "(15:00) #14 G.Stockton pass complete short right to #81 C.Dandridge Jr. ",
        "caught at MIZ46, for 26 yards to the MIZ37 (#21 J.Florence; #3 Q.Johnson), ",
        "1ST DOWN. #7 K.Louidor-Faustin injured on the play"
      ),
      "(03:00) #3 N.Frazier rush left for 2 yards"
    )
  )
}

involvement_directory <- function() {
  tibble::tibble(
    playerId = c("p3", "q3", "p14", "p81", "b95", "b21", "a95", "b7"),
    team = c("A", "A", "A", "A", "B", "B", "A", "B"),
    jersey = c(3L, 3L, 14L, 81L, 95L, 21L, 95L, 7L),
    player = c(
      "Nate Frazier",
      "Quintavius Johnson",
      "Gunner Stockton",
      "Craig Dandridge",
      "Jalen Marshall",
      "Jahlil Florence",
      "Nnamdi Ogboko",
      "Khalil Louidor-Faustin"
    )
  )
}

test_that("play_text_mentions labels roles and drops injured players", {
  m <- play_text_mentions(involvement_plays())
  expect_equal(
    m$text_name[m$id == "2"],
    c("G.Stockton", "C.Dandridge Jr.", "J.Florence", "Q.Johnson")
  )
  expect_equal(
    m$role[m$id == "2"],
    c("Ball carrier or passer", "Target", "Tackle", "Tackle")
  )
  expect_equal(m$role[m$id == "1"], c("Ball carrier or passer", "Tackle"))
  expect_false("K.Louidor-Faustin" %in% m$text_name)
})

test_that("play_text_mentions ignores extra points and overturned text", {
  m <- play_text_mentions(tibble::tibble(
    id = c("1", "2"),
    playText = c(
      paste0(
        "(14:03) #3 N.Frazier rush left for 4 yards gain to the MIZ00 TOUCHDOWN, ",
        "clock 13:59 #91 P.Woodring kick attempt good (H: #14 G.Stockton, LS: #51 W.Snellings)"
      ),
      paste0(
        "(03:05) #14 G.Stockton pass incomplete short left broken up by #10 D.Hopkins. ",
        "CALL OVERTURNED. (Original Play: (03:05) #14 G.Stockton rush left ",
        "recovered by MIZ #7 K.Louidor-Faustin at UGA02)"
      )
    )
  ))
  expect_equal(m$text_name[m$id == "1"], "N.Frazier")
  expect_equal(m$text_name[m$id == "2"], c("G.Stockton", "D.Hopkins"))
  expect_equal(m$role[m$id == "2"], c("Ball carrier or passer", "Pass breakup"))
})

test_that("match_play_mentions needs jersey and surname to agree", {
  m <- play_text_mentions(involvement_plays()) |>
    match_play_mentions(involvement_directory())
  # #3 is two Team A players; the surname picks the right one
  expect_equal(m$playerId[m$text_name == "Q.Johnson"], "q3")
  expect_equal(unique(m$playerId[m$text_name == "N.Frazier"]), "p3")
  # #95 is on both teams; only Marshall's surname matches
  expect_equal(m$playerId[m$text_name == "J.Marshall"], "b95")
  expect_equal(m$team[m$text_name == "J.Marshall"], "B")
  # the generational suffix does not block a match
  expect_equal(m$playerId[m$text_name == "C.Dandridge Jr."], "p81")
})

test_that("match_play_mentions leaves unknown and ambiguous mentions NA", {
  dir <- involvement_directory() |>
    dplyr::bind_rows(tibble::tibble(
      playerId = "x95",
      team = "A",
      jersey = 95L,
      player = "Joe Marshall"
    ))
  m <- tibble::tibble(
    id = c("1", "1"),
    jersey = c(95L, 44L),
    text_name = c("J.Marshall", "Z.Nobody"),
    role = "Tackle"
  ) |>
    match_play_mentions(dir)
  expect_true(all(is.na(m$playerId)))
  expect_equal(nrow(m), 2L)
})

test_that("build_play_involvement adds text-only players and splits EPA by side", {
  plays <- involvement_plays()
  m <- play_text_mentions(plays) |> match_play_mentions(involvement_directory())
  log <- tibble::tibble(
    playId = c("1", "2", "2", "2", "2"),
    athleteId = c("p3", "p14", "p14", "p81", "p81"),
    team = "A",
    statType = c("Rush", "Completion", "Touchdown", "Reception", "Target")
  )
  inv <- build_play_involvement(plays, log, m)
  # the NA-ppa play is dropped; each (play, player) appears once
  expect_false("3" %in% inv$id)
  expect_equal(anyDuplicated(inv[c("id", "playerId")]), 0L)
  marshall <- inv[inv$playerId == "b95", ]
  expect_equal(marshall$source, "Play text")
  expect_equal(marshall$side, "Defense")
  expect_equal(marshall$share, 0.5)
  expect_equal(
    inv$source[inv$id == "1" & inv$playerId == "p3"],
    "Play-stats log"
  )
  expect_equal(inv$roles[inv$id == "2" & inv$playerId == "p81"], "Target")
  # each side's shares add up to the play's EPA from that side
  sums <- inv |>
    dplyr::summarise(s = sum(share), .by = c(id, side)) |>
    dplyr::arrange(id, side)
  expect_equal(sums$s, c(0.5, -0.5, -2, 2))
})

test_that("match_play_mentions searches only the rows sharing the by columns", {
  dir <- tibble::tibble(
    gameId = c(1L, 2L),
    playerId = c("a95", "c95"),
    team = c("B", "C"),
    jersey = 95L,
    player = c("Jalen Marshall", "Jim Marshall")
  )
  m <- tibble::tibble(
    id = c("1", "2"),
    gameId = c(1L, 2L),
    jersey = 95L,
    text_name = "J.Marshall",
    role = "Tackle"
  )
  # two J.Marshall #95s in the directory, but one per game
  expect_equal(
    match_play_mentions(m, dir, by = "gameId")$playerId,
    c("a95", "c95")
  )
  expect_true(all(is.na(match_play_mentions(m, dir)$playerId)))
})

test_that("play_mention_directory lists each game's two rosters by name", {
  roster <- tibble::tibble(
    playerId = c("a1", "a1", "b1", "c1", "b2"),
    season = c(2025L, 2026L, 2026L, 2026L, 2026L),
    team = c("A", "A", "B", "C", "B"),
    jersey = c(5L, 5L, 9L, 5L, NA),
    first_name = c("Al", "Al", "Bo", "Cy", "Ed"),
    last_name = c("Able", "Able", "Baker", "Cole", "Dunn")
  )
  games <- tibble::tibble(
    id = 10L,
    season = 2026L,
    homeTeam = "A",
    awayTeam = "B"
  )
  d <- play_mention_directory(roster, games)
  # only 2026 A and B players, and the jerseyless one is dropped
  expect_equal(sort(d$playerId), c("a1", "b1"))
  expect_equal(d$player[d$playerId == "b1"], "Bo Baker")
  expect_equal(unique(d$gameId), 10L)
})

test_that("play_text_players adds resolved players the log leaves out", {
  plays <- involvement_plays() |> dplyr::mutate(gameId = 1L)
  dir <- involvement_directory() |> dplyr::mutate(gameId = 1L)
  log <- tibble::tibble(
    playId = c("1", "2", "2"),
    athleteId = c("p3", "p14", "p81")
  )
  tp <- play_text_players(plays, log, dir)
  # the log already names the ball carriers and the target
  expect_equal(
    tp$playerId[order(tp$id, tp$playerId)],
    c("b95", "b21", "q3", "p3")
  )
  expect_equal(anyDuplicated(tp[c("id", "playerId")]), 0L)
  expect_equal(tp$roles[tp$playerId == "b95"], "Tackle")
  expect_equal(tp$player[tp$playerId == "b21"], "Jahlil Florence")
  expect_equal(tp$team[tp$playerId == "b95"], "B")
  # the injured player is never a chip
  expect_false("b7" %in% tp$playerId)
})

test_that("contract_explorer_text_players passes, and catches repeats of the log", {
  plays <- involvement_plays() |> dplyr::mutate(gameId = 1L)
  dir <- involvement_directory() |> dplyr::mutate(gameId = 1L)
  log <- tibble::tibble(playId = "1", athleteId = "p3")
  tp <- play_text_players(plays, log, dir)
  expect_true(pointblank::all_passed(
    contract_explorer_text_players(tp, plays, log, stop_on_fail = FALSE)
  ))
  dup_log <- tibble::tibble(playId = "1", athleteId = "b95")
  expect_false(pointblank::all_passed(
    contract_explorer_text_players(tp, plays, dup_log, stop_on_fail = FALSE)
  ))
  expect_error(
    contract_explorer_text_players(rbind(tp, tp[1, ]), plays, log),
    "explorer_text_players"
  )
})

test_that("play_text_mentions names the kicking roles and undotted suffixes", {
  m <- play_text_mentions(tibble::tibble(
    id = c("1", "2", "3"),
    playText = c(
      "#44 G.Spetic kickoff 65 yards to the LSU00, touchback",
      paste0(
        "#91 P.Woodring field goal attempt from 32 yards GOOD ",
        "(H: #37 T.Manship, LS: #51 W.Snellings), clock 06:59"
      ),
      "#7 R.Moore Jr rush left for 2 yards gain to the X10 (#9 A.Blocker)"
    )
  ))
  expect_equal(m$role[m$id == "1"], "Kicker or punter")
  expect_equal(
    m$role[m$id == "2"],
    c("Kicker or punter", "Holder", "Long snapper")
  )
  expect_equal(m$text_name[m$id == "3"], c("R.Moore Jr", "A.Blocker"))
  expect_equal(m$role[m$id == "3"], c("Ball carrier or passer", "Tackle"))
  expect_equal(name_surname("R.Moore Jr"), "moore")
})

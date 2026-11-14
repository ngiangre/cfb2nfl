import {test} from "node:test";
import assert from "node:assert/strict";
import {
  formatRecord, teamGames, effectiveGame, landscapePanels, timelineFor, parsePlayers,
  teamSeasonRow, teamGroups, conferenceAverages, mapPoints, mapTitle, shouldLoadPlays, stepPlay, playWhen, playAnnouncement, recordShares
} from "./teams.js";

const games = [
  {game_id: 2, team_id: 251, start: "2025-09-08T00:00:00.000Z", has_plays: true},
  {game_id: 1, team_id: 251, start: "2025-09-01T00:00:00.000Z", has_plays: true},
  {game_id: 3, team_id: 251, start: "2025-09-15T00:00:00.000Z", has_plays: false},
  {game_id: 9, team_id: 333, start: "2025-09-01T00:00:00.000Z", has_plays: true}
];

test("formatRecord shows ties only when there are some", () => {
  assert.equal(formatRecord({wins: 9, losses: 3, ties: 0}), "9-3");
  assert.equal(formatRecord({wins: 5, losses: 5, ties: 1}), "5-5-1");
});

test("teamGames keeps one team's games in kickoff order", () => {
  assert.deepEqual(teamGames(games, 251).map(g => g.game_id), [1, 2, 3]);
});

test("effectiveGame keeps a valid pick, else the latest game with plays", () => {
  const tg = teamGames(games, 251);
  assert.equal(effectiveGame(1, tg), 1);
  assert.equal(effectiveGame(999, tg), 2);
  assert.equal(effectiveGame(null, [{game_id: 5, has_plays: false}]), 5);
  assert.equal(effectiveGame(null, []), null);
});

test("landscapePanels groups by the season's conference, Power first", () => {
  const ts = [
    {team_id: 1, season: 2025, conference: "SEC", classification: "fbs", tier: 3, elo_end: 1700, win_pct: 0.8},
    {team_id: 1, season: 2024, conference: "Big 12", classification: "fbs", tier: 3, elo_end: 1650, win_pct: 0.7},
    {team_id: 2, season: 2025, conference: "Sun Belt", classification: "fbs", tier: 2, elo_end: 1500, win_pct: 0.5},
    {team_id: 3, season: 2025, conference: "SWAC", classification: "fcs", tier: 1, elo_end: null, win_pct: 0.6}
  ];
  const fbs = landscapePanels(ts, 2025, "fbs");
  assert.deepEqual(fbs.map(p => p.conference), ["SEC", "Sun Belt"]);
  assert.equal(fbs[0].metric, "elo_end");
  // Team 1's 2024 Big 12 season stays on its SEC line.
  assert.deepEqual(fbs[0].rows.map(d => d.season).sort(), [2024, 2025]);
  const fcs = landscapePanels(ts, 2025, "fcs");
  assert.equal(fcs[0].metric, "win_pct");
  assert.deepEqual(fcs[0].teamIds, [3]);
});

test("timelineFor flips margin and PPA for the away team and drops untimed plays", () => {
  const plays = [
    {elapsed: 0, home_margin: 0, home_cum_ppa: 0.5, home_score: 0, away_score: 0},
    {elapsed: null, home_margin: 7, home_cum_ppa: 1, home_score: 7, away_score: 0},
    {elapsed: 600, home_margin: 7, home_cum_ppa: 2.5, home_score: 7, away_score: 0}
  ];
  const home = timelineFor(plays, true);
  assert.deepEqual(home.map(d => d.margin), [0, 7]);
  assert.deepEqual(home.map(d => d.team_score), [0, 7]);
  const away = timelineFor(plays, false);
  assert.deepEqual(away.map(d => d.margin), [0, -7]);
  assert.deepEqual(away.map(d => d.cum_ppa), [-0.5, -2.5]);
  assert.deepEqual(away.map(d => d.opp_score), [0, 7]);
});

test("parsePlayers reads the JSON array and tolerates nothing", () => {
  assert.deepEqual(parsePlayers('[{"id":"p1","name":"A","stat":"Rush"}]'), [{id: "p1", name: "A", stat: "Rush"}]);
  assert.deepEqual(parsePlayers(null), []);
  assert.deepEqual(parsePlayers("not json"), []);
});

const ts = [
  {team_id: 333, season: 2024, conference: "SEC", classification: "fbs", tier: 3, wins: 9, losses: 4, ties: 0, win_pct: 0.692, elo_end: 1800},
  {team_id: 251, season: 2024, conference: "SEC", classification: "fbs", tier: 3, wins: 13, losses: 3, ties: 0, win_pct: 0.813, elo_end: 1900},
  {team_id: 2, season: 2024, conference: "SEC", classification: "fbs", tier: 3, wins: 5, losses: 7, ties: 0, win_pct: 0.417, elo_end: 1500},
  {team_id: 251, season: 2023, conference: "Big 12", classification: "fbs", tier: 3, wins: 12, losses: 2, ties: 0, win_pct: 0.857, elo_end: 1850},
  {team_id: 87, season: 2024, conference: "FBS Independents", classification: "fbs", tier: 2, wins: 14, losses: 2, ties: 0, win_pct: 0.875, elo_end: 1950},
  {team_id: 149, season: 2024, conference: "Big Sky", classification: "fcs", tier: 1, wins: 10, losses: 3, ties: 0, win_pct: 0.769, elo_end: null}
];
const tms = [
  {team_id: 333, team: "Alabama", color: "#9e1b32", latitude: 33.208, longitude: -87.55, city: "Tuscaloosa", state: "AL", venue: "Bryant-Denny Stadium"},
  {team_id: 251, team: "Texas", color: "#bf5700", latitude: 30.284, longitude: -97.733, city: "Austin", state: "TX", venue: null},
  {team_id: 2, team: "Auburn", color: "#0c2340", latitude: null, longitude: null, city: null, state: null, venue: null},
  {team_id: 87, team: "Notre Dame", color: "#0c2340", latitude: 41.698, longitude: -86.234, city: "South Bend", state: "IN", venue: "Notre Dame Stadium"},
  {team_id: 149, team: "Montana", color: "#70003c", latitude: 46.86, longitude: -113.99, city: "Missoula", state: "MT", venue: null},
  {team_id: 5, team: "Defunct", color: "#6b7280", latitude: null, longitude: null}
];

test("teamSeasonRow finds the team's season, or null", () => {
  assert.equal(teamSeasonRow(ts, 251, 2023).conference, "Big 12");
  assert.equal(teamSeasonRow(ts, 251, 2010), null);
});

test("teamGroups groups the season by conference, best record first", () => {
  const groups = teamGroups(ts, tms, 2024);
  assert.deepEqual(groups.map(g => g.label), ["SEC", "FBS Independents", "Big Sky", "Did not play in 2024"]);
  assert.deepEqual(groups[0].options.map(o => o.label), ["Texas (13-3)", "Alabama (9-4)", "Auburn (5-7)"]);
  // Every team stays selectable in any season.
  assert.deepEqual(groups.at(-1).options, [{team_id: 5, label: "Defunct"}]);
  assert.equal(groups.flatMap(g => g.options).length, tms.length);
});

test("conferenceAverages follows the team's conference each season", () => {
  assert.deepEqual(conferenceAverages(ts, 251), [
    {season: 2023, conference: "Big 12", members: 1, elo_mean: 1850, win_pct_mean: 0.857},
    {season: 2024, conference: "SEC", members: 3, elo_mean: 1733, win_pct_mean: 0.641}
  ]);
  // Independents have no conference average; FCS has win share but no Elo.
  assert.deepEqual(conferenceAverages(ts, 87), []);
  assert.equal(conferenceAverages(ts, 149)[0].elo_mean, null);
});

test("mapPoints keeps one classification's located teams for the season", () => {
  assert.deepEqual(mapPoints(tms, ts, 2024, "fbs").map(p => p.team), ["Alabama", "Notre Dame", "Texas"]);
  assert.deepEqual(mapPoints(tms, ts, 2024, "fcs").map(p => p.team), ["Montana"]);
});

test("mapTitle carries the record, conference and stadium", () => {
  const [bama, , texas] = mapPoints(tms, ts, 2024, "fbs");
  assert.equal(mapTitle(bama), "Alabama (9-4)\nSEC\nBryant-Denny Stadium, Tuscaloosa, AL");
  assert.equal(mapTitle(texas), "Texas (13-3)\nSEC\nAustin, TX");
});

test("shouldLoadPlays needs the Teams tab, a seen Game section and plays", () => {
  assert.equal(shouldLoadPlays({tab: "teams", gameInView: true, hasPlays: true}), true);
  assert.equal(shouldLoadPlays({tab: "players", gameInView: true, hasPlays: true}), false);
  assert.equal(shouldLoadPlays({tab: "teams", gameInView: false, hasPlays: true}), false);
  assert.equal(shouldLoadPlays({tab: "teams", gameInView: true, hasPlays: false}), false);
});

test("stepPlay moves one play and reports the ends instead of wrapping", () => {
  const tl = [{id: "a"}, {id: "b"}, {id: "c"}];
  assert.deepEqual(stepPlay(tl, tl[0], 1), {play: tl[1], edge: null});
  assert.deepEqual(stepPlay(tl, tl[1], -1), {play: tl[0], edge: null});
  assert.deepEqual(stepPlay(tl, tl[2], 1), {play: tl[2], edge: "last"});
  assert.deepEqual(stepPlay(tl, tl[0], -1), {play: tl[0], edge: "first"});
  assert.deepEqual(stepPlay([], null, 1), {play: null, edge: "last"});
});

test("playWhen labels regulation quarters and overtime", () => {
  assert.equal(playWhen({period: 2, clock: "7:30"}), "Q2 7:30");
  assert.equal(playWhen({period: 5, clock: "OT1"}), "OT1");
});

test("playAnnouncement reads the play for the live region", () => {
  assert.equal(
    playAnnouncement({period: 1, clock: "14:02", play_text: "Kickoff for 60 yards"}),
    "Q1 14:02: Kickoff for 60 yards"
  );
  assert.equal(playAnnouncement({period: 3, clock: "0:44", play_type: "Punt"}), "Q3 0:44: Punt");
});

test("recordShares splits each season into shares of its games, dropping empty outcomes", () => {
  const out = recordShares([{season: 2024, wins: 9, losses: 3, ties: 0}, {season: 2025, wins: 5, losses: 4, ties: 1}]);
  assert.deepEqual(out.filter(d => d.season === 2024).map(d => [d.outcome, d.n, d.share]), [["Wins", 9, 0.75], ["Losses", 3, 0.25]]);
  assert.equal(out.filter(d => d.season === 2025).reduce((a, d) => a + d.share, 0), 1);
  assert.deepEqual(recordShares([{season: 2026, wins: 0, losses: 0, ties: 0}]), []);
});

import {test} from "node:test";
import assert from "node:assert/strict";
import {formatRecord, teamGames, effectiveGame, landscapePanels, timelineFor, parsePlayers} from "./teams.js";

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

import {test} from "node:test";
import assert from "node:assert/strict";
import {
  formatRecord, teamGames, effectiveGame, landscapePanels, timelineFor, parsePlayers,
  defaultShowFcs, focusedConference, shouldLoadPlays, stepPlay, playWhen, playAnnouncement
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

test("defaultShowFcs is on only when the team is FCS in that season", () => {
  const rows = [
    {team_id: 149, season: 2026, classification: "fcs"},
    {team_id: 251, season: 2026, classification: "fbs"},
    {team_id: 251, season: 2025, classification: "fbs"}
  ];
  assert.equal(defaultShowFcs(rows, 149, 2026), true);
  assert.equal(defaultShowFcs(rows, 251, 2026), false);
  // A season the team has no row for falls back to FBS.
  assert.equal(defaultShowFcs(rows, 149, 2025), false);
});

test("focusedConference keeps the focus only while the team is in that panel", () => {
  const panels = [
    {conference: "SEC", teamIds: [251, 333]},
    {conference: "Big Sky", teamIds: [149]}
  ];
  assert.equal(focusedConference("SEC", panels, 251), "SEC");
  assert.equal(focusedConference("SEC", panels, 149), null);
  assert.equal(focusedConference(null, panels, 251), null);
  assert.equal(focusedConference("Nope", panels, 251), null);
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

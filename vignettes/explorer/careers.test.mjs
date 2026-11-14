import {test} from "node:test";
import assert from "node:assert/strict";
import {
  TIER_LABELS, DIRECTIONS, draftByTier, picksPerYear, teamPicks, longevityPoints, roundMedians,
  transferTotals, teamTransfers, nflSeasonsLabel
} from "./careers.js";

const picks = [
  {year: 2025, round: 1, overall: 1, name: "First", pos: "QB", team_id: 251, tier: 3, nfl_seasons: 2, active: true},
  {year: 2025, round: 1, overall: 32, name: "Last R1", pos: "WR", team_id: 333, tier: 3, nfl_seasons: 1, active: false},
  {year: 2025, round: 2, overall: 33, name: "Small", pos: "DL", team_id: null, tier: 1, nfl_seasons: 4, active: false},
  {year: 2025, round: 2, overall: 64, name: "Unlinked", pos: "QB", team_id: 251, tier: 2, nfl_seasons: null, active: null},
  {year: 2023, round: 1, overall: 5, name: "Older", pos: "QB", team_id: 251, tier: 3, nfl_seasons: 3, active: false}
];

test("draftByTier counts picks per draft year and tier with reader labels", () => {
  const out = draftByTier(picks);
  assert.deepEqual(out.find(d => d.year === 2025 && d.tier === 3), {year: 2025, tier: 3, label: TIER_LABELS[3], n: 2});
  assert.equal(out.reduce((a, d) => a + d.n, 0), picks.length);
});

test("picksPerYear fills every year, zero where the team had no pick", () => {
  assert.deepEqual(picksPerYear(picks, 251, [2023, 2024, 2025]), [
    {year: 2023, n: 1}, {year: 2024, n: 0}, {year: 2025, n: 2}
  ]);
});

test("teamPicks lists one team's picks in a draft in pick order", () => {
  assert.deepEqual(teamPicks(picks, 251, 2025).map(d => d.name), ["First", "Unlinked"]);
});

test("longevityPoints keeps linked picks and spreads each round by pick order", () => {
  const pts = longevityPoints(picks, {from: 2024, to: 2025, pos: "all"});
  assert.deepEqual(pts.map(d => d.name), ["First", "Last R1", "Small"]);
  const first = pts.find(d => d.name === "First"), last = pts.find(d => d.name === "Last R1");
  assert.ok(first.x < 1 && last.x > 1 && last.x < 1.5);
  assert.ok(first.x >= 0.6);
  assert.ok(pts.every(d => Math.abs(d.y - d.nfl_seasons) <= 0.3));
  assert.deepEqual(longevityPoints(picks, {from: 2023, to: 2025, pos: "QB"}).map(d => d.name), ["Older", "First"]);
});

test("roundMedians gives each round's median NFL seasons", () => {
  const pts = longevityPoints(picks, {from: 2023, to: 2025, pos: "all"});
  assert.deepEqual(roundMedians(pts), [{round: 1, median: 2, n: 3}, {round: 2, median: 4, n: 1}]);
});

test("nflSeasonsLabel says when a career is still going", () => {
  assert.equal(nflSeasonsLabel({nfl_seasons: 1, active: false}), "1 NFL season");
  assert.equal(nflSeasonsLabel({nfl_seasons: 4, active: true}), "4 NFL seasons and counting");
  assert.equal(nflSeasonsLabel({nfl_seasons: 0, active: false}), "Never on an NFL roster");
});

const transfers = [
  {season: 2024, team_id: 251, team: "Texas", direction: "up", n: 3},
  {season: 2024, team_id: 333, team: "Alabama", direction: "up", n: 2},
  {season: 2024, team_id: null, team: "Ferris State", direction: "down", n: 1},
  {season: 2025, team_id: 251, team: "Texas", direction: "lateral", n: 4}
];

test("transferTotals sums arrivals over teams, in direction order", () => {
  assert.deepEqual(transferTotals(transfers), [
    {season: 2024, direction: "up", label: DIRECTIONS[0].label, n: 5},
    {season: 2024, direction: "down", label: DIRECTIONS[2].label, n: 1},
    {season: 2025, direction: "lateral", label: DIRECTIONS[1].label, n: 4}
  ]);
});

test("teamTransfers keeps one team's arrivals", () => {
  assert.deepEqual(teamTransfers(transfers, 251).map(d => [d.season, d.n]), [[2024, 3], [2025, 4]]);
});

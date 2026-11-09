import {test} from "node:test";
import assert from "node:assert/strict";
import {
  positionGroups, resolvePlayersPos, positionStats, formatStat, ordinal, swarmRows,
  beeswarm, careerRows, seasonForPlayer, careerPercentiles, searchPlayers, groupPlural
} from "./players.js";

const meta = {
  positions: [
    {pos: "QB", group: "Quarterback", key: "passing_yds", label: "Passing yards", format: "int"},
    {pos: "QB", group: "Quarterback", key: "passing_ypa", label: "Yards per attempt", format: "dec1"},
    {pos: "WR", group: "Receiver", key: "receiving_yds", label: "Receiving yards", format: "int"}
  ]
};

const rows = [
  {player_id: "1", name: "Joe Burrow", season: 2018, tier: 3, team: null, team_id: 99, passing_yds: 2894, passing_yds_pct: 93, passing_ypa_pct: 70},
  {player_id: "1", name: "Joe Burrow", season: 2019, tier: 3, team: null, team_id: 99, passing_yds: 5671, passing_yds_pct: 100, passing_ypa_pct: null},
  {player_id: "2", name: "Small Schooler", season: 2019, tier: 1, team: "Ferris State", team_id: null, passing_yds: 3000, passing_yds_pct: 95, passing_ypa_pct: 90},
  {player_id: "3", name: "Backup", season: 2019, tier: 2, team: null, team_id: 7, passing_yds: 20, passing_yds_pct: null, passing_ypa_pct: null}
];

test("positionGroups lists each group once, in meta order", () => {
  assert.deepEqual(positionGroups(meta), [{pos: "QB", group: "Quarterback"}, {pos: "WR", group: "Receiver"}]);
});

test("resolvePlayersPos falls back to QB for OL and junk", () => {
  assert.equal(resolvePlayersPos("WR", meta), "WR");
  assert.equal(resolvePlayersPos("OL", meta), "QB");
  assert.equal(resolvePlayersPos(null, meta), "QB");
});

test("positionStats keeps one group's stats, default first", () => {
  assert.deepEqual(positionStats(meta, "QB").map(s => s.key), ["passing_yds", "passing_ypa"]);
});

test("formatStat writes counts, decimals, rates and a dash for missing", () => {
  assert.equal(formatStat(5671, "int"), "5,671");
  assert.equal(formatStat(7.456, "dec1"), "7.5");
  assert.equal(formatStat(0.653, "pct"), "65%");
  assert.equal(formatStat(null, "int"), "–");
});

test("ordinal handles the teens", () => {
  assert.deepEqual([1, 2, 3, 4, 11, 12, 13, 21, 93, 100].map(ordinal),
    ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "93rd", "100th"]);
});

test("swarmRows keeps ranked players in the chosen tiers, plus the selected one", () => {
  const base = {season: 2019, key: "passing_yds", tiers: [3, 2], player: null};
  assert.deepEqual(swarmRows(rows, base).map(d => d.player_id), ["1"]);
  assert.deepEqual(swarmRows(rows, {...base, player: "2"}).map(d => d.player_id), ["1", "2"]);
  assert.deepEqual(swarmRows(rows, {...base, tiers: [1]}).map(d => d.player_id), ["2"]);
});

test("beeswarm keeps dots apart and near the axis", () => {
  const xs = [0, 0, 0, 50];
  const ys = beeswarm(xs, 5);
  assert.equal(ys[3], 0);
  assert.equal(ys.filter(y => y === 0).length, 2);
  for (let i = 0; i < xs.length; i++) {
    for (let j = i + 1; j < xs.length; j++) {
      const d = Math.hypot(xs[i] - xs[j], ys[i] - ys[j]);
      assert.ok(d >= 10 - 1e-6, `dots ${i} and ${j} overlap`);
    }
  }
});

test("beeswarm spreads a tall tie across the band instead of growing", () => {
  const xs = new Array(200).fill(10);
  const ys = beeswarm(xs, 4, 40);
  assert.ok(ys.every(y => Math.abs(y) <= 40));
  assert.equal(new Set(ys).size > 50, true);
});

test("careerRows sorts one player's seasons", () => {
  const c = careerRows([rows[1], rows[0], rows[2]], "1");
  assert.deepEqual(c.map(d => d.season), [2018, 2019]);
});

test("seasonForPlayer keeps the season if the player has it, else their latest", () => {
  const c = careerRows(rows, "1");
  assert.equal(seasonForPlayer(c, 2018), 2018);
  assert.equal(seasonForPlayer(c, 2026), 2019);
  assert.equal(seasonForPlayer([], 2026), 2026);
});

test("careerPercentiles leaves a gap, not a zero", () => {
  const long = careerPercentiles(careerRows(rows, "1"), positionStats(meta, "QB"));
  assert.equal(long.length, 4);
  assert.deepEqual(long.filter(d => d.stat === "Yards per attempt").map(d => d.pct), [70, null]);
});

test("searchPlayers matches name starts first, then school, one row per player", () => {
  const team = d => d.team ?? (d.team_id === 99 ? "LSU" : "Other");
  const byName = searchPlayers(rows, "bur", team);
  assert.deepEqual(byName.map(d => [d.player_id, d.season]), [["1", 2019]]);
  assert.deepEqual(searchPlayers(rows, "ferris", team).map(d => d.player_id), ["2"]);
  assert.deepEqual(searchPlayers(rows, "lsu", team).map(d => d.player_id), ["1"]);
  assert.deepEqual(searchPlayers(rows, "b", team), []);
});

test("groupPlural reads naturally", () => {
  assert.equal(groupPlural("Quarterback"), "Quarterbacks");
  assert.equal(groupPlural("Defensive line"), "Defensive linemen");
  assert.equal(groupPlural("Special teams"), "Specialists");
});

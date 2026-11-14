import {test} from "node:test";
import assert from "node:assert/strict";
import {mapPoints, mapConferences, resolveMapConference, spreadRows, spreadSummary, mapTitle} from "./map.js";

const located = [
  {team_id: 130, latitude: 42.27, longitude: -83.75, city: "Ann Arbor", state: "MI", venue: "Michigan Stadium"},
  {team_id: 26, latitude: 34.16, longitude: -118.17, city: "Pasadena", state: "CA", venue: "Rose Bowl"},
  {team_id: 2000, latitude: 32.45, longitude: -99.74, city: "Abilene", state: "TX", venue: null}
];
const teamById = new Map([
  [130, {team: "Michigan", color: "#00274c"}],
  [26, {team: "UCLA", color: "#2d68c4"}],
  [2000, {team: "Abilene Christian", color: "#592d82"}]
]);
const teamSeason = [
  {team_id: 130, season: 2024, conference: "Big Ten", classification: "fbs", wins: 8, losses: 5, ties: 0},
  {team_id: 26, season: 2024, conference: "Big Ten", classification: "fbs", wins: 5, losses: 7, ties: 0},
  {team_id: 26, season: 2023, conference: "Pac-12", classification: "fbs", wins: 8, losses: 5, ties: 0},
  {team_id: 2000, season: 2024, conference: "UAC", classification: "fcs", wins: 7, losses: 4, ties: 0},
  // No home stadium: left off the map.
  {team_id: 999, season: 2024, conference: "Big Ten", classification: "fbs", wins: 1, losses: 11, ties: 0}
];

test("mapPoints places the season's located teams with that season's conference", () => {
  const fbs = mapPoints(located, teamSeason, teamById, 2024, false);
  assert.deepEqual(fbs.map(p => p.team), ["Michigan", "UCLA"]);
  assert.equal(fbs.find(p => p.team === "UCLA").conference, "Big Ten");
  assert.equal(mapPoints(located, teamSeason, teamById, 2023, false)[0].conference, "Pac-12");
  assert.equal(mapPoints(located, teamSeason, teamById, 2024, true).length, 3);
});

test("mapConferences lists FBS conferences before FCS", () => {
  assert.deepEqual(mapConferences(mapPoints(located, teamSeason, teamById, 2024, true)), ["Big Ten", "UAC"]);
});

test("resolveMapConference keeps a valid pick and falls back to the team's conference", () => {
  const confs = ["Big Ten", "SEC"];
  assert.equal(resolveMapConference("SEC", confs, "Big Ten"), "SEC");
  assert.equal(resolveMapConference("Pac-12", confs, "Big Ten"), "Big Ten");
  assert.equal(resolveMapConference(null, confs, "UAC"), "Big Ten");
  assert.equal(resolveMapConference(null, [], "UAC"), null);
});

const spread = [
  {season: 2023, conference: "Big Ten", classification: "fbs", members: 14, mapped: 14, spread_miles: 424},
  {season: 2024, conference: "Big Ten", classification: "fbs", members: 18, mapped: 18, spread_miles: 954},
  {season: 2024, conference: "UAC", classification: "fcs", members: 9, mapped: 0, spread_miles: null}
];

test("spreadRows keeps one classification's measured spreads", () => {
  assert.equal(spreadRows(spread, "fbs").length, 2);
  assert.equal(spreadRows(spread, "fcs").length, 0);
});

test("spreadSummary compares the season with the one before", () => {
  assert.equal(
    spreadSummary(spread, "Big Ten", 2024),
    "In 2024, two Big Ten home stadiums sit 954 miles apart on average (18 members). In 2023 it was 424 miles."
  );
  assert.match(spreadSummary(spread, "Big Ten", 2023), /424 miles apart on average \(14 members\)\.$/);
  assert.equal(spreadSummary(spread, "UAC", 2024), null);
});

test("mapTitle carries record, conference and the stadium's place", () => {
  const p = mapPoints(located, teamSeason, teamById, 2024, true).find(d => d.team === "Abilene Christian");
  assert.equal(mapTitle(p), "Abilene Christian (7-4)\nUAC\nAbilene, TX");
});

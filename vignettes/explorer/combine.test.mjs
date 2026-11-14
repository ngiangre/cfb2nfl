import {test} from "node:test";
import assert from "node:assert/strict";
import {
  columnsToRows, resolveCombinePos, combinePoints, missingCount, formatMeasure,
  canOpenPlayer, combineTraces, regionCuts, regionBin, inRegion, regionActive
} from "./combine.js";

const rows = columnsToRows({
  season: [2020, 2020, 2021, 2020],
  name: ["Joe Burrow", "Tall", "Later", "Lineman"],
  school: ["LSU", "Texas", "Texas", "Texas"],
  pos: ["QB", "QB", "QB", "OL"],
  height: [75, 78, 74, 78],
  weight: [221, 230, 210, 315],
  forty: [null, 4.8, 4.6, 5.2],
  outcome: ["r1", "undrafted", "pending", "r4_7"],
  outcome_label: ["Drafted R1 #1 (Cincinnati)", "Not drafted", "Draft pending", "Drafted R5 #150 (Denver)"],
  athlete_id: ["3915511", null, "9", "8"],
  players_pos: ["QB", null, "QB", null]
});

const measures = [
  {key: "height", label: "Height", unit: "in"},
  {key: "weight", label: "Weight", unit: "lb"},
  {key: "forty", label: "40-yard dash", unit: "s"}
];
const outcomes = [
  {outcome: "r1", label: "Drafted, round 1"},
  {outcome: "undrafted", label: "Not drafted"},
  {outcome: "pending", label: "Draft pending"}
];

test("columnsToRows turns columns into row objects", () => {
  assert.equal(rows.length, 4);
  assert.deepEqual(rows[0].name, "Joe Burrow");
  assert.equal(columnsToRows({}).length, 0);
});

test("resolveCombinePos keeps linemen and falls back to QB", () => {
  const meta = {combine_groups: [{pos: "QB"}, {pos: "OL"}]};
  assert.equal(resolveCombinePos("OL", meta), "OL");
  assert.equal(resolveCombinePos("ZZ", meta), "QB");
});

test("combinePoints needs every axis and respects group and classes", () => {
  const axes = ["height", "weight", "forty"];
  assert.deepEqual(combinePoints(rows, {pos: "QB", from: 2020, to: 2021, axes}).map(d => d.name), ["Tall", "Later"]);
  assert.deepEqual(combinePoints(rows, {pos: "QB", from: 2021, to: 2020, axes}).map(d => d.name), ["Tall", "Later"]);
  assert.deepEqual(combinePoints(rows, {pos: "QB", from: 2020, to: 2020, axes: ["height", "weight"]}).map(d => d.name), ["Joe Burrow", "Tall"]);
  assert.equal(missingCount(rows, {pos: "QB", from: 2020, to: 2021, axes}), 1);
});

test("formatMeasure writes feet and inches, seconds and units", () => {
  assert.equal(formatMeasure(75, measures[0]), "6'3\"");
  assert.equal(formatMeasure(4.6, measures[2]), "4.60 s");
  assert.equal(formatMeasure(221, measures[1]), "221 lb");
  assert.equal(formatMeasure(null, measures[1]), "–");
});

test("canOpenPlayer needs a CFBD id and a Players group", () => {
  assert.equal(canOpenPlayer(rows[0]), true);
  assert.equal(canOpenPlayer(rows[1]), false);
  assert.equal(canOpenPlayer(rows[3]), false);
});

test("combineTraces makes one trace per outcome present, plus the selected player", () => {
  const points = combinePoints(rows, {pos: "QB", from: 2020, to: 2021, axes: ["height", "weight", "forty"]});
  const colors = new Map([["r1", "#000"], ["undrafted", "#999"], ["pending", "#0f0"]]);
  const t = combineTraces(points, {axes: ["height", "weight", "forty"], measures, outcomes, colors, selected: "9"});
  assert.deepEqual(t.map(d => d.name), ["Not drafted (N=1)", "Draft pending (N=1)", "Later"]);
  assert.deepEqual(t[0].customdata, [0]);
  assert.deepEqual(t[1].x, [74]);
  assert.equal(t[2].marker.size, 9);
  assert.match(t[0].text[0], /40-yard dash: 4.80 s/);
  assert.equal(combineTraces(points, {axes: ["height", "weight", "forty"], measures, outcomes, colors, selected: null}).length, 2);
});

const field = Array.from({length: 9}, (_, i) => ({
  name: `P${i}`, school: "S", season: 2020, combine_pos: "WR", outcome: i % 2 ? "r1" : "undrafted",
  outcome_label: "x", height: 70 + i, weight: 180 + i, forty: 4.3 + i / 100
}));
const axes = ["height", "weight", "forty"];

test("regionCuts splits each axis into thirds of the shown invitees", () => {
  const cuts = regionCuts(field, axes);
  assert.deepEqual(cuts[0], [70, 72.66666666666667, 75.33333333333333, 78]);
  assert.deepEqual([0, 1, 2].map(i => field.filter(d => regionBin(d.height, cuts[0]) === i).length), [3, 3, 3]);
  assert.equal(regionBin(70, cuts[0]), 0);
  assert.equal(regionBin(78, cuts[0]), 2);
});

test("inRegion keeps players in every picked third; Any (null) keeps the axis", () => {
  const cuts = regionCuts(field, axes);
  assert.equal(regionActive([null, null, null]), false);
  assert.equal(field.filter(d => inRegion(d, axes, cuts, [null, null, null])).length, 9);
  assert.deepEqual(field.filter(d => inRegion(d, axes, cuts, [2, null, null])).map(d => d.name), ["P6", "P7", "P8"]);
  assert.equal(field.filter(d => inRegion(d, axes, cuts, [2, 0, null])).length, 0);
});

test("combineTraces fades everyone outside the region and counts both", () => {
  const colors = new Map([["r1", "#000"], ["undrafted", "#999"]]);
  const outcomes2 = [{outcome: "r1", label: "Drafted, round 1"}, {outcome: "undrafted", label: "Not drafted"}];
  const cuts = regionCuts(field, axes);
  const t = combineTraces(field, {axes, measures, outcomes: outcomes2, colors, selected: null, region: [2, null, null], cuts});
  assert.deepEqual(t.map(d => d.name), ["Everyone else (N=6)", "Drafted, round 1 (N=1)", "Not drafted (N=2)"]);
  // Taps on faded points still find their player.
  assert.deepEqual(t[0].customdata, [0, 1, 2, 3, 4, 5]);
  assert.ok(t[0].marker.opacity < 0.5);
  assert.equal(t[1].marker.line.width, 1);
});

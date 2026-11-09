import {test} from "node:test";
import assert from "node:assert/strict";
import {
  columnsToRows, resolveCombinePos, combinePoints, missingCount, formatMeasure,
  canOpenPlayer, combineTraces
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
  assert.deepEqual(t.map(d => d.name), ["Not drafted", "Draft pending", "Later"]);
  assert.deepEqual(t[0].customdata, [0]);
  assert.deepEqual(t[1].x, [74]);
  assert.equal(t[2].marker.size, 9);
  assert.match(t[0].text[0], /40-yard dash: 4.80 s/);
  assert.equal(combineTraces(points, {axes: ["height", "weight", "forty"], measures, outcomes, colors, selected: null}).length, 2);
});

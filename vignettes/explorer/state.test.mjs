import {test} from "node:test";
import assert from "node:assert/strict";
import {TABS, parseHash, toHash, resolveSeason, resolveTeam} from "./state.js";

const meta = {default_season: 2026, seasons: [2024, 2025, 2026], default_team: 251};

test("empty hash gives the defaults", () => {
  assert.deepEqual(parseHash("", meta), {
    tab: "teams", season: 2026, team: 251, game: null, pos: "QB", player: null
  });
});

test("ids parse as integers, player stays a string", () => {
  const s = parseHash("#tab=players&season=2025&team=333&game=401752677&pos=WR&player=4870906", meta);
  assert.equal(s.tab, "players");
  assert.equal(s.season, 2025);
  assert.equal(s.team, 333);
  assert.equal(s.game, 401752677);
  assert.equal(s.pos, "WR");
  assert.equal(s.player, "4870906");
});

test("bad values fall back to defaults", () => {
  const s = parseHash("#tab=nope&season=1999&team=abc&game=1.5", meta);
  assert.equal(s.tab, "teams");
  assert.equal(s.season, 2026);
  assert.equal(s.team, 251);
  assert.equal(s.game, null);
});

test("toHash writes every non-null key in a fixed order", () => {
  const s = {tab: "teams", season: 2026, team: 251, game: null, pos: "QB", player: null};
  assert.equal(toHash(s), "#tab=teams&season=2026&team=251&pos=QB");
  assert.deepEqual(parseHash(toHash({...s, game: 7}), meta), {...s, game: 7});
});

test("resolveSeason and resolveTeam", () => {
  assert.equal(resolveSeason(2025, meta), 2025);
  assert.equal(resolveSeason(2010, meta), 2026);
  const teams = [{team_id: 251}, {team_id: 333}];
  assert.equal(resolveTeam(333, teams, meta), 333);
  assert.equal(resolveTeam(9, teams, meta), 251);
});

test("tabs are the shell's four, Teams first", () => {
  assert.deepEqual(TABS.map(t => t.key), ["teams", "players", "combine", "careers"]);
});

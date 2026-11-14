import {test} from "node:test";
import assert from "node:assert/strict";
import {sourceLine, errorCard, escapeHtml, loadOnce, axisRoom} from "./ui.js";

test("sourceLine links each table to its Data page anchor", () => {
  assert.equal(
    sourceLine(["games", "teams"]),
    '<p class="explorer-source">Data: <a href="data.html#table-games"><code>games</code></a>, ' +
      '<a href="data.html#table-teams"><code>teams</code></a></p>'
  );
});

test("errorCard names what failed and offers a retry button", () => {
  const html = errorCard("team seasons");
  assert.match(html, /role="alert"/);
  assert.match(html, /Couldn't load team seasons\./);
  assert.match(html, /<button type="button" class="explorer-retry">Retry<\/button>/);
});

test("escapeHtml escapes markup", () => {
  assert.equal(escapeHtml(`<a "b">&`), "&lt;a &quot;b&quot;&gt;&amp;");
});

test("loadOnce loads a tab's data once and retries after a failure", async () => {
  const cache = new Map();
  let calls = 0;
  const load = async () => { calls += 1; return calls; };
  assert.equal(await loadOnce(cache, "players", load), 1);
  assert.equal(await loadOnce(cache, "players", load), 1);
  assert.equal(calls, 1);
  let fail = true;
  const flaky = async () => { if (fail) throw new Error("offline"); return "ok"; };
  await assert.rejects(loadOnce(cache, "combine", flaky), /offline/);
  fail = false;
  assert.equal(await loadOnce(cache, "combine", flaky), "ok");
});

test("axisRoom gives labelled axes room clear of the tick labels", () => {
  const o = axisRoom({height: 200, x: {label: "Season"}, y: {label: "Elo", grid: true}});
  assert.equal(o.marginTop, 34);
  assert.equal(o.marginBottom, 50);
  assert.equal(o.x.labelAnchor, "center");
  assert.equal(o.y.labelAnchor, "top");
  assert.equal(o.y.grid, true);
  assert.equal(o.height, 200 + 34 - 20 + 50 - 30);
});

test("axisRoom leaves unlabelled axes and larger margins alone", () => {
  const o = axisRoom({height: 300, marginTop: 40, x: {label: null}, y: {label: "Percentile"}});
  assert.equal(o.marginTop, 40);
  assert.equal(o.marginBottom, undefined);
  assert.equal(o.x.labelAnchor, undefined);
  assert.equal(o.height, 300);
});

import {test} from "node:test";
import assert from "node:assert/strict";
import {sourceLine, errorCard, escapeHtml} from "./ui.js";

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

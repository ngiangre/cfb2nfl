import {test} from "node:test";
import assert from "node:assert/strict";
import {readGamePlays, hyparquetUrl} from "./plays.js";

const rows = [{game_id: 2, play_id: "21"}, {game_id: 2, play_id: "22"}];

// A fake fetch that answers with a buffer for known URLs and 404 otherwise.
function fakeFetch(known) {
  const calls = [];
  const fetchImpl = async url => {
    calls.push(url);
    if (!known.has(url)) return new Response("missing", {status: 404});
    return new Response(new Uint8Array([1, 2, 3]));
  };
  return {fetchImpl, calls};
}

// A fake hyparquet: "reads" the buffer as the fixed rows.
function fakeHp(seen) {
  return {
    parquetReadObjects: async ({file}) => {
      seen.push(file);
      return rows;
    }
  };
}

test("readGamePlays fetches the whole file and returns its rows", async () => {
  const url = "explorer-data/plays/2025/2.parquet";
  const {fetchImpl, calls} = fakeFetch(new Set([url]));
  const seen = [];
  const got = await readGamePlays(fakeHp(seen), url, fetchImpl);
  assert.deepEqual(got, rows);
  assert.deepEqual(calls, [url]);
  assert.equal(seen.length, 1);
  assert.ok(seen[0] instanceof ArrayBuffer);
  assert.deepEqual([...new Uint8Array(seen[0])], [1, 2, 3]);
});

test("readGamePlays throws on a failed response", async () => {
  const url = "explorer-data/plays/2025/9.parquet";
  const {fetchImpl} = fakeFetch(new Set());
  await assert.rejects(readGamePlays(fakeHp([]), url, fetchImpl), /404 explorer-data\/plays\/2025\/9\.parquet/);
});

test("hyparquetUrl busts the CDN cache only after a retry", () => {
  const base = "https://cdn.jsdelivr.net/npm/hyparquet@1/+esm";
  assert.equal(hyparquetUrl(base, 0), base);
  assert.equal(hyparquetUrl(base, 2), base + "?retry=2");
});

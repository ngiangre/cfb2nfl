import {test} from "node:test";
import assert from "node:assert/strict";
import {pickRowGroups, readGamePlays} from "./plays.js";

const stats = (lo, hi) => ({meta_data: {path_in_schema: ["game_id"], statistics: {min_value: lo, max_value: hi}}});
const metadata = {
  row_groups: [
    {num_rows: 3n, columns: [stats(1, 2)]},
    {num_rows: 2n, columns: [stats(2, 4)]},
    {num_rows: 4n, columns: [stats(5, 9)]}
  ]
};

test("pickRowGroups returns the row ranges whose game_id span covers the game", () => {
  assert.deepEqual(pickRowGroups(metadata, 2), [{rowStart: 0, rowEnd: 3}, {rowStart: 3, rowEnd: 5}]);
  assert.deepEqual(pickRowGroups(metadata, 7), [{rowStart: 5, rowEnd: 9}]);
  assert.deepEqual(pickRowGroups(metadata, 99), []);
});

test("pickRowGroups reads every group when statistics are missing", () => {
  const bare = {row_groups: [{num_rows: 2, columns: [{meta_data: {path_in_schema: ["game_id"]}}]}]};
  assert.deepEqual(pickRowGroups(bare, 1), [{rowStart: 0, rowEnd: 2}]);
});

test("readGamePlays reads only the picked groups, filters to the game, caches metadata", async () => {
  const rows = [
    {game_id: 1}, {game_id: 2}, {game_id: 2},
    {game_id: 2}, {game_id: 4},
    {game_id: 5}, {game_id: 6}, {game_id: 7}, {game_id: 9}
  ];
  let metaCalls = 0;
  const reads = [];
  const hp = {
    asyncBufferFromUrl: async ({url}) => ({url}),
    parquetMetadataAsync: async () => { metaCalls += 1; return metadata; },
    parquetReadObjects: async ({rowStart, rowEnd}) => { reads.push([rowStart, rowEnd]); return rows.slice(rowStart, rowEnd); }
  };
  const cache = new Map();
  const got = await readGamePlays(hp, "plays_2025.parquet", 2, cache);
  assert.equal(got.length, 3);
  assert.deepEqual(reads, [[0, 3], [3, 5]]);
  await readGamePlays(hp, "plays_2025.parquet", 7, cache);
  assert.equal(metaCalls, 1);
});

// Plays from a per-season shard parquet file (decision 0046). A shard holds
// every game whose id has the same remainder mod 100. The file is fetched whole: GitHub Pages gzips octet-stream responses for browsers,
// which breaks HTTP range requests. The hyparquet module and fetch are passed
// in, so node tests use fakes and never touch the network.

// The hyparquet bundle's URL. A retry appends a query string so the browser
// re-fetches a module that failed to load (the failed import is not cached).
export function hyparquetUrl(base, retry) {
  return retry > 0 ? `${base}?retry=${retry}` : base;
}

// The shard file holding a game's plays: game_id % 100 within the season.
export function playsShardPath(season, gameId) {
  return `explorer-data/plays/${season}/${Number(gameId) % 100}.parquet`;
}

// Reads every row of one shard.
export async function readShard(hp, url, fetchImpl = fetch) {
  const response = await fetchImpl(url);
  if (!response.ok) throw new Error(`${response.status} ${url}`);
  const file = await response.arrayBuffer();
  return hp.parquetReadObjects({file});
}

// One game's rows out of a shard's rows (order kept).
export function gameRows(shardRows, gameId) {
  return shardRows.filter(row => Number(row.game_id) === gameId);
}

// Reads a shard and keeps only the given game's rows.
export async function readGamePlays(hp, url, gameId, fetchImpl = fetch) {
  return gameRows(await readShard(hp, url, fetchImpl), gameId);
}

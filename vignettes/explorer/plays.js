// One game's plays from a season parquet over HTTP range requests (decision
// 0046). The hyparquet module is passed in, so node tests use a fake and
// never touch the network.

// The hyparquet bundle's URL. A retry appends a query string so the browser
// re-fetches a module that failed to load (the failed import is not cached).
export function hyparquetUrl(base, retry) {
  return retry > 0 ? `${base}?retry=${retry}` : base;
}

// Row ranges of the groups whose game_id min/max spans the game. Groups
// without statistics are always read.
export function pickRowGroups(metadata, gameId) {
  const picks = [];
  let start = 0;
  for (const rg of metadata.row_groups) {
    const n = Number(rg.num_rows);
    const col = rg.columns.find(c => (c.meta_data?.path_in_schema ?? []).join(".") === "game_id");
    const st = col?.meta_data?.statistics ?? {};
    const lo = Number(st.min_value ?? st.min);
    const hi = Number(st.max_value ?? st.max);
    if (!(gameId < lo || gameId > hi)) picks.push({rowStart: start, rowEnd: start + n});
    start += n;
  }
  return picks;
}

// Reads one game's rows. The file handle and metadata are cached per URL, so
// later games in the same season skip the footer fetch.
export async function readGamePlays(hp, url, gameId, cache) {
  if (!cache.has(url)) {
    const opened = (async () => {
      const file = await hp.asyncBufferFromUrl({url});
      const metadata = await hp.parquetMetadataAsync(file);
      return {file, metadata};
    })();
    cache.set(url, opened.catch(error => {
      cache.delete(url);
      throw error;
    }));
  }
  const {file, metadata} = await cache.get(url);
  const rows = [];
  for (const {rowStart, rowEnd} of pickRowGroups(metadata, gameId)) {
    const part = await hp.parquetReadObjects({file, metadata, rowStart, rowEnd});
    for (const r of part) if (Number(r.game_id) === gameId) rows.push(r);
  }
  return rows;
}

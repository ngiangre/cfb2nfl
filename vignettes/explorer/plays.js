// One game's plays from its per-game parquet file (decision 0046). The file
// is fetched whole: GitHub Pages gzips octet-stream responses for browsers,
// which breaks HTTP range requests. The hyparquet module and fetch are passed
// in, so node tests use fakes and never touch the network.

// The hyparquet bundle's URL. A retry appends a query string so the browser
// re-fetches a module that failed to load (the failed import is not cached).
export function hyparquetUrl(base, retry) {
  return retry > 0 ? `${base}?retry=${retry}` : base;
}

// Reads one game's rows from its parquet file.
export async function readGamePlays(hp, url, fetchImpl = fetch) {
  const response = await fetchImpl(url);
  if (!response.ok) throw new Error(`${response.status} ${url}`);
  const file = await response.arrayBuffer();
  return hp.parquetReadObjects({file});
}

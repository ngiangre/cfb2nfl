// Small HTML builders shared by every explorer tab (plans/explorer.md).

export function escapeHtml(s) {
  return String(s).replace(/[&<>"]/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"})[c]);
}

// The "Data:" line under each visual: one link per source table to its
// anchor on the Data page.
export function sourceLine(tables, href = "data.html") {
  const links = tables
    .map(t => `<a href="${href}#table-${escapeHtml(t)}"><code>${escapeHtml(t)}</code></a>`)
    .join(", ");
  return `<p class="explorer-source">Data: ${links}</p>`;
}

export function errorCard(what) {
  return `<div class="explorer-card explorer-error" role="alert"><p>Couldn't load ${escapeHtml(what)}.</p>` +
    `<button type="button" class="explorer-retry">Retry</button></div>`;
}

// Lazy tab data: the first open starts the load, later opens reuse it, and a
// failed load is forgotten so Retry can try again.
export function loadOnce(cache, key, load) {
  if (!cache.has(key)) {
    cache.set(key, Promise.resolve().then(load).catch(error => {
      cache.delete(key);
      throw error;
    }));
  }
  return cache.get(key);
}

// Room for axis titles so they never sit on the tick labels (#78): a labelled
// y axis puts its title above the top tick, a labelled x axis centres its
// title under the ticks. The height grows by the added margin, so the plot
// area keeps its size. Plot's defaults are marginTop 20, marginBottom 30.
export function axisRoom(opts) {
  const out = {...opts};
  let grow = 0;
  if (opts.y?.label) {
    out.y = {labelAnchor: "top", ...opts.y};
    if ((opts.marginTop ?? 20) < 34) {
      grow += 34 - (opts.marginTop ?? 20);
      out.marginTop = 34;
    }
  }
  if (opts.x?.label) {
    out.x = {labelAnchor: "center", labelOffset: 44, ...opts.x};
    if ((opts.marginBottom ?? 30) < 50) {
      grow += 50 - (opts.marginBottom ?? 30);
      out.marginBottom = 50;
    }
  }
  if (out.height !== undefined) out.height += grow;
  return out;
}

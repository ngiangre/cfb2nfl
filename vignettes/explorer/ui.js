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

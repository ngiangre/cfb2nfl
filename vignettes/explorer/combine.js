import {playerLabel, jerseyPos} from "./ui.js";

// Combine-tab helpers (plans/explorer.md step 5). R computes every value;
// these reshape, filter and format for the plotly 3D scatter, and are
// unit-tested with node --test.

// combine.json is an object of columns; the page wants rows.
export function columnsToRows(cols) {
  const keys = Object.keys(cols);
  const n = keys.length ? cols[keys[0]].length : 0;
  const rows = new Array(n);
  for (let i = 0; i < n; i++) {
    const row = {};
    for (const k of keys) row[k] = cols[k][i];
    rows[i] = row;
  }
  return rows;
}

// The hash's pos if the combine has the group (it includes linemen), else QB.
export function resolveCombinePos(pos, meta) {
  return meta.combine_groups.some(g => g.pos === pos) ? pos : "QB";
}

// Invitees in the group and class range with all three axes measured.
export function combinePoints(rows, {pos, from, to, axes}) {
  const lo = Math.min(from, to), hi = Math.max(from, to);
  return rows.filter(d =>
    d.pos === pos && d.season >= lo && d.season <= hi &&
    axes.every(k => d[k] !== null && d[k] !== undefined)
  );
}

// How many invitees in the group and range skipped a drill on these axes.
export function missingCount(rows, {pos, from, to, axes}) {
  const lo = Math.min(from, to), hi = Math.max(from, to);
  return rows.filter(d => d.pos === pos && d.season >= lo && d.season <= hi).length -
    combinePoints(rows, {pos, from, to, axes}).length;
}

export function formatMeasure(value, measure) {
  if (value === null || value === undefined) return "–";
  if (measure.key === "height") {
    const v = Number(value);
    return `${Math.floor(v / 12)}'${Math.round(v % 12)}"`;
  }
  const digits = measure.unit === "s" ? 2 : Number.isInteger(value) ? 0 : 1;
  return `${Number(value).toFixed(digits)} ${measure.unit}`;
}

// A point opens the Players tab only when it links to a CFBD player with a
// stat line there.
export function canOpenPlayer(d) {
  return Boolean(d && d.athlete_id && d.players_pos);
}

// Region filters: each axis cut into thirds (Low, Mid, High) of the shown
// invitees. A cut is [min, first tertile, second tertile, max].
export function regionCuts(points, axes) {
  return axes.map(k => {
    const v = points.map(d => d[k]).sort((a, b) => a - b);
    const q = p => {
      const i = (v.length - 1) * p, lo = Math.floor(i), hi = Math.ceil(i);
      return v[lo] + (v[hi] - v[lo]) * (i - lo);
    };
    return v.length ? [v[0], q(1 / 3), q(2 / 3), v.at(-1)] : [0, 0, 0, 0];
  });
}

export function regionBin(value, cut) {
  return value <= cut[1] ? 0 : value <= cut[2] ? 1 : 2;
}

// `region` holds a third (0, 1, 2) or null ("Any") per axis.
export function regionActive(region) {
  return Boolean(region) && region.some(b => b !== null && b !== undefined);
}

export function inRegion(d, axes, cuts, region) {
  return axes.every((k, i) => region[i] === null || region[i] === undefined || regionBin(d[k], cuts[i]) === region[i]);
}

// One plotly trace per outcome (legend order, with its count), each point
// carrying its index into `points` so a tap can find it, plus an outlined
// trace for the selected player. With a region picked, the outcome traces
// hold only its players (outlined, larger) and everyone else is one faded
// trace drawn first.
export function combineTraces(points, {axes, measures, outcomes, colors, selected, region = null, cuts = null}) {
  const [x, y, z] = axes;
  const byKey = new Map(measures.map(m => [m.key, m]));
  const hover = d => `${playerLabel(d.name, jerseyPos(d.players_jersey, d.combine_pos), d.school, d.season)}<br>${d.outcome_label}<br>` +
    axes.map(k => `${byKey.get(k).label}: ${formatMeasure(d[k], byKey.get(k))}`).join("<br>");
  const active = regionActive(region) && cuts;
  const all = points.map((d, i) => i);
  const kept = active ? all.filter(i => inRegion(points[i], axes, cuts, region)) : all;
  const coords = idx => ({x: idx.map(i => points[i][x]), y: idx.map(i => points[i][y]), z: idx.map(i => points[i][z])});
  const traces = [];
  if (active) {
    const keep = new Set(kept);
    const rest = all.filter(i => !keep.has(i));
    traces.push({
      type: "scatter3d", mode: "markers", name: `Everyone else (N=${rest.length.toLocaleString("en-US")})`, ...coords(rest),
      customdata: rest, text: rest.map(i => hover(points[i])), hoverinfo: "text",
      marker: {size: 3, color: "#cbd5e1", opacity: 0.35}
    });
  }
  for (const o of outcomes) {
    const idx = kept.filter(i => points[i].outcome === o.outcome);
    if (!idx.length) continue;
    traces.push({
      type: "scatter3d", mode: "markers", name: `${o.label} (N=${idx.length.toLocaleString("en-US")})`, ...coords(idx),
      customdata: idx, text: idx.map(i => hover(points[i])), hoverinfo: "text",
      marker: active
        ? {size: 6, color: colors.get(o.outcome) ?? "#9ca3af", opacity: 1, line: {color: "#111827", width: 1}}
        : {size: 4, color: colors.get(o.outcome) ?? "#9ca3af", opacity: 0.85}
    });
  }
  const s = points.findIndex(d => selected && String(d.athlete_id) === String(selected));
  if (s >= 0) {
    const d = points[s];
    traces.push({
      type: "scatter3d", mode: "markers+text", name: d.name, showlegend: false,
      x: [d[x]], y: [d[y]], z: [d[z]], customdata: [s], text: [playerLabel(d.name, jerseyPos(d.players_jersey, d.combine_pos))],
      textposition: "top center", hoverinfo: "text", hovertext: [hover(d)],
      marker: {size: 9, color: colors.get(d.outcome) ?? "#9ca3af", line: {color: "#111827", width: 3}}
    });
  }
  return traces;
}

// Players-tab helpers (plans/explorer.md step 4). R computes every stat and
// percentile; these pick rows, lay out the beeswarm and format values, and are
// unit-tested with node --test.

export const TIERS = [
  {tier: 3, label: "Power"},
  {tier: 2, label: "Group of 5"},
  {tier: 1, label: "FCS and below"}
];

// The stat position groups in meta order (one entry per group).
export function positionGroups(meta) {
  const seen = new Map();
  for (const s of meta.positions) if (!seen.has(s.pos)) seen.set(s.pos, s.group);
  return [...seen].map(([pos, group]) => ({pos, group}));
}

// The hash's pos if it is a stat group (offensive linemen have none), else QB.
export function resolvePlayersPos(pos, meta) {
  return meta.positions.some(s => s.pos === pos) ? pos : "QB";
}

const PLURAL = {
  "Defensive line": "Defensive linemen",
  "Special teams": "Specialists"
};

// "Quarterbacks", "Defensive linemen": a group label as a plural noun.
export function groupPlural(group) {
  return PLURAL[group] ?? `${group}s`;
}

export function positionStats(meta, pos) {
  return meta.positions.filter(s => s.pos === pos);
}

export function formatStat(value, format) {
  if (value === null || value === undefined || Number.isNaN(value)) return "–";
  const v = Number(value);
  if (format === "pct") return `${Math.round(v * 100)}%`;
  if (format === "dec1") return v.toFixed(1);
  return Math.round(v).toLocaleString("en-US");
}

// Every 11th, 12th, 13th ... gets "th"; otherwise 1st, 2nd, 3rd.
export function ordinal(n) {
  const k = n % 100;
  if (k >= 11 && k <= 13) return `${n}th`;
  return `${n}${["th", "st", "nd", "rd"][n % 10] ?? "th"}`;
}

// The swarm's dots: one season's players with a percentile for the stat, in
// the chosen tiers. The selected player stays in even when their tier is off.
export function swarmRows(rows, {season, key, tiers, player}) {
  const pct = `${key}_pct`;
  return rows.filter(d =>
    d.season === season &&
    d[pct] !== null && d[pct] !== undefined &&
    (tiers.includes(d.tier) || String(d.player_id) === String(player))
  );
}

// A greedy beeswarm: each dot, in x order, takes the offset nearest the axis
// that clears every dot already placed. Where a pile of tied values would
// grow past maxOffset, the rest of the pile is spread across the band
// (overlapping), so a tall tie can't stretch the chart. Returns one y offset
// per input x, in input order.
export function beeswarm(xs, r, maxOffset = Infinity) {
  const d2 = (2 * r) ** 2;
  const order = xs.map((_, i) => i).sort((a, b) => xs[a] - xs[b]);
  const ys = new Array(xs.length);
  const placed = [];
  let start = 0;
  let spill = 0;
  for (const i of order) {
    const x = xs[i];
    while (start < placed.length && placed[start].x < x - 2 * r) start++;
    const near = placed.slice(start);
    const candidates = [0];
    for (const p of near) {
      const dy = Math.sqrt(Math.max(0, d2 - (x - p.x) ** 2));
      candidates.push(p.y + dy, p.y - dy);
    }
    candidates.sort((a, b) => Math.abs(a) - Math.abs(b) || b - a);
    let y = null;
    for (const c of candidates) {
      if (Math.abs(c) > maxOffset) break;
      if (near.every(p => (x - p.x) ** 2 + (c - p.y) ** 2 >= d2 - 1e-6)) {
        y = c;
        break;
      }
    }
    if (y === null) {
      // Golden-ratio steps fill the band evenly and deterministically.
      spill += 1;
      y = ((spill * 0.6180339887) % 1 * 2 - 1) * maxOffset;
    }
    ys[i] = y;
    placed.push({x, y});
  }
  return ys;
}

// One player's seasons in this group, oldest first.
export function careerRows(rows, player) {
  return rows
    .filter(d => String(d.player_id) === String(player))
    .sort((a, b) => a.season - b.season);
}

// The season to show for a picked player: the current one if they have a
// line in it, else their latest.
export function seasonForPlayer(career, season) {
  if (!career.length) return season;
  return career.some(d => d.season === season) ? season : career.at(-1).season;
}

// Long rows for the career chart: one per season and stat, with a null where
// the season has no percentile, so the line breaks instead of dropping to 0.
export function careerPercentiles(career, stats) {
  return stats.flatMap(s => career.map(d => ({
    season: d.season,
    stat: s.label,
    pct: d[`${s.key}_pct`] ?? null
  })));
}

// Name or school search: one result per player (their latest season), best
// matches first (a name that starts with the query beats one that contains it).
export function searchPlayers(rows, query, teamName, limit = 8) {
  const q = String(query ?? "").trim().toLowerCase();
  if (q.length < 2) return [];
  const latest = new Map();
  for (const d of rows) {
    const id = String(d.player_id);
    const prev = latest.get(id);
    if (!prev || d.season > prev.season) latest.set(id, d);
  }
  const scored = [];
  for (const d of latest.values()) {
    const name = String(d.name ?? "").toLowerCase();
    const team = String(teamName(d) ?? "").toLowerCase();
    const score = name.startsWith(q) || name.split(" ").some(w => w.startsWith(q)) ? 0
      : name.includes(q) ? 1
      : team.includes(q) ? 2
      : null;
    if (score !== null) scored.push({score, d});
  }
  return scored
    .sort((a, b) => a.score - b.score || b.d.season - a.d.season || a.d.name.localeCompare(b.d.name))
    .slice(0, limit)
    .map(s => s.d);
}

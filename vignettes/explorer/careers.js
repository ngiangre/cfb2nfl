// Draft & careers tab (plans/explorer.md step 6). Pure functions over
// careers.json, unit-tested with node --test.

export const TIER_LABELS = {3: "Power conferences", 2: "Group of Five", 1: "FCS and below"};

// Transfer directions in stacking and legend order.
export const DIRECTIONS = [
  {direction: "up", label: "Up a tier"},
  {direction: "lateral", label: "Same tier"},
  {direction: "down", label: "Down a tier"}
];

// Picks per draft year and conference tier of the player's last college season.
export function draftByTier(rows) {
  const counts = new Map();
  for (const d of rows) {
    const key = `${d.year}|${d.tier}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts].map(([key, n]) => {
    const [year, tier] = key.split("|").map(Number);
    return {year, tier, label: TIER_LABELS[tier], n};
  }).sort((a, b) => a.year - b.year || b.tier - a.tier);
}

// One team's picks per draft year, with a zero for each year it had none.
export function picksPerYear(rows, teamId, years) {
  const counts = new Map(years.map(y => [y, 0]));
  for (const d of rows) if (d.team_id === teamId && counts.has(d.year)) counts.set(d.year, counts.get(d.year) + 1);
  return years.map(year => ({year, n: counts.get(year)}));
}

export function teamPicks(rows, teamId, year) {
  return rows.filter(d => d.team_id === teamId && d.year === year).sort((a, b) => a.overall - b.overall);
}

// Picks linked to an NFL record, filtered by draft class and position. Each
// round is spread across x by pick order within that draft's round, so the
// first pick of round 1 sits at the left of the round and the last at the right.
export function longevityPoints(rows, {from, to, pos}) {
  const span = new Map();
  for (const d of rows) {
    const key = `${d.year}|${d.round}`;
    const s = span.get(key) ?? {lo: Infinity, hi: -Infinity};
    s.lo = Math.min(s.lo, d.overall);
    s.hi = Math.max(s.hi, d.overall);
    span.set(key, s);
  }
  return rows
    .filter(d => d.nfl_seasons !== null && d.nfl_seasons !== undefined)
    .filter(d => d.year >= from && d.year <= to && (pos === "all" || d.pos === pos))
    .map(d => {
      const s = span.get(`${d.year}|${d.round}`);
      const frac = s.hi > s.lo ? (d.overall - s.lo) / (s.hi - s.lo) : 0.5;
      // A fixed per-pick nudge (within a third of a season) so picks with the
      // same count in the same slot don't stack into one dot.
      const nudge = ((d.overall * 37 + d.year * 11) % 100) / 100 - 0.5;
      return {...d, x: d.round - 0.35 + 0.7 * frac, y: d.nfl_seasons + 0.6 * nudge};
    })
    .sort((a, b) => a.year - b.year || a.overall - b.overall);
}

function median(values) {
  const v = values.slice().sort((a, b) => a - b);
  const mid = Math.floor(v.length / 2);
  return v.length % 2 ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

export function roundMedians(points) {
  const byRound = new Map();
  for (const d of points) {
    if (!byRound.has(d.round)) byRound.set(d.round, []);
    byRound.get(d.round).push(d.nfl_seasons);
  }
  return [...byRound].sort((a, b) => a[0] - b[0])
    .map(([round, v]) => ({round, median: median(v), n: v.length}));
}

export function nflSeasonsLabel(d) {
  if (!d.nfl_seasons) return "Never on an NFL roster";
  const s = `${d.nfl_seasons} NFL season${d.nfl_seasons === 1 ? "" : "s"}`;
  return d.active ? `${s} and counting` : s;
}

function directionRows(rows) {
  const counts = new Map();
  for (const d of rows) {
    const key = `${d.season}|${d.direction}`;
    counts.set(key, (counts.get(key) ?? 0) + d.n);
  }
  const order = new Map(DIRECTIONS.map((d, i) => [d.direction, i]));
  return [...counts].map(([key, n]) => {
    const [season, direction] = key.split("|");
    return {season: Number(season), direction, label: DIRECTIONS[order.get(direction)].label, n};
  }).sort((a, b) => a.season - b.season || order.get(a.direction) - order.get(b.direction));
}

// Transfer arrivals per season and direction, summed over every school.
export function transferTotals(rows) {
  return directionRows(rows);
}

export function teamTransfers(rows, teamId) {
  return directionRows(rows.filter(d => d.team_id === teamId));
}

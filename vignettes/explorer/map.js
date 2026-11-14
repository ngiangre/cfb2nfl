// Map tab (plans/explorer.md step 7, issue #48). Pure functions over
// map.json and team_season.json, unit-tested with node --test.

// The selected season's teams with a home stadium on the map: FBS only, or
// FBS and FCS. Membership and record are that season's own.
export function mapPoints(located, teamSeason, teamById, season, showFcs) {
  const where = new Map(located.map(d => [d.team_id, d]));
  const classes = showFcs ? ["fbs", "fcs"] : ["fbs"];
  return teamSeason
    .filter(d => d.season === season && classes.includes(d.classification) && where.has(d.team_id))
    .map(d => {
      const loc = where.get(d.team_id), info = teamById.get(d.team_id) ?? {};
      return {
        team_id: d.team_id, team: info.team ?? String(d.team_id), color: info.color,
        conference: d.conference, classification: d.classification,
        wins: d.wins, losses: d.losses, ties: d.ties,
        latitude: loc.latitude, longitude: loc.longitude,
        city: loc.city, state: loc.state, venue: loc.venue
      };
    })
    .sort((a, b) => a.team.localeCompare(b.team));
}

// Conferences on the map, FBS before FCS, then by name.
export function mapConferences(points) {
  const cls = new Map();
  for (const p of points) if (p.conference && (!cls.has(p.conference) || p.classification === "fbs")) cls.set(p.conference, p.classification);
  return [...cls].sort(([a, ca], [b, cb]) => (ca === cb ? a.localeCompare(b) : ca === "fbs" ? -1 : 1)).map(([c]) => c);
}

// The conference to highlight: the reader's pick if it is on the map, else
// the selected team's conference that season, else the first one.
export function resolveMapConference(pick, conferences, teamConference) {
  if (conferences.includes(pick)) return pick;
  if (conferences.includes(teamConference)) return teamConference;
  return conferences[0] ?? null;
}

// Every conference's spread across seasons for one classification, for the
// context lines; the highlighted conference is drawn on top.
export function spreadRows(spread, classification) {
  return spread.filter(d => d.classification === classification && d.spread_miles !== null);
}

export function spreadSummary(spread, conference, season) {
  const rows = spread.filter(d => d.conference === conference && d.spread_miles !== null).sort((a, b) => a.season - b.season);
  const now = rows.find(d => d.season === season);
  if (!now) return null;
  const miles = n => `${n.toLocaleString("en-US")} miles`;
  let text = `In ${season}, two ${conference} home stadiums sit ${miles(now.spread_miles)} apart on average (${now.members} members).`;
  const prev = rows.filter(d => d.season < season).at(-1);
  if (prev && prev.spread_miles !== now.spread_miles) {
    text += ` In ${prev.season} it was ${miles(prev.spread_miles)}.`;
  }
  return text;
}

export function mapTitle(p) {
  const place = [p.city, p.state].filter(Boolean).join(", ");
  const record = `${p.wins}-${p.losses}${p.ties ? `-${p.ties}` : ""}`;
  return `${p.team} (${record})\n${p.conference}\n${[p.venue, place].filter(Boolean).join(", ")}`;
}

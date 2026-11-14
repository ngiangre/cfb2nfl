// Teams-tab helpers (plans/explorer.md step 3). R computes every value; these
// only filter, order and flip signs, and are unit-tested with node --test.

export function formatRecord(d) {
  return `${d.wins}-${d.losses}${d.ties ? "-" + d.ties : ""}`;
}

// One team's games in a season, in kickoff order (ISO strings sort by time).
export function teamGames(rows, teamId) {
  return rows.filter(d => d.team_id === teamId).sort((a, b) => a.start.localeCompare(b.start));
}

// The game to show: the reader's pick if it belongs to this team-season, else
// the latest game with play-by-play, else the latest game.
export function effectiveGame(gameId, games) {
  if (games.some(g => g.game_id === gameId)) return gameId;
  const withPlays = games.filter(g => g.has_plays);
  const pick = (withPlays.length ? withPlays : games).at(-1);
  return pick ? pick.game_id : null;
}

// Conference panels for a season: membership as of that season, each panel
// carrying its teams' whole history so their lines span every season. FBS
// panels plot end-of-season Elo; FCS has no Elo, so its panels plot win share.
export function landscapePanels(teamSeason, season, classification) {
  const metric = classification === "fbs" ? "elo_end" : "win_pct";
  const panels = new Map();
  for (const d of teamSeason) {
    if (d.season !== season || d.classification !== classification) continue;
    const conference = d.conference ?? "Independent";
    if (!panels.has(conference)) panels.set(conference, {conference, tier: d.tier ?? 0, teams: new Set()});
    panels.get(conference).teams.add(d.team_id);
  }
  return [...panels.values()]
    .map(p => ({
      conference: p.conference,
      tier: p.tier,
      metric,
      teamIds: [...p.teams],
      rows: teamSeason.filter(d => p.teams.has(d.team_id) && d[metric] !== null)
    }))
    .sort((a, b) => b.tier - a.tier || a.conference.localeCompare(b.conference));
}

// One game's plays from the selected team's side: margin and cumulative PPA
// flip sign for the away team. Plays without an elapsed time are dropped.
export function timelineFor(plays, isHome) {
  const sign = isHome ? 1 : -1;
  return plays
    .filter(p => p.elapsed !== null && p.elapsed !== undefined)
    .map(p => ({
      ...p,
      elapsed: Number(p.elapsed),
      margin: sign * Number(p.home_margin) + 0,
      cum_ppa: sign * Number(p.home_cum_ppa) + 0,
      team_score: Number(isHome ? p.home_score : p.away_score),
      opp_score: Number(isHome ? p.away_score : p.home_score)
    }));
}

// The selected team's row for a season (conference, record), or null when
// it did not play that season.
export function teamSeasonRow(teamSeason, team, season) {
  return teamSeason.find(d => d.team_id === team && d.season === season) ?? null;
}

// The team menu for a season, one group per conference (FBS before FCS,
// Power conferences first), teams ordered by win share then wins. Teams that
// did not play that season close the menu, so any team stays selectable.
export function teamGroups(teamSeason, teams, season) {
  const name = new Map(teams.map(t => [t.team_id, t.team]));
  const groups = new Map();
  for (const d of teamSeason) {
    if (d.season !== season || !name.has(d.team_id)) continue;
    const conference = d.conference ?? "Independent";
    if (!groups.has(conference)) {
      groups.set(conference, {label: conference, fbs: d.classification === "fbs", tier: d.tier ?? 0, rows: []});
    }
    groups.get(conference).rows.push(d);
  }
  const out = [...groups.values()]
    .sort((a, b) => Number(b.fbs) - Number(a.fbs) || b.tier - a.tier || a.label.localeCompare(b.label))
    .map(g => ({
      label: g.label,
      options: g.rows
        .sort((a, b) => b.win_pct - a.win_pct || b.wins - a.wins || name.get(a.team_id).localeCompare(name.get(b.team_id)))
        .map(d => ({team_id: d.team_id, label: `${name.get(d.team_id)} (${formatRecord(d)})`}))
    }));
  const played = new Set(out.flatMap(g => g.options.map(o => o.team_id)));
  const rest = teams.filter(t => !played.has(t.team_id)).sort((a, b) => a.team.localeCompare(b.team));
  if (rest.length) out.push({label: `Did not play in ${season}`, options: rest.map(t => ({team_id: t.team_id, label: t.team}))});
  return out;
}

const isConference = c => Boolean(c) && !/Independent/.test(c);

// For each season the team played in a conference, that conference's average
// end-of-season Elo and win share over its members (the team included).
// Independents are not a conference, so their seasons have no average.
export function conferenceAverages(teamSeason, team) {
  const mean = xs => (xs.length ? xs.reduce((a, x) => a + x, 0) / xs.length : null);
  return teamSeason
    .filter(d => d.team_id === team && isConference(d.conference))
    .map(d => {
      const members = teamSeason.filter(m => m.season === d.season && m.conference === d.conference);
      const elo = mean(members.filter(m => m.elo_end !== null).map(m => m.elo_end));
      return {
        season: d.season, conference: d.conference, members: members.length,
        elo_mean: elo === null ? null : Math.round(elo),
        win_pct_mean: Math.round(1000 * mean(members.map(m => m.win_pct))) / 1000
      };
    })
    .sort((a, b) => a.season - b.season);
}

// The season's teams with a home stadium, in one classification, for the
// map. Membership and record are that season's own.
export function mapPoints(teams, teamSeason, season, classification) {
  const byId = new Map(teams.map(t => [t.team_id, t]));
  return teamSeason
    .filter(d => d.season === season && d.classification === classification)
    .map(d => ({d, t: byId.get(d.team_id)}))
    .filter(({t}) => t && t.latitude !== null && t.latitude !== undefined && t.longitude !== null && t.longitude !== undefined)
    .map(({d, t}) => ({
      team_id: d.team_id, team: t.team, color: t.color, conference: d.conference ?? "Independent",
      wins: d.wins, losses: d.losses, ties: d.ties,
      latitude: t.latitude, longitude: t.longitude, city: t.city, state: t.state, venue: t.venue
    }))
    .sort((a, b) => a.team.localeCompare(b.team));
}

export function mapTitle(p) {
  const place = [p.venue, [p.city, p.state].filter(Boolean).join(", ")].filter(Boolean).join(", ");
  return `${p.team} (${formatRecord(p)})\n${p.conference}${place ? `\n${place}` : ""}`;
}

// The game timeline loads only on the Teams tab, once its Game section has
// been in view, and only for a game that has plays.
export function shouldLoadPlays({tab, gameInView, hasPlays}) {
  return tab === "teams" && gameInView === true && hasPlays === true;
}

// The play Prev/Next moves to. Stops at either end and reports the edge, so
// the live region can say so instead of the control wrapping around.
export function stepPlay(timeline, current, delta) {
  if (!timeline.length) return {play: null, edge: "last"};
  const i = timeline.indexOf(current);
  const from = i < 0 ? 0 : i;
  const to = from + delta;
  if (to < 0) return {play: timeline[0], edge: "first"};
  if (to >= timeline.length) return {play: timeline.at(-1), edge: "last"};
  return {play: timeline[to], edge: null};
}

// "Q2 7:30", or the overtime label, which already carries its period.
export function playWhen(p) {
  return p.period > 4 ? p.clock : `Q${p.period} ${p.clock ?? ""}`.trimEnd();
}

// What the screen reader hears when a reader steps to a play.
export function playAnnouncement(p) {
  return `${playWhen(p)}: ${p.play_text ?? p.play_type ?? ""}`;
}

export function parsePlayers(json) {
  if (!json) return [];
  try {
    const players = JSON.parse(json);
    return Array.isArray(players) ? players : [];
  } catch {
    return [];
  }
}

// A team's record as shares of each season's games, for the 100% W-L bars;
// `n` keeps the count for the tooltip.
export function recordShares(rows) {
  return rows.flatMap(d => {
    const games = d.wins + d.losses + d.ties;
    if (!games) return [];
    return [["Wins", d.wins], ["Losses", d.losses], ["Ties", d.ties]]
      .filter(([, n]) => n > 0)
      .map(([outcome, n]) => ({season: d.season, outcome, n, share: n / games}));
  });
}

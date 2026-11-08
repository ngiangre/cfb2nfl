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

export function parsePlayers(json) {
  if (!json) return [];
  try {
    const players = JSON.parse(json);
    return Array.isArray(players) ? players : [];
  } catch {
    return [];
  }
}

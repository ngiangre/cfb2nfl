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

// The Show FCS toggle's starting value: on when the team is FCS that season.
export function defaultShowFcs(teamSeason, team, season) {
  return teamSeason.some(d => d.team_id === team && d.season === season && d.classification === "fcs");
}

// The conference panel the reader opened, kept only while the selected team
// is in it; otherwise the landscape shows every conference again.
export function focusedConference(focusConf, panels, team) {
  if (focusConf === null || focusConf === undefined) return null;
  const panel = panels.find(p => p.conference === focusConf);
  return panel && panel.teamIds.includes(team) ? focusConf : null;
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

// Explorer URL-hash state (plans/explorer.md, decision 0046). Pure functions,
// unit-tested with node --test; the page wires them to the DOM. Every key is
// written to the hash so a shared link pins the season instead of following
// the in-progress one.

export const TABS = [
  {key: "teams", label: "Teams"},
  {key: "players", label: "Players"},
  {key: "combine", label: "Combine"},
  {key: "careers", label: "Draft & careers"}
];

const KEYS = ["tab", "season", "team", "game", "pos", "player"];
const INTEGER_KEYS = new Set(["season", "team", "game"]);

export function resolveSeason(season, meta) {
  return meta.seasons.includes(season) ? season : meta.default_season;
}

export function resolveTeam(team, teams, meta) {
  return teams.some(t => t.team_id === team) ? team : meta.default_team;
}

export function parseHash(hash, meta) {
  const state = {
    tab: "teams", season: meta.default_season, team: meta.default_team,
    game: null, pos: "QB", player: null
  };
  const params = new URLSearchParams(String(hash ?? "").replace(/^#/, ""));
  for (const key of KEYS) {
    const raw = params.get(key);
    if (raw === null || raw === "") continue;
    if (!INTEGER_KEYS.has(key)) {
      state[key] = raw;
      continue;
    }
    const n = Number(raw);
    if (Number.isInteger(n)) state[key] = n;
  }
  if (!TABS.some(t => t.key === state.tab)) state.tab = "teams";
  state.season = resolveSeason(state.season, meta);
  return state;
}

export function toHash(state) {
  const params = new URLSearchParams();
  for (const key of KEYS) {
    if (state[key] !== null && state[key] !== undefined) params.set(key, String(state[key]));
  }
  return "#" + params.toString();
}

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { googleAuthEntryHref, resolveGoogleAuthReturnHref } from "../app/google-auth-return";
import {
  marketRouteDetailFromParams,
  marketRouteFiltersFromParams,
  readMarketLocationPreference,
  readMarketReadCache,
  safeMarketError,
  updateMarketRouteParams,
  writeMarketLocationPreference,
  writeMarketReadCache,
} from "../app/mercado/market-ui-contract";
import { resolveThemePreference } from "../app/theme-toggle";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("official Home exposes one primary action and one visual authority per context", async () => {
  const [component, page] = await Promise.all([
    source("app/_components/official-home-game-dashboard.tsx"),
    source("app/page.tsx"),
  ]);

  assert.equal(component.match(/data-primary-action="true"/g)?.length, 2, "one Link branch and one button branch share the same single action slot");
  assert.equal(component.match(/<ActionControl action=\{nextAction\}/g)?.length, 1);
  assert.equal(component.match(/data-official-identity-band="true"/g)?.length, 1);
  assert.equal(component.match(/data-official-upcoming-rail="true"/g)?.length, 1);
  assert.equal(component.match(/data-official-activity-rail="true"/g)?.length, 1);
  assert.equal(component.match(/data-official-identity-controls="integrated"/g)?.length, 1);
  assert.equal(component.match(/data-official-team-access="identity"/g)?.length, 1);
  assert.match(page, /<OfficialHomeGameDashboard/);
  assert.doesNotMatch(page, /<OfficialTeamAccess/);
  assert.match(page, /contextVisual=\{hasHomeTeamIdentity/);
  assert.doesNotMatch(component, /<\/div>\s*\{access\}\s*<OfficialUpcomingMatchesRail/);
});

test("official Home uses the canonical team shield and never another roster card as its team object", async () => {
  const page = await source("app/page.tsx");

  assert.match(page, /const hasHomeTeamIdentity = hasRealTeam \|\| previewDemoMode/);
  assert.match(page, /get_pachanga_team_shield_snapshot_v1/);
  assert.match(page, /hasHomeTeamIdentity \? \(\s*<TeamShieldView/);
  assert.match(page, /: homeObjectPlayer \? \([\s\S]*<PlayerCosmeticCard/);
  assert.match(page, /const homeObjectPlayer = hasHomeTeamIdentity \? undefined : ownPlayer/);
  assert.doesNotMatch(page, /ownPlayer \?\? activeGroupPlayers\[0\]/);
  assert.match(page, /contextVisual=\{hasHomeTeamIdentity/);
});

test("authenticated theme defaults to dark without overriding explicit preferences", () => {
  assert.equal(resolveThemePreference(null, "dark"), "dark");
  assert.equal(resolveThemePreference("light", "dark"), "light");
  assert.equal(resolveThemePreference("dark", "system"), "dark");
  assert.equal(resolveThemePreference("system", "dark"), "system");
});

test("protected V2.1 deep links survive the Google OAuth round trip", async () => {
  const [home, shield, card] = await Promise.all([
    source("app/page.tsx"),
    source("app/equipo/identidad/page.tsx"),
    source("app/personalizar-carta/page.tsx"),
  ]);
  const origin = "https://preview.example.test";

  assert.equal(
    googleAuthEntryHref("/equipo/identidad"),
    "/?authReturn=%2Fequipo%2Fidentidad",
  );
  assert.equal(
    resolveGoogleAuthReturnHref(
      `${origin}/?authReturn=%2Fpersonalizar-carta%3Fslot%3Dframe`,
      origin,
    ),
    `${origin}/personalizar-carta?slot=frame`,
  );
  assert.equal(
    resolveGoogleAuthReturnHref(`${origin}/?authReturn=https%3A%2F%2Fevil.example`, origin),
    `${origin}/`,
  );
  assert.match(home, /resolveGoogleAuthReturnHref\(window\.location\.href, window\.location\.origin\)/);
  assert.match(shield, /googleAuthEntryHref\("\/equipo\/identidad"\)/);
  assert.match(card, /window\.location\.assign\(googleAuthEntryHref\(`\$\{window\.location\.pathname\}\$\{window\.location\.search\}`\)\)/);
  assert.match(card, /playerProfileRequired\(result\.error\)/);
  assert.match(card, /href="\/perfil\/test-inicial">Hacer test inicial y crear mi carta<\/Link>/);
  assert.match(card, /!message && !missingProfile/);
  assert.doesNotMatch(card, /description: message,[\s\S]*Player profile required/);
});

test("Match is a single persistent game hub without changing its callbacks", async () => {
  const [component, page, css] = await Promise.all([
    source("app/_components/official-match-game-hub.tsx"),
    source("app/page.tsx"),
    source("app/_components/official-match-game-hub.module.css"),
  ]);

  assert.equal(component.match(/data-official-match-navigation="single"/g)?.length, 1);
  assert.equal(component.match(/data-official-match-context="persistent"/g)?.length, 1);
  assert.doesNotMatch(component, /CustomEvent|localStorage|supabase|\.rpc\(/i);
  assert.match(page, /onSelectPane=\{\(pane\) => setActiveMatchManagerPane/);
  assert.match(page, /onClick=\{applyBalancedTeams\}/);
  assert.match(page, /toggleLineupClosed/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /max-height: 600px/);
});

test("Market has one navigation while retaining authoritative operations", async () => {
  const [component, market, css] = await Promise.all([
    source("app/_components/official-market-game-view.tsx"),
    source("app/mercado/marketplace-client.tsx"),
    source("app/_components/official-market-game-view.module.css"),
  ]);

  assert.equal(component.match(/data-official-market-navigation="single"/g)?.length, 1);
  assert.equal(market.match(/<OfficialMarketGameView/g)?.length, 1);
  assert.doesNotMatch(market, /className="market-tabs"/);
  for (const tab of ["partidos", "jugadores", "equipos"]) assert.match(market, new RegExp(`id: "${tab}"`));
  for (const tab of ["retos", "arbitros", "clubes"]) assert.doesNotMatch(market, new RegExp(`id: "${tab}"`));
  assert.match(market, /get\("tab"\) === "retos"[\s\S]*window\.location\.replace\("\/retos"\)/);
  assert.match(market, /request_pachanga_open_match_authoritative_v2/);
  assert.match(market, /operation_id: crypto\.randomUUID\(\)/);
  assert.doesNotMatch(component, /supabase|localStorage|\.rpc\(/i);
  assert.match(css, /\.official-ui-v2-market/);
});

test("V3D keeps safe shareable filters and restorable detail deep links", () => {
  const filters = marketRouteFiltersFromParams(new URLSearchParams("zona=Barcelona&placeId=abc&dia=Esta+semana&modalidad=futbol7&posicion=Defensa&radio=50&orden=date"));
  assert.deepEqual(filters, {
    day: "Esta semana",
    maxPrice: null,
    maxRating: null,
    minRating: null,
    modality: "futbol7",
    position: "Defensa",
    radiusKm: 50,
    sort: "date",
    zone: "Barcelona",
    zonePlaceId: "abc",
  });
  assert.deepEqual(marketRouteDetailFromParams(new URLSearchParams("openMatch=match-1")), { id: "match-1", kind: "match" });
  const next = updateMarketRouteParams(new URLSearchParams("partido=context-1&lat=41.1&lng=2.1"), {
    detail: { id: "player-1", kind: "player" },
    filters,
    tab: "jugadores",
  });
  assert.equal(next.get("partido"), "context-1");
  assert.equal(next.get("player"), "player-1");
  assert.equal(next.get("tab"), "jugadores");
  assert.equal(next.get("lat"), "41.1", "legacy context coordinates are preserved but V3D never creates device coordinates");
  assert.equal(next.get("openMatch"), null);
});

test("V3D local caches are derived reads and location preferences never persist device coordinates", () => {
  const values = new Map<string, string>();
  const storage = {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => void values.set(key, value),
  };
  writeMarketLocationPreference(storage, { label: "Barcelona", placeId: "place-1", radiusKm: 30 });
  assert.deepEqual(readMarketLocationPreference(storage), { label: "Barcelona", placeId: "place-1", radiusKm: 30 });
  assert.doesNotMatch(values.get("pachangas-market-location-v3d") ?? "", /lat|lng|latitude|longitude/i);
  const updatedAt = new Date().toISOString();
  writeMarketReadCache(storage, { matches: [{ id: "m1" }], profiles: [{ id: "p1" }], updatedAt, version: 1 });
  assert.deepEqual(readMarketReadCache(storage)?.matches, [{ id: "m1" }]);
  assert.equal(safeMarketError({ code: "PT409", message: "stale revision" }).stale, true);
  assert.match(safeMarketError({ message: "network fetch failed" }).body, /conexión/);
});

test("V3D removes synthetic live fallbacks and keeps configuration outside team results", async () => {
  const [market, marketUiState, teamPanel, marketCss, filterSheet, globals, shellCss, demo, worker] = await Promise.all([
    source("app/mercado/marketplace-client.tsx"),
    source("app/mercado/marketplace-ui-state.ts"),
    source("app/mercado/challengeable-teams-panel.tsx"),
    source("app/mercado/marketplace-v3d.module.css"),
    source("app/mercado/market-filter-sheet.tsx"),
    source("app/globals.css"),
    source("app/_components/official-market-game-view.module.css"),
    source("app/demo-world/demo-world-app.tsx"),
    source("app/service-worker-source.ts"),
  ]);
  assert.doesNotMatch(market, /fallbackProfiles|fallbackOpenMatches|open-demo-|market-demo-/);
  assert.match(marketUiState, /"CACHED" \| "IDLE" \| "LIVE" \| "LOADING" \| "UNAVAILABLE"/);
  assert.match(market, /marketQueryPhase\(activeSource, resultCount, online\)/);
  assert.match(market, /readMarketReadCache/);
  assert.match(market, /Necesitas conexión para confirmar esta acción/);
  assert.match(market, /navigator\.geolocation\.getCurrentPosition/);
  assert.match(market, /request_pachanga_open_match_authoritative_v2/);
  assert.match(market, /cancel_my_pachanga_open_match_request_v1/);
  assert.match(market, /create_pachanga_match_invitation_v1/);
  assert.match(market, /cancel_pachanga_match_invitation_v1/);
  assert.match(teamPanel, /Mi equipo en Mercado/);
  assert.match(teamPanel, /<MarketDetailSheet/);
  assert.doesNotMatch(teamPanel, /Revisión \{searchSnapshot/);
  assert.doesNotMatch(shellCss, /176px/);
  assert.match(shellCss, /orientation: landscape/);
  assert.match(marketCss, /\.filterSheet/);
  assert.match(marketCss, /\.detailSheet/);
  assert.match(marketCss, /padding: 0 0 calc\(60px \+ env\(safe-area-inset-bottom\)\)/);
  assert.match(marketCss, /left: calc\(82px \+ env\(safe-area-inset-left\)\)/);
  assert.match(marketCss, /left: calc\(88px \+ env\(safe-area-inset-left\)\)/);
  assert.match(filterSheet, /market-filter-backdrop-v3d/);
  assert.match(globals, /:not\(\.market-filter-backdrop-v3d\)/);
  assert.match(demo, /Recorrido social de Mercado/);
  assert.match(demo, /remoteWrites = 0/);
  assert.match(demo, /Math\.round\(player\.rating\.currentOverall\)/);
  assert.match(demo, /Math\.round\(selectedPlayer\.rating\.currentOverall\)/);
  assert.match(demo, /data-demo-auth=\{signedOut \? "signed-out" : "signed-in"\}/);
  assert.match(demo, /Probar sin sesión/);
  assert.match(demo, /Entrar para continuar\. La ruta de Mercado se conserva/);
  assert.match(demo, /const \[creating, setCreating\] = useState\(Boolean\(initialOpponentTeamId\)\)/);
  assert.match(demo, /params\.set\("crear", "1"\)/);
  assert.match(demo, /params\.set\("rival", teamId\)/);
  assert.match(demo, /team\.id !== perspective\.teamId/);
  assert.match(await source("app/demo-world/demo-world.module.css"), /\.demoMarketV3d \{\s*--official-surface-solid: color-mix\(in srgb, var\(--demo-panel\) 94%, var\(--demo-bg\)\)/);
  assert.match(demo, /externalNotifications = 0/);
  assert.match(demo, /realEntities = 0/);
  assert.match(demo, /StripeCalls = 0/);
  assert.match(worker, /"\/mercado"/);
});

test("product primary navigation has one canonical destination per menu item", async () => {
  const [shell, page, market] = await Promise.all([
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/page.tsx"),
    source("app/mercado/marketplace-client.tsx"),
  ]);

  for (const [tab, href] of [
    ["inicio", "/?mobile=inicio"],
    ["partido", "/?mobile=partido"],
    ["retos", "/retos"],
    ["mercado", "/mercado"],
  ]) {
    assert.match(shell, new RegExp(`${tab}: "${href.replace(/[?]/g, "\\?")}"`));
  }

  assert.match(shell, /const primaryItems[^=]*= PRODUCT_PRIMARY_DESTINATIONS/);
  assert.match(page, /links=\{\{ mercado: "\/mercado", retos: "\/retos" \}\}/);
  assert.match(page, /const openMatches = openMatchesByDate\(matches\)/);
  assert.match(page, /requestsNextMatchFromPrimaryNavigation\(entrySearch, entryRoute\)/);
  assert.match(page, /setActiveMatchManagerPane\(requestedMatchPane === "admin" \? "admin" : "proximo"\)/);
  assert.match(page, /if \(tabId === "perfil"\) \{[\s\S]*window\.location\.assign\("\/perfil"\)[\s\S]*return;/);
  assert.doesNotMatch(page, /compactProfileNavigation/);
  assert.doesNotMatch(page, /setSelectedPlayerId\(ownPlayer\?\.id \?\? selectedPlayerId \?\? players\[0\]\?\.id/);
  assert.match(shell, /links=\{onNavigate \? links : destinations\}/);
  assert.doesNotMatch(market, /<OfficialProductShellV2[\s\S]*links=\{\{/);
});

test("Ranking renders the own position before the public table", async () => {
  const board = await source("app/ranking/provincial-ranking-board.tsx");
  const ownIndex = board.indexOf("data-own-ranking=\"first\"");
  const tableIndex = board.indexOf("className={styles.rankingPanel}");
  assert.ok(ownIndex >= 0);
  assert.ok(tableIndex > ownIndex);
  assert.match(board, /eligibilityState/);
  assert.doesNotMatch(board, /\.rpc\(|supabaseClient/);
});

test("V2.1 lab is noindex, dark by default and isolated from product authority", async () => {
  const [page, client, css] = await Promise.all([
    source("app/laboratorio-official-ui-v2-1/page.tsx"),
    source("app/laboratorio-official-ui-v2-1/lab-client.tsx"),
    source("app/laboratorio-official-ui-v2-1/official-ui-v2-1-lab.module.css"),
  ]);

  assert.match(page, /follow: false, index: false/);
  assert.match(page, /initialTheme=\{queryValue\(query\.theme, "dark"\)\}/);
  assert.match(client, /root\.dataset\.theme = theme/);
  assert.match(client, /previousTheme/);
  assert.match(client, /Fixtures visuales|fixtures visuales/i);
  assert.doesNotMatch(client, /supabaseClient|\.rpc\(|localStorage|indexedDB|demo-world.*json/i);
  assert.match(css, /data-capture="true"/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /max-width: 760px/);
  assert.match(css, /prefers-reduced-motion: reduce/);
});

test("Demo World authority and Platform Admin remain outside V2.1 presentation components", async () => {
  const [lab, demo, publicDemo, fullDemo, admin] = await Promise.all([
    source("app/laboratorio-official-ui-v2-1/lab-client.tsx"),
    source("app/demo-world/demo-world-app.tsx"),
    source("app/demo/page.tsx"),
    source("app/admin/demo/page.tsx"),
    source("app/admin/_components/platform-shell.tsx"),
  ]);

  assert.doesNotMatch(lab, /DemoWorldApp|DEMO_WORLD_FIXTURES/);
  assert.match(demo, /DemoWorld/);
  assert.match(publicDemo, /mode="social"/);
  assert.match(fullDemo, /session\.access\.role !== "platform_owner"/);
  assert.match(fullDemo, /mode="full"/);
  assert.match(admin, /data-shell-variant="PLATFORM_ADMIN"/);
  assert.doesNotMatch(admin, /OfficialHomeGameDashboard|OfficialMatchGameHub/);
});

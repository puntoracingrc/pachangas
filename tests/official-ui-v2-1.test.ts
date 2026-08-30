import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { googleAuthEntryHref, resolveGoogleAuthReturnHref } from "../app/google-auth-return";
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
  assert.match(page, /<OfficialTeamAccess/);
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
  assert.match(page, />Mi carta<\/button>/);
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
  assert.match(card, />Crear mi ficha<\/Link>/);
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
    source("app/mercado/page.tsx"),
    source("app/_components/official-market-game-view.module.css"),
  ]);

  assert.equal(component.match(/data-official-market-navigation="single"/g)?.length, 1);
  assert.equal(market.match(/<OfficialMarketGameView/g)?.length, 1);
  assert.doesNotMatch(market, /className="market-tabs"/);
  for (const tab of ["jugadores", "partidos", "retos", "equipos", "arbitros"]) assert.match(market, new RegExp(`id: "${tab}"`));
  assert.match(market, /request_pachanga_open_match_authoritative_v2/);
  assert.match(market, /operation_id: crypto\.randomUUID\(\)/);
  assert.doesNotMatch(component, /supabase|localStorage|\.rpc\(/i);
  assert.match(css, /\.official-ui-v2-market/);
});

test("product primary navigation has one canonical destination per menu item", async () => {
  const [shell, page, market] = await Promise.all([
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/page.tsx"),
    source("app/mercado/page.tsx"),
  ]);

  for (const [tab, href] of [
    ["inicio", "/?mobile=inicio"],
    ["partido", "/?mobile=partido"],
    ["competir", "/competiciones"],
    ["mercado", "/mercado"],
    ["equipo", "/?mobile=equipo"],
    ["perfil", "/?mobile=perfil"],
  ]) {
    assert.match(shell, new RegExp(`${tab}: "${href.replace(/[?]/g, "\\?")}"`));
  }

  assert.match(page, /links=\{\{ competir: "\/competiciones", mercado: "\/mercado" \}\}/);
  assert.match(page, /const openMatches = openMatchesByDate\(matches\)/);
  assert.match(page, /requestsNextMatchFromPrimaryNavigation\(entrySearch, entryRoute\)/);
  assert.match(page, /setActiveMatchManagerPane\(requestedMatchPane === "admin" \? "admin" : "proximo"\)/);
  assert.match(page, /const compactProfileNavigation =/);
  assert.match(page, /if \(!compactProfileNavigation && !managerLandscape\) \{[\s\S]*void openOwnPlayerProfile\(\)/);
  assert.match(page, /if \(managerLandscape && ownPlayer\)[\s\S]*setSelectedPlayerId\(ownPlayer\.id\)/);
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
  const [lab, demo, admin] = await Promise.all([
    source("app/laboratorio-official-ui-v2-1/lab-client.tsx"),
    source("app/demo-world/demo-world-app.tsx"),
    source("app/admin/_components/platform-shell.tsx"),
  ]);

  assert.doesNotMatch(lab, /DemoWorldApp|DEMO_WORLD_FIXTURES/);
  assert.match(demo, /DemoWorld/);
  assert.match(admin, /data-shell-variant="PLATFORM_ADMIN"/);
  assert.doesNotMatch(admin, /OfficialHomeGameDashboard|OfficialMatchGameHub/);
});

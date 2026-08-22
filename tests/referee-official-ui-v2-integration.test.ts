import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const source = (path: string) => readFile(new URL(path, root), "utf8");

test("Mercado keeps R3 authority inside the Official UI V2 shell", async () => {
  const market = await source("app/mercado/page.tsx");
  assert.match(market, /OfficialProductShellV2/);
  assert.match(market, /active="mercado"/);
  assert.match(market, /MarketTab[^;]+"arbitros"/s);
  assert.match(market, /get_pachanga_referee_foundation_flags_v1/);
  assert.match(market, /refereeMarketplaceEnabled \? <button[^>]+activeTab === "arbitros"/s);
  assert.match(market, /activeTab === "arbitros" && refereeMarketplaceEnabled \? \(/);
  assert.match(market, /<RefereeMarketplacePanel/);
  assert.match(market, /String\(membership\?\.data\?\.role\) === "owner"/);
  assert.match(market, /activeTab === "arbitros" \? "Árbitros" : "Equipos"/);
  assert.doesNotMatch(market, /\bMobileAppNav\b/);
});

test("an unavailable referee market falls back without mounting its request panel", async () => {
  const market = await source("app/mercado/page.tsx");
  assert.match(market, /requestedTab === "arbitros" && !marketplaceEnabled\) setActiveTab\("jugadores"\)/);
  assert.match(market, /activeTab === "arbitros" && refereeMarketplaceEnabled/);
  assert.doesNotMatch(market, /<RefereeMarketplacePanel[\s\S]*?refereeMarketplaceEnabled={/);
});

test("referee marketplace uses a real three-pane game-landscape composition", async () => {
  const [panel, css] = await Promise.all([
    source("app/mercado/referee-marketplace-panel.tsx"),
    source("app/mercado/referee-marketplace-panel.module.css"),
  ]);
  assert.match(panel, /data-referee-market-v2="true"/);
  assert.match(panel, /className={styles\.filters}/);
  assert.match(panel, /className={styles\.resultsPane}/);
  assert.match(panel, /className={styles\.detailPane}/);
  assert.match(panel, /role="group" aria-label="Resultados del mercado arbitral"/);
  assert.match(panel, /aria-pressed={selected}/);
  assert.doesNotMatch(panel, /role="listbox"|role="option"/);
  assert.match(panel, /selectedProfileId/);
  assert.match(css, /grid-template-columns: clamp\(150px, 20vw, 205px\) minmax\(170px, \.72fr\) minmax\(210px, 1fr\)/);
  assert.match(css, /max-width: 740px/);
  assert.match(css, /105px 126px minmax\(150px, 1fr\)/);
  assert.match(css, /var\(--official-surface-solid/);
  assert.match(css, /color-scheme: inherit/);
  assert.doesNotMatch(css, /table/);
});

test("private and public referee surfaces share the shell but retain the dedicated card", async () => {
  const [privateProfile, publicProfile] = await Promise.all([
    source("app/_components/referee-platform-client.tsx"),
    source("app/arbitros/[slug]/public-referee-profile.tsx"),
  ]);
  for (const component of [privateProfile, publicProfile]) {
    assert.match(component, /OfficialProductShellV2/);
    assert.match(component, /RefereeProfileCard/);
  }
  assert.match(privateProfile, /data-referee-section="identity"/);
  assert.match(privateProfile, /data-referee-section="marketplace"/);
  assert.match(privateProfile, /data-referee-section="assignments"/);
  assert.match(privateProfile, /data-referee-section="statistics"/);
  assert.match(publicProfile, /Estadísticas disciplinarias/);
  assert.match(publicProfile, /NOT_AVAILABLE/);
  assert.match(publicProfile, /aria-label="Detalle del perfil arbitral"[\s\S]*role="region"[\s\S]*tabIndex=\{0\}/);
  assert.doesNotMatch(publicProfile, /(?:GRL|Rating|estrellas|amarillas|rojas|azules)/i);
});

test("referee controls inherit the Official UI theme instead of forcing dark fields", async () => {
  const css = await source("app/_components/referee-platform-client.module.css");
  assert.match(css, /var\(--official-surface-solid/);
  assert.match(css, /var\(--official-surface-soft/);
  assert.match(css, /var\(--official-text/);
  assert.match(css, /var\(--official-muted/);
});

test("assignment presentation preserves every R3 command and translates schedule conflicts", async () => {
  const client = await source("app/_components/referee-platform-client.tsx");
  for (const action of ["assignment.propose", "assignment.accept", "assignment.decline", "assignment.cancel", "assignment.replace", "assignment.reconcile"]) {
    assert.match(client, new RegExp(action.replace(".", "\\.")));
  }
  assert.match(client, /MATCH_SCHEDULE_CHANGED/);
  assert.match(client, /El horario del partido ha cambiado\. Revisa la nueva fecha antes de confirmar\./);
  assert.match(client, /REFEREE_ASSIGNMENT_TIME_CONFLICT/);
  assert.match(client, /partido en conflicto/i);
  assert.doesNotMatch(client, /conflict[\s\S]{0,120}(?:rating|valoración)/i);
});

test("rotation changes layout without remounting or duplicating the R3 functional tree", async () => {
  const [shell, privateProfile, marketPanel] = await Promise.all([
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/_components/referee-platform-client.tsx"),
    source("app/mercado/referee-marketplace-panel.tsx"),
  ]);
  assert.equal(shell.match(/\{children\}/g)?.length, 1);
  assert.match(shell, /data-layout-mode={mode}/);
  assert.match(privateProfile, /useState<RefereeJson \| null>\(previewData\)/);
  assert.match(marketPanel, /useState\(\(\) => refereeText\(previewItems\?\.\[0\]/);
  assert.doesNotMatch(privateProfile + marketPanel, /key={.*(?:orientation|layoutMode|innerWidth)/);
});

test("the referee lab is noindex and offers isolated visual-review fixtures", async () => {
  const [layout, page, fixtures, css] = await Promise.all([
    source("app/laboratorio-referee-platform/layout.tsx"),
    source("app/laboratorio-referee-platform/page.tsx"),
    source("app/laboratorio-referee-platform/referee-platform-fixtures.ts"),
    source("app/laboratorio-referee-platform/referee-platform-lab.module.css"),
  ]);
  assert.match(layout, /robots: \{ follow: false, index: false \}/);
  for (const surface of ["market", "private", "public", "proposed", "confirmed", "admin"]) assert.match(page, new RegExp(`"${surface}"`));
  assert.match(page, /previewItems={refereeMarketFixtures}/);
  assert.match(page, /previewData={refereePrivateFixture/);
  assert.match(page, /data-shell-variant="PLATFORM_ADMIN"|PlatformShell/);
  assert.match(css, /adminControls p \{ color: var\(--admin-muted, #9fb0aa\)/);
  assert.doesNotMatch(fixtures, /supabase|\.rpc\(|fetch\(|localStorage|indexedDB/);
});

test("Control Center remains PLATFORM_ADMIN and is not wrapped in a game HUD", async () => {
  const [shell, page] = await Promise.all([
    source("app/admin/_components/platform-shell.tsx"),
    source("app/admin/referees/page.tsx"),
  ]);
  assert.match(shell, /data-shell-variant="PLATFORM_ADMIN"/);
  assert.doesNotMatch(page, /OfficialProductShellV2/);
  assert.match(page, /requirePlatformPage\("referees\.read"\)/);
});

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { PRODUCT_PRIMARY_DESTINATIONS } from "../app/_components/product-navigation-contract";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("V3A exposes play-first navigation only", async () => {
  const [shell, mobileNav] = await Promise.all([
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/mobile-app-nav.tsx"),
  ]);

  assert.deepEqual(PRODUCT_PRIMARY_DESTINATIONS.map(({ id, label }) => [id, label]), [
    ["inicio", "Inicio"],
    ["partido", "Partidos"],
    ["retos", "Retos"],
    ["mercado", "Mercado"],
  ]);
  assert.match(shell, /data-social-core="v3a"/);
  assert.match(shell, /const primaryItems[^=]*= PRODUCT_PRIMARY_DESTINATIONS/);
  assert.match(mobileNav, /PRODUCT_PORTRAIT_DESTINATIONS/);
  assert.doesNotMatch(shell, /contextualDestinationsForPerspective\(perspective\)/);
});

test("team identity and account actions own secondary navigation", async () => {
  const shell = await source("app/_components/official-product-shell-v2.tsx");
  for (const label of ["Ver equipo", "Gestionar equipo", "Crear equipo", "Mi perfil", "Mi carta", "Mi equipo", "Ajustes", "Cerrar sesión"]) {
    assert.match(shell, new RegExp(label));
  }
  assert.match(shell, /perspective === "team-admin" \|\| perspective === "team-owner"/);
  assert.match(shell, /platformOwner \? <Link href="\/admin">Administración<\/Link>/);
  assert.match(shell, /platformOwner \? <Link href="\/admin\/demo">Mundo Demo completo<\/Link>/);
});

test("platform owner controls fail closed against the canonical server session", async () => {
  const hook = await source("app/_components/use-canonical-platform-owner.ts");
  assert.match(hook, /useState\(false\)/);
  assert.match(hook, /fetch\("\/api\/platform-admin\/session"/);
  assert.match(hook, /cache: "no-store"/);
  assert.match(hook, /body\?\.access\?\.role === "platform_owner"/);
  assert.doesNotMatch(hook, /email|@/i);
});

test("social Demo and full platform Demo have separate canonical entry points", async () => {
  const [demo, publicPage, adminPage] = await Promise.all([
    source("app/demo-world/demo-world-app.tsx"),
    source("app/demo/page.tsx"),
    source("app/admin/demo/page.tsx"),
  ]);
  assert.match(publicPage, /mode="social"/);
  assert.match(adminPage, /requirePlatformPage\("overview\.read"\)/);
  assert.match(adminPage, /session\.access\.role !== "platform_owner"/);
  assert.match(adminPage, /mode="full"/);
  assert.match(demo, /socialDemoTabs = new Set[^\n]+\["avisos", "inicio", "partido", "retos", "mercado", "equipo", "perfil"\]/);
  assert.match(demo, /fullMode \? <DemoDomainMenu/);
});

test("Retos is independent and Mercado keeps exactly three discovery domains", async () => {
  const [market, retos, challengePanel] = await Promise.all([
    source("app/mercado/marketplace-client.tsx"),
    source("app/retos/page.tsx"),
    source("app/mercado/team-challenges-panel.tsx"),
  ]);
  assert.match(market, /type MarketTab = "equipos" \| "jugadores" \| "partidos"/);
  assert.match(market, /return "partidos"/);
  assert.match(market, /window\.location\.replace\("\/retos"\)/);
  assert.doesNotMatch(market, /RefereeMarketplacePanel|ClubDirectoryClient/);
  assert.match(retos, /active=\{matchMode \? "partido" : "retos"\}/);
  assert.match(retos, /data-mobile-tab=\{matchMode \? "partido" : "retos"\}/);
  assert.match(retos, /Activos/);
  assert.match(retos, /Historial/);
  assert.match(retos, /\+ Retar equipo/);
  assert.match(retos, /<TeamChallengesPanel/);
  assert.match(challengePanel, /useState\(initialOpponent\?\.teamCode \?\? initialTeamCode\)/);
  assert.doesNotMatch(challengePanel, /Sincronización|Revisión N/);
});

test("match navigation is contextual and never exposes a permanent Admin tab", async () => {
  const [page, demo] = await Promise.all([
    source("app/page.tsx"),
    source("app/demo-world/demo-world-app.tsx"),
  ]);
  assert.match(page, /matchFinalized[\s\S]*\? \["proximo", "resultado", "campo"\][\s\S]*: \["proximo", "campo", "alineacion"\]/);
  assert.match(page, /if \(pane === "proximo"\) return "Resumen"/);
  assert.match(page, /if \(pane === "campo"\) return matchFinalized \? "Estadísticas" : "Jugadores"/);
  assert.match(page, /if \(pane === "alineacion"\) return "Equipos"/);
  assert.match(page, /Administrar partido/);
  assert.doesNotMatch(page, /matchManagerPanes[^\n]+"admin"/);
  assert.match(demo, /match\.status === "finalized"[\s\S]*\["proximo", "resultado", "historico"\][\s\S]*\["proximo", "historico", "alineacion"\]/);
  for (const label of ["Resumen", "Jugadores", "Equipos", "Resultado", "Estadísticas", "Administrar partido"]) {
    assert.match(demo, new RegExp(label));
  }
  assert.doesNotMatch(demo, /\["proximo", "alineacion", "resultado", "historico", "admin"\]/);
});

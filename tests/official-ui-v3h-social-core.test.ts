import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { PRODUCT_PRIMARY_DESTINATIONS } from "../app/_components/product-navigation-contract";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("V3H public landing has one message, one primary action and an honest Demo", async () => {
  const page = await source("app/page.tsx");
  const start = page.indexOf("if (isPublicEntryMode)");
  const end = page.indexOf("return (\n    <OfficialProductShellV2", start);
  const landing = page.slice(start, end);

  assert.match(landing, /<h1>Organiza tu pachanga\.<\/h1>/);
  assert.match(landing, /Invita a tus amigos, crea los equipos y juega\./);
  assert.match(landing, /href="\/demo\?review=1">Probar Demo/);
  assert.match(landing, /label="Entrar"/);
  assert.match(landing, /href="\/mercado">Buscar una pachanga/);
  for (const step of ["Crea el partido", "Reúne a los jugadores", "Juega y guarda el resultado"]) assert.match(landing, new RegExp(step));
  assert.match(landing, /<b>SIMULACIÓN<\/b>/);
  assert.doesNotMatch(landing, /Miles de jugadores|Cientos de partidos|Actividad en directo|Clubes|Ligas|Torneos|Billing|Control Center/);
});

test("V3H keeps exactly five primary social destinations", () => {
  assert.deepEqual(PRODUCT_PRIMARY_DESTINATIONS.map(({ id, label }) => [id, label]), [
    ["inicio", "Inicio"],
    ["partido", "Partidos"],
    ["retos", "Retos"],
    ["mercado", "Mercado"],
    ["equipo", "Equipo"],
  ]);
});

test("Retos uses one local navigation and one compact filter", async () => {
  const [page, panel] = await Promise.all([
    source("app/retos/page.tsx"),
    source("app/mercado/team-challenges-panel.tsx"),
  ]);

  assert.match(page, /<nav className=\{styles\.tabs\} aria-label="Vistas de retos">/);
  assert.match(page, /<select aria-label="Filtrar retos activos"/);
  assert.doesNotMatch(page, /<nav className=\{styles\.filters\}/);
  assert.match(panel, /Aún no tienes equipo/);
  assert.match(panel, /No podemos abrir tus Retos/);
  assert.match(panel, /Entra para ver tus Retos/);
  const emptyBranch = panel.slice(panel.indexOf("if (!memberships.length)"), panel.indexOf("if (matchChallengeId"));
  assert.doesNotMatch(emptyBranch, /renderNotice\(\)/);
  assert.doesNotMatch(emptyBranch, /Unirme a un equipo/);
});

test("Demo Retos uses theme-aware surfaces in light and dark modes", async () => {
  const styles = await source("app/demo-world/demo-world.module.css");

  assert.match(styles, /\.demoChallengeFilterSelect select \{[^}]*background: var\(--demo-panel-soft\)/);
  assert.match(styles, /\.demoChallengeCard \{[^}]*background: var\(--demo-panel\)/s);
  assert.match(styles, /\.demoChallengeHistory > button \{[^}]*background: var\(--demo-panel\)/);
  assert.match(styles, /\.demoChallengeFocus \{[^}]*background: var\(--demo-panel\)/s);
  assert.match(styles, /\.demoChallengeFields select \{[^}]*background: var\(--demo-panel-soft\)[^}]*color-scheme: inherit/);
  assert.match(styles, /\.demoOpponentList > button \{[^}]*background: var\(--demo-panel-soft\)/);
  assert.match(styles, /\.demoChallengeDetail dl > div \{[^}]*background: var\(--demo-panel\)/);
});

test("Mercado keeps location first and compacts geolocation accessibly", async () => {
  const [market, styles] = await Promise.all([
    source("app/mercado/marketplace-client.tsx"),
    source("app/mercado/marketplace-v3d.module.css"),
  ]);

  assert.match(market, /placeholder="¿Dónde quieres jugar\?"/);
  assert.match(market, /className=\{styles\.locationAction\}/);
  assert.match(market, /aria-label=\{locating \? "Buscando tu ubicación" : "Usar mi ubicación"\}/);
  assert.match(styles, /\.locationAction span \{ display: none; \}/);
  assert.match(styles, /grid-template-columns: minmax\(0, 1fr\) 44px 44px/);
});

test("social Demo exposes the seven local-only V3H review journeys", async () => {
  const [app, review] = await Promise.all([
    source("app/demo-world/demo-world-app.tsx"),
    source("app/demo-world/demo-social-quick-review.tsx"),
  ]);

  assert.match(app, /<b>SIMULACIÓN<\/b> · datos ficticios · sesión local/);
  assert.match(app, /socialJourneyLauncher[\s\S]*<small>SIMULACIÓN<\/small><span>Revisión rápida<\/span>/);
  assert.match(app, /get\("review"\) !== "1"/);
  assert.match(app, /requestAnimationFrame\(\(\) => setSocialQuickReviewOpen\(true\)\)/);
  assert.match(app, /cancelAnimationFrame\(frame\)/);
  assert.match(app, /DemoSocialQuickReview/);
  assert.match(app, /fullMode \? world\.core\.perspectives : world\.core\.perspectives\.filter/);
  assert.match(app, /fullMode \? "Season Score V3" : `Ranking de \$\{selectedTeam\.name\}`/);
  assert.match(app, /ausencias sin avisar/);
  assert.match(app, /<select aria-label="Filtrar Retos"/);

  for (const label of ["Usuario nuevo", "Jugador con equipo", "Owner del equipo", "Crear partido", "Retar rival", "Buscar jugador", "Resolver Avisos"]) {
    assert.match(review, new RegExp(label));
  }
  for (const proof of ["remoteWrites = 0", "externalNotifications = 0", "pushSent = 0", "emailsSent = 0", "realEntities = 0", "StripeCalls = 0"]) {
    assert.match(review, new RegExp(proof.replace(/[=]/g, "\\=")));
  }
  assert.match(review, /Anterior/);
  assert.match(review, /Reiniciar/);
  assert.match(review, /Siguiente/);
  assert.match(review, /returnFocusRef/);
  assert.match(review, /requestAnimationFrame/);
  assert.match(review, /const dialog = dialogRef\.current/);
  assert.match(review, /!dialog\?\.isConnected/);
});

test("V3H visual audit captures Inbox and notification settings separately", async () => {
  const visualAudit = await source("scripts/visual-audit-v1.mjs");
  assert.match(visualAudit, /key: "avisos", path: "\/avisos"/);
  assert.match(visualAudit, /key: "ajustes-notificaciones", path: "\/ajustes\/notificaciones"/);
  assert.doesNotMatch(visualAudit, /key: "avisos", path: "\/perfil\/avisos"/);
});

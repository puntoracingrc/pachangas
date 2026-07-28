import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("builds Pachangas IQ HTML", async () => {
  const html = await readFile(new URL("../.next/server/app/index.html", import.meta.url), "utf8");
  assert.match(html, /<html lang="es">/i);
  assert.match(html, /<title>Pachangas IQ<\/title>/i);
  assert.match(html, /El grupo del partido, pero con memoria\./);
  assert.match(html, /Confirmados/);
  assert.match(html, /Equipos sugeridos/i);
  assert.match(html, /Alineación abierta/);
  assert.match(html, /Registro/);
  assert.match(html, /Entrar con Google/);
  assert.match(html, /Entra para crear tu equipo/);
  assert.match(html, /Finalizar partido/);
  assert.match(html, /Comparte este partido!/);
  assert.match(html, /Copiar link/);
  assert.match(html, /Abrir manual de usuario/);
  assert.doesNotMatch(html, /Manual de usuario<\/span>/);
  assert.doesNotMatch(html, /Your site is taking shape|Building your site|react-loading-skeleton/i);
});

test("builds the user manual as its own page", async () => {
  const html = await readFile(new URL("../.next/server/app/manual.html", import.meta.url), "utf8");
  assert.match(html, /Manual de usuario/);
  assert.match(html, /Equipo privado/);
  assert.match(html, /Ranking vivo/);
  assert.match(html, /Volver/);
});

test("keeps the project wired to the Pachangas app", async () => {
  const [page, layout, packageJson, supabaseClient] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    readFile(new URL("../app/supabaseClient.ts", import.meta.url), "utf8"),
  ]);

  assert.match(page, /join_pachanga_team/);
  assert.match(page, /MemberRole/);
  assert.match(page, /Equipo pachanguero/);
  assert.match(page, /grupo/);
  assert.match(page, /invite/);
  assert.match(page, /remoteInviteToken/);
  assert.match(page, /canEditMatchSettings\s*=\s*canUseAdminControls\s*&&\s*!matchFinalized/);
  assert.match(page, /Partido finalizado/);
  assert.match(layout, /title:\s*"Pachangas IQ"/);
  assert.match(packageJson, /"@supabase\/supabase-js"/);
  assert.match(supabaseClient, /NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY/);
  assert.doesNotMatch(page, /SkeletonPreview/);
  assert.doesNotMatch(layout, /Starter Project|codex-preview/);
});

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("builds Pachanga IQ HTML", async () => {
  const html = await readFile(new URL("../.next/server/app/index.html", import.meta.url), "utf8");
  assert.match(html, /<html lang="es">/i);
  assert.match(html, /<title>Pachanga IQ<\/title>/i);
  assert.match(html, /El grupo del partido, pero con memoria\./);
  assert.match(html, /Confirmados/);
  assert.match(html, /Equipos sugeridos/i);
  assert.match(html, /Abrir WhatsApp/);
  assert.doesNotMatch(html, /Your site is taking shape|Building your site|react-loading-skeleton/i);
});

test("keeps the project wired to the Pachanga app", async () => {
  const [page, layout, packageJson, supabaseClient] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    readFile(new URL("../app/supabaseClient.ts", import.meta.url), "utf8"),
  ]);

  assert.match(page, /join_pachanga_group/);
  assert.match(page, /grupo/);
  assert.match(page, /invite/);
  assert.match(page, /remoteInviteToken/);
  assert.match(layout, /title:\s*"Pachanga IQ"/);
  assert.match(packageJson, /"@supabase\/supabase-js"/);
  assert.match(supabaseClient, /NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY/);
  assert.doesNotMatch(page, /SkeletonPreview/);
  assert.doesNotMatch(layout, /Starter Project|codex-preview/);
});

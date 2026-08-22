import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  OFFICIAL_UI_V2_TOKENS,
  resolveOfficialLayoutMode,
} from "../app/_design-v2/official-ui-v2-contract";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("resolves desktop, portrait and every required game-landscape viewport", () => {
  assert.equal(resolveOfficialLayoutMode({ coarsePointer: true, height: 844, landscape: false, width: 390 }), "MOBILE_PORTRAIT");
  assert.equal(resolveOfficialLayoutMode({ coarsePointer: false, height: 900, landscape: false, width: 1440 }), "DESKTOP");

  for (const [width, height] of [[667, 375], [740, 360], [812, 375], [844, 390], [896, 414], [932, 430]]) {
    assert.equal(
      resolveOfficialLayoutMode({ coarsePointer: false, height, landscape: true, width }),
      "MOBILE_GAME_LANDSCAPE",
      `${width}x${height}`,
    );
  }

  assert.equal(resolveOfficialLayoutMode({ coarsePointer: true, height: 768, landscape: true, width: 1024 }), "MOBILE_GAME_LANDSCAPE");
  assert.equal(resolveOfficialLayoutMode({ coarsePointer: false, height: 768, landscape: true, width: 1024 }), "DESKTOP");
  assert.equal(
    resolveOfficialLayoutMode({ coarsePointer: false, height: 600, landscape: true, width: 960 }),
    "DESKTOP",
    "desktop at 150% zoom must not become the game HUD",
  );
  assert.equal(
    resolveOfficialLayoutMode({ coarsePointer: true, height: 600, landscape: true, width: 960 }),
    "MOBILE_GAME_LANDSCAPE",
    "a touch landscape device keeps the game HUD",
  );
});

test("keeps a semantic Demo-derived token layer", () => {
  assert.equal(OFFICIAL_UI_V2_TOKENS.color.background, "#07110f");
  assert.equal(OFFICIAL_UI_V2_TOKENS.color.accent, "#c8ef5d");
  assert.equal(OFFICIAL_UI_V2_TOKENS.navigation.landscapeRail, "88px");
  assert.ok(Object.keys(OFFICIAL_UI_V2_TOKENS.color).includes("surfacePrimary"));
  assert.ok(Object.values(OFFICIAL_UI_V2_TOKENS.radius).every((value) => Number.parseInt(value, 10) <= 8));
});

test("the shell changes composition without remounting route content", async () => {
  const [component, css, icon] = await Promise.all([
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/_components/official-product-shell-v2.module.css"),
    source("public/icon-monochrome.svg"),
  ]);

  assert.match(component, /visualViewport/);
  assert.match(component, /orientationchange/);
  assert.doesNotMatch(component, /userAgent|navigator\.platform/);
  assert.equal(component.match(/\{children\}/g)?.length, 1);
  assert.match(component, /data-layout-mode=\{mode\}/);
  assert.match(component, /Navegación de modo juego/);
  assert.match(component, /src="\/icon-192\.png"/);
  assert.match(css, /100dvh/);
  assert.match(css, /display-mode: standalone/);
  assert.match(css, /env\(safe-area-inset-left\)/);
  assert.match(css, /env\(safe-area-inset-right\)/);
  assert.match(css, /prefers-reduced-motion: reduce/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /--official-accent-text: #476b00/);
  assert.match(css, /--official-overlay: rgba\(255, 255, 255, 0\.94\)/);
  assert.equal(icon.match(/fill-rule="evenodd"/g)?.length, 2);
  assert.doesNotMatch(css, /\b100vh\b/);
});

test("priority production routes share the official shell without replacing their logic", async () => {
  const routes = [
    "app/page.tsx",
    "app/mercado/page.tsx",
    "app/ranking/provincial-ranking-product.tsx",
    "app/perfil/avisos/page.tsx",
    "app/equipo/identidad/page.tsx",
    "app/personalizar-carta/page.tsx",
  ];

  for (const route of routes) {
    const page = await source(route);
    assert.match(page, /OfficialProductShellV2/, route);
  }

  const market = await source("app/mercado/page.tsx");
  for (const capability of ["jugadores", "partidos", "retos", "equipos"]) assert.match(market, new RegExp(capability));
  assert.match(market, /\.rpc\(/);
});

test("the visual lab is isolated, noindex and free from productive/demo data authority", async () => {
  const [page, css] = await Promise.all([
    source("app/laboratorio-official-ui-v2/page.tsx"),
    source("app/laboratorio-official-ui-v2/official-ui-v2-lab.module.css"),
  ]);

  assert.match(page, /follow: false, index: false/);
  assert.match(page, /Fixtures visuales · sin Supabase/);
  assert.match(page, /data-capture/);
  assert.match(page, />Finalizar partido</);
  assert.doesNotMatch(page, /supabaseClient|\.rpc\(|localStorage|indexedDB|demo-world.*json/i);
  assert.match(css, /data-capture="true"/);
  assert.match(css, /var\(--official-surface/);
  assert.match(css, /var\(--official-accent-text/);
  assert.match(css, /orientation:landscape/);
  assert.match(css, /max-width:760px/);
});

test("Control Center retains the explicit platform-admin shell", async () => {
  const [adminShell, adminStyles] = await Promise.all([
    source("app/admin/_components/platform-shell.tsx"),
    source("app/admin/platform-admin.module.css"),
  ]);
  assert.match(adminShell, /data-shell-variant="PLATFORM_ADMIN"/);
  assert.doesNotMatch(adminShell, /OfficialProductShellV2/);
  assert.match(adminStyles, /\.sidebar \{[\s\S]*visibility: hidden;[\s\S]*pointer-events: none;/);
  assert.match(adminStyles, /\.sidebarOpen \{[\s\S]*visibility: visible;[\s\S]*pointer-events: auto;/);
});

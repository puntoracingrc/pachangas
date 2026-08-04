import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { MobileAppNav } from "../app/mobile-app-nav";

test("keeps the admin-player switch visible in both preview states", () => {
  const adminView = renderToStaticMarkup(
    <MobileAppNav active="inicio" adminViewPreview={{ active: false, onToggle: () => undefined }} />,
  );
  const playerView = renderToStaticMarkup(
    <MobileAppNav active="inicio" adminViewPreview={{ active: true, onToggle: () => undefined }} />,
  );
  const regularPlayer = renderToStaticMarkup(<MobileAppNav active="inicio" />);

  assert.match(adminView, />Admin</);
  assert.match(adminView, /Cambiar a vista jugador/);
  assert.match(playerView, />Jugador</);
  assert.match(playerView, /Volver a vista admin/);
  assert.match(playerView, /player-preview-active/);
  assert.doesNotMatch(regularPlayer, /admin-view-preview-button/);
});

test("keeps real authorization separate from the visual preview", async () => {
  const [home, market, previewState, css] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/mercado/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/admin-view-preview.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
  ]);

  assert.match(home, /const actualCanManageTeam = Boolean/);
  assert.match(home, /const playerPreviewActive = canPreviewPlayerView && previewRequested/);
  assert.match(home, /const canManageTeam = actualCanManageTeam && !playerPreviewActive/);
  assert.match(home, /isDemoMode: isDemoMode && !playerPreviewActive/);
  assert.doesNotMatch(home, /canDragPlayers=\{\(canEditLineup \|\| isDemoMode\)/);
  assert.match(home, /adminViewPreview=\{canPreviewPlayerView/);
  assert.match(market, /const canUseMarketAdminControls = canInvite && !playerPreviewActive/);
  assert.match(market, /adminViewPreview=\{canInvite/);
  assert.match(previewState, /window\.sessionStorage\.setItem/);
  assert.match(previewState, /window\.sessionStorage\.removeItem/);
  assert.doesNotMatch(previewState, /setCurrentRole|supabase|\.rpc\(/);
  assert.match(css, /\.mobile-app-nav-inner\.has-admin-view-preview\s*\{\s*grid-template-columns:\s*repeat\(6/);
});

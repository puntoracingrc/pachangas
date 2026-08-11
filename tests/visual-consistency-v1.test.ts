import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync } from "node:fs";
import test from "node:test";

import { PREMIUM_ART_PACK_V1 } from "../app/laboratorio-premium-art-pack/premium-art-pack-catalog";
import { SERVICE_UNAVAILABLE_MESSAGE, userFacingError } from "../app/user-facing-error";
import { TEAM_COSMETIC_REWARD_MAPPINGS_V1 } from "../simulation/synthetic-world/scripts/team-cosmetic-rewards-v1";

const root = process.cwd();
const source = (file: string) => readFileSync(`${root}/${file}`, "utf8");

test("the Premium Art Pack is a bounded lab-only catalog with unique proposals", () => {
  assert.ok(PREMIUM_ART_PACK_V1.length >= 20 && PREMIUM_ART_PACK_V1.length <= 30);
  assert.equal(new Set(PREMIUM_ART_PACK_V1.map((item) => item.id)).size, PREMIUM_ART_PACK_V1.length);
  assert.equal(PREMIUM_ART_PACK_V1.filter((item) => item.technique === "3D prerender").length, 2);
  assert.equal(PREMIUM_ART_PACK_V1.filter((item) => item.decision === "DESCARTAR").length, 1);
  assert.ok(PREMIUM_ART_PACK_V1.every((item) => item.lod && item.performance && item.reuse));

  for (const item of PREMIUM_ART_PACK_V1) {
    if (!item.asset) continue;
    assert.match(item.asset, /^\/lab\/premium-art-pack-v1\//);
    const file = `${root}/public${item.asset}`;
    assert.equal(existsSync(file), true, `${item.name} is missing ${file}`);
    assert.ok(statSync(file).size < 64 * 1024, `${item.name} exceeds the 64 KB delivery budget`);
    assert.doesNotMatch(item.asset, /\.glb$/i);
  }
});

test("the art lab remains noindex and outside normal navigation", () => {
  const layout = source("app/laboratorio-premium-art-pack/layout.tsx");
  const page = source("app/laboratorio-premium-art-pack/page.tsx");
  const rootPage = source("app/page.tsx");
  assert.match(layout, /follow:\s*false,\s*index:\s*false/);
  assert.match(page, /Laboratorio · no productivo/);
  assert.doesNotMatch(rootPage, /laboratorio-premium-art-pack/);
});

test("the five active team cosmetic reward mappings stay exact", () => {
  assert.deepEqual(TEAM_COSMETIC_REWARD_MAPPINGS_V1, [
    { achievementKey: "team.external.wins.001", cosmeticKey: "team.shield.border.copper", firstOccurrenceOnly: true, mappingKey: "first_challenge_win" },
    { achievementKey: "team.external.matches.010", cosmeticKey: "team.shield.ornament.banner", firstOccurrenceOnly: false, mappingKey: "ten_challenges" },
    { achievementKey: "team.matches.025", cosmeticKey: "team.shield.ornament.laurels", firstOccurrenceOnly: false, mappingKey: "twenty_five_matches" },
    { achievementKey: "team.matches.050", cosmeticKey: "team.shield.border.silver", firstOccurrenceOnly: false, mappingKey: "fifty_matches" },
    { achievementKey: "team.external.clean_sheets.001", cosmeticKey: "team.shield.effect.edge_glow", firstOccurrenceOnly: true, mappingKey: "first_clean_sheet" },
  ]);
});

test("technical infrastructure errors are converted into product copy", () => {
  assert.equal(userFacingError({ code: "PGRST116", message: "PostgREST relation missing" }), "No se pudo completar la acción. Vuelve a intentarlo.");
  assert.equal(userFacingError({ message: "TypeError: Failed to fetch" }), "No se pudo completar la acción. Vuelve a intentarlo.");
  assert.equal(userFacingError({ message: "Network request failed" }), "No se pudo completar la acción. Vuelve a intentarlo.");
  assert.doesNotMatch(userFacingError({ code: "PT409", message: "stale" }), /PT409|stale/i);
  assert.equal(userFacingError({ message: "No quedan plazas para este partido." }), "No quedan plazas para este partido.");
  assert.doesNotMatch(SERVICE_UNAVAILABLE_MESSAGE, /Supabase|PostgREST|RPC/i);

  for (const file of [
    "app/equipo/identidad/page.tsx",
    "app/personalizar-carta/page.tsx",
    "app/mercado/page.tsx",
    "app/notification-preferences.tsx",
  ]) {
    assert.doesNotMatch(source(file), /Supabase no está configurado|Google Places pendiente/);
  }
});

test("visual regression matrix includes core routes, spot viewports and PWA standalone", () => {
  const audit = source("scripts/visual-audit-v1.mjs");
  for (const marker of [
    "1920, height: 1080",
    "360, height: 800",
    "844, height: 390",
    "displayMode: \"standalone\"",
    "key: \"zoom-200\"",
    "prefers-reduced-motion",
    "demo-partido-alineacion",
    "mercado-retos",
    "/laboratorio-premium-art-pack",
    "doc.scrollWidth",
    "failedImages",
    "viewportViolations",
    "gameChromeViolations",
    "captureBeyondViewport: false",
    "VISUAL_AUDIT_SURFACES",
  ]) {
    assert.match(audit, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }
});

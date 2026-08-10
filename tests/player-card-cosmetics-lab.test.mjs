import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import test from "node:test";

const pageUrl = new URL("../app/laboratorio-cosmeticos-ficha/page.tsx", import.meta.url);
const stylesUrl = new URL("../app/laboratorio-cosmeticos-ficha/page.module.css", import.meta.url);
const componentUrl = new URL("../app/_components/player-card-view.tsx", import.meta.url);

test("the cosmetics laboratory reuses the product card presentation and exposes exactly ten samples", async () => {
  const [page, component, home] = await Promise.all([
    readFile(pageUrl, "utf8"),
    readFile(componentUrl, "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
  ]);

  assert.match(page, /import \{ PlayerCardView \}/);
  assert.match(home, /import \{ PlayerCardView \}/);
  const cosmeticsBlock = page.slice(page.indexOf("const COSMETICS"), page.indexOf("const FRAME_OPTIONS"));
  assert.equal(cosmeticsBlock.match(/\{ id:/g)?.length, 10);
  assert.deepEqual(
    [...cosmeticsBlock.matchAll(/id: "([^"]+)"/g)].map((match) => match[1]),
    ["barrio-acero", "retro-cromo", "future-iq", "asfalto-nocturno", "papel-liga", "grid-iq", "focos", "iq-scan", "de-toda-la-vida", "motor-del-equipo"],
  );
  for (const slot of ["card_frame", "card_background", "card_effect", "player_title"]) assert.match(page, new RegExp(slot));
  assert.match(component, /fifa-player-card/);
  assert.match(page, /LABORATORIO VISUAL|Laboratorio visual/);
  assert.match(page, /No es catálogo definitivo/);
});

test("the lab is visual-only and keeps real badge names as explicit previews", async () => {
  const page = await readFile(pageUrl, "utf8");

  assert.match(page, /Hat-trick/);
  assert.match(page, /Primera conquista/);
  assert.match(page, /Póker/);
  assert.match(page, /Preview local/);
  assert.match(page, /sin propiedad ni equipamiento/);
  assert.doesNotMatch(page, /supabase|\.rpc\(|clientWriteFetch|localStorage|indexedDB/i);
});

test("animated effects are compositor-only and have a static reduced-motion treatment", async () => {
  const css = await readFile(stylesUrl, "utf8");

  assert.match(css, /@keyframes stadiumLights/);
  assert.match(css, /@keyframes iqScan/);
  assert.match(css, /will-change: opacity, transform/);
  assert.match(css, /will-change: transform/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(css, /animation: none/);
  assert.doesNotMatch(css, /canvas|webgl/i);
});

test("the lab defines desktop, portrait and landscape layouts without a remote image", async () => {
  const [css, page, image] = await Promise.all([
    readFile(stylesUrl, "utf8"),
    readFile(pageUrl, "utf8"),
    stat(new URL("../public/lab/player-card-preview.jpg", import.meta.url)),
  ]);

  assert.match(css, /@media \(max-width: 720px\)/);
  assert.match(css, /@media \(orientation: landscape\) and \(max-height: 600px\)/);
  assert.match(css, /overflow-x: hidden/);
  assert.match(css, /env\(safe-area-inset-right\)/);
  assert.match(page, /\/lab\/player-card-preview\.jpg/);
  assert.ok(image.size < 250_000, "The fixed preview portrait should stay below 250 KB");
});

test("the production build contains the interactive laboratory route", async () => {
  const html = await readFile(new URL("../.next/server/app/laboratorio-cosmeticos-ficha.html", import.meta.url), "utf8");
  assert.match(html, /Cosméticos de ficha/);
  assert.match(html, /Carta en tiempo real/);
  assert.match(html, /Galería por pieza/);
  assert.match(html, /Alejandro Martínez/);
});

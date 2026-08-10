import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import test from "node:test";

const pageUrl = new URL("../app/laboratorio-cosmeticos-ficha/page.tsx", import.meta.url);
const stylesUrl = new URL("../app/laboratorio-cosmeticos-ficha/page.module.css", import.meta.url);
const rendererUrl = new URL("../app/_components/player-cosmetic-card.tsx", import.meta.url);
const catalogUrl = new URL("../app/player-cosmetics-catalog.ts", import.meta.url);

test("the V0.2 laboratory reuses the production renderer and shared editor", async () => {
  const [page, renderer, home] = await Promise.all([
    readFile(pageUrl, "utf8"),
    readFile(rendererUrl, "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(page, /PlayerCosmeticCard/);
  assert.match(page, /CosmeticEditorShell/);
  assert.match(renderer, /PlayerCardView/);
  assert.match(home, /PlayerCosmeticCard/);
  assert.match(page, /Laboratorio visual V0\.2/);
  assert.match(page, /PLAYER_COSMETIC_PROTOTYPES\.length/);
  assert.match(page, /PLAYER_COSMETIC_CATALOG\.length/);
});

test("the shared catalog contains 14 V1 pieces and 16 visual-only experiments", async () => {
  const catalog = await readFile(catalogUrl, "utf8");
  const selected = catalog.slice(catalog.indexOf("const selected"), catalog.indexOf("const experimental"));
  const experimental = catalog.slice(catalog.indexOf("const experimental"), catalog.indexOf("export const PLAYER_COSMETIC_CATALOG"));
  assert.equal(selected.match(/key: "/g)?.length, 14);
  assert.equal(experimental.match(/key: "/g)?.length, 16);
  for (const slot of ["frame", "background", "accent", "effect", "title"]) assert.match(selected, new RegExp(`slot: "${slot}"`));
});

test("the lab remains visual-only and badges are explicit previews", async () => {
  const page = await readFile(pageUrl, "utf8");
  assert.match(page, /Hat-trick/);
  assert.match(page, /Primera conquista/);
  assert.match(page, /Póker/);
  assert.doesNotMatch(page, /supabase|\.rpc\(|clientWriteFetch|localStorage|indexedDB/i);
});

test("effects have a reduced-motion treatment and no second card renderer", async () => {
  const [rendererCss, renderer] = await Promise.all([
    readFile(new URL("../app/_components/player-cosmetic-card.module.css", import.meta.url), "utf8"),
    readFile(rendererUrl, "utf8"),
  ]);
  assert.match(rendererCss, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(rendererCss, /animation: none/);
  assert.doesNotMatch(renderer, /fifa-player-card/);
});

test("the lab supports desktop, portrait and landscape with a local lightweight portrait", async () => {
  const [css, image] = await Promise.all([
    readFile(stylesUrl, "utf8"),
    stat(new URL("../public/lab/player-card-preview.jpg", import.meta.url)),
  ]);
  assert.match(css, /@media \(max-width: 720px\)/);
  assert.match(css, /@media \(orientation: landscape\) and \(max-height: 600px\)/);
  assert.match(css, /overflow-x: hidden/);
  assert.match(css, /env\(safe-area-inset-right\)/);
  assert.ok(image.size < 250_000);
});

test("the production build contains the V0.2 laboratory route", async () => {
  const html = await readFile(new URL("../.next/server/app/laboratorio-cosmeticos-ficha.html", import.meta.url), "utf8");
  assert.match(html, /Cosméticos de ficha/);
  assert.match(html, /Exploración por pieza/);
  assert.match(html, /Alejandro Martínez/);
});

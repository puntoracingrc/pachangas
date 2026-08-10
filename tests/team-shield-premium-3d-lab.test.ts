import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const root = process.cwd();

async function source(relativePath: string) {
  return readFile(path.join(root, relativePath), "utf8");
}

test("premium shield lab is isolated, noindex and keeps the canonical 2D renderer", async () => {
  const [layout, page, contract] = await Promise.all([
    source("app/laboratorio-cosmeticos-escudo-3d/layout.tsx"),
    source("app/laboratorio-cosmeticos-escudo-3d/page.tsx"),
    source("app/team-shield-contract.ts"),
  ]);

  assert.match(layout, /robots:\s*\{\s*follow:\s*false,\s*index:\s*false\s*\}/);
  assert.match(page, /import \{ TeamShieldView \}/);
  assert.match(page, /size=\{24\}/);
  assert.match(page, /size=\{32\}/);
  assert.match(page, /Local · sin persistencia/);
  assert.doesNotMatch(page, /localStorage|sessionStorage|supabase|\.rpc\(|fetch\(/i);
  assert.match(contract, /TEAM_SHIELD_SCHEMA_VERSION = 1 as const/);
});

test("all three pipelines share generated assets and expose explicit LOD", async () => {
  const page = await source("app/laboratorio-cosmeticos-escudo-3d/page.tsx");
  assert.match(page, /key: "A"/);
  assert.match(page, /key: "B"/);
  assert.match(page, /key: "C"/);
  assert.match(page, /dynamic\(/);
  assert.match(page, /ssr: false/);
  assert.match(page, /data-frame-count="8"/);
  assert.match(page, /ball-premium-frame-\$\{frame\}\.webp/);
  assert.match(page, /48 · render/);
  assert.match(page, /64 · sprite/);
  assert.match(page, /Editor · GLB en vista principal/);
});

test("orientation permission is user initiated and reduced motion stays static", async () => {
  const [motion, renderer, styles] = await Promise.all([
    source("app/laboratorio-cosmeticos-escudo-3d/_components/use-premium-motion.ts"),
    source("app/laboratorio-cosmeticos-escudo-3d/_components/premium-shield-3d.tsx"),
    source("app/laboratorio-cosmeticos-escudo-3d/page.module.css"),
  ]);

  assert.match(motion, /constructor\.requestPermission \? await constructor\.requestPermission\(\)/);
  assert.match(motion, /window\.addEventListener\("deviceorientation"/);
  assert.match(motion, /sensorPermission !== "granted"/);
  assert.match(renderer, /if \(!reduced\) animate\(\)/);
  assert.match(renderer, /preserveDrawingBuffer: true/);
  assert.match(renderer, /dataset\.canvasNonblank/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(styles, /@media \(orientation: landscape\) and \(max-height: 560px\)/);
});

test("Blender source and generated artifacts are reproducible and valid", async () => {
  const generator = await source("scripts/team-shield-premium-3d/generate-assets.py");
  const assetDirectory = path.join(root, "public/team-shield-premium-3d");
  const assets = [
    "shield-premium-copper.webp",
    "shield-premium-silver.webp",
    "shield-premium-gold.webp",
    "shield-premium-chrome.webp",
    "shield-premium-carbon.webp",
    "crown-premium-gold-overlay.webp",
    "crown-premium-chrome-overlay.webp",
    "team-shield-premium-kit.glb",
  ];
  assets.push(...Array.from({ length: 8 }, (_, index) => `ball-premium-frame-${index}.webp`));

  assert.match(generator, /bpy\.ops\.export_scene\.gltf/);
  assert.match(generator, /bpy\.ops\.wm\.save_as_mainfile/);
  assert.match(generator, /for index in range\(8\)/);

  for (const asset of assets) {
    const details = await stat(path.join(assetDirectory, asset));
    assert.ok(details.size > 4_000, `${asset} must not be empty`);
  }

  const webp = await readFile(path.join(assetDirectory, "shield-premium-gold.webp"));
  assert.equal(webp.subarray(0, 4).toString("ascii"), "RIFF");
  assert.equal(webp.subarray(8, 12).toString("ascii"), "WEBP");
  const glb = await readFile(path.join(assetDirectory, "team-shield-premium-kit.glb"));
  assert.equal(glb.subarray(0, 4).toString("ascii"), "glTF");
});

test("the lab source does not introduce authoritative product mutations", async () => {
  const files = [
    "app/laboratorio-cosmeticos-escudo-3d/page.tsx",
    "app/laboratorio-cosmeticos-escudo-3d/_components/premium-shield-3d.tsx",
    "app/laboratorio-cosmeticos-escudo-3d/_components/use-premium-motion.ts",
  ];
  for (const file of files) {
    const contents = await source(file);
    assert.doesNotMatch(contents, /operationId|expectedRevision|supabase|service_role|\.rpc\(|\.from\(/i);
  }
});

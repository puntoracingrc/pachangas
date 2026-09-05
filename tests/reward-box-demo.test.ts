import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";
import test from "node:test";

const modelUrl = new URL("../public/models/rewards/reward-box-refined.glb", import.meta.url);
const componentSource = readFileSync(new URL("../app/reward-box-demo.tsx", import.meta.url), "utf8");
const pageSource = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");
const stylesSource = readFileSync(new URL("../app/reward-box-demo.module.css", import.meta.url), "utf8");

function readGlbJson() {
  const glb = readFileSync(modelUrl);
  assert.equal(glb.toString("utf8", 0, 4), "glTF");
  assert.equal(glb.readUInt32LE(4), 2);
  const jsonLength = glb.readUInt32LE(12);
  assert.equal(glb.toString("utf8", 16, 20), "JSON");
  return JSON.parse(glb.toString("utf8", 20, 20 + jsonLength).trim()) as Record<string, unknown>;
}

test("the reward box uses the compact animated Draco GLB", () => {
  const json = readGlbJson();
  assert.ok(statSync(modelUrl).size < 600_000, "The web model must stay below 600 KB");
  assert.ok(Array.isArray(json.animations) && json.animations.length > 0, "The GLB must contain animation clips");
  assert.ok(Array.isArray(json.extensionsUsed) && json.extensionsUsed.includes("KHR_draco_mesh_compression"));
  for (const decoder of ["draco_decoder.js", "draco_decoder.wasm", "draco_wasm_wrapper.js"]) {
    assert.ok(statSync(new URL(`../public/draco/${decoder}`, import.meta.url)).size > 0);
  }
});

test("the Three.js demo is visual-only, replay-safe and explicitly closable", () => {
  assert.match(componentSource, /new THREE\.WebGLRenderer/);
  assert.match(componentSource, /new GLTFLoader/);
  assert.match(componentSource, /new DRACOLoader/);
  assert.match(componentSource, /action\.setLoop\(THREE\.LoopOnce, 1\)/);
  assert.match(componentSource, /aria-label="Cerrar animación"/);
  assert.doesNotMatch(componentSource, /supabase|open_pachanga_reward|claim|reclamar/i);
});

test("only admin-capable surfaces expose the visual test", () => {
  assert.equal(pageSource.match(/<span>Animación de logro<\/span>/g)?.length, 3);
  assert.match(pageSource, /dynamic\(\s*\(\) => import\("\.\/reward-box-demo"\)/);
  assert.match(pageSource, /rewardBoxDemoOpen && canUseAdminControls/);
  assert.match(pageSource, /disabled={!canUseAdminControls}/);
});

test("the full-screen stage has desktop, portrait and landscape layouts", () => {
  assert.match(stylesSource, /height: var\(--app-viewport-height, 100dvh\)/);
  assert.match(stylesSource, /@media \(min-width: 900px\) and \(min-height: 650px\)/);
  assert.match(stylesSource, /@media \(orientation: landscape\) and \(max-height: 650px\)/);
  assert.match(stylesSource, /@media \(orientation: portrait\) and \(max-width: 760px\)/);
  assert.match(stylesSource, /env\(safe-area-inset-top\)/);
  assert.match(stylesSource, /env\(safe-area-inset-right\)/);
});


test("the refined reveal exports all moving pieces in one three-second clip", () => {
  const json = readGlbJson() as {
    animations: { samplers: { input: number }[]; channels: { target: { node: number } }[] }[];
    nodes: { name: string }[];
    accessors: { max: number[] }[];
  };
  assert.equal(json.animations.length, 1, "The viewer plays one clip: all actions must be merged");
  const clip = json.animations[0];
  const names = new Set(clip.channels.map((channel) => json.nodes[channel.target.node].name));
  for (const name of ["Box_Lid", "Front_Latch", "Reward_Card", "Particle_Blue_01", "Particle_Blue_12"]) {
    assert.ok(names.has(name), `${name} must animate with the reveal`);
  }
  assert.equal(Math.max(...clip.samplers.map((sampler) => json.accessors[sampler.input].max[0])), 3);
});

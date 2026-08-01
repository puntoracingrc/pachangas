import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { adaptiveHeightClass, adaptiveWidthClass, adaptiveWindowClass } from "../app/adaptive-window";

const viewportMatrix = [
  { height: 780, label: "small phone portrait", width: 360, widthClass: "compact", heightClass: "medium" },
  { height: 375, label: "small phone landscape", width: 667, widthClass: "medium", heightClass: "compact" },
  { height: 390, label: "large phone game landscape", width: 844, widthClass: "expanded", heightClass: "compact" },
  { height: 720, label: "foldable portrait-like window", width: 717, widthClass: "medium", heightClass: "medium" },
  { height: 600, label: "tablet split or small landscape tablet", width: 1024, widthClass: "expanded", heightClass: "medium" },
  { height: 800, label: "large tablet landscape", width: 1280, widthClass: "large", heightClass: "medium" },
  { height: 950, label: "desktop or ChromeOS wide window", width: 1700, widthClass: "extra-large", heightClass: "expanded" },
] as const;

test("classifies windows with Android adaptive breakpoints", () => {
  assert.equal(adaptiveWidthClass(599), "compact");
  assert.equal(adaptiveWidthClass(600), "medium");
  assert.equal(adaptiveWidthClass(839), "medium");
  assert.equal(adaptiveWidthClass(840), "expanded");
  assert.equal(adaptiveWidthClass(1199), "expanded");
  assert.equal(adaptiveWidthClass(1200), "large");
  assert.equal(adaptiveWidthClass(1599), "large");
  assert.equal(adaptiveWidthClass(1600), "extra-large");

  assert.equal(adaptiveHeightClass(479), "compact");
  assert.equal(adaptiveHeightClass(480), "medium");
  assert.equal(adaptiveHeightClass(899), "medium");
  assert.equal(adaptiveHeightClass(900), "expanded");

  for (const viewport of viewportMatrix) {
    assert.deepEqual(
      adaptiveWindowClass(viewport.width, viewport.height),
      { width: viewport.widthClass, height: viewport.heightClass },
      viewport.label,
    );
  }
});

test("wires adaptive window classes into runtime and CSS", async () => {
  const [runtime, globalsCss, renderedHtmlTest] = await Promise.all([
    readFile(new URL("../app/pwa-runtime.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("./rendered-html.test.mjs", import.meta.url), "utf8"),
  ]);

  assert.match(runtime, /adaptiveWindowClass\(width, height\)/);
  assert.match(runtime, /dataset\.windowWidthClass = sizeClass\.width/);
  assert.match(runtime, /dataset\.windowHeightClass = sizeClass\.height/);
  assert.match(runtime, /dataset\.windowSizeClass = `\$\{sizeClass\.width\}-\$\{sizeClass\.height\}`/);
  assert.match(globalsCss, /html\[data-window-width-class="medium"\]/);
  assert.match(globalsCss, /html\[data-window-width-class="large"\]/);
  assert.match(globalsCss, /html\[data-window-height-class="compact"\]/);
  assert.match(renderedHtmlTest, /data-window-width-class/);
});

test("keeps an Android adaptive QA matrix in the repository", async () => {
  const guide = await readFile(new URL("../docs/android-adaptive-compatibility.md", import.meta.url), "utf8");

  for (const viewport of viewportMatrix) {
    assert.match(guide, new RegExp(`${viewport.width}x${viewport.height}`));
  }

  assert.match(guide, /Android 16/);
  assert.match(guide, /edge-to-edge/);
  assert.match(guide, /Window size classes/);
  assert.match(guide, /Pachangas IQ/);
});

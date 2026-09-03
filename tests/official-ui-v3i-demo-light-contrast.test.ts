import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

type Rgb = readonly [number, number, number];

function block(sourceText: string, marker: string, from = 0) {
  const markerIndex = sourceText.indexOf(marker, from);
  assert.notEqual(markerIndex, -1, `Missing CSS marker: ${marker}`);
  const openIndex = sourceText.indexOf("{", markerIndex);
  assert.notEqual(openIndex, -1, `Missing opening brace after: ${marker}`);
  let depth = 0;
  for (let index = openIndex; index < sourceText.length; index += 1) {
    if (sourceText[index] === "{") depth += 1;
    if (sourceText[index] === "}") depth -= 1;
    if (depth === 0) return sourceText.slice(openIndex + 1, index);
  }
  assert.fail(`Unclosed CSS block: ${marker}`);
}

function property(scope: string, name: string) {
  const match = scope.match(new RegExp(`${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*:\\s*([^;]+);`));
  assert.ok(match, `Missing CSS property: ${name}`);
  return match[1].trim().toLowerCase();
}

function rgb(hex: string): Rgb {
  const normalized = hex.replace(/^#/, "");
  assert.match(normalized, /^[0-9a-f]{6}$/i);
  return [0, 2, 4].map((offset) => Number.parseInt(normalized.slice(offset, offset + 2), 16)) as unknown as Rgb;
}

function composite(foreground: Rgb, alpha: number, background: Rgb): Rgb {
  return foreground.map((channel, index) => Math.round(channel * alpha + background[index] * (1 - alpha))) as unknown as Rgb;
}

function luminance(color: Rgb) {
  const [red, green, blue] = color.map((channel) => {
    const value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

function contrast(foreground: Rgb, background: Rgb) {
  const foregroundLuminance = luminance(foreground);
  const backgroundLuminance = luminance(background);
  return (Math.max(foregroundLuminance, backgroundLuminance) + 0.05)
    / (Math.min(foregroundLuminance, backgroundLuminance) + 0.05);
}

test("OFFICIAL-UI-V3I-003 freezes dark paint tokens and maps dark foreground aliases", async () => {
  const styles = await source("app/demo-world/demo-world.module.css");
  const dark = block(styles, ".shell {");

  assert.equal(property(dark, "--demo-lime"), "#c8ef5d");
  assert.equal(property(dark, "--demo-cyan"), "#51cfdf");
  assert.equal(property(dark, "--demo-lime-text"), "var(--demo-lime)");
  assert.equal(property(dark, "--demo-cyan-text"), "var(--demo-cyan)");
  assert.equal(property(dark, "--official-accent"), "var(--demo-lime)");
  assert.equal(property(dark, "--official-cyan"), "var(--demo-cyan)");
});

test("OFFICIAL-UI-V3I-003 gives explicit and automatic light the same foreground tokens", async () => {
  const styles = await source("app/demo-world/demo-world.module.css");
  const automaticMedia = block(styles, "@media (prefers-color-scheme: light)");
  const automatic = block(automaticMedia, ':global(:root:not([data-theme="dark"])) .shell');
  const explicit = block(styles, ':global(:root[data-theme="light"]) .shell');

  for (const name of ["--demo-lime-text", "--demo-cyan-text", "--demo-cyan-on-dark-text"]) {
    assert.equal(property(automatic, name), property(explicit, name));
  }
  assert.equal(property(explicit, "--demo-lime-text"), "#4d6800");
  assert.equal(property(explicit, "--demo-cyan-text"), "#006a73");
  assert.equal(property(explicit, "--demo-cyan-on-dark-text"), "#55d2e1");
  assert.match(styles, /:root:not\(\[data-theme="dark"\]\)/);
});

test("OFFICIAL-UI-V3I-003 foregrounds meet AA against every measured light surface", () => {
  const canvas = rgb("#eef2ef");
  const backgrounds: Array<[string, Rgb]> = [
    ["canvas", canvas],
    ["white", rgb("#ffffff")],
    ["identity", rgb("#e4ece7")],
    ["panel", composite(rgb("#ffffff"), 0.94, canvas)],
    ["panel soft", composite(rgb("#f8fbf9"), 0.94, canvas)],
    ["header", composite(rgb("#f3f7f4"), 0.96, canvas)],
    ["challenge wash", composite(rgb("#c8ef5d"), 0.06, canvas)],
    ["selected lime on canvas", composite(rgb("#c8ef5d"), 0.11, canvas)],
    ["selected lime on white", composite(rgb("#c8ef5d"), 0.11, rgb("#ffffff"))],
  ];

  for (const [foregroundName, foreground] of [["lime", rgb("#4d6800")], ["cyan", rgb("#006a73")]] as const) {
    for (const [backgroundName, background] of backgrounds) {
      assert.ok(contrast(foreground, background) >= 4.5, `${foregroundName} fails AA on ${backgroundName}`);
    }
  }
  assert.ok(contrast(rgb("#55d2e1"), rgb("#47504d")) >= 4.5);
});

test("OFFICIAL-UI-V3I-003 preserves paint contrast for dark brand and lime buttons", () => {
  assert.ok(contrast(rgb("#c8ef5d"), rgb("#17210d")) >= 4.5);
  assert.ok(contrast(rgb("#c8ef5d"), rgb("#07110f")) >= 3);
  assert.ok(contrast(rgb("#51cfdf"), rgb("#07110f")) >= 3);
});

test("OFFICIAL-UI-V3I-003 routes official and direct Demo text through foreground aliases", async () => {
  const styles = await source("app/demo-world/demo-world.module.css");
  const shell = block(styles, ".shell {");
  const headerContext = block(styles, ".headerContext {");

  assert.equal(property(shell, "--official-accent-text"), "var(--demo-lime-text)");
  assert.equal(property(shell, "--official-cyan-text"), "var(--demo-cyan-text)");
  assert.equal(property(headerContext, "--official-accent-text"), "var(--demo-lime-text)");
  assert.equal(property(headerContext, "--official-cyan-text"), "var(--demo-cyan-text)");
  for (const marker of [
    ".demoBanner b", ".brand > span", ".eyebrow", ".resultTile > strong b",
    ".demoMarketTabs button[aria-current=\"page\"]", ".demoSocialProof summary",
    '[data-demo-social-inbox="local-only"]', ".demoMarketV3d button[aria-pressed=\"true\"]",
  ]) assert.match(styles, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
});

test("OFFICIAL-UI-V3I-003 remains scoped to Demo and does not alter the shared selector", async () => {
  const [demoStyles, globalStyles, selectorStyles] = await Promise.all([
    source("app/demo-world/demo-world.module.css"),
    source("app/globals.css"),
    source("app/_components/product-context-selector.module.css"),
  ]);

  assert.match(demoStyles, /--demo-lime-text/);
  assert.doesNotMatch(globalStyles, /--demo-(?:lime|cyan)-(?:on-dark-)?text/);
  assert.doesNotMatch(selectorStyles, /--demo-(?:lime|cyan)-(?:on-dark-)?text/);
  assert.match(selectorStyles, /var\(--official-accent-text, #c8ef5d\)/);
  assert.match(selectorStyles, /var\(--official-cyan-text, #51cfdf\)/);
});

test("OFFICIAL-UI-V3I-003 leaves Demo authority, manifest and Service Worker contracts intact", async () => {
  const [demo, manifest, worker] = await Promise.all([
    source("app/demo-world/demo-world-app.tsx"),
    source("app/manifest.ts"),
    source("app/sw.js/route.ts"),
  ]);

  for (const counter of ["remoteWrites = 0", "externalNotifications = 0", "realEntities = 0", "StripeCalls = 0"]) {
    assert.match(demo, new RegExp(counter.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }
  assert.match(demo, /data-demo-world="ready"/);
  assert.match(demo, /sessionStorage/);
  assert.doesNotMatch(manifest, /demo-lime-text|demo-cyan-text/);
  assert.doesNotMatch(worker, /demo-lime-text|demo-cyan-text/);
});

test("Official UI V3I suites and frozen Social regressions remain registered once", async () => {
  const packageJson = await source("package.json");
  for (const suite of [
    "tests/official-ui-v3h-social-core.test.ts",
    "tests/social-core-rc-hotfix-001.test.ts",
    "tests/social-core-rc-hotfix-002.test.ts",
    "tests/official-ui-v3i-compact-accessibility.test.ts",
    "tests/official-ui-v3i-demo-light-contrast.test.ts",
  ]) {
    const escaped = suite.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    assert.equal((packageJson.match(new RegExp(escaped, "g")) ?? []).length, 1, `${suite} must be registered once`);
  }
});

test("Official UI V3I Batch 001 remains historically frozen while Batch 002 is active", async () => {
  const [market, shell, functionalReport, productionReport] = await Promise.all([
    source("app/mercado/marketplace-client.tsx"),
    source("app/_components/official-product-shell-v2.tsx"),
    source("OFFICIAL_UI_V3I_BATCH_001_COMPACT_ACCESSIBILITY_REPORT.md"),
    source("OFFICIAL_UI_V3I_BATCH_001_PRODUCTION_RELEASE.md"),
  ]);

  assert.match(market, /<select aria-label="Ordenar por"/);
  assert.match(shell, /<header className=\{styles\.contextBar\}>/);
  assert.match(productionReport, /OFFICIAL-UI-V3I-003`: `NOT STARTED/);
  assert.match(productionReport, /Contraste del tema claro Demo: no modificado/);
  assert.match(functionalReport, /CSS modificado: `NO`/);
  assert.match(productionReport, /cierra exclusivamente `OFFICIAL-UI-V3I-001` y `OFFICIAL-UI-V3I-002`/);
});

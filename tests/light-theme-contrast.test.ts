import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("the official shell exposes complete light-theme surface and foreground tokens", async () => {
  const styles = await source("app/_components/official-product-shell-v2.module.css");

  assert.match(styles, /:global\(:root\[data-theme="light"\]\) \.shell/);
  for (const token of [
    "--official-canvas: #eef2ef",
    "--official-surface-solid: #ffffff",
    "--official-text: #10201a",
    "--official-muted: #53675e",
    "--official-accent-text: #476b00",
    "--official-cyan-text: #086875",
  ]) assert.match(styles, new RegExp(token));
  assert.match(styles, /:global\(:root\[data-theme="light"\]\) \.gameMark/);
});

test("explicit light preference wins over a dark operating-system preference on mobile", async () => {
  const styles = await source("app/globals.css");

  assert.doesNotMatch(styles, /@media \(prefers-color-scheme: dark\) and \(max-width: 760px\)/);
  assert.match(styles, /:root\[data-theme="dark"\] \.mobile-app-nav/);
  assert.match(styles, /:root\[data-theme="light"\] \.legal-warning/);
  assert.match(styles, /main\[data-mobile-tab\] :is\(input, select, textarea\)[\s\S]*background: var\(--panel\) !important/);
});

test("shared headers and product states use theme-aware foregrounds", async () => {
  const [headers, states, market] = await Promise.all([
    source("app/_components/official-ui-v2-primitives.module.css"),
    source("app/_components/product-state.module.css"),
    source("app/_components/official-market-game-view.module.css"),
  ]);

  assert.match(headers, /\.pageHeader h1 \{[^}]*var\(--official-text/);
  assert.match(states, /:global\(:root\[data-theme="light"\]\) \.state\[data-surface="dark"\]/);
  assert.match(market, /:global\(:root\[data-theme="light"\]\) \.titlebar h1/);
});

test("every migrated product surface defines an explicit light-theme contract", async () => {
  const files = [
    "app/avisos/social-inbox.module.css",
    "app/competiciones/public-competitions.module.css",
    "app/conduct.module.css",
    "app/equipo/identidad/page.module.css",
    "app/equipo/social-team.module.css",
    "app/perfil/profile.module.css",
    "app/personalizar-carta/page.module.css",
    "app/ranking/ranking.module.css",
    "app/retos/retos.module.css",
    "app/venue-operations.module.css",
  ];

  for (const file of files) {
    const styles = await source(file);
    assert.match(styles, /:global\(:root\[data-theme="light"\]\)/, `${file} has no explicit light-theme rules`);
  }
});

test("dark-only administration keeps its access heading readable", async () => {
  const styles = await source("app/admin/platform-admin.module.css");
  assert.match(styles, /\.accessPanel h1 \{[^}]*color: #eef5f1 !important/);
});

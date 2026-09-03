import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("OFFICIAL-UI-V3I-001 keeps a persistent accessible name on the Market sort", async () => {
  const market = await source("app/mercado/marketplace-client.tsx");
  const sortStart = market.indexOf('<label className={styles.sortLabel}>');
  const sortEnd = market.indexOf("</label>", sortStart);
  const sort = market.slice(sortStart, sortEnd);

  assert.notEqual(sortStart, -1);
  assert.match(sort, /<span>Ordenar por<\/span>/);
  assert.match(sort, /<select aria-label="Ordenar por" value=\{filters\.sort\}/);
  assert.match(sort, /onChange=\{\(event\) => applyQuickFilter\(\{ sort: event\.target\.value as MarketSort \}\)\}/);
  assert.equal((sort.match(/aria-label="Ordenar por"/g) ?? []).length, 1);
});

test("OFFICIAL-UI-V3I-001 preserves the existing Market sort options and state mechanism", async () => {
  const market = await source("app/mercado/marketplace-client.tsx");

  for (const option of [
    '<option value="relevance">Relevancia</option>',
    '<option value="date">Más próximo</option>',
    '<option value="slots">Más plazas</option>',
    '<option value="level">Nivel</option>',
    '<option value="distance">Más cerca</option>',
  ]) assert.match(market, new RegExp(option.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.match(market, /value=\{filters\.sort\}/);
  assert.match(market, /activeTab === "partidos"/);
  assert.doesNotMatch(market, /window\.matchMedia[\s\S]{0,240}aria-label="Ordenar por"/);
});

test("OFFICIAL-UI-V3I-001 does not depend exclusively on the hideable visual label", async () => {
  const [market, styles] = await Promise.all([
    source("app/mercado/marketplace-client.tsx"),
    source("app/mercado/marketplace-v3d.module.css"),
  ]);

  assert.match(styles, /\.headerActions \.sortLabel span \{ display: none; \}/);
  assert.match(market, /<span>Ordenar por<\/span>[\s\S]*?<select aria-label="Ordenar por"/);
});

test("OFFICIAL-UI-V3I-002 gives desktop and compact account actions one banner each", async () => {
  const shell = await source("app/_components/official-product-shell-v2.tsx");
  const desktopStart = shell.indexOf('<header className={styles.desktopHeader}>');
  const desktopEnd = shell.indexOf("</header>", desktopStart);
  const compactStart = shell.indexOf('<header className={styles.contextBar}>');
  const compactEnd = shell.indexOf("</header>", compactStart);

  assert.notEqual(desktopStart, -1);
  assert.notEqual(compactStart, -1);
  assert.match(shell.slice(desktopStart, desktopEnd), /accountActions/);
  assert.match(shell.slice(compactStart, compactEnd), /accountActions/);
  assert.doesNotMatch(shell, /<div className=\{styles\.contextBar\}>/);
  assert.equal((shell.match(/<AccountActions /g) ?? []).length, 1);
  assert.equal((shell.match(/const accountActions = <AccountActions /g) ?? []).length, 1);
});

test("OFFICIAL-UI-V3I-002 preserves account links, badges and permission boundaries", async () => {
  const shell = await source("app/_components/official-product-shell-v2.tsx");
  const accountStart = shell.indexOf("function AccountActions");
  const accountEnd = shell.indexOf("export function OfficialProductShellV2", accountStart);
  const account = shell.slice(accountStart, accountEnd);

  assert.match(account, /notificationsHref = account\.notificationsHref \?\? "\/avisos"/);
  assert.match(account, /useSocialInbox\(\)/);
  assert.match(account, /pendingCount > 9 \? "9\+" : pendingCount/);
  assert.match(account, /aria-label=\{bellLabel\}/);
  assert.match(account, /aria-label="Abrir menú de cuenta"/);
  assert.match(account, /platformOwner \? <Link href="\/admin">Administración<\/Link> : null/);
  assert.match(account, /adminViewPreview \? \(/);
});

test("OFFICIAL-UI-V3I-002 preserves exactly four primary social destinations", async () => {
  const navigation = await source("app/_components/product-navigation-contract.ts");
  const destinations = navigation.slice(
    navigation.indexOf("export const PRODUCT_PRIMARY_DESTINATIONS"),
    navigation.indexOf("export const PRODUCT_PORTRAIT_DESTINATIONS"),
  );

  assert.equal((destinations.match(/\{ href:/g) ?? []).length, 4);
  for (const label of ["Inicio", "Partidos", "Retos", "Mercado"]) {
    assert.match(destinations, new RegExp(`label: "${label}"`));
  }
  assert.match(navigation, /PRODUCT_PORTRAIT_DESTINATIONS = PRODUCT_PRIMARY_DESTINATIONS/);
});

test("Official UI V3I Batch 001 keeps historical suites registered and frozen", async () => {
  const [packageJson, v3h, batch001, batch002] = await Promise.all([
    source("package.json"),
    source("tests/official-ui-v3h-social-core.test.ts"),
    source("tests/social-core-rc-hotfix-001.test.ts"),
    source("tests/social-core-rc-hotfix-002.test.ts"),
  ]);

  for (const suite of [
    "tests/official-ui-v3h-social-core.test.ts",
    "tests/social-core-rc-hotfix-001.test.ts",
    "tests/social-core-rc-hotfix-002.test.ts",
    "tests/official-ui-v3i-compact-accessibility.test.ts",
  ]) assert.equal((packageJson.match(new RegExp(suite.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g")) ?? []).length, 1);
  for (const id of ["SOCIAL-RC-001", "SOCIAL-RC-004", "SOCIAL-RC-006", "SOCIAL-RC-008", "SOCIAL-RC-010"]) assert.match(batch001, new RegExp(id));
  for (const id of ["SOCIAL-RC-002", "SOCIAL-RC-003", "SOCIAL-RC-005", "SOCIAL-RC-007", "SOCIAL-RC-009", "SOCIAL-RC-011", "SOCIAL-RC-012"]) assert.match(batch002, new RegExp(id));
  assert.match(v3h, /V3H keeps exactly four primary social destinations/);
});

test("OFFICIAL-UI-V3I-003 remains outside Batch 001", async () => {
  const [packageJson, demoStyles] = await Promise.all([
    source("package.json"),
    source("app/demo-world/demo-world.module.css"),
  ]);

  assert.doesNotMatch(packageJson, /official-ui-v3i-demo-light-contrast/);
  assert.doesNotMatch(demoStyles, /OFFICIAL-UI-V3I-003/);
});

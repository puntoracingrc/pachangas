import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { registerHooks } from "node:module";
import test from "node:test";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

registerHooks({
  load(url, context, nextLoad) {
    if (url.endsWith(".module.css")) {
      return {
        format: "module",
        shortCircuit: true,
        source: "export default new Proxy({}, { get: (_target, key) => String(key) });",
      };
    }
    return nextLoad(url, context);
  },
  resolve(specifier, context, nextResolve) {
    if (specifier.endsWith(".module.css")) {
      return { shortCircuit: true, url: new URL(specifier, context.parentURL).href };
    }
    return nextResolve(specifier, context);
  },
});

test("SOCIAL-RC-002 activates the declared first-time perspective before opening the journey", async () => {
  const [app, review] = await Promise.all([
    source("app/demo-world/demo-world-app.tsx"),
    source("app/demo-world/demo-social-quick-review.tsx"),
  ]);

  assert.match(review, /firstTime: true,[\s\S]*perspectiveId: "free-agent",[\s\S]*tab: "inicio"/);
  assert.match(review, /onOpenFirstTime: \(perspectiveId: DemoWorldPerspective\["id"\]\) => void/);
  assert.match(review, /if \(journey\.firstTime\) onOpenFirstTime\(journey\.perspectiveId\)/);
  assert.match(app, /openSocialReviewJourney\("inicio", perspectiveId, true\)/);
  assert.match(app, /choosePerspective\(perspectiveId, false\)/);
  assert.match(app, /params\.set\("journey", "first-time"\)/);
  assert.match(app, /setSocialFirstTimeOpen\(firstTime\)/);
  assert.doesNotMatch(review.slice(review.indexOf("function openJourney"), review.indexOf("return (")), /onReset|resetWorld|removeItem/);
});

test("SOCIAL-RC-002 keeps URL, Back/Forward and dialog state coherent", async () => {
  const app = await source("app/demo-world/demo-world-app.tsx");
  assert.match(app, /const firstTimeRequested = !fullMode && params\.get\("journey"\) === "first-time"/);
  assert.match(app, /const quickReviewRequested = !fullMode && params\.get\("review"\) === "1"/);
  assert.match(app, /setSocialFirstTimeOpen\(firstTimeRequested\)/);
  assert.match(app, /setSocialQuickReviewOpen\(!firstTimeRequested && quickReviewRequested\)/);
  assert.match(app, /function closeSocialFirstTimeJourney\(\)[\s\S]*params\.delete\("journey"\)[\s\S]*writeDemoRoute\(params, "route", "replace"\)/);
  assert.match(app, /window\.addEventListener\("popstate", restoreDemoRoute\)/);
});

test("SOCIAL-RC-002 keeps every quick-review journey bound to its declared perspective", async () => {
  const review = await source("app/demo-world/demo-social-quick-review.tsx");
  for (const [journeyId, perspectiveId] of [
    ["new-user", "free-agent"],
    ["team-player", "player"],
    ["team-owner", "team-owner"],
    ["create-match", "team-owner"],
    ["challenge-team", "team-owner"],
    ["find-player", "admin"],
    ["resolve-inbox", "admin"],
  ]) assert.match(review, new RegExp(`id: "${journeyId}",[\\s\\S]*?perspectiveId: "${perspectiveId}"`));
  assert.match(review, /if \(journey\.firstTime\) onOpenFirstTime\(journey\.perspectiveId\)/);
  assert.match(review, /else onStart\(journey\.tab, journey\.perspectiveId\)/);
});

test("SOCIAL-RC-007 gives challenge mutations one primary hierarchy and an immediate lock", async () => {
  const [app, styles] = await Promise.all([
    source("app/demo-world/demo-world-app.tsx"),
    source("app/demo-world/demo-world.module.css"),
  ]);

  assert.match(app, /const challengeActionLock = useRef\(false\)/);
  assert.match(app, /if \(challengeActionLock\.current\) return/);
  assert.match(app, /runChallengeMutation\(`accept:\$\{selectedChallenge\.id\}`/);
  assert.match(app, /<details className=\{styles\.demoChallengeMoreActions\}>/);
  assert.match(app, /summary aria-label="Más acciones para el reto"/);
  assert.match(app, /data-destructive="true"[\s\S]*Rechazar/);
  assert.match(app, /className=\{styles\.demoPerspectiveReview\}[\s\S]*Vista de revisión/);
  assert.match(styles, /\.demoChallengeMoreActions > summary \{[\s\S]*min-height: 44px/);
  assert.match(styles, /button\[data-destructive="true"\] \{ color: #ffaaa7; \}/);
});

test("SOCIAL-RC-009 opens the exact projected upcoming match and retains the existing fallback", async () => {
  const app = await source("app/demo-world/demo-world-app.tsx");
  assert.match(app, /const upcoming = teamMatches\.filter[\s\S]*sort\(\(left, right\) => Date\.parse\(left\.date\) - Date\.parse\(right\.date\)\)/);
  assert.match(app, /upcoming\[0\] \? onMatch\(upcoming\[0\]\.id\) : onTab\("partido"\)/);
  assert.match(app, /params\.set\("match", matchId\)/);
  assert.match(app, /params\.set\("matchView", "detail"\)/);
  assert.match(app, /writeDemoRoute\(params, "route", "push"\)/);
});

test("SOCIAL-RC-012 exposes one keyboard-scrollable guarantees region inside the focus trap", async () => {
  const [review, styles] = await Promise.all([
    source("app/demo-world/demo-social-quick-review.tsx"),
    source("app/demo-world/demo-social-quick-review.module.css"),
  ]);

  assert.match(review, /role="region"[\s\S]*aria-label="Garantías de la simulación"[\s\S]*tabIndex=\{0\}/);
  assert.match(review, /event\.key === "ArrowLeft" \|\| event\.key === "ArrowRight"/);
  assert.match(review, /event\.key === "Home" \|\| event\.key === "End"/);
  assert.match(review, /\[tabindex\]:not\(\[tabindex="-1"\]\)/);
  assert.match(styles, /\.proof:focus-visible \{ outline: 2px solid #51cfdf/);
  assert.match(styles, /scrollbar-width: thin/);
  assert.doesNotMatch(styles, /\.proof::\-webkit-scrollbar \{ display: none; \}/);
  for (const guarantee of [
    "LOCAL SESSION ONLY",
    "remoteWrites = 0",
    "externalNotifications = 0",
    "pushSent = 0",
    "emailsSent = 0",
    "realEntities = 0",
    "StripeCalls = 0",
  ]) assert.match(review, new RegExp(guarantee.replace(/[=]/g, "\\=")));
});

test("SOCIAL-RC-003 preserves useful search width and a named 44px location target", async () => {
  const [demo, styles] = await Promise.all([
    source("app/demo-world/demo-world-app.tsx"),
    source("app/mercado/marketplace-v3d.module.css"),
  ]);

  assert.match(demo, /className=\{marketStyles\.locationAction\}[^>]*aria-label="Usar ubicación demo"/);
  assert.match(demo, /<svg aria-hidden="true"[\s\S]*<span>Usar ubicación demo<\/span>/);
  assert.match(styles, /\.locationRow \{ grid-template-columns: minmax\(0, 1fr\) 44px 44px; \}/);
  assert.match(styles, /\.locationAction \{ min-width: 44px; padding: 0; \}/);
  assert.match(styles, /\.locationAction span \{ display: none; \}/);
  assert.match(styles, /\.locationAction:focus-visible \{ outline: 2px solid/);
  assert.doesNotMatch(styles, /\.locationRow \{ grid-template-columns: 44px minmax\(0, 1fr\)/);
});

test("SOCIAL-RC-005 renders product language instead of internal version labels", async () => {
  const { DemoSocialFirstTimeJourney } = await import("../app/demo-world/demo-social-first-time-journey");
  const renderedJourney = renderToStaticMarkup(createElement(DemoSocialFirstTimeJourney, {
    onClose: () => undefined,
    onNavigate: () => undefined,
  }));
  const [app, firstTime, inbox, contract] = await Promise.all([
    source("app/demo-world/demo-world-app.tsx"),
    source("app/demo-world/demo-social-first-time-journey.tsx"),
    source("app/demo-world/demo-social-inbox.tsx"),
    source("app/demo-world/demo-social-first-time-contract.ts"),
  ]);
  const visibleCopy = [
    app.slice(app.indexOf("const demoSteps"), app.indexOf("return (", app.indexOf("const demoSteps"))),
    firstTime,
    inbox,
    contract,
  ].join("\n");

  for (const internalLabel of [
    "Abrir Partido V3B",
    "Abrir V3C",
    "Mercado V3D",
    "Partidos V3B",
    "Retos V3C",
    "First-time social journey",
    "desactivados en V3G",
    "Invitación de jugador V2",
  ]) assert.doesNotMatch(visibleCopy, new RegExp(internalLabel));
  assert.match(renderedJourney, /Mundo Demo · Primeros pasos/);
  assert.match(renderedJourney, /Abre Partidos/);
  assert.match(renderedJourney, /Verifica Retos/);
  assert.match(renderedJourney, /Verifica Mercado/);
  assert.doesNotMatch(renderedJourney, /\b(?:V3|V3H|V3\.5|Official UI|read model)\b/i);
  assert.match(firstTime, /Mundo Demo · Primeros pasos/);
  assert.match(inbox, /Push y correo siguen desactivados por ahora/);
});

test("SOCIAL-RC-011 keeps every existing context field visible or available in its accessible label", async () => {
  const [selector, styles] = await Promise.all([
    source("app/_components/product-context-selector.tsx"),
    source("app/_components/product-context-selector.module.css"),
  ]);

  assert.match(selector, /context\.title,[\s\S]*productContextTypeLabels\[context\.type\],[\s\S]*context\.role,[\s\S]*context\.detail,[\s\S]*context\.status,[\s\S]*context\.nextAction/);
  assert.match(selector, /const seen = new Set<string>\(\)[\s\S]*seen\.has\(key\)[\s\S]*seen\.add\(key\)/);
  assert.match(selector, /<option key=\{context\.id\} value=\{context\.id\}>\{productContextOptionLabel\(context\)\}<\/option>/);
  assert.match(selector, /aria-label=\{`Contexto activo: \$\{activeLabel\}`\}/);
  assert.match(styles, /\.copy \{[\s\S]*flex-wrap: wrap/);
  assert.match(styles, /\.copy em \{[\s\S]*flex-basis: 100%[\s\S]*white-space: normal/);
  assert.match(styles, /@media \(min-width: 761px\) and \(max-width: 1100px\)[\s\S]*\.selector \{ grid-template-columns: minmax\(0, 1fr\); \}/);
  assert.match(styles, /@media \(orientation: landscape\) and \(max-height: 600px\)[\s\S]*\.copy em, \.meta small \{ display: none; \}/);
});

test("Batch 001 regressions remain part of the complete suite", async () => {
  const [packageJson, batch001] = await Promise.all([
    source("package.json"),
    source("tests/social-core-rc-hotfix-001.test.ts"),
  ]);
  assert.match(packageJson, /tests\/social-core-rc-hotfix-001\.test\.ts/);
  for (const id of ["SOCIAL-RC-001", "SOCIAL-RC-004", "SOCIAL-RC-006", "SOCIAL-RC-008", "SOCIAL-RC-010"]) {
    assert.match(batch001, new RegExp(id));
  }
});

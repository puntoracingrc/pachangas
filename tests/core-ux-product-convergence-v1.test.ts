import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  PRODUCT_PORTRAIT_DESTINATIONS,
  PRODUCT_PRIMARY_DESTINATIONS,
  contextualDestinationsForPerspective,
  productNavigationForViewport,
} from "../app/_components/product-navigation-contract";
import {
  DEMO_WORLD_V33_AUTHORITY_HASH,
  DEMO_WORLD_V33_TOURS,
  demoWorldV33StepHref,
} from "../app/demo-world/demo-world-v3-3-contract";
import { buildServiceWorkerSource } from "../app/service-worker-source";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("the social core exposes the same four primary destinations in every viewport", () => {
  assert.deepEqual(PRODUCT_PRIMARY_DESTINATIONS.map(({ id }) => id), [
    "inicio",
    "partido",
    "retos",
    "mercado",
  ]);
  assert.deepEqual(PRODUCT_PORTRAIT_DESTINATIONS, PRODUCT_PRIMARY_DESTINATIONS);
  assert.equal(productNavigationForViewport("portrait").length, 4);
  assert.equal(productNavigationForViewport("desktop").length, 4);
  assert.equal(productNavigationForViewport("landscape").length, 4);
});

test("role-aware utilities prioritize capability context without granting authority", () => {
  const player = contextualDestinationsForPerspective("player");
  const owner = contextualDestinationsForPerspective("team-owner");
  const referee = contextualDestinationsForPerspective("referee");
  const reviewer = contextualDestinationsForPerspective("platform-reviewer");
  assert.deepEqual(player.map(({ id }) => id), ["team", "reservations", "ranking", "notifications"]);
  assert.ok(owner.some(({ id }) => id === "organize"));
  assert.ok(referee.some(({ id }) => id === "assignments"));
  assert.deepEqual(referee.map(({ href }) => href), [
    "/perfil/arbitro",
    "/mis-asignaciones-arbitrales",
    "/perfil/avisos",
  ]);
  assert.deepEqual(reviewer.map(({ id }) => id), ["control-center", "notifications"]);
  assert.ok(player.every(({ id }) => id !== "control-center" && id !== "organize"));
});

test("the unified header keeps team context separate from primary navigation", async () => {
  const shell = await source("app/_components/official-product-shell-v2.tsx");
  assert.match(shell, /aria-label="Abrir selector de equipo"/);
  assert.match(shell, /contextOptions/);
  assert.match(shell, /onContextChange/);
  assert.match(shell, /Ver equipo/);
  assert.match(shell, /Gestionar equipo/);
  assert.match(shell, /PRODUCT_PRIMARY_DESTINATIONS/);
  assert.doesNotMatch(shell, /contextualDestinationsForPerspective\(perspective\)/);
});

test("all official competition operations identify Competir as their primary domain", async () => {
  const paths = [
    "app/_components/competition-configuration-client.tsx",
    "app/_components/competition-discipline-client.tsx",
    "app/_components/league-match-operations-client.tsx",
    "app/_components/league-operational-exceptions-client.tsx",
    "app/_components/league-participation-client.tsx",
    "app/_components/league-private-beta-client.tsx",
    "app/_components/league-scheduling-client.tsx",
    "app/_components/tournament-group-stage-client.tsx",
    "app/_components/tournament-private-beta-client.tsx",
    "app/competiciones/competition-directory-client.tsx",
    "app/competiciones/[competition]/public-competition-hub.tsx",
  ];
  const files = await Promise.all(paths.map(source));
  for (const file of files) assert.match(file, /active="competir"/);
  assert.ok(files.some((file) => /perspective="league-organizer"/.test(file)));
  assert.ok(files.some((file) => /perspective="tournament-organizer"/.test(file)));
  assert.ok(files.some((file) => /perspective="free-agent"/.test(file)));
});

test("the visual state family covers every canonical product state without fake success", async () => {
  const component = await source("app/_components/product-state.tsx");
  for (const state of [
    "LOADING",
    "EMPTY",
    "NO_ACCESS",
    "FEATURE_DISABLED",
    "NOT_READY",
    "STALE",
    "OFFLINE",
    "ERROR",
    "SUCCESS",
    "ACTION_REQUIRED",
    "UNDER_REVIEW",
    "SUSPENDED",
    "ARCHIVED",
  ]) assert.match(component, new RegExp(`\\| "${state}"|= "${state}"`));
  assert.match(component, /technicalCode/);
  assert.match(component, /aria-live="polite"/);
  assert.doesNotMatch(component, /setTimeout|window\.location|\.rpc\(/);
});

test("Demo World V3.3 has eight guided tours spanning every required perspective", () => {
  assert.equal(DEMO_WORLD_V33_TOURS.length, 8);
  assert.equal(new Set(DEMO_WORLD_V33_TOURS.map(({ id }) => id)).size, 8);
  assert.ok(DEMO_WORLD_V33_TOURS.every(({ steps }) => steps.length >= 2));
  assert.deepEqual(
    new Set(DEMO_WORLD_V33_TOURS.flatMap(({ steps }) => steps.map(({ perspective }) => perspective))),
    new Set([
      "player",
      "team-owner",
      "free-agent",
      "league-organizer",
      "tournament-organizer",
      "referee",
      "club-organizer",
      "platform-reviewer",
    ]),
  );
});

test("guided links restore role, tour, step, week, competition and season surface", () => {
  const tour = DEMO_WORLD_V33_TOURS.find(({ id }) => id === "league-organizer")!;
  const href = new URL(demoWorldV33StepHref(tour, 1), "https://pachangasiq.test");
  assert.equal(href.pathname, "/demo");
  assert.equal(href.searchParams.get("perspective"), "league-organizer");
  assert.equal(href.searchParams.get("tour"), "league-organizer");
  assert.equal(href.searchParams.get("step"), "1");
  assert.equal(href.searchParams.get("checkpoint"), "4");
  assert.equal(href.searchParams.get("week"), "8");
  assert.equal(href.searchParams.get("competition"), "liga-barrios-iq");
  assert.equal(href.searchParams.get("surface"), "standings");
  assert.equal(href.searchParams.get("view"), "standings");
});

test("V3.3 is presentation-only and preserves the V3.2 synthetic authority", async () => {
  const [manifest, proof, reviewSource] = await Promise.all([
    source("public/demo-world/v3-3/manifest.json").then((value) => JSON.parse(value) as {
      version: number;
      authority: { version: number; hash: string };
      guidedReview: { remoteWrites: number };
      privacy: { pii: boolean; authIds: boolean };
    }),
    source("simulation/synthetic-season/generated/synthetic-season-proof.json").then((value) => JSON.parse(value) as {
      authorityHash: string;
    }),
    source("app/demo-world/demo-world-v3-3-guided-review.tsx"),
  ]);
  assert.equal(manifest.version, 3.3);
  assert.equal(manifest.authority.version, 3.2);
  assert.equal(manifest.authority.hash, DEMO_WORLD_V33_AUTHORITY_HASH);
  assert.equal(proof.authorityHash, DEMO_WORLD_V33_AUTHORITY_HASH);
  assert.equal(manifest.guidedReview.remoteWrites, 0);
  assert.equal(manifest.privacy.pii, false);
  assert.equal(manifest.privacy.authIds, false);
  assert.match(reviewSource, /window\.localStorage/);
  assert.doesNotMatch(reviewSource, /fetch\(|supabase|\.rpc\(|clientWrite/i);
});

test("the season review loads one checkpoint plus adjacent snapshots and supports URL restoration", async () => {
  const view = await source("app/demo-world/demo-world-v3-2-view.tsx");
  assert.match(view, /adjacentSyntheticSeasonCheckpoints/);
  assert.match(view, /params\.get\("week"\)/);
  assert.match(view, /params\.get\("surface"\) \?\? params\.get\("view"\)/);
  assert.match(view, /\.get\("competition"\)/);
  assert.match(view, /addEventListener\("popstate"/);
  assert.doesNotMatch(view, /Promise\.all\(index\.checkpointFiles/);
});

test("the Service Worker precaches V3.3 while refusing commands and private services", () => {
  const worker = buildServiceWorkerSource("wave8d-test");
  assert.match(worker, /\/demo-world\/v3-3\/manifest\.json/);
  assert.match(worker, /if \(request\.method !== "GET"\) return/);
  assert.match(worker, /pathname\.startsWith\("\/api\/"\)/);
  assert.match(worker, /supabase\.co/);
  assert.match(worker, /stripe\.com/);
  assert.doesNotMatch(worker, /service_role|Authorization:/i);
});

test("frontend stabilization contains no rule suppression or TypeScript escape hatch", async () => {
  const files = await Promise.all([
    source("app/page.tsx"),
    source("app/mercado/marketplace-client.tsx"),
    source("app/legal-data.tsx"),
  ]);
  for (const file of files) {
    assert.doesNotMatch(file, /eslint-disable|@ts-ignore|@ts-nocheck/);
  }
});

test("Mercado hydrates deterministically and restores shareable tab state", async () => {
  const market = await source("app/mercado/marketplace-client.tsx");
  assert.match(market, /useState\(\(\) => marketRouteFromSearch\(""\)\)/);
  assert.match(market, /window\.queueMicrotask/);
  assert.match(market, /addEventListener\("popstate"/);
  assert.match(market, /history\.pushState/);
  assert.doesNotMatch(market, /typeof window === "undefined" \? "" : window\.location\.search/);
});

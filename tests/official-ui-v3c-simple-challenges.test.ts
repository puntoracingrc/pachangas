import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  challengePrimaryLabel,
  challengeRouteSearch,
  groupTeamChallenges,
  parseChallengeRoute,
  safeChallengeError,
} from "../app/team-challenges-ui-contract";
import type { TeamChallenge } from "../app/team-social-contract";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

function challenge(patch: Partial<TeamChallenge> = {}): TeamChallenge {
  return {
    acceptedAt: null,
    cancelledAt: null,
    createdAt: "2026-08-31T10:00:00.000Z",
    direction: "incoming",
    expiredAt: null,
    field: { address: "Carrer Demo 1", mapsUrl: null, name: "Camp Demo", placeId: null },
    id: "challenge-1",
    lastProposedBy: "opponent",
    message: "Partido amistoso",
    modality: "futbol7",
    opponent: { groupId: "group-2", name: "Raval FC", teamCode: "RAVAL1" },
    proposalNumber: 1,
    rejectedAt: null,
    revision: 4,
    scheduledAt: "2026-09-10T19:00:00.000Z",
    status: "proposed",
    updatedAt: "2026-08-31T10:00:00.000Z",
    ...patch,
  };
}

test("legacy challenge links normalize without losing rival or match context", () => {
  const received = parseChallengeRoute("?vista=received&rival=abc123");
  assert.equal(received.view, "active");
  assert.equal(received.filter, "received");
  assert.equal(received.creating, true);
  assert.equal(received.rivalCode, "ABC123");
  assert.equal(received.legacy, true);
  assert.equal(challengeRouteSearch({ ...received, legacy: false }), "view=active&filter=received&crear=1&rival=ABC123");
  const history = parseChallengeRoute("?vista=history&retoPartido=challenge-9");
  assert.equal(history.view, "history");
  assert.equal(history.matchChallengeId, "challenge-9");
  assert.match(challengeRouteSearch({ ...history, legacy: false }), /retoPartido=challenge-9/);
});

test("active challenges derive one canonical next-action group", () => {
  const needsResponse = challenge();
  const waiting = challenge({ direction: "outgoing", id: "challenge-2", lastProposedBy: "own" });
  const agreed = challenge({ id: "challenge-3", status: "accepted" });
  const rejected = challenge({ id: "challenge-4", status: "rejected" });
  const groups = groupTeamChallenges([needsResponse, waiting, agreed, rejected]);
  assert.deepEqual(groups.needsResponse.map(({ id }) => id), ["challenge-1"]);
  assert.deepEqual(groups.waiting.map(({ id }) => id), ["challenge-2"]);
  assert.deepEqual(groups.agreed.map(({ id }) => id), ["challenge-3"]);
  assert.deepEqual(groups.history.map(({ id }) => id), ["challenge-4"]);
  assert.equal(challengePrimaryLabel(needsResponse, true), "Aceptar");
  assert.equal(challengePrimaryLabel(waiting, true), "Ver propuesta");
  assert.equal(challengePrimaryLabel(agreed, false), "Ver partido");
});

test("received and sent stay compact filters rather than primary state machines", () => {
  const incoming = challenge();
  const outgoing = challenge({ direction: "outgoing", id: "challenge-2", lastProposedBy: "own" });
  assert.deepEqual(groupTeamChallenges([incoming, outgoing], "received").needsResponse.map(({ id }) => id), ["challenge-1"]);
  assert.deepEqual(groupTeamChallenges([incoming, outgoing], "sent").waiting.map(({ id }) => id), ["challenge-2"]);
});

test("technical server errors become safe product messages", () => {
  const stale = safeChallengeError({ code: "PT409", message: "revision mismatch" });
  assert.equal(stale.stale, true);
  assert.match(stale.body, /última propuesta/);
  assert.doesNotMatch(stale.body, /PT409|revision|PostgREST|UUID/i);
  assert.equal(safeChallengeError({ message: "permission denied" }).title, "No tienes permiso");
  assert.equal(safeChallengeError({ message: "network fetch failed" }).title, "Sin conexión");
  assert.equal(safeChallengeError({ message: "same team" }).title, "Ese rival no es válido");
});

test("Retos exposes only Activos and Historial with shell-owned team context", async () => {
  const [page, panel] = await Promise.all([source("app/retos/page.tsx"), source("app/mercado/team-challenges-panel.tsx")]);
  assert.match(page, />Activos</);
  assert.match(page, />Historial</);
  assert.match(page, /contextOptions=\{contextOptions\.length \? contextOptions : undefined\}/);
  assert.match(page, /onContextChange=\{\(groupId\) => setRequestedGroupId\(groupId\)\}/);
  assert.doesNotMatch(page, />Recibidos<\/button>[\s\S]*>Enviados<\/button>[\s\S]*>Historial<\/button>/);
  assert.doesNotMatch(panel, /Sincronización|Revisión \$\{|Sin snapshot|team-challenges-toolbar/);
});

test("the creation journey has exactly three steps and sends only at review", async () => {
  const panel = await source("app/mercado/team-challenges-panel.tsx");
  assert.match(panel, /useState<1 \| 2 \| 3>\(1\)/);
  assert.match(panel, /\[1, 2, 3\]\.map/);
  assert.match(panel, /Elige rival/);
  assert.match(panel, /Cuándo y dónde/);
  assert.match(panel, /Revisa la propuesta/);
  assert.match(panel, /Más detalles/);
  assert.match(panel, /El reto solo se enviará al confirmar este último paso/);
  assert.match(panel, /create_pachanga_team_challenge_authoritative/);
  assert.match(panel, /expected_revision: snapshot\.socialRevision/);
  assert.match(panel, /operation_id: operationId/);
  assert.match(panel, /disabled=\{!confirmedTeam\}/);
});

test("known opponents and exact market rival deep links only preselect", async () => {
  const [panel, market] = await Promise.all([source("app/mercado/team-challenges-panel.tsx"), source("app/mercado/marketplace-client.tsx")]);
  assert.match(panel, /filtered\.slice\(0, 5\)/);
  assert.match(panel, /lookup_pachanga_team_by_code/);
  assert.match(panel, /initialTeamCode/);
  assert.match(market, /\/retos\?view=active&crear=1&rival=/);
  assert.doesNotMatch(market, /\/retos\?vista=search/);
});

test("counterproposals preserve the authoritative response RPC and prior proposal", async () => {
  const panel = await source("app/mercado/team-challenges-panel.tsx");
  assert.match(panel, /Propuesta actual/);
  assert.match(panel, /Tu contrapropuesta/);
  assert.match(panel, /target_action: "propose_changes"/);
  assert.match(panel, /respond_pachanga_team_challenge_authoritative/);
  assert.match(panel, /data-changed=/);
  assert.match(panel, /challenge\.direction === "outgoing" && challenge\.lastProposedBy === "own"/);
  assert.doesNotMatch(panel, /setSnapshot\([^)]*challenge\.status/);
});

test("accept, reject and cancel wait for canonical snapshots and stale state refetches", async () => {
  const panel = await source("app/mercado/team-challenges-panel.tsx");
  assert.match(panel, /acceptCanonicalSnapshot\(result\.data/);
  assert.match(panel, /if \(nextNotice\.stale\) await loadSnapshot/);
  assert.match(panel, /window\.confirm/);
  assert.match(panel, /target_action: action/);
});

test("role and offline boundaries stay fail-closed", async () => {
  const [page, panel] = await Promise.all([source("app/retos/page.tsx"), source("app/mercado/team-challenges-panel.tsx")]);
  assert.match(page, /selectedMembership\?\.role === "owner"/);
  assert.match(page, /selectedMembership\?\.role === "admin"/);
  assert.match(panel, /snapshot\?\.canManage/);
  assert.match(panel, /Aún no tienes equipo/);
  assert.match(panel, /Solo un admin u owner/);
  assert.match(panel, /!navigator\.onLine/);
  assert.match(panel, /Necesitas conexión para confirmar esta acción/);
  assert.doesNotMatch(panel, /offline.*queue|queued.*challenge/i);
});

test("Realtime invalidates and debounces a canonical refetch", async () => {
  const panel = await source("app/mercado/team-challenges-panel.tsx");
  assert.match(panel, /pachanga_team_social_state/);
  assert.match(panel, /scheduleCanonicalRefresh/);
  assert.match(panel, /window\.setTimeout[\s\S]*loadSnapshot/);
  assert.match(panel, /status === "SUBSCRIBED"/);
  assert.match(panel, /window\.addEventListener\("online"/);
  assert.doesNotMatch(panel, /setSnapshot\([^)]*payload/);
});

test("accepted challenges remain active and reuse ExternalResultsPanel", async () => {
  const [page, panel, external] = await Promise.all([
    source("app/retos/page.tsx"),
    source("app/mercado/team-challenges-panel.tsx"),
    source("app/mercado/external-results-panel.tsx"),
  ]);
  assert.match(panel, /groups\.agreed/);
  assert.match(panel, /Partidos acordados/);
  assert.match(page, /matchChallengeId/);
  assert.match(panel, /<ExternalResultsPanel groupId=\{selectedGroupId\} initialChallengeId=\{matchChallengeId\}/);
  assert.match(external, /match\.challengeId === initialChallengeId/);
  assert.match(panel, /Origen: Reto entre equipos/);
});

test("the social Demo covers the local challenge lifecycle with zero remote effects", async () => {
  const demo = await source("app/demo-world/demo-world-app.tsx");
  for (const copy of [
    "Reto aceptado en la sesión Demo",
    "Contrapropuesta guardada solo en esta sesión Demo",
    "Reto creado solo en esta sesión Demo",
    "Reto cancelado solo en la sesión Demo",
    "Vista jugador",
    "No perteneces todavía a ningún equipo",
    "Ver como",
    "Partidos acordados",
  ]) assert.match(demo, new RegExp(copy));
  assert.match(demo, /remoteWrites = 0/);
  assert.match(demo, /externalNotifications = 0/);
  assert.match(demo, /realEntities = 0/);
  assert.match(demo, /StripeCalls = 0/);
  assert.match(demo, /draft\.kind === selectedChallenge\.proposedKind/);
  assert.doesNotMatch(demo, /supabaseClient|\.rpc\(|method:\s*["'](?:POST|PUT|PATCH|DELETE)/);
});

test("Home shows at most one canonical social action and V3A/V3B remain linked", async () => {
  const demo = await source("app/demo-world/demo-world-app.tsx");
  assert.match(demo, /const primaryPendingAction = pendingActions\.find/);
  assert.match(demo, /pendingActions=\{socialInboxActions\}/);
  assert.match(demo, /const socialChallenge = demoChallenges\.find/);
  assert.match(demo, /id: DEMO_SOCIAL_CHALLENGE_ID/);
  assert.match(demo, /targetTab: "retos"/);
  assert.match(demo, /function demoChallengeNeedsResponse/);
  assert.match(demo, /demoChallengeLastProposer\(challenge, overrides\) !== teamId/);
  assert.doesNotMatch(demo, /left\.awayTeamId === currentTeam\.id/);
  assert.match(demo, /Pendiente de ti/);
  assert.match(demo, /Responder reto/);
  assert.match(demo, /onPendingAction\(primaryPendingAction\)/);
  assert.match(demo, /OfficialMatchesOverview/);
  assert.match(demo, /OfficialQuickMatchWizard/);
});

test("V3C responsive surfaces cover portrait, compact landscape and reduced motion", async () => {
  const [challengeStyles, demoStyles] = await Promise.all([source("app/retos/retos.module.css"), source("app/demo-world/demo-world.module.css")]);
  assert.match(challengeStyles, /@media \(max-width: 760px\) and \(orientation: portrait\)/);
  assert.match(challengeStyles, /@media \(orientation: landscape\) and \(max-height: 600px\)/);
  assert.match(challengeStyles, /env\(safe-area-inset-bottom\)/);
  assert.match(challengeStyles, /prefers-reduced-motion/);
  assert.match(challengeStyles, /min-height: 40px/);
  assert.match(demoStyles, /demoChallengesV3c/);
  assert.match(demoStyles, /demoChallengeFocus/);
  assert.match(demoStyles, /demoChallengeCard/);
});

test("the PWA caches the Retos read shell while challenge writes remain online-only", async () => {
  const [worker, panel] = await Promise.all([
    source("app/service-worker-source.ts"),
    source("app/mercado/team-challenges-panel.tsx"),
  ]);
  assert.match(worker, /precacheUrls = \[[\s\S]*"\/retos"/);
  assert.match(worker, /CACHEABLE_NAVIGATION_PATHS = new Set\(\[[^\]]*"\/retos"/);
  assert.match(panel, /!navigator\.onLine/);
  assert.doesNotMatch(panel, /offline.*queue|queued.*challenge/i);
});

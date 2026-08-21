import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  CLIENT_UPDATE_REQUIRED,
  V1_UNVERSIONED,
  classifyClientVersion,
  clientVersionIsSupported,
  compareSemVer,
  detectClientDisplayMode,
  parseSemVer,
} from "../app/client-version-contract";
import {
  OFFLINE_WRITE_NOT_CONFIRMED,
  PwaWriteBridge,
  WRITE_PAUSED_FOR_UPDATE,
  type PwaWriteRejection,
} from "../app/pwa-client-bridge-core";
import {
  activateWaitingServiceWorker,
  reloadOnceAfterControllerChange,
} from "../app/pwa-service-worker-update";
import {
  classifySupabaseWrite,
  isKnownClientWriteOperation,
  knownClientWriteRpcNames,
  knownV1WriteRpcNames,
} from "../app/pwa-write-classifier";
import type { ClientWriteTelemetryInput } from "../app/api/client-telemetry/_contract";

function policyResponse(minimum: string, writeAllowed: boolean) {
  return Response.json({
    clientClassification: writeAllowed ? "1.0.0+test" : "v1-unversioned",
    minimumSupportedClientVersion: minimum,
    serverTime: "2026-08-02T12:00:00.000Z",
    writeAllowed,
  });
}

function createBridge(input: {
  clientVersion?: string;
  displayMode?: "browser" | "fullscreen" | "standalone";
  fetchPolicy?: typeof fetch;
  online?: () => boolean;
}) {
  const rejected: PwaWriteRejection[] = [];
  const telemetry: ClientWriteTelemetryInput[] = [];
  const bridge = new PwaWriteBridge({
    clientVersion: input.clientVersion ?? "1.0.0+abc123",
    displayMode: () => input.displayMode ?? "browser",
    fetch: input.fetchPolicy ?? (async () => policyResponse("1.0.0", true)),
    isOnline: input.online ?? (() => true),
    onRejected: (entry) => rejected.push(entry),
    randomUUID: () => "123e4567-e89b-42d3-a456-426614174000",
    serviceWorkerVersion: "1.0.0+sw.abc123",
    telemetry: (entry) => {
      telemetry.push(entry);
    },
  });
  return { bridge, rejected, telemetry };
}

test("compares SemVer correctly and ignores build metadata", () => {
  assert.equal(compareSemVer("1.0.0+abc", "1.0.0+xyz"), 0);
  assert.equal(compareSemVer("1.0.1+abc", "1.0.0+xyz"), 1);
  assert.equal(compareSemVer("2.0.0-alpha.2+one", "2.0.0-alpha.10+two"), -1);
  assert.equal(compareSemVer("2.0.0-rc.1", "2.0.0"), -1);
  assert.equal(parseSemVer("1.0.0-01"), null);
  assert.equal(classifyClientVersion(undefined), V1_UNVERSIONED);
  assert.equal(classifyClientVersion("not-a-version"), V1_UNVERSIONED);
  assert.equal(clientVersionIsSupported("1.0.0+sha", "1.0.0"), true);
});

test("classifies browser, installed PWA and fullscreen modes", () => {
  assert.equal(detectClientDisplayMode({ fullscreen: false, standalone: false }), "browser");
  assert.equal(detectClientDisplayMode({ fullscreen: false, standalone: true }), "standalone");
  assert.equal(detectClientDisplayMode({ fullscreen: false, iosStandalone: true, standalone: false }), "standalone");
  assert.equal(detectClientDisplayMode({ fullscreen: true, standalone: true }), "fullscreen");
});

test("sends immutable versions and display mode with a compatible write", async () => {
  const { bridge, rejected, telemetry } = createBridge({ displayMode: "standalone" });
  let sentHeaders: Headers | null = null;

  const response = await bridge.executeWrite("rpc:save_pachanga_payload_if_current", async (headers) => {
    sentHeaders = headers;
    return Response.json({ payload_revision: 19 });
  });

  assert.equal(response.ok, true);
  assert.equal(sentHeaders?.get("x-pachangas-client-version"), "1.0.0+abc123");
  assert.equal(sentHeaders?.get("x-pachangas-service-worker-version"), "1.0.0+sw.abc123");
  assert.equal(sentHeaders?.get("x-pachangas-display-mode"), "standalone");
  assert.equal(sentHeaders?.get("x-pachangas-operation"), "rpc:save_pachanga_payload_if_current");
  assert.equal(rejected.length, 0);
  assert.deepEqual(telemetry.map((entry) => entry.result), ["attempted", "confirmed"]);
});

test("blocks an unversioned or older client but keeps reads classifiable as reads", async () => {
  for (const clientVersion of [undefined, "0.9.9+old"]) {
    let writesSent = 0;
    const classified = classifyClientVersion(clientVersion);
    const { bridge, rejected } = createBridge({
      clientVersion: classified,
      fetchPolicy: async () => policyResponse("1.0.0", false),
    });
    const response = await bridge.executeWrite("rpc:patch_pachanga_match_player_status", async () => {
      writesSent += 1;
      return Response.json({ ok: true });
    });
    const body = (await response.json()) as { code: string };
    assert.equal(response.status, 426);
    assert.equal(body.code, CLIENT_UPDATE_REQUIRED);
    assert.equal(writesSent, 0);
    assert.equal(rejected[0]?.code, CLIENT_UPDATE_REQUIRED);
  }

  assert.equal(classifySupabaseWrite("https://demo.supabase.co/rest/v1/pachanga_groups?select=*", { method: "GET" }), null);
  assert.equal(classifySupabaseWrite("https://demo.supabase.co/rest/v1/rpc/read_only_future_rpc", { method: "POST" }), null);
});

test("offline writes are unconfirmed and a later retry can converge after reconnection", async () => {
  let online = false;
  let writesSent = 0;
  const { bridge, rejected, telemetry } = createBridge({ online: () => online });

  const offlineResponse = await bridge.executeWrite("table:pachanga_groups:post", async () => {
    writesSent += 1;
    return Response.json({ ok: true });
  });
  assert.equal(offlineResponse.status, 503);
  assert.equal((await offlineResponse.json() as { code: string }).code, OFFLINE_WRITE_NOT_CONFIRMED);
  assert.equal(writesSent, 0);
  assert.equal(rejected.at(-1)?.code, OFFLINE_WRITE_NOT_CONFIRMED);
  assert.equal(telemetry.at(-1)?.result, "rejected-offline");

  online = true;
  bridge.setOnlineState(true);
  const reconnectedResponse = await bridge.executeWrite("table:pachanga_groups:post", async () => {
    writesSent += 1;
    return Response.json({ ok: true });
  });
  assert.equal(reconnectedResponse.ok, true);
  assert.equal(writesSent, 1);
  assert.equal(bridge.snapshot().offline, false);
});

test("RPC errors reject optimistic state instead of being interpreted as success", async () => {
  const { bridge, rejected, telemetry } = createBridge({});
  const response = await bridge.executeWrite("rpc:finalize_pachanga_match_if_current", async () => Response.json({
    code: "STALE_REVISION",
    message: "revision mismatch",
  }, { status: 409 }));

  assert.equal(response.status, 409);
  assert.equal(rejected.at(-1)?.code, "STALE_REVISION");
  assert.equal(telemetry.at(-1)?.result, "rpc-error");
});

test("a waiting worker pauses new writes until the in-flight write finishes", async () => {
  const { bridge } = createBridge({});
  let releaseWrite: (() => void) | null = null;
  const pendingResponse = new Promise<Response>((resolve) => {
    releaseWrite = () => resolve(Response.json({ ok: true }));
  });
  const pendingWrite = bridge.executeWrite("rpc:save_pachanga_payload_if_current", async () => pendingResponse);
  await new Promise((resolve) => setTimeout(resolve, 0));

  const messages: unknown[] = [];
  let expectedVersion = "";
  const activation = activateWaitingServiceWorker({
    getVersion: async () => "1.0.1+sw.next",
    pauseWrites: (paused) => bridge.setWritesPaused(paused),
    registration: { waiting: { postMessage: (message) => messages.push(message) } },
    setExpectedVersion: (version) => {
      expectedVersion = version;
    },
    waitForWrites: () => bridge.waitForActiveWrites(2_000),
  });

  const pausedResponse = await bridge.executeWrite("rpc:patch_pachanga_match_player_paid", async () => Response.json({ ok: true }));
  assert.equal((await pausedResponse.json() as { code: string }).code, WRITE_PAUSED_FOR_UPDATE);
  assert.deepEqual(messages, []);

  releaseWrite?.();
  await pendingWrite;
  assert.equal(await activation, true);
  assert.equal(expectedVersion, "1.0.1+sw.next");
  assert.deepEqual(messages, [{ type: "SKIP_WAITING" }]);
});

test("controllerchange reloads exactly once per Service Worker version", () => {
  const values = new Map<string, string>();
  let reloads = 0;
  const input = {
    reload: () => {
      reloads += 1;
    },
    serviceWorkerVersion: "1.0.1+sw.next",
    storage: {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => {
        values.set(key, value);
      },
    },
  };

  assert.equal(reloadOnceAfterControllerChange(input), true);
  assert.equal(reloadOnceAfterControllerChange(input), false);
  assert.equal(reloads, 1);
});

test("the classifier covers every current V1 write RPC and leaves auth outside the bridge", () => {
  const expectedRpcNames = [
    "accept_pachanga_admin_invite",
    "append_pachanga_player_rating",
    "complete_pachanga_player_advanced_assessment",
    "complete_pachanga_player_initial_assessment",
    "create_pachanga_admin_invite",
    "create_pachanga_group_backup",
    "finalize_pachanga_match_if_current",
    "join_pachanga_team",
    "patch_pachanga_match_lineup_state",
    "patch_pachanga_match_player_paid",
    "patch_pachanga_match_player_status",
    "patch_pachanga_match_scorers",
    "patch_pachanga_player_profile",
    "request_pachanga_open_match",
    "restore_pachanga_group_backup",
    "review_pachanga_open_match_request",
    "save_pachanga_payload_if_current",
    "set_pachanga_member_role",
    "sync_pachanga_market_profile",
    "sync_pachanga_open_match",
    "update_pachanga_member_name",
    "upsert_pachanga_own_player_profile",
  ];
  assert.deepEqual(knownV1WriteRpcNames(), expectedRpcNames);
  for (const rpcName of expectedRpcNames) {
    assert.equal(
      classifySupabaseWrite(`https://demo.supabase.co/rest/v1/rpc/${rpcName}`, { method: "POST" }),
      `rpc:${rpcName}`,
    );
  }
  assert.equal(classifySupabaseWrite("https://demo.supabase.co/auth/v1/token", { method: "POST" }), null);
});

test("the write bridge classifies every browser RPC without treating reads as writes", async () => {
  const source = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/mercado/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/mercado/challengeable-teams-panel.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/mercado/team-challenges-panel.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/notification-center.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/invitacion-partido/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/partido-invitado/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/global-rating-panel.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/valorar-equipo/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/conduct-player-center.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/conduct-report-form.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/admin/conduct/conduct-admin-client.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/personalizar-carta/page.tsx", import.meta.url), "utf8"),
  ]).then((files) => files.join("\n"));
  const readRpcNames = new Set([
    "get_pachanga_global_rating_context_v2",
    "get_pachanga_guest_rating_token_context_v2",
    "get_pachanga_rating_eligibility",
    "get_pachanga_team_social_snapshot",
    "get_pachanga_challengeable_team_profile",
    "get_pachanga_guest_match_snapshot_v1",
    "get_pachanga_match_link_invitation_v1",
    "get_pachanga_match_invitation_admin_state_v1",
    "get_pachanga_notification_center_v1",
    "get_pachanga_player_cosmetics_snapshot_v1",
    "get_pachanga_public_player_card_cosmetics_v1",
    "get_pachanga_referee_foundation_flags_v1",
    "get_pachanga_attendance_admin_v1",
    "get_pachanga_moderation_case_evidence_v1",
    "get_pachanga_moderation_case_evidence_v1_1",
    "get_pachanga_moderation_queue_v1",
    "get_pachanga_moderation_queue_v1_1",
    "get_pachanga_my_conduct_v1",
    "get_my_pachanga_open_match_requests_v1",
    "lookup_pachanga_challengeable_team_for_challenge",
    "lookup_pachanga_team_by_code",
    "search_pachanga_challengeable_teams",
    "search_pachanga_open_matches_v1",
  ]);
  const invokedRpcNames = [...new Set(
    [...source.matchAll(/\.rpc\("([a-z0-9_]+)"/g)].map((match) => match[1]),
  )].sort();
  const currentWriteRpcNames = invokedRpcNames.filter((rpcName) => !readRpcNames.has(rpcName));

  for (const rpcName of invokedRpcNames) {
    const classified = classifySupabaseWrite(`https://demo.supabase.co/rest/v1/rpc/${rpcName}`, { method: "POST" });
    assert.equal(classified, readRpcNames.has(rpcName) ? null : `rpc:${rpcName}`);
  }
  assert.deepEqual(
    currentWriteRpcNames,
    knownClientWriteRpcNames().filter((rpcName) => currentWriteRpcNames.includes(rpcName)),
  );
  assert.equal(isKnownClientWriteOperation("api:ratings-assessment"), true);
  assert.match(source, /clientWriteFetch\("api:ratings-assessment", "\/api\/ratings\/assessment"/);
});

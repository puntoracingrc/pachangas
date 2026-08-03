import assert from "node:assert/strict";
import test from "node:test";
import { GET as getClientPolicy } from "../app/api/client-policy/route";
import { POST as postClientTelemetry } from "../app/api/client-telemetry/route";
import { GET as getServiceWorker } from "../app/sw.js/route";
import { clientWriteGateResponse } from "../app/api/client-policy/_contract";

test("client policy is no-store and requires minimumSupportedClientVersion 2.0.0", async () => {
  const previous = process.env.PACHANGAS_MINIMUM_SUPPORTED_CLIENT_VERSION;
  delete process.env.PACHANGAS_MINIMUM_SUPPORTED_CLIENT_VERSION;
  try {
    const response = await getClientPolicy(new Request("http://localhost/api/client-policy", {
      headers: { "X-Pachangas-Client-Version": "2.0.0+abcdef" },
    }));
    const body = (await response.json()) as { minimumSupportedClientVersion: string; writeAllowed: boolean };
    assert.equal(body.minimumSupportedClientVersion, "2.0.0");
    assert.equal(body.writeAllowed, true);
    assert.match(response.headers.get("cache-control") ?? "", /no-store/);
    assert.equal(response.headers.get("pragma"), "no-cache");
  } finally {
    if (previous === undefined) delete process.env.PACHANGAS_MINIMUM_SUPPORTED_CLIENT_VERSION;
    else process.env.PACHANGAS_MINIMUM_SUPPORTED_CLIENT_VERSION = previous;
  }
});

test("server policy classifies unversioned and old clients and blocks only writes", async () => {
  const unversioned = await getClientPolicy(new Request("http://localhost/api/client-policy"));
  const unversionedBody = (await unversioned.json()) as { clientClassification: string; writeAllowed: boolean };
  assert.equal(unversionedBody.clientClassification, "v1-unversioned");
  assert.equal(unversionedBody.writeAllowed, false);

  const oldRequest = new Request("http://localhost/api/billing/checkout", {
    headers: { "X-Pachangas-Client-Version": "0.9.9+old" },
    method: "POST",
  });
  const blockedWrite = clientWriteGateResponse(oldRequest);
  assert.equal(blockedWrite?.status, 426);
  assert.equal((await blockedWrite?.json() as { error: { code: string } }).error.code, "CLIENT_UPDATE_REQUIRED");

  const compatibleRequest = new Request("http://localhost/api/billing/checkout", {
    headers: { "X-Pachangas-Client-Version": "2.0.0+current" },
    method: "POST",
  });
  assert.equal(clientWriteGateResponse(compatibleRequest), null);
});

test("telemetry accepts only a no-PII allowlist and assigns server time", async () => {
  const validTelemetry = {
    clientVersion: "1.0.0+abcdef",
    displayMode: "fullscreen",
    event: "write-intent",
    operation: "rpc:patch_pachanga_match_player_status",
    result: "confirmed",
    serviceWorkerVersion: "1.0.0+sw.abcdef",
    writeId: "123e4567-e89b-42d3-a456-426614174000",
  };
  const originalInfo = console.info;
  const logged: string[] = [];
  console.info = (...values: unknown[]) => logged.push(values.join(" "));
  try {
    const accepted = await postClientTelemetry(new Request("http://localhost/api/client-telemetry", {
      body: JSON.stringify(validTelemetry),
      headers: { "Content-Type": "application/json" },
      method: "POST",
    }));
    const acceptedBody = (await accepted.json()) as { accepted: boolean; serverTime: string };
    assert.equal(acceptedBody.accepted, true);
    assert.match(acceptedBody.serverTime, /^\d{4}-\d{2}-\d{2}T/);
    assert.match(accepted.headers.get("cache-control") ?? "", /no-store/);
    assert.equal(logged.length, 1);
    assert.match(logged[0], /serverTime/);
    assert.doesNotMatch(logged[0], /nobody@example|"email"|"displayName"|"payload"/i);

    const rejected = await postClientTelemetry(new Request("http://localhost/api/client-telemetry", {
      body: JSON.stringify({ ...validTelemetry, email: "nobody@example.test" }),
      headers: { "Content-Type": "application/json" },
      method: "POST",
    }));
    assert.equal(rejected.status, 400);
    assert.equal(logged.length, 1);

    const disguisedPii = await postClientTelemetry(new Request("http://localhost/api/client-telemetry", {
      body: JSON.stringify({ ...validTelemetry, operation: "api:persona-privada" }),
      headers: { "Content-Type": "application/json" },
      method: "POST",
    }));
    assert.equal(disguisedPii.status, 400);
  } finally {
    console.info = originalInfo;
  }
});

test("Service Worker endpoint is versioned and never cached", async () => {
  const response = await getServiceWorker();
  const source = await response.text();
  assert.match(response.headers.get("cache-control") ?? "", /no-store/);
  assert.equal(response.headers.get("service-worker-allowed"), "/");
  assert.match(source, /SERVICE_WORKER_VERSION/);
  assert.match(source, /GET_VERSION/);
  assert.match(source, /SKIP_WAITING/);
  assert.doesNotMatch(source, /install[\s\S]{0,220}skipWaiting/);
});

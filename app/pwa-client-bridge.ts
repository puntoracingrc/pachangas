"use client";

import {
  CLIENT_VERSION,
  V1_UNVERSIONED,
  detectClientDisplayMode,
  type ClientDisplayMode,
} from "./client-version-contract";
import type { ClientWriteTelemetryInput } from "./api/client-telemetry/_contract";
import {
  PwaWriteBridge,
  type PwaBridgeSnapshot,
  type PwaWriteRejection,
} from "./pwa-client-bridge-core";
import { classifySupabaseWrite } from "./pwa-write-classifier";

export const PWA_WRITE_REJECTED_EVENT = "pachangas:pwa-write-rejected";

const telemetryQueueKey = "pachangas-pwa-telemetry-v1";
const maxQueuedTelemetryRecords = 100;

let bridge: PwaWriteBridge | null = null;

function nativeFetch(input: RequestInfo | URL, init?: RequestInit) {
  return globalThis.fetch(input, init);
}

function randomUUID() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") return crypto.randomUUID();
  if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") {
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = [...bytes].map((value) => value.toString(16).padStart(2, "0"));
    return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (token) => {
    const value = Math.floor(Math.random() * 16);
    return (token === "x" ? value : (value & 0x3) | 0x8).toString(16);
  });
}

export function currentClientDisplayMode(): ClientDisplayMode {
  if (typeof window === "undefined" || typeof navigator === "undefined") return "browser";
  const iosNavigator = navigator as Navigator & { standalone?: boolean };
  return detectClientDisplayMode({
    fullscreen: window.matchMedia("(display-mode: fullscreen)").matches,
    iosStandalone: Boolean(iosNavigator.standalone),
    minimalUi: window.matchMedia("(display-mode: minimal-ui)").matches,
    standalone: window.matchMedia("(display-mode: standalone)").matches,
  });
}

function readQueuedTelemetry() {
  if (typeof window === "undefined") return [] as ClientWriteTelemetryInput[];
  try {
    const parsed = JSON.parse(window.sessionStorage.getItem(telemetryQueueKey) ?? "[]") as unknown;
    return Array.isArray(parsed) ? (parsed.slice(-maxQueuedTelemetryRecords) as ClientWriteTelemetryInput[]) : [];
  } catch {
    return [] as ClientWriteTelemetryInput[];
  }
}

function storeQueuedTelemetry(records: ClientWriteTelemetryInput[]) {
  if (typeof window === "undefined") return;
  try {
    window.sessionStorage.setItem(telemetryQueueKey, JSON.stringify(records.slice(-maxQueuedTelemetryRecords)));
  } catch {
    // Telemetry is best effort and never justifies blocking an application write.
  }
}

function queueTelemetry(record: ClientWriteTelemetryInput) {
  storeQueuedTelemetry([...readQueuedTelemetry(), record]);
}

async function postTelemetry(record: ClientWriteTelemetryInput) {
  if (typeof navigator !== "undefined" && !navigator.onLine) {
    queueTelemetry(record);
    return;
  }

  try {
    const response = await nativeFetch("/api/client-telemetry", {
      body: JSON.stringify(record),
      cache: "no-store",
      headers: { "Content-Type": "application/json" },
      keepalive: true,
      method: "POST",
    });
    if (!response.ok) queueTelemetry(record);
  } catch {
    queueTelemetry(record);
  }
}

export async function flushQueuedClientTelemetry() {
  if (typeof navigator !== "undefined" && !navigator.onLine) return;
  const queued = readQueuedTelemetry();
  if (queued.length === 0) return;
  storeQueuedTelemetry([]);

  for (let index = 0; index < queued.length; index += 1) {
    try {
      const response = await nativeFetch("/api/client-telemetry", {
        body: JSON.stringify(queued[index]),
        cache: "no-store",
        headers: { "Content-Type": "application/json" },
        keepalive: true,
        method: "POST",
      });
      if (!response.ok) {
        storeQueuedTelemetry(queued.slice(index));
        return;
      }
    } catch {
      storeQueuedTelemetry(queued.slice(index));
      return;
    }
  }
}

function dispatchWriteRejection(rejection: PwaWriteRejection) {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent<PwaWriteRejection>(PWA_WRITE_REJECTED_EVENT, { detail: rejection }));
}

export function getPwaWriteBridge() {
  if (!bridge) {
    bridge = new PwaWriteBridge({
      clientVersion: CLIENT_VERSION,
      displayMode: currentClientDisplayMode,
      fetch: nativeFetch,
      isOnline: () => typeof navigator === "undefined" || navigator.onLine,
      onRejected: dispatchWriteRejection,
      randomUUID,
      serviceWorkerVersion: V1_UNVERSIONED,
      telemetry: postTelemetry,
    });
  }
  return bridge;
}

function headersWithBridgeMetadata(input: RequestInfo | URL, init: RequestInit | undefined, metadata: Headers) {
  const headers = new Headers(typeof Request !== "undefined" && input instanceof Request ? input.headers : undefined);
  new Headers(init?.headers).forEach((value, key) => headers.set(key, value));
  metadata.forEach((value, key) => headers.set(key, value));
  return headers;
}

export async function supabaseBridgeFetch(input: RequestInfo | URL, init?: RequestInit) {
  const operation = classifySupabaseWrite(input, init);
  if (!operation || typeof window === "undefined") return nativeFetch(input, init);

  return getPwaWriteBridge().executeWrite(operation, (metadata) => nativeFetch(input, {
    ...init,
    headers: headersWithBridgeMetadata(input, init, metadata),
  }));
}

export async function clientWriteFetch(operation: `api:${string}`, input: RequestInfo | URL, init?: RequestInit) {
  if (typeof window === "undefined") return nativeFetch(input, init);
  return getPwaWriteBridge().executeWrite(operation, (metadata) => nativeFetch(input, {
    ...init,
    headers: headersWithBridgeMetadata(input, init, metadata),
  }));
}

export function subscribePwaBridge(listener: () => void) {
  return getPwaWriteBridge().subscribe(listener);
}

export function pwaBridgeSnapshot(): PwaBridgeSnapshot {
  if (typeof window === "undefined") {
    return {
      activeWrites: 0,
      clientVersion: CLIENT_VERSION,
      lastErrorCode: null,
      minimumSupportedClientVersion: null,
      offline: false,
      serviceWorkerVersion: V1_UNVERSIONED,
      updateRequired: false,
      writesPaused: false,
    };
  }
  return getPwaWriteBridge().snapshot();
}

export function pausePwaWrites(paused: boolean) {
  getPwaWriteBridge().setWritesPaused(paused);
}

export function waitForPwaWrites(timeoutMs?: number) {
  return getPwaWriteBridge().waitForActiveWrites(timeoutMs);
}

export function setPwaOnlineState(online: boolean) {
  getPwaWriteBridge().setOnlineState(online);
}

export function setPwaServiceWorkerVersion(version: string | null | undefined) {
  getPwaWriteBridge().setServiceWorkerVersion(version);
}

export function refreshPwaClientPolicy() {
  return getPwaWriteBridge().refreshPolicy();
}

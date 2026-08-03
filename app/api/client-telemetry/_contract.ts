import { classifyClientVersion, type ClientDisplayMode } from "../../client-version-contract";
import { isKnownClientWriteOperation } from "../../pwa-write-classifier";

export const telemetryResults = [
  "attempted",
  "confirmed",
  "network-error",
  "rejected-offline",
  "rejected-paused",
  "rejected-update",
  "rpc-error",
] as const;

export type ClientWriteTelemetryResult = (typeof telemetryResults)[number];

export type ClientWriteTelemetryInput = {
  clientVersion: string;
  displayMode: ClientDisplayMode;
  event: "write-intent";
  operation: string;
  result: ClientWriteTelemetryResult;
  serviceWorkerVersion: string;
  writeId: string;
};

const allowedKeys = new Set<keyof ClientWriteTelemetryInput>([
  "clientVersion",
  "displayMode",
  "event",
  "operation",
  "result",
  "serviceWorkerVersion",
  "writeId",
]);
const displayModes = new Set<ClientDisplayMode>(["browser", "fullscreen", "standalone"]);
const resultValues = new Set<string>(telemetryResults);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function sanitizeClientWriteTelemetry(value: unknown): ClientWriteTelemetryInput | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !allowedKeys.has(key as keyof ClientWriteTelemetryInput))) return null;
  if (record.event !== "write-intent") return null;
  if (typeof record.operation !== "string" || !isKnownClientWriteOperation(record.operation)) return null;
  if (typeof record.clientVersion !== "string" || classifyClientVersion(record.clientVersion) !== record.clientVersion) return null;
  if (typeof record.serviceWorkerVersion !== "string" || classifyClientVersion(record.serviceWorkerVersion) !== record.serviceWorkerVersion) return null;
  if (typeof record.displayMode !== "string" || !displayModes.has(record.displayMode as ClientDisplayMode)) return null;
  if (typeof record.result !== "string" || !resultValues.has(record.result)) return null;
  if (typeof record.writeId !== "string" || !uuidPattern.test(record.writeId)) return null;

  return {
    clientVersion: record.clientVersion,
    displayMode: record.displayMode as ClientDisplayMode,
    event: "write-intent",
    operation: record.operation,
    result: record.result as ClientWriteTelemetryResult,
    serviceWorkerVersion: record.serviceWorkerVersion,
    writeId: record.writeId,
  };
}

export function serverTelemetryRecord(input: ClientWriteTelemetryInput) {
  return {
    ...input,
    serverTime: new Date().toISOString(),
  };
}

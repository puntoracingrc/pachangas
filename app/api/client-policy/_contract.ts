import {
  CLIENT_UPDATE_REQUIRED,
  INITIAL_MINIMUM_SUPPORTED_CLIENT_VERSION,
  classifyClientVersion,
  clientVersionIsSupported,
  parseSemVer,
} from "../../client-version-contract";

export const clientBridgeHeaderNames = {
  clientVersion: "x-pachangas-client-version",
  displayMode: "x-pachangas-display-mode",
  operation: "x-pachangas-operation",
  serviceWorkerVersion: "x-pachangas-service-worker-version",
  writeId: "x-pachangas-write-id",
} as const;

export const noStoreHeaders = {
  "Cache-Control": "private, no-store, max-age=0, must-revalidate",
  Expires: "0",
  Pragma: "no-cache",
} as const;

export function minimumSupportedClientVersion() {
  const configured = process.env.PACHANGAS_MINIMUM_SUPPORTED_CLIENT_VERSION?.trim();
  if (!configured) return INITIAL_MINIMUM_SUPPORTED_CLIENT_VERSION;
  if (!parseSemVer(configured)) throw new Error("PACHANGAS_MINIMUM_SUPPORTED_CLIENT_VERSION must be valid SemVer");
  return configured;
}

export function evaluateClientPolicy(headers: Headers) {
  const minimum = minimumSupportedClientVersion();
  const suppliedVersion = headers.get(clientBridgeHeaderNames.clientVersion);
  const clientClassification = classifyClientVersion(suppliedVersion);
  const writeAllowed = clientVersionIsSupported(suppliedVersion, minimum);

  return {
    clientClassification,
    error: writeAllowed
      ? null
      : {
          code: CLIENT_UPDATE_REQUIRED,
          message: "Actualiza Pachangas IQ antes de volver a guardar cambios.",
        },
    minimumSupportedClientVersion: minimum,
    serverTime: new Date().toISOString(),
    writeAllowed,
  };
}

export function clientWriteGateResponse(request: Request) {
  const policy = evaluateClientPolicy(request.headers);
  if (policy.writeAllowed) return null;
  return Response.json(policy, { status: 426, headers: noStoreHeaders });
}

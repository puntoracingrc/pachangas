import { noStoreHeaders } from "../client-policy/_contract";
import { platformUserClient } from "../../admin/_lib/platform-auth";

export const venueUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function venueApiJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

export function venueApiRecord(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

export async function venueApiSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("VENUE_AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const user = await client.auth.getUser(token);
  if (user.error || !user.data.user) throw new Error("VENUE_AUTHENTICATION_REQUIRED");
  return { client, token, user: user.data.user };
}

export function venueApiError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const status = /AUTHENTICATION_REQUIRED/i.test(message) ? 401
    : /STALE_REVISION|CONFLICT|PT409/i.test(message) ? 409
      : /FORBIDDEN|AUTHORITY_REQUIRED|NOT_VISIBLE|42501/i.test(message) ? 403
        : /NOT_FOUND|P0002/i.test(message) ? 404
          : /DISABLED|NOT_AVAILABLE|0A000/i.test(message) ? 409
            : 400;
  return venueApiJson({ error: "VENUE_OPERATION_REJECTED", message }, status);
}

export function venueClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface,
  };
}

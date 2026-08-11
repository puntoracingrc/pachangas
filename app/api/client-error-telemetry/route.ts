import { createHash, randomBytes } from "node:crypto";
import { noStoreHeaders } from "../client-policy/_contract";
import { platformServiceClient } from "../../admin/_lib/platform-auth";
import { sanitizeClientErrorTelemetry } from "./_contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const buckets = new Map<string, { count: number; expiresAt: number }>();
const runtimeSalt = randomBytes(16);

function rateLimitKey(request: Request) {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  return createHash("sha256").update(runtimeSalt).update(forwarded).digest("hex").slice(0, 24);
}

function limited(request: Request) {
  const now = Date.now();
  const key = rateLimitKey(request);
  const bucket = buckets.get(key);
  if (!bucket || bucket.expiresAt <= now) {
    buckets.set(key, { count: 1, expiresAt: now + 60_000 });
    if (buckets.size > 2000) for (const [entry, value] of buckets) if (value.expiresAt <= now) buckets.delete(entry);
    return false;
  }
  bucket.count += 1;
  return bucket.count > 20;
}

export async function POST(request: Request) {
  if (limited(request)) return Response.json({ error: "RATE_LIMITED" }, { status: 429, headers: noStoreHeaders });
  const length = Number(request.headers.get("content-length") ?? 0);
  if (length > 1200) return Response.json({ error: "INVALID_ERROR_TELEMETRY" }, { status: 413, headers: noStoreHeaders });
  let input: unknown;
  try { input = await request.json(); } catch { return Response.json({ error: "INVALID_ERROR_TELEMETRY" }, { status: 400, headers: noStoreHeaders }); }
  const telemetry = sanitizeClientErrorTelemetry(input);
  if (!telemetry) return Response.json({ error: "INVALID_ERROR_TELEMETRY" }, { status: 400, headers: noStoreHeaders });
  try {
    const result = await platformServiceClient().rpc("record_pachanga_client_error_v1", {
      error_app_version: telemetry.appVersion,
      error_browser_family: telemetry.browserFamily,
      error_category: telemetry.category,
      error_fingerprint: telemetry.fingerprint,
      error_platform: telemetry.platform,
      error_route: telemetry.route,
      operation_id: telemetry.operationId,
    });
    if (result.error) throw new Error("Error telemetry sink unavailable");
    return Response.json(result.data, { headers: noStoreHeaders });
  } catch {
    return Response.json({ accepted: false, error: "ERROR_TELEMETRY_UNAVAILABLE" }, { status: 503, headers: noStoreHeaders });
  }
}

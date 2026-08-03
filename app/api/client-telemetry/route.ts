import { noStoreHeaders } from "../client-policy/_contract";
import { sanitizeClientWriteTelemetry, serverTelemetryRecord } from "./_contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > 2048) {
    return Response.json({ error: "Invalid telemetry payload" }, { status: 413, headers: noStoreHeaders });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Invalid telemetry payload" }, { status: 400, headers: noStoreHeaders });
  }

  const telemetry = sanitizeClientWriteTelemetry(body);
  if (!telemetry) {
    return Response.json({ error: "Invalid telemetry payload" }, { status: 400, headers: noStoreHeaders });
  }

  const record = serverTelemetryRecord(telemetry);
  console.info("[pwa-client-telemetry]", JSON.stringify(record));
  return Response.json({ accepted: true, serverTime: record.serverTime }, { headers: noStoreHeaders });
}

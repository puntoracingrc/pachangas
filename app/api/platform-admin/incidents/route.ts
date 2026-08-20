import { platformErrorResponse, platformJson, requirePlatformRequest, requireSameOriginMutation } from "../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const revalidate = 0;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const session = await requirePlatformRequest(request, "system.read");
    const body = record(await request.json());
    const fingerprint = typeof body.fingerprint === "string" ? body.fingerprint : "";
    const state = typeof body.state === "string" ? body.state : "";
    const note = typeof body.note === "string" ? body.note.trim() : "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!/^[0-9a-f]{16,160}$/i.test(fingerprint) || !uuidPattern.test(operationId) || !new Set(["new", "investigating", "resolved", "ignored"]).has(state)) throw new Error("Invalid incident request");
    if (!Number.isInteger(expectedRevision) || expectedRevision < 0 || note.length > 1200 || reason.length < 3 || reason.length > 1200) throw new Error("Invalid incident revision or reason");
    const result = await session.client.rpc("set_pachanga_platform_incident_v1", { error_fingerprint: fingerprint, expected_revision: expectedRevision, incident_note: note || null, next_state: state, operation_id: operationId, reason });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) { return platformErrorResponse(error); }
}

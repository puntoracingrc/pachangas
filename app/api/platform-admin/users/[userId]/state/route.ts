import {
  platformErrorResponse,
  platformJson,
  platformServiceClient,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function record(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

export async function POST(request: Request, context: { params: Promise<{ userId: string }> }) {
  try {
    requireSameOriginMutation(request);
    const session = await requirePlatformRequest(request, "users.suspend");
    const { userId } = await context.params;
    const body = record(await request.json());
    const status = typeof body.status === "string" ? body.status : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    const expectedRevision = Number(body.expectedRevision);
    const expiresAt = typeof body.expiresAt === "string" ? body.expiresAt : null;
    if (!uuidPattern.test(userId) || !uuidPattern.test(operationId)) throw new Error("Invalid operation identifiers");
    if (!Number.isInteger(expectedRevision) || expectedRevision < 0) throw new Error("Invalid expected revision");
    if (!new Set(["active", "suspended", "banned"]).has(status) || reason.length < 3 || reason.length > 1200) {
      throw new Error("Invalid platform state request");
    }
    const expiry = status === "suspended" && expiresAt ? new Date(expiresAt) : null;
    if (status === "suspended" && (!expiry || Number.isNaN(expiry.getTime()) || expiry.getTime() <= Date.now())) {
      throw new Error("Suspension expiry must be in the future");
    }

    const mutation = await session.client.rpc("set_pachanga_platform_user_state_v1", {
      expected_revision: expectedRevision,
      next_expires_at: expiry?.toISOString() ?? null,
      next_status: status,
      operation_id: operationId,
      reason,
      target_user_id: userId,
    });
    if (mutation.error) throw new Error(mutation.error.message);

    const service = platformServiceClient();
    const durationHours = expiry ? Math.max(1, Math.ceil((expiry.getTime() - Date.now()) / (60 * 60 * 1000))) : null;
    const banDuration = status === "active" ? "none" : status === "banned" ? "876000h" : `${durationHours}h`;
    const authResult = await service.auth.admin.updateUserById(userId, { ban_duration: banDuration });
    const sync = await service.rpc("confirm_pachanga_platform_user_auth_sync_v1", {
      sanitized_error: authResult.error ? "Supabase Auth update failed" : null,
      source_operation_id: operationId,
      sync_succeeded: !authResult.error,
    });
    if (sync.error) throw new Error(sync.error.message);
    if (authResult.error) {
      return platformJson({
        canonical: mutation.data,
        error: "AUTH_SYNC_FAILED",
        message: "El estado quedó registrado, pero Supabase Auth no confirmó el cambio. Reintenta la misma operación.",
        sync: sync.data,
      }, { status: 502 });
    }
    return platformJson({ canonical: mutation.data, sync: sync.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}

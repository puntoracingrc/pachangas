import {
  billingServiceClient,
  organizerBillingClientMetadata,
  organizerBillingError,
  organizerBillingJson,
  organizerBillingMode,
  organizerBillingRecord,
  organizerBillingSession,
  organizerBillingWriteGate,
  organizerStripeClient,
  parsePortalInput,
  portalReturnUrl,
  requireOrganizerBillingOrigin,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;
export const runtime = "nodejs";

export async function POST(request: Request) {
  const gated = organizerBillingWriteGate(request);
  if (gated) return gated;
  try {
    requireOrganizerBillingOrigin(request);
    const input = parsePortalInput(await request.json());
    const { user } = await organizerBillingSession(request);
    const mode = organizerBillingMode();
    const service = billingServiceClient();
    const prepared = await service.rpc("prepare_pachanga_organizer_portal_service_v1", {
      actor_id: user.id,
      client_metadata: organizerBillingClientMetadata(request, "organizer_portal"),
      expected_revision: input.expectedRevision,
      operation_id: input.operationId,
      organizer_id: input.organizerId,
      organizer_kind: input.organizerKind,
      stripe_mode: mode,
    });
    if (prepared.error) throw new Error(prepared.error.message);
    const intent = organizerBillingRecord(prepared.data);
    if (intent.status === "SESSION_CREATED" && typeof intent.portalUrl === "string") {
      return organizerBillingJson({ canonical: { replayed: true, status: intent.status, url: intent.portalUrl } });
    }
    const customerId = typeof intent.stripeCustomerId === "string" ? intent.stripeCustomerId : "";
    if (!customerId) throw new Error("BILLING_CUSTOMER_NOT_FOUND");
    const portal = await organizerStripeClient(mode).billingPortal.sessions.create({
      customer: customerId,
      return_url: portalReturnUrl(request, input),
    }, { idempotencyKey: `${input.operationId}:portal` });
    const confirmed = await service.rpc("confirm_pachanga_organizer_portal_service_v1", {
      expires_at: null,
      operation_id: input.operationId,
      portal_url: portal.url,
      stripe_portal_session_id: portal.id,
    });
    if (confirmed.error) throw new Error(confirmed.error.message);
    const canonical = organizerBillingRecord(confirmed.data);
    return organizerBillingJson({ canonical: { replayed: false, status: canonical.status, url: canonical.portalUrl } });
  } catch (error) {
    return organizerBillingError(error);
  }
}

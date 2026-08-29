import {
  billingServiceClient,
  checkoutReturnUrls,
  organizerBillingClientMetadata,
  organizerBillingError,
  organizerBillingJson,
  organizerBillingMode,
  organizerBillingRecord,
  organizerBillingSession,
  organizerBillingWriteGate,
  organizerStripeClient,
  parseCheckoutInput,
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
    const input = parseCheckoutInput(await request.json());
    const { user } = await organizerBillingSession(request);
    const mode = organizerBillingMode();
    const service = billingServiceClient();
    const prepared = await service.rpc("prepare_pachanga_organizer_checkout_service_v1", {
      actor_id: user.id,
      billing_interval: input.billingInterval,
      client_metadata: organizerBillingClientMetadata(request, "organizer_checkout"),
      expected_revision: input.expectedRevision,
      operation_id: input.operationId,
      organizer_id: input.organizerId,
      organizer_kind: input.organizerKind,
      plan_code: input.planCode,
      stripe_mode: mode,
    });
    if (prepared.error) throw new Error(prepared.error.message);
    const intent = organizerBillingRecord(prepared.data);
    if (intent.status === "SESSION_CREATED" && typeof intent.checkoutUrl === "string") {
      return organizerBillingJson({ canonical: {
        confirmedRevision: intent.confirmedRevision,
        expiresAt: intent.expiresAt,
        replayed: true,
        status: intent.status,
        url: intent.checkoutUrl,
      } });
    }
    const stripe = organizerStripeClient(mode);
    let customerId = typeof intent.stripeCustomerId === "string" ? intent.stripeCustomerId : "";
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email ?? undefined,
        metadata: {
          billingAccountId: String(intent.billingAccountId),
          organizerId: input.organizerId,
          organizerKind: input.organizerKind,
          source: "pachangas_iq_organizer_v1",
        },
      }, { idempotencyKey: `${input.operationId}:customer` });
      customerId = customer.id;
    }
    const urls = checkoutReturnUrls(request, input);
    const session = await stripe.checkout.sessions.create({
      allow_promotion_codes: true,
      billing_address_collection: "required",
      cancel_url: urls.cancel,
      customer: customerId,
      customer_update: { address: "auto", name: "auto" },
      line_items: [{ price: String(intent.stripePriceId), quantity: 1 }],
      metadata: {
        billingAccountId: String(intent.billingAccountId),
        operationId: input.operationId,
        organizerId: input.organizerId,
        organizerKind: input.organizerKind,
        planCode: input.planCode,
      },
      mode: "subscription",
      subscription_data: {
        metadata: {
          billingAccountId: String(intent.billingAccountId),
          operationId: input.operationId,
          organizerId: input.organizerId,
          organizerKind: input.organizerKind,
          planCode: input.planCode,
        },
      },
      success_url: urls.success,
      tax_id_collection: { enabled: true },
    }, { idempotencyKey: `${input.operationId}:checkout` });
    if (!session.url) throw new Error("BILLING_CHECKOUT_URL_MISSING");
    const confirmed = await service.rpc("confirm_pachanga_organizer_checkout_service_v1", {
      checkout_url: session.url,
      expires_at: session.expires_at ? new Date(session.expires_at * 1000).toISOString() : null,
      operation_id: input.operationId,
      stripe_checkout_session_id: session.id,
      stripe_customer_id: customerId,
    });
    if (confirmed.error) throw new Error(confirmed.error.message);
    const canonical = organizerBillingRecord(confirmed.data);
    return organizerBillingJson({ canonical: {
      confirmedRevision: canonical.confirmedRevision,
      expiresAt: canonical.expiresAt,
      replayed: false,
      status: canonical.status,
      url: canonical.checkoutUrl,
    } });
  } catch (error) {
    return organizerBillingError(error);
  }
}

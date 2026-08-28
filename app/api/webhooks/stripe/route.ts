import Stripe from "stripe";
import {
  billingServiceClient,
  newDeliveryOperationId,
  normalizeOrganizerStripeEvent,
  organizerBillingJson,
  organizerBillingMode,
  organizerBillingRecord,
  organizerWebhookSecrets,
  recordRejectedStripeDelivery,
  requestIdFrom,
  stripeEventChecksum,
  stripeEventCreatedAt,
  stripeEventMode,
} from "../../billing/organizer/_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;
export const runtime = "nodejs";

export async function POST(request: Request) {
  const signature = request.headers.get("stripe-signature") ?? "";
  const requestId = requestIdFrom(request);
  const endpointHint = new URL(request.url).searchParams.get("mode");
  const fallbackMode = endpointHint === "test" || endpointHint === "live" ? endpointHint : organizerBillingMode();
  const rawBody = await request.text();
  if (!signature) {
    await recordRejectedStripeDelivery(fallbackMode, "REJECTED_SIGNATURE", 400, requestId).catch(() => undefined);
    return organizerBillingJson({ received: false }, 400);
  }

  let event: Stripe.Event | null = null;
  let verifiedMode: "live" | "test" | null = null;
  let modeMismatch = false;
  for (const candidate of organizerWebhookSecrets()) {
    try {
      const verified = Stripe.webhooks.constructEvent(rawBody, signature, candidate.secret);
      if (stripeEventMode(verified) !== candidate.mode) {
        modeMismatch = true;
        continue;
      }
      event = verified;
      verifiedMode = candidate.mode;
      break;
    } catch {
      // Each endpoint secret is attempted independently; no verifier details leave the server.
    }
  }
  if (!event || !verifiedMode) {
    await recordRejectedStripeDelivery(
      fallbackMode,
      modeMismatch ? "REJECTED_MODE" : "REJECTED_SIGNATURE",
      400,
      requestId,
    ).catch(() => undefined);
    return organizerBillingJson({ received: false }, 400);
  }

  try {
    const result = await billingServiceClient().rpc("ingest_pachanga_stripe_event_v1", {
      api_version: event.api_version ?? "",
      delivery_operation_id: newDeliveryOperationId(),
      event_type: event.type,
      normalized_payload: normalizeOrganizerStripeEvent(event),
      payload_checksum: stripeEventChecksum(rawBody),
      request_id: requestId,
      stripe_created_at: stripeEventCreatedAt(event),
      stripe_event_id: event.id,
      stripe_mode: verifiedMode,
    });
    if (result.error) throw new Error(result.error.message);
    const canonical = organizerBillingRecord(result.data);
    return organizerBillingJson({
      duplicate: canonical.duplicate === true,
      received: canonical.accepted === true,
      status: canonical.status,
    });
  } catch {
    await recordRejectedStripeDelivery(verifiedMode, "FAILED_SAFE", 500, requestId).catch(() => undefined);
    return organizerBillingJson({ received: false }, 500);
  }
}

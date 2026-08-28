import {
  billingServiceClient,
  normalizeOrganizerStripeSubscription,
  organizerBillingRecord,
  organizerStripeClient,
  organizerSubscriptionDifferenceCodes,
  type OrganizerBillingMode,
} from "../../../billing/organizer/_shared";
import { noStoreHeaders } from "../../../client-policy/_contract";

export const dynamic = "force-dynamic";
export const maxDuration = 60;
export const runtime = "nodejs";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function safeFailure(error: unknown) {
  const detail = error instanceof Error ? error.message : "";
  if (/STALE_REVISION|PT409/i.test(detail)) {
    return { code: "STALE_REVISION", difference: "PROJECTION_CHANGED_AFTER_CLAIM" };
  }
  if (/NO SUCH SUBSCRIPTION|RESOURCE_MISSING|SUBSCRIPTION_NOT_FOUND/i.test(detail)) {
    return { code: "STRIPE_SUBSCRIPTION_NOT_FOUND", difference: "REMOTE_SUBSCRIPTION_NOT_FOUND" };
  }
  if (/CUSTOMER_MISMATCH/i.test(detail)) {
    return { code: "STRIPE_CUSTOMER_MISMATCH", difference: "CUSTOMER_ID_MISMATCH" };
  }
  if (/SUBSCRIPTION_AMBIGUOUS/i.test(detail)) {
    return { code: "STRIPE_SUBSCRIPTION_AMBIGUOUS", difference: "REMOTE_SUBSCRIPTION_AMBIGUOUS" };
  }
  return { code: "STRIPE_RECONCILIATION_FAILED", difference: "REMOTE_READ_FAILED" };
}

function integer(value: unknown) {
  const result = Number(value);
  return Number.isSafeInteger(result) && result >= 0 ? result : -1;
}

function stringValue(value: unknown, maximum = 255) {
  return typeof value === "string" && value.trim().length <= maximum ? value.trim() : "";
}

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET?.trim();
  if (!secret) return Response.json({ error: "BILLING_RECONCILIATION_NOT_CONFIGURED" }, { headers: noStoreHeaders, status: 503 });
  if (request.headers.get("authorization") !== `Bearer ${secret}`) {
    return Response.json({ error: "BILLING_RECONCILIATION_FORBIDDEN" }, { headers: noStoreHeaders, status: 403 });
  }

  const service = billingServiceClient();
  const expiration = await service.rpc("process_pachanga_billing_expirations_service_v1", {
    batch_size: 100,
    operation_id: crypto.randomUUID(),
  });
  if (expiration.error) {
    return Response.json({ error: "BILLING_EXPIRATION_FAILED" }, { headers: noStoreHeaders, status: 500 });
  }
  const claimed = await service.rpc("claim_pachanga_billing_reconciliation_service_v1", {
    batch_size: 20,
    operation_id: crypto.randomUUID(),
  });
  if (claimed.error) {
    return Response.json({ error: "BILLING_RECONCILIATION_CLAIM_FAILED" }, { headers: noStoreHeaders, status: 500 });
  }
  const claim = organizerBillingRecord(claimed.data);
  const items = Array.isArray(claim.items) ? claim.items : [];
  const outcomes: string[] = [];

  for (const rawItem of items) {
    const item = organizerBillingRecord(rawItem);
    const reconciliationId = stringValue(item.id, 36);
    const billingAccountId = stringValue(item.billingAccountId, 36);
    const mode = stringValue(item.mode, 8) as OrganizerBillingMode;
    const customerId = stringValue(item.customerId);
    const claimedSubscriptionId = stringValue(item.subscriptionId);
    const reconciliationRevision = integer(item.revision);
    const projectionRevision = integer(item.localProjectionRevision);
    if (!uuidPattern.test(reconciliationId) || !uuidPattern.test(billingAccountId)
        || !["live", "test"].includes(mode) || !/^cus_[A-Za-z0-9_]+$/.test(customerId)
        || reconciliationRevision < 1 || projectionRevision < 0) {
      outcomes.push("INVALID_CLAIM");
      continue;
    }

    try {
      const stripe = organizerStripeClient(mode);
      const observedAt = new Date().toISOString();
      let subscription;
      if (/^sub_[A-Za-z0-9_]+$/.test(claimedSubscriptionId)) {
        subscription = await stripe.subscriptions.retrieve(claimedSubscriptionId, {
          expand: ["items.data.price"],
        });
      } else {
        const candidates = await stripe.subscriptions.list({
          customer: customerId,
          limit: 10,
          status: "all",
          expand: ["data.items.data.price"],
        });
        const matching = candidates.data.filter((candidate) =>
          candidate.metadata.billingAccountId === billingAccountId
          && !["canceled", "incomplete_expired"].includes(candidate.status));
        if (matching.length !== 1) throw new Error("BILLING_STRIPE_SUBSCRIPTION_AMBIGUOUS");
        subscription = matching[0];
      }
      const snapshot = normalizeOrganizerStripeSubscription(subscription);
      if (snapshot.customerId !== customerId) throw new Error("BILLING_STRIPE_CUSTOMER_MISMATCH");
      const differences = organizerSubscriptionDifferenceCodes(item, snapshot);
      if (differences.length === 0) {
        const completed = await service.rpc("complete_pachanga_billing_reconciliation_service_v1", {
          difference_codes: [],
          expected_revision: reconciliationRevision,
          operation_id: crypto.randomUUID(),
          outcome: "HEALTHY",
          reconciliation_id: reconciliationId,
          safe_error_code: null,
        });
        if (completed.error) throw new Error(completed.error.message);
        outcomes.push("HEALTHY");
        continue;
      }
      const repaired = await service.rpc("apply_pachanga_billing_reconciliation_snapshot_service_v1", {
        billing_interval: snapshot.billingInterval,
        cancel_at_period_end: snapshot.cancelAtPeriodEnd,
        canceled_at: snapshot.canceledAt,
        current_period_end: snapshot.currentPeriodEnd,
        current_period_start: snapshot.currentPeriodStart,
        difference_codes: differences,
        expected_projection_revision: projectionRevision,
        expected_revision: reconciliationRevision,
        observed_at: observedAt,
        operation_id: crypto.randomUUID(),
        reconciliation_id: reconciliationId,
        stripe_customer_id: snapshot.customerId,
        stripe_price_id: snapshot.priceId,
        stripe_subscription_id: snapshot.subscriptionId,
        subscription_status: snapshot.subscriptionStatus,
      });
      if (repaired.error) throw new Error(repaired.error.message);
      const result = organizerBillingRecord(repaired.data);
      outcomes.push(result.applied === false ? "STALE_OBSERVATION_IGNORED" : "REPAIRED");
    } catch (error) {
      const failure = safeFailure(error);
      const completed = await service.rpc("complete_pachanga_billing_reconciliation_service_v1", {
        difference_codes: [failure.difference],
        expected_revision: reconciliationRevision,
        operation_id: crypto.randomUUID(),
        outcome: "FAILED",
        reconciliation_id: reconciliationId,
        safe_error_code: failure.code,
      });
      outcomes.push(completed.error ? "CONCURRENT_COMPLETION" : "FAILED_SAFE");
    }
  }

  return Response.json({
    claimed: items.length,
    expirationProcessed: true,
    outcomes: outcomes.reduce<Record<string, number>>((counts, outcome) => {
      counts[outcome] = (counts[outcome] ?? 0) + 1;
      return counts;
    }, {}),
  }, { headers: noStoreHeaders });
}

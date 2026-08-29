import "server-only";

import { createHash, randomUUID } from "node:crypto";
import Stripe from "stripe";
import { authedSupabaseClient, getOrigin, serviceSupabaseClient } from "../_shared";
import { clientWriteGateResponse, noStoreHeaders } from "../../client-policy/_contract";

export type OrganizerBillingMode = "live" | "test";
export type OrganizerKind = "CLUB" | "TEAM";
export type OrganizerBillingInterval = "month" | "year";

export const organizerBillingUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type JsonRecord = Record<string, unknown>;

function requiredEnvironment(name: string) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function optionalEnvironment(name: string) {
  return process.env[name]?.trim() || "";
}

export function organizerBillingRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function boundedText(value: unknown, maximum: number) {
  return typeof value === "string" && value.trim().length <= maximum ? value.trim() : "";
}

function identifier(value: unknown) {
  if (typeof value === "string") return value;
  return boundedText(organizerBillingRecord(value).id, 255);
}

function unixTimestamp(value: unknown) {
  const seconds = typeof value === "number" && Number.isFinite(value) ? value : 0;
  return seconds > 0 ? new Date(seconds * 1000).toISOString() : null;
}

function stripNullish(source: JsonRecord) {
  return Object.fromEntries(Object.entries(source).filter(([, value]) => value !== null && value !== undefined && value !== ""));
}

export function organizerBillingJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

export function requireOrganizerBillingOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("BILLING_ORIGIN_REQUIRED");
}

export function organizerBillingWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function organizerBillingClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    displayMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    sessionId: request.headers.get("x-pachangas-write-id"),
    surface,
  };
}

export function organizerBillingMode(): OrganizerBillingMode {
  const configured = optionalEnvironment("PACHANGAS_ORGANIZER_STRIPE_MODE").toLowerCase();
  if (configured === "live" || configured === "test") return configured;
  return process.env.VERCEL_ENV === "production" ? "live" : "test";
}

function stripeKeyForMode(mode: OrganizerBillingMode) {
  const dedicated = optionalEnvironment(mode === "live" ? "STRIPE_LIVE_SECRET_KEY" : "STRIPE_TEST_SECRET_KEY");
  const fallback = optionalEnvironment("STRIPE_SECRET_KEY");
  const value = dedicated || fallback;
  const expectedPrefixes = mode === "live" ? ["sk_live_"] : ["sk_test_", "rk_test_"];
  if (!expectedPrefixes.some((prefix) => value.startsWith(prefix))) {
    throw new Error(`BILLING_STRIPE_${mode.toUpperCase()}_NOT_CONFIGURED`);
  }
  return value;
}

export function organizerStripeClient(mode: OrganizerBillingMode) {
  return new Stripe(stripeKeyForMode(mode));
}

export function organizerWebhookSecrets() {
  const generic = optionalEnvironment("STRIPE_WEBHOOK_SECRET");
  const live = optionalEnvironment("STRIPE_LIVE_WEBHOOK_SECRET") || generic;
  const test = optionalEnvironment("STRIPE_TEST_WEBHOOK_SECRET");
  return [
    ...(live.startsWith("whsec_") ? [{ mode: "live" as const, secret: live }] : []),
    ...(test.startsWith("whsec_") ? [{ mode: "test" as const, secret: test }] : []),
  ];
}

export async function organizerBillingSession(request: Request) {
  return authedSupabaseClient(request);
}

export function parseCheckoutInput(value: unknown) {
  const body = organizerBillingRecord(value);
  const allowed = new Set(["billingInterval", "expectedRevision", "operationId", "organizerId", "organizerKind", "planCode"]);
  if (Object.keys(body).some((key) => !allowed.has(key))) throw new Error("BILLING_CHECKOUT_PAYLOAD_REJECTED");
  const operationId = boundedText(body.operationId, 36);
  const organizerId = boundedText(body.organizerId, 36);
  const organizerKind = boundedText(body.organizerKind, 8).toUpperCase();
  const planCode = boundedText(body.planCode, 64).toUpperCase();
  const billingInterval = boundedText(body.billingInterval, 8).toLowerCase();
  const expectedRevision = Number(body.expectedRevision);
  if (!organizerBillingUuidPattern.test(operationId) || !organizerBillingUuidPattern.test(organizerId)
      || !["CLUB", "TEAM"].includes(organizerKind) || !/^[A-Z][A-Z0-9_]{2,63}$/.test(planCode)
      || !["month", "year"].includes(billingInterval) || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
    throw new Error("BILLING_CHECKOUT_PAYLOAD_REJECTED");
  }
  return {
    billingInterval: billingInterval as OrganizerBillingInterval,
    expectedRevision,
    operationId,
    organizerId,
    organizerKind: organizerKind as OrganizerKind,
    planCode,
  };
}

export function parsePortalInput(value: unknown) {
  const body = organizerBillingRecord(value);
  const allowed = new Set(["expectedRevision", "operationId", "organizerId", "organizerKind"]);
  if (Object.keys(body).some((key) => !allowed.has(key))) throw new Error("BILLING_PORTAL_PAYLOAD_REJECTED");
  const operationId = boundedText(body.operationId, 36);
  const organizerId = boundedText(body.organizerId, 36);
  const organizerKind = boundedText(body.organizerKind, 8).toUpperCase();
  const expectedRevision = Number(body.expectedRevision);
  if (!organizerBillingUuidPattern.test(operationId) || !organizerBillingUuidPattern.test(organizerId)
      || !["CLUB", "TEAM"].includes(organizerKind) || !Number.isSafeInteger(expectedRevision) || expectedRevision < 1) {
    throw new Error("BILLING_PORTAL_PAYLOAD_REJECTED");
  }
  return { expectedRevision, operationId, organizerId, organizerKind: organizerKind as OrganizerKind };
}

export function checkoutReturnUrls(request: Request, input: ReturnType<typeof parseCheckoutInput>) {
  const query = new URLSearchParams({
    checkout: input.operationId,
    organizerId: input.organizerId,
    organizerKind: input.organizerKind,
  });
  const base = getOrigin(request);
  return {
    cancel: `${base}/ajustes/facturacion?${query.toString()}&checkoutStatus=cancelled`,
    success: `${base}/ajustes/facturacion?${query.toString()}&checkoutStatus=confirming`,
  };
}

export function portalReturnUrl(request: Request, input: ReturnType<typeof parsePortalInput>) {
  const query = new URLSearchParams({ organizerId: input.organizerId, organizerKind: input.organizerKind });
  return `${getOrigin(request)}/ajustes/facturacion?${query.toString()}`;
}

export function stripeEventChecksum(rawBody: string) {
  return createHash("sha256").update(rawBody, "utf8").digest("hex");
}

export function normalizeOrganizerStripeEvent(event: Stripe.Event) {
  const object = organizerBillingRecord(event.data.object);
  const objectType = boundedText(object.object, 80);
  const metadata = organizerBillingRecord(object.metadata);
  const customer = identifier(object.customer) || (objectType === "customer" ? boundedText(object.id, 255) : "");
  const subscriptionObject = objectType === "subscription" ? object : organizerBillingRecord(object.subscription);
  const parent = organizerBillingRecord(object.parent);
  const parentSubscription = organizerBillingRecord(parent.subscription_details);
  const subscriptionId = identifier(object.subscription)
    || identifier(parentSubscription.subscription)
    || (objectType === "subscription" ? boundedText(object.id, 255) : "");
  const items = organizerBillingRecord(object.items);
  const firstItem = Array.isArray(items.data) ? organizerBillingRecord(items.data[0]) : {};
  const price = organizerBillingRecord(firstItem.price);
  const recurring = organizerBillingRecord(price.recurring);
  const statusTransitions = organizerBillingRecord(object.status_transitions);
  const lastError = organizerBillingRecord(object.last_finalization_error);
  const address = organizerBillingRecord(object.address);
  const tax = organizerBillingRecord(object.tax);
  const normalized = stripNullish({
    amountDue: typeof object.amount_due === "number" ? Math.trunc(object.amount_due) : null,
    amountPaid: typeof object.amount_paid === "number" ? Math.trunc(object.amount_paid) : null,
    billingCountry: boundedText(address.country, 2).toUpperCase(),
    billingInterval: boundedText(recurring.interval, 8).toLowerCase(),
    cancelAtPeriodEnd: typeof object.cancel_at_period_end === "boolean" ? object.cancel_at_period_end : null,
    canceledAt: unixTimestamp(object.canceled_at),
    checkoutSessionId: objectType === "checkout.session" ? boundedText(object.id, 255) : "",
    checkoutStatus: objectType === "checkout.session" ? boundedText(object.status, 40) : "",
    currency: boundedText(object.currency, 3).toLowerCase(),
    currentPeriodEnd: unixTimestamp(object.current_period_end ?? firstItem.current_period_end),
    currentPeriodStart: unixTimestamp(object.current_period_start ?? firstItem.current_period_start),
    customerId: customer,
    dueAt: unixTimestamp(object.due_date),
    failureCode: boundedText(lastError.code, 120) || boundedText(lastError.type, 120),
    hostedInvoiceUrl: boundedText(object.hosted_invoice_url, 2048),
    invoiceId: objectType === "invoice" ? boundedText(object.id, 255) : "",
    invoicePdfUrl: boundedText(object.invoice_pdf, 2048),
    invoiceStatus: objectType === "invoice" ? boundedText(object.status, 40).toLowerCase() : "",
    locale: Array.isArray(object.preferred_locales) ? boundedText(object.preferred_locales[0], 20) : "",
    metadataOperationId: boundedText(metadata.operationId, 36),
    objectId: boundedText(object.id, 255),
    objectType,
    paidAt: unixTimestamp(statusTransitions.paid_at),
    priceId: boundedText(price.id, 255),
    subscriptionId,
    subscriptionStatus: objectType === "subscription" ? boundedText(subscriptionObject.status, 40).toLowerCase() : "",
    taxConfigurationStatus: boundedText(tax.exempt, 40).toUpperCase(),
  });
  return normalized;
}

export type OrganizerStripeSubscriptionSnapshot = {
  billingInterval: OrganizerBillingInterval;
  cancelAtPeriodEnd: boolean;
  canceledAt: string | null;
  currentPeriodEnd: string;
  currentPeriodStart: string;
  customerId: string;
  priceId: string;
  subscriptionId: string;
  subscriptionStatus: Stripe.Subscription.Status;
};

export function normalizeOrganizerStripeSubscription(subscription: Stripe.Subscription): OrganizerStripeSubscriptionSnapshot {
  const item = subscription.items.data[0];
  const customerId = identifier(subscription.customer);
  const priceId = item?.price.id?.trim() || "";
  const billingInterval = item?.price.recurring?.interval;
  if (!/^cus_[A-Za-z0-9_]+$/.test(customerId)
      || !/^sub_[A-Za-z0-9_]+$/.test(subscription.id)
      || !/^price_[A-Za-z0-9_]+$/.test(priceId)
      || (billingInterval !== "month" && billingInterval !== "year")
      || !item?.current_period_start || !item.current_period_end) {
    throw new Error("BILLING_STRIPE_SUBSCRIPTION_INCOMPLETE");
  }
  return {
    billingInterval,
    cancelAtPeriodEnd: subscription.cancel_at_period_end,
    canceledAt: unixTimestamp(subscription.canceled_at),
    currentPeriodEnd: new Date(item.current_period_end * 1000).toISOString(),
    currentPeriodStart: new Date(item.current_period_start * 1000).toISOString(),
    customerId,
    priceId,
    subscriptionId: subscription.id,
    subscriptionStatus: subscription.status,
  };
}

function timestampsEqual(left: unknown, right: string | null) {
  if ((left === null || left === undefined || left === "") && right === null) return true;
  if (typeof left !== "string" || !right) return false;
  const leftTime = Date.parse(left);
  const rightTime = Date.parse(right);
  return Number.isFinite(leftTime) && leftTime === rightTime;
}

export function organizerSubscriptionDifferenceCodes(
  localValue: unknown,
  snapshot: OrganizerStripeSubscriptionSnapshot,
) {
  const local = organizerBillingRecord(localValue);
  const differences = new Set<string>();
  if (boundedText(local.subscriptionId, 255) !== snapshot.subscriptionId) differences.add("SUBSCRIPTION_ID_MISMATCH");
  if (boundedText(local.customerId, 255) !== snapshot.customerId) differences.add("CUSTOMER_ID_MISMATCH");
  if (boundedText(local.localPriceId, 255) !== snapshot.priceId) differences.add("PRICE_MISMATCH");
  if (boundedText(local.localSubscriptionStatus, 40).toLowerCase() !== snapshot.subscriptionStatus) differences.add("STATUS_MISMATCH");
  if (boundedText(local.localBillingInterval, 8).toLowerCase() !== snapshot.billingInterval) differences.add("INTERVAL_MISMATCH");
  if (!timestampsEqual(local.localCurrentPeriodStart, snapshot.currentPeriodStart)) differences.add("PERIOD_START_MISMATCH");
  if (!timestampsEqual(local.localCurrentPeriodEnd, snapshot.currentPeriodEnd)) differences.add("PERIOD_END_MISMATCH");
  if (Boolean(local.localCancelAtPeriodEnd) !== snapshot.cancelAtPeriodEnd) differences.add("CANCEL_AT_PERIOD_END_MISMATCH");
  if (!timestampsEqual(local.localCanceledAt, snapshot.canceledAt)) differences.add("CANCELED_AT_MISMATCH");
  return [...differences].sort();
}

export function stripeEventMode(event: Stripe.Event): OrganizerBillingMode {
  return event.livemode ? "live" : "test";
}

export function stripeEventCreatedAt(event: Stripe.Event) {
  return new Date(event.created * 1000).toISOString();
}

export function newDeliveryOperationId() {
  return randomUUID();
}

export function organizerBillingError(error: unknown) {
  const detail = error instanceof Error ? error.message : "BILLING_REQUEST_FAILED";
  const status = /AUTHENTICATION|INVALID SESSION/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|REUSED/i.test(detail) ? 409
      : /OWNER_REQUIRED|ORIGIN_REQUIRED|42501|PERMISSION/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /DISABLED|NOT_AVAILABLE|NOT_APPROVED|0A000/i.test(detail) ? 422
            : 400;
  const code = /CHECKOUT_LIVE_DISABLED|PRICE_NOT_APPROVED|LIVE.*NOT_CONFIGURED/i.test(detail)
    ? "BILLING_AWAITING_PRICE_APPROVAL"
    : /SANDBOX_DISABLED|TEST.*NOT_CONFIGURED/i.test(detail)
      ? "BILLING_SANDBOX_NOT_AVAILABLE"
      : /STALE_REVISION|PT409/i.test(detail)
        ? "BILLING_STALE_REVISION"
        : /OWNER_REQUIRED|42501/i.test(detail)
          ? "BILLING_OWNER_REQUIRED"
          : "BILLING_REQUEST_REJECTED";
  return organizerBillingJson({ error: code }, status);
}

export async function recordRejectedStripeDelivery(
  endpointMode: OrganizerBillingMode,
  deliveryStatus: "FAILED_SAFE" | "REJECTED_MODE" | "REJECTED_SIGNATURE",
  httpResult: number,
  requestId: string,
) {
  const service = serviceSupabaseClient();
  await service.rpc("record_pachanga_stripe_delivery_rejection_service_v1", {
    delivery_status: deliveryStatus,
    endpoint_mode: endpointMode,
    http_result: httpResult,
    operation_id: newDeliveryOperationId(),
    request_id: requestId,
  });
}

export function requestIdFrom(request: Request) {
  return boundedText(request.headers.get("x-vercel-id") || request.headers.get("x-request-id"), 160) || newDeliveryOperationId();
}

export function billingServiceClient() {
  requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
  return serviceSupabaseClient();
}

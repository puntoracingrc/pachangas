import {
  platformErrorResponse,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../admin/_lib/platform-auth";
import { getStripeHealth } from "../../../admin/_lib/platform-external";
import { clientWriteGateResponse } from "../../client-policy/_contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const flagKeys = new Set([
  "billing_accounts_enabled", "demo_world_v28_enabled", "foundation_enabled",
  "live_checkout_enabled", "live_prices_approved", "organizer_ui_enabled",
  "partner_grants_enabled", "plan_catalog_enabled", "portal_enabled",
  "reconciliation_enabled", "stripe_sandbox_enabled", "webhook_ingest_enabled",
]);
const taxHealthStates = new Set(["BLOCKED", "LIVE_READY", "LIVE_REVIEW_REQUIRED", "SANDBOX_READY", "UNCONFIGURED"]);
const manualPlans = new Set(["CLUB_PARTNER", "PRIVATE_BETA", "PLATFORM_GRANT", "PROMOTION"]);

function record(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function text(value: unknown, maximum = 1200) {
  return typeof value === "string" && value.trim().length <= maximum ? value.trim() : "";
}

function reason(value: unknown) {
  const result = text(value, 1200);
  if (result.length < 3) throw new Error("Invalid billing reason");
  return result;
}

function optionalTimestamp(value: unknown) {
  const result = text(value, 40);
  if (!result) return "";
  if (Number.isNaN(Date.parse(result))) throw new Error("Invalid billing timestamp");
  return new Date(result).toISOString();
}

function commandPayload(action: string, value: unknown) {
  const input = record(value);
  const why = reason(input.reason);
  if (action === "settings.flag") {
    const flagKey = text(input.flagKey, 80).toLowerCase();
    if (!flagKeys.has(flagKey) || typeof input.enabled !== "boolean") throw new Error("Invalid billing flag");
    return { enabled: input.enabled, flagKey, reason: why };
  }
  if (action === "settings.tax_health") {
    const taxHealth = text(input.taxHealth, 40).toUpperCase();
    if (!taxHealthStates.has(taxHealth)) throw new Error("Invalid billing tax health");
    return { reason: why, taxHealth };
  }
  if (action === "price_mapping.upsert") {
    const planCode = text(input.planCode, 64).toUpperCase();
    const stripeMode = text(input.stripeMode, 8).toLowerCase();
    const billingInterval = text(input.billingInterval, 8).toLowerCase();
    const stripeProductId = text(input.stripeProductId, 255);
    const stripePriceId = text(input.stripePriceId, 255);
    const currency = text(input.currency, 3).toLowerCase();
    const taxBehavior = text(input.taxBehavior, 16).toLowerCase();
    const unitAmount = input.unitAmount === "" || input.unitAmount == null ? "" : Number(input.unitAmount);
    if (!/^(CLUB_ORGANIZER|TEAM_ORGANIZER_PRO)$/.test(planCode)
        || !["test", "live"].includes(stripeMode) || !["month", "year"].includes(billingInterval)
        || !/^prod_[A-Za-z0-9_]+$/.test(stripeProductId) || !/^price_[A-Za-z0-9_]+$/.test(stripePriceId)
        || !/^[a-z]{3}$/.test(currency) || !["exclusive", "inclusive", "unspecified"].includes(taxBehavior)
        || (unitAmount !== "" && (!Number.isSafeInteger(unitAmount) || Number(unitAmount) < 0))
        || typeof input.approved !== "boolean") throw new Error("Invalid billing Price mapping");
    return { approved: input.approved, billingInterval, currency, planCode, reason: why,
      stripeMode, stripePriceId, stripeProductId, taxBehavior, unitAmount };
  }
  if (action === "manual.grant") {
    const organizerKind = text(input.organizerKind, 8).toUpperCase();
    const planCode = text(input.planCode, 64).toUpperCase();
    if (!["CLUB", "TEAM"].includes(organizerKind) || !manualPlans.has(planCode)
        || (planCode === "CLUB_PARTNER" && organizerKind !== "CLUB")) throw new Error("Invalid manual organizer grant");
    return { expiresAt: optionalTimestamp(input.expiresAt), organizerKind, planCode,
      reason: why, validFrom: optionalTimestamp(input.validFrom) };
  }
  if (action === "manual.revoke") return { reason: why };
  if (action === "manual.renew") return { expiresAt: optionalTimestamp(input.expiresAt), reason: why };
  throw new Error("Invalid billing command");
}

function clientMetadata(request: Request) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    displayMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    sessionId: request.headers.get("x-pachangas-write-id"),
    surface: "platform_billing_control_center_v2",
  };
}

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "billing.read");
    const params = new URL(request.url).searchParams;
    const page = Math.max(1, Number.parseInt(params.get("page") ?? "1", 10) || 1);
    const pageSize = Math.min(100, Math.max(1, Number.parseInt(params.get("pageSize") ?? "50", 10) || 50));
    const force = params.get("refresh") === "1";
    const [canonical, stripe] = await Promise.all([
      session.client.rpc("get_pachanga_platform_organizer_billing_v2", {
        page_offset: (page - 1) * pageSize,
        page_size: pageSize,
      }),
      getStripeHealth(force),
    ]);
    if (canonical.error) throw new Error(canonical.error.message);
    return platformJson({ canonical: canonical.data, stripe });
  } catch (error) {
    return platformErrorResponse(error);
  }
}

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const gated = clientWriteGateResponse(request);
    if (gated) return gated;
    const session = await requirePlatformRequest(request, "billing.write");
    const body = record(await request.json());
    const operationId = text(body.operationId, 36);
    const aggregateId = text(body.aggregateId, 36);
    const action = text(body.action, 64).toLowerCase();
    const expectedRevision = Number(body.expectedRevision);
    if (!uuidPattern.test(operationId) || !uuidPattern.test(aggregateId)
        || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) throw new Error("Invalid billing envelope");
    const result = await session.client.rpc("command_pachanga_organizer_billing_platform_v1", {
      aggregate_id: aggregateId,
      client_metadata: clientMetadata(request),
      command_action: action,
      command_payload: commandPayload(action, body.payload),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}

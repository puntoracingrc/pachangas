import {
  platformErrorResponse,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../admin/_lib/platform-auth";
import {
  ensureOrganizerStripePortal,
  getOrganizerStripeCommercialHealth,
  parseOrganizerCatalogIntent,
  provisionOrganizerStripeCatalog,
} from "../../billing/organizer/_stripe-commercial";
import { billingServiceClient } from "../../billing/organizer/_shared";
import { clientWriteGateResponse } from "../../client-policy/_contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;
export const runtime = "nodejs";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const legacyFlagKeys = new Set([
  "billing_accounts_enabled", "demo_world_v28_enabled", "foundation_enabled",
  "organizer_ui_enabled", "partner_grants_enabled", "plan_catalog_enabled",
  "reconciliation_enabled", "stripe_sandbox_enabled", "webhook_ingest_enabled",
]);
const commercialFlagKeys = new Set([
  "commercial_decision_workflow_enabled", "demo_world_v29_enabled",
  "organizer_pricing_ui_enabled", "stripe_test_checkout_enabled",
  "stripe_test_portal_enabled",
]);
const taxHealthStates = new Set([
  "BLOCKED", "COMMERCIAL_DECISION_PENDING", "LIVE_READY", "TAX_REVIEW_REQUIRED",
  "TEST_READY", "UNCONFIGURED",
]);
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

function exactText(value: unknown, maximum: number, label: string) {
  const result = text(value, maximum);
  if (!result) throw new Error(`Invalid billing ${label}`);
  return result;
}

function nonNegativeInteger(value: unknown, label: string) {
  const result = Number(value);
  if (!Number.isSafeInteger(result) || result < 0) throw new Error(`Invalid billing ${label}`);
  return result;
}

function optionalTimestamp(value: unknown) {
  const result = text(value, 40);
  if (!result) return "";
  if (Number.isNaN(Date.parse(result))) throw new Error("Invalid billing timestamp");
  return new Date(result).toISOString();
}

function mode(value: unknown) {
  const result = text(value, 8).toLowerCase();
  if (result !== "test" && result !== "live") throw new Error("Invalid billing Stripe mode");
  return result;
}

function decisionPayload(action: string, value: unknown) {
  const input = record(value);
  const why = reason(input.reason);
  if (action === "commercial_decision.submit" || action === "commercial_decision.withdraw") return { reason: why };
  const currency = exactText(input.currency, 3, "currency").toUpperCase();
  const monthlyAmountMinor = nonNegativeInteger(input.monthlyAmountMinor, "monthly amount");
  const annualAmountMinor = nonNegativeInteger(input.annualAmountMinor, "annual amount");
  const taxDisplayMode = exactText(input.taxDisplayMode, 40, "tax display").toUpperCase();
  const stripeTaxBehavior = exactText(input.stripeTaxBehavior, 16, "tax behavior").toLowerCase();
  const effectiveFrom = optionalTimestamp(input.effectiveFrom);
  const termsRevision = exactText(input.termsRevision, 120, "terms revision");
  const privacyRevision = exactText(input.privacyRevision, 120, "privacy revision");
  if (!/^[A-Z]{3}$/.test(currency)
      || !["PENDING_REVIEW", "TAX_EXCLUDED", "TAX_INCLUDED"].includes(taxDisplayMode)
      || !["exclusive", "inclusive", "unspecified"].includes(stripeTaxBehavior)) {
    throw new Error("Invalid billing commercial decision");
  }
  const common = {
    annualAmountMinor,
    currency,
    effectiveFrom,
    monthlyAmountMinor,
    privacyRevision,
    reason: why,
    stripeTaxBehavior,
    taxDisplayMode,
    termsRevision,
  };
  if (action === "commercial_decision.approve") {
    if (input.confirmLivePricing !== "CONFIRM_STRIPE_LIVE_PRICING") {
      throw new Error("Invalid billing live pricing confirmation");
    }
    return { ...common, billingIntervals: ["month", "year"], confirmLivePricing: input.confirmLivePricing };
  }
  if (action !== "commercial_decision.update") throw new Error("Invalid billing commercial action");
  return {
    ...common,
    publicCopyRevision: exactText(input.publicCopyRevision, 120, "public copy revision"),
    trialDays: nonNegativeInteger(input.trialDays, "trial days"),
  };
}

function commercialSettingsPayload(action: string, value: unknown) {
  const input = record(value);
  const why = reason(input.reason);
  if (action === "settings.feature_flag_v2") {
    const flagKey = text(input.flagKey, 80).toLowerCase();
    if (!commercialFlagKeys.has(flagKey) || typeof input.enabled !== "boolean") {
      throw new Error("Invalid billing commercial flag");
    }
    return { enabled: input.enabled, flagKey, reason: why };
  }
  if (action === "settings.tax_health_v2") {
    const taxHealth = text(input.taxHealth, 40).toUpperCase();
    if (!taxHealthStates.has(taxHealth) || input.confirmation !== "CONFIRM_ORGANIZER_TAX_HEALTH") {
      throw new Error("Invalid billing tax health");
    }
    return {
      confirmation: input.confirmation,
      privacyRevision: text(input.privacyRevision, 120),
      reason: why,
      taxHealth,
      termsRevision: text(input.termsRevision, 120),
    };
  }
  throw new Error("Invalid billing commercial settings action");
}

function legacyCommandPayload(action: string, value: unknown) {
  const input = record(value);
  const why = reason(input.reason);
  if (action === "settings.flag") {
    const flagKey = text(input.flagKey, 80).toLowerCase();
    if (!legacyFlagKeys.has(flagKey) || typeof input.enabled !== "boolean") throw new Error("Invalid billing flag");
    return { enabled: input.enabled, flagKey, reason: why };
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
    surface: "platform_billing_control_center_v3",
  };
}

async function stripeHealth() {
  const [test, live] = await Promise.all([
    getOrganizerStripeCommercialHealth("test"),
    getOrganizerStripeCommercialHealth("live"),
  ]);
  return { live, test };
}

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "billing.read");
    const params = new URL(request.url).searchParams;
    const page = Math.max(1, Number.parseInt(params.get("page") ?? "1", 10) || 1);
    const pageSize = Math.min(100, Math.max(1, Number.parseInt(params.get("pageSize") ?? "50", 10) || 50));
    const [canonical, stripe] = await Promise.all([
      session.client.rpc("get_pachanga_platform_organizer_billing_v2", {
        page_offset: (page - 1) * pageSize,
        page_size: pageSize,
      }),
      stripeHealth(),
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
    const action = text(body.action, 80).toLowerCase();
    const expectedRevision = Number(body.expectedRevision);
    const payload = record(body.payload);
    if (!uuidPattern.test(operationId) || !uuidPattern.test(aggregateId)
        || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) throw new Error("Invalid billing envelope");

    if (action === "reconciliation.request") {
      const result = await session.client.rpc("request_pachanga_billing_reconciliation_platform_v1", {
        billing_account_id: aggregateId,
        client_metadata: clientMetadata(request),
        expected_revision: expectedRevision,
        operation_id: operationId,
        reason: reason(payload.reason),
      });
      if (result.error) throw new Error(result.error.message);
      return platformJson({ canonical: result.data });
    }

    if (action.startsWith("commercial_decision.")) {
      const result = await session.client.rpc("command_pachanga_organizer_commercial_decision_v1", {
        client_metadata: clientMetadata(request),
        command_action: action,
        command_payload: decisionPayload(action, payload),
        decision_id: aggregateId,
        expected_revision: expectedRevision,
        operation_id: operationId,
      });
      if (result.error) throw new Error(result.error.message);
      return platformJson({ canonical: result.data });
    }

    if (action === "settings.feature_flag_v2" || action === "settings.tax_health_v2") {
      const result = await session.client.rpc("command_pachanga_organizer_commercial_settings_v1", {
        client_metadata: clientMetadata(request),
        command_action: action,
        command_payload: commercialSettingsPayload(action, payload),
        expected_revision: expectedRevision,
        operation_id: operationId,
      });
      if (result.error) throw new Error(result.error.message);
      return platformJson({ canonical: result.data });
    }

    if (action === "stripe_catalog.provision") {
      const stripeMode = mode(payload.stripeMode);
      const prepared = await session.client.rpc("prepare_pachanga_organizer_stripe_catalog_platform_v1", {
        client_metadata: clientMetadata(request),
        decision_id: aggregateId,
        expected_revision: expectedRevision,
        operation_id: operationId,
        reason: reason(payload.reason),
        stripe_mode: stripeMode,
      });
      if (prepared.error) throw new Error(prepared.error.message);
      const intent = parseOrganizerCatalogIntent(operationId, prepared.data);
      const observed = await provisionOrganizerStripeCatalog(intent);
      const confirmed = await billingServiceClient().rpc("confirm_pachanga_organizer_stripe_catalog_service_v1", {
        observed_annual_amount_minor: observed.observedAnnualAmountMinor,
        observed_catalog_revision: observed.observedCatalogRevision,
        observed_currency: observed.observedCurrency,
        observed_metadata: observed.observedMetadata,
        observed_monthly_amount_minor: observed.observedMonthlyAmountMinor,
        observed_tax_behavior: observed.observedTaxBehavior,
        operation_id: operationId,
        stripe_annual_price_id: observed.stripeAnnualPriceId,
        stripe_monthly_price_id: observed.stripeMonthlyPriceId,
        stripe_product_id: observed.stripeProductId,
      });
      if (confirmed.error) throw new Error(confirmed.error.message);
      return platformJson({ canonical: confirmed.data, stripe: {
        mode: stripeMode,
        planCode: intent.planCode,
        pricesConfirmed: 2,
        productName: intent.productName,
      } });
    }

    if (action === "stripe_runtime.verify") {
      const stripeMode = mode(payload.stripeMode);
      let health = await getOrganizerStripeCommercialHealth(stripeMode);
      if (health.catalogReady && !health.portalReady) {
        await ensureOrganizerStripePortal(stripeMode, new URL(request.url).origin);
        health = await getOrganizerStripeCommercialHealth(stripeMode);
      }
      const result = await billingServiceClient().rpc("record_pachanga_organizer_stripe_runtime_health_service_v1", {
        checkout_api_ready: health.checkoutApiReady,
        destination_path: "/api/webhooks/stripe",
        expected_revision: expectedRevision,
        operation_id: operationId,
        portal_ready: health.portalReady,
        safe_error_code: health.safeErrorCode,
        source_revision: health.sourceRevision,
        stripe_mode: stripeMode,
        webhook_destination_ready: health.webhookDestinationReady,
        webhook_signing_ready: health.webhookSigningReady,
      });
      if (result.error) throw new Error(result.error.message);
      return platformJson({ canonical: result.data, stripe: health });
    }

    if (action === "live_checkout.activate") {
      const result = await session.client.rpc("activate_pachanga_organizer_live_checkout_platform_v1", {
        client_metadata: clientMetadata(request),
        confirmation: payload.confirmation,
        expected_revision: expectedRevision,
        operation_id: operationId,
        privacy_revision: exactText(payload.privacyRevision, 120, "privacy revision"),
        reason: reason(payload.reason),
        terms_revision: exactText(payload.termsRevision, 120, "terms revision"),
      });
      if (result.error) throw new Error(result.error.message);
      return platformJson({ canonical: result.data });
    }

    const result = await session.client.rpc("command_pachanga_organizer_billing_platform_v1", {
      aggregate_id: aggregateId,
      client_metadata: clientMetadata(request),
      command_action: action,
      command_payload: legacyCommandPayload(action, payload),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}

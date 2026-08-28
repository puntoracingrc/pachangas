import "server-only";

import Stripe from "stripe";
import {
  type OrganizerBillingMode,
  organizerBillingRecord,
  organizerStripeClient,
  organizerWebhookSecrets,
} from "./_shared";

export const organizerStripeEventTypes = [
  "checkout.session.completed",
  "checkout.session.expired",
  "customer.subscription.created",
  "customer.subscription.updated",
  "customer.subscription.deleted",
  "customer.subscription.paused",
  "customer.subscription.resumed",
  "invoice.paid",
  "invoice.payment_failed",
  "invoice.payment_action_required",
  "customer.updated",
] as const;

type OrganizerCatalogIntent = {
  annualAmountMinor: number;
  catalogRevision: string;
  currency: string;
  decisionId: string;
  metadata: Record<string, string>;
  monthlyAmountMinor: number;
  operationId: string;
  organizerKind: "CLUB" | "TEAM";
  planCode: "CLUB_ORGANIZER" | "TEAM_ORGANIZER_PRO";
  productName: string;
  stripeMode: OrganizerBillingMode;
  taxBehavior: Stripe.PriceCreateParams.TaxBehavior;
};

type OrganizerStripeHealth = {
  catalogReady: boolean;
  checkoutApiReady: boolean;
  configured: boolean;
  measuredAt: string;
  mode: OrganizerBillingMode;
  portalReady: boolean;
  priceCount: number;
  productCount: number;
  productNames: string[];
  safeErrorCode: string | null;
  sourceRevision: string;
  state: "OK" | "UNKNOWN" | "WARNING";
  webhookDestinationReady: boolean;
  webhookSigningReady: boolean;
};

const expectedProductNames = new Map([
  ["CLUB_ORGANIZER", "Pachangas IQ — Club Organizer"],
  ["TEAM_ORGANIZER_PRO", "Pachangas IQ — Team Organizer Pro"],
]);

function text(value: unknown, maximum = 255) {
  return typeof value === "string" && value.trim().length <= maximum ? value.trim() : "";
}

function integer(value: unknown) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : Number.NaN;
}

function stripeIdentifier(value: unknown) {
  if (typeof value === "string") return value;
  return text(organizerBillingRecord(value).id);
}

function exactMetadata(value: unknown) {
  const record = organizerBillingRecord(value);
  const metadata = Object.fromEntries(Object.entries(record).flatMap(([key, item]) => {
    const normalized = text(item, 500);
    return normalized ? [[key, normalized]] : [];
  }));
  const allowed = ["catalog_revision", "environment", "organizer_kind", "plan_code", "product_family"];
  if (Object.keys(metadata).length !== allowed.length || Object.keys(metadata).some((key) => !allowed.includes(key))) {
    throw new Error("BILLING_STRIPE_CATALOG_METADATA_REJECTED");
  }
  return metadata;
}

export function parseOrganizerCatalogIntent(operationId: string, value: unknown): OrganizerCatalogIntent {
  const intent = organizerBillingRecord(value);
  const planCode = text(intent.planCode, 64);
  const organizerKind = text(intent.organizerKind, 8);
  const stripeMode = text(intent.stripeMode, 8);
  const taxBehavior = text(intent.taxBehavior, 16);
  const productName = text(intent.productName, 160);
  const expectedName = expectedProductNames.get(planCode);
  const parsed: OrganizerCatalogIntent = {
    annualAmountMinor: integer(intent.annualAmountMinor),
    catalogRevision: text(intent.catalogRevision, 120),
    currency: text(intent.currency, 3).toLowerCase(),
    decisionId: text(intent.decisionId, 36),
    metadata: exactMetadata(intent.metadata),
    monthlyAmountMinor: integer(intent.monthlyAmountMinor),
    operationId,
    organizerKind: organizerKind as OrganizerCatalogIntent["organizerKind"],
    planCode: planCode as OrganizerCatalogIntent["planCode"],
    productName,
    stripeMode: stripeMode as OrganizerBillingMode,
    taxBehavior: taxBehavior as Stripe.PriceCreateParams.TaxBehavior,
  };
  if (!expectedName || productName !== expectedName
      || !["CLUB", "TEAM"].includes(organizerKind)
      || !["test", "live"].includes(stripeMode)
      || !["exclusive", "inclusive", "unspecified"].includes(taxBehavior)
      || !/^[a-z]{3}$/.test(parsed.currency)
      || !/^[0-9a-f-]{36}$/i.test(parsed.decisionId)
      || !parsed.catalogRevision
      || !Number.isSafeInteger(parsed.monthlyAmountMinor) || parsed.monthlyAmountMinor < 0
      || !Number.isSafeInteger(parsed.annualAmountMinor) || parsed.annualAmountMinor < 0
      || parsed.metadata.plan_code !== planCode
      || parsed.metadata.organizer_kind !== organizerKind.toLowerCase()
      || parsed.metadata.environment !== stripeMode
      || parsed.metadata.product_family !== "organizer"
      || parsed.metadata.catalog_revision !== parsed.catalogRevision) {
    throw new Error("BILLING_STRIPE_CATALOG_INTENT_REJECTED");
  }
  return parsed;
}

function sameMetadata(actual: Stripe.Metadata, expected: Record<string, string>) {
  const keys = Object.keys(expected).sort();
  return Object.keys(actual).sort().join("|") === keys.join("|")
    && keys.every((key) => actual[key] === expected[key]);
}

function assertPrice(
  price: Stripe.Price,
  interval: "month" | "year",
  amount: number,
  productId: string,
  intent: OrganizerCatalogIntent,
) {
  if (!price.active || stripeIdentifier(price.product) !== productId
      || price.currency !== intent.currency || price.unit_amount !== amount
      || price.recurring?.interval !== interval
      || (price.tax_behavior ?? "unspecified") !== intent.taxBehavior
      || !sameMetadata(price.metadata, intent.metadata)) {
    throw new Error("BILLING_STRIPE_CATALOG_READBACK_MISMATCH");
  }
}

function matchingCatalogProduct(product: Stripe.Product, intent: OrganizerCatalogIntent) {
  return product.active
    && product.name === intent.productName
    && sameMetadata(product.metadata, intent.metadata);
}

function matchingCatalogPrice(
  price: Stripe.Price,
  interval: "month" | "year",
  amount: number,
  productId: string,
  intent: OrganizerCatalogIntent,
) {
  return price.active
    && stripeIdentifier(price.product) === productId
    && price.currency === intent.currency
    && price.unit_amount === amount
    && price.recurring?.interval === interval
    && (price.tax_behavior ?? "unspecified") === intent.taxBehavior
    && sameMetadata(price.metadata, intent.metadata);
}

async function resolveCatalogProduct(stripe: Stripe, intent: OrganizerCatalogIntent) {
  const products = await stripe.products.list({ active: true, limit: 100 });
  const matching = products.data.filter((product) => matchingCatalogProduct(product, intent));
  if (matching.length > 1) throw new Error("BILLING_STRIPE_CATALOG_DUPLICATE_PRODUCT");
  if (matching[0]) return matching[0];
  return stripe.products.create({
    active: true,
    description: intent.organizerKind === "CLUB"
      ? "Organización de competiciones para clubs en Pachangas IQ."
      : "Complemento de organización de competiciones para equipos en Pachangas IQ.",
    metadata: intent.metadata,
    name: intent.productName,
  }, { idempotencyKey: `${intent.operationId}:organizer-product` });
}

async function resolveCatalogPrice(
  stripe: Stripe,
  interval: "month" | "year",
  amount: number,
  productId: string,
  intent: OrganizerCatalogIntent,
) {
  const prices = await stripe.prices.list({ active: true, limit: 100, product: productId, type: "recurring" });
  const matching = prices.data.filter((price) => matchingCatalogPrice(price, interval, amount, productId, intent));
  if (matching.length > 1) throw new Error("BILLING_STRIPE_CATALOG_DUPLICATE_PRICE");
  if (matching[0]) return matching[0];
  return stripe.prices.create({
    active: true,
    currency: intent.currency,
    metadata: intent.metadata,
    product: productId,
    recurring: { interval },
    tax_behavior: intent.taxBehavior,
    unit_amount: amount,
  }, { idempotencyKey: `${intent.operationId}:organizer-price-${interval}` });
}

export async function provisionOrganizerStripeCatalog(intent: OrganizerCatalogIntent) {
  const stripe = organizerStripeClient(intent.stripeMode);
  const product = await resolveCatalogProduct(stripe, intent);
  const [monthly, annual] = await Promise.all([
    resolveCatalogPrice(stripe, "month", intent.monthlyAmountMinor, product.id, intent),
    resolveCatalogPrice(stripe, "year", intent.annualAmountMinor, product.id, intent),
  ]);
  const [observedProduct, observedMonthly, observedAnnual] = await Promise.all([
    stripe.products.retrieve(product.id),
    stripe.prices.retrieve(monthly.id),
    stripe.prices.retrieve(annual.id),
  ]);
  if ("deleted" in observedProduct || !observedProduct.active
      || observedProduct.name !== intent.productName
      || !sameMetadata(observedProduct.metadata, intent.metadata)) {
    throw new Error("BILLING_STRIPE_CATALOG_READBACK_MISMATCH");
  }
  assertPrice(observedMonthly, "month", intent.monthlyAmountMinor, observedProduct.id, intent);
  assertPrice(observedAnnual, "year", intent.annualAmountMinor, observedProduct.id, intent);
  return {
    observedAnnualAmountMinor: observedAnnual.unit_amount,
    observedCatalogRevision: intent.catalogRevision,
    observedCurrency: observedAnnual.currency,
    observedMetadata: intent.metadata,
    observedMonthlyAmountMinor: observedMonthly.unit_amount,
    observedTaxBehavior: observedAnnual.tax_behavior ?? "unspecified",
    stripeAnnualPriceId: observedAnnual.id,
    stripeMonthlyPriceId: observedMonthly.id,
    stripeProductId: observedProduct.id,
  };
}

function matchingOrganizerProducts(products: Stripe.Product[], mode: OrganizerBillingMode) {
  return products.filter((product) => product.active
    && product.metadata.product_family === "organizer"
    && product.metadata.environment === mode
    && expectedProductNames.get(product.metadata.plan_code) === product.name);
}

function webhookSupportsOrganizerEvents(endpoint: Stripe.WebhookEndpoint) {
  const enabled = new Set(endpoint.enabled_events);
  return enabled.has("*") || organizerStripeEventTypes.every((event) => enabled.has(event));
}

function isOrganizerWebhookUrl(value: string) {
  try {
    return new URL(value).pathname === "/api/webhooks/stripe";
  } catch {
    return false;
  }
}

async function organizerStripeResources(mode: OrganizerBillingMode) {
  const stripe = organizerStripeClient(mode);
  const [account, products, prices, endpoints, portal] = await Promise.allSettled([
    stripe.balance.retrieve(),
    stripe.products.list({ active: true, limit: 100 }),
    stripe.prices.list({ active: true, limit: 100, type: "recurring" }),
    stripe.webhookEndpoints.list({ limit: 100 }),
    stripe.billingPortal.configurations.list({ active: true, limit: 100 }),
  ]);
  const organizerProducts = products.status === "fulfilled"
    ? matchingOrganizerProducts(products.value.data, mode)
    : [];
  const productIds = new Set(organizerProducts.map((product) => product.id));
  const organizerPrices = prices.status === "fulfilled"
    ? prices.value.data.filter((price) => productIds.has(stripeIdentifier(price.product))
      && price.metadata.product_family === "organizer"
      && price.metadata.environment === mode)
    : [];
  const webhookDestinationReady = endpoints.status === "fulfilled"
    && endpoints.value.data.some((endpoint) => endpoint.status === "enabled"
      && isOrganizerWebhookUrl(endpoint.url) && webhookSupportsOrganizerEvents(endpoint));
  const portalReady = portal.status === "fulfilled" && portal.value.data.some((configuration) => {
    const metadata = configuration.metadata ?? {};
    return configuration.active && metadata.product_family === "organizer"
      && metadata.environment === mode;
  });
  return {
    checkoutApiReady: account.status === "fulfilled",
    organizerPrices,
    organizerProducts,
    portalReady,
    stripe,
    webhookDestinationReady,
  };
}

export async function ensureOrganizerStripePortal(mode: OrganizerBillingMode, origin: string) {
  const resources = await organizerStripeResources(mode);
  if (resources.organizerProducts.length !== 2 || resources.organizerPrices.length !== 4) {
    throw new Error("BILLING_STRIPE_CATALOG_NOT_READY");
  }
  const products = resources.organizerProducts.map((product) => ({
    prices: resources.organizerPrices
      .filter((price) => stripeIdentifier(price.product) === product.id)
      .map((price) => price.id)
      .sort(),
    product: product.id,
  })).sort((left, right) => left.product.localeCompare(right.product));
  const configurations = await resources.stripe.billingPortal.configurations.list({ active: true, limit: 100 });
  const existing = configurations.data.find((configuration) => {
    const metadata = configuration.metadata ?? {};
    return metadata.product_family === "organizer" && metadata.environment === mode;
  });
  const payload: Stripe.BillingPortal.ConfigurationUpdateParams = {
    business_profile: {
      headline: "Gestiona tu plan de organizador de Pachangas IQ",
      privacy_policy_url: `${origin}/privacidad`,
      terms_of_service_url: `${origin}/terminos`,
    },
    features: {
      customer_update: { allowed_updates: ["address", "email", "name", "phone", "tax_id"], enabled: true },
      invoice_history: { enabled: true },
      payment_method_update: { enabled: true },
      subscription_cancel: { enabled: true, mode: "at_period_end" },
      subscription_update: {
        default_allowed_updates: ["price"],
        enabled: true,
        products,
        proration_behavior: "create_prorations",
      },
    },
    metadata: { environment: mode, product_family: "organizer" },
  };
  if (existing) {
    await resources.stripe.billingPortal.configurations.update(existing.id, payload, {
      idempotencyKey: `organizer-portal:${mode}:${products.flatMap((item) => item.prices).join(":")}`,
    });
    return existing.id;
  }
  const created = await resources.stripe.billingPortal.configurations.create(
    payload as Stripe.BillingPortal.ConfigurationCreateParams,
    { idempotencyKey: `organizer-portal:${mode}:${products.flatMap((item) => item.prices).join(":")}` },
  );
  return created.id;
}

export async function getOrganizerStripeCommercialHealth(mode: OrganizerBillingMode): Promise<OrganizerStripeHealth> {
  const measuredAt = new Date().toISOString();
  const sourceRevision = process.env.VERCEL_GIT_COMMIT_SHA ?? process.env.GITHUB_SHA ?? "local-wave7c";
  try {
    const resources = await organizerStripeResources(mode);
    const webhookSigningReady = organizerWebhookSecrets().some((candidate) => candidate.mode === mode);
    const monthly = resources.organizerPrices.filter((price) => price.recurring?.interval === "month");
    const annual = resources.organizerPrices.filter((price) => price.recurring?.interval === "year");
    const catalogReady = resources.organizerProducts.length === 2
      && resources.organizerPrices.length === 4 && monthly.length === 2 && annual.length === 2;
    const allReady = catalogReady && resources.checkoutApiReady && resources.portalReady
      && resources.webhookDestinationReady && webhookSigningReady;
    return {
      catalogReady,
      checkoutApiReady: resources.checkoutApiReady,
      configured: true,
      measuredAt,
      mode,
      portalReady: resources.portalReady,
      priceCount: resources.organizerPrices.length,
      productCount: resources.organizerProducts.length,
      productNames: resources.organizerProducts.map((product) => product.name).sort(),
      safeErrorCode: allReady ? null : "ORGANIZER_STRIPE_RUNTIME_INCOMPLETE",
      sourceRevision,
      state: allReady ? "OK" : "WARNING",
      webhookDestinationReady: resources.webhookDestinationReady,
      webhookSigningReady,
    };
  } catch {
    return {
      catalogReady: false,
      checkoutApiReady: false,
      configured: false,
      measuredAt,
      mode,
      portalReady: false,
      priceCount: 0,
      productCount: 0,
      productNames: [],
      safeErrorCode: `ORGANIZER_STRIPE_${mode.toUpperCase()}_NOT_CONFIGURED`,
      sourceRevision,
      state: "UNKNOWN",
      webhookDestinationReady: false,
      webhookSigningReady: false,
    };
  }
}

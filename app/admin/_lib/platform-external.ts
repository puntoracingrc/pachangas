import "server-only";

import Stripe from "stripe";
import { CLIENT_VERSION, SERVICE_WORKER_VERSION } from "../../client-version-contract";
import { minimumSupportedClientVersion } from "../../api/client-policy/_contract";
import { platformServiceClient } from "./platform-auth";

type HealthState = "CRITICAL" | "OK" | "UNKNOWN" | "WARNING";
type CachedValue = { expiresAt: number; measuredAt: string; value: unknown };

const externalCache = new Map<string, CachedValue>();
const forcedRefreshes = new Map<string, number>();

function optionalEnvironment(name: string) {
  return process.env[name]?.trim() || null;
}

function unknown(source: string, reason: string) {
  return { configured: false, measuredAt: new Date().toISOString(), reason, source, state: "UNKNOWN" as HealthState };
}

function connectorFailureReason(error: unknown) {
  const message = error instanceof Error ? error.message : "";
  const status = message.match(/HTTP\s+(\d{3})/i)?.[1];
  return status ? `La integración respondió HTTP ${status}` : "La integración no pudo completar la consulta";
}

async function cached<T>(key: string, ttlMs: number, force: boolean, loader: () => Promise<T>) {
  const now = Date.now();
  const current = externalCache.get(key);
  if (!force && current && current.expiresAt > now) return current.value as T;
  if (force) {
    const lastForced = forcedRefreshes.get(key) ?? 0;
    if (now - lastForced < 15_000 && current) return current.value as T;
    forcedRefreshes.set(key, now);
  }
  const value = await loader();
  externalCache.set(key, { expiresAt: now + ttlMs, measuredAt: new Date().toISOString(), value });
  return value;
}

async function jsonRequest(url: string, token: string) {
  const response = await fetch(url, {
    cache: "no-store",
    headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(12_000),
  });
  if (!response.ok) throw new Error(`Connector returned HTTP ${response.status}`);
  return response.json() as Promise<Record<string, unknown>>;
}

type AdvisoryCounts = { error: number; info: number; warning: number };

function advisoryCounts(value: unknown): AdvisoryCounts {
  const rows = value && typeof value === "object" && !Array.isArray(value)
    ? (value as { lints?: unknown[] }).lints ?? []
    : [];
  return rows.reduce<AdvisoryCounts>((counts, row) => {
    const level = row && typeof row === "object" ? String((row as { level?: unknown }).level ?? "INFO").toUpperCase() : "INFO";
    if (level === "ERROR") counts.error += 1;
    else if (level === "WARN" || level === "WARNING") counts.warning += 1;
    else counts.info += 1;
    return counts;
  }, { error: 0, info: 0, warning: 0 });
}

export async function getSupabaseManagementHealth(force = false) {
  return cached("supabase-management", 90_000, force, async () => {
    const token = optionalEnvironment("SUPABASE_MANAGEMENT_ACCESS_TOKEN");
    const projectRef = optionalEnvironment("PACHANGAS_SUPABASE_PROJECT_REF");
    if (!token || !projectRef) return unknown("Supabase Management API", "Integración no configurada");
    try {
      const base = `https://api.supabase.com/v1/projects/${encodeURIComponent(projectRef)}`;
      const [usageResult, securityResult, performanceResult] = await Promise.allSettled([
        jsonRequest(`${base}/analytics/endpoints/usage.api-counts`, token),
        jsonRequest(`${base}/advisors/security`, token),
        jsonRequest(`${base}/advisors/performance`, token),
      ]);
      const usage = usageResult.status === "fulfilled" ? usageResult.value : null;
      const security: AdvisoryCounts | null = securityResult.status === "fulfilled" ? advisoryCounts(securityResult.value) : null;
      const performance: AdvisoryCounts | null = performanceResult.status === "fulfilled" ? advisoryCounts(performanceResult.value) : null;
      const advisorErrors = (security?.error ?? 0) + (performance?.error ?? 0);
      const advisorWarnings = (security?.warning ?? 0) + (performance?.warning ?? 0);
      return {
        configured: true,
        limits: null,
        limitsAvailable: false,
        measuredAt: new Date().toISOString(),
        projectRef,
        source: "Supabase Management API",
        state: (advisorErrors ? "CRITICAL" : advisorWarnings ? "WARNING" : "OK") as HealthState,
        usage: usage && Array.isArray(usage.result) ? usage.result : null,
        advisors: { performance, security, experimental: true },
      };
    } catch (error) {
      return { ...unknown("Supabase Management API", connectorFailureReason(error)), configured: true };
    }
  });
}

type VercelDeployment = {
  buildingAt?: number;
  created?: number;
  meta?: Record<string, unknown>;
  name?: string;
  ready?: number;
  state?: string;
  target?: string;
  uid?: string;
  url?: string;
};

function safeDeployment(value: VercelDeployment) {
  const sha = value.meta?.githubCommitSha;
  return {
    buildDurationMs: value.ready && value.buildingAt ? Math.max(0, value.ready - value.buildingAt) : null,
    createdAt: value.created ? new Date(value.created).toISOString() : null,
    id: value.uid ?? null,
    name: value.name ?? null,
    sha: typeof sha === "string" ? sha : null,
    state: value.state ?? "UNKNOWN",
    target: value.target ?? null,
    url: value.url ? `https://${value.url}` : null,
  };
}

async function vercelBillingCharges(token: string, teamId: string) {
  const to = new Date();
  const from = new Date(to.getTime() - 30 * 24 * 60 * 60 * 1000);
  const url = new URL("https://api.vercel.com/v1/billing/charges");
  url.searchParams.set("teamId", teamId);
  url.searchParams.set("from", from.toISOString());
  url.searchParams.set("to", to.toISOString());
  const response = await fetch(url, {
    cache: "no-store",
    headers: { Accept: "application/x-ndjson", Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(12_000),
  });
  if (!response.ok) return { available: false, reason: `HTTP ${response.status}` };
  const text = (await response.text()).slice(0, 1_000_000);
  const rows = text.split("\n").filter(Boolean).slice(0, 5000).flatMap((line) => {
    try { return [JSON.parse(line) as Record<string, unknown>]; } catch { return []; }
  });
  const effectiveCost = rows.reduce((sum, row) => sum + (Number(row.EffectiveCost ?? row.effectiveCost) || 0), 0);
  return { available: true, currency: rows.find((row) => row.BillingCurrency)?.BillingCurrency ?? null, effectiveCost, rows: rows.length, truncated: text.length >= 1_000_000 };
}

export async function getVercelHealth(force = false) {
  return cached("vercel-health", 60_000, force, async () => {
    const token = optionalEnvironment("VERCEL_ADMIN_TOKEN");
    const projectId = optionalEnvironment("PACHANGAS_VERCEL_PROJECT_ID");
    const teamId = optionalEnvironment("PACHANGAS_VERCEL_TEAM_ID");
    if (!token || !projectId || !teamId) return unknown("Vercel REST API", "Integración no configurada");
    try {
      const url = new URL("https://api.vercel.com/v6/deployments");
      url.searchParams.set("projectId", projectId);
      url.searchParams.set("teamId", teamId);
      url.searchParams.set("limit", "10");
      const [deploymentPayload, billing] = await Promise.all([
        jsonRequest(url.toString(), token),
        vercelBillingCharges(token, teamId),
      ]);
      const deployments = (Array.isArray(deploymentPayload.deployments) ? deploymentPayload.deployments : [])
        .map((item) => safeDeployment(item as VercelDeployment));
      const production = deployments.find((item) => item.target === "production") ?? null;
      const failed = deployments.find((item) => /ERROR|CANCELED/.test(item.state)) ?? null;
      return {
        billing,
        configured: true,
        deployments,
        latestFailed: failed,
        measuredAt: new Date().toISOString(),
        production,
        source: "Vercel REST API",
        state: failed && failed === deployments[0] ? "CRITICAL" : failed ? "WARNING" : production?.state === "READY" ? "OK" : "UNKNOWN" as HealthState,
        usageLimits: null,
        usageLimitsAvailable: false,
      };
    } catch (error) {
      return { ...unknown("Vercel REST API", connectorFailureReason(error)), configured: true };
    }
  });
}

function stripeAdminClient() {
  const restricted = optionalEnvironment("STRIPE_ADMIN_RESTRICTED_KEY");
  const broad = optionalEnvironment("STRIPE_SECRET_KEY");
  const key = restricted ?? broad;
  if (!key) return null;
  return { client: new Stripe(key), credentialMode: restricted ? "restricted" : "broad-key-fallback" };
}

function stripeAmountByCurrency(subscriptions: Stripe.Subscription[]) {
  const monthly = new Map<string, number>();
  for (const subscription of subscriptions.filter((item) => item.status === "active" || item.status === "trialing")) {
    for (const item of subscription.items.data) {
      const amount = item.price.unit_amount ?? 0;
      const interval = item.price.recurring?.interval;
      const recurringMonthly = interval === "year" ? amount / 12 : interval === "month" ? amount : 0;
      const quantity = item.quantity ?? 1;
      monthly.set(item.price.currency, (monthly.get(item.price.currency) ?? 0) + recurringMonthly * quantity);
    }
  }
  return [...monthly].map(([currency, amount]) => ({ amount: Math.round(amount), currency }));
}

export async function getStripeHealth(force = false) {
  return cached("stripe-health", 60_000, force, async () => {
    const stripe = stripeAdminClient();
    if (!stripe) return unknown("Stripe API", "Integración no configurada");
    try {
      const [subscriptionsResult, paymentsResult, invoicesResult, refundsResult, disputesResult] = await Promise.all([
        stripe.client.subscriptions.list({ limit: 100, status: "all" }),
        stripe.client.paymentIntents.list({ limit: 50 }),
        stripe.client.invoices.list({ limit: 50 }),
        stripe.client.refunds.list({ limit: 25 }),
        stripe.client.disputes.list({ limit: 25 }),
      ]);
      const subscriptions = subscriptionsResult.data;
      const localResult = await platformServiceClient().from("pachanga_groups")
        .select("id,name,team_code,billing_status,billing_interval,stripe_customer_id,stripe_subscription_id,stripe_price_id,stripe_current_period_end")
        .not("stripe_subscription_id", "is", null)
        .order("updated_at", { ascending: false })
        .limit(200);
      if (localResult.error) throw new Error(localResult.error.message);
      const subscriptionsById = new Map(subscriptions.map((subscription) => [subscription.id, subscription]));
      const reconciliation = (localResult.data ?? []).map((group) => {
        const subscription = group.stripe_subscription_id ? subscriptionsById.get(group.stripe_subscription_id) : null;
        if (!subscription) return {
          groupId: group.id,
          groupName: group.name,
          localStatus: group.billing_status,
          reason: subscriptionsResult.has_more ? "Subscription outside current Stripe sample" : "Subscription not found in Stripe",
          state: subscriptionsResult.has_more ? "UNKNOWN" : "MISMATCH",
          stripeStatus: null,
          subscriptionId: group.stripe_subscription_id,
        };
        const price = subscription.items.data[0]?.price;
        const periodEnd = (subscription as Stripe.Subscription & { current_period_end?: number }).current_period_end;
        const periodIso = typeof periodEnd === "number" ? new Date(periodEnd * 1000).toISOString() : null;
        const differences = [
          group.billing_status !== subscription.status ? "status" : null,
          group.stripe_customer_id !== (typeof subscription.customer === "string" ? subscription.customer : subscription.customer?.id) ? "customer" : null,
          group.stripe_price_id !== (price?.id ?? null) ? "price" : null,
          group.billing_interval !== (price?.recurring?.interval ?? null) ? "interval" : null,
          group.stripe_current_period_end && periodIso && Math.abs(new Date(group.stripe_current_period_end).getTime() - new Date(periodIso).getTime()) > 60_000 ? "period_end" : null,
        ].filter(Boolean);
        return {
          differences,
          groupId: group.id,
          groupName: group.name,
          localStatus: group.billing_status,
          state: differences.length ? "MISMATCH" : "SYNC OK",
          stripeStatus: subscription.status,
          subscriptionId: subscription.id,
        };
      });
      const statusCounts = subscriptions.reduce<Record<string, number>>((counts, subscription) => {
        counts[subscription.status] = (counts[subscription.status] ?? 0) + 1;
        return counts;
      }, {});
      const failedPayments = paymentsResult.data.filter((payment) => payment.status === "requires_payment_method" || payment.last_payment_error);
      const paidInvoices = invoicesResult.data.filter((invoice) => invoice.status === "paid");
      const openInvoices = invoicesResult.data.filter((invoice) => invoice.status === "open");
      const recentPayments = paymentsResult.data.map((payment) => ({
        amount: payment.amount_received,
        createdAt: new Date(payment.created * 1000).toISOString(),
        currency: payment.currency,
        customerId: typeof payment.customer === "string" ? payment.customer : payment.customer?.id ?? null,
        id: payment.id,
        status: payment.status,
      }));
      return {
        configured: true,
        credentialMode: stripe.credentialMode,
        estimatedArr: stripeAmountByCurrency(subscriptions).map((item) => ({ ...item, amount: item.amount * 12 })),
        estimatedMrr: stripeAmountByCurrency(subscriptions),
        invoices: { hasMore: invoicesResult.has_more, open: openInvoices.length, paid: paidInvoices.length },
        measuredAt: new Date().toISOString(),
        payments: { failed: failedPayments.length, hasMore: paymentsResult.has_more, recent: recentPayments, succeeded: paymentsResult.data.filter((payment) => payment.status === "succeeded").length },
        refunds: { count: refundsResult.data.length, hasMore: refundsResult.has_more },
        reconciliation: {
          items: reconciliation,
          mismatch: reconciliation.filter((item) => item.state === "MISMATCH").length,
          syncOk: reconciliation.filter((item) => item.state === "SYNC OK").length,
          unknown: reconciliation.filter((item) => item.state === "UNKNOWN").length,
        },
        disputes: { count: disputesResult.data.length, hasMore: disputesResult.has_more },
        source: "Stripe API",
        state: failedPayments.length || openInvoices.length ? "WARNING" : "OK" as HealthState,
        subscriptions: { counts: statusCounts, hasMore: subscriptionsResult.has_more, sampled: subscriptions.length },
      };
    } catch (error) {
      return { ...unknown("Stripe API", connectorFailureReason(error)), configured: true, credentialMode: stripe.credentialMode };
    }
  });
}

export async function getPlatformExternalHealth(force = false) {
  const [supabase, vercel, stripe] = await Promise.all([
    getSupabaseManagementHealth(force),
    getVercelHealth(force),
    getStripeHealth(force),
  ]);
  const stripeSummary = {
    configured: Boolean(stripe && typeof stripe === "object" && "configured" in stripe && stripe.configured),
    measuredAt: stripe && typeof stripe === "object" && "measuredAt" in stripe ? stripe.measuredAt : null,
    reason: stripe && typeof stripe === "object" && "reason" in stripe ? stripe.reason : null,
    source: stripe && typeof stripe === "object" && "source" in stripe ? stripe.source : "Stripe API",
    state: stripe && typeof stripe === "object" && "state" in stripe ? stripe.state : "UNKNOWN",
  };
  return {
    app: {
      clientVersion: CLIENT_VERSION,
      minimumSupportedClientVersion: minimumSupportedClientVersion(),
      serviceWorkerVersion: SERVICE_WORKER_VERSION,
      sourceRevision: process.env.VERCEL_GIT_COMMIT_SHA ?? process.env.GITHUB_SHA ?? null,
    },
    measuredAt: new Date().toISOString(),
    stripe: stripeSummary,
    supabase,
    vercel,
  };
}

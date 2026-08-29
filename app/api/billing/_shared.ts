import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";
import Stripe from "stripe";

export const FREE_TRIAL_MATCH_LIMIT = 2;

export type BillingInterval = "month" | "year";

export type BillingGroup = {
  billing_interval: BillingInterval | null;
  billing_status: string | null;
  billing_trial_finalized_matches: number | null;
  id: string;
  name: string | null;
  owner_id: string;
  stripe_customer_id: string | null;
  stripe_current_period_end: string | null;
  stripe_price_id: string | null;
  stripe_subscription_id: string | null;
  team_code: string | null;
};

type AuthedClient = {
  client: SupabaseClient;
  token: string;
  user: User;
};

function requiredEnv(name: string) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

export function stripeClient() {
  return new Stripe(requiredEnv("STRIPE_SECRET_KEY"));
}

export function serviceSupabaseClient() {
  return createClient(requiredEnv("NEXT_PUBLIC_SUPABASE_URL"), requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

export function publicSupabaseClient() {
  return createClient(requiredEnv("NEXT_PUBLIC_SUPABASE_URL"), requiredEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

export function getOrigin(request: Request) {
  const envOrigin = process.env.NEXT_PUBLIC_APP_URL || process.env.PACHANGAS_APP_URL;
  if (envOrigin) return envOrigin.replace(/\/$/, "");

  const url = new URL(request.url);
  return url.origin;
}

function optionalEnv(name: string) {
  return process.env[name]?.trim();
}

export async function priceIdForInterval(stripe: Stripe, interval: BillingInterval) {
  const directPriceId = optionalEnv(interval === "year" ? "STRIPE_YEARLY_PRICE_ID" : "STRIPE_MONTHLY_PRICE_ID");
  if (directPriceId?.startsWith("price_")) return directPriceId;

  const productId =
    optionalEnv(interval === "year" ? "STRIPE_YEARLY_PRODUCT_ID" : "STRIPE_MONTHLY_PRODUCT_ID") ??
    (directPriceId?.startsWith("prod_") ? directPriceId : undefined);

  if (!productId) {
    throw new Error(`Missing ${interval === "year" ? "STRIPE_YEARLY_PRICE_ID" : "STRIPE_MONTHLY_PRICE_ID"}`);
  }

  const product = await stripe.products.retrieve(productId, { expand: ["default_price"] });
  const defaultPrice = product.default_price;
  if (typeof defaultPrice === "string") return defaultPrice;
  if (defaultPrice?.id) return defaultPrice.id;

  throw new Error("El producto de Stripe no tiene una tarifa por defecto.");
}

export async function authedSupabaseClient(request: Request): Promise<AuthedClient> {
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("Authentication required");

  const client = createClient(requiredEnv("NEXT_PUBLIC_SUPABASE_URL"), requiredEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    global: {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  });

  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new Error("Invalid session");

  return { client, token, user: userResult.data.user };
}

export async function requireOwnedGroup(request: Request, groupId: string) {
  const { client, user } = await authedSupabaseClient(request);
  const groupResult = await client
    .from("pachanga_groups")
    .select(
      "id, name, team_code, owner_id, billing_status, billing_trial_finalized_matches, stripe_customer_id, stripe_subscription_id, stripe_price_id, stripe_current_period_end, billing_interval",
    )
    .eq("id", groupId)
    .single();

  if (groupResult.error || !groupResult.data) throw new Error("Group not found");

  const group = groupResult.data as BillingGroup;
  if (group.owner_id !== user.id) throw new Error("Only the group owner can manage billing");

  return { group, user };
}

export function stripeStatusToBillingStatus(status: string | null | undefined) {
  if (status === "active" || status === "trialing") return status;
  if (status === "past_due" || status === "unpaid" || status === "incomplete") return status;
  if (status === "canceled") return "canceled";
  return "trial";
}

export function billingGroupIsActive(group: Pick<BillingGroup, "billing_status" | "stripe_current_period_end">) {
  if (group.billing_status !== "active" && group.billing_status !== "trialing") return false;
  if (!group.stripe_current_period_end) return true;

  const periodEnd = new Date(group.stripe_current_period_end);
  return Number.isNaN(periodEnd.getTime()) || periodEnd.getTime() >= Date.now();
}

export function subscriptionCurrentPeriodEnd(subscription: Stripe.Subscription) {
  const periodEnd = (subscription as Stripe.Subscription & { current_period_end?: number }).current_period_end;
  return typeof periodEnd === "number" ? new Date(periodEnd * 1000).toISOString() : null;
}

export async function updateGroupBillingFromSubscription(
  subscription: Stripe.Subscription,
  fallbackGroupId?: string | null,
  fallbackCustomerId?: string | null,
) {
  const groupId = subscription.metadata.groupId || fallbackGroupId;
  if (!groupId) return;

  const firstItem = subscription.items.data[0];
  const interval = firstItem?.price.recurring?.interval;
  const customerId = typeof subscription.customer === "string" ? subscription.customer : subscription.customer?.id ?? fallbackCustomerId ?? null;

  const service = serviceSupabaseClient();
  const updateResult = await service
    .from("pachanga_groups")
    .update({
      billing_interval: interval === "month" || interval === "year" ? interval : null,
      billing_status: stripeStatusToBillingStatus(subscription.status),
      stripe_customer_id: customerId,
      stripe_current_period_end: subscriptionCurrentPeriodEnd(subscription),
      stripe_price_id: firstItem?.price.id ?? null,
      stripe_subscription_id: subscription.id,
    })
    .eq("id", groupId);

  if (updateResult.error) throw new Error(updateResult.error.message);
}

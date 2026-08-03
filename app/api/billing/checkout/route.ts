import {
  billingGroupIsActive,
  getOrigin,
  priceIdForInterval,
  requireOwnedGroup,
  serviceSupabaseClient,
  stripeClient,
  type BillingInterval,
} from "../_shared";
import { clientWriteGateResponse } from "../../client-policy/_contract";

export async function POST(request: Request) {
  const clientGate = clientWriteGateResponse(request);
  if (clientGate) return clientGate;

  try {
    const body = (await request.json()) as { groupId?: string; interval?: BillingInterval };
    const groupId = body.groupId?.trim();
    const interval = body.interval === "year" ? "year" : "month";
    if (!groupId) return Response.json({ error: "Falta el grupo." }, { status: 400 });

    const { group, user } = await requireOwnedGroup(request, groupId);
    const stripe = stripeClient();
    let customerId = group.stripe_customer_id;
    const priceId = await priceIdForInterval(stripe, interval);
    const origin = getOrigin(request);

    if (customerId && billingGroupIsActive(group)) {
      const portal = await stripe.billingPortal.sessions.create({
        customer: customerId,
        return_url: `${origin}/?grupo=${group.id}`,
      });
      return Response.json({ portal: true, url: portal.url });
    }

    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email ?? undefined,
        metadata: {
          groupId: group.id,
          ownerUserId: user.id,
          source: "pachangas_iq",
        },
        name: group.name ?? user.email ?? "Pachangas IQ",
      });
      customerId = customer.id;

      const service = serviceSupabaseClient();
      const updateResult = await service
        .from("pachanga_groups")
        .update({ stripe_customer_id: customerId })
        .eq("id", group.id);
      if (updateResult.error) throw new Error(updateResult.error.message);
    }

    const session = await stripe.checkout.sessions.create({
      allow_promotion_codes: true,
      client_reference_id: group.id,
      customer: customerId,
      line_items: [{ price: priceId, quantity: 1 }],
      metadata: {
        groupId: group.id,
        interval,
        ownerUserId: user.id,
      },
      mode: "subscription",
      subscription_data: {
        metadata: {
          groupId: group.id,
          interval,
          ownerUserId: user.id,
        },
      },
      success_url: `${origin}/?grupo=${group.id}&billing=ok`,
      cancel_url: `${origin}/?grupo=${group.id}&billing=cancel`,
    });

    return Response.json({ url: session.url });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "No se pudo abrir Stripe." },
      { status: 400 },
    );
  }
}

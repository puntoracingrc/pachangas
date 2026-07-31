import Stripe from "stripe";
import {
  serviceSupabaseClient,
  stripeClient,
  stripeStatusToBillingStatus,
  updateGroupBillingFromSubscription,
} from "../../billing/_shared";

export async function POST(request: Request) {
  const stripe = stripeClient();
  const signature = request.headers.get("stripe-signature");
  if (!signature) return Response.json({ error: "Missing Stripe signature" }, { status: 400 });

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(await request.text(), signature, process.env.STRIPE_WEBHOOK_SECRET ?? "");
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Invalid Stripe webhook" },
      { status: 400 },
    );
  }

  const service = serviceSupabaseClient();
  const receiptResult = await service
    .from("pachanga_stripe_webhook_events")
    .insert({
      event_id: event.id,
      event_type: event.type,
      payload: event,
      processing_status: "processing",
    })
    .select("event_id")
    .single();

  if (receiptResult.error) {
    if (receiptResult.error.code !== "23505") {
      return Response.json({ error: receiptResult.error.message }, { status: 500 });
    }

    const existingResult = await service
      .from("pachanga_stripe_webhook_events")
      .select("processing_status")
      .eq("event_id", event.id)
      .maybeSingle();
    if (existingResult.error) return Response.json({ error: existingResult.error.message }, { status: 500 });
    if (existingResult.data?.processing_status !== "failed") {
      return Response.json({ duplicate: true, received: true });
    }

    const retryResult = await service
      .from("pachanga_stripe_webhook_events")
      .update({ error_message: null, payload: event, processing_status: "processing" })
      .eq("event_id", event.id);
    if (retryResult.error) return Response.json({ error: retryResult.error.message }, { status: 500 });
  }

  try {
    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const subscriptionId = typeof session.subscription === "string" ? session.subscription : session.subscription?.id;
      if (subscriptionId) {
        const subscription = await stripe.subscriptions.retrieve(subscriptionId);
        await updateGroupBillingFromSubscription(
          subscription,
          session.metadata?.groupId ?? session.client_reference_id ?? null,
          typeof session.customer === "string" ? session.customer : session.customer?.id ?? null,
        );
      }
    }

    if (
      event.type === "customer.subscription.created" ||
      event.type === "customer.subscription.updated" ||
      event.type === "customer.subscription.deleted"
    ) {
      await updateGroupBillingFromSubscription(event.data.object as Stripe.Subscription);
    }

    if (event.type === "invoice.payment_failed") {
      const invoice = event.data.object as Stripe.Invoice;
      const customerId = typeof invoice.customer === "string" ? invoice.customer : invoice.customer?.id;
      if (customerId) {
        const updateResult = await service
          .from("pachanga_groups")
          .update({ billing_status: stripeStatusToBillingStatus("past_due") })
          .eq("stripe_customer_id", customerId);
        if (updateResult.error) throw new Error(updateResult.error.message);
      }
    }

    if (event.type === "invoice.payment_succeeded") {
      const invoice = event.data.object as Stripe.Invoice;
      const invoiceWithSubscription = invoice as Stripe.Invoice & { subscription?: string | Stripe.Subscription | null };
      const subscriptionId =
        typeof invoiceWithSubscription.subscription === "string"
          ? invoiceWithSubscription.subscription
          : invoiceWithSubscription.subscription?.id;
      if (subscriptionId) {
        const subscription = await stripe.subscriptions.retrieve(subscriptionId);
        await updateGroupBillingFromSubscription(subscription);
      } else {
        const customerId = typeof invoice.customer === "string" ? invoice.customer : invoice.customer?.id;
        if (customerId) {
          const updateResult = await service
            .from("pachanga_groups")
            .update({ billing_status: "active" })
            .eq("stripe_customer_id", customerId);
          if (updateResult.error) throw new Error(updateResult.error.message);
        }
      }
    }

    const processedResult = await service
      .from("pachanga_stripe_webhook_events")
      .update({ error_message: null, processed_at: new Date().toISOString(), processing_status: "processed" })
      .eq("event_id", event.id);
    if (processedResult.error) throw new Error(processedResult.error.message);

    return Response.json({ received: true });
  } catch (error) {
    await service
      .from("pachanga_stripe_webhook_events")
      .update({
        error_message: error instanceof Error ? error.message : "Could not process Stripe webhook",
        processing_status: "failed",
      })
      .eq("event_id", event.id);

    return Response.json(
      { error: error instanceof Error ? error.message : "Could not process Stripe webhook" },
      { status: 500 },
    );
  }
}

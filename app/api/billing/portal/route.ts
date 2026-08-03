import { getOrigin, requireOwnedGroup, stripeClient } from "../_shared";
import { clientWriteGateResponse } from "../../client-policy/_contract";

export async function POST(request: Request) {
  const clientGate = clientWriteGateResponse(request);
  if (clientGate) return clientGate;

  try {
    const body = (await request.json()) as { groupId?: string };
    const groupId = body.groupId?.trim();
    if (!groupId) return Response.json({ error: "Falta el grupo." }, { status: 400 });

    const { group } = await requireOwnedGroup(request, groupId);
    if (!group.stripe_customer_id) {
      return Response.json({ error: "Este grupo todavia no tiene cliente de Stripe." }, { status: 400 });
    }

    const session = await stripeClient().billingPortal.sessions.create({
      customer: group.stripe_customer_id,
      return_url: `${getOrigin(request)}/?grupo=${group.id}`,
    });

    return Response.json({ url: session.url });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "No se pudo abrir el portal." },
      { status: 400 },
    );
  }
}

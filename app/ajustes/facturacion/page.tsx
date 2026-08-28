import type { Metadata } from "next";
import { OrganizerBillingClient } from "../../_components/organizer-billing-client";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Planes y facturacion | Pachangas IQ",
};

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

export default async function OrganizerBillingPage({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams;
  return <OrganizerBillingClient
    checkoutOperationId={first(params.checkout)}
    checkoutStatus={first(params.checkoutStatus)}
    initialOrganizerId={first(params.organizerId)}
    initialOrganizerKind={first(params.organizerKind)}
  />;
}

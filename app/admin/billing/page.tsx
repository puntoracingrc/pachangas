import Link from "next/link";
import { PageHeader } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { hasPlatformCapability } from "../_lib/platform-contract";
import { getStripeHealth } from "../_lib/platform-external";
import { OrganizerBillingAdminClient } from "./organizer-billing-admin-client";
import styles from "../platform-admin.module.css";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export default async function PlatformBillingPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("billing.read");
  const raw = await searchParams;
  const refresh = first(raw.refresh) === "1";
  const [canonicalResult, stripeRaw] = await Promise.all([
    session.client.rpc("get_pachanga_platform_organizer_billing_v2", { page_offset: 0, page_size: 100 }),
    getStripeHealth(refresh),
  ]);
  if (canonicalResult.error) throw new Error(canonicalResult.error.message);
  return <>
    <PageHeader title="Organizer Billing" subtitle="Planes, Stripe y grants canónicos. Ninguna divergencia concede permisos automáticamente." actions={<><Link className={styles.secondaryButton} href="/planes-organizador">Catalogo publico</Link><Link className={styles.secondaryButton} href="/admin/billing?refresh=1">Actualizar Stripe</Link></>} />
    <OrganizerBillingAdminClient
      canApproveLive={session.access.role === "platform_owner"}
      canWrite={hasPlatformCapability(session.access, "billing.write")}
      canonical={record(canonicalResult.data)}
      stripe={record(stripeRaw)}
    />
  </>;
}

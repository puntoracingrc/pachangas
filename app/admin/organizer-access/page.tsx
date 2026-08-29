import Link from "next/link";
import { PageHeader } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { hasPlatformCapability } from "../_lib/platform-contract";
import { OrganizerAccessAdminClient } from "./organizer-access-admin-client";
import styles from "../platform-admin.module.css";

function record(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

export default async function PlatformOrganizerAccessPage() {
  const session = await requirePlatformPage("organizer_access.read");
  const [canonicalResult, healthResult] = await Promise.all([
    session.client.rpc("get_pachanga_platform_organizer_access_v1", {
      target_limit: 200,
      target_search: null,
      target_status: null,
    }),
    session.client.rpc("get_pachanga_organizer_access_health_v1"),
  ]);
  if (canonicalResult.error) throw new Error(canonicalResult.error.message);
  if (healthResult.error) throw new Error(healthResult.error.message);

  return <>
    <PageHeader
      title="Acceso de organizadores"
      subtitle="Solicitudes privadas, revisión, grants y onboarding canónicos. Una aprobación solo concede acceso mediante PostgreSQL."
      actions={<><Link className={styles.secondaryButton} href="/planes-organizador">Planes públicos</Link><Link className={styles.secondaryButton} href="/admin/organizer-access">Actualizar</Link></>}
    />
    <OrganizerAccessAdminClient
      canApprove={hasPlatformCapability(session.access, "organizer_access.approve")}
      canOverride={hasPlatformCapability(session.access, "organizer_access.override")}
      canReview={hasPlatformCapability(session.access, "organizer_access.review")}
      canSupport={hasPlatformCapability(session.access, "organizer_access.support")}
      canonical={record(canonicalResult.data)}
      health={record(healthResult.data)}
    />
  </>;
}

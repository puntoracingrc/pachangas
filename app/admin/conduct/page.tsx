import { PageHeader } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { hasPlatformCapability } from "../_lib/platform-contract";
import { ConductAdminClient } from "./conduct-admin-client";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

export default async function ConductAdminPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("moderation.read");
  const params = await searchParams;
  return (
    <>
      <PageHeader title="Asistencia y conducta" subtitle="Colas, evidencias, revisiones y restricciones del sistema canónico existente. Ninguna señal aplica un ban global automáticamente." />
      <ConductAdminClient
        canModerate={hasPlatformCapability(session.access, "moderation.write")}
        initialGroupId={first(params.groupId)}
        initialMatchId={first(params.matchId)}
      />
    </>
  );
}

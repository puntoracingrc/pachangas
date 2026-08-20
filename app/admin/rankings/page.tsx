import Link from "next/link";
import { PageHeader } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { hasPlatformCapability } from "../_lib/platform-contract";
import { getRankingAdminOverview } from "../_lib/platform-data";
import styles from "../platform-admin.module.css";
import { RankingAdminClient } from "./ranking-admin-client";

export default async function PlatformRankingsPage() {
  const session = await requirePlatformPage("rankings.read");
  const overview = await getRankingAdminOverview(session);
  const canWrite = hasPlatformCapability(session.access, "rankings.write");

  return <>
    <PageHeader
      title="Ranking provincial"
      subtitle="Season Score V3, publicación provincial, cola e integridad desde autoridad PostgreSQL."
      actions={<>
        <Link className={styles.secondaryButton} href="/ranking">Abrir producto</Link>
        {hasPlatformCapability(session.access, "labs.read")
          ? <Link className={styles.secondaryButton} href="/laboratorio-ranking-provincial">Abrir laboratorio</Link>
          : null}
      </>}
    />
    <RankingAdminClient canWrite={canWrite} initialOverview={overview} />
  </>;
}

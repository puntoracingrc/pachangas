import Link from "next/link";
import { ConductReportForm } from "../conduct-report-form";
import styles from "../conduct.module.css";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

export default async function ConductReportPage({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams;
  return (
    <main className={styles.page}>
      <div className={styles.shell}>
        <nav className={styles.topbar} aria-label="Navegación de reporte">
          <div className={styles.title}>
            <span>Conducta</span>
            <h1>Reportar una incidencia</h1>
          </div>
          <Link href="/?mobile=partido">Volver</Link>
        </nav>
        <ConductReportForm context={{
          contextId: first(params.contextId),
          contextKind: first(params.contextKind) || "match",
          expectedRevision: Number(first(params.revision)) || 0,
          reporterGroupId: first(params.reporterGroupId),
          targetGroupId: first(params.targetGroupId),
          targetProfileId: first(params.targetProfileId),
        }} />
      </div>
    </main>
  );
}

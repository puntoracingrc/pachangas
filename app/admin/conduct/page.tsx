import Link from "next/link";
import styles from "../../conduct.module.css";
import { ConductAdminClient } from "./conduct-admin-client";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

export default async function ConductAdminPage({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams;
  return (
    <main className={styles.page}>
      <div className={styles.shell}>
        <nav className={styles.topbar} aria-label="Navegación de administración de conducta">
          <div className={styles.title}>
            <span>Administración</span>
            <h1>Asistencia y conducta</h1>
          </div>
          <Link href="/?mobile=partido">Volver</Link>
        </nav>
        <ConductAdminClient initialGroupId={first(params.groupId)} initialMatchId={first(params.matchId)} />
      </div>
    </main>
  );
}

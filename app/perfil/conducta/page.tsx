import Link from "next/link";
import { ConductPlayerCenter } from "../../conduct-player-center";
import styles from "../../conduct.module.css";

export default function PlayerConductPage() {
  return (
    <main className={styles.page}>
      <div className={styles.shell}>
        <nav className={styles.topbar} aria-label="Navegación de conducta">
          <div className={styles.title}>
            <span>Perfil</span>
            <h1>Avisos y conducta</h1>
            <p>Asistencia, decisiones administrativas y apelaciones confirmadas por el servidor.</p>
          </div>
          <Link href="/?mobile=perfil">Volver</Link>
        </nav>
        <ConductPlayerCenter />
      </div>
    </main>
  );
}

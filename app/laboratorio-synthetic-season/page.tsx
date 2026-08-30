import type { Metadata } from "next";
import Link from "next/link";
import manifest from "../../public/demo-world/v3-2/manifest.json";
import season from "../../public/demo-world/v3-2/season.json";
import styles from "./page.module.css";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Synthetic Season Control Center | Pachangas IQ",
};

function Metric({ label, value }: { label: string; value: number | string }) {
  return <div><dt>{label}</dt><dd>{value}</dd></div>;
}

export default function SyntheticSeasonControlCenter() {
  const proof = season.proof;
  const invariants = Object.entries(proof.invariants);
  return (
    <main className={styles.page}>
      <header>
        <div><span>Laboratorio noindex · solo lectura</span><h1>Synthetic Season Control Center</h1><p>Diagnóstico reproducible de Demo World V3.2. Esta superficie no puede ejecutar Simulation World.</p></div>
        <Link href="/demo?tab=temporada">Abrir temporada</Link>
      </header>
      <section className={styles.metrics}>
        <Metric label="Versión" value={proof.simulationVersion} />
        <Metric label="Seed" value={proof.seed} />
        <Metric label="Ledger" value={proof.migrationLedger.count} />
        <Metric label="Partidos" value={proof.counts.matches} />
        <Metric label="Checkpoints" value={proof.counts.checkpoints} />
        <Metric label="Remote writes" value={proof.remoteWrites} />
      </section>
      <section className={styles.columns}>
        <article><header><span>Autoridad</span><h2>Hashes semánticos</h2></header><dl className={styles.hashes}><Metric label="Authority" value={proof.authorityHash} /><Metric label="Public snapshot" value={proof.publicSnapshotHash} /><Metric label="Manifest" value={manifest.hash} /><Metric label="Input" value={proof.inputHash} /></dl></article>
        <article><header><span>Invariantes</span><h2>{invariants.filter(([, value]) => value).length}/{invariants.length} PASS</h2></header><ul>{invariants.map(([name, passed]) => <li data-pass={passed} key={name}><span>{name}</span><strong>{passed ? "PASS" : "FAIL"}</strong></li>)}</ul></article>
        <article><header><span>Privacidad</span><h2>Escaneo público</h2></header><dl><Metric label="Auth UUIDs" value={proof.privacyScan.authUuids} /><Metric label="Emails" value={proof.privacyScan.emails} /><Metric label="Teléfonos" value={proof.privacyScan.phones} /><Metric label="Secretos" value={proof.privacyScan.secrets} /><Metric label="Stripe IDs" value={proof.privacyScan.stripeIds} /></dl></article>
        <article><header><span>Notificaciones</span><h2>Sink sintético</h2></header><dl><Metric label="Destinatarios inválidos" value={proof.notificationScan.invalidRecipients} /><Metric label="Entregas externas" value={proof.notificationScan.externalDeliveries} /><Metric label="Eventos" value={proof.counts.notifications} /><Metric label="Stripe" value={proof.stripeTouched ? "TOCADO" : "NO"} /></dl></article>
      </section>
      <section className={styles.timeline}><header><span>Timeline</span><h2>Checkpoints inmutables</h2></header><div>{manifest.checkpoints.map((checkpoint) => <article key={checkpoint.checkpoint}><b>{checkpoint.checkpoint}</b><span><strong>{checkpoint.label}</strong><small>Semana {checkpoint.week}</small></span><code>{checkpoint.hash.slice(0, 14)}</code></article>)}</div></section>
      <footer><span>Database destroyed: {proof.cleanup.databaseDestroyed ? "sí" : "no"}</span><span>Production rows: {proof.cleanup.productionRows}</span><span>Pending operations: {proof.cleanup.pendingOperations}</span></footer>
    </main>
  );
}

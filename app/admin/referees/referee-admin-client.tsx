"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { clientWriteFetch } from "../../pwa-client-bridge";
import { refereeNumber, refereeText, type RefereeJson } from "../../referee-platform-contract";
import styles from "../platform-admin.module.css";

export function RefereeAdminClient({ canWrite, flags, selected }: { canWrite: boolean; flags: RefereeJson; selected: RefereeJson | null }) {
  const router = useRouter();
  const pending = useRef<{ id: string; key: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [reason, setReason] = useState("");
  const [flagState, setFlagState] = useState({
    clubRelationshipsEnabled: flags.clubRelationshipsEnabled === true,
    foundationEnabled: flags.foundationEnabled === true,
    marketplaceEnabled: flags.marketplaceEnabled === true,
    publicProfilesEnabled: flags.publicProfilesEnabled === true,
    selfServiceEnabled: flags.selfServiceEnabled === true,
  });
  const [assignmentFlagState, setAssignmentFlagState] = useState({
    assignmentPrivateBetaEnabled: flags.assignmentPrivateBetaEnabled === true,
    assignmentsEnabled: flags.assignmentsEnabled === true,
  });

  async function run(action: string, aggregateId: string, expectedRevision: number, payload: RefereeJson) {
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true); setMessage("");
    try {
      const response = await clientWriteFetch("api:platform-admin-referees", "/api/platform-admin/referees", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" }, method: "POST",
      });
      const body = await response.json() as { error?: string; message?: string };
      if (!response.ok) throw new Error(body.message || body.error || "Operación no confirmada");
      pending.current = null; setReason(""); setMessage("Cambio confirmado por PostgreSQL."); router.refresh();
    } catch (error) { setMessage(error instanceof Error ? error.message : "Operación no confirmada"); }
    finally { setBusy(false); }
  }

  if (!canWrite) return <p className={styles.helpText}>Tu rol dispone de lectura arbitral limitada.</p>;
  const id = refereeText(selected?.id);
  const revision = refereeNumber(selected?.revision);
  return <div className={styles.competitionControlGrid}>
    <section className={styles.competitionControl}><h3>Flags R3</h3>{Object.entries(flagState).map(([key, value]) => <label className={styles.checkField} key={key}><input type="checkbox" checked={value} disabled={busy} onChange={(event) => setFlagState((current) => ({ ...current, [key]: event.target.checked }))} />{key.replace("Enabled", "")}</label>)}<label className={styles.formField}>Motivo<textarea rows={2} value={reason} onChange={(event) => setReason(event.target.value)} /></label><button className={styles.primaryButton} type="button" disabled={busy} onClick={() => void run("referee_flags.set", "00000000-0000-0000-0000-00000000a3f3", refereeNumber(flags.revision), { ...flagState, reason })}>Guardar flags R3</button></section>
    <section className={styles.competitionControl}><h3>Assignments · Beta privada</h3>{Object.entries(assignmentFlagState).map(([key, value]) => <label className={styles.checkField} key={key}><input type="checkbox" checked={value} disabled={busy} onChange={(event) => setAssignmentFlagState((current) => ({ ...current, [key]: event.target.checked }))} />{key.replace("Enabled", "")}</label>)}<p>Activa primero la beta privada. Los pagos y el descubrimiento público permanecen fuera.</p><button className={styles.primaryButton} type="button" disabled={busy || reason.trim().length < 3} onClick={() => void run("assignment_beta.flags.set", "00000000-0000-0000-0000-00000000a4f4", refereeNumber(flags.revision), { ...assignmentFlagState, reason })}>Guardar beta arbitral</button></section>
    {selected ? <>
      <section className={styles.competitionControl}><h3>Perfil</h3><p>{refereeText(selected.displayName)} · revisión {revision}</p><button className={styles.secondaryButton} type="button" disabled={busy || refereeText(selected.operationalStatus) !== "draft"} onClick={() => void run("profile.activate", id, revision, { reason })}>Activar</button><button className={styles.dangerButton} type="button" disabled={busy || refereeText(selected.operationalStatus) !== "active"} onClick={() => void run("profile.suspend", id, revision, { reason })}>Suspender</button><button className={styles.secondaryButton} type="button" disabled={busy || refereeText(selected.operationalStatus) !== "suspended"} onClick={() => void run("profile.restore", id, revision, { reason })}>Restaurar</button></section>
      <section className={styles.competitionControl}><h3>Verificación</h3><p>{refereeText(selected.verificationStatus)}</p><button className={styles.secondaryButton} type="button" disabled={busy} onClick={() => void run("verification.pending", id, revision, { reason })}>Pendiente</button><button className={styles.primaryButton} type="button" disabled={busy} onClick={() => void run("verification.approve", id, revision, { reason })}>Aprobar</button><button className={styles.dangerButton} type="button" disabled={busy} onClick={() => void run("verification.revoke", id, revision, { reason })}>Revocar</button></section>
      <section className={styles.competitionControl}><h3>Estadísticas</h3><p>Solo reconstrucción desde asignaciones canónicas.</p><button className={styles.secondaryButton} type="button" disabled={busy} onClick={() => void run("stats.rebuild", id, refereeNumber(selected.statisticsRevision), { reason })}>Rebuild</button></section>
    </> : <section className={styles.competitionControl}><h3>Selecciona un árbitro</h3><p>Abre una fila del registro para revisar su estado y evidencia.</p></section>}
    {message ? <p className={styles.competitionControlMessage} role="status">{message}</p> : null}
  </div>;
}

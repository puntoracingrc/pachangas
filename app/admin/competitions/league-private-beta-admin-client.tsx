"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { clientWriteFetch } from "../../pwa-client-bridge";
import styles from "../platform-admin.module.css";

type JsonRecord = Record<string, unknown>;
function text(value: unknown) { return typeof value === "string" ? value : ""; }
function number(value: unknown) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }

export function LeaguePrivateBetaAdminClient({
  bundles,
  canWrite,
  flags,
  organizers,
}: {
  bundles: JsonRecord[];
  canWrite: boolean;
  flags: JsonRecord;
  organizers: JsonRecord[];
}) {
  const router = useRouter();
  const pending = useRef<{ id: string; key: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [enabled, setEnabled] = useState(Boolean(flags.enabled));
  const [creationEnabled, setCreationEnabled] = useState(Boolean(flags.creationEnabled));
  const [flagReason, setFlagReason] = useState("");
  const [organizerKey, setOrganizerKey] = useState("");
  const [maxTeams, setMaxTeams] = useState(12);
  const [expiresAt, setExpiresAt] = useState("");
  const [grantReason, setGrantReason] = useState("");

  async function run(action: string, aggregateId: string | null, expectedRevision: number, payload: JsonRecord) {
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación del servidor...");
    try {
      const response = await clientWriteFetch("api:platform-admin-league-private-beta", "/api/platform-admin/league-private-beta", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" },
        method: "POST",
      });
      const body = await response.json() as { error?: string; message?: string };
      if (!response.ok) throw new Error(body.message || body.error || "Operación no confirmada");
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Operación no confirmada");
    } finally {
      setBusy(false);
    }
  }

  if (!canWrite) return <p className={styles.helpText}>Tu rol puede consultar la beta, pero no conceder acceso ni cambiar sus gates.</p>;
  const selected = organizers.find((item) => `${text(item.organizerKind)}:${text(item.organizerId)}` === organizerKey);

  return <div className={styles.competitionControlGrid}>
    <section className={styles.competitionControl}>
      <h3>League Private Beta</h3>
      <p>El gate global y el bundle del organizador deben estar activos a la vez.</p>
      <label className={styles.checkField}><input type="checkbox" checked={enabled} onChange={(event) => setEnabled(event.target.checked)} disabled={busy} />Beta privada</label>
      <label className={styles.checkField}><input type="checkbox" checked={creationEnabled} onChange={(event) => setCreationEnabled(event.target.checked)} disabled={busy || !enabled} />Crear nuevas Ligas</label>
      <label className={styles.formField}>Motivo<textarea rows={2} value={flagReason} onChange={(event) => setFlagReason(event.target.value)} disabled={busy} /></label>
      <button className={styles.primaryButton} type="button" disabled={busy} onClick={() => void run("beta.flags.set", null, number(flags.revision), { creationEnabled: enabled && creationEnabled, enabled, publicDiscoveryEnabled: false, reason: flagReason })}>Guardar gate</button>
      <button className={styles.dangerButton} type="button" disabled={busy} onClick={() => { const reason = window.prompt("Motivo del apagado inmediato"); if (reason) void run("beta.kill_switch", null, number(flags.revision), { reason }); }}>Apagado inmediato</button>
    </section>

    <section className={styles.competitionControl}>
      <h3>Conceder bundle</h3>
      <label className={styles.formField}>Team o Club<select value={organizerKey} onChange={(event) => setOrganizerKey(event.target.value)} disabled={busy}><option value="">Selecciona</option>{organizers.map((item) => <option key={`${text(item.organizerKind)}:${text(item.organizerId)}`} value={`${text(item.organizerKind)}:${text(item.organizerId)}`}>{text(item.organizerKind)} · {text(item.name)} · {text(item.reference)}</option>)}</select></label>
      <label className={styles.formField}>Máximo de equipos<input type="number" min={4} max={20} value={maxTeams} onChange={(event) => setMaxTeams(Number(event.target.value))} disabled={busy} /></label>
      <label className={styles.formField}>Caduca<input type="datetime-local" value={expiresAt} onChange={(event) => setExpiresAt(event.target.value)} disabled={busy} /></label>
      <label className={styles.formField}>Motivo<textarea rows={2} value={grantReason} onChange={(event) => setGrantReason(event.target.value)} disabled={busy} /></label>
      <button className={styles.primaryButton} type="button" disabled={busy || !selected} onClick={() => selected && void run("beta.bundle.grant", text(selected.organizerId), number(selected.organizerRevision), { capacityOverride: maxTeams > 12, expiresAt, maxTeams, organizerKind: text(selected.organizerKind), reason: grantReason })}>Conceder 11 capacidades</button>
    </section>

    {bundles.filter((item) => text(item.status) === "active").map((bundle) => <section className={styles.competitionControl} key={text(bundle.bundleId)}><h3>{text(bundle.organizerKind)} autorizado</h3><p>{number(bundle.capabilityCount)} capacidades · máximo {number(bundle.teamCap)} equipos</p><small>{text(bundle.expiresAt) || "Sin caducidad"}</small><button className={styles.dangerButton} type="button" disabled={busy} onClick={() => { const reason = window.prompt("Motivo de revocación"); const organizer = organizers.find((item) => text(item.organizerId) === text(bundle.organizerId)); if (reason) void run("beta.bundle.revoke", text(bundle.organizerId), number(organizer?.organizerRevision), { bundleId: text(bundle.bundleId), organizerKind: text(bundle.organizerKind), reason }); }}>Revocar bundle</button></section>)}
    {message ? <p className={styles.competitionControlMessage} role="status">{message}</p> : null}
  </div>;
}

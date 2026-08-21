"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { clientWriteFetch } from "../../pwa-client-bridge";
import styles from "../platform-admin.module.css";

type JsonRecord = Record<string, unknown>;

function text(value: unknown) {
  return typeof value === "string" ? value : "";
}

function number(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function ClubAdminClient({
  canWrite,
  flags,
  selected,
}: {
  canWrite: boolean;
  flags: JsonRecord;
  selected: JsonRecord | null;
}) {
  const router = useRouter();
  const pending = useRef<{ id: string; key: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [reason, setReason] = useState("");
  const [foundationEnabled, setFoundationEnabled] = useState(Boolean(flags.foundationEnabled));
  const [selfServiceCreationEnabled, setSelfServiceCreationEnabled] = useState(Boolean(flags.selfServiceCreationEnabled));
  const [teamRelationshipsEnabled, setTeamRelationshipsEnabled] = useState(Boolean(flags.teamRelationshipsEnabled));
  const [publicProfilesEnabled, setPublicProfilesEnabled] = useState(Boolean(flags.publicProfilesEnabled));
  const [competitionOrganizerEnabled, setCompetitionOrganizerEnabled] = useState(Boolean(flags.competitionOrganizerEnabled));
  const [operationalStatus, setOperationalStatus] = useState(text(selected?.operationalStatus) || "draft");
  const [verificationStatus, setVerificationStatus] = useState(text(selected?.verificationStatus) || "unverified");
  const [partnershipStatus, setPartnershipStatus] = useState(text(selected?.partnershipStatus) || "none");
  const [entitlementSource, setEntitlementSource] = useState("platform_grant");
  const [entitlementExpiry, setEntitlementExpiry] = useState("");

  function resetPending() {
    pending.current = null;
    setMessage("");
  }

  async function run(action: string, aggregateId: string | null, expectedRevision: number, payload: JsonRecord) {
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("");
    try {
      const response = await clientWriteFetch("api:platform-admin-clubs", "/api/platform-admin/clubs", {
        body: JSON.stringify({
          action,
          aggregateId,
          expectedRevision,
          operationId: pending.current.id,
          payload,
        }),
        headers: {
          "Content-Type": "application/json",
          "X-Pachangas-Platform-Admin": "1",
        },
        method: "POST",
      });
      const body = await response.json() as { error?: string; message?: string };
      if (!response.ok) throw new Error(body.message || body.error || "Operación no confirmada");
      pending.current = null;
      setReason("");
      setMessage("Cambio confirmado por PostgreSQL.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Operación no confirmada");
    } finally {
      setBusy(false);
    }
  }

  if (!canWrite) {
    return <p className={styles.helpText}>Tu rol puede consultar clubes, pero no cambiar estados, flags ni entitlements.</p>;
  }

  const clubId = text(selected?.id);
  const clubRevision = number(selected?.revision);
  const entitlement = selected?.entitlements && typeof selected.entitlements === "object"
    ? selected.entitlements as JsonRecord
    : {};
  const grants = Array.isArray(entitlement.grants)
    ? entitlement.grants.filter((item): item is JsonRecord => Boolean(item && typeof item === "object" && !Array.isArray(item)))
    : [];

  return (
    <div className={styles.competitionControlGrid}>
      <section className={styles.competitionControl}>
        <h3>Flags de Club R2</h3>
        <label className={styles.checkField}><input type="checkbox" checked={foundationEnabled} onChange={(event) => { resetPending(); setFoundationEnabled(event.target.checked); }} disabled={busy} />Fundación</label>
        <label className={styles.checkField}><input type="checkbox" checked={selfServiceCreationEnabled} onChange={(event) => { resetPending(); setSelfServiceCreationEnabled(event.target.checked); }} disabled={busy} />Creación autoservicio</label>
        <label className={styles.checkField}><input type="checkbox" checked={teamRelationshipsEnabled} onChange={(event) => { resetPending(); setTeamRelationshipsEnabled(event.target.checked); }} disabled={busy} />Relaciones Club–Equipo</label>
        <label className={styles.checkField}><input type="checkbox" checked={publicProfilesEnabled} onChange={(event) => { resetPending(); setPublicProfilesEnabled(event.target.checked); }} disabled={busy} />Perfiles públicos</label>
        <label className={styles.checkField}><input type="checkbox" checked={competitionOrganizerEnabled} onChange={(event) => { resetPending(); setCompetitionOrganizerEnabled(event.target.checked); }} disabled={busy} />Club organizador</label>
        <label className={styles.formField}>Motivo<textarea rows={2} value={reason} onChange={(event) => { resetPending(); setReason(event.target.value); }} disabled={busy} /></label>
        <button className={styles.primaryButton} type="button" disabled={busy} onClick={() => void run("club_flags.set", null, number(flags.revision), {
          competitionOrganizerEnabled,
          foundationEnabled,
          publicProfilesEnabled,
          reason,
          selfServiceCreationEnabled,
          teamRelationshipsEnabled,
        })}>Guardar flags</button>
      </section>

      {selected ? (
        <>
          <section className={styles.competitionControl}>
            <h3>Ciclo operativo</h3>
            <p>{text(selected.name)} · revisión {clubRevision}</p>
            <label className={styles.formField}>Estado<select value={operationalStatus} onChange={(event) => { resetPending(); setOperationalStatus(event.target.value); }} disabled={busy}><option value="draft">Draft</option><option value="pending_review">Pendiente</option><option value="active">Activo</option><option value="suspended">Suspendido</option><option value="rejected">Rechazado</option><option value="archived">Archivado</option></select></label>
            <button className={styles.secondaryButton} type="button" disabled={busy} onClick={() => void run("club.status.set", clubId, clubRevision, { reason, status: operationalStatus })}>Confirmar estado</button>
            <label className={styles.formField}>Verificación<select value={verificationStatus} onChange={(event) => { resetPending(); setVerificationStatus(event.target.value); }} disabled={busy}><option value="unverified">No verificado</option><option value="pending">Pendiente</option><option value="verified">Verificado</option><option value="rejected">Rechazado</option><option value="revoked">Revocado</option></select></label>
            <button className={styles.secondaryButton} type="button" disabled={busy} onClick={() => void run("club.verification.set", clubId, clubRevision, { reason, status: verificationStatus })}>Confirmar verificación</button>
          </section>

          <section className={styles.competitionControl}>
            <h3>Partnership y entitlement</h3>
            <label className={styles.formField}>Partnership<select value={partnershipStatus} onChange={(event) => { resetPending(); setPartnershipStatus(event.target.value); }} disabled={busy}><option value="none">Ninguno</option><option value="candidate">Candidato</option><option value="active">Activo</option><option value="paused">Pausado</option><option value="ended">Finalizado</option></select></label>
            <button className={styles.secondaryButton} type="button" disabled={busy} onClick={() => void run("club.partnership.set", clubId, clubRevision, { reason, status: partnershipStatus })}>Guardar partnership</button>
            <p>Partnership no concede permisos automáticamente.</p>
            <label className={styles.formField}>Origen<select value={entitlementSource} onChange={(event) => { resetPending(); setEntitlementSource(event.target.value); }} disabled={busy}><option value="platform_grant">Grant de plataforma</option><option value="partnership">Partnership explícito</option></select></label>
            <label className={styles.formField}>Caduca<input type="datetime-local" value={entitlementExpiry} onChange={(event) => { resetPending(); setEntitlementExpiry(event.target.value); }} disabled={busy} /></label>
            <button className={styles.primaryButton} type="button" disabled={busy} onClick={() => void run("club.entitlement.grant", clubId, clubRevision, { expiresAt: entitlementExpiry, reason, source: entitlementSource })}>Conceder creación de competición</button>
          </section>

          {grants.some((item) => text(item.status) === "active") ? (
            <section className={styles.competitionEntitlementActions}>
              <h3>Entitlements activos</h3>
              {grants.filter((item) => text(item.status) === "active").map((item) => (
                <div key={text(item.id)}>
                  <span><strong>{text(item.capability)}</strong><small>{text(item.source)}</small></span>
                  <button className={styles.dangerButton} type="button" disabled={busy} onClick={() => void run("club.entitlement.revoke", clubId, clubRevision, { entitlementId: text(item.id), reason })}>Revocar</button>
                </div>
              ))}
            </section>
          ) : null}
        </>
      ) : <section className={styles.competitionControl}><h3>Selecciona un club</h3><p>Abre un club del listado para revisar su ciclo, staff, equipos y entitlements.</p></section>}

      {message ? <p className={styles.competitionControlMessage} role="status">{message}</p> : null}
    </div>
  );
}

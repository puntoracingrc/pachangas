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

export function CompetitionAdminClient({
  canWrite,
  entitlements,
  flags,
  leagueFlags,
}: {
  canWrite: boolean;
  entitlements: JsonRecord[];
  flags: JsonRecord;
  leagueFlags: JsonRecord;
}) {
  const router = useRouter();
  const operationId = useRef<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [foundationEnabled, setFoundationEnabled] = useState(Boolean(flags.foundationEnabled));
  const [creationEnabled, setCreationEnabled] = useState(Boolean(flags.creationEnabled));
  const [contextBindingEnabled, setContextBindingEnabled] = useState(Boolean(flags.contextBindingEnabled));
  const [flagReason, setFlagReason] = useState("");
  const [groupId, setGroupId] = useState("");
  const [capability, setCapability] = useState("competition_create");
  const [expiresAt, setExpiresAt] = useState("");
  const [grantReason, setGrantReason] = useState("");
  const [backfillReason, setBackfillReason] = useState("");
  const [leagueFoundationEnabled, setLeagueFoundationEnabled] = useState(Boolean(leagueFlags.foundationEnabled));
  const [leagueRegistrationEnabled, setLeagueRegistrationEnabled] = useState(Boolean(leagueFlags.registrationEnabled));
  const [leaguePublicRegistrationEnabled, setLeaguePublicRegistrationEnabled] = useState(Boolean(leagueFlags.publicRegistrationEnabled));
  const [leagueDelegatesEnabled, setLeagueDelegatesEnabled] = useState(Boolean(leagueFlags.delegatesEnabled));
  const [leagueRostersEnabled, setLeagueRostersEnabled] = useState(Boolean(leagueFlags.rostersEnabled));
  const [leagueSchedulePreferencesEnabled, setLeagueSchedulePreferencesEnabled] = useState(Boolean(leagueFlags.schedulePreferencesEnabled));
  const [leagueFlagReason, setLeagueFlagReason] = useState("");

  function resetOperation() {
    operationId.current = null;
    setMessage("");
  }

  async function run(action: string, aggregateId: string | null, expectedRevision: number, payload: JsonRecord) {
    setBusy(true);
    setMessage("");
    try {
      operationId.current ??= crypto.randomUUID();
      const response = await clientWriteFetch(
        "api:platform-admin-competitions",
        "/api/platform-admin/competitions",
        {
          body: JSON.stringify({
            action,
            aggregateId,
            expectedRevision,
            operationId: operationId.current,
            payload,
          }),
          headers: {
            "Content-Type": "application/json",
            "X-Pachangas-Platform-Admin": "1",
          },
          method: "POST",
        },
      );
      const body = await response.json() as { error?: string; message?: string };
      if (!response.ok) throw new Error(body.message || body.error || "Operación no confirmada");
      operationId.current = null;
      setMessage("Cambio confirmado por el servidor.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Operación no confirmada");
    } finally {
      setBusy(false);
    }
  }

  function organizerRevision(targetGroupId: string) {
    const matching = entitlements.find((item) => (
      text(item.organizerKind) === "TEAM" && text(item.organizerGroupId) === targetGroupId
    ));
    return matching ? number(matching.organizerRevision) : 0;
  }

  if (!canWrite) {
    return <p className={styles.helpText}>Tu rol puede consultar la fundación, pero no modificar flags, grants ni bindings.</p>;
  }

  return (
    <div className={styles.competitionControlGrid}>
      <section className={styles.competitionControl}>
        <h3>Activación de laboratorio</h3>
        <label className={styles.checkField}><input type="checkbox" checked={foundationEnabled} onChange={(event) => { resetOperation(); setFoundationEnabled(event.target.checked); }} disabled={busy} />Fundación</label>
        <label className={styles.checkField}><input type="checkbox" checked={creationEnabled} onChange={(event) => { resetOperation(); setCreationEnabled(event.target.checked); }} disabled={busy} />Creación de drafts</label>
        <label className={styles.checkField}><input type="checkbox" checked={contextBindingEnabled} onChange={(event) => { resetOperation(); setContextBindingEnabled(event.target.checked); }} disabled={busy} />Binding de contexto</label>
        <label className={styles.formField}>Motivo<textarea rows={2} value={flagReason} onChange={(event) => { resetOperation(); setFlagReason(event.target.value); }} disabled={busy} /></label>
        <button className={styles.primaryButton} type="button" disabled={busy} onClick={() => void run("foundation_flags.set", null, number(flags.revision), { contextBindingEnabled, creationEnabled, foundationEnabled, reason: flagReason })}>Guardar flags</button>
      </section>

      <section className={styles.competitionControl}>
        <h3>League Participation R4A</h3>
        <p>Inscripciones, delegados, plantillas y elegibilidad. No genera jornadas ni partidos.</p>
        <label className={styles.checkField}><input type="checkbox" checked={leagueFoundationEnabled} onChange={(event) => { resetOperation(); setLeagueFoundationEnabled(event.target.checked); }} disabled={busy} />Fundación de participación</label>
        <label className={styles.checkField}><input type="checkbox" checked={leagueRegistrationEnabled} onChange={(event) => { resetOperation(); setLeagueRegistrationEnabled(event.target.checked); }} disabled={busy} />Inscripciones</label>
        <label className={styles.checkField}><input type="checkbox" checked={leaguePublicRegistrationEnabled} onChange={(event) => { resetOperation(); setLeaguePublicRegistrationEnabled(event.target.checked); }} disabled={busy} />Inscripción pública</label>
        <label className={styles.checkField}><input type="checkbox" checked={leagueDelegatesEnabled} onChange={(event) => { resetOperation(); setLeagueDelegatesEnabled(event.target.checked); }} disabled={busy} />Delegados</label>
        <label className={styles.checkField}><input type="checkbox" checked={leagueRostersEnabled} onChange={(event) => { resetOperation(); setLeagueRostersEnabled(event.target.checked); }} disabled={busy} />Plantillas</label>
        <label className={styles.checkField}><input type="checkbox" checked={leagueSchedulePreferencesEnabled} onChange={(event) => { resetOperation(); setLeagueSchedulePreferencesEnabled(event.target.checked); }} disabled={busy} />Restricciones y preferencias</label>
        <label className={styles.formField}>Motivo<textarea rows={2} value={leagueFlagReason} onChange={(event) => { resetOperation(); setLeagueFlagReason(event.target.value); }} disabled={busy} /></label>
        <button className={styles.primaryButton} type="button" disabled={busy} onClick={() => void run("league_participation_flags.set", null, number(leagueFlags.revision), {
          delegatesEnabled: leagueDelegatesEnabled,
          foundationEnabled: leagueFoundationEnabled,
          publicRegistrationEnabled: leaguePublicRegistrationEnabled,
          reason: leagueFlagReason,
          registrationEnabled: leagueRegistrationEnabled,
          rostersEnabled: leagueRostersEnabled,
          schedulePreferencesEnabled: leagueSchedulePreferencesEnabled,
        })}>Guardar flags R4A</button>
      </section>

      <section className={styles.competitionControl}>
        <h3>Grant de organizador</h3>
        <label className={styles.formField}>Group ID<input value={groupId} onChange={(event) => { resetOperation(); setGroupId(event.target.value); }} placeholder="UUID del equipo" disabled={busy} /></label>
        <label className={styles.formField}>Capacidad<select value={capability} onChange={(event) => { resetOperation(); setCapability(event.target.value); }} disabled={busy}><option value="competition_create">Crear</option><option value="competition_manage">Gestionar</option><option value="competition_staff">Staff</option><option value="competition_rules">Reglamentos</option></select></label>
        <label className={styles.formField}>Caduca<input type="datetime-local" value={expiresAt} onChange={(event) => { resetOperation(); setExpiresAt(event.target.value); }} disabled={busy} /></label>
        <label className={styles.formField}>Motivo<textarea rows={2} value={grantReason} onChange={(event) => { resetOperation(); setGrantReason(event.target.value); }} disabled={busy} /></label>
        <button className={styles.primaryButton} type="button" disabled={busy} onClick={() => void run("entitlement.grant", groupId, organizerRevision(groupId), { capability, expiresAt, reason: grantReason })}>Conceder</button>
      </section>

      <section className={styles.competitionControl}>
        <h3>Registro canónico</h3>
        <p>El backfill enlaza únicamente procedencias demostrables y deja las ambiguas para revisión.</p>
        <label className={styles.formField}>Motivo<textarea rows={2} value={backfillReason} onChange={(event) => { resetOperation(); setBackfillReason(event.target.value); }} disabled={busy} /></label>
        <button className={styles.secondaryButton} type="button" disabled={busy} onClick={() => void run("canonical.backfill", null, number(flags.revision), { reason: backfillReason })}>Ejecutar backfill idempotente</button>
      </section>

      {message ? <p className={styles.competitionControlMessage} role="status">{message}</p> : null}

      {entitlements.filter((item) => text(item.status) === "active" && text(item.organizerKind) === "TEAM").length ? (
        <section className={styles.competitionEntitlementActions}>
          <h3>Revocar grants activos</h3>
          {entitlements.filter((item) => text(item.status) === "active" && text(item.organizerKind) === "TEAM").map((item) => (
            <div key={text(item.id)}>
              <span><strong>{text(item.organizerName)}</strong><small>{text(item.capability)}</small></span>
              <button className={styles.dangerButton} type="button" disabled={busy} onClick={() => {
                const reason = window.prompt("Motivo de revocación");
                if (reason) {
                  resetOperation();
                  void run("entitlement.revoke", text(item.organizerGroupId), number(item.organizerRevision), { entitlementId: text(item.id), reason });
                }
              }}>Revocar</button>
            </div>
          ))}
        </section>
      ) : null}
    </div>
  );
}

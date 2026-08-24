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
  matchOperationsFlags,
  schedulingFlags,
}: {
  canWrite: boolean;
  entitlements: JsonRecord[];
  flags: JsonRecord;
  leagueFlags: JsonRecord;
  matchOperationsFlags: JsonRecord;
  schedulingFlags: JsonRecord;
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
  const [scheduleFoundationEnabled, setScheduleFoundationEnabled] = useState(Boolean(schedulingFlags.foundationEnabled));
  const [scheduleGenerationEnabled, setScheduleGenerationEnabled] = useState(Boolean(schedulingFlags.generationEnabled));
  const [scheduleEditingEnabled, setScheduleEditingEnabled] = useState(Boolean(schedulingFlags.editingEnabled));
  const [schedulePublicationEnabled, setSchedulePublicationEnabled] = useState(Boolean(schedulingFlags.publicationEnabled));
  const [schedulePublicCalendarEnabled, setSchedulePublicCalendarEnabled] = useState(Boolean(schedulingFlags.publicCalendarEnabled));
  const [scheduleCanonicalFixtureCreationEnabled, setScheduleCanonicalFixtureCreationEnabled] = useState(Boolean(schedulingFlags.canonicalFixtureCreationEnabled));
  const [scheduleFlagReason, setScheduleFlagReason] = useState("");
  const [matchOperationsFoundationEnabled, setMatchOperationsFoundationEnabled] = useState(Boolean(matchOperationsFlags.foundationEnabled));
  const [matchSquadsEnabled, setMatchSquadsEnabled] = useState(Boolean(matchOperationsFlags.squadsEnabled));
  const [matchAttendanceEnabled, setMatchAttendanceEnabled] = useState(Boolean(matchOperationsFlags.attendanceEnabled));
  const [sportingResultsEnabled, setSportingResultsEnabled] = useState(Boolean(matchOperationsFlags.sportingResultsEnabled));
  const [resultConfirmationEnabled, setResultConfirmationEnabled] = useState(Boolean(matchOperationsFlags.resultConfirmationEnabled));
  const [officialResultsEnabled, setOfficialResultsEnabled] = useState(Boolean(matchOperationsFlags.officialResultsEnabled));
  const [standingsEnabled, setStandingsEnabled] = useState(Boolean(matchOperationsFlags.standingsEnabled));
  const [publicStandingsEnabled, setPublicStandingsEnabled] = useState(Boolean(matchOperationsFlags.publicStandingsEnabled));
  const [matchOperationsFlagReason, setMatchOperationsFlagReason] = useState("");

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
        <h3>League Scheduling R4B</h3>
        <p>Jornadas, slots y publicación de fixtures canónicos. Requiere R4A activo.</p>
        <label className={styles.checkField}><input type="checkbox" checked={scheduleFoundationEnabled} onChange={(event) => { resetOperation(); setScheduleFoundationEnabled(event.target.checked); }} disabled={busy} />Fundación de calendarios</label>
        <label className={styles.checkField}><input type="checkbox" checked={scheduleGenerationEnabled} onChange={(event) => { resetOperation(); setScheduleGenerationEnabled(event.target.checked); }} disabled={busy} />Generación</label>
        <label className={styles.checkField}><input type="checkbox" checked={scheduleEditingEnabled} onChange={(event) => { resetOperation(); setScheduleEditingEnabled(event.target.checked); }} disabled={busy} />Edición de borradores</label>
        <label className={styles.checkField}><input type="checkbox" checked={schedulePublicationEnabled} onChange={(event) => { resetOperation(); setSchedulePublicationEnabled(event.target.checked); }} disabled={busy} />Publicación</label>
        <label className={styles.checkField}><input type="checkbox" checked={schedulePublicCalendarEnabled} onChange={(event) => { resetOperation(); setSchedulePublicCalendarEnabled(event.target.checked); }} disabled={busy} />Calendario público</label>
        <label className={styles.checkField}><input type="checkbox" checked={scheduleCanonicalFixtureCreationEnabled} onChange={(event) => { resetOperation(); setScheduleCanonicalFixtureCreationEnabled(event.target.checked); }} disabled={busy} />Creación canónica</label>
        <label className={styles.formField}>Motivo<textarea rows={2} value={scheduleFlagReason} onChange={(event) => { resetOperation(); setScheduleFlagReason(event.target.value); }} disabled={busy} /></label>
        <button className={styles.primaryButton} type="button" disabled={busy} onClick={() => void run("league_scheduling_flags.set", null, number(schedulingFlags.revision), {
          canonicalFixtureCreationEnabled: scheduleCanonicalFixtureCreationEnabled,
          editingEnabled: scheduleEditingEnabled,
          foundationEnabled: scheduleFoundationEnabled,
          generationEnabled: scheduleGenerationEnabled,
          publicCalendarEnabled: schedulePublicCalendarEnabled,
          publicationEnabled: schedulePublicationEnabled,
          reason: scheduleFlagReason,
        })}>Guardar flags R4B</button>
      </section>

      <section className={styles.competitionControl}>
        <h3>League Match Operations R4C</h3>
        <p>Convocatorias, asistencia, resultados oficiales y clasificación. Requiere R4A y R4B activos.</p>
        <label className={styles.checkField}><input type="checkbox" checked={matchOperationsFoundationEnabled} onChange={(event) => { resetOperation(); setMatchOperationsFoundationEnabled(event.target.checked); }} disabled={busy} />Fundación operativa</label>
        <label className={styles.checkField}><input type="checkbox" checked={matchSquadsEnabled} onChange={(event) => { resetOperation(); setMatchSquadsEnabled(event.target.checked); }} disabled={busy} />Convocatorias y alineaciones</label>
        <label className={styles.checkField}><input type="checkbox" checked={matchAttendanceEnabled} onChange={(event) => { resetOperation(); setMatchAttendanceEnabled(event.target.checked); }} disabled={busy} />Asistencia</label>
        <label className={styles.checkField}><input type="checkbox" checked={sportingResultsEnabled} onChange={(event) => { resetOperation(); setSportingResultsEnabled(event.target.checked); }} disabled={busy} />Resultados deportivos</label>
        <label className={styles.checkField}><input type="checkbox" checked={resultConfirmationEnabled} onChange={(event) => { resetOperation(); setResultConfirmationEnabled(event.target.checked); }} disabled={busy} />Confirmación bilateral</label>
        <label className={styles.checkField}><input type="checkbox" checked={officialResultsEnabled} onChange={(event) => { resetOperation(); setOfficialResultsEnabled(event.target.checked); }} disabled={busy} />Decisiones oficiales</label>
        <label className={styles.checkField}><input type="checkbox" checked={standingsEnabled} onChange={(event) => { resetOperation(); setStandingsEnabled(event.target.checked); }} disabled={busy} />Clasificación</label>
        <label className={styles.checkField}><input type="checkbox" checked={publicStandingsEnabled} onChange={(event) => { resetOperation(); setPublicStandingsEnabled(event.target.checked); }} disabled={busy} />Clasificación pública</label>
        <label className={styles.formField}>Motivo<textarea rows={2} value={matchOperationsFlagReason} onChange={(event) => { resetOperation(); setMatchOperationsFlagReason(event.target.value); }} disabled={busy} /></label>
        <button className={styles.primaryButton} type="button" disabled={busy} onClick={() => void run("league_match_operations_flags.set", null, number(matchOperationsFlags.revision), {
          attendanceEnabled: matchAttendanceEnabled,
          foundationEnabled: matchOperationsFoundationEnabled,
          officialResultsEnabled,
          publicStandingsEnabled,
          reason: matchOperationsFlagReason,
          resultConfirmationEnabled,
          sportingResultsEnabled,
          squadsEnabled: matchSquadsEnabled,
          standingsEnabled,
        })}>Guardar flags R4C</button>
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

"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { clientWriteFetch } from "../../pwa-client-bridge";
import styles from "../platform-admin.module.css";

type JsonRecord = Record<string, unknown>;
function text(value: unknown) { return typeof value === "string" ? value : ""; }
function number(value: unknown) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }

export function TournamentPrivateBetaAdminClient({ canWrite, flags, grants, groupStage, knockout }: {
  canWrite: boolean;
  flags: JsonRecord;
  grants: JsonRecord[];
  groupStage: JsonRecord;
  knockout: JsonRecord;
}) {
  const router = useRouter();
  const pending = useRef<{ id: string; key: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [reason, setReason] = useState("");
  const [organizerId, setOrganizerId] = useState("");
  const [organizerKind, setOrganizerKind] = useState("TEAM");
  const [organizerRevision, setOrganizerRevision] = useState(0);
  const [maxTeams, setMaxTeams] = useState(32);
  const [foundationEnabled, setFoundationEnabled] = useState(Boolean(flags.foundationEnabled));
  const [privateBetaEnabled, setPrivateBetaEnabled] = useState(Boolean(flags.privateBetaEnabled));
  const [creationEnabled, setCreationEnabled] = useState(Boolean(flags.creationEnabled));
  const [drawEnabled, setDrawEnabled] = useState(Boolean(flags.drawEnabled));
  const [automaticEnabled, setAutomaticEnabled] = useState(Boolean(flags.automaticEnabled));
  const [manualEnabled, setManualEnabled] = useState(Boolean(flags.manualEnabled));
  const [hybridEnabled, setHybridEnabled] = useState(Boolean(flags.hybridEnabled));
  const [publishEnabled, setPublishEnabled] = useState(Boolean(flags.publishEnabled));
  const groupFlags = (groupStage.flags && typeof groupStage.flags === "object" ? groupStage.flags : {}) as JsonRecord;
  const [groupStageEnabled, setGroupStageEnabled] = useState(Boolean(groupFlags.groupStageEnabled));
  const [groupSchedulingEnabled, setGroupSchedulingEnabled] = useState(Boolean(groupFlags.groupSchedulingEnabled));
  const [groupMatchGenerationEnabled, setGroupMatchGenerationEnabled] = useState(Boolean(groupFlags.groupMatchGenerationEnabled));
  const [groupTrackingEnabled, setGroupTrackingEnabled] = useState(Boolean(groupFlags.groupTrackingEnabled));
  const [groupStandingsEnabled, setGroupStandingsEnabled] = useState(Boolean(groupFlags.groupStandingsEnabled));
  const [qualificationEnabled, setQualificationEnabled] = useState(Boolean(groupFlags.qualificationEnabled));
  const [bracketTemplateEnabled, setBracketTemplateEnabled] = useState(Boolean(groupFlags.bracketTemplateEnabled));
  const knockoutFlags = (knockout.flags && typeof knockout.flags === "object" ? knockout.flags : {}) as JsonRecord;
  const [knockoutFoundationEnabled, setKnockoutFoundationEnabled] = useState(Boolean(knockoutFlags.knockoutFoundationEnabled));
  const [knockoutMatchGenerationEnabled, setKnockoutMatchGenerationEnabled] = useState(Boolean(knockoutFlags.knockoutMatchGenerationEnabled));
  const [bracketProgressionEnabled, setBracketProgressionEnabled] = useState(Boolean(knockoutFlags.bracketProgressionEnabled));
  const [extraTimeEnabled, setExtraTimeEnabled] = useState(Boolean(knockoutFlags.extraTimeEnabled));
  const [penaltyShootoutEnabled, setPenaltyShootoutEnabled] = useState(Boolean(knockoutFlags.penaltyShootoutEnabled));
  const [thirdPlaceEnabled, setThirdPlaceEnabled] = useState(Boolean(knockoutFlags.thirdPlaceEnabled));
  const [completionEnabled, setCompletionEnabled] = useState(Boolean(knockoutFlags.completionEnabled));

  async function run(action: string, aggregateId: string | null, expectedRevision: number, payload: JsonRecord) {
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:platform-admin-tournaments", "/api/platform-admin/tournaments", {
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

  if (!canWrite) return <p className={styles.helpText}>Tu rol puede consultar Tournament Private Beta, pero no cambiar gates ni grants.</p>;
  const activeBundles = [...new Map(grants.filter((item) => text(item.status) === "active").map((item) => [text(item.bundleId), item])).values()];
  return <div className={styles.competitionControlGrid}>
    <section className={styles.competitionControl}>
      <h3>Gates de Tournament</h3>
      <p>Descubrimiento público, partidos, bracket y pagos permanecen apagados por contrato.</p>
      <label className={styles.checkField}><input checked={foundationEnabled} disabled={busy} onChange={(event) => setFoundationEnabled(event.target.checked)} type="checkbox" />Foundation</label>
      <label className={styles.checkField}><input checked={privateBetaEnabled} disabled={busy} onChange={(event) => setPrivateBetaEnabled(event.target.checked)} type="checkbox" />Private Beta</label>
      <label className={styles.checkField}><input checked={creationEnabled} disabled={busy} onChange={(event) => setCreationEnabled(event.target.checked)} type="checkbox" />Creación</label>
      <label className={styles.checkField}><input checked={drawEnabled} disabled={busy} onChange={(event) => setDrawEnabled(event.target.checked)} type="checkbox" />Draw Engine</label>
      <label className={styles.checkField}><input checked={automaticEnabled} disabled={busy} onChange={(event) => setAutomaticEnabled(event.target.checked)} type="checkbox" />Automático</label>
      <label className={styles.checkField}><input checked={manualEnabled} disabled={busy} onChange={(event) => setManualEnabled(event.target.checked)} type="checkbox" />Manual asistido</label>
      <label className={styles.checkField}><input checked={hybridEnabled} disabled={busy} onChange={(event) => setHybridEnabled(event.target.checked)} type="checkbox" />Híbrido</label>
      <label className={styles.checkField}><input checked={publishEnabled} disabled={busy} onChange={(event) => setPublishEnabled(event.target.checked)} type="checkbox" />Publicar sorteo</label>
      <label className={styles.formField}>Motivo<textarea rows={2} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
      <button className={styles.primaryButton} disabled={busy || reason.trim().length < 3} onClick={() => void run("tournament.flags.set", null, number(flags.revision), {
        automaticEnabled, creationEnabled, drawEnabled, foundationEnabled, hybridEnabled, manualEnabled,
        privateBetaEnabled, publishEnabled, reason,
      })} type="button">Guardar gates</button>
      <button className={styles.dangerButton} disabled={busy} onClick={() => { const value = window.prompt("Motivo del apagado inmediato"); if (value) void run("tournament.kill_switch", null, number(flags.revision), { reason: value }); }} type="button">Apagado inmediato</button>
    </section>

    <section className={styles.competitionControl}>
      <h3>Group Stage Private Beta</h3>
      <p>Fase de grupos, clasificación y plantilla inicial. Las eliminatorias se gobiernan en su gate independiente.</p>
      <label className={styles.checkField}><input checked={groupStageEnabled} disabled={busy} onChange={(event) => setGroupStageEnabled(event.target.checked)} type="checkbox" />Fase de grupos</label>
      <label className={styles.checkField}><input checked={groupSchedulingEnabled} disabled={busy} onChange={(event) => setGroupSchedulingEnabled(event.target.checked)} type="checkbox" />Jornadas R4B</label>
      <label className={styles.checkField}><input checked={groupMatchGenerationEnabled} disabled={busy} onChange={(event) => setGroupMatchGenerationEnabled(event.target.checked)} type="checkbox" />CanonicalMatches de grupo</label>
      <label className={styles.checkField}><input checked={groupTrackingEnabled} disabled={busy} onChange={(event) => setGroupTrackingEnabled(event.target.checked)} type="checkbox" />Tracking R4C/R4D/R5</label>
      <label className={styles.checkField}><input checked={groupStandingsEnabled} disabled={busy} onChange={(event) => setGroupStandingsEnabled(event.target.checked)} type="checkbox" />Clasificación por grupo</label>
      <label className={styles.checkField}><input checked={qualificationEnabled} disabled={busy} onChange={(event) => setQualificationEnabled(event.target.checked)} type="checkbox" />Qualification</label>
      <label className={styles.checkField}><input checked={bracketTemplateEnabled} disabled={busy} onChange={(event) => setBracketTemplateEnabled(event.target.checked)} type="checkbox" />Plantilla de cuadro</label>
      <label className={styles.formField}>Motivo<textarea rows={2} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
      <button className={styles.primaryButton} disabled={busy || reason.trim().length < 3} onClick={() => void run("tournament.group_stage.flags.set", null, number(groupFlags.revision), {
        bracketTemplateEnabled, groupMatchGenerationEnabled, groupSchedulingEnabled,
        groupStageEnabled, groupStandingsEnabled, groupTrackingEnabled,
        qualificationEnabled, reason,
      })} type="button">Guardar Group Stage</button>
    </section>

    <section className={styles.competitionControl}>
      <h3>Knockout Private Beta</h3>
      <p>Cuadro a partido único. Ida y vuelta, doble eliminación, descubrimiento público y pagos permanecen apagados.</p>
      <label className={styles.checkField}><input checked={knockoutFoundationEnabled} disabled={busy} onChange={(event) => setKnockoutFoundationEnabled(event.target.checked)} type="checkbox" />Fundación del cuadro</label>
      <label className={styles.checkField}><input checked={knockoutMatchGenerationEnabled} disabled={busy} onChange={(event) => setKnockoutMatchGenerationEnabled(event.target.checked)} type="checkbox" />CanonicalMatches knockout</label>
      <label className={styles.checkField}><input checked={bracketProgressionEnabled} disabled={busy} onChange={(event) => setBracketProgressionEnabled(event.target.checked)} type="checkbox" />Progresión</label>
      <label className={styles.checkField}><input checked={extraTimeEnabled} disabled={busy} onChange={(event) => setExtraTimeEnabled(event.target.checked)} type="checkbox" />Prórroga</label>
      <label className={styles.checkField}><input checked={penaltyShootoutEnabled} disabled={busy} onChange={(event) => setPenaltyShootoutEnabled(event.target.checked)} type="checkbox" />Penaltis</label>
      <label className={styles.checkField}><input checked={thirdPlaceEnabled} disabled={busy} onChange={(event) => setThirdPlaceEnabled(event.target.checked)} type="checkbox" />Tercer puesto configurable</label>
      <label className={styles.checkField}><input checked={completionEnabled} disabled={busy} onChange={(event) => setCompletionEnabled(event.target.checked)} type="checkbox" />Campeón y cierre</label>
      <label className={styles.formField}>Motivo<textarea rows={2} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
      <button className={styles.primaryButton} disabled={busy || reason.trim().length < 3} onClick={() => void run("tournament.knockout.flags.set", null, number(knockoutFlags.revision), {
        bracketProgressionEnabled, completionEnabled, extraTimeEnabled,
        knockoutFoundationEnabled, knockoutMatchGenerationEnabled,
        penaltyShootoutEnabled, reason, thirdPlaceEnabled,
      })} type="button">Guardar Knockout</button>
    </section>

    <section className={styles.competitionControl}>
      <h3>Conceder bundle privado</h3>
      <label className={styles.formField}>Organizador<select value={organizerKind} onChange={(event) => setOrganizerKind(event.target.value)}><option>TEAM</option><option>CLUB</option></select></label>
      <label className={styles.formField}>ID<input value={organizerId} onChange={(event) => setOrganizerId(event.target.value)} placeholder="UUID del Team o Club" /></label>
      <label className={styles.formField}>Revisión esperada<input min={0} type="number" value={organizerRevision} onChange={(event) => setOrganizerRevision(Number(event.target.value))} /></label>
      <label className={styles.formField}>Capacidad<input min={4} max={64} type="number" value={maxTeams} onChange={(event) => setMaxTeams(Number(event.target.value))} /></label>
      <label className={styles.formField}>Motivo<textarea rows={2} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
      <button className={styles.primaryButton} disabled={busy || !organizerId || reason.trim().length < 3} onClick={() => void run("tournament.beta_bundle.grant", organizerId, organizerRevision, {
        capacityOverride: maxTeams > 32, maxTeams, organizerKind, reason,
      })} type="button">Conceder 4 capacidades</button>
    </section>

    {activeBundles.map((bundle) => <section className={styles.competitionControl} key={text(bundle.bundleId)}>
      <h3>{text(bundle.organizerKind)} autorizado</h3>
      <p>Máximo {number(bundle.teamCap)} equipos · revisión {number(bundle.organizerRevision)}</p>
      <small>{text(bundle.organizerId)}</small>
      <button className={styles.dangerButton} disabled={busy} onClick={() => { const value = window.prompt("Motivo de revocación"); if (value) void run("tournament.beta_bundle.revoke", text(bundle.organizerId), number(bundle.organizerRevision), { bundleId: text(bundle.bundleId), organizerKind: text(bundle.organizerKind), reason: value }); }} type="button">Revocar bundle</button>
    </section>)}
    {message ? <p className={styles.competitionControlMessage} role="status">{message}</p> : null}
  </div>;
}

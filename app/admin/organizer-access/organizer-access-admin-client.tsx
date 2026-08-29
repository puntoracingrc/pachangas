"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { clientWriteFetch } from "../../pwa-client-bridge";
import {
  organizerAccessArray,
  organizerAccessBoolean,
  organizerAccessDate,
  organizerAccessNumber,
  organizerAccessRecord,
  organizerAccessSettingsAggregateId,
  organizerAccessStatusLabel,
  organizerAccessText,
  organizerAccessTone,
  type OrganizerAccessJson,
  type OrganizerAccessPlatformAction,
} from "../../organizer-access-contract";
import { DataTable, Identifier, Metric, MetricGrid, Panel, StatusBadge } from "../_components/platform-ui";
import styles from "../platform-admin.module.css";

type PendingOperation = { id: string; key: string };

const statuses = ["", "draft", "submitted", "under_review", "needs_information", "approved", "approved_interest", "rejected", "expired", "withdrawn"];
const flagFields = [
  ["applicationsEnabled", "Solicitudes"],
  ["submissionEnabled", "Envío"],
  ["reviewEnabled", "Revisión"],
  ["partnershipApprovalEnabled", "Partnership"],
  ["onboardingEnabled", "Onboarding"],
  ["firstCompetitionLauncherEnabled", "Primer launcher"],
  ["demoWorldV30Enabled", "Demo World V3.0"],
] as const;

function lower(value: unknown) { return organizerAccessText(value).toLocaleLowerCase("es"); }

export function OrganizerAccessAdminClient({ canApprove, canOverride, canReview, canSupport, canonical, health }: {
  canApprove: boolean;
  canOverride: boolean;
  canReview: boolean;
  canSupport: boolean;
  canonical: OrganizerAccessJson;
  health: OrganizerAccessJson;
}) {
  const router = useRouter();
  const applications = organizerAccessArray(canonical.applications);
  const counts = organizerAccessRecord(canonical.counts);
  const initialFlags = organizerAccessRecord(canonical.flags);
  const pending = useRef<PendingOperation | null>(null);
  const [selectedId, setSelectedId] = useState(organizerAccessText(applications[0]?.id));
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [kindFilter, setKindFilter] = useState("");
  const [intentFilter, setIntentFilter] = useState("");
  const [planFilter, setPlanFilter] = useState("");
  const [reviewerFilter, setReviewerFilter] = useState("");
  const [updatedFrom, setUpdatedFrom] = useState("");
  const [updatedTo, setUpdatedTo] = useState("");
  const [reason, setReason] = useState("");
  const [message, setMessage] = useState("");
  const [privateNote, setPrivateNote] = useState("");
  const [decisionCode, setDecisionCode] = useState("ACCESS_APPROVED");
  const [grantPlanCode, setGrantPlanCode] = useState("");
  const [grantSource, setGrantSource] = useState("");
  const [validUntil, setValidUntil] = useState("");
  const [flags, setFlags] = useState(() => Object.fromEntries(flagFields.map(([key]) => [key, organizerAccessBoolean(initialFlags[key])])) as Record<typeof flagFields[number][0], boolean>);
  const [busy, setBusy] = useState(false);
  const [resultMessage, setResultMessage] = useState("");

  const filtered = applications.filter((item) => {
    const haystack = [item.organizerName, item.summary, item.area, item.municipality, item.requestedPlanCode].map(lower).join(" ");
    const updatedAt = Date.parse(organizerAccessText(item.updatedAt));
    const from = updatedFrom ? Date.parse(`${updatedFrom}T00:00:00.000Z`) : Number.NEGATIVE_INFINITY;
    const to = updatedTo ? Date.parse(`${updatedTo}T23:59:59.999Z`) : Number.POSITIVE_INFINITY;
    return (!search.trim() || haystack.includes(search.trim().toLocaleLowerCase("es")))
      && (!statusFilter || organizerAccessText(item.status) === statusFilter)
      && (!kindFilter || organizerAccessText(item.organizerKind) === kindFilter)
      && (!intentFilter || organizerAccessText(item.intent) === intentFilter)
      && (!planFilter || organizerAccessText(item.requestedPlanCode) === planFilter)
      && (!reviewerFilter || lower(item.assignedReviewer).includes(reviewerFilter.trim().toLocaleLowerCase("es")))
      && (Number.isNaN(updatedAt) || (updatedAt >= from && updatedAt <= to));
  });
  const selected = applications.find((item) => organizerAccessText(item.id) === selectedId) ?? filtered[0] ?? null;
  const selectedStatus = organizerAccessText(selected?.status);
  const selectedRevision = organizerAccessNumber(selected?.revision);
  const selectedIdValue = organizerAccessText(selected?.id);
  const selectedPlanCode = organizerAccessText(selected?.requestedPlanCode);
  const plans = [...new Set(applications.map((item) => organizerAccessText(item.requestedPlanCode)).filter(Boolean))].sort();
  const actionReady = reason.trim().length >= 3 && Boolean(selectedIdValue) && !busy;

  async function run(action: OrganizerAccessPlatformAction, aggregateId: string, expectedRevision: number, payload: OrganizerAccessJson) {
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setResultMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:platform-admin-organizer-access", "/api/platform-admin/organizer-access", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" },
        method: "POST",
      });
      const body = organizerAccessRecord(await response.json().catch(() => ({})));
      if (!response.ok) throw new Error(organizerAccessText(body.message, organizerAccessText(body.error, "Operación no confirmada")));
      pending.current = null;
      setResultMessage("Cambio confirmado por PostgreSQL.");
      router.refresh();
    } catch (error) {
      setResultMessage(error instanceof Error ? error.message : "Operación no confirmada");
    } finally {
      setBusy(false);
    }
  }

  function reviewPayload(extra: OrganizerAccessJson = {}) {
    return { message, privateNote, reason, ...extra };
  }

  return <>
    <MetricGrid>
      <Metric label="Nuevas" value={organizerAccessNumber(counts.submitted)} />
      <Metric label="En revisión" value={organizerAccessNumber(counts.underReview)} tone="warning" />
      <Metric label="Piden información" value={organizerAccessNumber(counts.needsInformation)} tone="warning" />
      <Metric label="Aprobadas" value={organizerAccessNumber(counts.approved)} tone="good" />
      <Metric label="Interés" value={organizerAccessNumber(counts.approvedInterest)} />
      <Metric label="Rechazadas" value={organizerAccessNumber(counts.rejected)} tone="danger" />
      <Metric label="Expiradas" value={organizerAccessNumber(counts.expired)} />
      <Metric label="Retiradas" value={organizerAccessNumber(counts.withdrawn)} />
      <Metric label="Integridad" value={organizerAccessNumber(health.orphanApprovedApplications) + organizerAccessNumber(health.interestWithGrant) === 0 ? "OK" : "Revisar"} tone={organizerAccessNumber(health.orphanApprovedApplications) + organizerAccessNumber(health.interestWithGrant) === 0 ? "good" : "danger"} />
    </MetricGrid>

    <Panel title="Banderas Wave 8A">
      <div className={styles.competitionControlGrid}>
        <section className={styles.competitionControl}>
          <h3>Activación escalonada</h3>
          {flagFields.map(([key, label]) => <label className={styles.checkField} key={key}><input checked={flags[key]} disabled={!canOverride || busy} onChange={(event) => setFlags({ ...flags, [key]: event.target.checked })} type="checkbox" />{label}</label>)}
        </section>
        <section className={styles.competitionControl}>
          <h3>Salud canónica</h3>
          <p>{organizerAccessNumber(organizerAccessRecord(health.applications).total)} solicitudes · {organizerAccessNumber(health.activeWorkspaces)} workspaces activos</p>
          <p>{organizerAccessNumber(health.operationReceipts)} recibos idempotentes · {organizerAccessNumber(health.events)} eventos</p>
          <small>Comprobado {organizerAccessDate(health.checkedAt, true)}</small>
        </section>
        <section className={styles.competitionControl}>
          <h3>Confirmación</h3>
          <label className={styles.formField}>Motivo auditable<textarea rows={4} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
          <button className={styles.primaryButton} disabled={!canOverride || reason.trim().length < 3 || busy} onClick={() => void run("settings.flags", organizerAccessSettingsAggregateId, organizerAccessNumber(initialFlags.revision), { ...flags, reason })} type="button">Guardar flags</button>
        </section>
      </div>
    </Panel>

    <Panel title="Cola privada de solicitudes">
      <div className={styles.filterGrid}>
        <label className={styles.formField}>Buscar<input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Organizador, zona o resumen" /></label>
        <label className={styles.formField}>Estado<select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>{statuses.map((status) => <option value={status} key={status || "all"}>{status ? organizerAccessStatusLabel(status) : "Todos"}</option>)}</select></label>
        <label className={styles.formField}>Tipo<select value={kindFilter} onChange={(event) => setKindFilter(event.target.value)}><option value="">Todos</option><option value="CLUB">Club</option><option value="TEAM">Equipo</option></select></label>
        <label className={styles.formField}>Competición<select value={intentFilter} onChange={(event) => setIntentFilter(event.target.value)}><option value="">Todas</option><option value="LEAGUE">Liga</option><option value="TOURNAMENT">Torneo</option><option value="BOTH">Ambas</option></select></label>
        <label className={styles.formField}>Plan<select value={planFilter} onChange={(event) => setPlanFilter(event.target.value)}><option value="">Todos</option>{plans.map((plan) => <option value={plan} key={plan}>{plan}</option>)}</select></label>
        <label className={styles.formField}>Reviewer<input value={reviewerFilter} onChange={(event) => setReviewerFilter(event.target.value)} placeholder="ID asignado" /></label>
        <label className={styles.formField}>Actualizada desde<input type="date" value={updatedFrom} onChange={(event) => setUpdatedFrom(event.target.value)} /></label>
        <label className={styles.formField}>Actualizada hasta<input type="date" value={updatedTo} onChange={(event) => setUpdatedTo(event.target.value)} /></label>
      </div>
      <DataTable label="Solicitudes de acceso de organizador">
        <thead><tr><th>Estado</th><th>Organizador</th><th>Plan</th><th>Intención</th><th>Zona</th><th>Actualizada</th><th /></tr></thead>
        <tbody>{filtered.map((item) => <tr key={organizerAccessText(item.id)}><td><StatusBadge tone={organizerAccessTone(item.status)}>{organizerAccessStatusLabel(item.status)}</StatusBadge></td><td><strong>{organizerAccessText(item.organizerName)}</strong><br /><small>{organizerAccessText(item.organizerKind)}</small></td><td>{organizerAccessText(item.requestedPlanCode)}</td><td>{organizerAccessText(item.intent)}</td><td>{organizerAccessText(item.municipality, organizerAccessText(item.area, "-"))}</td><td>{organizerAccessDate(item.updatedAt, true)}</td><td><button type="button" onClick={() => setSelectedId(organizerAccessText(item.id))}>Revisar</button></td></tr>)}</tbody>
      </DataTable>
    </Panel>

    {selected ? <Panel title={`Revisión · ${organizerAccessText(selected.organizerName)}`}>
      <div className={styles.competitionControlGrid}>
        <section className={styles.competitionControl}>
          <h3>Solicitud</h3>
          <p><StatusBadge tone={organizerAccessTone(selected.status)}>{organizerAccessStatusLabel(selected.status)}</StatusBadge> · revisión {selectedRevision}</p>
          <p>{organizerAccessText(selected.summary, "Sin resumen")}</p>
          <p>{organizerAccessText(selected.municipality, "Sin municipio")} · {organizerAccessText(selected.area, "Sin zona")}</p>
          <p>{organizerAccessNumber(selected.expectedTeamCount)} equipos · {organizerAccessText(selected.expectedCompetitionType)}</p>
          <Identifier value={selectedIdValue} />
        </section>
        <section className={styles.competitionControl}>
          <h3>Plan y acceso</h3>
          <p>{selectedPlanCode} · {organizerAccessText(selected.requestedAccessMode)}</p>
          <p>Owner actual: <Identifier value={organizerAccessText(selected.currentOwnerId)} /></p>
          <p>Reviewer: <Identifier value={organizerAccessText(selected.assignedReviewer)} /></p>
          <p>Grant: <Identifier value={organizerAccessText(organizerAccessRecord(selected.accessGrant).id)} /></p>
          <p>Onboarding: <Identifier value={organizerAccessText(organizerAccessRecord(selected.onboarding).id)} /></p>
          <p>{organizerAccessNumber(selected.otherApplicationCount)} solicitudes relacionadas · {organizerAccessNumber(selected.existingCompetitionCount)} competiciones existentes</p>
        </section>
        <section className={styles.competitionControl}>
          <h3>Decisión y trazabilidad</h3>
          <label className={styles.formField}>Mensaje para solicitante<textarea rows={4} value={message} onChange={(event) => setMessage(event.target.value)} /></label>
          <label className={styles.formField}>Nota privada<textarea rows={4} value={privateNote} onChange={(event) => setPrivateNote(event.target.value)} /></label>
        </section>
      </div>
      <div className={styles.competitionControlGrid}>
        <section className={styles.competitionControl}>
          <h3>Ciclo de revisión</h3>
          <button disabled={!canReview || !actionReady || selectedStatus !== "submitted"} onClick={() => void run("review.start", selectedIdValue, selectedRevision, { reason })} type="button">Comenzar revisión</button>
          <button disabled={!(canReview || canSupport) || !actionReady || selectedStatus !== "under_review" || !message.trim()} onClick={() => void run("review.request_information", selectedIdValue, selectedRevision, reviewPayload())} type="button">Pedir información</button>
          <button disabled={!canReview || !actionReady || !["submitted", "under_review", "needs_information"].includes(selectedStatus)} onClick={() => void run("review.expire", selectedIdValue, selectedRevision, reviewPayload({ decisionCode: decisionCode || "APPLICATION_EXPIRED" }))} type="button">Expirar</button>
        </section>
        <section className={styles.competitionControl}>
          <h3>Aprobar o registrar interés</h3>
          <label className={styles.formField}>Código de decisión<input value={decisionCode} onChange={(event) => setDecisionCode(event.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, ""))} /></label>
          <label className={styles.formField}>Grant<select value={grantSource} onChange={(event) => { const source = event.target.value; setGrantSource(source); setGrantPlanCode(source); }}><option value="">Solo interés, sin grant</option><option value="PARTNERSHIP">Partnership</option><option value="PRIVATE_BETA">Beta privada</option><option value="PROMOTION">Promoción</option><option value="PLATFORM_GRANT">Grant de plataforma</option></select></label>
          <label className={styles.formField}>Plan concedido<input value={grantPlanCode} onChange={(event) => setGrantPlanCode(event.target.value.toUpperCase())} placeholder={selectedPlanCode} /></label>
          <label className={styles.formField}>Válido hasta<input type="datetime-local" value={validUntil} onChange={(event) => setValidUntil(event.target.value)} /></label>
          <button className={styles.primaryButton} disabled={!canApprove || !actionReady || selectedStatus !== "under_review"} onClick={() => void run("review.approve", selectedIdValue, selectedRevision, reviewPayload({ decisionCode, grantPlanCode, grantSource, validUntil }))} type="button">{grantSource ? "Aprobar y conceder" : "Registrar interés"}</button>
        </section>
        <section className={styles.competitionControl}>
          <h3>Rechazo</h3>
          <p>Una única denuncia o preferencia comercial nunca decide por sí sola. La decisión queda inmutable y auditable.</p>
          <button className={styles.dangerButton} disabled={!canReview || !actionReady || !["submitted", "under_review", "needs_information"].includes(selectedStatus)} onClick={() => void run("review.reject", selectedIdValue, selectedRevision, reviewPayload({ decisionCode: decisionCode || "APPLICATION_REJECTED" }))} type="button">Rechazar solicitud</button>
        </section>
      </div>
      <DataTable label="Historial de mensajes de la solicitud">
        <thead><tr><th>Fecha</th><th>Tipo</th><th>Visibilidad</th><th>Mensaje</th></tr></thead>
        <tbody>{organizerAccessArray(selected.messages).map((item) => <tr key={organizerAccessText(item.id)}><td>{organizerAccessDate(item.createdAt, true)}</td><td>{organizerAccessText(item.kind)}</td><td>{organizerAccessText(item.visibility)}</td><td>{organizerAccessText(item.body)}</td></tr>)}</tbody>
      </DataTable>
    </Panel> : null}

    <Panel title="Salud de la cola">
      <MetricGrid>
        <Metric label="Pendientes" value={organizerAccessNumber(organizerAccessRecord(health.applications).pendingReview)} />
        <Metric label="Sin reviewer" value={organizerAccessNumber(organizerAccessRecord(health.applications).withoutReviewer)} tone="warning" />
        <Metric label="Espera máxima" value={`${Math.floor(organizerAccessNumber(organizerAccessRecord(health.applications).oldestPendingSeconds) / 3600)} h`} />
        <Metric label="Grants creados" value={organizerAccessNumber(health.grantsCreated)} tone="good" />
        <Metric label="Duplicados reutilizados" value={organizerAccessNumber(health.duplicateApplicationsReused)} />
        <Metric label="Errores de integridad" value={organizerAccessNumber(health.decisionsMissingExpectedGrant) + organizerAccessNumber(health.applicationGrantsWithoutDecision)} tone={organizerAccessNumber(health.decisionsMissingExpectedGrant) + organizerAccessNumber(health.applicationGrantsWithoutDecision) ? "danger" : "good"} />
      </MetricGrid>
    </Panel>

    {resultMessage ? <p className={styles.adminNotice} role="status">{resultMessage}</p> : null}
  </>;
}

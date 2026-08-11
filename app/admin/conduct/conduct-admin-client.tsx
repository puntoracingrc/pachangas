"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  attendanceOutcomeLabels,
  conductCategoryLabels,
  conductClientMetadata,
  type AttendanceOutcome,
} from "../../conduct-contract";
import styles from "../../conduct.module.css";
import { supabase } from "../../supabaseClient";

type AdminAttendancePlayer = {
  attendance?: {
    currentOutcome: AttendanceOutcome;
    id: string;
    responseState: string;
    revision: number;
    review?: { id: string; revision: number; state: string };
  };
  name: string;
  playerId: string;
  seatKind: string;
  status: string;
};

type AdminAttendanceSnapshot = {
  closure: { revision: number; state: string };
  groupId: string;
  matchId: string;
  matchRevision: number;
  players: AdminAttendancePlayer[];
};

type ModerationCase = {
  activeWindowEndsAt?: string;
  caseReference: string;
  category: string;
  correlatedReporting: boolean;
  correlatedSourceCount: number;
  independentSourceCount: number;
  operationalQueue: TriageQueue;
  priority: string;
  reportCount: number;
  revision: number;
  state: string;
  targetName: string;
  triageDueAt?: string;
  triageReasonCodes: string[];
  triageRecommendation: TriageQueue;
};

type TriageQueue = "urgent_review" | "priority_review" | "review" | "watch" | "record_only";

type QueueSnapshot = {
  cases: ModerationCase[];
  counts: Record<TriageQueue, number>;
  shadowMode: boolean;
  triageEnabled: boolean;
};

const queueLabels: Record<TriageQueue, string> = {
  urgent_review: "Urgente",
  priority_review: "Prioritario",
  review: "Revisión",
  watch: "En observación",
  record_only: "Solo registro",
};

const reasonLabels: Record<string, string> = {
  ACTIVE_WINDOW_EXPIRED: "La señal ya no está dentro de la ventana activa",
  ATTENDANCE_RELIABILITY_SEPARATE: "Fiabilidad de asistencia tratada por separado",
  CATEGORY_DISCRIMINATORY_BEHAVIOR: "Categoría sensible: comportamiento discriminatorio",
  CATEGORY_HARASSMENT: "Categoría sensible: acoso",
  CATEGORY_THREATS_OR_VIOLENCE: "Categoría grave: amenazas o violencia",
  CORRELATED_SOURCE_CLUSTER: "Varias señales proceden de una fuente correlacionada",
  ISOLATED_NON_SERIOUS_SIGNAL: "Señal aislada no grave",
  MUTUAL_RETALIATION: "Posible conflicto o denuncia recíproca",
};

function formatReason(code: string) {
  if (reasonLabels[code]) return reasonLabels[code];
  const independent = code.match(/^INDEPENDENT_SOURCES_(\d+)$/);
  if (independent) return `${independent[1]} equipos o fuentes independientes`;
  const contexts = code.match(/^DISTINCT_CONTEXTS_(\d+)$/);
  if (contexts) return `${contexts[1]} contextos deportivos distintos`;
  if (code === "RECENT_COMPATIBLE_SIGNALS_1") return "1 señal compatible reciente";
  if (code === "RECENT_COMPATIBLE_SIGNALS_2_PLUS") return "2 o más señales compatibles recientes";
  return code.replaceAll("_", " ").toLocaleLowerCase("es");
}

function asRecord(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function normalizeAttendance(value: unknown): AdminAttendanceSnapshot | null {
  const row = asRecord(value);
  if (!row || typeof row.groupId !== "string" || typeof row.matchId !== "string") return null;
  const closure = asRecord(row.closure) ?? {};
  return {
    closure: { revision: Number(closure.revision) || 0, state: typeof closure.state === "string" ? closure.state : "open" },
    groupId: row.groupId,
    matchId: row.matchId,
    matchRevision: Number(row.matchRevision) || 0,
    players: (Array.isArray(row.players) ? row.players : []).flatMap((value) => {
      const player = asRecord(value);
      if (!player || typeof player.playerId !== "string") return [];
      const attendance = asRecord(player.attendance);
      const review = asRecord(attendance?.review);
      return [{
        attendance: attendance && typeof attendance.id === "string" ? {
          currentOutcome: attendance.currentOutcome as AttendanceOutcome,
          id: attendance.id,
          responseState: String(attendance.responseState ?? ""),
          revision: Number(attendance.revision) || 1,
          review: review && typeof review.id === "string" ? {
            id: review.id, revision: Number(review.revision) || 1, state: String(review.state ?? ""),
          } : undefined,
        } : undefined,
        name: String(player.name ?? "Jugador"),
        playerId: player.playerId,
        seatKind: String(player.seatKind ?? "none"),
        status: String(player.status ?? "no"),
      }];
    }),
  };
}

function normalizeQueue(value: unknown): QueueSnapshot {
  const root = asRecord(value) ?? {};
  const countRows = asRecord(root.counts) ?? {};
  const cases = (Array.isArray(root.cases) ? root.cases : Array.isArray(value) ? value : []).flatMap((value) => {
    const row = asRecord(value);
    if (!row || typeof row.caseReference !== "string") return [];
    return [{
      activeWindowEndsAt: typeof row.activeWindowEndsAt === "string" ? row.activeWindowEndsAt : undefined,
      caseReference: row.caseReference,
      category: String(row.category ?? "other"),
      correlatedReporting: Boolean(row.correlatedReporting),
      correlatedSourceCount: Number(row.correlatedSourceCount) || 0,
      independentSourceCount: Number(row.independentSourceCount) || 0,
      operationalQueue: String(row.operationalQueue ?? "review") as TriageQueue,
      priority: String(row.priority ?? "normal"),
      reportCount: Number(row.reportCount) || 0,
      revision: Number(row.revision) || 1,
      state: String(row.state ?? "submitted"),
      targetName: String(row.targetName ?? "Jugador"),
      triageDueAt: typeof row.triageDueAt === "string" ? row.triageDueAt : undefined,
      triageReasonCodes: Array.isArray(row.triageReasonCodes) ? row.triageReasonCodes.map(String) : [],
      triageRecommendation: String(row.triageRecommendation ?? "review") as TriageQueue,
    }];
  });
  return {
    cases,
    counts: {
      urgent_review: Number(countRows.urgent_review) || 0,
      priority_review: Number(countRows.priority_review) || 0,
      review: Number(countRows.review) || 0,
      watch: Number(countRows.watch) || 0,
      record_only: Number(countRows.record_only) || 0,
    },
    shadowMode: Boolean(root.shadowMode),
    triageEnabled: Boolean(root.triageEnabled),
  };
}

export function ConductAdminClient({ canModerate, initialGroupId, initialMatchId }: { canModerate: boolean; initialGroupId: string; initialMatchId: string }) {
  const [groupId, setGroupId] = useState(initialGroupId);
  const [matchId, setMatchId] = useState(initialMatchId);
  const [attendance, setAttendance] = useState<AdminAttendanceSnapshot | null>(null);
  const [outcomes, setOutcomes] = useState<Record<string, AttendanceOutcome>>({});
  const [queue, setQueue] = useState<ModerationCase[]>([]);
  const [queueCounts, setQueueCounts] = useState<QueueSnapshot["counts"]>({ urgent_review: 0, priority_review: 0, review: 0, watch: 0, record_only: 0 });
  const [queueFilter, setQueueFilter] = useState<TriageQueue | "all">("urgent_review");
  const [shadowMode, setShadowMode] = useState(true);
  const [selectedReference, setSelectedReference] = useState("");
  const [evidence, setEvidence] = useState<Record<string, unknown> | null>(null);
  const moderator = canModerate;
  const [note, setNote] = useState("");
  const [duration, setDuration] = useState<"7" | "30" | "90" | "indefinite">("7");
  const [restrictionTypes, setRestrictionTypes] = useState<string[]>(["public_match_access"]);
  const [selectedReportReferences, setSelectedReportReferences] = useState<string[]>([]);
  const [mergeTargetReference, setMergeTargetReference] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const selectedCase = useMemo(() => queue.find((item) => item.caseReference === selectedReference) ?? null, [queue, selectedReference]);

  const loadAttendance = useCallback(async () => {
    if (!supabase || !groupId || !matchId) return;
    const result = await supabase.rpc("get_pachanga_attendance_admin_v1", { target_group_id: groupId, target_match_id: matchId });
    if (result.error) {
      setAttendance(null);
      setMessage(result.error.message);
      return;
    }
    const next = normalizeAttendance(result.data);
    setAttendance(next);
    if (next) setOutcomes(Object.fromEntries(next.players.map((player) => [
      player.playerId,
      player.attendance?.currentOutcome ?? (player.seatKind === "playing" ? "played" : "excused_absence"),
    ])));
  }, [groupId, matchId]);

  const loadQueue = useCallback(async () => {
    if (!supabase || !moderator) return;
    const result = await supabase.rpc("get_pachanga_moderation_queue_v1_1", {
      target_limit: 100,
      target_queue: queueFilter === "all" ? null : queueFilter,
    });
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    const next = normalizeQueue(result.data);
    setQueue(next.cases);
    setQueueCounts(next.counts);
    setShadowMode(next.shadowMode);
    setSelectedReference((current) => current && next.cases.some((item) => item.caseReference === current)
      ? current : next.cases[0]?.caseReference ?? "");
  }, [moderator, queueFilter]);

  useEffect(() => {
    const task = window.setTimeout(() => void loadAttendance(), 0);
    return () => window.clearTimeout(task);
  }, [loadAttendance]);
  useEffect(() => {
    const task = window.setTimeout(() => void loadQueue(), 0);
    return () => window.clearTimeout(task);
  }, [loadQueue]);

  useEffect(() => {
    if (!supabase || !groupId || !matchId) return;
    const client = supabase;
    const channel = client.channel(`attendance-admin-${groupId}-${matchId}`)
      .on("postgres_changes", {
        event: "*", schema: "public", table: "pachanga_attendance_group_state", filter: `group_id=eq.${groupId}`,
      }, () => void loadAttendance())
      .subscribe();
    return () => { void client.removeChannel(channel); };
  }, [groupId, loadAttendance, matchId]);

  useEffect(() => {
    if (!supabase || !selectedReference || !moderator) return;
    const client = supabase;
    const task = window.setTimeout(() => {
      void client.rpc("get_pachanga_moderation_case_evidence_v1_1", { target_case_reference: selectedReference })
        .then((result) => {
          setEvidence(result.error ? null : asRecord(result.data));
          setSelectedReportReferences([]);
        });
    }, 0);
    return () => window.clearTimeout(task);
  }, [moderator, selectedReference]);

  async function closeAttendance() {
    if (!supabase || !attendance || busy) return;
    setBusy(true);
    const result = await supabase.rpc("close_pachanga_post_match_attendance_v1", {
      client_metadata: conductClientMetadata("admin-attendance"),
      expected_revision: attendance.closure.revision,
      operation_id: crypto.randomUUID(),
      target_group_id: attendance.groupId,
      target_match_id: attendance.matchId,
      target_outcomes: attendance.players.map((player) => ({ outcome: outcomes[player.playerId], playerId: player.playerId })),
    });
    setMessage(result.error ? result.error.message : "Asistencia cerrada y confirmada por el servidor.");
    await loadAttendance();
    setBusy(false);
  }

  async function resolveAttendance(player: AdminAttendancePlayer, resolution: "maintain" | "correct" | "escalate") {
    if (!supabase || !player.attendance?.review || busy) return;
    setBusy(true);
    const result = await supabase.rpc("resolve_pachanga_attendance_review_v1", {
      client_metadata: conductClientMetadata("admin-attendance-review"),
      corrected_outcome: resolution === "correct" ? outcomes[player.playerId] : null,
      expected_revision: player.attendance.review.revision,
      next_resolution: resolution,
      operation_id: crypto.randomUUID(),
      resolution_note: note.trim(),
      target_review_id: player.attendance.review.id,
    });
    setMessage(result.error ? result.error.message : "Revisión resuelta por el servidor.");
    await loadAttendance();
    setBusy(false);
  }

  async function moderate(nextAction: string) {
    if (!supabase || !selectedCase || busy) return;
    setBusy(true);
    const result = await supabase.rpc("moderate_pachanga_conduct_case_v1", {
      client_metadata: conductClientMetadata("security-moderation"),
      decision_note: note.trim(),
      duration_days: duration === "indefinite" ? null : Number(duration),
      expected_revision: selectedCase.revision,
      next_action: nextAction,
      operation_id: crypto.randomUUID(),
      restriction_types: restrictionTypes,
      target_case_reference: selectedCase.caseReference,
    });
    setMessage(result.error ? result.error.message : "Decisión registrada con historial inmutable.");
    await loadQueue();
    setBusy(false);
  }

  async function splitCase() {
    if (!supabase || !selectedCase || busy || !selectedReportReferences.length) return;
    setBusy(true);
    const result = await supabase.rpc("split_pachanga_conduct_case_v1_1", {
      client_metadata: conductClientMetadata("security-triage-split"),
      expected_revision: selectedCase.revision,
      operation_id: crypto.randomUUID(),
      report_references: selectedReportReferences,
      source_case_reference: selectedCase.caseReference,
    });
    setMessage(result.error ? result.error.message : "Las evidencias se han separado con trazabilidad completa.");
    await loadQueue();
    setBusy(false);
  }

  async function mergeCase() {
    if (!supabase || !selectedCase || busy || !mergeTargetReference.trim()) return;
    const target = queue.find((item) => item.caseReference === mergeTargetReference.trim());
    if (!target) {
      setMessage("El caso de destino debe estar visible en la cola actual.");
      return;
    }
    setBusy(true);
    const result = await supabase.rpc("merge_pachanga_conduct_cases_v1_1", {
      client_metadata: conductClientMetadata("security-triage-merge"),
      expected_source_revision: selectedCase.revision,
      expected_target_revision: target.revision,
      operation_id: crypto.randomUUID(),
      source_case_reference: selectedCase.caseReference,
      target_case_reference: target.caseReference,
    });
    setMessage(result.error ? result.error.message : "Los casos se han unido conservando toda la evidencia.");
    setMergeTargetReference("");
    await loadQueue();
    setBusy(false);
  }

  return (
    <>
      {message ? <p className={styles.message} role="status">{message}</p> : null}
      <section className={styles.panel}>
        <h2>Cierre posterior de asistencia</h2>
        <form className={styles.form} onSubmit={(event) => { event.preventDefault(); void loadAttendance(); }}>
          <label>Grupo<input value={groupId} onChange={(event) => setGroupId(event.target.value)} /></label>
          <label>Partido<input value={matchId} onChange={(event) => setMatchId(event.target.value)} /></label>
          <button type="submit">Cargar partido</button>
        </form>
        {attendance ? (
          <div className={styles.list}>
            {attendance.players.map((player) => (
              <article className={styles.item} key={player.playerId}>
                <header><strong>{player.name}</strong><small>{player.status} · {player.seatKind}</small></header>
                <select value={outcomes[player.playerId]} disabled={attendance.closure.state === "closed" && !player.attendance?.review} onChange={(event) => setOutcomes((current) => ({ ...current, [player.playerId]: event.target.value as AttendanceOutcome }))}>
                  {Object.entries(attendanceOutcomeLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
                {player.attendance?.review?.state === "submitted" ? (
                  <div className={styles.actions}>
                    <button type="button" disabled={busy} onClick={() => void resolveAttendance(player, "maintain")}>Mantener</button>
                    <button type="button" disabled={busy} onClick={() => void resolveAttendance(player, "correct")}>Corregir</button>
                    <button className={styles.buttonSecondary} type="button" disabled={busy} onClick={() => void resolveAttendance(player, "escalate")}>Escalar</button>
                  </div>
                ) : null}
              </article>
            ))}
            {attendance.closure.state !== "closed" ? <div className={styles.actions}><button type="button" disabled={busy} onClick={() => void closeAttendance()}>Cerrar asistencia</button></div> : null}
          </div>
        ) : null}
      </section>

      {moderator ? (
        <div className={styles.moderationGrid}>
          <section className={styles.panel}>
            <div className={styles.sectionHeading}>
              <div><h2>Cola privada</h2><small>{shadowMode ? "Modo sombra: V1 sigue revisando todos los casos" : "Triage operativo"}</small></div>
            </div>
            <div className={styles.queueTabs} role="tablist" aria-label="Colas de moderación">
              {(Object.keys(queueLabels) as TriageQueue[]).map((value) => (
                <button aria-selected={queueFilter === value} className={styles.queueTab} data-active={queueFilter === value} key={value} onClick={() => setQueueFilter(value)} role="tab" type="button">
                  <span>{queueLabels[value]}</span><b>{queueCounts[value]}</b>
                </button>
              ))}
              <button aria-selected={queueFilter === "all"} className={styles.queueTab} data-active={queueFilter === "all"} onClick={() => setQueueFilter("all")} role="tab" type="button"><span>Todos</span><b>{Object.values(queueCounts).reduce((sum, count) => sum + count, 0)}</b></button>
            </div>
            <div className={styles.list}>
              {queue.map((item) => (
                <button className={styles.caseButton} data-active={item.caseReference === selectedReference} key={item.caseReference} type="button" onClick={() => setSelectedReference(item.caseReference)}>
                  <strong>{item.targetName} · {conductCategoryLabels[item.category] ?? item.category}</strong>
                  <span>{queueLabels[item.triageRecommendation]} · {item.state} · {item.independentSourceCount} fuentes independientes</span>
                </button>
              ))}
              {!queue.length ? <p className={styles.empty}>No hay casos pendientes.</p> : null}
            </div>
          </section>
          <section className={styles.panel}>
            <h2>Evidencia y decisión</h2>
            {selectedCase ? (
              <>
                <div className={styles.triageSummary}>
                  <strong>{queueLabels[selectedCase.triageRecommendation]}</strong>
                  <span>{selectedCase.reportCount} reportes · {selectedCase.independentSourceCount} fuentes independientes · {selectedCase.correlatedSourceCount} correlacionadas</span>
                  {shadowMode ? <small>Cola efectiva V1: {queueLabels[selectedCase.operationalQueue]}</small> : null}
                  <ul>{selectedCase.triageReasonCodes.map((reason) => <li key={reason}>{formatReason(reason)}</li>)}</ul>
                </div>
                <div className={styles.evidenceList}>
                  {(Array.isArray(evidence?.reports) ? evidence.reports : []).map((raw) => {
                    const report = asRecord(raw);
                    const reference = String(report?.reportReference ?? "");
                    if (!reference) return null;
                    return (
                      <label className={styles.evidenceItem} key={reference}>
                        <input checked={selectedReportReferences.includes(reference)} onChange={(event) => setSelectedReportReferences((current) => event.target.checked ? [...current, reference] : current.filter((value) => value !== reference))} type="checkbox" />
                        <span><strong>{String(report?.contextKind ?? "contexto")}</strong><small>{String(report?.contextId ?? "")} · {new Date(String(report?.createdAt ?? "")).toLocaleDateString("es-ES")}</small><em>{String(report?.description ?? "Sin texto adicional")}</em></span>
                      </label>
                    );
                  })}
                </div>
                <div className={styles.caseTools}>
                  <button className={styles.buttonSecondary} disabled={busy || !selectedReportReferences.length || selectedReportReferences.length >= selectedCase.reportCount} onClick={() => void splitCase()} type="button">Separar evidencias</button>
                  <label>Caso de destino<input placeholder="Referencia opaca" value={mergeTargetReference} onChange={(event) => setMergeTargetReference(event.target.value)} /></label>
                  <button className={styles.buttonSecondary} disabled={busy || !mergeTargetReference.trim()} onClick={() => void mergeCase()} type="button">Unir casos compatibles</button>
                </div>
                <div className={styles.form}>
                  <label>Motivo de la decisión<textarea maxLength={500} value={note} onChange={(event) => setNote(event.target.value)} /></label>
                  <label>Duración<select value={duration} onChange={(event) => setDuration(event.target.value as typeof duration)}><option value="7">7 días</option><option value="30">30 días</option><option value="90">90 días</option><option value="indefinite">Indefinida</option></select></label>
                  <label>Limitaciones<select multiple value={restrictionTypes} onChange={(event) => setRestrictionTypes(Array.from(event.target.selectedOptions, (option) => option.value))}><option value="public_market">Mercado público</option><option value="send_challenges">Enviar retos</option><option value="receive_public_challenges">Recibir retos públicos</option><option value="public_match_access">Partidos públicos</option><option value="public_guest_access">Acceso como invitado</option></select></label>
                </div>
                <div className={styles.actions}>
                  <button type="button" disabled={busy} onClick={() => void moderate("start_review")}>Revisar</button>
                  <button type="button" disabled={busy} onClick={() => void moderate("confirm")}>Confirmar</button>
                  <button type="button" disabled={busy} onClick={() => void moderate("issue_warning")}>Avisar</button>
                  <button type="button" disabled={busy} onClick={() => void moderate("apply_restrictions")}>Restringir</button>
                  <button className={styles.buttonSecondary} type="button" disabled={busy} onClick={() => void moderate("dismiss")}>Descartar</button>
                  <button className={styles.buttonSecondary} type="button" disabled={busy} onClick={() => void moderate("correct")}>Corregir</button>
                </div>
              </>
            ) : <p className={styles.empty}>Selecciona un caso.</p>}
          </section>
        </div>
      ) : null}
    </>
  );
}

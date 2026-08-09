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
  caseReference: string;
  category: string;
  correlatedReporting: boolean;
  correlatedSourceCount: number;
  independentSourceCount: number;
  priority: string;
  reportCount: number;
  revision: number;
  state: string;
  targetName: string;
};

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

function normalizeQueue(value: unknown): ModerationCase[] {
  return (Array.isArray(value) ? value : []).flatMap((value) => {
    const row = asRecord(value);
    if (!row || typeof row.caseReference !== "string") return [];
    return [{
      caseReference: row.caseReference,
      category: String(row.category ?? "other"),
      correlatedReporting: Boolean(row.correlatedReporting),
      correlatedSourceCount: Number(row.correlatedSourceCount) || 0,
      independentSourceCount: Number(row.independentSourceCount) || 0,
      priority: String(row.priority ?? "normal"),
      reportCount: Number(row.reportCount) || 0,
      revision: Number(row.revision) || 1,
      state: String(row.state ?? "submitted"),
      targetName: String(row.targetName ?? "Jugador"),
    }];
  });
}

export function ConductAdminClient({ initialGroupId, initialMatchId }: { initialGroupId: string; initialMatchId: string }) {
  const [groupId, setGroupId] = useState(initialGroupId);
  const [matchId, setMatchId] = useState(initialMatchId);
  const [attendance, setAttendance] = useState<AdminAttendanceSnapshot | null>(null);
  const [outcomes, setOutcomes] = useState<Record<string, AttendanceOutcome>>({});
  const [queue, setQueue] = useState<ModerationCase[]>([]);
  const [selectedReference, setSelectedReference] = useState("");
  const [evidence, setEvidence] = useState<Record<string, unknown> | null>(null);
  const [moderator, setModerator] = useState(false);
  const [note, setNote] = useState("");
  const [duration, setDuration] = useState<"7" | "30" | "90" | "indefinite">("7");
  const [restrictionTypes, setRestrictionTypes] = useState<string[]>(["public_match_access"]);
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
    const result = await supabase.rpc("get_pachanga_moderation_queue_v1", { target_limit: 100 });
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    const next = normalizeQueue(result.data);
    setQueue(next);
    setSelectedReference((current) => current && next.some((item) => item.caseReference === current)
      ? current : next[0]?.caseReference ?? "");
  }, [moderator]);

  useEffect(() => {
    if (!supabase) return;
    void supabase.auth.getSession().then(({ data }) => {
      const role = String(data.session?.user.app_metadata?.pachangas_security_role ?? "");
      setModerator(role === "moderator" || role === "security_admin");
    });
  }, []);

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
      void client.rpc("get_pachanga_moderation_case_evidence_v1", { target_case_reference: selectedReference })
        .then((result) => setEvidence(result.error ? null : asRecord(result.data)));
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
            <h2>Cola privada</h2>
            <div className={styles.list}>
              {queue.map((item) => (
                <button className={styles.caseButton} data-active={item.caseReference === selectedReference} key={item.caseReference} type="button" onClick={() => setSelectedReference(item.caseReference)}>
                  <strong>{item.targetName} · {conductCategoryLabels[item.category] ?? item.category}</strong>
                  <span>{item.priority} · {item.state} · {item.independentSourceCount} fuentes independientes</span>
                </button>
              ))}
              {!queue.length ? <p className={styles.empty}>No hay casos pendientes.</p> : null}
            </div>
          </section>
          <section className={styles.panel}>
            <h2>Evidencia y decisión</h2>
            {selectedCase ? (
              <>
                <p>{selectedCase.reportCount} reportes; {selectedCase.correlatedSourceCount} señales correlacionadas.</p>
                <pre>{JSON.stringify(evidence?.reports ?? [], null, 2)}</pre>
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

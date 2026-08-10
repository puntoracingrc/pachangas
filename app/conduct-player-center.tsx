"use client";

import { useCallback, useEffect, useState } from "react";
import {
  attendanceOutcomeLabels,
  conductCategoryLabels,
  conductClientMetadata,
  normalizeMyConductSnapshot,
  type ConductAction,
  type MyConductSnapshot,
} from "./conduct-contract";
import styles from "./conduct.module.css";
import { supabase } from "./supabaseClient";

function actionLabel(action: ConductAction) {
  return action.type?.replaceAll("_", " ") ?? conductCategoryLabels[action.category ?? ""] ?? action.category ?? "Medida social";
}

export function ConductPlayerCenter() {
  const [snapshot, setSnapshot] = useState<MyConductSnapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState("");

  const load = useCallback(async () => {
    if (!supabase) {
      setLoading(false);
      setMessage("La conexión central no está configurada.");
      return;
    }
    const session = await supabase.auth.getSession();
    if (!session.data.session?.user) {
      setLoading(false);
      setMessage("Inicia sesión para consultar tus avisos de conducta.");
      return;
    }
    const result = await supabase.rpc("get_pachanga_my_conduct_v1");
    setLoading(false);
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    setMessage("");
    setSnapshot(normalizeMyConductSnapshot(result.data));
  }, []);

  useEffect(() => {
    const client = supabase;
    const initialLoad = window.setTimeout(() => void load(), 0);
    if (!client) return () => window.clearTimeout(initialLoad);
    let channel: ReturnType<typeof client.channel> | null = null;
    let disposed = false;
    void client.auth.getSession().then(({ data }) => {
      const userId = data.session?.user.id;
      if (!userId || disposed) return;
      channel = client.channel(`conduct-subject-${userId}`)
        .on("postgres_changes", {
          event: "*", schema: "public", table: "pachanga_conduct_subject_state", filter: `user_id=eq.${userId}`,
        }, () => void load())
        .subscribe();
    });
    return () => {
      window.clearTimeout(initialLoad);
      disposed = true;
      if (channel) void client.removeChannel(channel);
    };
  }, [load]);

  async function respondAttendance(id: string, revision: number, nextResponse: "agree" | "dispute") {
    if (!supabase || busy) return;
    const responseNote = nextResponse === "dispute"
      ? window.prompt("Explica brevemente qué debe revisar el equipo (máximo 500 caracteres).", "")?.trim()
      : "";
    if (nextResponse === "dispute" && !responseNote) return;
    setBusy(id);
    setMessage("");
    const result = await supabase.rpc("respond_pachanga_post_match_attendance_v1", {
      client_metadata: conductClientMetadata("profile-conduct"),
      expected_revision: revision,
      next_response: nextResponse,
      operation_id: crypto.randomUUID(),
      response_note: responseNote ?? "",
      target_attendance_id: id,
    });
    setMessage(result.error ? result.error.message : "Respuesta confirmada por el servidor.");
    await load();
    setBusy(null);
  }

  async function appeal(action: ConductAction, actionKind: "warning" | "restriction") {
    if (!supabase || busy) return;
    const explanation = window.prompt("Explica el motivo de la apelación (máximo 500 caracteres).", "")?.trim();
    if (!explanation) return;
    setBusy(action.reference);
    setMessage("");
    const result = await supabase.rpc("appeal_pachanga_conduct_action_v1", {
      action_kind: actionKind,
      action_reference: action.reference,
      client_metadata: conductClientMetadata("profile-conduct"),
      expected_revision: action.revision,
      explanation,
      operation_id: crypto.randomUUID(),
    });
    setMessage(result.error ? result.error.message : "Apelación enviada para revisión.");
    await load();
    setBusy(null);
  }

  if (loading) return <p className={styles.message}>Cargando estado confirmado...</p>;

  return (
    <>
      {message ? <p className={styles.message} role="status">{message}</p> : null}
      <div className={styles.grid}>
        <section className={`${styles.panel} ${styles.panelWide}`}>
          <h2>Asistencia posterior al partido</h2>
          <div className={styles.list}>
            {snapshot?.attendance.map((fact) => (
              <article className={styles.item} data-tone={fact.currentOutcome === "unexcused_no_show" ? "critical" : fact.currentOutcome === "late_cancellation" ? "warning" : "normal"} key={fact.id}>
                <header><strong>{attendanceOutcomeLabels[fact.currentOutcome] ?? fact.currentOutcome}</strong><small>{fact.matchId}</small></header>
                <p>Estado: {fact.responseState.replaceAll("_", " ")}. Esta información no modifica tu nivel deportivo.</p>
                {fact.responseState === "pending" ? (
                  <div className={styles.actions}>
                    <button type="button" disabled={busy === fact.id} onClick={() => void respondAttendance(fact.id, fact.revision, "agree")}>De acuerdo</button>
                    <button className={styles.buttonSecondary} type="button" disabled={busy === fact.id} onClick={() => void respondAttendance(fact.id, fact.revision, "dispute")}>No estoy de acuerdo</button>
                  </div>
                ) : null}
              </article>
            ))}
            {!snapshot?.attendance.length ? <p className={styles.empty}>No tienes cierres de asistencia.</p> : null}
          </div>
        </section>

        <section className={styles.panel}>
          <h2>Avisos administrativos</h2>
          <div className={styles.list}>
            {snapshot?.warnings.map((warning) => (
              <article className={styles.item} data-tone="warning" key={warning.reference}>
                <header><strong>{actionLabel(warning)}</strong><small>{warning.state}</small></header>
                {warning.state === "active" ? <div className={styles.actions}><button type="button" disabled={busy === warning.reference} onClick={() => void appeal(warning, "warning")}>Apelar</button></div> : null}
              </article>
            ))}
            {!snapshot?.warnings.length ? <p className={styles.empty}>No tienes avisos.</p> : null}
          </div>
        </section>

        <section className={styles.panel}>
          <h2>Limitaciones sociales</h2>
          <div className={styles.list}>
            {snapshot?.restrictions.map((restriction) => (
              <article className={styles.item} data-tone="critical" key={restriction.reference}>
                <header><strong>{actionLabel(restriction)}</strong><small>{restriction.state}</small></header>
                {restriction.effectiveUntil ? <p>Hasta {new Date(restriction.effectiveUntil).toLocaleDateString("es-ES")}</p> : <p>Sin fecha automática de fin.</p>}
                {restriction.state === "active" ? <div className={styles.actions}><button type="button" disabled={busy === restriction.reference} onClick={() => void appeal(restriction, "restriction")}>Apelar</button></div> : null}
              </article>
            ))}
            {!snapshot?.restrictions.length ? <p className={styles.empty}>No tienes limitaciones sociales.</p> : null}
          </div>
        </section>

        <section className={styles.panel}>
          <h2>Reportes enviados</h2>
          <div className={styles.list}>
            {snapshot?.submittedReports.map((report) => (
              <article className={styles.item} key={report.reference}>
                <header><strong>{conductCategoryLabels[report.category] ?? report.category}</strong><small>{report.state}</small></header>
                <p>{report.contextKind.replaceAll("_", " ")} · {report.contextId}</p>
              </article>
            ))}
            {!snapshot?.submittedReports.length ? <p className={styles.empty}>No has enviado reportes.</p> : null}
          </div>
        </section>

        <section className={styles.panel}>
          <h2>Privacidad</h2>
          <p>Los reportes son privados. Solo moderación interna puede conocer la identidad del informante. Ningún aviso o limitación modifica facetas, GRL ni ranking deportivo.</p>
        </section>
      </div>
    </>
  );
}

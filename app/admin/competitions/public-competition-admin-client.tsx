"use client";

import Link from "next/link";
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { clientWriteFetch } from "../../pwa-client-bridge";
import styles from "../platform-admin.module.css";

type JsonRecord = Record<string, unknown>;
function text(value: unknown) { return typeof value === "string" ? value : ""; }
function number(value: unknown) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }

const safeFlagLabels: Array<[string, string]> = [
  ["foundation", "Foundation"], ["publication", "Publicación"], ["discovery", "Discovery"],
  ["registrationRequests", "Solicitudes"], ["waitlist", "Lista de espera"],
  ["calendar", "Calendario"], ["results", "Resultados"], ["standings", "Clasificación"],
  ["bracket", "Cuadro"], ["exceptionStatus", "Estado de incidencias"], ["referees", "Árbitros"],
];

function actionsForStatus(status: string) {
  if (status === "pending_review") return ["publication.approve", "publication.request_changes", "publication.reject"];
  if (status === "approved") return ["publication.publish"];
  if (status === "published") return ["publication.organizer.verify", "publication.suspend", "publication.archive"];
  if (status === "suspended") return ["publication.restore", "publication.archive"];
  if (["draft", "rejected", "changes_requested"].includes(status)) return ["publication.archive"];
  return [];
}

const actionLabels: Record<string, string> = {
  "publication.approve": "Aprobar", "publication.archive": "Archivar",
  "publication.organizer.verify": "Verificar organizador", "publication.publish": "Publicar",
  "publication.reject": "Rechazar", "publication.request_changes": "Pedir cambios",
  "publication.restore": "Restaurar", "publication.suspend": "Suspender",
  "report.dismiss": "Descartar", "report.resolve": "Resolver", "report.review": "Revisar",
};

export function PublicCompetitionAdminClient({ canManage, canModerate, canWriteFlags, data }: {
  canManage: boolean;
  canModerate: boolean;
  canWriteFlags: boolean;
  data: { flags: JsonRecord; publications: JsonRecord[]; reports: JsonRecord[] };
}) {
  const router = useRouter();
  const pending = useRef<{ id: string; key: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [reason, setReason] = useState("");
  const [flags, setFlags] = useState<Record<string, boolean>>(Object.fromEntries(safeFlagLabels.map(([key]) => [key, Boolean(data.flags[key])])));

  async function run(action: string, aggregateId: string, expectedRevision: number, payload: JsonRecord) {
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true); setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:platform-admin-public-competitions", "/api/platform-admin/public-competitions", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" },
        method: "POST",
      });
      const body = await response.json() as { error?: string; message?: string };
      if (!response.ok) throw new Error(body.message || body.error || "Operación no confirmada");
      pending.current = null; setMessage("Cambio confirmado por PostgreSQL."); setReason("");
      router.refresh();
    } catch (error) { setMessage(error instanceof Error ? error.message : "Operación no confirmada"); }
    finally { setBusy(false); }
  }

  return <div className={styles.competitionControlGrid}>
    <section className={styles.competitionControl}>
      <h3>Gates públicos</h3>
      <p>Activación progresiva. Disciplina, autoaceptación, pagos y formatos futuros permanecen fuera de alcance.</p>
      {safeFlagLabels.map(([key, label]) => <label className={styles.checkField} key={key}><input checked={flags[key] ?? false} disabled={busy || !canWriteFlags} onChange={(event) => setFlags((current) => ({ ...current, [key]: event.target.checked }))} type="checkbox" />{label}</label>)}
      <label className={styles.checkField}><input checked={false} disabled type="checkbox" />Disciplina (OFF contractual)</label>
      <label className={styles.checkField}><input checked={false} disabled type="checkbox" />Autoaceptación (OFF contractual)</label>
      <label className={styles.formField}>Motivo<textarea rows={2} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
      <button className={styles.primaryButton} disabled={busy || !canWriteFlags || reason.trim().length < 3} onClick={() => void run("flags.set", "singleton", number(data.flags.revision), { patch: flags, reason })} type="button">Guardar gates</button>
    </section>

    {data.publications.map((publication) => {
      const status = text(publication.status);
      const privacy = publication.privacy && typeof publication.privacy === "object" ? publication.privacy as JsonRecord : {};
      return <section className={styles.competitionControl} key={text(publication.id)}>
        <h3>{text(publication.slug) || "Publicación sin slug"}</h3>
        <p>{status.replaceAll("_", " ")} · revisión {number(publication.revision)} · secuencia {number(publication.serverSequence)}</p>
        <small>Privacidad: roster {String(Boolean(privacy.containsRoster))} · asistencia {String(Boolean(privacy.containsAttendance))} · contacto {String(Boolean(privacy.containsContactData))}</small>
        {status === "published" ? <Link href={`/competiciones/${text(publication.slug)}`}>Abrir hub público</Link> : null}
        {canManage ? <div className={styles.inlineActions}>{actionsForStatus(status).map((action) => {
          const needsReason = ["publication.reject", "publication.request_changes", "publication.suspend", "publication.archive"].includes(action);
          return <button className={action === "publication.suspend" || action === "publication.archive" || action === "publication.reject" ? styles.dangerButton : styles.secondaryButton} disabled={busy || (needsReason && reason.trim().length < 3)} key={action} onClick={() => void run(action, text(publication.id), number(publication.revision), { publicReason: reason, reason: reason || action })} type="button">{actionLabels[action]}</button>;
        })}</div> : null}
      </section>;
    })}

    {data.reports.map((report) => <section className={styles.competitionControl} key={text(report.id)}>
      <h3>Reporte {text(report.opaqueReference)}</h3>
      <p>{text(report.category)} · {text(report.status).replaceAll("_", " ")} · revisión {number(report.revision)}</p>
      <small>{text(report.summary)}</small>
      {canModerate ? <div className={styles.inlineActions}>{(text(report.status) === "submitted" ? ["report.review", "report.resolve", "report.dismiss"] : text(report.status) === "under_review" ? ["report.resolve", "report.dismiss"] : []).map((action) => <button className={action === "report.dismiss" ? styles.dangerButton : styles.secondaryButton} disabled={busy || (action !== "report.review" && reason.trim().length < 3)} key={action} onClick={() => void run(action, text(report.id), number(report.revision), { publicReason: reason, reason: reason || action })} type="button">{actionLabels[action]}</button>)}</div> : null}
    </section>)}
    {message ? <p className={styles.competitionControlMessage} role="status">{message}</p> : null}
  </div>;
}

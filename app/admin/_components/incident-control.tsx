"use client";

import { useRef, useState } from "react";
import styles from "../platform-admin.module.css";

export function IncidentControl({ fingerprint, revision, state }: { fingerprint: string; revision: number; state: string }) {
  const [open, setOpen] = useState(false);
  const [nextState, setNextState] = useState(state);
  const [note, setNote] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const pendingOperationId = useRef<string | null>(null);
  async function save() {
    if (reason.trim().length < 3) { setMessage("Escribe un motivo."); return; }
    setBusy(true); setMessage("");
    try {
      pendingOperationId.current ??= crypto.randomUUID();
      const response = await fetch("/api/platform-admin/incidents", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" },
        body: JSON.stringify({ expectedRevision: revision, fingerprint, note, operationId: pendingOperationId.current, reason: reason.trim(), state: nextState }),
      });
      const body = await response.json() as { error?: string; message?: string };
      if (!response.ok) throw new Error(body.message || body.error || "No se pudo actualizar la incidencia");
      pendingOperationId.current = null;
      window.location.reload();
    } catch (error) { setMessage(error instanceof Error ? error.message : "No se pudo actualizar"); setBusy(false); }
  }
  if (!open) return <button className={styles.secondaryButton} type="button" onClick={() => setOpen(true)}>Gestionar</button>;
  return <div className={styles.inlineAction}><label className={styles.formField}>Estado<select value={nextState} onChange={(event) => { pendingOperationId.current = null; setNextState(event.target.value); }} disabled={busy}><option value="new">Nuevo</option><option value="investigating">Investigando</option><option value="resolved">Resuelto</option><option value="ignored">Ignorado</option></select></label><label className={styles.formField}>Nota<textarea rows={2} maxLength={1200} value={note} onChange={(event) => { pendingOperationId.current = null; setNote(event.target.value); }} disabled={busy} /></label><label className={styles.formField}>Motivo<textarea rows={2} maxLength={1200} value={reason} onChange={(event) => { pendingOperationId.current = null; setReason(event.target.value); }} disabled={busy} /></label><div className={styles.inlineButtons}><button className={styles.primaryButton} type="button" onClick={() => void save()} disabled={busy}>Guardar</button><button className={styles.secondaryButton} type="button" onClick={() => setOpen(false)} disabled={busy}>Cancelar</button></div>{message ? <p className={styles.formMessage} role="alert">{message}</p> : null}</div>;
}

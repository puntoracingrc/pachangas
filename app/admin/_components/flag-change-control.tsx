"use client";

import { useRef, useState } from "react";
import styles from "../platform-admin.module.css";

export function FlagChangeControl({ enabled, flagKey, revision }: { enabled: boolean; flagKey: string; revision: number }) {
  const [open, setOpen] = useState(false);
  const [nextEnabled, setNextEnabled] = useState(!enabled);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const pendingOperationId = useRef<string | null>(null);

  async function submit() {
    if (reason.trim().length < 3) { setMessage("Escribe un motivo operativo."); return; }
    if (!window.confirm(`Confirma cambiar ${flagKey} a ${nextEnabled ? "ACTIVO" : "INACTIVO"}.`)) return;
    setBusy(true);
    setMessage("");
    try {
      pendingOperationId.current ??= crypto.randomUUID();
      const response = await fetch("/api/platform-admin/flags", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" },
        body: JSON.stringify({ enabled: nextEnabled, expectedRevision: revision, flagKey, operationId: pendingOperationId.current, reason: reason.trim() }),
      });
      const body = await response.json() as { error?: string; message?: string };
      if (!response.ok) throw new Error(body.message || body.error || "No se pudo cambiar el flag");
      pendingOperationId.current = null;
      window.location.reload();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo cambiar el flag");
      setBusy(false);
    }
  }

  if (!open) return <button className={styles.secondaryButton} type="button" onClick={() => setOpen(true)}>Cambiar</button>;
  return (
    <div className={styles.inlineAction}>
      <strong>Impacto: cambia comportamiento de producto para todos los flujos afectados.</strong>
      <label className={styles.formField}>Nuevo valor<select value={nextEnabled ? "on" : "off"} onChange={(event) => { pendingOperationId.current = null; setNextEnabled(event.target.value === "on"); }} disabled={busy}><option value="on">Activo</option><option value="off">Inactivo</option></select></label>
      <label className={styles.formField}>Motivo<textarea rows={2} maxLength={1200} value={reason} onChange={(event) => { pendingOperationId.current = null; setReason(event.target.value); }} disabled={busy} /></label>
      <div className={styles.inlineButtons}><button className={styles.primaryButton} type="button" onClick={() => void submit()} disabled={busy}>{busy ? "Confirmando..." : "Confirmar"}</button><button className={styles.secondaryButton} type="button" onClick={() => setOpen(false)} disabled={busy}>Cancelar</button></div>
      {message ? <p className={styles.formMessage} role="alert">{message}</p> : null}
    </div>
  );
}

"use client";

import { useRef, useState } from "react";
import styles from "../platform-admin.module.css";

type Draft = { audienceId: string; audienceType: "team" | "team_admins" | "user"; body: string; reason: string; title: string; url: string };
type Preview = { id: string; recipientCount: number; revision: number; state: string };

const initialDraft: Draft = { audienceId: "", audienceType: "user", body: "", reason: "", title: "", url: "" };

async function request(path: string, method: "GET" | "POST", payload?: unknown) {
  const response = await fetch(path, {
    cache: "no-store",
    method,
    headers: method === "POST" ? { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" } : undefined,
    body: payload ? JSON.stringify(payload) : undefined,
  });
  const body = await response.json() as Record<string, unknown>;
  if (!response.ok) throw new Error(String(body.message ?? body.error ?? "No se pudo completar la operación"));
  return body;
}

export function AnnouncementComposer() {
  const [draft, setDraft] = useState<Draft>(initialDraft);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const draftOperationId = useRef<string | null>(null);
  const sendOperationId = useRef<string | null>(null);

  function update<Key extends keyof Draft>(key: Key, value: Draft[Key]) {
    draftOperationId.current = null;
    setDraft((current) => ({ ...current, [key]: value }));
  }

  async function createDraft() {
    setBusy(true); setMessage("");
    try {
      draftOperationId.current ??= crypto.randomUUID();
      const created = await request("/api/platform-admin/announcements", "POST", {
        actionUrl: draft.url,
        audienceId: draft.audienceId,
        audienceType: draft.audienceType,
        body: draft.body,
        operationId: draftOperationId.current,
        reason: draft.reason,
        title: draft.title,
      });
      const canonical = created.canonical as Record<string, unknown>;
      const announcementId = String(canonical.id);
      const result = await request(`/api/platform-admin/announcements/${encodeURIComponent(announcementId)}/preview`, "GET");
      draftOperationId.current = null;
      setPreview(result.preview as Preview);
    } catch (error) { setMessage(error instanceof Error ? error.message : "No se pudo crear el borrador"); }
    finally { setBusy(false); }
  }

  async function send() {
    if (!preview) return;
    if (!window.confirm(`Se enviará a ${preview.recipientCount} destinatarios. Confirma el envío definitivo.`)) return;
    setBusy(true); setMessage("");
    try {
      sendOperationId.current ??= crypto.randomUUID();
      await request(`/api/platform-admin/announcements/${encodeURIComponent(preview.id)}/send`, "POST", {
        expectedRevision: preview.revision,
        operationId: sendOperationId.current,
        reason: draft.reason,
      });
      sendOperationId.current = null;
      setDraft(initialDraft); setPreview(null); setMessage("Anuncio enviado y confirmado por el servidor.");
      window.setTimeout(() => window.location.reload(), 700);
    } catch (error) { setMessage(error instanceof Error ? error.message : "No se pudo enviar el anuncio"); }
    finally { setBusy(false); }
  }

  return (
    <div className={styles.composer}>
      <div className={styles.composerGrid}>
        <label className={styles.formField}>Audiencia<select value={draft.audienceType} onChange={(event) => update("audienceType", event.target.value as Draft["audienceType"])} disabled={busy || Boolean(preview)}><option value="user">Un usuario</option><option value="team">Un equipo completo</option><option value="team_admins">Admins de un equipo</option></select></label>
        <label className={styles.formField}>UUID de audiencia<input value={draft.audienceId} onChange={(event) => update("audienceId", event.target.value)} placeholder="UUID de usuario o equipo" disabled={busy || Boolean(preview)} /></label>
        <label className={styles.formField}>Título<input value={draft.title} maxLength={120} onChange={(event) => update("title", event.target.value)} disabled={busy || Boolean(preview)} /></label>
        <label className={styles.formField}>URL interna opcional<input value={draft.url} maxLength={500} onChange={(event) => update("url", event.target.value)} placeholder="/perfil/avisos" disabled={busy || Boolean(preview)} /></label>
      </div>
      <label className={styles.formField}>Mensaje<textarea rows={3} maxLength={1000} value={draft.body} onChange={(event) => update("body", event.target.value)} disabled={busy || Boolean(preview)} /></label>
      <label className={styles.formField}>Motivo administrativo<textarea rows={2} maxLength={1200} value={draft.reason} onChange={(event) => update("reason", event.target.value)} disabled={busy || Boolean(preview)} /></label>
      {preview ? <div className={styles.previewBox}><strong>Vista previa confirmada</strong><span>{preview.recipientCount} destinatarios · estado {preview.state} · revisión {preview.revision}</span></div> : null}
      <div className={styles.inlineButtons}>
        {!preview ? <button className={styles.primaryButton} type="button" onClick={() => void createDraft()} disabled={busy}>Crear borrador y previsualizar</button> : <button className={styles.dangerButton} type="button" onClick={() => void send()} disabled={busy}>Enviar a {preview.recipientCount} destinatarios</button>}
        {preview ? <button className={styles.secondaryButton} type="button" onClick={() => setPreview(null)} disabled={busy}>Descartar vista previa</button> : null}
      </div>
      {message ? <p className={styles.formMessage} role="status">{message}</p> : null}
    </div>
  );
}

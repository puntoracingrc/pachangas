"use client";

import { useRef, useState } from "react";
import { platformRoles, platformRoleLabels, type PlatformRole } from "../_lib/platform-contract";
import styles from "../platform-admin.module.css";

function operationId() {
  return crypto.randomUUID();
}

async function adminMutation(path: string, body: Record<string, unknown>) {
  const response = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" },
    body: JSON.stringify(body),
  });
  const result = await response.json() as { error?: string; message?: string };
  if (!response.ok) throw new Error(result.message || result.error || "No se pudo completar la acción");
  return result;
}

export function UserStateActions({ currentStatus, expectedRevision, userId }: { currentStatus: string; expectedRevision: number; userId: string }) {
  const [status, setStatus] = useState(currentStatus);
  const [duration, setDuration] = useState("30");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const pendingOperationId = useRef<string | null>(null);

  async function apply() {
    if (reason.trim().length < 3) {
      setMessage("Escribe un motivo operativo.");
      return;
    }
    const label = status === "active" ? "reactivar" : status === "banned" ? "banear" : "suspender";
    if (!window.confirm(`Confirma que quieres ${label} esta cuenta. La acción quedará auditada.`)) return;
    setBusy(true);
    setMessage("");
    try {
      const expiresAt = status === "suspended"
        ? new Date(Date.now() + Number(duration) * 24 * 60 * 60 * 1000).toISOString()
        : null;
      pendingOperationId.current ??= operationId();
      await adminMutation(`/api/platform-admin/users/${encodeURIComponent(userId)}/state`, {
        expectedRevision,
        expiresAt,
        operationId: pendingOperationId.current,
        reason: reason.trim(),
        status,
      });
      pendingOperationId.current = null;
      window.location.reload();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo completar la acción");
      setBusy(false);
    }
  }

  return (
    <div className={styles.actionForm}>
      <label className={styles.formField}>Estado global
        <select value={status} onChange={(event) => { pendingOperationId.current = null; setStatus(event.target.value); }} disabled={busy}>
          <option value="active">Activo</option>
          <option value="suspended">Suspendido</option>
          <option value="banned">Baneado</option>
        </select>
      </label>
      {status === "suspended" ? (
        <label className={styles.formField}>Duración
          <select value={duration} onChange={(event) => { pendingOperationId.current = null; setDuration(event.target.value); }} disabled={busy}>
            <option value="7">7 días</option>
            <option value="30">30 días</option>
            <option value="90">90 días</option>
          </select>
        </label>
      ) : null}
      <label className={styles.formField}>Motivo
        <textarea value={reason} onChange={(event) => { pendingOperationId.current = null; setReason(event.target.value); }} maxLength={1200} rows={3} disabled={busy} />
      </label>
      <button className={status === "active" ? styles.primaryButton : styles.dangerButton} type="button" onClick={() => void apply()} disabled={busy}>
        {busy ? "Confirmando..." : "Confirmar cambio"}
      </button>
      {message ? <p className={styles.formMessage} role="alert">{message}</p> : null}
    </div>
  );
}

export function UserRoleActions({ currentRole, expectedRevision, userId }: { currentRole: string | null; expectedRevision: number; userId: string }) {
  const [role, setRole] = useState<PlatformRole>(platformRoles.includes(currentRole as PlatformRole) ? currentRole as PlatformRole : "support");
  const [active, setActive] = useState(Boolean(currentRole));
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const pendingOperationId = useRef<string | null>(null);

  async function apply() {
    if (reason.trim().length < 3) {
      setMessage("Escribe un motivo operativo.");
      return;
    }
    if (!window.confirm("Confirma el cambio de autoridad de plataforma. Quedará registrado en auditoría.")) return;
    setBusy(true);
    setMessage("");
    try {
      pendingOperationId.current ??= operationId();
      await adminMutation(`/api/platform-admin/users/${encodeURIComponent(userId)}/role`, {
        active,
        expectedRevision,
        operationId: pendingOperationId.current,
        reason: reason.trim(),
        role,
      });
      pendingOperationId.current = null;
      window.location.reload();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo completar la acción");
      setBusy(false);
    }
  }

  return (
    <div className={styles.actionForm}>
      <label className={styles.checkField}>
        <input type="checkbox" checked={active} onChange={(event) => { pendingOperationId.current = null; setActive(event.target.checked); }} disabled={busy} />
        Rol de plataforma activo
      </label>
      <label className={styles.formField}>Rol
        <select value={role} onChange={(event) => { pendingOperationId.current = null; setRole(event.target.value as PlatformRole); }} disabled={busy}>
          {platformRoles.map((item) => <option value={item} key={item}>{platformRoleLabels[item]}</option>)}
        </select>
      </label>
      <label className={styles.formField}>Motivo
        <textarea value={reason} onChange={(event) => { pendingOperationId.current = null; setReason(event.target.value); }} maxLength={1200} rows={3} disabled={busy} />
      </label>
      <button className={styles.primaryButton} type="button" onClick={() => void apply()} disabled={busy}>
        {busy ? "Guardando..." : "Guardar autoridad"}
      </button>
      {message ? <p className={styles.formMessage} role="alert">{message}</p> : null}
    </div>
  );
}

"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { clientWriteFetch } from "../../../pwa-client-bridge";
import {
  teamOperationalArray,
  teamOperationalNumber,
  teamOperationalRecord,
  teamOperationalScopeLabel,
  teamOperationalText,
  type TeamOperationalJson,
  type TeamOperationalPlatformAction,
} from "../../../team-operational-contract";
import styles from "../../platform-admin.module.css";

const presets = ["SOCIAL_ONLY", "NEW_ACTIVITY_ONLY", "COMPETITION_ONLY", "FULL_PLATFORM_SUSPENSION", "CUSTOM"] as const;
const scopes = [
  "PUBLIC_DISCOVERY", "MARKETPLACE", "SOCIAL_CHALLENGES", "NEW_MATCH_CREATION",
  "COMPETITION_REGISTRATION", "COMPETITION_ORGANIZER", "EXISTING_COMPETITION_OPERATIONS",
  "TEAM_MEMBERSHIP_ADMINISTRATION", "PUBLIC_PROFILE",
] as const;
const continuityPolicies = [
  "ALLOW_EXISTING_COMPETITIONS_TO_FINISH", "FREEZE_FUTURE_SPORTING_WRITES",
  "PLATFORM_MANAGED_EXIT", "HISTORY_ONLY",
] as const;

type PendingOperation = { id: string; key: string };

export function TeamOperationalAdminActions({
  canAppeal,
  canEnforce,
  canReview,
  canonical,
  teamId,
}: {
  canAppeal: boolean;
  canEnforce: boolean;
  canReview: boolean;
  canonical: TeamOperationalJson;
  teamId: string;
}) {
  const router = useRouter();
  const pending = useRef<PendingOperation | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [reasonCode, setReasonCode] = useState("platform.team.review");
  const [safeMessage, setSafeMessage] = useState("");
  const [privateNote, setPrivateNote] = useState("");
  const [preset, setPreset] = useState<(typeof presets)[number]>("SOCIAL_ONLY");
  const [selectedScopes, setSelectedScopes] = useState<string[]>(["MARKETPLACE", "SOCIAL_CHALLENGES"]);
  const [continuityPolicy, setContinuityPolicy] = useState<(typeof continuityPolicies)[number]>("ALLOW_EXISTING_COMPETITIONS_TO_FINISH");
  const [effectiveUntil, setEffectiveUntil] = useState("");
  const [appealResolution, setAppealResolution] = useState("UPHELD");

  const revision = teamOperationalNumber(canonical.revision);
  const restrictions = teamOperationalArray(canonical.restrictions).filter((item) => teamOperationalText(item.status, "ACTIVE") === "ACTIVE");
  const reviews = teamOperationalArray(canonical.reviews);
  const openReview = reviews.find((item) => ["OPEN", "NEEDS_INFORMATION"].includes(teamOperationalText(item.status)));
  const appeal = teamOperationalRecord(canonical.appeal);
  const appealStatus = teamOperationalText(appeal.status);
  const actionReady = reasonCode.trim().length >= 3 && !busy;

  function payloadBase(extra: TeamOperationalJson = {}, messageField: "publicMessage" | "safeMessage" = "safeMessage") {
    return {
      reasonCode: reasonCode.trim(),
      ...(safeMessage.trim() ? { [messageField]: safeMessage.trim() } : {}),
      ...(privateNote.trim() ? { privateNote: privateNote.trim() } : {}),
      ...extra,
    };
  }

  async function run(action: TeamOperationalPlatformAction, payload: TeamOperationalJson) {
    const key = JSON.stringify({ action, payload, revision, teamId });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:platform-admin-team-operational", `/api/platform-admin/teams/${encodeURIComponent(teamId)}`, {
        body: JSON.stringify({ action, expectedRevision: revision, operationId: pending.current.id, payload }),
        headers: { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" },
        method: "POST",
      });
      const body = teamOperationalRecord(await response.json().catch(() => ({})));
      if (!response.ok) throw new Error(teamOperationalText(body.message, teamOperationalText(body.error, "Operación no confirmada")));
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Operación no confirmada");
    } finally {
      setBusy(false);
    }
  }

  function restrictionPayload(targetPreset = preset) {
    return payloadBase({
      confirm: true,
      continuityPolicy,
      ...(effectiveUntil ? { effectiveUntil: new Date(effectiveUntil).toISOString() } : {}),
      preset: targetPreset,
      ...(targetPreset === "CUSTOM" ? { scopes: selectedScopes } : {}),
    }, "publicMessage");
  }

  return <div className={styles.competitionControlGrid}>
    <section className={styles.competitionControl}>
      <h3>Justificación auditable</h3>
      <label className={styles.formField}>Código de motivo<input maxLength={120} value={reasonCode} onChange={(event) => setReasonCode(event.target.value)} /></label>
      <label className={styles.formField}>Mensaje seguro<textarea maxLength={500} rows={3} value={safeMessage} onChange={(event) => setSafeMessage(event.target.value)} /></label>
      {(canReview || canEnforce || canAppeal) ? <label className={styles.formField}>Nota privada<textarea maxLength={4000} rows={3} value={privateNote} onChange={(event) => setPrivateNote(event.target.value)} /></label> : null}
      <small>La nota privada no forma parte de las proyecciones de owner, miembros ni público.</small>
    </section>

    {canReview ? <section className={styles.competitionControl}>
      <h3>Revisión humana</h3>
      {openReview ? <>
        <p>Revisión abierta · {teamOperationalText(openReview.reasonCode)}</p>
        <button className={styles.secondaryButton} disabled={!actionReady} type="button" onClick={() => void run("team.review.close", payloadBase({ outcome: "NO_ACTION", reviewId: teamOperationalText(openReview.id) }))}>Cerrar sin medida</button>
        <button className={styles.secondaryButton} disabled={!actionReady} type="button" onClick={() => void run("team.review.close", payloadBase({ outcome: "ACTION_TAKEN", reviewId: teamOperationalText(openReview.id) }))}>Cerrar con medida registrada</button>
      </> : <button className={styles.secondaryButton} disabled={!actionReady} type="button" onClick={() => void run("team.review.open", payloadBase())}>Abrir revisión</button>}
      <small>Una revisión no bloquea por sí sola.</small>
    </section> : null}

    {canEnforce ? <section className={styles.competitionControl}>
      <h3>Restricción por ámbitos</h3>
      <label className={styles.formField}>Preset<select value={preset} onChange={(event) => setPreset(event.target.value as (typeof presets)[number])}>{presets.map((value) => <option key={value} value={value}>{value}</option>)}</select></label>
      {preset === "CUSTOM" ? <div>{scopes.map((scope) => <label className={styles.checkField} key={scope}><input checked={selectedScopes.includes(scope)} onChange={(event) => setSelectedScopes(event.target.checked ? [...selectedScopes, scope] : selectedScopes.filter((item) => item !== scope))} type="checkbox" />{teamOperationalScopeLabel(scope)}</label>)}</div> : null}
      <label className={styles.formField}>Continuidad<select value={continuityPolicy} onChange={(event) => setContinuityPolicy(event.target.value as (typeof continuityPolicies)[number])}>{continuityPolicies.map((value) => <option key={value} value={value}>{value}</option>)}</select></label>
      <label className={styles.formField}>Caducidad opcional<input type="datetime-local" value={effectiveUntil} onChange={(event) => setEffectiveUntil(event.target.value)} /></label>
      <button className={styles.primaryButton} disabled={!actionReady || (preset === "CUSTOM" && !selectedScopes.length)} type="button" onClick={() => void run(restrictions.length ? "team.restriction.modify" : "team.restriction.apply", restrictionPayload())}>{restrictions.length ? "Modificar limitación" : "Aplicar limitación"}</button>
      <button className={styles.dangerButton} disabled={!actionReady} type="button" onClick={() => void run("team.suspend", restrictionPayload("FULL_PLATFORM_SUSPENSION"))}>Suspender plataforma</button>
      {restrictions.length ? <button className={styles.secondaryButton} disabled={!actionReady} type="button" onClick={() => void run("team.restriction.lift", payloadBase({ confirm: true, scopes: restrictions.map((item) => teamOperationalText(item.scope)) }, "publicMessage"))}>Levantar ámbitos activos</button> : null}
      {teamOperationalText(canonical.enforcement) === "SUSPENDED" ? <button className={styles.secondaryButton} disabled={!actionReady} type="button" onClick={() => void run("team.restore", payloadBase({ confirm: true }, "publicMessage"))}>Restaurar plataforma</button> : null}
    </section> : null}

    {canAppeal && ["SUBMITTED", "UNDER_REVIEW"].includes(appealStatus) ? <section className={styles.competitionControl}>
      <h3>Resolver apelación</h3>
      {appealStatus === "SUBMITTED" ? <button className={styles.secondaryButton} disabled={!actionReady} type="button" onClick={() => void run("team.appeal.review", payloadBase({ appealId: teamOperationalText(appeal.id) }))}>Tomar en revisión</button> : null}
      <label className={styles.formField}>Resolución<select value={appealResolution} onChange={(event) => setAppealResolution(event.target.value)}><option value="UPHELD">Confirmar</option><option value="OVERTURNED">Retirar</option><option value="INADMISSIBLE">No admitir</option><option value="MODIFIED">Modificar</option></select></label>
      <button className={styles.primaryButton} disabled={!actionReady} type="button" onClick={() => void run("team.appeal.resolve", payloadBase({
        appealId: teamOperationalText(appeal.id),
        resolution: appealResolution,
        ...(appealResolution === "MODIFIED" ? { continuityPolicy, preset, ...(preset === "CUSTOM" ? { scopes: selectedScopes } : {}) } : {}),
      }))}>Resolver apelación</button>
    </section> : null}
    {message ? <p className={styles.competitionControlMessage} role="status">{message}</p> : null}
  </div>;
}

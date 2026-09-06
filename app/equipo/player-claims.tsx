"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { supabase } from "../supabaseClient";
import styles from "./player-claims.module.css";

type Claim = { id: string; playerId: string; playerName: string; requesterName: string; isMine: boolean; state: string; createdAt: string };
type ClaimState = { canReview: boolean; hasTeamPlayer: boolean; candidates: { playerId: string; name: string }[]; requests: Claim[] };

export function claimError(message: string) {
  if (message.includes("ALREADY_HAS_TEAM_PLAYER")) return "Tu cuenta ya tiene un jugador en este equipo. Habla con el administrador para revisar el duplicado sin perder el historial.";
  if (message.includes("ANOTHER_CLAIM_PENDING")) return "Ya tienes una solicitud pendiente. Cancélala antes de elegir otra ficha.";
  if (message.includes("ANOTHER_ADMIN_REQUIRED")) return "Otro administrador debe confirmar tu solicitud.";
  if (/PLAYER_ALREADY_OWNED|CLAIM_ALREADY_DECIDED|PLAYER_OWNER_IMMUTABLE/.test(message)) return "Esta ficha o solicitud ya se ha resuelto. Hemos actualizado su estado.";
  if (/REQUESTER_LEFT_TEAM|TEAM_MEMBERSHIP_REQUIRED/.test(message)) return "La cuenta debe seguir siendo miembro del equipo para vincular la ficha.";
  if (message.includes("PLAYER_NOT_AVAILABLE")) return "Este jugador ya no está disponible en la plantilla.";
  if (message.includes("TEAM_ADMIN_REQUIRED")) return "Solo un administrador actual del equipo puede revisar la solicitud.";
  return "No se pudo confirmar la acción. Vuelve a intentarlo con conexión.";
}

export function PlayerClaims({ groupId, showCandidates = false, onChanged }: { groupId: string; showCandidates?: boolean; onChanged: () => void }) {
  const [data, setData] = useState<ClaimState | null>(null);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [confirmation, setConfirmation] = useState<{ claim?: Claim; playerId?: string; name: string } | null>(null);
  const lifecycle = useRef({ active: true, sequence: 0 });
  const load = useCallback(async () => {
    if (!supabase) return;
    const requestGeneration = ++lifecycle.current.sequence;
    const result = await supabase.rpc("get_pachanga_player_claims_v1", { target_group_id: groupId });
    if (!lifecycle.current.active || lifecycle.current.sequence !== requestGeneration) return;
    if (result.error) { setError("No pudimos cargar las solicitudes de ficha."); return; }
    setData(result.data as ClaimState);
  }, [groupId]);

  useEffect(() => {
    const state = lifecycle.current;
    state.active = true;
    queueMicrotask(() => { if (state.active) void load(); });
    const refresh = () => { if (document.visibilityState === "visible") void load(); };
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", refresh);
    return () => { state.active = false; state.sequence++; window.removeEventListener("focus", refresh); document.removeEventListener("visibilitychange", refresh); };
  }, [load]);

  async function command(claimId: string | undefined, decision: "approve" | "reject" | "cancel" | "request", playerId?: string) {
    if (!supabase || busy) return;
    setBusy(true); setError(""); setMessage("");
    const result = decision === "request"
      ? await supabase.rpc("request_pachanga_player_claim_v1", { target_group_id: groupId, target_player_id: playerId })
      : await supabase.rpc("decide_pachanga_player_claim_v1", { target_claim_id: claimId, decision });
    if (!lifecycle.current.active) return;
    setBusy(false); setConfirmation(null);
    if (result.error) setError(claimError(result.error.message));
    else setMessage(decision === "request" ? "Solicitud enviada. Un administrador confirmará que esta ficha es tuya." : decision === "approve" ? "Ficha vinculada. Se han conservado sus partidos y estadísticas." : decision === "reject" ? "Solicitud rechazada." : "Solicitud cancelada.");
    await load();
    if (!result.error) onChanged();
  }

  const pending = data?.requests.filter((claim) => claim.state === "PENDING") ?? [];
  const myPending = pending.find((claim) => claim.isMine);
  const resolved = data?.requests.find((claim) => claim.isMine && claim.state !== "PENDING");
  if (!showCandidates && !pending.length && !error && !message) return null;
  return <section className={styles.panel} aria-label="Vincular fichas de jugadores">
    <header><span>Fichas del equipo</span><h2>{data?.canReview ? "Solicitudes de jugadores" : "¿Ya jugabas con este equipo?"}</h2></header>
    {error ? <p role="alert">{error} <button type="button" onClick={() => { setError(""); void load(); }}>Actualizar</button></p> : null}
    {message ? <p role="status">{message}</p> : null}
    {!data && !error ? <p>Cargando solicitudes…</p> : null}
    {pending.map((claim) => <article key={claim.id} className={styles.request}>
      <div><strong>{claim.isMine ? "Tu solicitud" : claim.requesterName}</strong><p>Ficha de <b>{claim.playerName}</b></p><small>Pendiente de aprobación · {new Date(claim.createdAt).toLocaleDateString("es-ES")}</small></div>
      <div className={styles.actions}>{claim.isMine
        ? <><small>{data?.canReview ? "Debe confirmarla otro administrador." : "El administrador debe confirmar tu identidad."}</small><button type="button" disabled={busy} onClick={() => void command(claim.id, "cancel")}>Cancelar solicitud</button></>
        : data?.canReview ? <><button type="button" disabled={busy} onClick={() => void command(claim.id, "reject")}>Rechazar</button><button className={styles.primary} type="button" disabled={busy} onClick={() => setConfirmation({ claim, name: claim.playerName })}>Revisar y vincular</button></> : null}</div>
    </article>)}
    {resolved && !myPending ? <p className={styles.notice}>{resolved.state === "APPROVED" ? <>Tu ficha de <strong>{resolved.playerName}</strong> ya está vinculada. <a href="/perfil">Abrir mi perfil</a></> : resolved.state === "REJECTED" ? "Tu última solicitud fue rechazada. Habla con el administrador si ha habido un error." : resolved.state === "SUPERSEDED" ? "La ficha solicitada se ha vinculado a otra cuenta. Habla con el administrador si no es correcto." : "Has cancelado tu última solicitud."}</p> : null}
    {showCandidates && data && !data.hasTeamPlayer && !myPending ? <>
      <p>Si el administrador ya te había añadido, solicita tu ficha para conservar tus partidos y estadísticas. La vinculación necesita su aprobación.</p>
      <div className={styles.candidates}>{data.candidates.map((player) => <div key={player.playerId}><strong>{player.name}</strong><button type="button" disabled={busy} onClick={() => setConfirmation({ playerId: player.playerId, name: player.name })}>Esta es mi ficha</button></div>)}</div>
      {!data.candidates.length ? <p>No hay fichas sin vincular en la plantilla.</p> : null}
    </> : null}
    {showCandidates && data?.hasTeamPlayer && !myPending && resolved?.state !== "APPROVED" ? <p>Tu cuenta ya tiene un jugador vinculado en este equipo. Si apareces también con otra ficha, pide al administrador que revise el duplicado.</p> : null}
    {data?.canReview && !pending.length ? <p>No hay solicitudes pendientes.</p> : null}
    {confirmation ? <div className={styles.confirmation} role="group" aria-label="Confirmar vinculación">
      <h3>{confirmation.claim ? `Vincular la ficha de ${confirmation.name}` : `Solicitar la ficha de ${confirmation.name}`}</h3>
      <p>{confirmation.claim ? <>Confirma con <strong>{confirmation.claim.requesterName}</strong> que esta es su ficha. Coincidir en el nombre no basta. Su cuenta quedará vinculada y conservará el historial del equipo.</> : "Solo solicita esta ficha si te corresponde. El administrador comprobará tu identidad antes de vincularla a tu cuenta."}</p>
      <p>El administrador podrá seguir apuntando y desapuntando al jugador en los partidos.</p>
      <div className={styles.actions}><button type="button" disabled={busy} onClick={() => setConfirmation(null)}>Volver</button><button className={styles.primary} type="button" disabled={busy} onClick={() => void command(confirmation.claim?.id, confirmation.claim ? "approve" : "request", confirmation.playerId)}>{busy ? "Guardando…" : confirmation.claim ? "He comprobado su identidad · Vincular" : "Enviar solicitud"}</button></div>
    </div> : null}
  </section>;
}

"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { CLIENT_VERSION } from "../client-version-contract";
import {
  externalMatchStateLabel,
  normalizeExternalMatch,
  normalizeExternalResultsSnapshot,
  readExternalResultsCache,
  writeExternalResultsCache,
  type ExternalMatch,
  type ExternalResultsSnapshot,
} from "../external-results-contract";
import { currentClientDisplayMode } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";

type Props = {
  groupId: string;
  initialChallengeId?: string;
  userId: string;
};

type MatchForm = {
  goals: Record<string, number>;
  participantIds: string[];
  scoreAway: string;
  scoreHome: string;
};

type ResultAction = "cancel" | "complete_scorers" | "confirm" | "propose_change" | "publish" | "reject_change";

function clientMetadata() {
  return {
    clientVersion: CLIENT_VERSION,
    displayMode: currentClientDisplayMode(),
    surface: "external-results",
  };
}

function dateTime(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return new Intl.DateTimeFormat("es-ES", { dateStyle: "medium", timeStyle: "short" }).format(parsed);
}

function modalityLabel(value: ExternalMatch["modality"]) {
  if (value === "sala") return "Fútbol sala";
  if (value === "futbol11") return "Fútbol 11";
  return "Fútbol 7";
}

function formFromMatch(match: ExternalMatch, groupId: string): MatchForm {
  const ownParticipants = match.participants
    .filter((participant) => participant.groupId === groupId)
    .map((participant) => participant.localPlayerId);
  const goals = Object.fromEntries(
    match.scorers
      .filter((scorer) => scorer.groupId === groupId)
      .map((scorer) => [scorer.localPlayerId, scorer.goals]),
  );
  return {
    goals,
    participantIds: ownParticipants,
    scoreAway: String(match.scoreAway ?? match.canonicalScoreAway ?? 0),
    scoreHome: String(match.scoreHome ?? match.canonicalScoreHome ?? 0),
  };
}

function operationFingerprint(action: ResultAction, match: ExternalMatch, form: MatchForm) {
  return `${action}:${match.id}:${match.revision}:${JSON.stringify(form)}`;
}

export function ExternalResultsPanel({ groupId, initialChallengeId = "", userId }: Props) {
  const [snapshot, setSnapshot] = useState<ExternalResultsSnapshot | null>(null);
  const [selectedMatchId, setSelectedMatchId] = useState("");
  const [form, setForm] = useState<MatchForm>({ goals: {}, participantIds: [], scoreAway: "0", scoreHome: "0" });
  const [busy, setBusy] = useState("");
  const [message, setMessage] = useState("");
  const operationIds = useRef(new Map<string, string>());

  const selectedMatch = useMemo(
    () => snapshot?.matches.find((match) => match.id === selectedMatchId)
      ?? snapshot?.matches.find((match) => match.challengeId === initialChallengeId)
      ?? snapshot?.matches[0]
      ?? null,
    [initialChallengeId, selectedMatchId, snapshot?.matches],
  );

  const acceptSnapshot = useCallback((value: unknown) => {
    const normalized = normalizeExternalResultsSnapshot(value);
    if (!normalized || normalized.groupId !== groupId) return false;
    setSnapshot(normalized);
    try {
      writeExternalResultsCache(window.localStorage, userId, groupId, normalized);
    } catch {
      // Cache is derived and optional.
    }
    return true;
  }, [groupId, userId]);

  const loadSnapshot = useCallback(async () => {
    if (!supabase || !groupId) return;
    const result = await supabase.rpc("get_pachanga_external_results_snapshot_v1", { target_group_id: groupId });
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    if (!acceptSnapshot(result.data)) setMessage("El servidor devolvió un snapshot de resultados no válido.");
  }, [acceptSnapshot, groupId]);

  useEffect(() => {
    if (!groupId || !userId) return;
    const cached = readExternalResultsCache(window.localStorage, userId, groupId);
    if (cached) queueMicrotask(() => setSnapshot(cached));
    queueMicrotask(() => void loadSnapshot());
  }, [groupId, loadSnapshot, userId]);

  useEffect(() => {
    if (!supabase || !groupId) return;
    const client = supabase;
    const channel = client
      .channel(`pachanga-external-results-${groupId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_external_match_group_state", filter: `group_id=eq.${groupId}` },
        () => void loadSnapshot(),
      )
      .subscribe();
    const reconnect = () => {
      if (navigator.onLine) void loadSnapshot();
    };
    window.addEventListener("online", reconnect);
    return () => {
      window.removeEventListener("online", reconnect);
      void client.removeChannel(channel);
    };
  }, [groupId, loadSnapshot]);

  useEffect(() => {
    if (!selectedMatch) return;
    queueMicrotask(() => {
      setSelectedMatchId(selectedMatch.id);
      setForm(formFromMatch(selectedMatch, groupId));
    });
  }, [groupId, selectedMatch]);

  function operationIdFor(fingerprint: string) {
    const existing = operationIds.current.get(fingerprint);
    if (existing) return existing;
    const created = crypto.randomUUID();
    operationIds.current.set(fingerprint, created);
    return created;
  }

  function replaceCanonicalMatch(value: unknown) {
    const canonical = normalizeExternalMatch(value);
    if (!canonical || !snapshot) return false;
    const next = {
      ...snapshot,
      confirmedRevision: Math.max(snapshot.confirmedRevision, canonical.revision),
      matches: snapshot.matches.map((match) => match.id === canonical.id ? canonical : match),
      serverSequence: Math.max(snapshot.serverSequence, canonical.serverSequence),
      updatedAt: canonical.updatedAt,
    };
    setSnapshot(next);
    try {
      writeExternalResultsCache(window.localStorage, userId, groupId, next);
    } catch {
      // Cache is derived and optional.
    }
    return true;
  }

  async function runAction(action: ResultAction) {
    if (!supabase || !selectedMatch || !snapshot?.canManage || busy) return;
    const scoreHome = Number(form.scoreHome);
    const scoreAway = Number(form.scoreAway);
    const ownScore = selectedMatch.side === "home" ? scoreHome : scoreAway;
    const ownScorerTotal = form.participantIds.reduce((sum, playerId) => sum + Math.max(0, form.goals[playerId] ?? 0), 0);
    const needsLineup = action === "publish" || action === "propose_change" || action === "confirm" || action === "complete_scorers";
    if (needsLineup && (!Number.isInteger(scoreHome) || scoreHome < 0 || !Number.isInteger(scoreAway) || scoreAway < 0)) {
      setMessage("Introduce un marcador válido.");
      return;
    }
    if (needsLineup && form.participantIds.length < 1) {
      setMessage("Selecciona al menos un participante de tu equipo.");
      return;
    }
    if (needsLineup && ownScorerTotal !== ownScore) {
      setMessage(`Los goleadores de tu equipo suman ${ownScorerTotal}, pero deben sumar ${ownScore}.`);
      return;
    }

    const fingerprint = operationFingerprint(action, selectedMatch, form);
    const operationId = operationIdFor(fingerprint);
    const scorers = form.participantIds
      .filter((playerId) => (form.goals[playerId] ?? 0) > 0)
      .map((playerId) => ({ goals: form.goals[playerId], playerId }));
    const shared = {
      client_metadata: clientMetadata(),
      expected_revision: selectedMatch.revision,
      operation_id: operationId,
      target_external_match_id: selectedMatch.id,
      target_group_id: groupId,
    };
    setBusy(action);
    setMessage("");
    let result;
    if (action === "publish") {
      result = await supabase.rpc("publish_pachanga_external_result_v1", {
        ...shared,
        target_participant_ids: form.participantIds,
        target_score_away: scoreAway,
        target_score_home: scoreHome,
        target_scorers: scorers,
      });
    } else if (action === "propose_change") {
      result = await supabase.rpc("propose_pachanga_external_result_change_v1", {
        ...shared,
        target_participant_ids: form.participantIds,
        target_score_away: scoreAway,
        target_score_home: scoreHome,
        target_scorers: scorers,
      });
    } else if (action === "confirm") {
      result = await supabase.rpc("confirm_pachanga_external_result_v1", {
        ...shared,
        target_participant_ids: form.participantIds,
        target_scorers: scorers,
      });
    } else if (action === "complete_scorers") {
      result = await supabase.rpc("complete_pachanga_external_scorers_v1", {
        ...shared,
        target_participant_ids: form.participantIds,
        target_scorers: scorers,
      });
    } else if (action === "reject_change") {
      result = await supabase.rpc("reject_pachanga_external_result_change_v1", shared);
    } else {
      result = await supabase.rpc("cancel_pachanga_external_match_v1", shared);
    }
    setBusy("");
    if (result.error) {
      setMessage(result.error.message);
      if (result.error.code === "PT409") await loadSnapshot();
      return;
    }
    operationIds.current.delete(fingerprint);
    if (!replaceCanonicalMatch(result.data)) await loadSnapshot();
    setMessage(
      action === "confirm" ? "Resultado confirmado por el servidor."
        : action === "reject_change" ? "Corrección rechazada; el resultado queda en discrepancia."
          : action === "complete_scorers" ? "Goleadores pendientes guardados."
            : action === "cancel" ? "Partido externo cancelado."
              : "Propuesta enviada al rival.",
    );
  }

  if (!snapshot?.matches.length) return null;
  if (!selectedMatch) return null;

  const waitingForOwnTeam = selectedMatch.pendingResponseFromGroupId === groupId;
  const correctionWaiting = waitingForOwnTeam
    && (selectedMatch.state === "change_proposed" || selectedMatch.state === "needs_scorer_fix");
  const initialWaiting = waitingForOwnTeam && selectedMatch.state === "pending_rival";
  const ownUnassigned = selectedMatch.side === "home" ? selectedMatch.unassignedHome : selectedMatch.unassignedAway;
  const showEditor = snapshot.canManage && (
    selectedMatch.state === "draft" || initialWaiting || correctionWaiting
    || (selectedMatch.state === "auto_confirmed" && ownUnassigned > 0)
  );

  return (
    <section className="market-panel external-results-panel" aria-label="Resultados compartidos con equipos rivales">
      <header className="external-results-heading">
        <div><span>Partidos entre equipos</span><strong>Resultado compartido</strong></div>
        <select value={selectedMatch.id} onChange={(event) => setSelectedMatchId(event.target.value)}>
          {snapshot.matches.map((match) => (
            <option key={match.id} value={match.id}>
              {match.homeTeam.name} - {match.awayTeam.name} · {dateTime(match.scheduledAt)}
            </option>
          ))}
        </select>
      </header>

      <div className="external-result-scoreboard">
        <div><span>{selectedMatch.homeTeam.name}</span><strong>{selectedMatch.scoreHome ?? "-"}</strong></div>
        <b>{externalMatchStateLabel(selectedMatch.state)}</b>
        <div><span>{selectedMatch.awayTeam.name}</span><strong>{selectedMatch.scoreAway ?? "-"}</strong></div>
      </div>
      <div className="external-result-meta">
        <span>{modalityLabel(selectedMatch.modality)}</span>
        <span>{dateTime(selectedMatch.scheduledAt)}</span>
        <span>{selectedMatch.field.name || "Campo pendiente"}</span>
        {selectedMatch.responseDeadline ? <span>Responde antes del {dateTime(selectedMatch.responseDeadline)}</span> : null}
      </div>

      {showEditor ? (
        <div className="external-result-editor">
          <div className="external-score-inputs">
            <label>{selectedMatch.homeTeam.name}<input type="number" min="0" inputMode="numeric" value={form.scoreHome} onChange={(event) => setForm((current) => ({ ...current, scoreHome: event.target.value }))} /></label>
            <span>-</span>
            <label>{selectedMatch.awayTeam.name}<input type="number" min="0" inputMode="numeric" value={form.scoreAway} onChange={(event) => setForm((current) => ({ ...current, scoreAway: event.target.value }))} /></label>
          </div>
          <fieldset>
            <legend>Tu convocatoria y goleadores</legend>
            <div className="external-roster-grid">
              {snapshot.roster.map((player) => {
                const selected = form.participantIds.includes(player.localPlayerId);
                return (
                  <div className={selected ? "external-roster-player selected" : "external-roster-player"} key={player.localPlayerId}>
                    <label>
                      <input
                        type="checkbox"
                        checked={selected}
                        onChange={(event) => setForm((current) => ({
                          ...current,
                          goals: event.target.checked ? current.goals : { ...current.goals, [player.localPlayerId]: 0 },
                          participantIds: event.target.checked
                            ? [...current.participantIds, player.localPlayerId]
                            : current.participantIds.filter((id) => id !== player.localPlayerId),
                        }))}
                      />
                      <span>{player.name}</span>
                    </label>
                    {selected ? (
                      <div className="external-goal-stepper">
                        <button type="button" aria-label={`Restar gol a ${player.name}`} onClick={() => setForm((current) => ({ ...current, goals: { ...current.goals, [player.localPlayerId]: Math.max(0, (current.goals[player.localPlayerId] ?? 0) - 1) } }))}>−</button>
                        <strong>{form.goals[player.localPlayerId] ?? 0}</strong>
                        <button type="button" aria-label={`Añadir gol a ${player.name}`} onClick={() => setForm((current) => ({ ...current, goals: { ...current.goals, [player.localPlayerId]: (current.goals[player.localPlayerId] ?? 0) + 1 } }))}>+</button>
                      </div>
                    ) : null}
                  </div>
                );
              })}
            </div>
          </fieldset>
          <div className="external-result-actions">
            {selectedMatch.state === "draft" ? <button type="button" disabled={Boolean(busy)} onClick={() => void runAction("publish")}>Enviar resultado</button> : null}
            {initialWaiting || correctionWaiting ? <button type="button" disabled={Boolean(busy)} onClick={() => void runAction("confirm")}>Aceptar marcador</button> : null}
            {initialWaiting ? <button type="button" disabled={Boolean(busy)} onClick={() => void runAction("propose_change")}>Proponer corrección</button> : null}
            {correctionWaiting ? <button type="button" disabled={Boolean(busy)} onClick={() => void runAction("reject_change")}>Rechazar corrección</button> : null}
            {selectedMatch.state === "auto_confirmed" && ownUnassigned > 0 ? <button type="button" disabled={Boolean(busy)} onClick={() => void runAction("complete_scorers")}>Completar goleadores</button> : null}
            {selectedMatch.state !== "auto_confirmed" && selectedMatch.state !== "confirmed" ? <button className="danger" type="button" disabled={Boolean(busy)} onClick={() => void runAction("cancel")}>Cancelar partido</button> : null}
          </div>
        </div>
      ) : null}
      {!snapshot.canManage ? <p className="external-result-readonly">Puedes seguir el marcador y sus cambios. Solo los administradores certifican el resultado.</p> : null}
      {selectedMatch.state === "auto_confirmed" && ownUnassigned > 0 && !snapshot.canManage ? <p className="external-result-readonly">Quedan {ownUnassigned} goles de tu equipo sin asignar.</p> : null}
      {message ? <p className="team-challenges-message" aria-live="polite">{message}</p> : null}
    </section>
  );
}

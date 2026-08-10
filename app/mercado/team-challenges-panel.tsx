"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { attachVenueAutocomplete, type VenuePlace } from "../googlePlacesClient";
import { supabase } from "../supabaseClient";
import { ExternalResultsPanel } from "./external-results-panel";
import {
  normalizeTeamSocialSnapshot,
  readTeamSocialCache,
  teamChallengeModalityLabel,
  teamChallengeStatusLabel,
  type TeamChallenge,
  type TeamChallengeAction,
  type TeamChallengeModality,
  type TeamSocialSnapshot,
  type TeamSummary,
  writeTeamSocialCache,
} from "../team-social-contract";

const googleMapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;

type GroupMembership = TeamSummary & {
  role: "admin" | "owner" | "player";
};

type ChallengeDraft = {
  fieldAddress: string;
  fieldMapsUrl: string;
  fieldName: string;
  fieldPlaceId: string;
  message: string;
  modality: TeamChallengeModality;
  scheduledAt: string;
};

type Props = {
  initialOpponent?: TeamSummary | null;
};

const emptyDraft: ChallengeDraft = {
  fieldAddress: "",
  fieldMapsUrl: "",
  fieldName: "",
  fieldPlaceId: "",
  message: "",
  modality: "futbol7",
  scheduledAt: "",
};

function operationMetadata() {
  let sessionId = window.sessionStorage.getItem("pachangas-operation-session");
  if (!sessionId) {
    sessionId = crypto.randomUUID();
    window.sessionStorage.setItem("pachangas-operation-session", sessionId);
  }
  return {
    orientation: window.matchMedia("(orientation: landscape)").matches ? "landscape" : "portrait",
    sessionId,
    surface: window.matchMedia("(display-mode: standalone)").matches ? "pwa-market-challenges" : "web-market-challenges",
  };
}

function localDateTimeValue(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

function formatDateTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("es-ES", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function mapsUrlForPlace(place: VenuePlace) {
  return place.placeId ? `https://www.google.com/maps/place/?q=place_id:${encodeURIComponent(place.placeId)}` : "";
}

function normalizeMemberships(value: unknown): GroupMembership[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const row = item as Record<string, unknown>;
    const nested = Array.isArray(row.pachanga_groups) ? row.pachanga_groups[0] : row.pachanga_groups;
    if (!nested || typeof nested !== "object") return [];
    const group = nested as Record<string, unknown>;
    const groupId = typeof group.id === "string" ? group.id : "";
    const name = typeof group.name === "string" ? group.name : "";
    const teamCode = typeof group.team_code === "string" ? group.team_code : "";
    const role = row.role === "owner" || row.role === "admin" ? row.role : "player";
    return groupId && name ? [{ groupId, name, role, teamCode }] : [];
  });
}

function draftFromChallenge(challenge: TeamChallenge): ChallengeDraft {
  return {
    fieldAddress: challenge.field.address,
    fieldMapsUrl: challenge.field.mapsUrl ?? "",
    fieldName: challenge.field.name,
    fieldPlaceId: challenge.field.placeId ?? "",
    message: challenge.message ?? "",
    modality: challenge.modality,
    scheduledAt: localDateTimeValue(challenge.scheduledAt),
  };
}

function challengeDraftFingerprint(draft: ChallengeDraft) {
  return JSON.stringify(draft);
}

export function TeamChallengesPanel({ initialOpponent }: Props) {
  const [memberships, setMemberships] = useState<GroupMembership[]>([]);
  const [selectedGroupId, setSelectedGroupId] = useState("");
  const [currentUserId, setCurrentUserId] = useState("");
  const [snapshot, setSnapshot] = useState<TeamSocialSnapshot | null>(null);
  const [teamCode, setTeamCode] = useState(initialOpponent?.teamCode ?? "");
  const [confirmedTeam, setConfirmedTeam] = useState<TeamSummary | null>(initialOpponent ?? null);
  const [draft, setDraft] = useState<ChallengeDraft>(emptyDraft);
  const [editingChallengeId, setEditingChallengeId] = useState<string | null>(null);
  const [message, setMessage] = useState(
    initialOpponent
      ? `Rival público confirmado: ${initialOpponent.name}. Completa el campo y la fecha.`
      : supabase ? "" : "Supabase no está configurado para cargar retos.",
  );
  const [loading, setLoading] = useState(Boolean(supabase));
  const [busyKey, setBusyKey] = useState("");
  const fieldInputRef = useRef<HTMLInputElement>(null);
  const operationIdsRef = useRef(new Map<string, string>());

  const selectedMembership = useMemo(
    () => memberships.find((membership) => membership.groupId === selectedGroupId) ?? null,
    [memberships, selectedGroupId],
  );
  const editingChallenge = useMemo(
    () => snapshot?.challenges.find((challenge) => challenge.id === editingChallengeId) ?? null,
    [editingChallengeId, snapshot?.challenges],
  );

  const operationIdFor = useCallback((fingerprint: string) => {
    const existing = operationIdsRef.current.get(fingerprint);
    if (existing) return existing;
    const next = crypto.randomUUID();
    operationIdsRef.current.set(fingerprint, next);
    return next;
  }, []);

  const acceptCanonicalSnapshot = useCallback((value: unknown, userId: string, groupId: string) => {
    const canonical = normalizeTeamSocialSnapshot(value);
    if (!canonical || canonical.group.groupId !== groupId) return false;
    setSnapshot(canonical);
    if (userId && groupId) {
      try {
        writeTeamSocialCache(window.localStorage, userId, groupId, canonical);
      } catch {
        // Cache failures never change the confirmed server state.
      }
    }
    return true;
  }, []);

  const loadSnapshot = useCallback(async (groupId: string, userId: string) => {
    if (!supabase || !groupId) return;
    const result = await supabase.rpc("get_pachanga_team_social_snapshot", { target_group_id: groupId });
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    acceptCanonicalSnapshot(result.data, userId, groupId);
  }, [acceptCanonicalSnapshot]);

  useEffect(() => {
    if (!supabase) return;
    let active = true;

    async function loadGroups() {
      const session = await supabase?.auth.getSession();
      const user = session?.data.session?.user ?? null;
      if (!active) return;
      if (!user) {
        setLoading(false);
        setMessage("Entra con Google para ver los retos de tus equipos.");
        return;
      }
      setCurrentUserId(user.id);
      const result = await supabase
        ?.from("pachanga_group_members")
        .select("group_id, role, pachanga_groups(id, name, team_code)")
        .eq("user_id", user.id)
        .order("created_at", { ascending: true });
      if (!active) return;
      if (result?.error) {
        setLoading(false);
        setMessage(result.error.message);
        return;
      }
      const nextMemberships = normalizeMemberships(result?.data);
      setMemberships(nextMemberships);
      const preferredGroupId = window.localStorage.getItem("pachangas-social-selected-group") ?? "";
      const nextGroupId = nextMemberships.some((group) => group.groupId === preferredGroupId)
        ? preferredGroupId
        : nextMemberships[0]?.groupId ?? "";
      setSelectedGroupId(nextGroupId);
      if (nextGroupId) {
        const cached = readTeamSocialCache(window.localStorage, user.id, nextGroupId);
        if (cached) setSnapshot(cached);
        await loadSnapshot(nextGroupId, user.id);
      }
      if (active) setLoading(false);
    }

    void loadGroups();
    return () => {
      active = false;
    };
  }, [loadSnapshot]);

  function selectGroup(groupId: string) {
    if (!groupId || !currentUserId) return;
    setSelectedGroupId(groupId);
    window.localStorage.setItem("pachangas-social-selected-group", groupId);
    const cached = readTeamSocialCache(window.localStorage, currentUserId, groupId);
    setSnapshot(cached);
    setConfirmedTeam(null);
    setEditingChallengeId(null);
    setDraft(emptyDraft);
    void loadSnapshot(groupId, currentUserId);
  }

  useEffect(() => {
    if (!supabase || !selectedGroupId) return;
    const channel = supabase
      .channel(`pachanga-team-social-${selectedGroupId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_team_social_state", filter: `group_id=eq.${selectedGroupId}` },
        () => void loadSnapshot(selectedGroupId, currentUserId),
      )
      .subscribe();
    return () => {
      void supabase?.removeChannel(channel);
    };
  }, [currentUserId, loadSnapshot, selectedGroupId]);

  useEffect(() => {
    if (!selectedGroupId || !currentUserId) return;
    const refreshConfirmedState = () => {
      if (navigator.onLine) void loadSnapshot(selectedGroupId, currentUserId);
    };
    const refreshWhenVisible = () => {
      if (document.visibilityState === "visible") refreshConfirmedState();
    };
    window.addEventListener("online", refreshConfirmedState);
    document.addEventListener("visibilitychange", refreshWhenVisible);
    return () => {
      window.removeEventListener("online", refreshConfirmedState);
      document.removeEventListener("visibilitychange", refreshWhenVisible);
    };
  }, [currentUserId, loadSnapshot, selectedGroupId]);

  useEffect(() => {
    if (!snapshot?.canManage || !googleMapsApiKey || !fieldInputRef.current) return;
    let cleanup: (() => void) | undefined;
    let disposed = false;
    attachVenueAutocomplete({
      apiKey: googleMapsApiKey,
      input: fieldInputRef.current,
      onPlace: (place) => {
        if (disposed) return;
        setDraft((current) => ({
          ...current,
          fieldAddress: place.address,
          fieldMapsUrl: mapsUrlForPlace(place),
          fieldName: place.name,
          fieldPlaceId: place.placeId,
        }));
        setMessage("");
      },
    }).then((nextCleanup) => {
      if (disposed) nextCleanup();
      else cleanup = nextCleanup;
    }).catch(() => setMessage("Puedes escribir el nombre y la dirección del campo manualmente."));
    return () => {
      disposed = true;
      cleanup?.();
    };
  }, [snapshot?.canManage]);

  async function lookupTeam() {
    if (!supabase || !selectedGroupId || !teamCode.trim()) return;
    setBusyKey("lookup");
    setMessage("");
    const result = await supabase.rpc("lookup_pachanga_team_by_code", {
      opponent_team_code: teamCode.trim(),
      target_group_id: selectedGroupId,
    });
    setBusyKey("");
    if (result.error) {
      setConfirmedTeam(null);
      setMessage(result.error.message);
      return;
    }
    const value = result.data as Partial<TeamSummary> | null;
    if (!value?.groupId || !value.name || !value.teamCode) {
      setMessage("El servidor no devolvió un equipo válido.");
      return;
    }
    setConfirmedTeam({ groupId: value.groupId, name: value.name, teamCode: value.teamCode });
  }

  async function createOrProposeChallenge() {
    if (!supabase || !snapshot || !navigator.onLine) {
      setMessage("Conéctate para enviar el reto. No se guardará como confirmado sin respuesta del servidor.");
      return;
    }
    if (!draft.scheduledAt || !draft.fieldName.trim() || !draft.fieldAddress.trim()) {
      setMessage("Indica fecha, campo y dirección antes de enviar.");
      return;
    }

    const fingerprint = editingChallenge
      ? `challenge:${editingChallenge.id}:propose:${editingChallenge.revision}:${challengeDraftFingerprint(draft)}`
      : `challenge:create:${selectedGroupId}:${confirmedTeam?.teamCode ?? ""}:${snapshot.socialRevision}:${challengeDraftFingerprint(draft)}`;
    const operationId = operationIdFor(fingerprint);
    setBusyKey(editingChallenge ? `propose:${editingChallenge.id}` : "create");
    setMessage("");

    const common = {
      client_metadata: operationMetadata(),
      operation_id: operationId,
      target_field_address: draft.fieldAddress.trim(),
      target_field_maps_url: draft.fieldMapsUrl.trim() || null,
      target_field_name: draft.fieldName.trim(),
      target_field_place_id: draft.fieldPlaceId.trim() || null,
      target_message: draft.message.trim() || null,
      target_modality: draft.modality,
      target_scheduled_at: new Date(draft.scheduledAt).toISOString(),
    };
    const result = editingChallenge
      ? await supabase.rpc("respond_pachanga_team_challenge_authoritative", {
          ...common,
          expected_revision: editingChallenge.revision,
          target_action: "propose_changes",
          target_challenge_id: editingChallenge.id,
          target_group_id: selectedGroupId,
        })
      : await supabase.rpc("create_pachanga_team_challenge_authoritative", {
          ...common,
          expected_revision: snapshot.socialRevision,
          opponent_team_code: confirmedTeam?.teamCode ?? "",
          target_group_id: selectedGroupId,
        });
    setBusyKey("");
    if (result.error) {
      setMessage(result.error.message);
      if (result.error.code === "PT409") await loadSnapshot(selectedGroupId, currentUserId);
      return;
    }
    operationIdsRef.current.delete(fingerprint);
    if (!acceptCanonicalSnapshot(result.data, currentUserId, selectedGroupId)) {
      setMessage("El servidor confirmó la acción, pero el snapshot recibido no era válido. Recargando.");
      await loadSnapshot(selectedGroupId, currentUserId);
      return;
    }
    setEditingChallengeId(null);
    setConfirmedTeam(null);
    setTeamCode("");
    setDraft(emptyDraft);
    setMessage(editingChallenge ? "Cambios enviados y confirmados." : "Reto enviado y confirmado.");
  }

  async function respond(challenge: TeamChallenge, action: Exclude<TeamChallengeAction, "propose_changes">) {
    if (!supabase || !snapshot || !navigator.onLine) {
      setMessage("Conéctate para responder. El estado no cambiará sin confirmación del servidor.");
      return;
    }
    const fingerprint = `challenge:${challenge.id}:${action}:${challenge.revision}`;
    setBusyKey(`${action}:${challenge.id}`);
    setMessage("");
    const result = await supabase.rpc("respond_pachanga_team_challenge_authoritative", {
      client_metadata: operationMetadata(),
      expected_revision: challenge.revision,
      operation_id: operationIdFor(fingerprint),
      target_action: action,
      target_challenge_id: challenge.id,
      target_field_address: null,
      target_field_maps_url: null,
      target_field_name: null,
      target_field_place_id: null,
      target_group_id: selectedGroupId,
      target_message: null,
      target_modality: null,
      target_scheduled_at: null,
    });
    setBusyKey("");
    if (result.error) {
      setMessage(result.error.message);
      if (result.error.code === "PT409") await loadSnapshot(selectedGroupId, currentUserId);
      return;
    }
    operationIdsRef.current.delete(fingerprint);
    if (!acceptCanonicalSnapshot(result.data, currentUserId, selectedGroupId)) {
      setMessage("El servidor confirmó la acción, pero el snapshot recibido no era válido. Recargando.");
      await loadSnapshot(selectedGroupId, currentUserId);
      return;
    }
    setMessage(action === "accept" ? "Reto aceptado." : action === "reject" ? "Reto rechazado." : "Reto cancelado.");
  }

  function editChallenge(challenge: TeamChallenge) {
    setEditingChallengeId(challenge.id);
    setConfirmedTeam(challenge.opponent);
    setTeamCode(challenge.opponent.teamCode);
    setDraft(draftFromChallenge(challenge));
    document.getElementById("private-challenge-form")?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  if (loading) return <section className="market-panel team-challenges-loading">Cargando retos…</section>;
  if (!memberships.length) {
    return <section className="market-panel team-challenges-empty">Necesitas pertenecer a un equipo para usar retos privados.</section>;
  }

  const pendingChallenges = snapshot?.challenges.filter((challenge) => challenge.status === "proposed" || challenge.status === "changes_proposed") ?? [];
  const acceptedChallenges = snapshot?.challenges.filter((challenge) => challenge.status === "accepted") ?? [];
  const resolvedChallenges = snapshot?.challenges.filter((challenge) => challenge.status === "rejected" || challenge.status === "cancelled" || challenge.status === "expired") ?? [];

  return (
    <section className="team-challenges-area" aria-label="Retos privados entre equipos">
      <div className="team-challenges-toolbar">
        <label>
          Equipo
          <select value={selectedGroupId} onChange={(event) => selectGroup(event.target.value)}>
            {memberships.map((membership) => <option key={membership.groupId} value={membership.groupId}>{membership.name}</option>)}
          </select>
        </label>
        <div>
          <span>Código propio</span>
          <strong>{selectedMembership?.teamCode || "Pendiente"}</strong>
        </div>
        <div>
          <span>Sincronización</span>
          <strong>{snapshot ? `Revisión ${snapshot.socialRevision}` : "Sin snapshot"}</strong>
        </div>
      </div>

      {snapshot?.canManage ? (
        <section className="market-panel private-challenge-form" id="private-challenge-form">
          <header>
            <div>
              <span>{editingChallenge ? "Contrapropuesta" : "Reto privado"}</span>
              <strong>{editingChallenge ? `Cambios para ${editingChallenge.opponent.name}` : "Retar mediante código"}</strong>
            </div>
            {editingChallenge ? <button type="button" onClick={() => { setEditingChallengeId(null); setConfirmedTeam(null); setTeamCode(""); setDraft(emptyDraft); }}>Cerrar edición</button> : null}
          </header>

          {!editingChallenge ? (
            <div className="challenge-team-code-row">
              <label>
                Código del rival
                <input value={teamCode} onChange={(event) => { setTeamCode(event.target.value.toUpperCase()); setConfirmedTeam(null); }} placeholder="ABC123" />
              </label>
              <button type="button" onClick={() => void lookupTeam()} disabled={!teamCode.trim() || busyKey === "lookup"}>Comprobar</button>
              {confirmedTeam ? <div className="challenge-confirmed-team"><span>Equipo confirmado</span><strong>{confirmedTeam.name}</strong></div> : null}
            </div>
          ) : null}

          <div className="challenge-fields-grid">
            <label>
              Fecha y hora
              <input type="datetime-local" value={draft.scheduledAt} onChange={(event) => setDraft((current) => ({ ...current, scheduledAt: event.target.value }))} />
            </label>
            <label>
              Modalidad
              <select value={draft.modality} onChange={(event) => setDraft((current) => ({ ...current, modality: event.target.value as TeamChallengeModality }))}>
                <option value="sala">Fútbol sala</option>
                <option value="futbol7">Fútbol 7</option>
                <option value="futbol11">Fútbol 11</option>
              </select>
            </label>
            <label>
              Campo
              <input ref={fieldInputRef} value={draft.fieldName} onChange={(event) => setDraft((current) => ({ ...current, fieldName: event.target.value, fieldPlaceId: "" }))} placeholder="Busca o escribe el campo" />
            </label>
            <label>
              Dirección
              <input value={draft.fieldAddress} onChange={(event) => setDraft((current) => ({ ...current, fieldAddress: event.target.value }))} placeholder="Dirección completa" />
            </label>
            <label className="challenge-wide-field">
              Enlace de Google Maps opcional
              <input value={draft.fieldMapsUrl} onChange={(event) => setDraft((current) => ({ ...current, fieldMapsUrl: event.target.value, fieldPlaceId: "" }))} placeholder="https://www.google.com/maps/..." />
            </label>
            <label className="challenge-message-field">
              Mensaje opcional
              <textarea value={draft.message} maxLength={1200} onChange={(event) => setDraft((current) => ({ ...current, message: event.target.value }))} placeholder="Detalles útiles para el rival" />
            </label>
          </div>
          <button
            className="challenge-primary-action"
            type="button"
            onClick={() => void createOrProposeChallenge()}
            disabled={Boolean(busyKey) || (!editingChallenge && !confirmedTeam)}
          >
            {editingChallenge ? "Enviar cambios" : "Enviar reto"}
          </button>
        </section>
      ) : (
        <p className="market-panel team-challenges-readonly">Puedes consultar los retos. Solo admins y owner pueden responder o crear propuestas.</p>
      )}

      {message ? <p className="team-challenges-message" aria-live="polite">{message}</p> : null}

      <div className="team-challenges-columns">
        <section className="market-panel challenge-list-panel">
          <header><span>Retos pendientes</span><strong>{pendingChallenges.length}</strong></header>
          <div className="challenge-list">
            {pendingChallenges.map((challenge) => {
              const canAnswer = snapshot?.canManage && challenge.lastProposedBy === "opponent";
              return (
                <article className="challenge-card" key={challenge.id}>
                  <div className="challenge-card-heading">
                    <div><span>{challenge.direction === "incoming" ? "Recibido de" : "Enviado a"}</span><strong>{challenge.opponent.name}</strong></div>
                    <span className={`challenge-status ${challenge.status}`}>{teamChallengeStatusLabel(challenge.status)}</span>
                  </div>
                  <dl>
                    <div><dt>Cuándo</dt><dd>{formatDateTime(challenge.scheduledAt)}</dd></div>
                    <div><dt>Modalidad</dt><dd>{teamChallengeModalityLabel(challenge.modality)}</dd></div>
                    <div><dt>Campo</dt><dd>{challenge.field.name}</dd></div>
                    <div><dt>Dirección</dt><dd>{challenge.field.address}</dd></div>
                  </dl>
                  {challenge.message ? <p>{challenge.message}</p> : null}
                  {challenge.field.mapsUrl ? <a href={challenge.field.mapsUrl} target="_blank" rel="noreferrer">Abrir en Google Maps</a> : null}
                  {snapshot?.canManage ? (
                    <div className="challenge-card-actions">
                      {canAnswer ? <button type="button" onClick={() => void respond(challenge, "accept")} disabled={Boolean(busyKey)}>Aceptar</button> : null}
                      <button type="button" onClick={() => editChallenge(challenge)} disabled={Boolean(busyKey)}>Proponer cambios</button>
                      {canAnswer ? <button type="button" onClick={() => void respond(challenge, "reject")} disabled={Boolean(busyKey)}>Rechazar</button> : null}
                      {challenge.direction === "outgoing" ? <button type="button" onClick={() => void respond(challenge, "cancel")} disabled={Boolean(busyKey)}>Cancelar</button> : null}
                    </div>
                  ) : null}
                </article>
              );
            })}
            {!pendingChallenges.length ? <p className="market-empty">No hay retos pendientes.</p> : null}
          </div>
        </section>

        <section className="market-panel known-opponents-panel">
          <header><span>Rivales conocidos</span><strong>{snapshot?.knownOpponents.length ?? 0}</strong></header>
          <div className="known-opponents-list">
            {snapshot?.knownOpponents.map((opponent) => (
              <article key={opponent.groupId}>
                <div><strong>{opponent.name}</strong><span>{opponent.matchesPlayed} partido{opponent.matchesPlayed === 1 ? "" : "s"}</span></div>
                <small>Último: {formatDateTime(opponent.lastEncounterAt)}</small>
                {snapshot.canManage ? (
                  <button
                    type="button"
                    onClick={() => {
                      setConfirmedTeam(opponent);
                      setTeamCode(opponent.teamCode);
                      setEditingChallengeId(null);
                      setDraft(emptyDraft);
                      document.getElementById("private-challenge-form")?.scrollIntoView({ behavior: "smooth" });
                    }}
                  >
                    Retar de nuevo
                  </button>
                ) : null}
              </article>
            ))}
            {!snapshot?.knownOpponents.length ? <p className="market-empty">Aparecerán aquí después del primer partido finalizado y enlazado con el rival.</p> : null}
          </div>
        </section>
      </div>

      {selectedGroupId && currentUserId ? (
        <ExternalResultsPanel groupId={selectedGroupId} userId={currentUserId} />
      ) : null}

      {acceptedChallenges.length ? (
        <section className="market-panel resolved-challenges-panel accepted-challenges-panel">
          <header><span>Retos acordados</span><strong>{acceptedChallenges.length}</strong></header>
          <div>
            {acceptedChallenges.map((challenge) => (
              <article key={challenge.id}>
                <strong>{challenge.opponent.name}</strong>
                <span>{formatDateTime(challenge.scheduledAt)}</span>
                <span>{teamChallengeModalityLabel(challenge.modality)} · {challenge.field.name}</span>
                {challenge.field.mapsUrl ? <a href={challenge.field.mapsUrl} target="_blank" rel="noreferrer">Abrir campo</a> : null}
                <b className={`challenge-status ${challenge.status}`}>{teamChallengeStatusLabel(challenge.status)}</b>
              </article>
            ))}
          </div>
        </section>
      ) : null}

      {resolvedChallenges.length ? (
        <section className="market-panel resolved-challenges-panel">
          <header><span>Historial de retos</span><strong>{resolvedChallenges.length}</strong></header>
          <div>
            {resolvedChallenges.map((challenge) => (
              <article key={challenge.id}>
                <strong>{challenge.opponent.name}</strong>
                <span>{formatDateTime(challenge.scheduledAt)}</span>
                <span>{teamChallengeModalityLabel(challenge.modality)}</span>
                <b className={`challenge-status ${challenge.status}`}>{teamChallengeStatusLabel(challenge.status)}</b>
              </article>
            ))}
          </div>
        </section>
      ) : null}
    </section>
  );
}

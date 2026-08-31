"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { attachVenueAutocomplete, type VenuePlace } from "../googlePlacesClient";
import { supabase } from "../supabaseClient";
import {
  challengeDirectionLabel,
  challengePrimaryLabel,
  challengeSuccess,
  groupTeamChallenges,
  safeChallengeError,
  type ChallengeActiveFilter,
  type ChallengeMainView,
  type ChallengeNotice,
} from "../team-challenges-ui-contract";
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
import { ExternalResultsPanel } from "./external-results-panel";
import styles from "../retos/retos.module.css";

const googleMapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;

export type GroupMembership = TeamSummary & {
  role: "admin" | "owner" | "player";
};

export type TeamChallengesShellState = {
  canManage: boolean;
  memberships: GroupMembership[];
  selectedGroupId: string;
};

type ChallengeDraft = {
  fieldAddress: string;
  fieldMapsUrl: string;
  fieldName: string;
  fieldPlaceId: string;
  message: string;
  modality: TeamChallengeModality;
  scheduledDate: string;
  scheduledTime: string;
};

type Props = {
  activeFilter?: ChallengeActiveFilter;
  challengeId?: string;
  creating?: boolean;
  initialOpponent?: TeamSummary | null;
  initialTeamCode?: string;
  matchChallengeId?: string;
  onCloseCreate?: () => void;
  onCloseDetail?: () => void;
  onOpenChallenge?: (challengeId: string) => void;
  onOpenMatch?: (challengeId: string) => void;
  onShellState?: (state: TeamChallengesShellState) => void;
  onStartCreate?: () => void;
  requestedGroupId?: string;
  view?: ChallengeMainView;
};

const emptyDraft: ChallengeDraft = {
  fieldAddress: "",
  fieldMapsUrl: "",
  fieldName: "",
  fieldPlaceId: "",
  message: "",
  modality: "futbol7",
  scheduledDate: "",
  scheduledTime: "",
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
    surface: window.matchMedia("(display-mode: standalone)").matches ? "pwa-team-challenges" : "web-team-challenges",
  };
}

function localDateParts(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return { scheduledDate: "", scheduledTime: "" };
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000).toISOString();
  return { scheduledDate: local.slice(0, 10), scheduledTime: local.slice(11, 16) };
}

function scheduledIso(draft: ChallengeDraft) {
  if (!draft.scheduledDate || !draft.scheduledTime) return "";
  const date = new Date(`${draft.scheduledDate}T${draft.scheduledTime}:00`);
  return Number.isNaN(date.getTime()) ? "" : date.toISOString();
}

function formatDateTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return { day: value, time: "" };
  return {
    day: new Intl.DateTimeFormat("es-ES", { day: "numeric", month: "short", weekday: "short" }).format(date),
    time: new Intl.DateTimeFormat("es-ES", { hour: "2-digit", minute: "2-digit" }).format(date),
  };
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
    ...localDateParts(challenge.scheduledAt),
  };
}

function challengeDraftFingerprint(draft: ChallengeDraft) {
  return JSON.stringify(draft);
}

function hasDraftContent(draft: ChallengeDraft) {
  return Boolean(draft.fieldName || draft.scheduledDate || draft.scheduledTime || draft.message);
}

function TeamMark({ team }: { team: TeamSummary }) {
  const initials = team.name.split(/\s+/).slice(0, 2).map((part) => part[0] ?? "").join("").toUpperCase();
  return <span className={styles.teamMark} aria-hidden="true">{initials || "IQ"}</span>;
}

export function TeamChallengesPanel({
  activeFilter = "all",
  challengeId = "",
  creating = false,
  initialOpponent,
  initialTeamCode = "",
  matchChallengeId = "",
  onCloseCreate,
  onCloseDetail,
  onOpenChallenge,
  onOpenMatch,
  onShellState,
  onStartCreate,
  requestedGroupId = "",
  view = "active",
}: Props) {
  const [memberships, setMemberships] = useState<GroupMembership[]>([]);
  const [selectedGroupId, setSelectedGroupId] = useState("");
  const [currentUserId, setCurrentUserId] = useState("");
  const [snapshot, setSnapshot] = useState<TeamSocialSnapshot | null>(null);
  const [teamCode, setTeamCode] = useState(initialOpponent?.teamCode ?? initialTeamCode);
  const [confirmedTeam, setConfirmedTeam] = useState<TeamSummary | null>(initialOpponent ?? null);
  const [draft, setDraft] = useState<ChallengeDraft>(emptyDraft);
  const [wizardStep, setWizardStep] = useState<1 | 2 | 3>(1);
  const [editingChallengeId, setEditingChallengeId] = useState<string | null>(null);
  const [opponentQuery, setOpponentQuery] = useState("");
  const [showAllOpponents, setShowAllOpponents] = useState(false);
  const [notice, setNotice] = useState<ChallengeNotice | null>(supabase ? null : safeChallengeError(null));
  const [loading, setLoading] = useState(Boolean(supabase));
  const [busyKey, setBusyKey] = useState("");
  const fieldInputRef = useRef<HTMLInputElement>(null);
  const operationIdsRef = useRef(new Map<string, string>());
  const realtimeRefreshRef = useRef<number | null>(null);
  const autoLookupRef = useRef("");

  const selectedMembership = useMemo(
    () => memberships.find((membership) => membership.groupId === selectedGroupId) ?? null,
    [memberships, selectedGroupId],
  );
  const selectedChallenge = useMemo(
    () => snapshot?.challenges.find((challenge) => challenge.id === challengeId) ?? null,
    [challengeId, snapshot?.challenges],
  );
  const editingChallenge = useMemo(
    () => snapshot?.challenges.find((challenge) => challenge.id === editingChallengeId) ?? null,
    [editingChallengeId, snapshot?.challenges],
  );
  const groups = useMemo(
    () => groupTeamChallenges(snapshot?.challenges ?? [], activeFilter),
    [activeFilter, snapshot?.challenges],
  );
  const knownOpponents = useMemo(() => {
    const query = opponentQuery.trim().toLocaleLowerCase("es");
    const filtered = (snapshot?.knownOpponents ?? []).filter((opponent) => !query || opponent.name.toLocaleLowerCase("es").includes(query));
    return showAllOpponents || query ? filtered : filtered.slice(0, 5);
  }, [opponentQuery, showAllOpponents, snapshot?.knownOpponents]);

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
    try {
      writeTeamSocialCache(window.localStorage, userId, groupId, canonical);
    } catch {
      // The local copy is disposable; canonical state remains on the server.
    }
    return true;
  }, []);

  const loadSnapshot = useCallback(async (groupId: string, userId: string) => {
    if (!supabase || !groupId) return;
    const result = await supabase.rpc("get_pachanga_team_social_snapshot", { target_group_id: groupId });
    if (result.error) {
      setNotice(safeChallengeError(result.error));
      return;
    }
    if (!acceptCanonicalSnapshot(result.data, userId, groupId)) setNotice(safeChallengeError(null));
  }, [acceptCanonicalSnapshot]);

  const scheduleCanonicalRefresh = useCallback(() => {
    if (!selectedGroupId || !currentUserId) return;
    if (realtimeRefreshRef.current !== null) window.clearTimeout(realtimeRefreshRef.current);
    realtimeRefreshRef.current = window.setTimeout(() => {
      realtimeRefreshRef.current = null;
      void loadSnapshot(selectedGroupId, currentUserId);
    }, 140);
  }, [currentUserId, loadSnapshot, selectedGroupId]);

  useEffect(() => {
    if (!supabase) return;
    let active = true;
    async function loadGroups() {
      const session = await supabase?.auth.getSession();
      const user = session?.data.session?.user ?? null;
      if (!active) return;
      if (!user) {
        setLoading(false);
        setNotice({ body: "Inicia sesión para ver los retos de tus equipos.", stale: false, title: "Tu sesión está cerrada", tone: "info" });
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
        setNotice(safeChallengeError(result.error));
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
    return () => { active = false; };
  }, [loadSnapshot]);

  const selectGroup = useCallback((groupId: string) => {
    if (!groupId || !currentUserId || groupId === selectedGroupId) return;
    setSelectedGroupId(groupId);
    window.localStorage.setItem("pachangas-social-selected-group", groupId);
    setSnapshot(readTeamSocialCache(window.localStorage, currentUserId, groupId));
    setConfirmedTeam(null);
    setEditingChallengeId(null);
    setDraft(emptyDraft);
    setWizardStep(1);
    setNotice(null);
    void loadSnapshot(groupId, currentUserId);
  }, [currentUserId, loadSnapshot, selectedGroupId]);

  useEffect(() => {
    if (requestedGroupId) queueMicrotask(() => selectGroup(requestedGroupId));
  }, [requestedGroupId, selectGroup]);

  useEffect(() => {
    onShellState?.({ canManage: Boolean(snapshot?.canManage), memberships, selectedGroupId });
  }, [memberships, onShellState, selectedGroupId, snapshot?.canManage]);

  useEffect(() => {
    if (!supabase || !selectedGroupId) return;
    const client = supabase;
    const channel = client
      .channel(`pachanga-team-social-${selectedGroupId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "pachanga_team_social_state", filter: `group_id=eq.${selectedGroupId}` },
        scheduleCanonicalRefresh,
      )
      .subscribe((status) => {
        if (status === "SUBSCRIBED") scheduleCanonicalRefresh();
      });
    return () => {
      if (realtimeRefreshRef.current !== null) window.clearTimeout(realtimeRefreshRef.current);
      void client.removeChannel(channel);
    };
  }, [scheduleCanonicalRefresh, selectedGroupId]);

  useEffect(() => {
    if (!selectedGroupId || !currentUserId) return;
    const refresh = () => { if (navigator.onLine) scheduleCanonicalRefresh(); };
    const refreshVisible = () => { if (document.visibilityState === "visible") refresh(); };
    window.addEventListener("online", refresh);
    document.addEventListener("visibilitychange", refreshVisible);
    return () => {
      window.removeEventListener("online", refresh);
      document.removeEventListener("visibilitychange", refreshVisible);
    };
  }, [currentUserId, scheduleCanonicalRefresh, selectedGroupId]);

  useEffect(() => {
    if (!snapshot?.canManage || !googleMapsApiKey || !fieldInputRef.current || (!creating && !editingChallenge)) return;
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
        setNotice(null);
      },
    }).then((nextCleanup) => {
      if (disposed) nextCleanup();
      else cleanup = nextCleanup;
    }).catch(() => undefined);
    return () => {
      disposed = true;
      cleanup?.();
    };
  }, [creating, editingChallenge, snapshot?.canManage, wizardStep]);

  useEffect(() => {
    if (!initialTeamCode || !creating) return;
    queueMicrotask(() => {
      setTeamCode(initialTeamCode);
      setConfirmedTeam((current) => current?.teamCode === initialTeamCode ? current : null);
    });
  }, [creating, initialTeamCode]);

  async function lookupTeam(code = teamCode) {
    if (!supabase || !selectedGroupId || !code.trim()) return;
    setBusyKey("lookup");
    setNotice(null);
    const result = await supabase.rpc("lookup_pachanga_team_by_code", {
      opponent_team_code: code.trim(),
      target_group_id: selectedGroupId,
    });
    setBusyKey("");
    if (result.error) {
      setConfirmedTeam(null);
      setNotice(safeChallengeError(result.error));
      return;
    }
    const value = result.data as Partial<TeamSummary> | null;
    if (!value?.groupId || !value.name || !value.teamCode) {
      setNotice(safeChallengeError(null));
      return;
    }
    setConfirmedTeam({ groupId: value.groupId, name: value.name, teamCode: value.teamCode });
    setTeamCode(value.teamCode);
    setNotice({ body: `${value.name} está listo para recibir una propuesta.`, stale: false, title: "Equipo encontrado", tone: "success" });
  }

  useEffect(() => {
    if (!creating || !snapshot?.canManage || !selectedGroupId || !initialTeamCode || autoLookupRef.current === `${selectedGroupId}:${initialTeamCode}`) return;
    autoLookupRef.current = `${selectedGroupId}:${initialTeamCode}`;
    void lookupTeam(initialTeamCode);
    // lookupTeam intentionally follows the canonical URL code once per team.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [creating, initialTeamCode, selectedGroupId, snapshot?.canManage]);

  async function createOrProposeChallenge() {
    if (!supabase || !snapshot || !navigator.onLine) {
      setNotice({ body: "Necesitas conexión para confirmar esta acción.", stale: false, title: "Sin conexión", tone: "error" });
      return;
    }
    const scheduledAt = scheduledIso(draft);
    if (!scheduledAt || !draft.fieldName.trim() || !draft.fieldAddress.trim()) {
      setNotice({ body: "Completa fecha, hora, campo y dirección antes de continuar.", stale: false, title: "Faltan datos", tone: "error" });
      return;
    }
    const fingerprint = editingChallenge
      ? `challenge:${editingChallenge.id}:propose:${editingChallenge.revision}:${challengeDraftFingerprint(draft)}`
      : `challenge:create:${selectedGroupId}:${confirmedTeam?.teamCode ?? ""}:${snapshot.socialRevision}:${challengeDraftFingerprint(draft)}`;
    const operationId = operationIdFor(fingerprint);
    setBusyKey(editingChallenge ? `propose:${editingChallenge.id}` : "create");
    setNotice(null);
    const common = {
      client_metadata: operationMetadata(),
      operation_id: operationId,
      target_field_address: draft.fieldAddress.trim(),
      target_field_maps_url: draft.fieldMapsUrl.trim() || null,
      target_field_name: draft.fieldName.trim(),
      target_field_place_id: draft.fieldPlaceId.trim() || null,
      target_message: draft.message.trim() || null,
      target_modality: draft.modality,
      target_scheduled_at: scheduledAt,
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
      const nextNotice = safeChallengeError(result.error);
      setNotice(nextNotice);
      if (nextNotice.stale) await loadSnapshot(selectedGroupId, currentUserId);
      return;
    }
    operationIdsRef.current.delete(fingerprint);
    if (!acceptCanonicalSnapshot(result.data, currentUserId, selectedGroupId)) {
      setNotice(safeChallengeError(null));
      await loadSnapshot(selectedGroupId, currentUserId);
      return;
    }
    const wasEditing = Boolean(editingChallenge);
    setEditingChallengeId(null);
    setConfirmedTeam(null);
    setTeamCode("");
    setDraft(emptyDraft);
    setWizardStep(1);
    setNotice(challengeSuccess(wasEditing ? "La contrapropuesta está confirmada por el servidor." : "El reto está confirmado y esperando al rival."));
    if (wasEditing) onCloseDetail?.();
    else onCloseCreate?.();
  }

  async function respond(challenge: TeamChallenge, action: Exclude<TeamChallengeAction, "propose_changes">) {
    if (!supabase || !snapshot || !navigator.onLine) {
      setNotice({ body: "Necesitas conexión para confirmar esta acción.", stale: false, title: "Sin conexión", tone: "error" });
      return;
    }
    if ((action === "reject" || action === "cancel") && !window.confirm(action === "reject" ? "¿Rechazar este reto?" : "¿Cancelar este reto? Seguirá en el historial.")) return;
    const fingerprint = `challenge:${challenge.id}:${action}:${challenge.revision}`;
    setBusyKey(`${action}:${challenge.id}`);
    setNotice(null);
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
      const nextNotice = safeChallengeError(result.error);
      setNotice(nextNotice);
      if (nextNotice.stale) await loadSnapshot(selectedGroupId, currentUserId);
      return;
    }
    operationIdsRef.current.delete(fingerprint);
    if (!acceptCanonicalSnapshot(result.data, currentUserId, selectedGroupId)) {
      setNotice(safeChallengeError(null));
      await loadSnapshot(selectedGroupId, currentUserId);
      return;
    }
    setNotice(challengeSuccess(action === "accept" ? "El reto está acordado. Ya podéis abrir el partido." : action === "reject" ? "El reto se ha rechazado y queda en el historial." : "El reto se ha cancelado y queda en el historial."));
    if (action !== "accept") onCloseDetail?.();
  }

  function editChallenge(challenge: TeamChallenge) {
    setEditingChallengeId(challenge.id);
    setConfirmedTeam(challenge.opponent);
    setTeamCode(challenge.opponent.teamCode);
    setDraft(draftFromChallenge(challenge));
    setNotice(null);
    onOpenChallenge?.(challenge.id);
  }

  async function shareTeamCode() {
    const code = selectedMembership?.teamCode;
    if (!code) return;
    const text = `Reta a ${selectedMembership?.name ?? "nuestro equipo"} en Pachangas IQ con el código ${code}.`;
    try {
      if (typeof navigator.share === "function") await navigator.share({ text, title: "Reto de Pachangas IQ" });
      else await navigator.clipboard.writeText(code);
      setNotice(challengeSuccess("Código de equipo listo para compartir."));
    } catch {
      setNotice({ body: "Puedes volver a intentarlo desde el menú del equipo.", stale: false, title: "No se pudo compartir", tone: "error" });
    }
  }

  function chooseOpponent(opponent: TeamSummary) {
    setConfirmedTeam(opponent);
    setTeamCode(opponent.teamCode);
    setNotice(null);
  }

  function validateProposalStep() {
    if (!draft.scheduledDate || !draft.scheduledTime || !draft.fieldName.trim()) {
      setNotice({ body: "Completa fecha, hora y campo para continuar.", stale: false, title: "Faltan datos", tone: "error" });
      return false;
    }
    if (!draft.fieldAddress.trim()) {
      setNotice({ body: "Añade la dirección completa dentro de Más detalles.", stale: false, title: "Falta la dirección", tone: "error" });
      return false;
    }
    setNotice(null);
    return true;
  }

  function renderNotice() {
    return notice ? (
      <div className={styles.notice} data-tone={notice.tone} role={notice.tone === "error" ? "alert" : "status"} aria-live="polite">
        <strong>{notice.title}</strong><span>{notice.body}</span>
      </div>
    ) : null;
  }

  function renderWizard() {
    if (!snapshot?.canManage) return null;
    return (
      <section className={styles.focusSurface} aria-label="Crear reto en tres pasos" data-challenge-wizard-step={wizardStep}>
        <header className={styles.focusHeader}>
          <div><span>{hasDraftContent(draft) ? "Borrador local" : "Nuevo reto"}</span><h2>Retar equipo</h2></div>
          <button type="button" onClick={onCloseCreate}>Cerrar</button>
        </header>
        <ol className={styles.stepper} aria-label="Progreso del reto">
          {[1, 2, 3].map((step) => <li aria-current={wizardStep === step ? "step" : undefined} data-complete={wizardStep > step} key={step}><b>{step}</b><span>{step === 1 ? "Rival" : step === 2 ? "Propuesta" : "Revisar"}</span></li>)}
        </ol>

        {wizardStep === 1 ? (
          <div className={styles.wizardBody}>
            <div className={styles.sectionTitle}><span>Paso 1</span><h3>Elige rival</h3></div>
            {confirmedTeam ? (
              <article className={styles.confirmedOpponent}><TeamMark team={confirmedTeam} /><div><span>Equipo confirmado</span><strong>{confirmedTeam.name}</strong></div><button type="button" onClick={() => setConfirmedTeam(null)}>Cambiar</button></article>
            ) : (
              <>
                {snapshot.knownOpponents.length ? (
                  <section className={styles.opponentPicker}>
                    <header><strong>Rivales conocidos</strong><input aria-label="Buscar rival conocido" placeholder="Buscar" value={opponentQuery} onChange={(event) => setOpponentQuery(event.target.value)} /></header>
                    <div>{knownOpponents.map((opponent) => (
                      <button key={opponent.groupId} type="button" onClick={() => chooseOpponent(opponent)}><TeamMark team={opponent} /><span><strong>{opponent.name}</strong><small>{opponent.matchesPlayed} partido{opponent.matchesPlayed === 1 ? "" : "s"} · último {formatDateTime(opponent.lastEncounterAt).day}</small></span><b aria-hidden="true">›</b></button>
                    ))}</div>
                    {!showAllOpponents && snapshot.knownOpponents.length > 5 ? <button className={styles.textButton} type="button" onClick={() => setShowAllOpponents(true)}>Ver todos</button> : null}
                  </section>
                ) : null}
                <div className={styles.codeLookup}>
                  <label><span>Código del equipo</span><input value={teamCode} onChange={(event) => { setTeamCode(event.target.value.toUpperCase()); setConfirmedTeam(null); }} placeholder="ABC123" /></label>
                  <button type="button" onClick={() => void lookupTeam()} disabled={!teamCode.trim() || busyKey === "lookup"}>{busyKey === "lookup" ? "Comprobando" : "Comprobar"}</button>
                </div>
              </>
            )}
            <div className={styles.wizardActions}><span /><button className={styles.primaryAction} type="button" disabled={!confirmedTeam} onClick={() => setWizardStep(2)}>Continuar</button></div>
          </div>
        ) : null}

        {wizardStep === 2 ? (
          <div className={styles.wizardBody}>
            <div className={styles.sectionTitle}><span>Paso 2</span><h3>Cuándo y dónde</h3></div>
            <div className={styles.proposalGrid}>
              <label><span>Fecha</span><input type="date" value={draft.scheduledDate} onChange={(event) => setDraft((current) => ({ ...current, scheduledDate: event.target.value }))} /></label>
              <label><span>Hora</span><input type="time" value={draft.scheduledTime} onChange={(event) => setDraft((current) => ({ ...current, scheduledTime: event.target.value }))} /></label>
              <label><span>Modalidad</span><select value={draft.modality} onChange={(event) => setDraft((current) => ({ ...current, modality: event.target.value as TeamChallengeModality }))}><option value="sala">Fútbol sala</option><option value="futbol7">Fútbol 7</option><option value="futbol11">Fútbol 11</option></select></label>
              <label><span>Campo</span><input ref={fieldInputRef} value={draft.fieldName} onChange={(event) => setDraft((current) => ({ ...current, fieldName: event.target.value, fieldPlaceId: "" }))} placeholder="Busca o escribe el campo" /></label>
            </div>
            <details className={styles.moreDetails}>
              <summary>Más detalles</summary>
              <div>
                <label><span>Dirección completa</span><input value={draft.fieldAddress} onChange={(event) => setDraft((current) => ({ ...current, fieldAddress: event.target.value }))} /></label>
                <label><span>Enlace de Maps</span><input value={draft.fieldMapsUrl} onChange={(event) => setDraft((current) => ({ ...current, fieldMapsUrl: event.target.value, fieldPlaceId: "" }))} /></label>
                <label><span>Mensaje opcional</span><textarea maxLength={1200} value={draft.message} onChange={(event) => setDraft((current) => ({ ...current, message: event.target.value }))} /></label>
              </div>
            </details>
            <div className={styles.wizardActions}><button type="button" onClick={() => setWizardStep(1)}>Atrás</button><button className={styles.primaryAction} type="button" onClick={() => { if (validateProposalStep()) setWizardStep(3); }}>Revisar</button></div>
          </div>
        ) : null}

        {wizardStep === 3 && confirmedTeam ? (
          <div className={styles.wizardBody}>
            <div className={styles.sectionTitle}><span>Paso 3</span><h3>Revisa la propuesta</h3></div>
            <article className={styles.reviewCard}>
              <div><strong>{selectedMembership?.name}</strong><b>vs</b><strong>{confirmedTeam.name}</strong></div>
              <dl><div><dt>Cuándo</dt><dd>{formatDateTime(scheduledIso(draft)).day} · {formatDateTime(scheduledIso(draft)).time}</dd></div><div><dt>Modalidad</dt><dd>{teamChallengeModalityLabel(draft.modality)}</dd></div><div><dt>Campo</dt><dd>{draft.fieldName}</dd></div>{draft.message ? <div><dt>Mensaje</dt><dd>{draft.message}</dd></div> : null}</dl>
            </article>
            <p className={styles.canonicalHint}>El reto solo se enviará al confirmar este último paso.</p>
            <div className={styles.wizardActions}><button type="button" onClick={() => setWizardStep(2)}>Atrás</button><button className={styles.primaryAction} type="button" disabled={Boolean(busyKey)} onClick={() => void createOrProposeChallenge()}>{busyKey === "create" ? "Enviando" : "Enviar reto"}</button></div>
          </div>
        ) : null}
        {renderNotice()}
      </section>
    );
  }

  function renderCounterproposal(challenge: TeamChallenge) {
    const current = formatDateTime(challenge.scheduledAt);
    const original = draftFromChallenge(challenge);
    return (
      <section className={styles.counterproposal} aria-label="Contrapropuesta">
        <div className={styles.sectionTitle}><span>Propuesta actual</span><h3>{current.day} · {current.time}</h3><p>{challenge.field.name}</p></div>
        <div className={styles.sectionTitle}><span>Tu contrapropuesta</span><h3>Cambia solo lo necesario</h3></div>
        <div className={styles.proposalGrid}>
          <label data-changed={draft.scheduledDate !== original.scheduledDate}><span>Fecha</span><input type="date" value={draft.scheduledDate} onChange={(event) => setDraft((value) => ({ ...value, scheduledDate: event.target.value }))} /></label>
          <label data-changed={draft.scheduledTime !== original.scheduledTime}><span>Hora</span><input type="time" value={draft.scheduledTime} onChange={(event) => setDraft((value) => ({ ...value, scheduledTime: event.target.value }))} /></label>
          <label data-changed={draft.modality !== original.modality}><span>Modalidad</span><select value={draft.modality} onChange={(event) => setDraft((value) => ({ ...value, modality: event.target.value as TeamChallengeModality }))}><option value="sala">Fútbol sala</option><option value="futbol7">Fútbol 7</option><option value="futbol11">Fútbol 11</option></select></label>
          <label data-changed={draft.fieldName !== original.fieldName}><span>Campo</span><input ref={fieldInputRef} value={draft.fieldName} onChange={(event) => setDraft((value) => ({ ...value, fieldName: event.target.value, fieldPlaceId: "" }))} /></label>
        </div>
        <details className={styles.moreDetails}><summary>Más detalles</summary><div><label><span>Dirección</span><input value={draft.fieldAddress} onChange={(event) => setDraft((value) => ({ ...value, fieldAddress: event.target.value }))} /></label><label><span>Maps</span><input value={draft.fieldMapsUrl} onChange={(event) => setDraft((value) => ({ ...value, fieldMapsUrl: event.target.value }))} /></label><label><span>Mensaje</span><textarea value={draft.message} onChange={(event) => setDraft((value) => ({ ...value, message: event.target.value }))} /></label></div></details>
        <div className={styles.wizardActions}><button type="button" onClick={() => setEditingChallengeId(null)}>Cancelar</button><button className={styles.primaryAction} type="button" disabled={Boolean(busyKey)} onClick={() => void createOrProposeChallenge()}>{busyKey.startsWith("propose") ? "Enviando" : "Enviar cambios"}</button></div>
      </section>
    );
  }

  function renderDetail(challenge: TeamChallenge) {
    const when = formatDateTime(challenge.scheduledAt);
    const needsResponse = challenge.lastProposedBy === "opponent" && (challenge.status === "proposed" || challenge.status === "changes_proposed");
    return (
      <section className={styles.focusSurface} aria-label={`Reto contra ${challenge.opponent.name}`}>
        <header className={styles.focusHeader}><div><span>{challengeDirectionLabel(challenge)}</span><h2>{challenge.opponent.name}</h2></div><button type="button" onClick={onCloseDetail}>Cerrar</button></header>
        <div className={styles.detailHero}><TeamMark team={challenge.opponent} /><div><span>{teamChallengeStatusLabel(challenge.status)}</span><strong>{when.day} · {when.time}</strong><p>{teamChallengeModalityLabel(challenge.modality)} · {challenge.field.name}</p></div></div>
        <dl className={styles.detailList}>
          <div><dt>Última propuesta</dt><dd>{challenge.lastProposedBy === "own" ? "Tu equipo" : challenge.opponent.name}</dd></div>
          <div><dt>Campo</dt><dd>{challenge.field.name}</dd></div>
          <div><dt>Dirección</dt><dd>{challenge.field.address}</dd></div>
          {challenge.message ? <div><dt>Mensaje</dt><dd>{challenge.message}</dd></div> : null}
        </dl>
        <div className={styles.detailActions}>
          {challenge.status === "accepted" ? <button className={styles.primaryAction} type="button" onClick={() => onOpenMatch?.(challenge.id)}>Ver partido</button> : null}
          {needsResponse && snapshot?.canManage ? <button className={styles.primaryAction} type="button" disabled={Boolean(busyKey)} onClick={() => void respond(challenge, "accept")}>{challenge.status === "changes_proposed" ? "Aceptar cambios" : "Aceptar"}</button> : null}
          {needsResponse && snapshot?.canManage ? <button type="button" onClick={() => editChallenge(challenge)}>Proponer otros cambios</button> : null}
          {challenge.field.mapsUrl ? <a href={challenge.field.mapsUrl} target="_blank" rel="noreferrer">Abrir campo</a> : null}
          {snapshot?.canManage && challenge.direction === "outgoing" && challenge.lastProposedBy === "own" && challenge.status !== "accepted" ? <button type="button" onClick={() => editChallenge(challenge)}>Modificar propuesta</button> : null}
          {snapshot?.canManage && (challenge.status === "proposed" || challenge.status === "changes_proposed") ? (
            <details className={styles.destructiveMenu}><summary aria-label="Más acciones para el reto">•••</summary><div>{needsResponse ? <button type="button" onClick={() => void respond(challenge, "reject")}>Rechazar</button> : null}{challenge.direction === "outgoing" ? <button type="button" onClick={() => void respond(challenge, "cancel")}>Cancelar reto</button> : null}</div></details>
          ) : null}
        </div>
        {!snapshot?.canManage && (challenge.status === "proposed" || challenge.status === "changes_proposed") ? <p className={styles.readonly}>Puedes seguir la propuesta. Solo un admin u owner del equipo puede responder.</p> : null}
        {editingChallengeId === challenge.id ? renderCounterproposal(challenge) : null}
        {renderNotice()}
      </section>
    );
  }

  function renderCard(challenge: TeamChallenge) {
    const when = formatDateTime(challenge.scheduledAt);
    const canRespond = Boolean(snapshot?.canManage && challenge.lastProposedBy === "opponent" && (challenge.status === "proposed" || challenge.status === "changes_proposed"));
    const openPrimary = () => {
      if (challenge.status === "accepted") onOpenMatch?.(challenge.id);
      else if (canRespond) void respond(challenge, "accept");
      else onOpenChallenge?.(challenge.id);
    };
    return (
      <article className={styles.challengeCard} data-state={challenge.status} key={challenge.id}>
        <button className={styles.cardMain} type="button" onClick={() => onOpenChallenge?.(challenge.id)} aria-label={`Ver reto contra ${challenge.opponent.name}`}>
          <TeamMark team={challenge.opponent} />
          <span className={styles.cardIdentity}><strong>{challenge.opponent.name}</strong><small>{challengeDirectionLabel(challenge)}</small></span>
          <span className={styles.cardWhen}><strong>{when.day}</strong><small>{when.time} · {teamChallengeModalityLabel(challenge.modality)}</small></span>
          <span className={styles.cardField}>{challenge.field.name}</span>
        </button>
        <div className={styles.cardActions}>
          <button className={styles.primaryAction} type="button" disabled={Boolean(busyKey)} onClick={openPrimary}>{challengePrimaryLabel(challenge, Boolean(snapshot?.canManage))}</button>
          {canRespond ? <button type="button" onClick={() => editChallenge(challenge)}>Proponer otro momento</button> : null}
          {snapshot?.canManage && (challenge.status === "proposed" || challenge.status === "changes_proposed") ? (
            <details className={styles.cardMenu}><summary aria-label={`Más acciones para ${challenge.opponent.name}`}>•••</summary><div>{challenge.direction === "outgoing" && challenge.lastProposedBy === "own" ? <button type="button" onClick={() => editChallenge(challenge)}>Modificar propuesta</button> : null}{canRespond ? <button type="button" onClick={() => void respond(challenge, "reject")}>Rechazar</button> : null}{challenge.direction === "outgoing" ? <button type="button" onClick={() => void respond(challenge, "cancel")}>Cancelar reto</button> : null}</div></details>
          ) : null}
        </div>
      </article>
    );
  }

  if (loading) return <section className={styles.loadingState} aria-live="polite"><span /><strong>Cargando Retos</strong><p>Recuperando el estado confirmado de tu equipo.</p></section>;
  if (!memberships.length) {
    return (
      <section className={styles.emptyState}>
        <span>Sin equipo</span><h2>No perteneces todavía a ningún equipo.</h2><p>Únete a uno para ver sus retos o encuentra un partido abierto.</p>
        <div><Link href="/?mobile=inicio&create=team">Crear equipo</Link><Link href="/?mobile=perfil&join=team">Unirme a un equipo</Link><Link href="/mercado?tab=partidos">Ver partidos abiertos</Link></div>
        {renderNotice()}
      </section>
    );
  }
  if (matchChallengeId && selectedGroupId && currentUserId) {
    return <div className={styles.matchOrigin} data-challenge-match-origin="retos"><span>Origen: Reto entre equipos</span><ExternalResultsPanel groupId={selectedGroupId} initialChallengeId={matchChallengeId} key={matchChallengeId} userId={currentUserId} /></div>;
  }
  if (creating) return renderWizard();
  if (selectedChallenge) return renderDetail(selectedChallenge);

  const activeCount = groups.needsResponse.length + groups.waiting.length + groups.agreed.length;
  return (
    <section className={styles.challengeArea} aria-label="Retos entre equipos" data-challenge-state={view === "history" ? "terminal" : activeCount ? "ready" : "empty"}>
      {renderNotice()}
      {view === "active" && snapshot?.canManage ? (
        <details className={styles.teamCodeMenu}><summary>Compartir código del equipo</summary><div><strong>{selectedMembership?.teamCode || "Pendiente"}</strong><button type="button" onClick={() => void shareTeamCode()}>Copiar o compartir</button></div></details>
      ) : null}

      {view === "active" ? (
        <>
          {groups.needsResponse.length ? <section className={styles.challengeGroup}><header><span>Necesitan tu respuesta</span><b>{groups.needsResponse.length}</b></header><div>{groups.needsResponse.map(renderCard)}</div></section> : null}
          {groups.waiting.length ? <section className={styles.challengeGroup}><header><span>Esperando al rival</span><b>{groups.waiting.length}</b></header><div>{groups.waiting.map(renderCard)}</div></section> : null}
          {groups.agreed.length ? <section className={styles.challengeGroup}><header><span>Partidos acordados</span><b>{groups.agreed.length}</b></header><div>{groups.agreed.map(renderCard)}</div></section> : null}
          {!activeCount ? <section className={styles.emptyState}><span>Activos</span><h2>Aún no tenéis ningún reto activo.</h2><p>{snapshot?.canManage ? "Elige un rival y proponle día y campo." : "Cuando un admin organice un reto, aparecerá aquí."}</p>{snapshot?.canManage ? <button type="button" onClick={onStartCreate}>Retar equipo</button> : null}</section> : null}
        </>
      ) : (
        <section className={styles.historyList}>
          {groups.history.map((challenge) => {
            const when = formatDateTime(challenge.scheduledAt);
            return <button key={challenge.id} type="button" onClick={() => onOpenChallenge?.(challenge.id)}><TeamMark team={challenge.opponent} /><span><strong>{challenge.opponent.name}</strong><small>{when.day} · {teamChallengeModalityLabel(challenge.modality)}</small></span><b data-status={challenge.status}>{teamChallengeStatusLabel(challenge.status)}</b></button>;
          })}
          {!groups.history.length ? <section className={styles.emptyState}><span>Historial</span><h2>Todavía no hay retos cerrados.</h2><p>Los rechazados, cancelados y expirados aparecerán aquí.</p></section> : null}
        </section>
      )}
    </section>
  );
}

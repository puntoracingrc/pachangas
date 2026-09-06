"use client";

import Link from "next/link";
import { isAdultBirthDate, madridToday, validBirthDate } from "../market-age-contract";
import Image from "next/image";
import { useEffect, useMemo, useRef, useState } from "react";
import { attachVenueAutocomplete, type VenuePlace } from "../googlePlacesClient";
import {
  DEFAULT_SOCIAL_ONBOARDING_DRAFT,
  SOCIAL_DAY_OPTIONS,
  SOCIAL_POSITION_OPTIONS,
  TEAM_CREATION_AUTHORITY,
  normalizeSocialOnboardingDraft,
  parseTeamInvitationInput,
  socialFirstTimeProfileReady,
  socialProfileMinimumReady,
  socialWriteAvailability,
  type SocialEntryState,
  type SocialOnboardingFlow,
  type SocialOnboardingDraft,
  type SocialProfileMinimum,
} from "../social-onboarding-contract";
import {
  DEFAULT_SOCIAL_TEAM_CREATE_DRAFT,
  SOCIAL_TEAM_NAME_MAX_LENGTH,
  SOCIAL_TEAM_NAME_MIN_LENGTH,
  modalityLabel,
  normalizeSocialTeamCreateProgress,
  type SocialTeamCreateDraft,
  type SocialTeamInvitation,
} from "../social-team-core-contract";
import { TEAM_SHIELD_DEFAULT_CONFIG } from "../team-shield-contract";
import { TeamShieldView } from "./team-shield-view";
import styles from "./social-onboarding.module.css";
import polishStyles from "./social-onboarding-polish.module.css";

type FlowView = SocialOnboardingFlow;

export type PendingSocialInvitation = {
  kind: "admin" | "player";
  snapshot?: SocialTeamInvitation | null;
  token: string;
};

type TeamCodePreview = {
  generalArea: string;
  groupId: string;
  memberCount: number;
  modality: string;
  name: string;
  teamCode: string;
  teamRevision: number;
};

type SocialOnboardingProps = {
  canonicalProfile: SocialProfileMinimum | null;
  createDraftStorageKey?: string;
  dismissed: boolean;
  draft: SocialOnboardingDraft;
  entryState: SocialEntryState;
  forcedView?: FlowView | null;
  googleMapsApiKey?: string;
  invitation?: PendingSocialInvitation | null;
  onDismiss: () => void;
  onCreateTeam: (draft: SocialTeamCreateDraft) => Promise<{ error?: string; ok: boolean }>;
  onDraftChange: (draft: SocialOnboardingDraft) => void;
  onForcedViewHandled?: (nextView: FlowView | null) => void;
  onJoin: (invitation: PendingSocialInvitation, displayName: string) => Promise<{ error?: string; ok: boolean }>;
  onLookupTeamCode: (code: string) => Promise<{ error?: string; ok: boolean; team?: TeamCodePreview }>;
  onRequestTeamJoin: (groupId: string, expectedRevision: number) => Promise<{ error?: string; ok: boolean }>;
  onCloseInvitation: (invitation: PendingSocialInvitation) => void;
  onOpen: () => void;
  onProfileSaved?: () => void;
  onSaveProfile: (draft: SocialOnboardingDraft) => Promise<{ error?: string; ok: boolean }>;
  profileOnly?: boolean;
  requiredCardOnboarding?: boolean;
};

const modalityOptions = [
  { id: "sala", label: "Fútbol sala" },
  { id: "futbol7", label: "Fútbol 7" },
  { id: "futbol11", label: "Fútbol 11" },
] as const;

const initialShieldOptions = [
  { key: "team.shield.shape.classic_iq", label: "Clásico" },
  { key: "team.shield.shape.round", label: "Redondo" },
  { key: "team.shield.shape.hex_iq", label: "Hex IQ" },
] as const;

function initialShieldLabel(key: string) {
  return initialShieldOptions.find((shield) => shield.key === key)?.label ?? "Clásico";
}

function viewForEntry(entryState: SocialEntryState): FlowView {
  if (entryState === "TEAM_INVITATION_PENDING") return "join";
  if (entryState === "PROFILE_READY_NO_TEAM") return "start";
  return "profile";
}

function defaultStep(entryState: SocialEntryState) {
  return entryState === "PROFILE_READY_NO_TEAM" || entryState === "TEAM_INVITATION_PENDING" ? 3 : 1;
}

function requiredProfileStep(profile: SocialProfileMinimum | null) {
  if (socialFirstTimeProfileReady(profile)) return 3;
  return socialProfileMinimumReady(profile) ? 2 : 1;
}

export function SocialOnboarding({
  canonicalProfile,
  createDraftStorageKey = "",
  dismissed,
  draft,
  entryState,
  forcedView = null,
  googleMapsApiKey = "",
  invitation,
  onDismiss,
  onCreateTeam,
  onDraftChange,
  onForcedViewHandled,
  onJoin,
  onLookupTeamCode,
  onRequestTeamJoin,
  onCloseInvitation,
  onOpen,
  onProfileSaved,
  onSaveProfile,
  profileOnly = false,
  requiredCardOnboarding = false,
}: SocialOnboardingProps) {
  const [open, setOpen] = useState(!dismissed);
  const [view, setView] = useState<FlowView>(() => viewForEntry(entryState));
  const [step, setStep] = useState(() => requiredCardOnboarding ? requiredProfileStep(canonicalProfile) : defaultStep(entryState));
  const [joinInput, setJoinInput] = useState("");
  const [joinCandidate, setJoinCandidate] = useState<PendingSocialInvitation | null>(invitation ?? null);
  const [joinMessage, setJoinMessage] = useState("");
  const [joining, setJoining] = useState(false);
  const [requestingTeamJoin, setRequestingTeamJoin] = useState(false);
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileMessage, setProfileMessage] = useState("");
  const [creating, setCreating] = useState(false);
  const [createMessage, setCreateMessage] = useState("");
  const [createStep, setCreateStep] = useState(1);
  const [createDraft, setCreateDraft] = useState<SocialTeamCreateDraft>({ ...DEFAULT_SOCIAL_TEAM_CREATE_DRAFT });
  const [createProgressLoadedKey, setCreateProgressLoadedKey] = useState("");
  const [teamCodePreview, setTeamCodePreview] = useState<TeamCodePreview | null>(null);
  const [online, setOnline] = useState(() => typeof navigator === "undefined" ? true : navigator.onLine);
  const [avatarPreview, setAvatarPreview] = useState("");
  const [confirmedCity, setConfirmedCity] = useState(() => canonicalProfile?.generalArea?.trim() ?? "");
  const [placeMessage, setPlaceMessage] = useState("");
  const [placeStatus, setPlaceStatus] = useState<"error" | "idle" | "loading" | "missing-key" | "ready">("idle");
  const cityInputRef = useRef<HTMLInputElement>(null);
  const [confirmedTeamCity, setConfirmedTeamCity] = useState("");
  const [teamPlaceMessage, setTeamPlaceMessage] = useState("");
  const [teamPlaceStatus, setTeamPlaceStatus] = useState<"error" | "idle" | "loading" | "missing-key" | "ready">("idle");
  const teamCityInputRef = useRef<HTMLInputElement>(null);

  const profileReady = socialProfileMinimumReady(canonicalProfile);
  const firstTimeProfileReady = socialFirstTimeProfileReady(canonicalProfile);
  const writeAvailability = socialWriteAvailability(online);
  const visibleDraft = useMemo(() => normalizeSocialOnboardingDraft(draft), [draft]);
  const draftRef = useRef(visibleDraft);
  const activeView = profileOnly
    ? "profile"
    : requiredCardOnboarding
    ? "profile"
    : invitation ? (profileReady ? "join" : "profile") : forcedView ?? view;
  const activeJoinCandidate = invitation ?? joinCandidate;
  const alreadyInInvitedTeam = activeJoinCandidate?.snapshot?.alreadyMember === true;
  const visibleOpen = Boolean(profileOnly || requiredCardOnboarding || forcedView || open);
  const cityConfirmed = Boolean(confirmedCity && confirmedCity === visibleDraft.zone.trim());
  const teamCityConfirmed = Boolean(confirmedTeamCity && confirmedTeamCity === createDraft.zone.trim());

  useEffect(() => {
    if (!createDraftStorageKey || createProgressLoadedKey === createDraftStorageKey) return;
    let active = true;
    queueMicrotask(() => {
      if (!active) return;
      try {
        const progress = normalizeSocialTeamCreateProgress(JSON.parse(localStorage.getItem(createDraftStorageKey) ?? "null"));
        setCreateDraft(progress.draft);
        setCreateStep(progress.step);
        setConfirmedTeamCity(progress.confirmedCity);
      } catch {
        setCreateDraft({ ...DEFAULT_SOCIAL_TEAM_CREATE_DRAFT });
        setCreateStep(1);
        setConfirmedTeamCity("");
      }
      setCreateProgressLoadedKey(createDraftStorageKey);
    });
    return () => { active = false; };
  }, [createDraftStorageKey, createProgressLoadedKey]);

  useEffect(() => {
    if (!createDraftStorageKey || createProgressLoadedKey !== createDraftStorageKey || activeView !== "create") return;
    try {
      localStorage.setItem(createDraftStorageKey, JSON.stringify({
        confirmedCity: teamCityConfirmed ? confirmedTeamCity : "",
        draft: createDraft,
        step: createStep,
      }));
    } catch {
      // This is a resumable local draft. Team creation remains server-authoritative.
    }
  }, [activeView, confirmedTeamCity, createDraft, createDraftStorageKey, createProgressLoadedKey, createStep, teamCityConfirmed]);

  useEffect(() => {
    if (!visibleOpen || activeView !== "create") return;
    document.body.classList.add("team-onboarding-active");
    return () => document.body.classList.remove("team-onboarding-active");
  }, [activeView, visibleOpen]);

  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  useEffect(() => {
    draftRef.current = visibleDraft;
  }, [visibleDraft]);

  useEffect(() => () => {
    if (avatarPreview.startsWith("blob:")) URL.revokeObjectURL(avatarPreview);
  }, [avatarPreview]);

  useEffect(() => {
    const canonicalCity = canonicalProfile?.generalArea?.trim();
    if (!canonicalCity) return;
    let active = true;
    queueMicrotask(() => {
      if (active) setConfirmedCity(canonicalCity);
    });
    return () => { active = false; };
  }, [canonicalProfile?.generalArea]);

  useEffect(() => {
    if (!requiredCardOnboarding) return;
    const nextStep = firstTimeProfileReady ? 3 : profileReady && validBirthDate(canonicalProfile?.birthDate) ? 2 : 1;
    let active = true;
    queueMicrotask(() => {
      if (active) setStep((current) => !validBirthDate(canonicalProfile?.birthDate) ? 1 : current === 3 && nextStep < 3 ? nextStep : Math.max(current, nextStep));
    });
    return () => { active = false; };
  }, [firstTimeProfileReady, profileReady, requiredCardOnboarding, canonicalProfile?.birthDate]);

  useEffect(() => {
    if (activeView !== "profile" || step !== 2) return;
    if (!googleMapsApiKey) {
      let active = true;
      queueMicrotask(() => {
        if (!active) return;
        setPlaceStatus("missing-key");
        setPlaceMessage("No podemos abrir el buscador de poblaciones ahora mismo.");
      });
      return () => { active = false; };
    }

    const input = cityInputRef.current;
    if (!input) return;
    let cleanup: (() => void) | undefined;
    let disposed = false;
    queueMicrotask(() => {
      if (!disposed) setPlaceStatus("loading");
    });

    attachVenueAutocomplete({
      apiKey: googleMapsApiKey,
      input,
      onError: (message) => {
        if (disposed) return;
        setConfirmedCity("");
        setPlaceStatus("error");
        setPlaceMessage(message);
      },
      onPlace: (place: VenuePlace) => {
        if (disposed) return;
        const city = (place.city || place.name).trim();
        if (!city) {
          setConfirmedCity("");
          setPlaceStatus("error");
          setPlaceMessage("Elige una ciudad o población de las sugerencias.");
          return;
        }
        setConfirmedCity(city);
        setPlaceStatus("ready");
        setPlaceMessage(`Población confirmada: ${city}`);
        onDraftChange(normalizeSocialOnboardingDraft({ ...draftRef.current, zone: city }));
      },
      onSelectionInvalidated: () => {
        if (disposed) return;
        setConfirmedCity("");
        setPlaceStatus("ready");
        setPlaceMessage("Elige una ciudad o población de las sugerencias.");
      },
      types: ["(cities)"],
    })
      .then((nextCleanup) => {
        if (disposed) {
          nextCleanup();
          return;
        }
        cleanup = nextCleanup;
        setPlaceStatus("ready");
      })
      .catch((error: unknown) => {
        if (disposed) return;
        setPlaceStatus("error");
        setPlaceMessage(error instanceof Error ? error.message : "No se pudo cargar Google Places.");
      });

    return () => {
      disposed = true;
      cleanup?.();
    };
  }, [activeView, googleMapsApiKey, onDraftChange, step]);

  useEffect(() => {
    if (activeView !== "create" || createStep !== 2) return;
    if (!googleMapsApiKey) {
      let active = true;
      queueMicrotask(() => {
        if (!active) return;
        setTeamPlaceStatus("missing-key");
        setTeamPlaceMessage("No podemos abrir el buscador de poblaciones ahora mismo.");
      });
      return () => { active = false; };
    }

    const input = teamCityInputRef.current;
    if (!input) return;
    let cleanup: (() => void) | undefined;
    let disposed = false;
    queueMicrotask(() => {
      if (!disposed) setTeamPlaceStatus("loading");
    });

    attachVenueAutocomplete({
      apiKey: googleMapsApiKey,
      input,
      onError: (message) => {
        if (disposed) return;
        setConfirmedTeamCity("");
        setTeamPlaceStatus("error");
        setTeamPlaceMessage(message);
      },
      onPlace: (place: VenuePlace) => {
        if (disposed) return;
        const city = (place.city || place.name).trim();
        if (!city) {
          setConfirmedTeamCity("");
          setTeamPlaceStatus("error");
          setTeamPlaceMessage("Elige una ciudad o población de las sugerencias.");
          return;
        }
        setCreateDraft((current) => ({ ...current, zone: city }));
        setConfirmedTeamCity(city);
        setTeamPlaceStatus("ready");
        setTeamPlaceMessage(`Población confirmada: ${city}`);
      },
      onSelectionInvalidated: () => {
        if (disposed) return;
        setConfirmedTeamCity("");
        setTeamPlaceStatus("ready");
        setTeamPlaceMessage("Elige una ciudad o población de las sugerencias.");
      },
      types: ["(cities)"],
    })
      .then((nextCleanup) => {
        if (disposed) {
          nextCleanup();
          return;
        }
        cleanup = nextCleanup;
        setTeamPlaceStatus("ready");
      })
      .catch((error: unknown) => {
        if (disposed) return;
        setTeamPlaceStatus("error");
        setTeamPlaceMessage(error instanceof Error ? error.message : "No se pudo cargar Google Places.");
      });

    return () => {
      disposed = true;
      cleanup?.();
    };
  }, [activeView, createStep, googleMapsApiKey]);

  if ((entryState === "TEAM_MEMBER" || entryState === "MULTI_TEAM_MEMBER") && !forcedView && !visibleOpen) return null;

  function updateDraft(patch: Partial<SocialOnboardingDraft>) {
    onDraftChange(normalizeSocialOnboardingDraft({ ...draftRef.current, ...patch }));
  }

  function closeFlow() {
    if (invitation) {
      onCloseInvitation(invitation);
      return;
    }
    onForcedViewHandled?.(null);
    setOpen(false);
    onDismiss();
  }

  function selectView(nextView: FlowView) {
    onForcedViewHandled?.(nextView);
    setView(nextView);
    setOpen(true);
  }

  function resumeFlow(nextView: FlowView = viewForEntry(entryState)) {
    onForcedViewHandled?.(nextView);
    setView(nextView);
    setStep(defaultStep(entryState));
    setOpen(true);
    onOpen();
  }

  async function inspectJoinInput() {
    const parsed = parseTeamInvitationInput(joinInput);
    if (parsed.kind === "invalid") {
      setJoinMessage(parsed.reason === "EMPTY" ? "Introduce un código o enlace de invitación." : "EQUIPO NO ENCONTRADO");
      return;
    }
    if (parsed.kind === "team-code") {
      setJoinCandidate(null);
      setJoinMessage("Buscando el equipo...");
      const result = await onLookupTeamCode(parsed.code);
      setTeamCodePreview(result.team ?? null);
      setJoinMessage(result.ok
        ? "Equipo encontrado. Envía una solicitud para que un admin la revise."
        : result.error ?? "EQUIPO NO ENCONTRADO");
      return;
    }
    setTeamCodePreview(null);
    setJoinCandidate({ kind: "player", token: parsed.token });
    setJoinMessage("");
  }

  async function saveProfile() {
    if (!validBirthDate(visibleDraft.birthDate)) { setStep(1); setProfileMessage("Indica una fecha de nacimiento válida."); return; }
    if (profileSaving || !writeAvailability.allowed || !visibleDraft.displayName.trim() || !cityConfirmed) return;
    setProfileSaving(true);
    setProfileMessage("Guardando con el servidor...");
    const result = await onSaveProfile(visibleDraft);
    setProfileSaving(false);
    if (!result.ok) {
      setProfileMessage(result.error ?? "No se pudo guardar el perfil.");
      return;
    }
    setProfileMessage("Perfil confirmado.");
    if (profileOnly) {
      onProfileSaved?.();
      return;
    }
    setStep(3);
    if (requiredCardOnboarding) {
      setView("profile");
      return;
    }
    selectView("start");
  }

  async function createTeam() {
    if (creating || !writeAvailability.allowed || createDraft.name.trim().length < SOCIAL_TEAM_NAME_MIN_LENGTH || !teamCityConfirmed) return;
    setCreating(true);
    setCreateMessage("Creando equipo y owner en una sola transacción...");
    const result = await onCreateTeam(createDraft);
    setCreating(false);
    if (!result.ok) {
      setCreateMessage(result.error ?? "El servidor no confirmó el equipo.");
      return;
    }
    if (createDraftStorageKey) {
      try {
        localStorage.removeItem(createDraftStorageKey);
      } catch {
        // A stale local draft is harmless; the confirmed server response wins.
      }
    }
    setCreateMessage("Equipo confirmado. Abriendo su portada...");
  }

  async function confirmJoin() {
    if (!activeJoinCandidate || joining || !writeAvailability.allowed) return;
    setJoining(true);
    setJoinMessage("Comprobando la invitación con el servidor...");
    const result = await onJoin(activeJoinCandidate, visibleDraft.displayName);
    setJoining(false);
    if (!result.ok) {
      setJoinMessage(result.error ?? "NO PUEDES UNIRTE AHORA");
      return;
    }
    setJoinMessage("Equipo confirmado. Cargando el estado oficial...");
    setOpen(false);
  }

  async function requestTeamJoin() {
    if (!teamCodePreview || requestingTeamJoin || !writeAvailability.allowed) return;
    setRequestingTeamJoin(true);
    setJoinMessage("Enviando la solicitud al equipo...");
    const result = await onRequestTeamJoin(teamCodePreview.groupId, teamCodePreview.teamRevision);
    setRequestingTeamJoin(false);
    if (!result.ok) {
      setJoinMessage(result.error ?? "NO SE PUDO ENVIAR LA SOLICITUD");
      return;
    }
    setJoinMessage("Solicitud enviada. Un admin del equipo debe aceptarla.");
    setTeamCodePreview(null);
  }

  if (!visibleOpen) {
    return (
      <section className={styles.resumeCard} aria-label="Continuar configuración inicial">
        <div>
          <span>{invitation ? "Invitación pendiente" : profileReady ? "Tu siguiente paso" : "Perfil pendiente"}</span>
          <strong>{invitation ? "Tienes una invitación sin responder" : "Termina de preparar tu espacio de jugador"}</strong>
        </div>
        <button type="button" onClick={() => resumeFlow(invitation ? "join" : undefined)}>Continuar</button>
      </section>
    );
  }

  return (
    <section className={`${styles.flow} ${activeView === "create" ? polishStyles.immersiveFlow : ""}`.trim()} data-onboarding-view={activeView} data-social-entry-state={entryState} data-social-onboarding="v3f" aria-labelledby="social-onboarding-title">
      <header className={styles.header}>
        <div>
          <span>{profileOnly ? "Mi perfil" : "Primeros pasos"}</span>
          <h2 id="social-onboarding-title">
            {profileOnly ? "Editar perfil" : requiredCardOnboarding ? "Crea tu ficha de jugador" : activeView === "join" ? "Unirme a un equipo" : activeView === "create" ? "Crear mi equipo" : activeView === "start" ? "¿Cómo quieres empezar?" : invitation ? "Primero, prepara tu perfil" : "Prepara tu perfil"}
          </h2>
        </div>
        <div className={styles.headerActions}>
          {!profileReady ? <small>BORRADOR LOCAL</small> : <small>PERFIL CONFIRMADO</small>}
          {profileOnly ? <button type="button" onClick={closeFlow}>Volver</button> : !requiredCardOnboarding && !alreadyInInvitedTeam ? <button type="button" onClick={closeFlow}>Ahora no</button> : null}
        </div>
      </header>

      {activeView === "profile" ? (
        <div className={styles.profileFlow}>
          <nav className={styles.steps} aria-label="Pasos del perfil">
            {(profileOnly ? [1, 2] : [1, 2, 3]).map((item) => (
              <button
                aria-current={step === item ? "step" : undefined}
                disabled={item === 2 ? (!visibleDraft.displayName.trim() || !validBirthDate(visibleDraft.birthDate)) : item === 3 ? requiredCardOnboarding && !firstTimeProfileReady : false}
                key={item}
                type="button"
                onClick={() => setStep(item)}
              >
                {item}
              </button>
            ))}
          </nav>
          {step === 1 ? (
            <div className={styles.formBody}>
              <div className={styles.stepHeading}><span>Paso 1</span><h3>Tu perfil</h3><p>Solo lo necesario para reconocerte cuando juegues.</p></div>
              <div className={styles.profileGrid}>
                <label>Fecha de nacimiento<input type="date" autoComplete="bday" max={madridToday()} value={visibleDraft.birthDate ?? ""} onChange={(event) => updateDraft({ birthDate: event.target.value })} /><small>Es privada. Mercado y retos están disponibles a partir de los 18 años.</small></label>
                <label>Nombre visible<input autoComplete="nickname" maxLength={80} value={visibleDraft.displayName} onChange={(event) => updateDraft({ displayName: event.target.value })} /></label>
                <label>Posición principal<select value={visibleDraft.position} onChange={(event) => updateDraft({ position: event.target.value })}>{SOCIAL_POSITION_OPTIONS.map((position) => <option key={position}>{position}</option>)}</select></label>
                <fieldset><legend>Modalidad preferida</legend><div className={styles.segmented}>{modalityOptions.map((option) => <button aria-pressed={visibleDraft.modality === option.id} key={option.id} type="button" onClick={() => updateDraft({ modality: option.id })}>{option.label}</button>)}</div></fieldset>
                <label className={styles.photoField}>Foto <span>{avatarPreview ? <Image alt="Vista previa local" fill sizes="90px" src={avatarPreview} unoptimized /> : <b aria-hidden="true">+</b>}<input accept="image/*" type="file" onChange={(event) => {
                  const file = event.currentTarget.files?.[0];
                  if (!file) return;
                  if (avatarPreview.startsWith("blob:")) URL.revokeObjectURL(avatarPreview);
                  setAvatarPreview(URL.createObjectURL(file));
                }} /></span><small>Opcional. Esta vista previa no se publica hasta guardar tu perfil canónico.</small></label>
              </div>
              {validBirthDate(visibleDraft.birthDate) && !isAdultBirthDate(visibleDraft.birthDate) ? <p className={styles.ageNotice}>Puedes jugar con tu equipo y crear uno para partidos internos. Un administrador adulto podrá organizar encuentros por mercado y retos.</p> : null}
              <div className={styles.actions}><button className={styles.primary} type="button" onClick={() => setStep(2)} disabled={!visibleDraft.displayName.trim() || !validBirthDate(visibleDraft.birthDate)}>Continuar</button></div>
            </div>
          ) : null}
          {step === 2 ? (
            <div className={styles.formBody}>
              <div className={styles.stepHeading}><span>Paso 2</span><h3>Dónde y cuándo prefieres jugar</h3><p>Solo pedimos tu ciudad o población, nunca una dirección exacta.</p></div>
              <label>
                Ciudad o población
                <input
                  autoComplete="off"
                  maxLength={120}
                  placeholder="Ej. Barcelona"
                  ref={cityInputRef}
                  value={visibleDraft.zone}
                  onChange={(event) => {
                    setConfirmedCity("");
                    setPlaceMessage("Elige una ciudad o población de las sugerencias.");
                    updateDraft({ zone: event.target.value });
                  }}
                />
              </label>
              {placeStatus === "loading" ? <p className={styles.placeStatus}>Preparando el buscador de poblaciones...</p> : null}
              {placeMessage ? <p className={placeStatus === "error" || placeStatus === "missing-key" ? styles.warning : styles.placeStatus} role="status">{placeMessage}</p> : null}
              <fieldset><legend>Días preferidos</legend><div className={styles.dayPicker}>{SOCIAL_DAY_OPTIONS.map((day) => <button aria-pressed={visibleDraft.days.includes(day)} key={day} type="button" onClick={() => updateDraft({ days: visibleDraft.days.includes(day) ? visibleDraft.days.filter((item) => item !== day) : [...visibleDraft.days, day] })}>{day}</button>)}</div></fieldset>
              <label>Franja aproximada<select value={visibleDraft.approximateTime} onChange={(event) => updateDraft({ approximateTime: event.target.value })}><option>08:00-12:00</option><option>12:00-16:00</option><option>16:00-20:00</option><option>20:00-22:00</option><option>22:00-00:00</option></select></label>
              {!writeAvailability.allowed ? <p className={styles.warning}>{writeAvailability.label}</p> : null}
              {profileMessage ? <p className={styles.message} role="status">{profileMessage}</p> : null}
              <div className={styles.actions}><button type="button" onClick={() => setStep(1)}>Volver</button><button className={styles.primary} type="button" disabled={profileSaving || !writeAvailability.allowed || !cityConfirmed || !validBirthDate(visibleDraft.birthDate)} onClick={() => void saveProfile()}>{profileSaving ? "Guardando..." : profileOnly ? "Guardar cambios" : profileReady ? "Actualizar perfil" : "Guardar perfil"}</button></div>
            </div>
          ) : null}
          {step === 3 ? requiredCardOnboarding ? <RequiredAssessmentStep invitation={invitation} onBack={() => setStep(2)} /> : <StartChoices onCreate={() => selectView("create")} onJoin={() => selectView("join")} /> : null}
        </div>
      ) : null}

      {activeView === "start" ? <StartChoices onCreate={() => selectView("create")} onJoin={() => selectView("join")} /> : null}

      {activeView === "join" ? (
        <div className={styles.formBody}>
          {invitation && !alreadyInInvitedTeam ? (
            <article className={styles.invitationCard}>
              <span>Te han invitado</span>
              <strong>Invitación segura de equipo</strong>
              <p>Entrarás como {invitation.kind === "admin" ? "administrador" : "jugador"}. El nombre y la plantilla se mostrarán después de confirmar con el servidor.</p>
              <small>La invitación no se acepta automáticamente.</small>
            </article>
          ) : null}
          {alreadyInInvitedTeam && activeJoinCandidate ? (
            <article className={styles.alreadyMemberCard} role="status">
              <span>Equipo confirmado</span>
              <strong>Ya estás en este equipo</strong>
              <p>{activeJoinCandidate.snapshot?.teamName || "Tu membresía ya estaba activa."}</p>
              <button className={styles.primary} type="button" onClick={() => onCloseInvitation(activeJoinCandidate)}>Cerrar</button>
            </article>
          ) : null}
          {!invitation ? <><label>Código o enlace de invitación<input autoCapitalize="off" autoCorrect="off" value={joinInput} onChange={(event) => { setJoinInput(event.target.value); setJoinMessage(""); setTeamCodePreview(null); }} /></label><button className={styles.secondary} type="button" onClick={() => void inspectJoinInput()}>Buscar equipo</button></> : null}
          {teamCodePreview ? <article className={styles.invitationCard}><span>Equipo encontrado</span><strong>{teamCodePreview.name}</strong><p>{modalityLabel(teamCodePreview.modality)} · {teamCodePreview.generalArea || "Zona no indicada"} · {teamCodePreview.memberCount} miembros</p><small>El código no concede acceso. Puedes enviar una solicitud a sus admins.</small><button className={styles.primary} type="button" disabled={requestingTeamJoin || !writeAvailability.allowed} onClick={() => void requestTeamJoin()}>{requestingTeamJoin ? "Enviando..." : "Solicitar entrada"}</button></article> : null}
          {activeJoinCandidate && !alreadyInInvitedTeam ? (
            <div className={styles.joinConfirmation}>
              <span>Confirmar</span><strong>{activeJoinCandidate.snapshot?.teamName || `Acceso como ${activeJoinCandidate.kind === "admin" ? "administrador" : "jugador"}`}</strong><p>{activeJoinCandidate.snapshot ? `${modalityLabel(activeJoinCandidate.snapshot.modality)} · ${activeJoinCandidate.snapshot.generalArea}` : "La membresía solo aparecerá cuando el servidor la confirme y recarguemos el equipo."}</p>
              <button className={styles.primary} type="button" disabled={joining || !writeAvailability.allowed} onClick={() => void confirmJoin()}>{joining ? "Confirmando..." : "Unirme"}</button>
            </div>
          ) : null}
          {!writeAvailability.allowed ? <p className={styles.warning}>{writeAvailability.label}</p> : null}
          {joinMessage ? <p className={styles.message} role="status">{joinMessage}</p> : null}
          {!alreadyInInvitedTeam ? <div className={styles.actions}><button type="button" onClick={() => invitation ? closeFlow() : selectView("start")}>Volver</button>{!invitation ? <button type="button" onClick={closeFlow}>Ahora no</button> : null}</div> : null}
        </div>
      ) : null}

      {activeView === "create" ? (
        <div className={styles.formBody}>
          <nav className={styles.steps} aria-label="Pasos para crear equipo">{[1, 2, 3].map((item) => <button aria-current={createStep === item ? "step" : undefined} key={item} type="button" onClick={() => setCreateStep(item)}>{item}</button>)}</nav>
          {createStep === 1 ? <><div className={styles.stepHeading}><span>Paso 1</span><h3>Identidad</h3></div><label>Nombre del equipo<input maxLength={SOCIAL_TEAM_NAME_MAX_LENGTH} value={createDraft.name} onChange={(event) => setCreateDraft((current) => ({ ...current, name: event.target.value }))} /><small className={styles.characterCount}>{createDraft.name.length}/{SOCIAL_TEAM_NAME_MAX_LENGTH}</small></label><fieldset><legend>Escudo inicial</legend><div className={polishStyles.shields}>{initialShieldOptions.map((shield) => <button aria-pressed={createDraft.shieldKey === shield.key} key={shield.key} type="button" onClick={() => setCreateDraft((current) => ({ ...current, shieldKey: shield.key }))}><TeamShieldView className={polishStyles.shieldPreview} config={{ ...TEAM_SHIELD_DEFAULT_CONFIG, shapeKey: shield.key }} label={`Escudo ${shield.label}`} size={64} /><strong>{shield.label}</strong></button>)}</div></fieldset></> : null}
          {createStep === 2 ? <><div className={styles.stepHeading}><span>Paso 2</span><h3>Fútbol</h3></div><label>Modalidad principal<select value={createDraft.modality} onChange={(event) => setCreateDraft((current) => ({ ...current, modality: event.target.value as SocialTeamCreateDraft["modality"] }))}>{modalityOptions.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}</select></label><label>Ciudad o población<input autoComplete="off" maxLength={120} placeholder="Ej. Barcelona" ref={teamCityInputRef} value={createDraft.zone} onChange={(event) => { setConfirmedTeamCity(""); setTeamPlaceMessage("Elige una ciudad o población de las sugerencias."); setCreateDraft((current) => ({ ...current, zone: event.target.value })); }} /></label>{teamPlaceStatus === "loading" ? <p className={styles.placeStatus}>Preparando el buscador de poblaciones...</p> : null}{teamPlaceMessage ? <p className={teamPlaceStatus === "error" || teamPlaceStatus === "missing-key" ? styles.warning : styles.placeStatus} role="status">{teamPlaceMessage}</p> : null}</> : null}
          {createStep === 3 ? <><div className={styles.stepHeading}><span>Paso 3</span><h3>Revisar</h3></div><dl className={styles.review}><div><dt>Equipo</dt><dd>{createDraft.name || "Sin nombre"}</dd></div><div><dt>Escudo</dt><dd>{initialShieldLabel(createDraft.shieldKey)}</dd></div><div><dt>Modalidad</dt><dd>{modalityOptions.find((option) => option.id === createDraft.modality)?.label}</dd></div><div><dt>Ciudad</dt><dd>{createDraft.zone || "Pendiente"}</dd></div></dl><p className={styles.message}>{createMessage || TEAM_CREATION_AUTHORITY.message}</p></> : null}
          <div className={styles.actions}><button type="button" onClick={() => createStep === 1 ? selectView("start") : setCreateStep((current) => current - 1)}>Volver</button>{createStep < 3 ? <button className={styles.primary} type="button" disabled={createStep === 1 ? createDraft.name.trim().length < SOCIAL_TEAM_NAME_MIN_LENGTH : !teamCityConfirmed} onClick={() => setCreateStep((current) => current + 1)}>Continuar</button> : <button className={styles.primary} type="button" disabled={creating || !writeAvailability.allowed || !teamCityConfirmed} onClick={() => void createTeam()}>{creating ? "Creando..." : "Crear equipo"}</button>}</div>
        </div>
      ) : null}
    </section>
  );
}

function StartChoices({ onCreate, onJoin }: { onCreate: () => void; onJoin: () => void }) {
  return (
    <div className={styles.startChoices}>
      <div className={styles.stepHeading}><span>Paso 3</span><h3>¿Cómo quieres empezar?</h3><p>Elige una sola dirección; podrás cambiarla después.</p></div>
      <div className={styles.choiceGrid}>
        <button type="button" onClick={onJoin}><b aria-hidden="true">+</b><strong>Unirme a un equipo</strong><small>Usa el enlace de invitación de un admin.</small></button>
        <button type="button" onClick={onCreate}><b aria-hidden="true">◇</b><strong>Crear mi equipo</strong><small>Prepara identidad, modalidad y zona.</small></button>
        <Link href="/mercado?tab=partidos"><b aria-hidden="true">⌕</b><strong>Buscar una pachanga</strong><small>Explora partidos públicos sin crear equipo.</small></Link>
      </div>
    </div>
  );
}

function RequiredAssessmentStep({ invitation, onBack }: { invitation?: PendingSocialInvitation | null; onBack: () => void }) {
  const invitationPath = invitation
    ? invitation.kind === "admin"
      ? `/invitacion/admin/${encodeURIComponent(invitation.token)}`
      : `/invitacion/grupo/${encodeURIComponent(invitation.token)}`
    : "";
  const assessmentHref = invitationPath
    ? `/perfil/test-inicial?onboarding=1&next=${encodeURIComponent(invitationPath)}`
    : "/perfil/test-inicial?onboarding=1";
  return (
    <div className={styles.requiredAssessment}>
      <div className={styles.stepHeading}>
        <span>Paso 3</span>
        <h3>Crea tu primera carta</h3>
        <p>El test inicial es obligatorio y solo puede completarse una vez. Responde con sinceridad: el servidor usará tus respuestas para crear tu ficha universal.</p>
      </div>
      <div className={styles.requiredAssessmentActions}>
        <button type="button" onClick={onBack}>Volver</button>
        <Link className={styles.primary} href={assessmentHref}>Hacer test inicial</Link>
      </div>
    </div>
  );
}

export function emptySocialOnboardingDraft() {
  return { ...DEFAULT_SOCIAL_ONBOARDING_DRAFT };
}

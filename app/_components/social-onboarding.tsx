"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useMemo, useState } from "react";
import {
  DEFAULT_SOCIAL_ONBOARDING_DRAFT,
  SOCIAL_DAY_OPTIONS,
  SOCIAL_POSITION_OPTIONS,
  TEAM_CREATION_AUTHORITY,
  normalizeSocialOnboardingDraft,
  parseTeamInvitationInput,
  socialProfileMinimumReady,
  socialWriteAvailability,
  type SocialEntryState,
  type SocialOnboardingFlow,
  type SocialOnboardingDraft,
} from "../social-onboarding-contract";
import { modalityLabel, type SocialTeamCreateDraft, type SocialTeamInvitation } from "../social-team-core-contract";
import styles from "./social-onboarding.module.css";

type FlowView = SocialOnboardingFlow;

export type PendingSocialInvitation = {
  kind: "admin" | "player";
  snapshot?: SocialTeamInvitation | null;
  token: string;
};

type TeamCodePreview = {
  generalArea: string;
  memberCount: number;
  modality: string;
  name: string;
  teamCode: string;
};

type SocialOnboardingProps = {
  canonicalProfile: {
    displayName?: string | null;
    modalities?: string[] | null;
    position?: string | null;
  } | null;
  dismissed: boolean;
  draft: SocialOnboardingDraft;
  entryState: SocialEntryState;
  forcedView?: FlowView | null;
  invitation?: PendingSocialInvitation | null;
  onDismiss: () => void;
  onCreateTeam: (draft: SocialTeamCreateDraft) => Promise<{ error?: string; ok: boolean }>;
  onDraftChange: (draft: SocialOnboardingDraft) => void;
  onForcedViewHandled?: () => void;
  onJoin: (invitation: PendingSocialInvitation, displayName: string) => Promise<{ error?: string; ok: boolean }>;
  onLookupTeamCode: (code: string) => Promise<{ error?: string; ok: boolean; team?: TeamCodePreview }>;
  onOpen: () => void;
  onSaveProfile: (draft: SocialOnboardingDraft) => Promise<{ error?: string; ok: boolean }>;
};

const modalityOptions = [
  { id: "sala", label: "Fútbol sala" },
  { id: "futbol7", label: "Fútbol 7" },
  { id: "futbol11", label: "Fútbol 11" },
] as const;

function viewForEntry(entryState: SocialEntryState): FlowView {
  if (entryState === "TEAM_INVITATION_PENDING") return "join";
  if (entryState === "PROFILE_READY_NO_TEAM") return "start";
  return "profile";
}

function defaultStep(entryState: SocialEntryState) {
  return entryState === "PROFILE_READY_NO_TEAM" || entryState === "TEAM_INVITATION_PENDING" ? 3 : 1;
}

export function SocialOnboarding({
  canonicalProfile,
  dismissed,
  draft,
  entryState,
  forcedView = null,
  invitation,
  onDismiss,
  onCreateTeam,
  onDraftChange,
  onForcedViewHandled,
  onJoin,
  onLookupTeamCode,
  onOpen,
  onSaveProfile,
}: SocialOnboardingProps) {
  const [open, setOpen] = useState(!dismissed);
  const [view, setView] = useState<FlowView>(() => viewForEntry(entryState));
  const [step, setStep] = useState(() => defaultStep(entryState));
  const [joinInput, setJoinInput] = useState("");
  const [joinCandidate, setJoinCandidate] = useState<PendingSocialInvitation | null>(invitation ?? null);
  const [joinMessage, setJoinMessage] = useState("");
  const [joining, setJoining] = useState(false);
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileMessage, setProfileMessage] = useState("");
  const [creating, setCreating] = useState(false);
  const [createMessage, setCreateMessage] = useState("");
  const [createStep, setCreateStep] = useState(1);
  const [createDraft, setCreateDraft] = useState<SocialTeamCreateDraft>({
    modality: "futbol7",
    name: "",
    shieldKey: "team.shield.shape.classic_iq",
    targetPlayerCount: 14,
    zone: "",
  });
  const [teamCodePreview, setTeamCodePreview] = useState<TeamCodePreview | null>(null);
  const [online, setOnline] = useState(() => typeof navigator === "undefined" ? true : navigator.onLine);
  const [avatarPreview, setAvatarPreview] = useState("");

  const profileReady = socialProfileMinimumReady(canonicalProfile);
  const writeAvailability = socialWriteAvailability(online);
  const visibleDraft = useMemo(() => normalizeSocialOnboardingDraft(draft), [draft]);
  const activeView = invitation ? (profileReady ? "join" : "profile") : forcedView ?? view;
  const activeJoinCandidate = invitation ?? joinCandidate;
  const visibleOpen = Boolean(forcedView || open);

  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  useEffect(() => () => {
    if (avatarPreview.startsWith("blob:")) URL.revokeObjectURL(avatarPreview);
  }, [avatarPreview]);

  if ((entryState === "TEAM_MEMBER" || entryState === "MULTI_TEAM_MEMBER") && !forcedView && !visibleOpen) return null;

  function updateDraft(patch: Partial<SocialOnboardingDraft>) {
    onDraftChange(normalizeSocialOnboardingDraft({ ...visibleDraft, ...patch }));
  }

  function closeFlow() {
    onForcedViewHandled?.();
    setOpen(false);
    onDismiss();
  }

  function selectView(nextView: FlowView) {
    onForcedViewHandled?.();
    setView(nextView);
    setOpen(true);
  }

  function resumeFlow(nextView: FlowView = viewForEntry(entryState)) {
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
        ? "El código identifica este equipo, pero no concede acceso. Pide a un admin su enlace de invitación."
        : result.error ?? "EQUIPO NO ENCONTRADO");
      return;
    }
    setTeamCodePreview(null);
    setJoinCandidate({ kind: "player", token: parsed.token });
    setJoinMessage("");
  }

  async function saveProfile() {
    if (profileSaving || !writeAvailability.allowed || !visibleDraft.displayName.trim()) return;
    setProfileSaving(true);
    setProfileMessage("Guardando con el servidor...");
    const result = await onSaveProfile(visibleDraft);
    setProfileSaving(false);
    if (!result.ok) {
      setProfileMessage(result.error ?? "No se pudo guardar el perfil.");
      return;
    }
    setProfileMessage("Perfil confirmado.");
    setStep(3);
    selectView("start");
  }

  async function createTeam() {
    if (creating || !writeAvailability.allowed || !createDraft.name.trim() || !createDraft.zone.trim()) return;
    setCreating(true);
    setCreateMessage("Creando equipo y owner en una sola transacción...");
    const result = await onCreateTeam(createDraft);
    setCreating(false);
    if (!result.ok) {
      setCreateMessage(result.error ?? "El servidor no confirmó el equipo.");
      return;
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
    <section className={styles.flow} data-social-entry-state={entryState} data-social-onboarding="v3f" aria-labelledby="social-onboarding-title">
      <header className={styles.header}>
        <div>
          <span>Primeros pasos</span>
          <h2 id="social-onboarding-title">
            {activeView === "join" ? "Unirme a un equipo" : activeView === "create" ? "Crear mi equipo" : activeView === "start" ? "¿Cómo quieres empezar?" : invitation ? "Primero, prepara tu perfil" : "Prepara tu perfil"}
          </h2>
        </div>
        <div className={styles.headerActions}>
          {!profileReady ? <small>BORRADOR LOCAL</small> : <small>PERFIL CONFIRMADO</small>}
          <button type="button" onClick={closeFlow}>Ahora no</button>
        </div>
      </header>

      {activeView === "profile" ? (
        <div className={styles.profileFlow}>
          <nav className={styles.steps} aria-label="Pasos del perfil">
            {[1, 2, 3].map((item) => <button aria-current={step === item ? "step" : undefined} key={item} type="button" onClick={() => setStep(item)}>{item}</button>)}
          </nav>
          {step === 1 ? (
            <div className={styles.formBody}>
              <div className={styles.stepHeading}><span>Paso 1</span><h3>Tu perfil</h3><p>Solo lo necesario para reconocerte cuando juegues.</p></div>
              <div className={styles.profileGrid}>
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
              <div className={styles.actions}><button className={styles.primary} type="button" onClick={() => setStep(2)} disabled={!visibleDraft.displayName.trim()}>Continuar</button><button type="button" onClick={() => setStep(2)}>Omitir foto</button></div>
            </div>
          ) : null}
          {step === 2 ? (
            <div className={styles.formBody}>
              <div className={styles.stepHeading}><span>Paso 2</span><h3>Dónde y cuándo juegas</h3><p>Una referencia general. No pedimos ubicación exacta.</p></div>
              <label>Ciudad o zona general<input maxLength={120} placeholder="Ej. Gràcia, Barcelona" value={visibleDraft.zone} onChange={(event) => updateDraft({ zone: event.target.value })} /></label>
              <fieldset><legend>Días habituales</legend><div className={styles.dayPicker}>{SOCIAL_DAY_OPTIONS.map((day) => <button aria-pressed={visibleDraft.days.includes(day)} key={day} type="button" onClick={() => updateDraft({ days: visibleDraft.days.includes(day) ? visibleDraft.days.filter((item) => item !== day) : [...visibleDraft.days, day] })}>{day}</button>)}</div></fieldset>
              <label>Franja aproximada<select value={visibleDraft.approximateTime} onChange={(event) => updateDraft({ approximateTime: event.target.value })}><option>08:00-12:00</option><option>12:00-16:00</option><option>16:00-20:00</option><option>20:00-22:00</option><option>22:00-00:00</option></select></label>
              {!writeAvailability.allowed ? <p className={styles.warning}>{writeAvailability.label}</p> : null}
              {profileMessage ? <p className={styles.message} role="status">{profileMessage}</p> : null}
              <div className={styles.actions}><button type="button" onClick={() => setStep(1)}>Volver</button><button className={styles.primary} type="button" disabled={profileSaving || !writeAvailability.allowed} onClick={() => void saveProfile()}>{profileSaving ? "Guardando..." : profileReady ? "Actualizar perfil" : "Guardar perfil"}</button></div>
            </div>
          ) : null}
          {step === 3 ? <StartChoices onCreate={() => selectView("create")} onJoin={() => selectView("join")} /> : null}
        </div>
      ) : null}

      {activeView === "start" ? <StartChoices onCreate={() => selectView("create")} onJoin={() => selectView("join")} /> : null}

      {activeView === "join" ? (
        <div className={styles.formBody}>
          {invitation ? (
            <article className={styles.invitationCard}>
              <span>Te han invitado</span>
              <strong>Invitación segura de equipo</strong>
              <p>Entrarás como {invitation.kind === "admin" ? "administrador" : "jugador"}. El nombre y la plantilla se mostrarán después de confirmar con el servidor.</p>
              <small>La invitación no se acepta automáticamente.</small>
            </article>
          ) : null}
          {!invitation ? <><label>Código o enlace de invitación<input autoCapitalize="off" autoCorrect="off" value={joinInput} onChange={(event) => { setJoinInput(event.target.value); setJoinMessage(""); setTeamCodePreview(null); }} /></label><button className={styles.secondary} type="button" onClick={() => void inspectJoinInput()}>Buscar equipo</button></> : null}
          {teamCodePreview ? <article className={styles.invitationCard}><span>Equipo identificado</span><strong>{teamCodePreview.name}</strong><p>{modalityLabel(teamCodePreview.modality)} · {teamCodePreview.generalArea || "Zona no indicada"} · {teamCodePreview.memberCount} miembros</p><small>Necesitas un enlace de invitación para entrar.</small></article> : null}
          {activeJoinCandidate ? (
            <div className={styles.joinConfirmation}>
              <span>Confirmar</span><strong>{activeJoinCandidate.snapshot?.teamName || `Acceso como ${activeJoinCandidate.kind === "admin" ? "administrador" : "jugador"}`}</strong><p>{activeJoinCandidate.snapshot ? `${modalityLabel(activeJoinCandidate.snapshot.modality)} · ${activeJoinCandidate.snapshot.generalArea}` : "La membresía solo aparecerá cuando el servidor la confirme y recarguemos el equipo."}</p>
              <button className={styles.primary} type="button" disabled={joining || !writeAvailability.allowed} onClick={() => void confirmJoin()}>{joining ? "Confirmando..." : "Unirme"}</button>
            </div>
          ) : null}
          {!writeAvailability.allowed ? <p className={styles.warning}>{writeAvailability.label}</p> : null}
          {joinMessage ? <p className={styles.message} role="status">{joinMessage}</p> : null}
          <div className={styles.actions}><button type="button" onClick={() => selectView("start")}>Volver</button><button type="button" onClick={closeFlow}>Ahora no</button></div>
        </div>
      ) : null}

      {activeView === "create" ? (
        <div className={styles.formBody}>
          <nav className={styles.steps} aria-label="Pasos para crear equipo">{[1, 2, 3].map((item) => <button aria-current={createStep === item ? "step" : undefined} key={item} type="button" onClick={() => setCreateStep(item)}>{item}</button>)}</nav>
          {createStep === 1 ? <><div className={styles.stepHeading}><span>Paso 1</span><h3>Identidad</h3></div><label>Nombre del equipo<input maxLength={80} value={createDraft.name} onChange={(event) => setCreateDraft((current) => ({ ...current, name: event.target.value }))} /></label><fieldset><legend>Escudo inicial</legend><div className={styles.shields}>{[{ key: "team.shield.shape.classic_iq", label: "Clásico" }, { key: "team.shield.shape.round", label: "Redondo" }, { key: "team.shield.shape.modern", label: "Moderno" }].map((shield) => <button aria-pressed={createDraft.shieldKey === shield.key} key={shield.key} type="button" onClick={() => setCreateDraft((current) => ({ ...current, shieldKey: shield.key }))}><i aria-hidden="true">{shield.label.slice(0, 1)}</i>{shield.label}</button>)}</div></fieldset></> : null}
          {createStep === 2 ? <><div className={styles.stepHeading}><span>Paso 2</span><h3>Fútbol</h3></div><label>Modalidad principal<select value={createDraft.modality} onChange={(event) => setCreateDraft((current) => ({ ...current, modality: event.target.value as SocialTeamCreateDraft["modality"] }))}>{modalityOptions.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}</select></label><label>Zona general<input maxLength={120} value={createDraft.zone} onChange={(event) => setCreateDraft((current) => ({ ...current, zone: event.target.value }))} /></label><label>Jugadores orientativos<select value={createDraft.targetPlayerCount} onChange={(event) => setCreateDraft((current) => ({ ...current, targetPlayerCount: Number(event.target.value) }))}><option value={10}>8-12</option><option value={14}>12-16</option><option value={20}>16-22</option><option value={28}>22+</option></select></label></> : null}
          {createStep === 3 ? <><div className={styles.stepHeading}><span>Paso 3</span><h3>Revisar</h3></div><dl className={styles.review}><div><dt>Equipo</dt><dd>{createDraft.name || "Sin nombre"}</dd></div><div><dt>Escudo</dt><dd>{createDraft.shieldKey.endsWith("round") ? "Redondo" : createDraft.shieldKey.endsWith("modern") ? "Moderno" : "Clásico"}</dd></div><div><dt>Modalidad</dt><dd>{modalityOptions.find((option) => option.id === createDraft.modality)?.label}</dd></div><div><dt>Zona</dt><dd>{createDraft.zone || "Pendiente"}</dd></div></dl><button className={styles.primary} type="button" disabled={creating || !writeAvailability.allowed || !createDraft.zone.trim()} onClick={() => void createTeam()}>{creating ? "Creando..." : "Crear equipo"}</button><p className={styles.message}>{createMessage || TEAM_CREATION_AUTHORITY.message}</p></> : null}
          <div className={styles.actions}><button type="button" onClick={() => createStep === 1 ? selectView("start") : setCreateStep((current) => current - 1)}>Volver</button>{createStep < 3 ? <button className={styles.primary} type="button" disabled={createStep === 1 && !createDraft.name.trim()} onClick={() => setCreateStep((current) => current + 1)}>Continuar</button> : null}</div>
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

export function emptySocialOnboardingDraft() {
  return { ...DEFAULT_SOCIAL_ONBOARDING_DRAFT };
}

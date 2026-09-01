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
import styles from "./social-onboarding.module.css";

type FlowView = SocialOnboardingFlow;

export type PendingSocialInvitation = {
  kind: "admin" | "player";
  token: string;
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
  onDraftChange: (draft: SocialOnboardingDraft) => void;
  onForcedViewHandled?: () => void;
  onJoin: (invitation: PendingSocialInvitation, displayName: string) => Promise<{ error?: string; ok: boolean }>;
  onOpen: () => void;
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
  onDraftChange,
  onForcedViewHandled,
  onJoin,
  onOpen,
}: SocialOnboardingProps) {
  const [open, setOpen] = useState(!dismissed);
  const [view, setView] = useState<FlowView>(() => viewForEntry(entryState));
  const [step, setStep] = useState(() => defaultStep(entryState));
  const [joinInput, setJoinInput] = useState("");
  const [joinCandidate, setJoinCandidate] = useState<PendingSocialInvitation | null>(invitation ?? null);
  const [joinMessage, setJoinMessage] = useState("");
  const [joining, setJoining] = useState(false);
  const [createStep, setCreateStep] = useState(1);
  const [createDraft, setCreateDraft] = useState({ modality: "futbol7", name: "", players: "12-16", shield: "clásico", zone: "" });
  const [online, setOnline] = useState(() => typeof navigator === "undefined" ? true : navigator.onLine);
  const [avatarPreview, setAvatarPreview] = useState("");

  const profileReady = socialProfileMinimumReady(canonicalProfile);
  const writeAvailability = socialWriteAvailability(online);
  const visibleDraft = useMemo(() => normalizeSocialOnboardingDraft(draft), [draft]);
  const activeView = invitation ? "join" : forcedView ?? view;
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

  function inspectJoinInput() {
    const parsed = parseTeamInvitationInput(joinInput);
    if (parsed.kind === "invalid") {
      setJoinMessage(parsed.reason === "EMPTY" ? "Introduce un código o enlace de invitación." : "EQUIPO NO ENCONTRADO");
      return;
    }
    if (parsed.kind === "team-code") {
      setJoinCandidate(null);
      setJoinMessage("Ese código identifica al equipo, pero no concede acceso. Pide a un admin su enlace de invitación.");
      return;
    }
    setJoinCandidate({ kind: "player", token: parsed.token });
    setJoinMessage("");
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
    <section className={styles.flow} data-social-entry-state={entryState} data-social-onboarding="v3e" aria-labelledby="social-onboarding-title">
      <header className={styles.header}>
        <div>
          <span>Primeros pasos</span>
          <h2 id="social-onboarding-title">
            {activeView === "join" ? "Unirme a un equipo" : activeView === "create" ? "Crear mi equipo" : activeView === "start" ? "¿Cómo quieres empezar?" : "Prepara tu perfil"}
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
              <div className={styles.actions}><button className={styles.primary} type="button" onClick={() => setStep(2)} disabled={!visibleDraft.displayName.trim()}>Guardar borrador y continuar</button><button type="button" onClick={() => setStep(2)}>Omitir foto</button></div>
            </div>
          ) : null}
          {step === 2 ? (
            <div className={styles.formBody}>
              <div className={styles.stepHeading}><span>Paso 2</span><h3>Dónde y cuándo juegas</h3><p>Una referencia general. No pedimos ubicación exacta.</p></div>
              <label>Ciudad o zona general<input maxLength={120} placeholder="Ej. Gràcia, Barcelona" value={visibleDraft.zone} onChange={(event) => updateDraft({ zone: event.target.value })} /></label>
              <fieldset><legend>Días habituales</legend><div className={styles.dayPicker}>{SOCIAL_DAY_OPTIONS.map((day) => <button aria-pressed={visibleDraft.days.includes(day)} key={day} type="button" onClick={() => updateDraft({ days: visibleDraft.days.includes(day) ? visibleDraft.days.filter((item) => item !== day) : [...visibleDraft.days, day] })}>{day}</button>)}</div></fieldset>
              <label>Franja aproximada<select value={visibleDraft.approximateTime} onChange={(event) => updateDraft({ approximateTime: event.target.value })}><option>08:00-12:00</option><option>12:00-16:00</option><option>16:00-20:00</option><option>20:00-22:00</option><option>22:00-00:00</option></select></label>
              <div className={styles.actions}><button type="button" onClick={() => setStep(1)}>Volver</button><button className={styles.primary} type="button" onClick={() => { setStep(3); selectView("start"); }}>Continuar</button></div>
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
          {!invitation ? <><label>Código o enlace de invitación<input autoCapitalize="off" autoCorrect="off" value={joinInput} onChange={(event) => { setJoinInput(event.target.value); setJoinMessage(""); }} /></label><button className={styles.secondary} type="button" onClick={inspectJoinInput}>Buscar equipo</button></> : null}
          {activeJoinCandidate ? (
            <div className={styles.joinConfirmation}>
              <span>Confirmar</span><strong>Acceso como {activeJoinCandidate.kind === "admin" ? "administrador" : "jugador"}</strong><p>La membresía solo aparecerá cuando el servidor la confirme y recarguemos el equipo.</p>
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
          {createStep === 1 ? <><div className={styles.stepHeading}><span>Paso 1</span><h3>Identidad</h3></div><label>Nombre del equipo<input maxLength={80} value={createDraft.name} onChange={(event) => setCreateDraft((current) => ({ ...current, name: event.target.value }))} /></label><fieldset><legend>Escudo inicial</legend><div className={styles.shields}>{["clásico", "redondo", "moderno"].map((shield) => <button aria-pressed={createDraft.shield === shield} key={shield} type="button" onClick={() => setCreateDraft((current) => ({ ...current, shield }))}><i aria-hidden="true">{shield.slice(0, 1).toUpperCase()}</i>{shield}</button>)}</div></fieldset></> : null}
          {createStep === 2 ? <><div className={styles.stepHeading}><span>Paso 2</span><h3>Fútbol</h3></div><label>Modalidad principal<select value={createDraft.modality} onChange={(event) => setCreateDraft((current) => ({ ...current, modality: event.target.value }))}>{modalityOptions.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}</select></label><label>Zona general<input maxLength={120} value={createDraft.zone} onChange={(event) => setCreateDraft((current) => ({ ...current, zone: event.target.value }))} /></label><label>Jugadores orientativos<select value={createDraft.players} onChange={(event) => setCreateDraft((current) => ({ ...current, players: event.target.value }))}><option>8-12</option><option>12-16</option><option>16-22</option><option>22+</option></select></label></> : null}
          {createStep === 3 ? <><div className={styles.stepHeading}><span>Paso 3</span><h3>Revisar</h3></div><dl className={styles.review}><div><dt>Equipo</dt><dd>{createDraft.name || "Sin nombre"}</dd></div><div><dt>Escudo</dt><dd>{createDraft.shield}</dd></div><div><dt>Modalidad</dt><dd>{modalityOptions.find((option) => option.id === createDraft.modality)?.label}</dd></div><div><dt>Zona</dt><dd>{createDraft.zone || "Pendiente"}</dd></div></dl><button className={styles.primary} type="button" disabled>Crear equipo</button><p className={styles.warning}>{TEAM_CREATION_AUTHORITY.message}</p><small>La ruta antigua hacía dos escrituras separadas. V3E no la presenta como una creación confirmada.</small></> : null}
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

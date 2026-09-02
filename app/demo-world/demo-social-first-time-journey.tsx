"use client";

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import {
  DEMO_SOCIAL_FIRST_TIME_SESSION_KEY,
  DEMO_SOCIAL_FIRST_TIME_STORIES,
} from "./demo-social-first-time-contract";
import styles from "./demo-social-first-time-journey.module.css";

type JourneyStage = "availability" | "create" | "join" | "join-confirm" | "profile" | "ready" | "start";
type SocialDemoTab = "inicio" | "mercado" | "partido" | "perfil" | "retos";
type CreateStep = 1 | 2 | 3;
type DemoPerspective = "owner" | "player";
type DemoInvitationState = "ACTIVE" | "IDLE" | "USED";

type JourneyState = {
  activeTeam: string;
  cardPreview: boolean;
  createStep: CreateStep;
  createdLocally: boolean;
  days: string[];
  joinCode: string;
  codeIdentified: boolean;
  inviteOpened: boolean;
  invitationState: DemoInvitationState;
  marketVisible: boolean;
  marketViewedAsRival: boolean;
  modality: string;
  multiTeam: boolean;
  name: string;
  offline: boolean;
  perspective: DemoPerspective;
  position: string;
  profileConfirmed: boolean;
  replayVerified: boolean;
  revokedInvite: boolean;
  revokedInviteBlocked: boolean;
  rosterJoined: boolean;
  shield: string;
  stage: JourneyStage;
  teamName: string;
  timeRange: string;
  zone: string;
};

const initialState: JourneyState = {
  activeTeam: "Sin equipo",
  cardPreview: false,
  createStep: 1,
  createdLocally: false,
  days: [],
  joinCode: "PIQ-DEMO",
  codeIdentified: false,
  inviteOpened: false,
  invitationState: "IDLE",
  marketVisible: false,
  marketViewedAsRival: false,
  modality: "Fútbol 7",
  multiTeam: false,
  name: "",
  offline: false,
  perspective: "owner",
  position: "Mediocentro / pivote",
  profileConfirmed: false,
  replayVerified: false,
  revokedInvite: false,
  revokedInviteBlocked: false,
  rosterJoined: false,
  shield: "Clásico",
  stage: "profile",
  teamName: "Cobalto Social",
  timeRange: "20:00-22:00",
  zone: "",
};

function readState(): JourneyState {
  if (typeof window === "undefined") return initialState;
  try {
    const parsed = JSON.parse(window.sessionStorage.getItem(DEMO_SOCIAL_FIRST_TIME_SESSION_KEY) ?? "null") as Partial<JourneyState> | null;
    const createStep: CreateStep = parsed?.createStep === 2 || parsed?.createStep === 3 ? parsed.createStep : 1;
    return parsed ? {
      ...initialState,
      ...parsed,
      createStep,
      days: Array.isArray(parsed.days) ? parsed.days.filter((day): day is string => typeof day === "string") : [],
    } : initialState;
  } catch {
    return initialState;
  }
}

export function DemoSocialFirstTimeJourney({ onClose, onNavigate }: {
  onClose: () => void;
  onNavigate: (tab: SocialDemoTab) => void;
}) {
  const [state, setState] = useState<JourneyState>(readState);
  const [message, setMessage] = useState("Sesión local preparada. Remote writes: 0.");
  const dialogRef = useRef<HTMLElement>(null);

  useEffect(() => {
    window.sessionStorage.setItem(DEMO_SOCIAL_FIRST_TIME_SESSION_KEY, JSON.stringify(state));
  }, [state]);

  useEffect(() => {
    const previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    dialogRef.current?.querySelector<HTMLElement>("button, input, select, a[href]")?.focus();
    return () => previousFocus?.focus();
  }, []);

  useEffect(() => {
    dialogRef.current?.scrollTo({ top: 0 });
  }, [state.createStep, state.stage]);

  function patch(next: Partial<JourneyState>) {
    setState((current) => ({ ...current, ...next }));
  }

  function reset() {
    window.sessionStorage.removeItem(DEMO_SOCIAL_FIRST_TIME_SESSION_KEY);
    setState(initialState);
    setMessage("Recorrido restaurado. Remote writes: 0.");
  }

  function navigate(tab: SocialDemoTab) {
    onNavigate(tab);
    onClose();
  }

  function handleDialogKeyDown(event: KeyboardEvent<HTMLElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      onClose();
      return;
    }
    if (event.key !== "Tab") return;
    const focusable = Array.from(dialogRef.current?.querySelectorAll<HTMLElement>("button:not([disabled]), input:not([disabled]), select:not([disabled]), a[href]") ?? []);
    if (!focusable.length) return;
    const first = focusable[0];
    const last = focusable.at(-1);
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last?.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  return (
    <div className={styles.backdrop} role="presentation">
      <section className={styles.journey} role="dialog" aria-modal="true" aria-labelledby="demo-social-title" data-demo-social-first-time="v3f" onKeyDown={handleDialogKeyDown} ref={dialogRef}>
        <header>
          <div><span>Mundo Demo · First-time social journey</span><h2 id="demo-social-title">Empieza como un jugador nuevo</h2></div>
          <button type="button" onClick={onClose} aria-label="Cerrar recorrido">×</button>
        </header>
        <div className={styles.proof}><span>DATOS FICTICIOS</span><span>REMOTE WRITES 0</span><span>NOTIFICACIONES 0</span><span>STRIPE 0</span></div>

        {state.stage === "profile" ? <div className={styles.body}>
          <Step number="1" title="Tu perfil" copy="Tres datos bastan para empezar. La foto es opcional." />
          <div className={styles.grid}><label>Nombre visible<input value={state.name} onChange={(event) => patch({ name: event.target.value })} placeholder="Alex Demo" /></label><label>Posición<select value={state.position} onChange={(event) => patch({ position: event.target.value })}><option>Portero</option><option>Defensa central</option><option>Mediocentro / pivote</option><option>Delantero / punta</option></select></label><label>Modalidad<select value={state.modality} onChange={(event) => patch({ modality: event.target.value })}><option>Fútbol sala</option><option>Fútbol 7</option><option>Fútbol 11</option></select></label><div className={styles.optionalPhoto}><b aria-hidden="true">+</b><span>Foto opcional</span><small>Omitida en esta historia</small></div></div>
          <Actions secondary="Ahora no" onSecondary={() => patch({ stage: "start" })} primary="Continuar" onPrimary={() => patch({ name: state.name.trim() || "Alex Demo", stage: "availability" })} />
        </div> : null}

        {state.stage === "availability" ? <div className={styles.body}>
          <Step number="2" title="Dónde y cuándo juegas" copy="Solo una zona general; nunca pedimos coordenadas al cargar." />
          <label>Ciudad o zona general<input value={state.zone} onChange={(event) => patch({ zone: event.target.value })} placeholder="Gràcia, Barcelona" /></label>
          <div className={styles.dayRow}>{["L", "M", "X", "J", "V", "S", "D"].map((day) => <button aria-pressed={state.days.includes(day)} key={day} type="button" onClick={() => patch({ days: state.days.includes(day) ? state.days.filter((item) => item !== day) : [...state.days, day] })}>{day}</button>)}</div>
          <label>Franja aproximada<select value={state.timeRange} onChange={(event) => patch({ timeRange: event.target.value })}><option>20:00-22:00</option><option>18:00-20:00</option><option>Fin de semana</option></select></label>
          <Actions secondary="Volver" onSecondary={() => patch({ stage: "profile" })} primary="Guardar perfil" onPrimary={() => { patch({ profileConfirmed: true, stage: "start", zone: state.zone.trim() || "Barcelona" }); setMessage("Perfil confirmado simulado. Remote writes: 0."); }} />
        </div> : null}

        {state.stage === "start" ? <div className={styles.body}>
          <Step number="3" title="Cómo quieres empezar" copy={state.profileConfirmed ? "Perfil confirmado simulado. Elige una dirección." : "Puedes explorar sin confirmar un perfil."} />
          <div className={styles.choices}><button type="button" onClick={() => patch({ stage: "join" })}><b>+</b><strong>Unirme a un equipo</strong><small>Prueba el código sintético PIQ-DEMO.</small></button><button type="button" onClick={() => patch({ createStep: 1, stage: "create" })}><b>◇</b><strong>Crear mi equipo</strong><small>Simula identidad, escudo y modalidad.</small></button><button type="button" onClick={() => navigate("mercado")}><b>⌕</b><strong>Buscar una pachanga</strong><small>Abre Mercado V3D con datos ficticios.</small></button></div>
        </div> : null}

        {state.stage === "join" ? <div className={styles.body}>
          <Step number="1/2" title="Código o enlace" copy="La Demo reconoce únicamente PIQ-DEMO y no consulta servidores." />
          <label>Código del equipo<input value={state.joinCode} onChange={(event) => patch({ joinCode: event.target.value })} /></label>
          <p className={styles.localNotice}>El código identifica este equipo ficticio, pero nunca concede acceso por sí solo.</p>
          <Actions secondary="Volver" onSecondary={() => patch({ stage: "start" })} primary="Buscar equipo" onPrimary={() => {
            if (state.joinCode.trim().toUpperCase() !== "PIQ-DEMO") {
              setMessage("EQUIPO NO ENCONTRADO. Conservamos el código para que puedas corregirlo.");
              return;
            }
            patch({ codeIdentified: true, stage: "join-confirm" });
            setMessage("Equipo ficticio localizado. El código identifica, pero no concede acceso.");
          }} />
          {message.startsWith("EQUIPO NO ENCONTRADO") ? <p className={styles.message} role="status">{message}</p> : null}
        </div> : null}

        {state.stage === "join-confirm" ? <div className={styles.body}>
          <Step number="2/2" title="Equipo identificado" copy="El código no es una invitación y no puede crear una membresía." />
          <article className={styles.teamPreview}><i aria-hidden="true">CR</i><div><span>Equipo encontrado</span><strong>Cobalto Raval</strong><p>Fútbol 7 · Barcelona · 14 miembros</p></div></article>
          <p className={styles.localNotice}>Necesitas un enlace de invitación válido para solicitar la entrada.</p>
          <Actions secondary="Volver" onSecondary={() => patch({ stage: "join" })} primary="Entendido" onPrimary={() => patch({ stage: "start" })} />
        </div> : null}

        {state.stage === "create" ? <div className={styles.body}>
          <nav className={styles.createSteps} aria-label="Pasos para crear un equipo"><span aria-current={state.createStep === 1 ? "step" : undefined}>1</span><span aria-current={state.createStep === 2 ? "step" : undefined}>2</span><span aria-current={state.createStep === 3 ? "step" : undefined}>3</span></nav>
          {state.createStep === 1 ? <><Step number="1/3" title="Identidad" copy="Elige un nombre y uno de los escudos iniciales." /><label>Nombre del equipo<input value={state.teamName} onChange={(event) => patch({ teamName: event.target.value })} /></label><fieldset className={styles.shieldOptions}><legend>Escudo inicial</legend>{["Clásico", "Redondo", "Moderno"].map((shield) => <button aria-pressed={shield === state.shield} key={shield} type="button" onClick={() => patch({ shield })}><i aria-hidden="true">{shield.slice(0, 1)}</i>{shield}</button>)}</fieldset><Actions secondary="Volver" onSecondary={() => patch({ stage: "start" })} primary="Continuar" onPrimary={() => patch({ createStep: 2, teamName: state.teamName.trim() || "Cobalto Social" })} /></> : null}
          {state.createStep === 2 ? <><Step number="2/3" title="Fútbol" copy="Modalidad y zona general, sin configuración avanzada." /><div className={styles.grid}><label>Modalidad<select value={state.modality} onChange={(event) => patch({ modality: event.target.value })}><option>Fútbol 7</option><option>Fútbol sala</option><option>Fútbol 11</option></select></label><label>Zona<input value={state.zone} onChange={(event) => patch({ zone: event.target.value })} /></label><label>Jugadores orientativos<select defaultValue="12-16"><option>8-12</option><option>12-16</option><option>16-22</option></select></label></div><Actions secondary="Volver" onSecondary={() => patch({ createStep: 1 })} primary="Revisar" onPrimary={() => patch({ createStep: 3, zone: state.zone.trim() || "Barcelona" })} /></> : null}
          {state.createStep === 3 ? <><Step number="3/3" title="Revisar" copy="Esta confirmación solo modifica la sesión local del Mundo Demo." /><dl className={styles.review}><div><dt>Equipo</dt><dd>{state.teamName}</dd></div><div><dt>Escudo</dt><dd>{state.shield}</dd></div><div><dt>Modalidad</dt><dd>{state.modality}</dd></div><div><dt>Zona</dt><dd>{state.zone}</dd></div></dl><p className={styles.localNotice}>En producción esta acción exige autoridad canónica. Aquí: remote writes 0.</p><Actions secondary="Volver" onSecondary={() => patch({ createStep: 2 })} primary="Crear solo en Demo" onPrimary={() => { patch({ activeTeam: state.teamName || "Cobalto Social", createdLocally: true, perspective: "owner", stage: "ready" }); setMessage("Equipo ficticio creado. Owner y selección confirmados solo en esta sesión."); }} /></> : null}
        </div> : null}

        {state.stage === "ready" ? <div className={styles.body}>
          <Step number="✓" title={state.activeTeam} copy={`${state.name || "Alex Demo"} · ${state.position} · ${state.modality} · ${state.zone || "Barcelona"}`} />
          <article className={styles.teamPreview}><i aria-hidden="true">{state.shield.slice(0, 1)}</i><div><span>Portada de equipo · {state.perspective === "owner" ? "Owner" : "Jugador"}</span><strong>{state.activeTeam}</strong><p>{state.modality} · {state.zone || "Barcelona"} · {state.rosterJoined ? 2 : 1} miembros</p></div></article>
          <div className={styles.readyGrid}>
            <button type="button" onClick={() => navigate("inicio")}><strong>Inicio</strong><small>Portada con equipo activo</small></button>
            <button type="button" onClick={() => navigate("partido")}><strong>Partidos V3B</strong><small>Próximos, asistencia y alineación</small></button>
            <button type="button" onClick={() => navigate("retos")}><strong>Retos V3C</strong><small>Rivales y contrapropuestas</small></button>
            <button type="button" onClick={() => navigate("mercado")}><strong>Mercado V3D</strong><small>Jugadores y partidos públicos</small></button>
            {state.createdLocally && state.perspective === "owner" ? <button type="button" onClick={() => state.offline ? setMessage("Necesitas conexión para confirmar esta acción.") : navigate("partido")}><strong>Crear primer partido</strong><small>Abre Partidos V3B</small></button> : null}
          </div>
          {state.createdLocally ? <div className={styles.teamCode}><span>Código sintético</span><strong>PIQ-DEMO-NUEVO</strong><small>Identifica; no concede acceso.</small><button type="button" onClick={() => { patch({ codeIdentified: true }); setMessage("Código reconocido. Membresías creadas: 0; hace falta invitación."); }}>Probar código</button></div> : null}

          {state.createdLocally ? <article className={styles.marketPreview} data-demo-invitation={state.invitationState}>
            <div><span>Invitación de jugador V2 · simulada</span><strong>{state.invitationState === "IDLE" ? "Sin enlace activo" : state.invitationState === "ACTIVE" ? "Enlace activo" : "Aceptada"}</strong><small>Un uso · caducidad simulada · token no mostrado</small></div>
            <p>Perspectiva actual: {state.perspective === "owner" ? "owner" : "jugador ordinario"}. La plantilla contiene {state.rosterJoined ? 2 : 1} membresía{state.rosterJoined ? "s" : ""}.</p>
            <div className={styles.inviteActions}>
              {state.perspective === "owner" ? <>
                <button type="button" onClick={() => state.offline ? setMessage("Necesitas conexión para confirmar esta acción.") : state.invitationState === "IDLE" ? (patch({ invitationState: "ACTIVE" }), setMessage("Invitación sintética creada. Se comparte sin persistir el token.")) : setMessage("Invitación sintética compartida. External notifications: 0.")}>{state.invitationState === "IDLE" ? "Crear invitación" : "Compartir invitación"}</button>
                <button type="button" onClick={() => state.offline ? setMessage("Necesitas conexión para confirmar esta acción.") : (patch({ revokedInvite: true }), setMessage("Segundo enlace sintético revocado."))}>Revocar otro enlace</button>
                <button type="button" onClick={() => patch({ perspective: "player" })}>Ver como jugador</button>
              </> : <>
                {state.invitationState === "ACTIVE" && !state.inviteOpened ? <button type="button" onClick={() => { patch({ inviteOpened: true }); setMessage("Invitación abierta. Aún no existe membresía."); }}>Abrir invitación</button> : null}
                {state.invitationState === "ACTIVE" && state.inviteOpened ? <button type="button" onClick={() => state.offline ? setMessage("Necesitas conexión para confirmar esta acción.") : (patch({ invitationState: "USED", rosterJoined: true }), setMessage("Entrada confirmada. Una membresía canónica simulada."))}>Confirmar entrada</button> : null}
                {state.rosterJoined ? <button type="button" onClick={() => { patch({ replayVerified: true }); setMessage("Replay idempotente: sigue existiendo una sola membresía."); }}>Repetir aceptación</button> : null}
                {state.revokedInvite ? <button type="button" onClick={() => { patch({ revokedInviteBlocked: true }); setMessage("Enlace revocado: entrada bloqueada, cero membresías nuevas."); }}>Probar enlace revocado</button> : null}
                <button type="button" onClick={() => setMessage("Permiso denegado: un jugador ordinario no puede invitar.")}>Intentar invitar</button>
                <button type="button" onClick={() => patch({ perspective: "owner" })}>Volver a owner</button>
              </>}
            </div>
            <small>{state.replayVerified ? "Replay verificado · 1 membresía" : "Replay pendiente"} · {state.revokedInviteBlocked ? "Revocación verificada" : "Revocación pendiente"} · {state.codeIdentified ? "Código sin acceso verificado" : "Código pendiente"}</small>
          </article> : null}

          <div className={styles.toggles}><label><input checked={state.cardPreview} type="checkbox" onChange={(event) => patch({ cardPreview: event.target.checked })} /> Vista previa de carta</label><label><input checked={state.marketVisible} type="checkbox" onChange={(event) => { patch({ marketVisible: event.target.checked, marketViewedAsRival: false }); setMessage(event.target.checked ? "Perfil ficticio publicado solo en esta sesión Demo." : "Visibilidad de Mercado pausada en esta sesión Demo."); }} /> Perfil publicado en Mercado</label><label><input checked={state.multiTeam} type="checkbox" onChange={(event) => patch({ multiTeam: event.target.checked, activeTeam: event.target.checked ? "Cobalto Raval" : state.teamName })} /> Usuario con varios equipos</label><label><input checked={state.offline} type="checkbox" onChange={(event) => { patch({ offline: event.target.checked }); setMessage(event.target.checked ? "Modo offline: lecturas disponibles, escrituras bloqueadas." : "Reconectado a la sesión demo."); }} /> Probar offline</label></div>
          {state.cardPreview ? <article className={styles.cardPreview} aria-label="Vista previa local de carta"><span>{state.position}</span><strong>--</strong><b>{state.name || "Alex Demo"}</b><small>Vista previa · sin rating inventado</small></article> : null}
          {state.marketVisible ? <article className={styles.marketPreview}><div><span>Mercado · perfil ficticio</span><strong>{state.name || "Alex Demo"}</strong><small>{state.position} · {state.modality} · {state.zone || "Barcelona"}</small></div><button type="button" onClick={() => patch({ marketViewedAsRival: !state.marketViewedAsRival })}>{state.marketViewedAsRival ? "Volver a mi vista" : "Ver como otro equipo"}</button><p>{state.marketViewedAsRival ? "Así aparece tu perfil público para un equipo rival." : "Vista privada de tu disponibilidad publicada."}</p></article> : null}
          {state.multiTeam ? <div className={styles.teamSwitch}><button type="button" onClick={() => patch({ activeTeam: "Cobalto Raval" })}>Cobalto Raval</button><button type="button" onClick={() => patch({ activeTeam: "Vértice Gràcia" })}>Vértice Gràcia</button></div> : null}
          <p className={styles.message} role="status">{state.offline ? "Modo offline: lecturas disponibles, escrituras bloqueadas." : message}</p>
        </div> : null}

        <details className={styles.storyLedger}><summary>{DEMO_SOCIAL_FIRST_TIME_STORIES.length} historias cubiertas</summary><ol>{DEMO_SOCIAL_FIRST_TIME_STORIES.map((story, index) => <li key={`${index}-${story}`}>{story}</li>)}</ol></details>
        <footer><button type="button" onClick={reset}>Reiniciar recorrido</button><button type="button" onClick={onClose}>Cerrar</button></footer>
      </section>
    </div>
  );
}

function Step({ copy, number, title }: { copy: string; number: string; title: string }) {
  return <div className={styles.step}><span>{number}</span><div><h3>{title}</h3><p>{copy}</p></div></div>;
}

function Actions({ onPrimary, onSecondary, primary, secondary }: { onPrimary: () => void; onSecondary: () => void; primary: string; secondary: string }) {
  return <div className={styles.actions}><button type="button" onClick={onSecondary}>{secondary}</button><button type="button" onClick={onPrimary}>{primary}</button></div>;
}

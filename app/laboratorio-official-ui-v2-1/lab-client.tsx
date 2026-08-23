"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  OfficialHomeGameDashboard,
  OfficialSecondaryActions,
  OfficialTeamAccess,
} from "../_components/official-home-game-dashboard";
import { OfficialMarketGameView, type OfficialMarketTab } from "../_components/official-market-game-view";
import { OfficialMatchGameHub } from "../_components/official-match-game-hub";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { PlayerCosmeticCard } from "../_components/player-cosmetic-card";
import { TeamShieldView } from "../_components/team-shield-view";
import type { MobileAppTab } from "../mobile-app-nav";
import { TEAM_SHIELD_DEFAULT_CONFIG } from "../team-shield-contract";
import styles from "./official-ui-v2-1-lab.module.css";

type LabSurface = "arbitro" | "avisos" | "carta" | "equipo" | "escudo" | "inicio" | "mercado" | "partido" | "ranking";
type LabPane = "admin" | "alineacion" | "proximo" | "resultado";

const surfaces: Array<{ id: LabSurface; label: string }> = [
  { id: "inicio", label: "Inicio" },
  { id: "partido", label: "Partido" },
  { id: "mercado", label: "Mercado" },
  { id: "ranking", label: "Ranking" },
  { id: "avisos", label: "Avisos" },
  { id: "carta", label: "Carta" },
  { id: "escudo", label: "Escudo" },
  { id: "equipo", label: "Equipo" },
  { id: "arbitro", label: "Árbitro" },
];

const matchPanes: Array<{ id: LabPane; label: string }> = [
  { id: "proximo", label: "Próximo" },
  { id: "alineacion", label: "Alineación" },
  { id: "resultado", label: "Resultado" },
  { id: "admin", label: "Admin" },
];

const names = ["Alberto", "Marta", "Sergio", "Nuria", "Dani", "Paula", "Iván", "Lucía", "Álex", "Carla", "Hugo", "Sara"];

function validSurface(value: string): LabSurface {
  return surfaces.some((surface) => surface.id === value) ? value as LabSurface : "inicio";
}

function validPane(value: string): LabPane {
  return matchPanes.some((pane) => pane.id === value) ? value as LabPane : "proximo";
}

function shellTab(surface: LabSurface): MobileAppTab {
  if (surface === "partido") return "partido";
  if (surface === "mercado") return "mercado";
  if (surface === "ranking" || surface === "equipo" || surface === "escudo") return "equipo";
  if (surface === "avisos" || surface === "carta" || surface === "arbitro") return "perfil";
  return "inicio";
}

function updateLabUrl(surface: LabSurface, pane?: LabPane) {
  const url = new URL(window.location.href);
  url.searchParams.set("surface", surface);
  if (pane) url.searchParams.set("pane", pane);
  else url.searchParams.delete("pane");
  window.history.replaceState({}, "", url);
}

function LabToolbar({ capture, onSurface, surface, theme }: {
  capture: boolean;
  onSurface: (surface: LabSurface) => void;
  surface: LabSurface;
  theme: string;
}) {
  if (capture) return null;
  return (
    <nav className={styles.labToolbar} aria-label="Superficies del laboratorio V2.1">
      <span>V2.1 · fixtures visuales · sin Supabase</span>
      <div>{surfaces.map((item) => <button aria-current={surface === item.id ? "page" : undefined} key={item.id} type="button" onClick={() => onSurface(item.id)}>{item.label}</button>)}</div>
      <div className={styles.themeLinks}>
        <Link aria-current={theme === "dark" ? "page" : undefined} href={`?surface=${surface}&theme=dark`}>Oscuro</Link>
        <Link aria-current={theme === "light" ? "page" : undefined} href={`?surface=${surface}&theme=light`}>Claro</Link>
      </div>
    </nav>
  );
}

function LabPlayerCard() {
  return (
    <PlayerCosmeticCard
      className="readonly-card gold-card"
      facets={[
        { key: "ritmo", label: "RIT", value: 78 },
        { key: "tiro", label: "TIR", value: 75 },
        { key: "pase", label: "PAS", value: 82 },
        { key: "regate", label: "REG", value: 79 },
        { key: "defensa", label: "DEF", value: 71 },
        { key: "fisico", label: "FIS", value: 77 },
      ]}
      meta="18 goles · 34 PJ"
      name="Alberto"
      position="MC"
      score={78}
    />
  );
}

function HomeSurface({ role, state }: { role: string; state: string }) {
  const noTeam = state === "no-team";
  return (
    <OfficialHomeGameDashboard
      access={!noTeam ? (
        <OfficialTeamAccess selector={<label className={styles.teamSelector}><span>Equipo activo</span><select defaultValue="team"><option value="team">Los del Miércoles</option></select></label>}>
          <dl className="official-home-team-access-details"><div><dt>Código</dt><dd>IQ-8K4P</dd></div><div><dt>Rol</dt><dd>{role}</dd></div><div><dt>Nivel</dt><dd>76</dd></div><div><dt>Plantilla</dt><dd>18</dd></div></dl>
          <div className="official-home-team-access-actions"><button type="button">Copiar invitación</button><button type="button">Identidad</button><button type="button">Ajustes</button></div>
        </OfficialTeamAccess>
      ) : undefined}
      activity={noTeam ? [] : [
        { detail: "4 - 3 · Can Caralleu", id: "a1", label: "Resultado", title: "Victoria del equipo", tone: "accent" },
        { detail: "La alineación ya refleja el cambio.", id: "a2", label: "Partido", title: "Marta se ha apuntado", tone: "info" },
        { detail: "Abre el aviso para ver y reclamar.", id: "a3", label: "Logro", title: "Nueva recompensa pendiente", tone: "warning" },
      ]}
      identity={{
        context: noTeam ? "Crea o encuentra un equipo para entrar en el vestuario." : "Temporada 2026/27 · Barcelona · Fútbol 7",
        name: noTeam ? "Tu próximo equipo" : "Los del Miércoles",
      }}
      metrics={noTeam ? [
        { label: "Partidos", value: "-" }, { label: "Próximos", value: "-" }, { label: "Plantilla", value: "-" }, { label: "Nivel", value: "-" },
      ] : [
        { label: "Partidos", value: 28 }, { label: "Próximos", value: 2 }, { label: "Plantilla", value: 18 }, { label: "Nivel", value: 76 },
      ]}
      nextAction={noTeam
        ? { detail: "Una sola acción válida para comenzar.", eyebrow: "Primer paso", label: "Encontrar equipo", onClick: () => undefined }
        : { detail: "Miércoles 26 · 21:00 · Can Caralleu", eyebrow: "Tu asistencia", label: "Confirmar asistencia", onClick: () => undefined }}
      object={noTeam ? <div className={styles.emptyObject}><Image src="/icon-512.png" alt="Pachangas IQ" width={180} height={180} priority /><small>El objeto del equipo aparecerá aquí.</small></div> : <TeamShieldView className="official-home-team-shield" config={{ ...TEAM_SHIELD_DEFAULT_CONFIG, initials: "LDM" }} label="Escudo de Los del Miércoles" />}
      secondaryActions={<OfficialSecondaryActions><button type="button">Mi ficha</button><button type="button">Mi equipo</button><button type="button">Configurar</button><button type="button">Manual</button><button type="button">Cerrar sesión</button></OfficialSecondaryActions>}
      upcoming={noTeam ? [] : [
        { context: "Fútbol 7", date: "Mié 26 · 21:00", id: "m1", meta: "12/14 confirmados · 2 plazas", onOpen: () => undefined, title: "Can Caralleu" },
        { context: "Fútbol sala", date: "Dom 30 · 11:30", id: "m2", meta: "8/10 confirmados · 2 plazas", onOpen: () => undefined, title: "Pavelló Nord" },
      ]}
    />
  );
}

function Pitch() {
  return (
    <div className={styles.pitch} aria-label="Campo de alineación">
      <span className={styles.halfway} /><span className={styles.circle} />
      {names.slice(0, 10).map((name, index) => (
        <button className={styles.player} data-side={index < 5 ? "a" : "b"} style={{ left: `${10 + (index % 5) * 20}%`, top: index < 5 ? "22%" : "70%" }} type="button" key={name}><b>{index % 5 === 0 ? "POR" : index % 3 === 0 ? "DEL" : "MC"}</b><span>{name}</span></button>
      ))}
      <div className={styles.balance}><span>Equilibrio</span><strong>Equipo 1 +2</strong></div>
    </div>
  );
}

function MatchSurface({ initialPane, role }: { initialPane: LabPane; role: string }) {
  const [pane, setPane] = useState(initialPane);
  const isAdmin = role === "admin" || role === "owner";
  const panes = isAdmin ? matchPanes : matchPanes.filter((item) => item.id !== "admin");
  const selectPane = (next: string) => {
    const safePane = validPane(next);
    setPane(safePane);
    updateLabUrl("partido", safePane);
  };
  return (
    <main className={styles.matchPage} data-mobile-tab="partido" data-pane={pane}>
      <OfficialMatchGameHub
        activePane={pane}
        context={{ date: "miércoles 26 de agosto · 21:00", kind: "Fútbol 7", label: "Partido activo", place: "Can Caralleu", status: <button className={styles.statusButton} type="button">Alineación abierta</button>, title: "Miércoles en Can Caralleu" }}
        onSelectPane={selectPane}
        panes={panes}
        tools={pane === "alineacion" ? <div className={styles.sideTools}><span>Herramientas</span><button type="button">Aleatorio</button><button type="button">Equilibrado</button><button type="button">Cerrar</button></div> : undefined}
        share={pane === "proximo" ? <button className={styles.shareButton} type="button">Compartir partido</button> : undefined}
      />
      <div className={styles.matchWorkspace}>
        {pane === "alineacion" ? <div className={styles.lineup}><Pitch /><aside><span>Banquillo</span>{names.slice(10).map((name) => <button type="button" key={name}><b>RES</b>{name}</button>)}</aside></div> : null}
        {pane === "proximo" ? <div className={styles.nextMatch}><section className={styles.matchCallout}><span>Tu asistencia</span><strong>¿Vienes al partido?</strong><p>12 de 14 plazas confirmadas · 4,00 € por persona</p><div><button type="button">No voy</button><button type="button">Duda</button><button className={styles.accentButton} type="button">Voy</button></div></section><section className={styles.roster}><header><span>Convocatoria</span><strong>12 confirmados</strong></header><div>{names.map((name, index) => <p key={name}><b>{index % 5 === 0 ? "POR" : "MC"}</b><span>{name}</span><small>{index < 10 ? "Voy" : "Reserva"}</small></p>)}</div></section></div> : null}
        {pane === "resultado" ? <div className={styles.result}><section className={styles.score}><span>Equipo 1</span><strong>4 <i>:</i> 3</strong><span>Equipo 2</span><small>Pendiente de confirmar</small><button className={styles.accentButton} type="button">Finalizar partido</button></section><section className={styles.scorers}><header><span>Goleadores</span><strong>7 goles</strong></header>{names.slice(0, 6).map((name, index) => <p key={name}><span>{name}</span><button type="button">−</button><b>{index < 2 ? 2 : index === 2 ? 1 : 0}</b><button type="button">+</button></p>)}</section></div> : null}
        {pane === "admin" ? <div className={styles.admin}><section><header><span>Configuración</span><strong>Partido</strong></header><div><button type="button">Editar fecha y campo</button><button type="button">Cerrar alineación</button></div></section><section><header><span>Mercado</span><strong>Plazas e invitados</strong></header><div><button type="button">Abrir al mercado</button><button type="button">Invitar jugador</button></div></section><section><header><span>Privacidad</span><strong>Acceso</strong></header><div><button type="button">Copiar invitación</button><button type="button">Gestionar solicitudes</button></div></section><section className={styles.danger}><header><span>Acciones peligrosas</span><strong>Partido</strong></header><div><button type="button">Cancelar partido</button><button type="button">Eliminar partido</button></div></section></div> : null}
      </div>
    </main>
  );
}

function MarketSurface({ role }: { role: string }) {
  const [tab, setTab] = useState("jugadores");
  const marketTabs: OfficialMarketTab[] = ["jugadores", "partidos", "retos", "equipos", "arbitros"].map((id) => ({ id, label: id[0].toUpperCase() + id.slice(1), onSelect: () => setTab(id) }));
  const isAdmin = role === "admin" || role === "owner";
  return (
    <main className={styles.marketPage} data-mobile-tab="mercado">
      <OfficialMarketGameView
        actions={<Link className={styles.backLink} href="/laboratorio-official-ui-v2-1?surface=inicio">Volver</Link>}
        activeTab={tab}
        adminHref={isAdmin ? "#market-admin" : undefined}
        context={tab === "jugadores" ? <div className={styles.marketContext}><strong>Filtrado por próximo partido:</strong><span>2 plazas libres</span></div> : undefined}
        filters={tab === "jugadores" || tab === "partidos" ? <div className={styles.marketFilters}><label>Zona<input defaultValue="Barcelona" /></label><label>Día<select defaultValue="Todos"><option>Todos</option></select></label><label>Modalidad<select defaultValue="Fútbol 7"><option>Fútbol 7</option></select></label><label>Posición<select defaultValue="Todas"><option>Todas</option></select></label></div> : undefined}
        tabs={marketTabs}
        title={marketTabs.find((item) => item.id === tab)?.label ?? "Mercado"}
      >
        <div className={styles.marketResults}>
          <section className={styles.marketList} aria-label="Resultados del mercado">
            {(tab === "partidos" ? ["Can Caralleu", "Pavelló Nord", "Camp de la Mina", "Montjuïc"] : names.slice(0, 7)).map((item, index) => <button aria-current={index === 0 ? "true" : undefined} key={item} type="button"><b>{tab === "partidos" ? `${2 + index} plazas` : `${78 - index} · ${index % 3 ? "MC" : "DEL"}`}</b><strong>{item}</strong><small>Barcelona · {tab === "partidos" ? "Mié 21:00" : "Disponible esta semana"}</small></button>)}
          </section>
          <aside className={styles.marketDetail}><span>{tab === "partidos" ? "Partido seleccionado" : "Ficha seleccionada"}</span><div className={styles.detailObject}>{tab === "partidos" ? <Image src="/icon-512.png" alt="Equipo" width={180} height={180} /> : <LabPlayerCard />}</div><strong>{tab === "partidos" ? "Miércoles en Can Caralleu" : "Alberto · MC"}</strong><p>{tab === "partidos" ? "Fútbol 7 · 12/14 confirmados · nivel 72-82" : "Nivel verificado · Barcelona · disponible miércoles"}</p><button className={styles.accentButton} type="button">{tab === "partidos" ? "Solicitar plaza" : isAdmin ? "Invitar al partido" : "Ver ficha"}</button></aside>
        </div>
      </OfficialMarketGameView>
    </main>
  );
}

function RankingSurface() {
  return <main className={styles.standardPage}><header className={styles.pageHeader}><div><span>Barcelona · 2026/27</span><h1>Ranking provincial</h1></div><b>Posición provisional</b></header><section className={styles.ownRank}><div><span>Tu posición</span><strong>#18</strong><small>Season Score 712</small></div><p>Necesitas 2 rivales lógicos más para optar al Top 10 territorial.</p></section><section className={styles.table}><header><span>Pos.</span><span>Equipo</span><span>PJ</span><span>Season Score</span></header>{["Furia Vallès", "Atlètic Nord", "Los del Miércoles", "Barrio Sur", "Diagonal FC", "Raval United"].map((team, index) => <div data-own={index === 2 ? "true" : "false"} key={team}><b>{index + 1}</b><strong>{team}</strong><span>{16 - index}</span><output>{824 - index * 31}</output></div>)}</section></main>;
}

function NotificationsSurface() {
  return <main className={styles.standardPage}><header className={styles.pageHeader}><div><span>Centro de avisos</span><h1>Avisos</h1></div><button type="button">Marcar todo leído</button></header><div className={styles.notifications}><nav><button aria-current="page" type="button">Todos · 4</button><button type="button">Partidos</button><button type="button">Mercado</button><button type="button">Logros</button><button type="button">Seguridad</button></nav><section>{["Nueva solicitud desde Mercado", "Marta se ha apuntado", "Alineación actualizada", "Nuevo logro desbloqueado"].map((title, index) => <article data-priority={index === 0 ? "action" : "info"} key={title}><span>{index === 0 ? "Acción necesaria" : "Nuevo"}</span><div><strong>{title}</strong><p>{index === 0 ? "Revisa la ficha y acepta o rechaza la solicitud." : "Estado confirmado por el servidor central."}</p></div><button type="button">Abrir</button></article>)}</section></div></main>;
}

function ObjectSurface({ kind }: { kind: "carta" | "escudo" }) {
  const card = kind === "carta";
  return <main className={styles.objectPage}><section className={styles.objectHero}>{card ? <LabPlayerCard /> : <div className={styles.shield}><Image src="/icon-512.png" alt="Escudo de Los del Miércoles" width={512} height={512} priority /></div>}<span>{card ? "Carta oficial" : "Escudo oficial"}</span><strong>{card ? "Alberto · GRL 78" : "Los del Miércoles"}</strong><small>Revisión confirmada por el servidor</small></section><section className={styles.objectControls}><header><span>{card ? "Colección personal" : "Identidad del equipo"}</span><h1>{card ? "Personalizar carta" : "Personalizar escudo"}</h1></header><nav>{(card ? ["Marco", "Fondo", "Nombre", "Efecto", "Título", "Logro"] : ["Forma", "Borde", "Fondo", "Símbolo", "Efecto"]).map((item, index) => <button aria-current={index === 0 ? "page" : undefined} type="button" key={item}>{item}</button>)}</nav><div className={styles.choices}>{["Original", "Plata", "Oro", "Esmeralda", "Noche", "Copa"].map((item, index) => <button type="button" key={item}><span data-index={index} />{item}</button>)}</div><footer><button type="button">Deshacer</button><button className={styles.accentButton} type="button">Guardar</button></footer></section></main>;
}

function TeamSurface() {
  return <main className={styles.standardPage}><header className={styles.pageHeader}><div><span>Vestuario</span><h1>Los del Miércoles</h1></div><button type="button">Filtros</button></header><section className={styles.teamRoom}>{names.concat(["Marcos", "Elena", "David", "Ana", "Joel", "Irene"]).map((name, index) => <button type="button" key={name}><span>{78 - (index % 7)}</span><b>{index % 5 === 0 ? "POR" : index % 3 === 0 ? "DEL" : "MC"}</b><strong>{name}</strong><small>{32 - index} PJ · {index % 6} goles</small></button>)}</section></main>;
}

function RefereeSurface() {
  return <main className={styles.standardPage}><header className={styles.pageHeader}><div><span>Perfil arbitral</span><h1>Laura Martín</h1></div><b>Disponible</b></header><div className={styles.referee}><section><div className={styles.refereeAvatar}>LM</div><strong>Árbitra verificada</strong><p>Barcelona · Fútbol 7 y fútbol sala</p><dl><div><dt>Partidos</dt><dd>42</dd></div><div><dt>Valoración</dt><dd>4,8</dd></div><div><dt>Respuesta</dt><dd>2 h</dd></div></dl></section><section><header><span>Disponibilidad</span><h2>Próximas fechas</h2></header>{["Mié 26 · 21:00", "Vie 28 · 20:30", "Dom 30 · 11:30"].map((date) => <button type="button" key={date}><strong>{date}</strong><span>Barcelona · 35 €</span></button>)}</section></div></main>;
}

export function OfficialUiV21Lab({ capture, initialPane, initialRole, initialState, initialSurface, initialTheme }: {
  capture: boolean;
  initialPane: string;
  initialRole: string;
  initialState: string;
  initialSurface: string;
  initialTheme: string;
}) {
  const [surface, setSurface] = useState<LabSurface>(() => validSurface(initialSurface));
  const pane = validPane(initialPane);
  const role = ["player", "admin", "owner"].includes(initialRole) ? initialRole : "admin";
  const theme = initialTheme === "light" ? "light" : "dark";
  useEffect(() => {
    const root = document.documentElement;
    const previousTheme = root.dataset.theme;
    root.dataset.theme = theme;
    return () => {
      if (previousTheme) root.dataset.theme = previousTheme;
      else delete root.dataset.theme;
    };
  }, [theme]);
  const selectSurface = (next: LabSurface) => {
    setSurface(next);
    updateLabUrl(next, next === "partido" ? pane : undefined);
  };
  const links = useMemo(() => ({
    equipo: "?surface=ranking",
    inicio: "?surface=inicio",
    mercado: "?surface=mercado",
    partido: "?surface=partido&pane=proximo",
    perfil: "?surface=avisos",
  }), []);
  const title = surfaces.find((item) => item.id === surface)?.label ?? "Inicio";
  return (
    <OfficialProductShellV2 active={shellTab(surface)} context={{ detail: `${role} · ${initialState}`, eyebrow: "Official UI V2.1 Lab", status: initialState === "offline" ? "Solo lectura" : "Visual", title }} links={links}>
      <div className={styles.lab} data-capture={capture ? "true" : "false"} data-lab-theme={theme} data-surface={surface}>
        <LabToolbar capture={capture} onSurface={selectSurface} surface={surface} theme={theme} />
        {surface === "inicio" ? <HomeSurface role={role} state={initialState} /> : null}
        {surface === "partido" ? <MatchSurface initialPane={pane} role={role} /> : null}
        {surface === "mercado" ? <MarketSurface role={role} /> : null}
        {surface === "ranking" ? <RankingSurface /> : null}
        {surface === "avisos" ? <NotificationsSurface /> : null}
        {surface === "carta" || surface === "escudo" ? <ObjectSurface kind={surface} /> : null}
        {surface === "equipo" ? <TeamSurface /> : null}
        {surface === "arbitro" ? <RefereeSurface /> : null}
      </div>
    </OfficialProductShellV2>
  );
}

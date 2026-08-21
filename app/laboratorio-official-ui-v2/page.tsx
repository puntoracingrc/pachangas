import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import {
  ActivityFeed,
  CompactList,
  GamePageHeader,
  GameTabs,
  MetricTile,
  PrimaryActionCard,
  ResponsiveActionBar,
  SecondaryActionCard,
  SectionHeader,
  StatusChip,
} from "../_components/official-ui-v2-primitives";
import { OFFICIAL_UI_V2_TOKENS } from "../_design-v2/official-ui-v2-contract";
import type { MobileAppTab } from "../mobile-app-nav";
import styles from "./official-ui-v2-lab.module.css";

export const metadata: Metadata = {
  title: "Official UI V2 Lab | Pachangas IQ",
  robots: { follow: false, index: false },
};

type LabSurface = "avisos" | "carta" | "comparativa" | "equipo" | "inicio" | "mercado" | "partido" | "ranking" | "tokens";
type MatchPane = "admin" | "alineacion" | "proximo" | "resultado";

const surfaces: Array<{ id: LabSurface; label: string }> = [
  { id: "inicio", label: "Inicio" },
  { id: "partido", label: "Partido" },
  { id: "mercado", label: "Mercado" },
  { id: "ranking", label: "Ranking" },
  { id: "avisos", label: "Avisos" },
  { id: "equipo", label: "Equipo" },
  { id: "carta", label: "Carta" },
  { id: "tokens", label: "Tokens" },
  { id: "comparativa", label: "Comparativa" },
];

const matchPanes: Array<{ id: MatchPane; label: string }> = [
  { id: "proximo", label: "Próximo" },
  { id: "alineacion", label: "Alineación" },
  { id: "resultado", label: "Resultado" },
  { id: "admin", label: "Admin" },
];

const players = ["Alberto", "Marta", "Sergio", "Nuria", "Dani", "Paula", "Iván", "Lucía", "Álex", "Carla"];

function value(value: string | string[] | undefined, fallback: string) {
  return Array.isArray(value) ? value[0] ?? fallback : value ?? fallback;
}

function surfaceTab(surface: LabSurface): MobileAppTab {
  if (surface === "partido") return "partido";
  if (surface === "mercado") return "mercado";
  if (surface === "ranking" || surface === "equipo") return "equipo";
  if (surface === "avisos" || surface === "carta") return "perfil";
  return "inicio";
}

function LabToolbar({ surface }: { surface: LabSurface }) {
  return (
    <nav className={styles.labToolbar} aria-label="Pantallas del laboratorio">
      <span>Laboratorio · solo visual</span>
      <div>{surfaces.map((item) => <Link aria-current={surface === item.id ? "page" : undefined} href={`?surface=${item.id}`} key={item.id}>{item.label}</Link>)}</div>
    </nav>
  );
}

function HomeView() {
  return (
    <div className={styles.pageStack}>
      <GamePageHeader
        actions={<><button type="button">Ver partido</button><button className={styles.accentButton} type="button">Confirmar asistencia</button></>}
        eyebrow="Vestuario"
        summary="La próxima acción, el partido y la actividad del equipo comparten una jerarquía clara."
        title="Los del Miércoles"
      />
      <section className={styles.metricGrid} aria-label="Estado del equipo">
        <MetricTile label="Próximo partido" value="Mié 21:00" />
        <MetricTile label="Confirmados" value="12 / 14" />
        <MetricTile label="Racha" value="3 victorias" />
        <MetricTile label="Avisos" value="2 nuevos" />
      </section>
      <div className={styles.homeGrid}>
        <PrimaryActionCard title="Próximo partido" action={<button className={styles.accentButton} type="button">Voy</button>}>
          <div className={styles.matchBillboard}><span>Fútbol 7</span><strong>Can Caralleu · 21:00</strong><small>Miércoles 26 de agosto · 2 plazas libres</small></div>
        </PrimaryActionCard>
        <SecondaryActionCard title="Actividad">
          <ActivityFeed><p><b>Marta</b> se ha apuntado al partido.</p><p>La alineación se ha actualizado.</p><p><b>Nuevo logro</b> pendiente de reclamar.</p></ActivityFeed>
        </SecondaryActionCard>
        <SecondaryActionCard title="Accesos rápidos">
          <div className={styles.quickGrid}><button type="button">Alineación</button><button type="button">Mercado</button><button type="button">Ranking</button><button type="button">Avisos</button></div>
        </SecondaryActionCard>
      </div>
    </div>
  );
}

function Pitch() {
  return (
    <div className={styles.pitch} aria-label="Campo de alineación">
      <span className={styles.centerLine} /><span className={styles.centerCircle} />
      {players.slice(0, 8).map((player, index) => (
        <button className={styles.playerToken} data-side={index < 4 ? "home" : "away"} style={{ left: `${12 + (index % 4) * 23}%`, top: `${index < 4 ? 22 : 68}%` }} type="button" key={player}>
          <b>{index % 4 === 0 ? "POR" : index % 3 === 0 ? "DEL" : "MC"}</b><span>{player}</span>
        </button>
      ))}
      <div className={styles.balance}><span>Equilibrio</span><strong>Equipo 1 +2</strong></div>
    </div>
  );
}

function MatchView({ pane }: { pane: MatchPane }) {
  const items = matchPanes.map((item) => ({ href: `?surface=partido&pane=${item.id}`, id: item.id, label: item.label }));
  return (
    <div className={styles.matchLayout}>
      <GameTabs active={pane} items={items} />
      <section className={styles.matchWorkspace}>
        <GamePageHeader eyebrow="Partido activo · Fútbol 7" title={pane === "proximo" ? "Miércoles en Can Caralleu" : matchPanes.find((item) => item.id === pane)?.label ?? "Partido"} actions={<StatusChip tone="success">Revisión 18</StatusChip>} />
        {pane === "alineacion" ? (
          <div className={styles.lineupLayout}><Pitch /><aside className={styles.bench}><SectionHeader eyebrow="Banquillo" title="Reservas" /><CompactList label="Reservas">{players.slice(8).map((player) => <button type="button" key={player}><b>RES</b><span>{player}</span></button>)}</CompactList><ResponsiveActionBar className={styles.benchActions}><button type="button">Aleatorio</button><button className={styles.accentButton} type="button">Cerrar alineación</button></ResponsiveActionBar></aside></div>
        ) : pane === "resultado" ? (
          <div className={styles.resultLayout}><div className={styles.scoreboard}><span>Equipo 1</span><strong>4 <i>:</i> 3</strong><span>Equipo 2</span><small>Final pendiente de confirmar</small></div><SecondaryActionCard title="Goleadores"><CompactList label="Goleadores">{players.slice(0, 5).map((player, index) => <div className={styles.scorer} key={player}><span>{player}</span><b>{index < 2 ? 2 : 1}</b><button type="button">−</button><button type="button">+</button></div>)}</CompactList></SecondaryActionCard></div>
        ) : pane === "admin" ? (
          <div className={styles.adminGrid}><PrimaryActionCard title="Estado del partido"><p>Alineación abierta · 12 confirmados · mercado cerrado.</p><ResponsiveActionBar><button type="button">Cerrar alineación</button><button className={styles.accentButton} type="button">Guardar</button></ResponsiveActionBar></PrimaryActionCard><SecondaryActionCard title="Operaciones"><div className={styles.adminActions}><button type="button">Invitar jugador</button><button type="button">Abrir al mercado</button><button type="button">Editar partido</button><button type="button">Eliminar partido</button></div></SecondaryActionCard></div>
        ) : (
          <div className={styles.nextLayout}><PrimaryActionCard title="Tu asistencia" action={<ResponsiveActionBar><button type="button">No voy</button><button type="button">Duda</button><button className={styles.accentButton} type="button">Voy</button></ResponsiveActionBar>}><div className={styles.matchBillboard}><span>Próximo partido</span><strong>Miércoles 26 · 21:00</strong><small>Can Caralleu · 17 °C · sin lluvia</small></div></PrimaryActionCard><SecondaryActionCard title="Convocatoria"><div className={styles.rosterColumns}><CompactList label="Equipo 1">{players.slice(0, 5).map((player) => <p key={player}><b>✓</b>{player}</p>)}</CompactList><CompactList label="Equipo 2">{players.slice(5).map((player) => <p key={player}><b>✓</b>{player}</p>)}</CompactList></div></SecondaryActionCard></div>
        )}
      </section>
    </div>
  );
}

function MarketView() {
  return <div className={styles.pageStack}><GamePageHeader eyebrow="Mercado" title="Encontrar partido o jugador" actions={<StatusChip tone="info">2 plazas del próximo partido</StatusChip>} /><div className={styles.filters}><input aria-label="Zona" placeholder="Barcelona" /><select aria-label="Modalidad" defaultValue="f7"><option value="f7">Fútbol 7</option></select><select aria-label="Posición" defaultValue="all"><option value="all">Todas las posiciones</option></select><button className={styles.accentButton} type="button">Buscar</button></div><section className={styles.marketCards}>{players.slice(0, 6).map((player, index) => <article key={player}><div className={styles.miniCard}><b>{76 + index}</b><span>{index % 2 ? "MC" : "DEL"}</span><strong>{player}</strong></div><div><StatusChip tone={index < 2 ? "success" : "neutral"}>{index < 2 ? "Disponible hoy" : "Fin de semana"}</StatusChip><h2>{player}</h2><p>Barcelona · Fútbol 7 · nivel verificado</p><button type="button">Ver ficha</button></div></article>)}</section></div>;
}

function RankingView() {
  return <div className={styles.pageStack}><GamePageHeader eyebrow="Barcelona · 2026/27" title="Ranking provincial" actions={<StatusChip tone="warning">Posición provisional</StatusChip>} /><section className={styles.rankingHero}><div><span>Tu posición</span><strong>#18</strong><small>Season Score 712</small></div><p>Necesitas 2 rivales lógicos más para optar al Top 10 territorial.</p></section><section className={styles.rankingTable}><header><span>Pos.</span><span>Equipo</span><span>PJ</span><span>Season Score</span></header>{["Furia Vallès", "Atlètic Nord", "Los del Miércoles", "Barrio Sur", "Diagonal FC", "Raval United"].map((team, index) => <div data-own={index === 2 ? "true" : "false"} key={team}><b>{index + 1}</b><strong>{team}</strong><span>{16 - index}</span><output>{824 - index * 31}</output></div>)}</section></div>;
}

function NotificationsView() {
  return <div className={styles.pageStack}><GamePageHeader eyebrow="Centro de avisos" title="Avisos" actions={<button type="button">Marcar todo leído</button>} /><div className={styles.notificationLayout}><nav><button className={styles.activeFilter} type="button">Todos · 4</button><button type="button">Partidos</button><button type="button">Mercado</button><button type="button">Logros</button><button type="button">Seguridad</button></nav><section>{["Marta se ha apuntado al partido", "Nueva solicitud desde Mercado", "Alineación actualizada", "Nuevo logro desbloqueado"].map((title, index) => <article key={title}><StatusChip tone={index === 1 ? "warning" : index === 3 ? "success" : "info"}>{index === 1 ? "Acción necesaria" : "Nuevo"}</StatusChip><div><strong>{title}</strong><p>{index === 1 ? "Revisa la ficha y acepta o rechaza la solicitud." : "Estado confirmado por el servidor central."}</p></div><button type="button">Abrir</button></article>)}</section></div></div>;
}

function TeamView() {
  return <div className={styles.objectLayout}><section className={styles.objectStage}><div className={styles.shield}><Image src="/icon-512.png" alt="Escudo de Los del Miércoles" width={512} height={512} /></div><span>Escudo oficial</span><strong>Los del Miércoles</strong><small>Revisión confirmada 7</small></section><section className={styles.objectControls}><GamePageHeader eyebrow="Identidad" title="Personalizar equipo" /><div className={styles.objectTabs}>{["Forma", "Borde", "Fondo", "Símbolo", "Efecto"].map((item, index) => <button className={index === 0 ? styles.activeObjectTab : ""} key={item} type="button">{item}</button>)}</div><div className={styles.choiceGrid}>{["Clásico", "Moderno", "Angular", "Vintage", "Elite", "Compacto"].map((item) => <button type="button" key={item}><span className={styles.choiceShape} />{item}</button>)}</div><ResponsiveActionBar><button type="button">Deshacer</button><button className={styles.accentButton} type="button">Guardar escudo</button></ResponsiveActionBar></section></div>;
}

function CardView() {
  return <div className={styles.objectLayout}><section className={styles.objectStage}><Image className={styles.playerCardImage} src="/lab/player-card-preview.jpg" alt="Vista previa de la carta de jugador" width={800} height={1000} /><span>Carta oficial</span><strong>Alberto · GRL 78</strong><small>6 piezas equipadas</small></section><section className={styles.objectControls}><GamePageHeader eyebrow="Colección personal" title="Personalizar carta" /><div className={styles.objectTabs}>{["Marco", "Fondo", "Nombre", "Efecto", "Título", "Logro"].map((item, index) => <button className={index === 0 ? styles.activeObjectTab : ""} key={item} type="button">{item}</button>)}</div><div className={styles.choiceGrid}>{["Original", "Plata", "Oro", "Esmeralda", "Noche", "Copa"].map((item, index) => <button type="button" key={item}><span className={styles.cardSwatch} data-index={index} />{item}</button>)}</div><ResponsiveActionBar><button type="button">Deshacer</button><button className={styles.accentButton} type="button">Guardar ficha</button></ResponsiveActionBar></section></div>;
}

function TokensView() {
  const colors = Object.entries(OFFICIAL_UI_V2_TOKENS.color);
  return <div className={styles.pageStack}><GamePageHeader eyebrow="Contrato visual" title="Tokens Official UI V2" summary="Valores extraídos de Demo World y expresados como roles semánticos." /><section className={styles.tokenGrid}>{colors.map(([name, token]) => <article key={name}><span style={{ background: token }} /><strong>{name}</strong><code>{token}</code></article>)}</section><section className={styles.stateGrid}><PrimaryActionCard title="Estado vacío"><p>No hay partidos programados. La acción disponible permanece clara.</p><button type="button">Crear partido</button></PrimaryActionCard><SecondaryActionCard title="Sin conexión"><StatusChip tone="warning">Solo lectura</StatusChip><p>Los datos guardados siguen disponibles. Ninguna acción aparece como confirmada.</p></SecondaryActionCard><SecondaryActionCard title="Permiso insuficiente"><StatusChip tone="danger">Acceso restringido</StatusChip><p>Esta operación corresponde a un administrador del equipo.</p></SecondaryActionCard></section></div>;
}

function ComparisonView() {
  return <div className={styles.pageStack}><GamePageHeader eyebrow="Revisión visual" title="Before / Demo / After" summary="Comparación de composición completa, no solo de colores o tarjetas aisladas." /><section className={styles.comparisonGrid}>{[{ label: "A · Oficial anterior", variant: "before" }, { label: "B · Demo World", variant: "demo" }, { label: "C · Official UI V2", variant: "after" }].map((item) => <article data-variant={item.variant} key={item.variant}><header>{item.label}</header><div className={styles.miniScreen}><nav><b>IQ</b><span>Inicio</span><span>Partido</span><span>Equipo</span></nav><main><h2>Próximo partido</h2><section><strong>Miércoles · 21:00</strong><p>12 confirmados · Fútbol 7</p></section><div><span /><span /><span /></div></main></div></article>)}</section></div>;
}

export default async function OfficialUiV2LabPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const query = await searchParams;
  const requestedSurface = value(query.surface, "inicio") as LabSurface;
  const surface = surfaces.some((item) => item.id === requestedSurface) ? requestedSurface : "inicio";
  const requestedPane = value(query.pane, "proximo") as MatchPane;
  const pane = matchPanes.some((item) => item.id === requestedPane) ? requestedPane : "proximo";
  const capture = value(query.capture, "0") === "1";
  const active = surfaceTab(surface);
  const titles: Record<LabSurface, string> = { avisos: "Avisos", carta: "Mi carta", comparativa: "Comparativa", equipo: "Identidad", inicio: "Los del Miércoles", mercado: "Mercado", partido: "Partido activo", ranking: "Ranking", tokens: "Sistema visual" };
  const labLinks = { equipo: "?surface=ranking", inicio: "?surface=inicio", mercado: "?surface=mercado", partido: "?surface=partido&pane=proximo", perfil: "?surface=avisos" };

  return (
    <OfficialProductShellV2 active={active} context={{ detail: "Fixtures visuales · sin Supabase", eyebrow: "Official UI V2 Lab", status: "Solo visual", title: titles[surface] }} links={labLinks}>
      <main className={styles.lab} data-capture={capture ? "true" : "false"} data-lab-surface={surface}>
        <LabToolbar surface={surface} />
        <div className={styles.labContent}>
          {surface === "inicio" ? <HomeView /> : surface === "partido" ? <MatchView pane={pane} /> : surface === "mercado" ? <MarketView /> : surface === "ranking" ? <RankingView /> : surface === "avisos" ? <NotificationsView /> : surface === "equipo" ? <TeamView /> : surface === "carta" ? <CardView /> : surface === "tokens" ? <TokensView /> : <ComparisonView />}
        </div>
      </main>
    </OfficialProductShellV2>
  );
}

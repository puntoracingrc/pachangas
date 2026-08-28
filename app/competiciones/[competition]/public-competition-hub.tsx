"use client";

import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { clientWriteFetch } from "../../pwa-client-bridge";
import { supabase } from "../../supabaseClient";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { GamePageHeader, MetricTile, ProductFeedback, SectionHeader, StatusChip } from "../../_components/official-ui-v2-primitives";
import {
  publicCompetitionArray,
  publicCompetitionBoolean,
  publicCompetitionNumber,
  publicCompetitionRealtimeTable,
  publicCompetitionRecord,
  publicCompetitionSportLabel,
  publicCompetitionStateLabel,
  publicCompetitionText,
  publicCompetitionTypeLabel,
  type PublicCompetitionAction,
  type PublicCompetitionJson,
} from "../../public-competition-contract";
import styles from "./public-competition-hub.module.css";

export type PublicCompetitionHubTab = "summary" | "format" | "teams" | "calendar" | "results" | "standings" | "bracket" | "rules" | "referees" | "registration";
type Tab = PublicCompetitionHubTab;
const cachePrefix = "pachangas-public-competition-v1";

function cacheKey(slug: string, entity = "hub") { return `${cachePrefix}:${slug}:${entity}`; }
function readCache(slug: string, entity = "hub") {
  try { return publicCompetitionRecord(JSON.parse(window.localStorage.getItem(cacheKey(slug, entity)) ?? "null").data); } catch { return {}; }
}
function writeCache(slug: string, entity: string, data: unknown) {
  try { window.localStorage.setItem(cacheKey(slug, entity), JSON.stringify({ data, storedAt: Date.now() })); } catch {
    // Derived public cache only. PostgreSQL remains authoritative.
  }
}
function dateLabel(value: unknown, includeTime = false) {
  const source = publicCompetitionText(value);
  if (!source) return "Por confirmar";
  return new Intl.DateTimeFormat("es-ES", includeTime
    ? { day: "2-digit", hour: "2-digit", minute: "2-digit", month: "short", timeZone: "Europe/Madrid" }
    : { day: "2-digit", month: "short", year: "numeric", timeZone: "Europe/Madrid" }).format(new Date(source));
}
function teamName(value: unknown, fallback = "Por confirmar") { return publicCompetitionText(publicCompetitionRecord(value).name) || fallback; }

function RegistrationPanel({
  accessToken, busy, competitionId, onCommand, publication, requests, teams,
}: {
  accessToken: string;
  busy: boolean;
  competitionId: string;
  onCommand: (action: PublicCompetitionAction, aggregateId: string, revision: number, payload: PublicCompetitionJson) => Promise<void>;
  publication: PublicCompetitionJson;
  requests: PublicCompetitionJson[];
  teams: PublicCompetitionJson[];
}) {
  const [teamId, setTeamId] = useState("");
  const [message, setMessage] = useState("");
  const current = requests.find((request) => publicCompetitionText(request.competitionId) === competitionId
    && ["submitted", "under_review", "waitlisted", "accepted"].includes(publicCompetitionText(request.status)));
  const selectedTeamId = teamId || publicCompetitionText(teams[0]?.id);
  if (!accessToken) return <section className={styles.registrationState}><strong>Inicia sesión para solicitar plaza con tu equipo.</strong><Link href="/">Iniciar sesión</Link></section>;
  if (current) return <section className={styles.registrationState}>
    <StatusChip tone={publicCompetitionText(current.status) === "accepted" ? "success" : "warning"}>{publicCompetitionText(current.status).replaceAll("_", " ")}</StatusChip>
    <h3>{teamName(current.team, "Tu equipo")}</h3>
    {publicCompetitionText(current.status) === "waitlisted" ? <p>Posición {publicCompetitionNumber(current.waitlistPosition)} en la lista de espera.</p> : null}
    {publicCompetitionText(current.publicReason) ? <p>{publicCompetitionText(current.publicReason)}</p> : null}
    {["submitted", "under_review", "waitlisted"].includes(publicCompetitionText(current.status)) ? <button type="button" disabled={busy} onClick={() => void onCommand("registration.withdraw", publicCompetitionText(current.id), publicCompetitionNumber(current.revision), { reason: "Retirada por el Team owner" })}>Retirar solicitud</button> : null}
  </section>;
  if (!teams.length) return <section className={styles.registrationState}><strong>Necesitas ser owner de un equipo para solicitar inscripción.</strong><Link href="/?mobile=perfil">Crear o gestionar equipo</Link></section>;
  return <form className={styles.registrationForm} onSubmit={(event) => {
    event.preventDefault();
    void onCommand("registration.submit", publicCompetitionText(publication.id), publicCompetitionNumber(publication.revision), { message, reason: "Solicitud pública de inscripción", teamId: selectedTeamId });
  }}>
    <label>Equipo<select value={selectedTeamId} onChange={(event) => setTeamId(event.target.value)}>{teams.map((team) => <option key={publicCompetitionText(team.id)} value={publicCompetitionText(team.id)}>{publicCompetitionText(team.name)}</option>)}</select></label>
    <label>Mensaje al organizador<textarea maxLength={1000} rows={3} value={message} onChange={(event) => setMessage(event.target.value)} placeholder="Presenta brevemente a tu equipo" /></label>
    <button type="submit" disabled={busy || !selectedTeamId}>{busy ? "Esperando confirmación..." : "Solicitar inscripción"}</button>
  </form>;
}

function OrganizerQueue({ busy, items, onCommand }: {
  busy: boolean;
  items: PublicCompetitionJson[];
  onCommand: (action: PublicCompetitionAction, aggregateId: string, revision: number, payload: PublicCompetitionJson) => Promise<void>;
}) {
  if (!items.length) return null;
  return <section className={styles.queue}><SectionHeader eyebrow="Organización" title="Solicitudes" /><div>{items.map((request) => <article key={publicCompetitionText(request.id)}><span><strong>{teamName(request.team)}</strong><small>{publicCompetitionText(request.status).replaceAll("_", " ")}{request.waitlistPosition ? ` · #${publicCompetitionNumber(request.waitlistPosition)}` : ""}</small></span><div>
    {["submitted", "under_review"].includes(publicCompetitionText(request.status)) ? <button type="button" disabled={busy} onClick={() => void onCommand("registration.accept", publicCompetitionText(request.id), publicCompetitionNumber(request.revision), { publicReason: "Inscripción aceptada.", reason: "Aceptada por organización" })}>Aceptar</button> : null}
    {["submitted", "under_review"].includes(publicCompetitionText(request.status)) ? <button type="button" disabled={busy} onClick={() => void onCommand("registration.waitlist", publicCompetitionText(request.id), publicCompetitionNumber(request.revision), { publicReason: "Solicitud en lista de espera.", reason: "Lista de espera" })}>Espera</button> : null}
    {["submitted", "under_review", "waitlisted"].includes(publicCompetitionText(request.status)) ? <button type="button" disabled={busy} onClick={() => void onCommand("registration.reject", publicCompetitionText(request.id), publicCompetitionNumber(request.revision), { publicReason: "La solicitud no ha sido aceptada en esta edición.", reason: "Rechazada por organización" })}>Rechazar</button> : null}
  </div></article>)}</div></section>;
}

export function PublicCompetitionHub({
  embedded = false,
  embeddedAuthenticated = false,
  initialQueue = [],
  initialRelated = {},
  initialRequests = [],
  initialSnapshot,
  initialTab = "summary",
  initialTeams = [],
  slug,
}: {
  embedded?: boolean;
  embeddedAuthenticated?: boolean;
  initialQueue?: PublicCompetitionJson[];
  initialRelated?: Record<string, PublicCompetitionJson>;
  initialRequests?: PublicCompetitionJson[];
  initialSnapshot: Record<string, unknown> | null;
  initialTab?: PublicCompetitionHubTab;
  initialTeams?: PublicCompetitionJson[];
  slug: string;
}) {
  const [snapshot, setSnapshot] = useState<Record<string, unknown> | null>(initialSnapshot);
  const [activeTab, setActiveTab] = useState<Tab>(initialTab);
  const [related, setRelated] = useState<Record<string, PublicCompetitionJson>>(initialRelated);
  const [accessToken, setAccessToken] = useState(embeddedAuthenticated ? "demo-read-only" : "");
  const [teams, setTeams] = useState<PublicCompetitionJson[]>(initialTeams);
  const [requests, setRequests] = useState<PublicCompetitionJson[]>(initialRequests);
  const [queue, setQueue] = useState<PublicCompetitionJson[]>(initialQueue);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);
  const competition = publicCompetitionRecord(snapshot?.competition);
  const publication = publicCompetitionRecord(snapshot?.publication);
  const registration = publicCompetitionRecord(snapshot?.registration);
  const organizer = publicCompetitionRecord(snapshot?.organizer);
  const edition = publicCompetitionRecord(snapshot?.edition);
  const category = publicCompetitionRecord(snapshot?.category);
  const sections = publicCompetitionRecord(snapshot?.sections);
  const competitionId = publicCompetitionText(competition.id);

  const loadHub = useCallback(async (source: "network" | "realtime" = "network", sequence = 0) => {
    try {
      const suffix = source === "realtime" ? `?sequence=${sequence || Date.now()}` : "";
      const response = await fetch(`/api/competitions/public/${encodeURIComponent(slug)}${suffix}`, { cache: source === "realtime" ? "reload" : "default" });
      const body = publicCompetitionRecord(await response.json());
      if (!response.ok) throw new Error(publicCompetitionText(body.error) || "Competición no disponible.");
      setSnapshot(body); writeCache(slug, "hub", body);
      if (source === "realtime") setMessage("Competición actualizada desde el servidor.");
    } catch (error) {
      const cached = readCache(slug, "hub");
      if (Object.keys(cached).length) { setSnapshot(cached); setMessage("Sin conexión. Mostrando la última versión guardada."); }
      else setMessage(error instanceof Error ? error.message : "Competición no disponible.");
    }
  }, [slug]);

  const loadAuthenticated = useCallback(async (token: string, targetCompetitionId: string) => {
    const headers = { Authorization: `Bearer ${token}` };
    const [teamResponse, requestResponse, queueResponse] = await Promise.all([
      fetch("/api/competitions/public/teams", { cache: "no-store", headers }),
      fetch("/api/competitions/public/my", { cache: "no-store", headers }),
      targetCompetitionId ? fetch(`/api/competitions/public/queue/${targetCompetitionId}`, { cache: "no-store", headers }) : Promise.resolve(null),
    ]);
    if (teamResponse.ok) setTeams(publicCompetitionArray(publicCompetitionRecord(await teamResponse.json()).items));
    if (requestResponse.ok) setRequests(publicCompetitionArray(publicCompetitionRecord(await requestResponse.json()).items));
    if (queueResponse?.ok) setQueue(publicCompetitionArray(publicCompetitionRecord(await queueResponse.json()).items));
    else setQueue([]);
  }, []);

  useEffect(() => {
    if (embedded) return;
    if (initialSnapshot) writeCache(slug, "hub", initialSnapshot);
    else {
      const initialLoad = window.setTimeout(() => void loadHub(), 0);
      return () => window.clearTimeout(initialLoad);
    }
  }, [embedded, initialSnapshot, loadHub, slug]);

  useEffect(() => {
    if (embedded) return;
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    const start = async () => {
      const session = (await supabase?.auth.getSession())?.data.session;
      if (!active || !session) return;
      setAccessToken(session.access_token);
      await loadAuthenticated(session.access_token, competitionId);
      if (!supabase) return;
      const reconcile = (sequence = 0) => {
        if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
        realtimeTimer.current = window.setTimeout(() => {
          void loadHub("realtime", sequence);
          void loadAuthenticated(session.access_token, competitionId);
        }, 120);
      };
      channel = supabase.channel(`public-competition:${competitionId}:${session.user.id}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: publicCompetitionRealtimeTable }, (payload) => {
          const row = publicCompetitionRecord(payload.new);
          if (publicCompetitionText(row.competition_id) === competitionId || publicCompetitionText(row.entity_type) === "public_competition_flags") reconcile(publicCompetitionNumber(row.server_sequence));
        })
        .subscribe((state) => { if (state === "SUBSCRIBED") reconcile(); });
      const online = () => reconcile();
      window.addEventListener("online", online);
      return () => window.removeEventListener("online", online);
    };
    let cleanup: (() => void) | undefined;
    void start().then((value) => { cleanup = value; });
    return () => { active = false; cleanup?.(); if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current); if (channel && supabase) void supabase.removeChannel(channel); };
  }, [competitionId, embedded, loadAuthenticated, loadHub]);

  async function loadSection(tab: Tab) {
    setActiveTab(tab);
    if (!["calendar", "results", "standings", "bracket", "referees"].includes(tab) || related[tab]) return;
    const entity = tab === "results" || tab === "referees" ? "calendar" : tab;
    if (related[entity]) return;
    if (embedded) {
      setMessage("Esta sección no forma parte del snapshot demo seleccionado.");
      return;
    }
    try {
      const response = await fetch(`/api/competitions/public/${encodeURIComponent(slug)}/${entity}`);
      const body = publicCompetitionRecord(await response.json());
      if (!response.ok) throw new Error(publicCompetitionText(body.error) || "Sección no disponible.");
      setRelated((current) => ({ ...current, [entity]: body })); writeCache(slug, entity, body);
    } catch (error) {
      const cached = readCache(slug, entity);
      if (Object.keys(cached).length) { setRelated((current) => ({ ...current, [entity]: cached })); setMessage("Sin conexión. Mostrando la última sección guardada."); }
      else setMessage(error instanceof Error ? error.message : "Sección no disponible.");
    }
  }

  async function command(action: PublicCompetitionAction, aggregateId: string, expectedRevision: number, payload: PublicCompetitionJson) {
    if (embedded) {
      setMessage("Mundo Demo de solo lectura. No se ha enviado ninguna operación.");
      return;
    }
    if (!accessToken) { setMessage("Inicia sesión para completar esta acción."); return; }
    if (!navigator.onLine) { setMessage("Sin conexión. La acción no se ha enviado ni confirmado."); return; }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true); setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:public-competition-command", "/api/competitions/public/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = publicCompetitionRecord(await response.json());
      if (!response.ok) throw new Error(publicCompetitionText(body.message) || "Operación no confirmada.");
      const canonical = publicCompetitionRecord(body.canonical);
      pending.current = null;
      setMessage("Cambio confirmado por el servidor.");
      await Promise.all([loadHub("realtime", publicCompetitionNumber(canonical.serverSequence)), loadAuthenticated(accessToken, competitionId)]);
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail) ? "El estado cambió. Se ha recuperado la versión oficial." : detail);
      if (/STALE_REVISION|revision/i.test(detail)) await Promise.all([loadHub("realtime"), loadAuthenticated(accessToken, competitionId)]);
    } finally { setBusy(false); }
  }

  const tabs = useMemo(() => {
    const values: Array<{ id: Tab; label: string }> = [{ id: "summary", label: "Resumen" }, { id: "format", label: "Formato" }];
    if (publicCompetitionBoolean(sections.teams)) values.push({ id: "teams", label: "Equipos" });
    if (publicCompetitionBoolean(sections.calendar)) values.push({ id: "calendar", label: "Calendario" });
    if (publicCompetitionBoolean(sections.results)) values.push({ id: "results", label: "Resultados" });
    if (publicCompetitionBoolean(sections.standings)) values.push({ id: "standings", label: "Clasificación" });
    if (publicCompetitionBoolean(sections.bracket) && snapshot?.bracket) values.push({ id: "bracket", label: "Cuadro" });
    values.push({ id: "rules", label: "Reglamento" });
    if (publicCompetitionBoolean(sections.referees)) values.push({ id: "referees", label: "Árbitros" });
    if (publicCompetitionText(registration.mode) !== "CLOSED") values.push({ id: "registration", label: "Inscripción" });
    return values;
  }, [registration.mode, sections, snapshot?.bracket]);

  if (!snapshot) {
    const unavailable = <div className={styles.page}><section className={styles.unavailable}><h1>Esta competición no es pública</h1><p>Puede ser privada, estar pendiente de revisión o haber sido suspendida.</p><Link href="/competiciones">Volver al directorio</Link></section></div>;
    return embedded ? unavailable : <OfficialProductShellV2 active="mercado" context={{ eyebrow: "Competiciones", status: "No disponible", title: "Competición" }}>{unavailable}</OfficialProductShellV2>;
  }

  const name = publicCompetitionText(competition.name) || "Competición";
  const image = publicCompetitionText(competition.image);
  const shellEyebrow = `${publicCompetitionTypeLabel(competition.type)} ${publicCompetitionText(competition.type) === "TOURNAMENT" ? "público" : "pública"}`;
  const calendarItems = publicCompetitionArray(related.calendar?.items);
  const standingsGroups = publicCompetitionArray(related.standings?.items ?? snapshot.standings);
  const bracket = publicCompetitionRecord(related.bracket ?? snapshot.bracket);
  const bracketRounds = publicCompetitionArray(bracket.rounds ?? publicCompetitionRecord(bracket.bracket).rounds);
  const publicTeams = publicCompetitionArray(snapshot.teams);
  const referees = Array.from(new Map(calendarItems.map((fixture) => publicCompetitionRecord(fixture.referee)).filter((referee) => publicCompetitionText(referee.displayName)).map((referee) => [publicCompetitionText(referee.assignmentId) || publicCompetitionText(referee.slug), referee])).values());

  const content = <div className={styles.page} data-mobile-tab="mercado" data-product-renderer="public-competition-hub">
      <GamePageHeader actions={<Link href="/competiciones">Directorio</Link>} eyebrow={`${publicCompetitionTypeLabel(competition.type)} · ${publicCompetitionSportLabel(category.sportFormat)}`} summary="Información pública confirmada por el servidor central." title={name} />
      {message ? <ProductFeedback tone={/confirmado|actualizada/i.test(message) ? "success" : /Sin conexión/i.test(message) ? "warning" : "info"}>{message}</ProductFeedback> : null}
      <section className={styles.hero}>
        <div className={styles.heroImage}>{image ? <Image src={image} alt="" fill sizes="(max-width: 700px) 100vw, 45vw" unoptimized priority /> : <span>{name.slice(0, 2).toUpperCase()}</span>}</div>
        <div className={styles.heroCopy}><div className={styles.chips}><StatusChip tone="info">{publicCompetitionTypeLabel(competition.type)}</StatusChip><StatusChip tone="success">{publicCompetitionStateLabel(competition.publicState)}</StatusChip>{publicCompetitionText(competition.badge) ? <StatusChip tone="warning">{publicCompetitionText(competition.badge)}</StatusChip> : null}</div><h2>{name}</h2><p>{publicCompetitionText(competition.description) || "Competición organizada en Pachangas IQ."}</p><strong>{publicCompetitionText(organizer.name)} · {publicCompetitionText(competition.municipality) || publicCompetitionText(competition.generalArea)}</strong></div>
        <div className={styles.heroMetrics}><MetricTile label="Equipos" value={publicCompetitionNumber(registration.teamCount)} /><MetricTile label="Plazas" value={publicCompetitionNumber(registration.availablePlaces)} /><MetricTile label="Inicio" value={dateLabel(competition.startsAt)} /></div>
      </section>
      <nav className={styles.tabs} aria-label="Secciones de la competición">{tabs.map((tab) => <button type="button" key={tab.id} aria-current={activeTab === tab.id ? "page" : undefined} onClick={() => void loadSection(tab.id)}>{tab.label}</button>)}</nav>

      {activeTab === "summary" ? <section className={styles.summary}><div><SectionHeader eyebrow="Competición" title="Resumen" /><dl><div><dt>Organizador</dt><dd>{publicCompetitionText(organizer.name)}</dd></div><div><dt>Zona</dt><dd>{publicCompetitionText(competition.municipality) || publicCompetitionText(competition.generalArea) || "Por confirmar"}</dd></div><div><dt>Fechas</dt><dd>{dateLabel(competition.startsAt)} – {dateLabel(competition.endsAt)}</dd></div><div><dt>Edición</dt><dd>{publicCompetitionText(edition.name)}</dd></div></dl></div><div><SectionHeader eyebrow="Inscripción" title={publicCompetitionText(registration.state).replaceAll("_", " ")} /><p>{publicCompetitionNumber(registration.availablePlaces) > 0 ? `${publicCompetitionNumber(registration.availablePlaces)} plazas disponibles.` : publicCompetitionNumber(registration.waitlistCount) > 0 ? "Lista de espera activa." : "Sin plazas disponibles."}</p>{publicCompetitionText(registration.closesAt) ? <small>Cierra {dateLabel(registration.closesAt, true)}</small> : null}<button type="button" onClick={() => void loadSection("registration")}>Ver inscripción</button></div></section> : null}
      {activeTab === "format" ? <section className={styles.detailBand}><SectionHeader eyebrow="Reglas de juego" title={publicCompetitionText(competition.format) || publicCompetitionTypeLabel(competition.type)} /><div className={styles.factGrid}><MetricTile label="Modalidad" value={publicCompetitionSportLabel(category.sportFormat)} /><MetricTile label="Categoría" value={publicCompetitionText(category.name)} /><MetricTile label="Temporada" value={publicCompetitionText(edition.seasonLabel)} /><MetricTile label="Capacidad" value={publicCompetitionNumber(registration.teamCapacity) || "Abierta"} /></div></section> : null}
      {activeTab === "teams" ? <section className={styles.detailBand}><SectionHeader eyebrow={`${publicTeams.length} participantes`} title="Equipos" /><div className={styles.teamGrid}>{publicTeams.map((team) => <article key={publicCompetitionText(team.entryId)}><span>{publicCompetitionText(team.name).slice(0, 2).toUpperCase()}</span><div><strong>{publicCompetitionText(team.name)}</strong><small>{publicCompetitionText(team.teamCode)}</small></div></article>)}</div></section> : null}
      {activeTab === "calendar" || activeTab === "results" ? <section className={styles.detailBand}><SectionHeader eyebrow={activeTab === "results" ? "Decisiones oficiales" : `${publicCompetitionNumber(related.calendar?.total)} partidos`} title={activeTab === "results" ? "Resultados" : "Calendario"} /><div className={styles.fixtureList}>{calendarItems.filter((fixture) => activeTab !== "results" || publicCompetitionText(publicCompetitionRecord(fixture.result).status) === "OFFICIAL").map((fixture) => { const result = publicCompetitionRecord(fixture.result); const round = publicCompetitionRecord(fixture.round); return <article key={publicCompetitionText(fixture.contextId)}><div><small>{publicCompetitionText(round.name) || `Jornada ${publicCompetitionNumber(round.number) || "-"}`}</small><strong>{dateLabel(fixture.scheduledStart, true)}</strong></div><div className={styles.score}><span>{teamName(fixture.home)}</span><b>{publicCompetitionText(result.status) === "OFFICIAL" ? `${publicCompetitionNumber(result.scoreHome)} – ${publicCompetitionNumber(result.scoreAway)}` : "Pendiente"}</b><span>{teamName(fixture.away)}</span></div><small>{publicCompetitionText(publicCompetitionRecord(fixture.venue).label) || publicCompetitionText(fixture.status).replaceAll("_", " ")}</small></article>; })}</div></section> : null}
      {activeTab === "standings" ? <section className={styles.detailBand}><SectionHeader eyebrow="Snapshot canónico" title="Clasificación" />{standingsGroups.map((group, index) => <div className={styles.tableWrap} key={publicCompetitionText(group.snapshotId) || String(index)}><table><thead><tr><th>Pos.</th><th>Equipo</th><th>PJ</th><th>G</th><th>E</th><th>P</th><th>DG</th><th>Pts</th></tr></thead><tbody>{publicCompetitionArray(group.rows).map((row) => <tr key={publicCompetitionText(row.entryId)}><td>{publicCompetitionNumber(row.position)}</td><td>{teamName(row.team)}</td><td>{publicCompetitionNumber(row.played)}</td><td>{publicCompetitionNumber(row.wins)}</td><td>{publicCompetitionNumber(row.draws)}</td><td>{publicCompetitionNumber(row.losses)}</td><td>{publicCompetitionNumber(row.goalDifference)}</td><td><strong>{publicCompetitionNumber(row.points)}</strong></td></tr>)}</tbody></table></div>)}</section> : null}
      {activeTab === "bracket" ? <section className={styles.detailBand}><SectionHeader eyebrow="Cuadro publicado" title="Eliminatorias" /><div className={styles.bracket}>{bracketRounds.map((round, index) => <section key={publicCompetitionText(round.id) || String(index)}><h3>{publicCompetitionText(round.name) || `Ronda ${index + 1}`}</h3>{publicCompetitionArray(round.nodes).map((node) => <article key={publicCompetitionText(node.id)}><span>{teamName(node.home)}</span><b>{publicCompetitionText(publicCompetitionRecord(node.result).status) === "OFFICIAL" ? `${publicCompetitionNumber(publicCompetitionRecord(node.result).scoreHome)} – ${publicCompetitionNumber(publicCompetitionRecord(node.result).scoreAway)}` : "vs"}</b><span>{teamName(node.away)}</span></article>)}</section>)}</div></section> : null}
      {activeTab === "rules" ? <section className={styles.detailBand}><SectionHeader eyebrow="Reglamento resumido" title="Reglamento" /><p className={styles.rules}>{publicCompetitionText(competition.rulesSummary) || "El reglamento completo está disponible para los participantes aceptados. La autoridad aplica la RuleRevision vigente de esta edición."}</p><p className={styles.privateNote}>La disciplina y las decisiones internas permanecen privadas para los participantes autorizados.</p></section> : null}
      {activeTab === "referees" ? <section className={styles.detailBand}><SectionHeader eyebrow="Asignaciones consentidas" title="Árbitros" /><div className={styles.teamGrid}>{referees.map((referee) => <Link href={`/arbitros/${publicCompetitionText(referee.slug)}`} key={publicCompetitionText(referee.assignmentId)}><span>{publicCompetitionText(referee.displayName).slice(0, 2).toUpperCase()}</span><div><strong>{publicCompetitionText(referee.displayName)}</strong><small>{publicCompetitionText(referee.status)}</small></div></Link>)}</div>{!referees.length ? <p className={styles.privateNote}>No hay asignaciones públicas confirmadas.</p> : null}</section> : null}
      {activeTab === "registration" ? <section className={styles.detailBand}><SectionHeader eyebrow={publicCompetitionText(registration.mode).replaceAll("_", " ")} title="Inscripción de equipo" /><RegistrationPanel accessToken={accessToken} busy={busy} competitionId={competitionId} onCommand={command} publication={publication} requests={requests} teams={teams} /><OrganizerQueue busy={busy} items={queue} onCommand={command} /></section> : null}
      <details className={styles.report}><summary>Reportar información de esta competición</summary><form onSubmit={(event: FormEvent<HTMLFormElement>) => { event.preventDefault(); const form = new FormData(event.currentTarget); void command("competition.report", publicCompetitionText(publication.id), publicCompetitionNumber(publication.revision), { category: String(form.get("category") ?? "OTHER"), reason: "Reporte de competición", summary: String(form.get("summary") ?? "") }); }}><label>Motivo<select name="category"><option value="MISLEADING">Información incorrecta</option><option value="IMPERSONATION">Suplantación</option><option value="PRIVACY">Privacidad</option><option value="ABUSE">Abuso</option><option value="OTHER">Otro</option></select></label><label>Descripción<textarea name="summary" required minLength={3} maxLength={1000} rows={3} /></label><button type="submit" disabled={busy || !accessToken}>Enviar a moderación</button></form></details>
    </div>;
  return embedded ? content : <OfficialProductShellV2 active="mercado" context={{ detail: publicCompetitionText(edition.name), eyebrow: shellEyebrow, status: publicCompetitionStateLabel(competition.publicState), title: name }}>{content}</OfficialProductShellV2>;
}

"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import {
  leagueArray,
  leagueNextActionLabel,
  leagueNumber,
  leagueParticipationCacheVersion,
  leagueParticipationRealtimeTable,
  leagueRecord,
  leagueStatusTone,
  leagueText,
  type LeagueJson,
  type LeagueParticipationAction,
} from "../league-participation-contract";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import {
  GamePageHeader,
  MetricTile,
  ProductFeedback,
  ResponsiveActionBar,
  SectionHeader,
  StatusChip,
} from "./official-ui-v2-primitives";
import styles from "./league-participation-client.module.css";

export type LeagueParticipationSurface = "desk" | "entry" | "mine" | "public" | "roster";

type Props = {
  competitionId?: string;
  entryId?: string;
  previewData?: LeagueJson | null;
  rosterId?: string;
  surface: LeagueParticipationSurface;
};

function status(value: unknown) {
  return <StatusChip tone={leagueStatusTone(value)}>{leagueText(value).replaceAll("_", " ") || "sin estado"}</StatusChip>;
}

function dateLabel(value: unknown) {
  const parsed = new Date(leagueText(value));
  return Number.isNaN(parsed.getTime())
    ? "Sin fecha"
    : new Intl.DateTimeFormat("es-ES", { dateStyle: "medium", timeStyle: "short" }).format(parsed);
}

function cacheKey(surface: LeagueParticipationSurface, id: string, userId: string) {
  return `pachangas-league-participation-read-v1:${surface}:${id || "self"}:${userId || "public"}`;
}

function readCache(key: string) {
  try {
    const envelope = leagueRecord(JSON.parse(window.localStorage.getItem(key) ?? "null"));
    return leagueNumber(envelope.version) === leagueParticipationCacheVersion
      ? leagueRecord(envelope.data)
      : null;
  } catch {
    return null;
  }
}

function writeCache(key: string, data: LeagueJson) {
  try {
    window.localStorage.setItem(key, JSON.stringify({
      data,
      storedAt: new Date().toISOString(),
      version: leagueParticipationCacheVersion,
    }));
  } catch {
    // Read caching is optional and never authoritative.
  }
}

function endpointFor(props: Props) {
  if (props.surface === "public") return `/api/competitions/participation/public/${props.competitionId ?? ""}`;
  if (props.surface === "desk") return `/api/competitions/participation/desk/${props.competitionId ?? ""}`;
  if (props.surface === "entry") return `/api/competitions/participation/entry/${props.entryId ?? ""}`;
  if (props.surface === "roster") return `/api/competitions/participation/roster/${props.rosterId ?? ""}`;
  return "/api/competitions/participation/my";
}

function surfaceTitle(surface: LeagueParticipationSurface) {
  if (surface === "desk") return "Mesa de inscripciones";
  if (surface === "entry") return "Participación del equipo";
  if (surface === "roster") return "Plantilla de competición";
  if (surface === "public") return "Inscripción de Liga";
  return "Mis competiciones";
}

function invalidationMatches(
  surface: LeagueParticipationSurface,
  props: Pick<Props, "competitionId" | "entryId" | "rosterId">,
  value: unknown,
) {
  const row = leagueRecord(leagueRecord(value).new);
  if (leagueText(row.entity_type) === "league_participation_flags") return true;
  if (surface === "mine") return true;
  const competitionId = leagueText(row.competition_id);
  if (props.competitionId && competitionId === props.competitionId) return true;
  const entityId = leagueText(row.entity_id);
  if (surface === "entry" && props.entryId && entityId === props.entryId) return true;
  if (surface === "roster" && props.rosterId && entityId === props.rosterId) return true;
  return false;
}

export function LeagueParticipationClient(props: Props) {
  const {
    competitionId,
    entryId,
    previewData = null,
    rosterId,
    surface,
  } = props;
  const [data, setData] = useState<LeagueJson | null>(previewData);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [loading, setLoading] = useState(!previewData);
  const [cached, setCached] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(previewData ? "Fixture visual aislado. Ninguna acción se enviará." : "");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);
  const endpoint = endpointFor(props);
  const identity = competitionId || entryId || rosterId || "";

  const loadCanonical = useCallback(async (token: string, actorId: string, source: "initial" | "mutation" | "realtime") => {
    const key = cacheKey(surface, identity, actorId);
    try {
      const headers = token ? { Authorization: `Bearer ${token}` } : undefined;
      const response = await fetch(endpoint, { cache: "no-store", headers });
      const body = await response.json() as LeagueJson;
      if (!response.ok) throw new Error(leagueText(body.message) || "No se pudo recuperar el estado canónico.");
      setData(leagueRecord(body));
      setCached(false);
      writeCache(key, leagueRecord(body));
      if (source === "realtime") setMessage("Estado actualizado desde el servidor.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo recuperar el estado canónico.");
    } finally {
      setLoading(false);
    }
  }, [endpoint, identity, surface]);

  useEffect(() => {
    if (previewData) return;
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    const start = async () => {
      const sessionResult = await supabase?.auth.getSession();
      if (!active) return;
      const token = sessionResult?.data.session?.access_token ?? "";
      const actorId = sessionResult?.data.session?.user.id ?? "";
      if (surface !== "public" && (!token || !actorId)) {
        setLoading(false);
        setMessage("Inicia sesión para consultar esta participación.");
        return;
      }
      setAccessToken(token);
      setUserId(actorId);
      const local = readCache(cacheKey(surface, identity, actorId));
      if (local) {
        setData(local);
        setCached(true);
        setLoading(false);
      }
      await loadCanonical(token, actorId, "initial");
      if (!supabase || !token) return;
      channel = supabase.channel(`league-participation:${surface}:${identity || actorId}`)
        .on("postgres_changes", {
          event: "INSERT",
          schema: "public",
          table: leagueParticipationRealtimeTable,
        }, (payload) => {
          if (!invalidationMatches(surface, { competitionId, entryId, rosterId }, payload)) return;
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(() => void loadCanonical(token, actorId, "realtime"), 120);
        })
        .subscribe();
    };
    void start();
    return () => {
      active = false;
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel && supabase) void supabase.removeChannel(channel);
    };
  }, [competitionId, entryId, identity, loadCanonical, previewData, rosterId, surface]);

  async function command(action: LeagueParticipationAction, aggregateId: string, expectedRevision: number, payload: LeagueJson) {
    if (previewData) {
      setMessage("Fixture visual: la intención no se ha enviado.");
      return;
    }
    if (!accessToken || !userId) {
      setMessage("Inicia sesión antes de enviar la operación.");
      return;
    }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación del servidor...");
    try {
      const response = await clientWriteFetch("api:league-participation-command", "/api/competitions/participation/command", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = await response.json() as LeagueJson;
      if (!response.ok) throw new Error(leagueText(body.message) || "Operación no confirmada.");
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      await loadCanonical(accessToken, userId, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail)
        ? "La revisión cambió. Se ha recargado el estado oficial."
        : detail);
      if (/STALE_REVISION|revision/i.test(detail)) await loadCanonical(accessToken, userId, "mutation");
    } finally {
      setBusy(false);
    }
  }

  function submitPublicApplication(event: FormEvent<HTMLFormElement>, categoryId: string, revision: number) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("entry.submit", categoryId, revision, {
      reason: "Solicitud pública enviada por el owner",
      teamId: String(form.get("teamId") ?? "").trim(),
    });
  }

  const shellContext = {
    detail: previewData ? "Mundo de prueba R4A" : cached ? "Copia local revalidándose" : "Estado canónico",
    eyebrow: "Competiciones",
    status: previewData ? "Solo visual" : loading ? "Sincronizando" : "Servidor",
    title: surfaceTitle(surface),
  };

  return <OfficialProductShellV2 active="equipo" context={shellContext}>
    <main className={styles.page} data-mobile-tab="equipo" data-surface={surface}>
      <GamePageHeader
        eyebrow="League Participation R4A"
        summary="Inscripciones, delegados, plantillas y elegibilidad sin generar jornadas ni partidos."
        title={surfaceTitle(surface)}
      />
      {message ? <ProductFeedback tone={/confirmado|actualizado/i.test(message) ? "success" : /no |error|cerrad|requer/i.test(message) ? "warning" : "info"}>{message}</ProductFeedback> : null}
      {loading && !data ? <section className={styles.state}><strong>Recuperando estado oficial</strong></section> : null}
      {!loading && !data ? <section className={styles.state}><strong>Sin datos disponibles</strong><span>La función permanece gated mientras sus flags estén apagados.</span></section> : null}
      {data && surface === "public" ? <PublicRegistration data={data} busy={busy} onSubmit={submitPublicApplication} /> : null}
      {data && surface === "mine" ? <MyEntries data={data} /> : null}
      {data && surface === "desk" ? <RegistrationDesk busy={busy} data={data} onCommand={command} /> : null}
      {data && surface === "entry" ? <EntryDetail busy={busy} data={data} onCommand={command} /> : null}
      {data && surface === "roster" ? <RosterDetail busy={busy} data={data} onCommand={command} /> : null}
    </main>
  </OfficialProductShellV2>;
}

function PublicRegistration({ busy, data, onSubmit }: { busy: boolean; data: LeagueJson; onSubmit: (event: FormEvent<HTMLFormElement>, categoryId: string, revision: number) => void }) {
  const competition = leagueRecord(data.competition);
  const edition = leagueRecord(data.edition);
  const categories = leagueArray(data.categories);
  return <>
    <section className={styles.heroBand}>
      <div><span>{leagueText(edition.seasonLabel)}</span><h2>{leagueText(competition.name)}</h2><p>Inscripción con aprobación del organizador.</p></div>
      <div className={styles.metrics}><MetricTile label="Aceptados" value={leagueNumber(data.acceptedTeams)} /><MetricTile label="Cierre" value={dateLabel(edition.registrationClosesAt)} /></div>
    </section>
    <section className={styles.categoryGrid}>
      {categories.map((category) => <article className={styles.category} key={leagueText(category.id)}>
        <SectionHeader eyebrow={leagueText(category.sportFormat)} title={leagueText(category.name)} />
        <p>{leagueText(category.description)}</p>
        <div className={styles.inlineMeta}><span>{leagueText(category.levelLabel) || "Categoría abierta"}</span><b>{leagueNumber(category.acceptedTeams)} equipos</b></div>
        <form onSubmit={(event) => onSubmit(event, leagueText(category.id), leagueNumber(category.revision))}>
          <label>Equipo<input name="teamId" placeholder="UUID del equipo" required /></label>
          <button type="submit" disabled={busy}>Solicitar plaza</button>
        </form>
      </article>)}
    </section>
  </>;
}

function MyEntries({ data }: { data: LeagueJson }) {
  const items = leagueArray(data.items);
  return <section className={styles.flowSection}>
    <SectionHeader eyebrow={`${leagueNumber(data.total)} participaciones`} title="Equipos y competiciones" />
    <div className={styles.entryGrid}>{items.map((item) => <Link className={styles.entryCard} href={`/competiciones/${leagueText(item.competitionId)}/equipos/${leagueText(item.id)}`} key={leagueText(item.id)}>
      <div><span>{leagueText(item.competitionName)}</span><strong>{leagueText(item.teamName)}</strong><small>{leagueText(item.editionName)} · {leagueText(item.categoryName)}</small></div>
      <div>{status(item.status)}{status(item.rosterStatus || "sin roster")}</div>
      <footer><span>{leagueText(item.nextValidAction) ? leagueNextActionLabel(leagueText(item.nextValidAction)) : leagueText(item.actorScope).replaceAll("_", " ")}</span><b>{dateLabel(item.registrationClosesAt)}</b></footer>
    </Link>)}</div>
  </section>;
}

function RegistrationDesk({ busy, data, onCommand }: { busy: boolean; data: LeagueJson; onCommand: (action: LeagueParticipationAction, aggregateId: string, revision: number, payload: LeagueJson) => void }) {
  const items = leagueArray(data.items);
  const counts = leagueRecord(data.counts);
  return <div className={styles.deskLayout}>
    <aside className={styles.filters}>
      <SectionHeader eyebrow="Estados" title="Cola" />
      {Object.entries(counts).map(([key, value]) => <div key={key}><span>{key.replaceAll("_", " ")}</span><b>{leagueNumber(value)}</b></div>)}
    </aside>
    <section className={styles.deskList}>
      {items.map((item) => <article className={styles.deskItem} key={leagueText(item.id)}>
        <div><span>{leagueText(item.categoryName)}</span><h3>{leagueText(item.teamName)}</h3><small>{leagueText(item.source).replaceAll("_", " ")}</small></div>
        <div className={styles.deskHealth}>{status(item.status)}{status(item.rosterStatus || "sin roster")}<small>{leagueNumber(item.memberCount)} jugadores · {leagueNumber(item.warningCount)} avisos</small></div>
        <ResponsiveActionBar>
          <Link href={`/competiciones/${leagueText(data.competitionId)}/equipos/${leagueText(item.id)}`}>Abrir</Link>
          {leagueText(item.status) === "submitted" ? <>
            <button type="button" disabled={busy} onClick={() => onCommand("entry.accept", leagueText(item.id), leagueNumber(item.revision), { reason: "Solicitud revisada y aceptada" })}>Aceptar</button>
            <button type="button" disabled={busy} onClick={() => onCommand("entry.reject", leagueText(item.id), leagueNumber(item.revision), { reason: "Solicitud revisada por la organización" })}>Rechazar</button>
          </> : null}
        </ResponsiveActionBar>
      </article>)}
    </section>
    <aside className={styles.detailRail}><SectionHeader eyebrow="R4A" title="Salud" /><MetricTile label="Solicitudes" value={leagueNumber(data.total)} /><p>Los avisos de elegibilidad se resuelven dentro de cada plantilla.</p></aside>
  </div>;
}

function EntryDetail({ busy, data, onCommand }: { busy: boolean; data: LeagueJson; onCommand: (action: LeagueParticipationAction, aggregateId: string, revision: number, payload: LeagueJson) => void }) {
  const competition = leagueRecord(data.competition);
  const edition = leagueRecord(data.edition);
  const category = leagueRecord(data.category);
  const entry = leagueRecord(data.entry);
  const roster = leagueRecord(data.roster);
  const membership = leagueRecord(data.stageMembership);
  const delegates = leagueArray(data.delegates);
  const hard = leagueArray(data.availabilityConstraints);
  const soft = leagueArray(data.schedulePreferences);
  const actions = Array.isArray(data.nextActions) ? data.nextActions.map(leagueText) : [];
  return <>
    <section className={styles.heroBand}>
      <div><span>{leagueText(competition.name)} · {leagueText(edition.seasonLabel)}</span><h2>{leagueText(entry.teamName)}</h2><p>{leagueText(category.name)} · {leagueText(category.sportFormat)}</p></div>
      <div>{status(entry.status)}{status(roster.status || "sin roster")}</div>
    </section>
    <div className={styles.entryDetailGrid}>
      <section className={styles.panel}>
        <SectionHeader eyebrow="Representación" title="Delegados" />
        {delegates.map((delegate) => <div className={styles.personRow} key={leagueText(delegate.id)}><span><strong>{leagueText(delegate.displayName)}</strong><small>{leagueText(delegate.role).replaceAll("_", " ")}</small></span>{status(delegate.status)}</div>)}
      </section>
      <section className={styles.panel}>
        <SectionHeader eyebrow="Plantilla" title={leagueText(roster.status) || "Pendiente"} />
        <div className={styles.metrics}><MetricTile label="Jugadores" value={leagueNumber(roster.memberCount)} /><MetricTile label="Revisión" value={leagueNumber(roster.revision)} /></div>
        {leagueText(roster.id) ? <Link className={styles.primaryLink} href={`/competiciones/${leagueText(competition.id)}/equipos/${leagueText(entry.id)}?roster=${leagueText(roster.id)}`}>Abrir plantilla</Link> : null}
      </section>
      <section className={styles.panel}>
        <SectionHeader eyebrow="Fase" title={leagueText(membership.stageName) || "Sin asignar"} />
        <p>{[membership.divisionName, membership.groupName].map(leagueText).filter(Boolean).join(" · ") || "La asignación no genera partidos."}</p>
      </section>
      <section className={styles.panel}>
        <SectionHeader eyebrow="Calendario futuro" title="Disponibilidad" />
        <div className={styles.constraintColumns}>
          <div data-kind="hard"><strong>NO PUEDO JUGAR</strong>{hard.map((item) => <span key={leagueText(item.id)}>Día {leagueNumber(item.weekday)} · {leagueText(item.startLocalTime)}-{leagueText(item.endLocalTime)}</span>)}</div>
          <div data-kind="soft"><strong>PREFERIRÍA JUGAR</strong>{soft.map((item) => <span key={leagueText(item.id)}>Día {leagueNumber(item.weekday)} · {leagueText(item.startLocalTime)}-{leagueText(item.endLocalTime)}</span>)}</div>
        </div>
      </section>
    </div>
    <ResponsiveActionBar className={styles.entryActions}>
      {actions.map((action) => <span key={action}>{leagueNextActionLabel(action)}</span>)}
      {leagueText(entry.status) === "invited" ? <><button type="button" disabled={busy} onClick={() => onCommand("entry.accept", leagueText(entry.id), leagueNumber(entry.revision), { reason: "Invitación aceptada por el owner" })}>Aceptar invitación</button><button type="button" disabled={busy} onClick={() => onCommand("entry.decline", leagueText(entry.id), leagueNumber(entry.revision), { reason: "Invitación declinada por el owner" })}>Declinar</button></> : null}
      {leagueText(entry.status) === "accepted" && leagueText(data.actorScope) === "TEAM_OWNER" ? <button type="button" disabled={busy} onClick={() => onCommand("entry.withdraw", leagueText(entry.id), leagueNumber(entry.revision), { reason: "Retirada confirmada por el owner" })}>Retirar participación</button> : null}
    </ResponsiveActionBar>
  </>;
}

function RosterDetail({ busy, data, onCommand }: { busy: boolean; data: LeagueJson; onCommand: (action: LeagueParticipationAction, aggregateId: string, revision: number, payload: LeagueJson) => void }) {
  const roster = leagueRecord(data.roster);
  const revision = leagueRecord(data.currentRevision);
  const members = leagueArray(data.members);
  const kits = leagueArray(data.kits);
  const history = leagueArray(data.history);
  const warnings = leagueArray(data.warnings);
  return <div className={styles.rosterLayout}>
    <section className={styles.rosterMembers}>
      <SectionHeader eyebrow={`${leagueNumber(revision.memberCount)} jugadores`} title="Plantilla actual" />
      <div className={styles.playerGrid}>{members.map((member) => {
        const player = leagueRecord(member.player);
        const credential = leagueRecord(member.credential);
        return <article className={styles.playerRow} key={leagueText(member.id)}>
          <b>{leagueText(member.jerseyNumber) || "-"}</b>
          <span><strong>{leagueText(player.displayName)}</strong><small>{leagueText(player.position)}</small></span>
          <div>{status(member.eligibilityStatus)}<small>{leagueText(credential.status)}</small></div>
        </article>;
      })}</div>
    </section>
    <aside className={styles.rosterTools}>
      <SectionHeader eyebrow={`Revisión ${leagueNumber(roster.revision)}`} title={leagueText(roster.status)} />
      <div className={styles.metrics}><MetricTile label="Elegibles" value={leagueNumber(leagueRecord(revision.eligibilitySummary).eligible)} /><MetricTile label="Pendientes" value={leagueNumber(leagueRecord(revision.eligibilitySummary).pending)} /></div>
      {warnings.length ? <div className={styles.warningList}><h3>Avisos</h3>{warnings.map((warning) => <div key={`${leagueText(warning.memberId)}:${leagueText(warning.code)}`}><strong>{leagueText(warning.playerName)}</strong><small>{leagueText(warning.code).replaceAll("_", " ")}</small></div>)}</div> : null}
      <h3>Equipaciones</h3>{kits.map((kit) => <div className={styles.kitRow} key={leagueText(kit.id)}><i style={{ background: leagueText(kit.primaryColor) }} /><span>{leagueText(kit.type)}</span></div>)}
      <h3>Historial</h3>{history.map((item) => <div className={styles.historyRow} key={leagueText(item.id)}><span>v{leagueNumber(item.revisionNumber)}</span>{status(item.status)}</div>)}
      <ResponsiveActionBar>
        {leagueText(roster.status) === "draft" ? <button type="button" disabled={busy} onClick={() => onCommand("roster.submit", leagueText(roster.id), leagueNumber(roster.revision), { reason: "Plantilla enviada a revisión" })}>Enviar plantilla</button> : null}
        {leagueText(roster.status) === "submitted" && leagueText(data.actorScope) === "ORGANIZER" ? <><button type="button" disabled={busy} onClick={() => onCommand("roster.approve", leagueText(roster.id), leagueNumber(roster.revision), { reason: "Plantilla validada" })}>Aprobar</button><button type="button" disabled={busy} onClick={() => onCommand("roster.request_changes", leagueText(roster.id), leagueNumber(roster.revision), { reason: "Se requieren correcciones" })}>Pedir cambios</button></> : null}
      </ResponsiveActionBar>
    </aside>
  </div>;
}

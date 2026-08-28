"use client";

import Link from "next/link";
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  tournamentArray,
  tournamentBoolean,
  tournamentNumber,
  tournamentRecord,
  tournamentStatusTone,
  tournamentText,
  type TournamentJson,
} from "../tournament-draw-contract";
import {
  buildTournamentGroupStageSlotIntents,
  compareTournamentGroupStageSnapshots,
  tournamentGroupStageReadCacheVersion,
  tournamentGroupStageRealtimeTable,
  tournamentGroupStageRevision,
  tournamentGroupStageTabs,
  type TournamentGroupStageAction,
  type TournamentGroupStageTab,
} from "../tournament-group-stage-contract";
import { tournamentKnockoutRevision } from "../tournament-knockout-contract";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import {
  TournamentKnockoutBracket,
  type TournamentKnockoutCommandOptions,
} from "./tournament-knockout-bracket";
import {
  GamePageHeader,
  MetricTile,
  ProductFeedback,
  ResponsiveActionBar,
  SectionHeader,
  StatusChip,
} from "./official-ui-v2-primitives";
import styles from "./tournament-group-stage-client.module.css";

type Props = { competitionId: string };
type CommandOptions = {
  action: TournamentGroupStageAction;
  payload?: TournamentJson;
};

const cachePrefix = "pachangas-tournament-group-stage-read-v2";
const tabLabels: Record<TournamentGroupStageTab, string> = {
  bracket: "Cuadro",
  discipline: "Disciplina",
  incidents: "Incidencias",
  matches: "Partidos",
  referees: "Árbitros",
  rounds: "Jornadas",
  rules: "Reglamento",
  standings: "Clasificación",
  summary: "Resumen",
  teams: "Equipos",
};

const matchFilterLabels: Record<string, string> = {
  all: "Todos",
  official: "Oficiales",
  pending: "Pendientes",
  played: "Jugados",
  postponed: "Aplazados",
  scheduled: "Próximos",
  suspended: "Suspendidos",
};

function cacheKey(competitionId: string, userId: string) {
  return `${cachePrefix}:${competitionId}:${userId}`;
}

function readCache(key: string) {
  try {
    const envelope = tournamentRecord(JSON.parse(window.localStorage.getItem(key) ?? "null"));
    if (tournamentNumber(envelope.version) !== tournamentGroupStageReadCacheVersion) return null;
    return tournamentRecord(envelope.data);
  } catch {
    return null;
  }
}

function writeCache(key: string, incoming: TournamentJson) {
  try {
    const current = readCache(key);
    const data = current && tournamentText(incoming.kind) === "TournamentGroupStageHub"
      && tournamentText(current.kind) === "TournamentGroupStageHub"
      && compareTournamentGroupStageSnapshots(current, incoming) > 0
      ? current
      : incoming;
    window.localStorage.setItem(key, JSON.stringify({
      data,
      storedAt: new Date().toISOString(),
      version: tournamentGroupStageReadCacheVersion,
    }));
    return data;
  } catch {
    return incoming;
  }
}

function messageFrom(value: unknown, fallback: string) {
  const record = tournamentRecord(value);
  const detail = tournamentText(record.message) || tournamentText(record.error);
  if (!detail || /schema cache|function public\./i.test(detail)) return fallback;
  return detail.replaceAll("_", " ");
}

function statusChip(value: unknown) {
  return <StatusChip tone={tournamentStatusTone(value)}>{tournamentText(value, "pendiente").replaceAll("_", " ")}</StatusChip>;
}

function formatDateTime(value: unknown, includeDate = true) {
  const date = new Date(tournamentText(value));
  if (!Number.isFinite(date.getTime())) return "Sin horario";
  return new Intl.DateTimeFormat("es-ES", {
    ...(includeDate ? { day: "2-digit", month: "short" } : {}),
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function groupName(groups: TournamentJson[], id: unknown) {
  return tournamentText(groups.find((item) => tournamentText(item.id) === tournamentText(id))?.name, "Grupo");
}

function invalidationMatches(competitionId: string, payload: unknown) {
  const row = tournamentRecord(tournamentRecord(payload).new);
  return tournamentText(row.competition_id) === competitionId;
}

export function TournamentGroupStageClient({ competitionId }: Props) {
  const [data, setData] = useState<TournamentJson | null>(null);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [loading, setLoading] = useState(true);
  const [cached, setCached] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [tab, setTab] = useState<TournamentGroupStageTab>("summary");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const loadCanonical = useCallback(async (
    token: string,
    actorId: string,
    source: "initial" | "mutation" | "realtime",
  ) => {
    try {
      const response = await fetch(`/api/tournaments/group-stage/${competitionId}`, {
        cache: "no-store",
        headers: { Authorization: `Bearer ${token}` },
      });
      const incoming = tournamentRecord(await response.json());
      if (!response.ok) throw new Error(messageFrom(incoming, "No se pudo recuperar el Tournament Hub."));
      const canonical = writeCache(cacheKey(competitionId, actorId), incoming);
      setData((current) => {
        if (!current || tournamentText(current.kind) !== "TournamentGroupStageHub"
            || tournamentText(canonical.kind) !== "TournamentGroupStageHub") return canonical;
        return compareTournamentGroupStageSnapshots(current, canonical) > 0 ? current : canonical;
      });
      setCached(false);
      if (source === "realtime") setMessage("Tournament Hub actualizado desde PostgreSQL.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo recuperar el estado canónico.");
    } finally {
      setLoading(false);
    }
  }, [competitionId]);

  useEffect(() => {
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    let reconnect: (() => void) | undefined;
    const start = async () => {
      const session = await supabase?.auth.getSession();
      if (!active) return;
      const token = session?.data.session?.access_token ?? "";
      const actorId = session?.data.session?.user.id ?? "";
      if (!token || !actorId) {
        setLoading(false);
        setMessage("Inicia sesión para consultar este Torneo privado.");
        return;
      }
      setAccessToken(token);
      setUserId(actorId);
      const local = readCache(cacheKey(competitionId, actorId));
      if (local) {
        setData(local);
        setCached(true);
        setLoading(false);
      }
      await loadCanonical(token, actorId, "initial");
      if (!supabase || !active) return;
      channel = supabase.channel(`tournament-group-stage:${competitionId}`)
        .on("system", {}, (payload) => {
          if (payload.extension === "postgres_changes" && payload.status === "ok") {
            void loadCanonical(token, actorId, "realtime");
          }
        })
        .on("postgres_changes", {
          event: "INSERT",
          filter: `competition_id=eq.${competitionId}`,
          schema: "public",
          table: tournamentGroupStageRealtimeTable,
        }, (payload) => {
          if (!invalidationMatches(competitionId, payload)) return;
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(
            () => void loadCanonical(token, actorId, "realtime"),
            140,
          );
        })
        .subscribe();
      reconnect = () => void loadCanonical(token, actorId, "realtime");
      window.addEventListener("online", reconnect);
    };
    void start();
    return () => {
      active = false;
      if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
      if (channel && supabase) void supabase.removeChannel(channel);
      if (reconnect) window.removeEventListener("online", reconnect);
    };
  }, [competitionId, loadCanonical]);

  const command = useCallback(async ({ action, payload = {} }: CommandOptions) => {
    if (!accessToken || !data) {
      setMessage("No hay sesión o snapshot canónico para esta operación.");
      return false;
    }
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      setMessage("Sin conexión: el calendario cacheado sigue disponible, pero no se permiten operaciones deportivas.");
      return false;
    }
    const expectedRevision = tournamentGroupStageRevision(data);
    const key = JSON.stringify({ action, competitionId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch(
        "api:tournament-group-stage-command",
        "/api/tournaments/group-stage/command",
        {
          body: JSON.stringify({
            action,
            aggregateId: competitionId,
            expectedRevision,
            operationId: pending.current.id,
            payload,
          }),
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          method: "POST",
        },
      );
      const body = tournamentRecord(await response.json());
      if (!response.ok) throw new Error(messageFrom(body, "Operación no confirmada."));
      pending.current = null;
      await loadCanonical(accessToken, userId, "mutation");
      setMessage("Cambio confirmado por PostgreSQL.");
      return true;
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE|revision/i.test(detail)
        ? "Otro dispositivo cambió la revisión. Se ha recuperado el estado oficial."
        : detail);
      if (/STALE|revision/i.test(detail)) await loadCanonical(accessToken, userId, "mutation");
      return false;
    } finally {
      setBusy(false);
    }
  }, [accessToken, competitionId, data, loadCanonical, userId]);

  const knockoutCommand = useCallback(async ({ action, payload = {} }: TournamentKnockoutCommandOptions) => {
    if (!accessToken || !data) {
      setMessage("No hay sesión o snapshot canónico para esta operación.");
      return false;
    }
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      setMessage("Sin conexión: el cuadro cacheado sigue disponible, pero no se permiten operaciones deportivas.");
      return false;
    }
    const expectedRevision = tournamentKnockoutRevision(data);
    const key = JSON.stringify({ action, competitionId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch(
        "api:tournament-knockout-command",
        "/api/tournaments/knockout/command",
        {
          body: JSON.stringify({
            action,
            aggregateId: competitionId,
            expectedRevision,
            operationId: pending.current.id,
            payload,
          }),
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          method: "POST",
        },
      );
      const body = tournamentRecord(await response.json());
      if (!response.ok) throw new Error(messageFrom(body, "Operación eliminatoria no confirmada."));
      pending.current = null;
      await loadCanonical(accessToken, userId, "mutation");
      setMessage("Cambio eliminatorio confirmado por PostgreSQL.");
      return true;
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación eliminatoria no confirmada.";
      setMessage(/STALE|revision/i.test(detail)
        ? "Otro dispositivo cambió el cuadro. Se ha recuperado el estado oficial."
        : detail);
      if (/STALE|revision/i.test(detail)) await loadCanonical(accessToken, userId, "mutation");
      return false;
    } finally {
      setBusy(false);
    }
  }, [accessToken, competitionId, data, loadCanonical, userId]);

  const competition = tournamentRecord(data?.competition);
  const groupStage = tournamentRecord(data?.groupStage);
  const isSetup = tournamentText(data?.kind) === "TournamentGroupStageSetup";
  const title = tournamentText(competition.name, "Tournament Hub");

  return <OfficialProductShellV2
    active="equipo"
    context={{
      detail: cached ? "Copia local revalidándose" : "Servidor autoritativo",
      eyebrow: "Tournament Private Beta",
      status: loading ? "Sincronizando" : tournamentText(groupStage.status, isSetup ? "Por preparar" : "Activo").replaceAll("_", " "),
      title,
    }}
  >
    <main className={styles.page} data-mobile-tab="equipo" data-tournament-hub="r6b">
      {message ? <ProductFeedback tone={/confirmado|actualizado/i.test(message) ? "success" : /sin conexión|no |error|stale|rechaz/i.test(message) ? "warning" : "info"}>{message}</ProductFeedback> : null}
      {loading && !data ? <div className={styles.empty}>Recuperando Tournament Hub...</div> : null}
      {!loading && !data ? <div className={styles.empty}>Tournament Hub no disponible para esta cuenta.</div> : null}
      {data && isSetup ? <SetupPanel busy={busy} command={command} data={data} /> : null}
      {data && !isSetup ? <>
        <GamePageHeader
          actions={<><Link href={`/competiciones/${competitionId}/sorteo`}>Sorteo</Link><Link href="/torneos">Torneos</Link></>}
          eyebrow={`${tournamentNumber(groupStage.groupCount)} grupos · ${tournamentNumber(groupStage.fixtureCount)} partidos`}
          summary="Jornadas, resultados, clasificaciones e incidencias proceden del snapshot canónico."
          title={title}
        />
        <nav className={styles.tabs} aria-label="Tournament Hub">
          {tournamentGroupStageTabs.map((item) => <button aria-pressed={tab === item} key={item} onClick={() => setTab(item)} type="button">{tabLabels[item]}</button>)}
        </nav>
        <HubView busy={busy} command={command} competitionId={competitionId} data={data} knockoutCommand={knockoutCommand} tab={tab} />
      </> : null}
    </main>
  </OfficialProductShellV2>;
}

function SetupPanel({ busy, command, data }: {
  busy: boolean;
  command: (options: CommandOptions) => Promise<boolean>;
  data: TournamentJson;
}) {
  const competition = tournamentRecord(data.competition);
  const drawPlans = tournamentArray(data.drawPlans).map(tournamentRecord);
  const published = drawPlans.find((plan) => tournamentText(plan.status) === "published");
  return <>
    <GamePageHeader
      actions={<Link href={`/competiciones/${tournamentText(competition.id)}/gestion/sorteo`}>Revisar sorteo</Link>}
      eyebrow="R6B · Fase de grupos"
      summary="La preparación consume el sorteo publicado y congela su RuleRevision. Todavía no crea partidos."
      title={tournamentText(competition.name, "Preparar Torneo")}
    />
    <section className={styles.setupPanel}>
      <SectionHeader eyebrow="Entrada autoritativa" title="Preparar fase de grupos" />
      <dl><Info label="Sorteo" value={published ? "Publicado" : "No publicado"} /><Info label="Revisión" value={tournamentGroupStageRevision(data)} /><Info label="Escritura" value="PostgreSQL" /></dl>
      <ResponsiveActionBar>
        <button disabled={busy || !published} onClick={() => void command({ action: "group_stage.prepare", payload: { reason: "Preparación desde Tournament Hub" } })} type="button">Preparar fase</button>
      </ResponsiveActionBar>
    </section>
  </>;
}

function HubView({ busy, command, competitionId, data, knockoutCommand, tab }: {
  busy: boolean;
  command: (options: CommandOptions) => Promise<boolean>;
  competitionId: string;
  data: TournamentJson;
  knockoutCommand: (options: TournamentKnockoutCommandOptions) => Promise<boolean>;
  tab: TournamentGroupStageTab;
}) {
  const groups = tournamentArray(data.groups).map(tournamentRecord);
  const rounds = tournamentArray(data.rounds).map(tournamentRecord);
  const matches = tournamentArray(data.matches).map(tournamentRecord);
  const standings = tournamentArray(data.standings).map(tournamentRecord);
  const organizer = tournamentRecord(data.organizerDesk);
  const qualification = tournamentRecord(data.qualification);
  const bracket = tournamentRecord(data.bracketTemplate);
  const knockout = tournamentRecord(data.knockout);
  const [requestedRound, setRound] = useState(() => tournamentNumber(rounds[0]?.roundNumber, 1));
  const round = rounds.some((item) => tournamentNumber(item.roundNumber) === requestedRound)
    ? requestedRound
    : tournamentNumber(rounds[0]?.roundNumber, 1);

  if (tab === "summary") return <SummaryView busy={busy} command={command} data={data} groups={groups} matches={matches} organizer={organizer} rounds={rounds} standings={standings} />;
  if (tab === "rounds") return <RoundsView groups={groups} matches={matches} round={round} rounds={rounds} setRound={setRound} standings={standings} />;
  if (tab === "matches") return <MatchesView competitionId={competitionId} groups={groups} matches={matches} />;
  if (tab === "standings") return <StandingsView standings={standings} />;
  if (tab === "teams") return <TeamsView data={data} groups={groups} />;
  if (tab === "discipline") return <OperationalList empty="No hay sanciones aplicables en el snapshot actual." matches={matches} mode="discipline" />;
  if (tab === "referees") return <OperationalList empty="Todavía no hay árbitros asignados." matches={matches} mode="referees" />;
  if (tab === "incidents") return <OperationalList empty="No hay incidencias públicas activas." matches={matches} mode="incidents" />;
  if (tab === "rules") return <RulesView data={data} />;
  if (tab === "bracket") return <BracketView
    bracket={bracket}
    busy={busy}
    competitionId={competitionId}
    data={data}
    groups={groups}
    knockout={knockout}
    knockoutCommand={knockoutCommand}
    qualification={qualification}
  />;

  return null;
}

function SummaryView({ busy, command, data, groups, matches, organizer, rounds, standings }: {
  busy: boolean;
  command: (options: CommandOptions) => Promise<boolean>;
  data: TournamentJson;
  groups: TournamentJson[];
  matches: TournamentJson[];
  organizer: TournamentJson;
  rounds: TournamentJson[];
  standings: TournamentJson[];
}) {
  const summary = tournamentRecord(data.summary);
  const groupStage = tournamentRecord(data.groupStage);
  const next = matches.filter((match) => ["scheduled", "ready", "postponed"].includes(tournamentText(match.status))).slice(0, 4);
  return <>
    <section className={styles.metrics}>
      <MetricTile label="Jornadas" value={rounds.length} />
      <MetricTile label="Oficiales" value={`${tournamentNumber(summary.official)}/${tournamentNumber(groupStage.fixtureCount)}`} />
      <MetricTile label="Pendientes" value={tournamentNumber(summary.pendingResults)} />
      <MetricTile label="Grupos" value={groups.length} />
    </section>
    <section className={styles.summaryGrid}>
      <div className={styles.panel}><SectionHeader eyebrow="Próxima acción" title={tournamentText(organizer.nextAction, "Seguir competición").replaceAll("_", " ")} /><dl><Info label="Sin árbitro" value={tournamentNumber(organizer.matchesWithoutReferee)} /><Info label="Incidencias" value={tournamentNumber(organizer.openIncidents)} /><Info label="Standings" value={tournamentText(organizer.standingsHealth, "CURRENT")} /><Info label="Qualification" value={tournamentText(organizer.qualificationHealth, "NOT BUILT")} /></dl></div>
      <div className={styles.panel}><SectionHeader eyebrow="Calendario" title="Próximos partidos" />{next.map((match) => <CompactMatch groups={groups} key={tournamentText(match.id)} match={match} />)}{!next.length ? <p className={styles.muted}>No quedan partidos programados.</p> : null}</div>
      <div className={styles.panel}><SectionHeader eyebrow="Clasificación" title="Líderes de grupo" />{standings.map((standing) => { const first = tournamentRecord(tournamentArray(standing.rows)[0]); return <div className={styles.leader} key={tournamentText(standing.groupId)}><span>{tournamentText(standing.groupName)}</span><strong>{tournamentText(tournamentRecord(first.team).name, "Sin datos")}</strong><b>{tournamentNumber(first.points)} pts</b></div>; })}</div>
    </section>
    <OrganizerActions busy={busy} command={command} data={data} />
  </>;
}

function OrganizerActions({ busy, command, data }: {
  busy: boolean;
  command: (options: CommandOptions) => Promise<boolean>;
  data: TournamentJson;
}) {
  const permissions = tournamentRecord(data.permissions);
  const groupStage = tournamentRecord(data.groupStage);
  const groups = tournamentArray(data.groups).map(tournamentRecord);
  const rules = tournamentRecord(data.rules);
  const schedule = tournamentRecord(rules.schedulePolicy);
  const qualification = tournamentRecord(data.qualification);
  const bracket = tournamentRecord(data.bracketTemplate);
  const canSchedule = tournamentBoolean(permissions.manageSchedule);
  const state = tournamentText(groupStage.status);
  if (!canSchedule && !tournamentBoolean(permissions.manageQualification) && !tournamentBoolean(permissions.manageBracket)) return null;
  return <section className={styles.organizerDesk}>
    <SectionHeader eyebrow="Organizer Desk" title="Operación autoritativa" />
    {canSchedule && ["prepared", "scheduling"].includes(state) ? <ScheduleSlots busy={busy} command={command} groups={groups} schedulePolicy={schedule} /> : null}
    <LifecycleActions bracket={bracket} busy={busy} command={command} data={data} qualification={qualification} state={state} />
  </section>;
}

function ScheduleSlots({ busy, command, groups, schedulePolicy }: {
  busy: boolean;
  command: (options: CommandOptions) => Promise<boolean>;
  groups: TournamentJson[];
  schedulePolicy: TournamentJson;
}) {
  const [selectedGroup, setSelectedGroup] = useState(tournamentText(groups[0]?.id));
  const [firstStartsAt, setFirstStartsAt] = useState(() => {
    const date = new Date(Date.now() + 48 * 60 * 60 * 1000);
    date.setMinutes(0, 0, 0);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}T${String(date.getHours()).padStart(2, "0")}:00`;
  });
  const [cadence, setCadence] = useState(1_440);
  const [venueLabel, setVenueLabel] = useState("");
  const selected = groups.find((group) => tournamentText(group.id) === selectedGroup) ?? groups[0];
  const entryCount = tournamentNumber(selected?.entryCount);
  const legs = Math.max(1, tournamentNumber(schedulePolicy.legs, 1));
  const fixtureCount = Math.max(1, entryCount * (entryCount - 1) / 2 * legs);
  const duration = Math.max(10, tournamentNumber(schedulePolicy.matchDurationMinutes, 60));
  const groupSchedule = tournamentRecord(selected?.schedule);
  const enoughSlots = tournamentNumber(groupSchedule.slotCount) >= fixtureCount;
  return <form className={styles.scheduleForm} onSubmit={(event) => event.preventDefault()}>
    <label>Grupo<select value={selectedGroup} onChange={(event) => setSelectedGroup(event.target.value)}>{groups.map((group) => <option key={tournamentText(group.id)} value={tournamentText(group.id)}>{tournamentText(group.name)}</option>)}</select></label>
    <label>Primer slot<input type="datetime-local" value={firstStartsAt} onChange={(event) => setFirstStartsAt(event.target.value)} /></label>
    <label>Separación (min)<input min={duration} max={10_080} type="number" value={cadence} onChange={(event) => setCadence(Number(event.target.value))} /></label>
    <label>Sede<input placeholder={`Sede ${tournamentText(selected?.name)}`} value={venueLabel} onChange={(event) => setVenueLabel(event.target.value)} /></label>
    <div className={styles.scheduleSummary}><span>{fixtureCount} slots requeridos</span>{statusChip(groupSchedule.status)}<strong>{tournamentNumber(groupSchedule.slotCount)}/{fixtureCount}</strong></div>
    <ScheduleSlotCommand busy={busy} cadence={cadence} command={command} duration={duration} enoughSlots={enoughSlots} firstStartsAt={firstStartsAt} fixtureCount={fixtureCount} group={selected ?? {}} venueLabel={venueLabel} />
  </form>;
}

function ScheduleSlotCommand({ busy, cadence, command, duration, enoughSlots, firstStartsAt, fixtureCount, group, venueLabel }: {
  busy: boolean;
  cadence: number;
  command: (options: CommandOptions) => Promise<boolean>;
  duration: number;
  enoughSlots: boolean;
  firstStartsAt: string;
  fixtureCount: number;
  group: TournamentJson;
  venueLabel: string;
}) {
  return <button
    data-group-slot-intent={tournamentText(group.id)}
    disabled={busy || enoughSlots || !firstStartsAt}
    onClick={() => void command({
      action: "group_schedule.create",
      payload: {
        groupId: tournamentText(group.id),
        reason: `Slots preparados desde Tournament Hub para ${tournamentText(group.name)}`,
        slots: buildTournamentGroupStageSlotIntents({
        firstStartsAt,
        fixtureCount,
        matchDurationMinutes: duration,
        slotCadenceMinutes: cadence,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Madrid",
        venueLabel: venueLabel || `Sede ${tournamentText(group.name)}`,
        }),
      },
    })}
    type="button"
  >{enoughSlots ? "Slots preparados" : "Preparar slots"}</button>;
}

function LifecycleActions({ bracket, busy, command, data, qualification, state }: {
  bracket: TournamentJson;
  busy: boolean;
  command: (options: CommandOptions) => Promise<boolean>;
  data: TournamentJson;
  qualification: TournamentJson;
  state: string;
}) {
  const permissions = tournamentRecord(data.permissions);
  const groups = tournamentArray(data.groups).map(tournamentRecord);
  const slotsReady = groups.length > 0 && groups.every((group) => {
    const schedule = tournamentRecord(group.schedule);
    const entries = tournamentNumber(group.entryCount);
    const legs = Math.max(1, tournamentNumber(tournamentRecord(tournamentRecord(data.rules).schedulePolicy).legs, 1));
    return tournamentNumber(schedule.slotCount) >= entries * (entries - 1) / 2 * legs;
  });
  const groupStage = tournamentRecord(data.groupStage);
  function run(action: TournamentGroupStageAction, reason: string) {
    void command({ action, payload: { reason } });
  }
  return <div className={styles.lifecycle} data-state={state}>
    <span>Estado: {statusChip(state)}</span>
    <span>Qualification: {statusChip(qualification.status || "not_built")}</span>
    <span>Cuadro: {statusChip(bracket.status || "not_built")}</span>
    <div>
      {tournamentBoolean(permissions.manageSchedule) && ["prepared", "scheduling"].includes(state) ? <button disabled={busy || !slotsReady} onClick={() => run("group_schedule.generate", "Generación round-robin desde Tournament Hub")} type="button">Generar jornadas</button> : null}
      {tournamentBoolean(permissions.manageSchedule) && state === "scheduling" ? <button disabled={busy} onClick={() => run("group_schedule.validate", "Validación global desde Tournament Hub")} type="button">Validar calendario</button> : null}
      {tournamentBoolean(permissions.publishSchedule) && state === "schedule_validated" ? <button disabled={busy} onClick={() => run("group_schedule.publish", "Publicación atómica desde Tournament Hub")} type="button">Publicar partidos</button> : null}
      {tournamentBoolean(permissions.manageSchedule) && state === "schedule_published" ? <button disabled={busy} onClick={() => run("group_stage.activate", "Activación operativa desde Tournament Hub")} type="button">Activar liguilla</button> : null}
      {tournamentBoolean(permissions.manageOperations) && state === "complete" && tournamentText(qualification.status) === "PUBLISHED" && !tournamentText(groupStage.completedAt) ? <button disabled={busy} onClick={() => run("group_stage.complete", "Cierre de liguilla tras clasificación publicada")} type="button">Cerrar liguilla</button> : null}
      {tournamentBoolean(permissions.manageQualification) && ["schedule_published", "active", "complete"].includes(state) && tournamentText(qualification.status) !== "PUBLISHED" ? <button disabled={busy} onClick={() => run("qualification.rebuild", "Cálculo de clasificados desde standings canónicas")} type="button">Actualizar clasificados</button> : null}
      {tournamentBoolean(permissions.manageQualification) && tournamentText(qualification.status) === "READY" ? <button disabled={busy} onClick={() => run("qualification.validate", "Validación final de clasificados")} type="button">Validar clasificados</button> : null}
      {tournamentBoolean(permissions.publishQualification) && tournamentText(qualification.status) === "READY" ? <button disabled={busy} onClick={() => run("qualification.publish", "Publicación final de clasificados")} type="button">Publicar clasificados</button> : null}
      {tournamentBoolean(permissions.manageBracket) && tournamentText(qualification.status) === "PUBLISHED" && !tournamentText(bracket.id) ? <button disabled={busy} onClick={() => run("bracket_template.create", "Plantilla inicial desde QualificationSnapshot")} type="button">Crear cuadro</button> : null}
      {tournamentBoolean(permissions.manageBracket) && tournamentText(bracket.status) === "DRAFT" ? <button disabled={busy} onClick={() => run("bracket_template.publish", "Publicación de plantilla sin progresión")} type="button">Publicar cuadro</button> : null}
    </div>
    <small>Las acciones disponibles se confirman desde PostgreSQL; no hay estado optimista.</small>
    <span data-permissions={`${tournamentBoolean(permissions.publishSchedule)}:${tournamentBoolean(permissions.manageQualification)}:${tournamentBoolean(permissions.manageBracket)}`} />
  </div>;
}

function RoundsView({ groups, matches, round, rounds, setRound, standings }: {
  groups: TournamentJson[];
  matches: TournamentJson[];
  round: number;
  rounds: TournamentJson[];
  setRound: (round: number) => void;
  standings: TournamentJson[];
}) {
  const selected = rounds.find((item) => tournamentNumber(item.roundNumber) === round);
  const roundMatches = matches.filter((item) => tournamentNumber(item.roundNumber) === round);
  return <section className={styles.gameLayout}>
    <nav className={styles.roundRail} aria-label="Jornadas">{rounds.map((item) => <button aria-pressed={round === tournamentNumber(item.roundNumber)} key={tournamentNumber(item.roundNumber)} onClick={() => setRound(tournamentNumber(item.roundNumber))} type="button"><b>J{tournamentNumber(item.roundNumber)}</b><small>{tournamentNumber(item.officialCount)}/{tournamentNumber(item.matchCount)}</small></button>)}</nav>
    <div className={styles.roundMatches}><SectionHeader eyebrow={formatDateTime(selected?.startsAt)} title={tournamentText(selected?.label, `Jornada ${round}`)} />{roundMatches.map((match) => <MatchCard groups={groups} key={tournamentText(match.id)} match={match} />)}{!roundMatches.length ? <p className={styles.muted}>Esta jornada aún no tiene partidos publicados.</p> : null}</div>
    <div className={styles.compactStandings}><SectionHeader eyebrow="En vivo" title="Clasificación" />{standings.map((standing) => <div key={tournamentText(standing.groupId)}><strong>{tournamentText(standing.groupName)}</strong>{tournamentArray(standing.rows).slice(0, 4).map((row, index) => { const item = tournamentRecord(row); return <span key={tournamentText(item.entryId)}><b>{index + 1}</b>{tournamentText(tournamentRecord(item.team).name)}<em>{tournamentNumber(item.points)}</em></span>; })}</div>)}</div>
  </section>;
}

function MatchesView({ competitionId, groups, matches }: { competitionId: string; groups: TournamentJson[]; matches: TournamentJson[] }) {
  const [filter, setFilter] = useState("all");
  const [groupId, setGroupId] = useState("all");
  const [query, setQuery] = useState("");
  const filtered = useMemo(() => matches.filter((match) => {
    const state = tournamentText(match.status);
    const stateMatches = filter === "all"
      || filter === state
      || (filter === "scheduled" && ["scheduled", "ready"].includes(state))
      || (filter === "pending" && ["played", "result_pending", "administrative_review"].includes(state))
      || (filter === "played" && ["played", "result_pending", "official"].includes(state));
    const text = `${tournamentText(tournamentRecord(match.home).name)} ${tournamentText(tournamentRecord(match.away).name)} ${tournamentText(tournamentRecord(match.venue).label)} ${tournamentText(tournamentRecord(match.referee).displayName)}`.toLowerCase();
    return stateMatches && (groupId === "all" || tournamentText(match.groupId) === groupId)
      && (!query.trim() || text.includes(query.trim().toLowerCase()));
  }), [filter, groupId, matches, query]);
  return <>
    <section className={styles.filters}><div>{Object.entries(matchFilterLabels).map(([id, label]) => <button aria-pressed={filter === id} key={id} onClick={() => setFilter(id)} type="button">{label}</button>)}</div><select aria-label="Filtrar por grupo" value={groupId} onChange={(event) => setGroupId(event.target.value)}><option value="all">Todos los grupos</option>{groups.map((group) => <option key={tournamentText(group.id)} value={tournamentText(group.id)}>{tournamentText(group.name)}</option>)}</select><input aria-label="Buscar equipo, sede o árbitro" placeholder="Equipo, sede o árbitro" value={query} onChange={(event) => setQuery(event.target.value)} /></section>
    <section className={styles.matchGrid}>{filtered.map((match) => <article className={styles.matchCard} key={tournamentText(match.id)}><MatchCard groups={groups} match={match} /><Link href={`/competiciones/${competitionId}/partidos/${tournamentText(match.id)}`}>Abrir partido</Link></article>)}{!filtered.length ? <p className={styles.empty}>No hay partidos con estos filtros.</p> : null}</section>
  </>;
}

function MatchCard({ groups, match }: { groups: TournamentJson[]; match: TournamentJson }) {
  const home = tournamentRecord(match.home);
  const away = tournamentRecord(match.away);
  const score = tournamentRecord(match.score);
  const referee = tournamentRecord(match.referee);
  const venue = tournamentRecord(match.venue);
  return <div className={styles.match}>
    <header><span>{groupName(groups, match.groupId)} · J{tournamentNumber(match.roundNumber)}</span>{statusChip(match.status)}</header>
    <div><strong>{tournamentText(home.name)}</strong><b>{score.home == null ? "–" : tournamentNumber(score.home)}</b></div>
    <div><strong>{tournamentText(away.name)}</strong><b>{score.away == null ? "–" : tournamentNumber(score.away)}</b></div>
    <footer><span>{formatDateTime(match.startsAt)}</span><span>{tournamentText(venue.label, "Sede por confirmar")}</span><span>{tournamentText(referee.displayName, "Sin árbitro")}</span></footer>
  </div>;
}

function CompactMatch({ groups, match }: { groups: TournamentJson[]; match: TournamentJson }) {
  const home = tournamentRecord(match.home);
  const away = tournamentRecord(match.away);
  return <div className={styles.compactMatch}><span>{groupName(groups, match.groupId)} · {formatDateTime(match.startsAt)}</span><strong>{tournamentText(home.name)} <b>vs</b> {tournamentText(away.name)}</strong>{statusChip(match.status)}</div>;
}

function StandingsView({ standings }: { standings: TournamentJson[] }) {
  const [groupId, setGroupId] = useState(tournamentText(standings[0]?.groupId));
  const selected = standings.find((item) => tournamentText(item.groupId) === groupId) ?? standings[0];
  const snapshot = tournamentRecord(selected?.snapshot);
  const rows = tournamentArray(selected?.rows).map(tournamentRecord);
  return <section className={styles.standingsPanel}>
    <header><div><span>Clasificación provisional</span><h2>{tournamentText(selected?.groupName, "Grupo")}</h2></div><select value={groupId} onChange={(event) => setGroupId(event.target.value)}>{standings.map((item) => <option key={tournamentText(item.groupId)} value={tournamentText(item.groupId)}>{tournamentText(item.groupName)}</option>)}</select></header>
    <div className={styles.tableWrap}><table><thead><tr><th>POS</th><th>Equipo</th><th>PJ</th><th>G</th><th>E</th><th>P</th><th>GF</th><th>GC</th><th>DG</th><th>PTS</th></tr></thead><tbody>{rows.map((row) => <tr data-zone={tournamentText(row.qualificationZone)} key={tournamentText(row.entryId)}><td>{tournamentNumber(row.position)}</td><td>{tournamentText(tournamentRecord(row.team).name)}</td><td>{tournamentNumber(row.played)}</td><td>{tournamentNumber(row.wins)}</td><td>{tournamentNumber(row.draws)}</td><td>{tournamentNumber(row.losses)}</td><td>{tournamentNumber(row.goalsFor)}</td><td>{tournamentNumber(row.goalsAgainst)}</td><td>{tournamentNumber(row.goalDifference)}</td><td><strong>{tournamentNumber(row.points)}</strong></td></tr>)}</tbody></table></div>
    <footer><span>Revisión {tournamentNumber(snapshot.sourceRevision)}</span><span>{tournamentArray(snapshot.criteria).map((item) => String(item).replaceAll("_", " ")).join(" · ") || "Desempates pendientes"}</span><span>{formatDateTime(snapshot.generatedAt)}</span></footer>
  </section>;
}

function TeamsView({ data, groups }: { data: TournamentJson; groups: TournamentJson[] }) {
  const journeys = tournamentArray(data.teamJourneys).map(tournamentRecord);
  return <>
    <section className={styles.teamGrid}>{groups.map((group) => <article key={tournamentText(group.id)}><header><span>Grupo</span><strong>{tournamentText(group.name)}</strong></header>{tournamentArray(group.entries).map((entry) => { const item = tournamentRecord(entry); const journey = journeys.find((value) => tournamentText(value.entryId) === tournamentText(item.entryId)); return <div key={tournamentText(item.entryId)}><span className={styles.initials}>{tournamentText(item.name).slice(0, 2).toUpperCase()}</span><strong>{tournamentText(item.name)}</strong><small>{journey ? `${tournamentNumber(tournamentRecord(journey.standing).points)} pts · ${tournamentText(journey.qualificationStatus).replaceAll("_", " ")}` : "Participante"}</small></div>; })}</article>)}</section>
    {journeys.length ? <section className={styles.journeyGrid}>{journeys.map((journey) => {
      const next = tournamentRecord(tournamentArray(journey.nextMatches)[0]);
      const attendance = tournamentRecord(next.attendance);
      const squad = tournamentRecord(next.squad);
      const referee = tournamentRecord(next.referee);
      return <article className={styles.journeyCard} key={tournamentText(journey.entryId)}>
        <SectionHeader eyebrow="Mi equipo" title={tournamentText(journey.teamName)} />
        <dl><Info label="Grupo" value={groupName(groups, journey.groupId)} /><Info label="Posición" value={tournamentNumber(tournamentRecord(journey.standing).position) || "–"} /><Info label="Clasificación" value={tournamentText(journey.qualificationStatus, "PROVISIONAL").replaceAll("_", " ")} /></dl>
        {tournamentText(next.contextId) ? <><strong>Próximo partido · {formatDateTime(next.startsAt)}</strong><dl><Info label="Asistencia" value={`${tournamentNumber(attendance.going)} voy · ${tournamentNumber(attendance.doubt)} duda`} /><Info label="Convocatoria" value={tournamentText(squad.status).replaceAll("_", " ")} /><Info label="Árbitro" value={tournamentText(referee.displayName, tournamentText(referee.status, "Sin asignar")).replaceAll("_", " ")} /><Info label="Sanciones" value={tournamentArray(next.sanctions).length} /><Info label="Incidencias" value={tournamentArray(next.incidents).length} /></dl></> : <p className={styles.muted}>No quedan partidos programados.</p>}
      </article>;
    })}</section> : null}
  </>;
}

function OperationalList({ empty, matches, mode }: { empty: string; matches: TournamentJson[]; mode: "discipline" | "incidents" | "referees" }) {
  const rows = matches.filter((match) => mode === "discipline"
    ? tournamentNumber(match.disciplineEventCount) > 0
    : mode === "referees" ? Object.keys(tournamentRecord(match.referee)).length > 0
      : Object.keys(tournamentRecord(match.incident)).length > 0);
  return <section className={styles.operationalList}>{rows.map((match) => { const referee = tournamentRecord(match.referee); const incident = tournamentRecord(match.incident); return <article key={tournamentText(match.id)}><div><strong>{tournamentText(tournamentRecord(match.home).name)} vs {tournamentText(tournamentRecord(match.away).name)}</strong><small>J{tournamentNumber(match.roundNumber)} · {formatDateTime(match.startsAt)}</small></div><b>{mode === "discipline" ? `${tournamentNumber(match.disciplineEventCount)} eventos` : mode === "referees" ? tournamentText(referee.displayName) : tournamentText(incident.status).replaceAll("_", " ")}</b></article>; })}{!rows.length ? <p className={styles.empty}>{empty}</p> : null}</section>;
}

function RulesView({ data }: { data: TournamentJson }) {
  const rules = tournamentRecord(data.rules);
  const schedule = tournamentRecord(rules.schedulePolicy);
  const qualification = tournamentRecord(rules.qualificationPolicy);
  return <section className={styles.ruleGrid}><div className={styles.panel}><SectionHeader eyebrow="Calendario" title="Round-robin R4B" /><dl><Info label="Vueltas" value={tournamentNumber(schedule.legs)} /><Info label="Duración" value={`${tournamentNumber(schedule.matchDurationMinutes)} min`} /><Info label="Descanso" value={`${tournamentNumber(schedule.minimumRestMinutes)} min`} /><Info label="Sede obligatoria" value={tournamentBoolean(schedule.venueRequired) ? "Sí" : "No"} /></dl></div><div className={styles.panel}><SectionHeader eyebrow="Clasificación" title={tournamentText(qualification.kind).replaceAll("_", " ")} /><dl><Info label="Directos por grupo" value={tournamentNumber(qualification.directQualifiersPerGroup)} /><Info label="Extras" value={tournamentNumber(qualification.extraQualifierCount)} /><Info label="Grupos iguales" value={tournamentBoolean(qualification.equalGroupSizeRequired) ? "Obligatorio" : "No"} /><Info label="Empate final" value={tournamentText(qualification.tieResolutionPolicy).replaceAll("_", " ")} /></dl></div><div className={styles.panel}><SectionHeader eyebrow="Linaje" title="RuleRevision congelada" /><p className={styles.hash}>{tournamentText(rules.ruleRevisionId)}<br />{tournamentText(rules.checksum)}</p></div></section>;
}

function BracketView({ bracket, busy, competitionId, data, groups, knockout, knockoutCommand, qualification }: {
  bracket: TournamentJson;
  busy: boolean;
  competitionId: string;
  data: TournamentJson;
  groups: TournamentJson[];
  knockout: TournamentJson;
  knockoutCommand: (options: TournamentKnockoutCommandOptions) => Promise<boolean>;
  qualification: TournamentJson;
}) {
  if (tournamentText(knockout.kind) === "TournamentBracketView") {
    return <TournamentKnockoutBracket busy={busy} command={knockoutCommand} competitionId={competitionId} data={knockout} />;
  }
  const slots = tournamentArray(bracket.slots).map(tournamentRecord);
  const groupEntries = new Map(groups.flatMap((group) => tournamentArray(group.entries).map((entry) => { const item = tournamentRecord(entry); return [tournamentText(item.entryId), tournamentText(item.name)] as const; })));
  if (!tournamentText(bracket.id)) return <section className={styles.empty}>La plantilla del cuadro aparecerá después de publicar la clasificación final.</section>;
  const matches = [...new Set(slots.map((slot) => tournamentNumber(slot.matchNumber)))];
  return <>
    <section className={styles.bracketHeader}><div><span>Qualification {tournamentText(qualification.status, "pendiente")}</span><h2>Cuadro inicial</h2></div>{statusChip(bracket.status)}</section>
    <section className={styles.bracket}>{matches.map((matchNumber) => <article key={matchNumber}><header>Partido {matchNumber}</header>{slots.filter((slot) => tournamentNumber(slot.matchNumber) === matchNumber).map((slot) => <div key={tournamentText(slot.key)}><span>{tournamentText(slot.side)}</span><strong>{groupEntries.get(tournamentText(slot.resolvedEntryId)) || `${groupName(groups, slot.sourceGroupId)} · ${tournamentNumber(slot.sourcePosition)}º`}</strong><small>{tournamentText(slot.sourceKind).replaceAll("_", " ")}</small></div>)}</article>)}</section>
    {tournamentText(bracket.status) === "PUBLISHED" && tournamentBoolean(tournamentRecord(data.permissions).manageBracket) && tournamentText(tournamentRecord(data.groupStage).completedAt) ? <ResponsiveActionBar><button disabled={busy} onClick={() => void knockoutCommand({ action: "bracket.activate", payload: { reason: "Activar cuadro desde Tournament Hub" } })} type="button">Activar eliminatorias</button></ResponsiveActionBar> : null}
    <ProductFeedback tone="info">{tournamentText(bracket.message, "Cuadro preparado. La fase eliminatoria se activará en la siguiente fase.")}</ProductFeedback>
  </>;
}

function Info({ label, value }: { label: string; value: ReactNode }) {
  return <div><dt>{label}</dt><dd>{value}</dd></div>;
}

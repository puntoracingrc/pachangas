"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import {
  leagueSchedulingCacheVersion,
  leagueSchedulingRealtimeTable,
  scheduleActionLabel,
  scheduleArray,
  scheduleNumber,
  scheduleRecord,
  scheduleStatusTone,
  scheduleText,
  type LeagueSchedulingAction,
  type LeagueSchedulingJson,
} from "../league-scheduling-contract";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import {
  GamePageHeader,
  MetricTile,
  ProductFeedback,
  ResponsiveActionBar,
  SectionHeader,
  StatusChip,
} from "./official-ui-v2-primitives";
import styles from "./league-scheduling-client.module.css";

export type LeagueSchedulingSurface = "public" | "round" | "team" | "workbench";

type Props = {
  competitionId?: string;
  embedded?: boolean;
  entryId?: string;
  planId?: string;
  previewData?: LeagueSchedulingJson | null;
  roundId?: string;
  surface: LeagueSchedulingSurface;
};

type Command = (
  action: LeagueSchedulingAction,
  expectedRevision: number,
  payload?: LeagueSchedulingJson,
  aggregateOverride?: string,
) => Promise<void>;

function endpointFor({ competitionId, entryId, planId, roundId, surface }: Props) {
  if (surface === "public") return `/api/competitions/scheduling/public/${competitionId ?? ""}`;
  if (surface === "round") return `/api/competitions/scheduling/round/${roundId ?? ""}`;
  if (surface === "team") return `/api/competitions/scheduling/team/${entryId ?? ""}`;
  if (planId) return `/api/competitions/scheduling/workbench/${planId}`;
  return `/api/competitions/scheduling/workbench/competition/${competitionId ?? ""}`;
}

function identityFor(props: Props) {
  return props.planId || props.roundId || props.entryId || props.competitionId || "unbound";
}

function cacheKey(surface: LeagueSchedulingSurface, identity: string, userId: string) {
  return `pachangas-league-scheduling-read-v1:${surface}:${identity}:${userId || "public"}`;
}

function readCache(key: string) {
  try {
    const envelope = scheduleRecord(JSON.parse(window.localStorage.getItem(key) ?? "null"));
    if (scheduleNumber(envelope.version) !== leagueSchedulingCacheVersion) return null;
    return scheduleRecord(envelope.data);
  } catch {
    return null;
  }
}

function writeCache(key: string, data: LeagueSchedulingJson) {
  try {
    window.localStorage.setItem(key, JSON.stringify({
      data,
      storedAt: new Date().toISOString(),
      version: leagueSchedulingCacheVersion,
    }));
  } catch {
    // The cache is optional and never authoritative.
  }
}

function dateLabel(value: unknown, timezone = "Europe/Madrid") {
  const parsed = new Date(scheduleText(value));
  if (Number.isNaN(parsed.getTime())) return "Sin horario";
  return new Intl.DateTimeFormat("es-ES", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: timezone || "Europe/Madrid",
  }).format(parsed);
}

function status(value: unknown) {
  const label = scheduleText(value).replaceAll("_", " ") || "sin estado";
  return <StatusChip tone={scheduleStatusTone(value)}>{label}</StatusChip>;
}

function titleFor(surface: LeagueSchedulingSurface) {
  if (surface === "workbench") return "Mesa del calendario";
  if (surface === "team") return "Mi calendario de Liga";
  if (surface === "round") return "Detalle de jornada";
  return "Calendario de Liga";
}

function invalidationMatches(props: Props, value: unknown) {
  const row = scheduleRecord(scheduleRecord(value).new);
  const entityType = scheduleText(row.entity_type);
  if (entityType === "league_scheduling_flags") return true;
  if (props.competitionId && scheduleText(row.competition_id) === props.competitionId) return true;
  const entityId = scheduleText(row.entity_id);
  if (props.planId && entityType === "league_schedule" && entityId === props.planId) return true;
  if (props.roundId && entityType === "league_round" && entityId === props.roundId) return true;
  if (props.entryId && entityType === "league_team_calendar" && entityId === props.entryId) return true;
  return false;
}

function roundsFor(data: LeagueSchedulingJson, surface: LeagueSchedulingSurface): LeagueSchedulingJson[] {
  if (surface === "round") return [scheduleRecord(data.round)];
  if (surface === "team") {
    const fixtures = scheduleArray(data.fixtures);
    return [...new Set(fixtures.map((item) => scheduleNumber(item.roundNumber)))].map((number) => scheduleRecord({
      id: `round-${number}`,
      name: scheduleText(fixtures.find((item) => scheduleNumber(item.roundNumber) === number)?.roundName) || `Jornada ${number}`,
      number,
      status: "published",
    }));
  }
  return scheduleArray(data.rounds);
}

function fixturesFor(data: LeagueSchedulingJson, surface: LeagueSchedulingSurface, roundNumber: number) {
  if (surface === "public") {
    const round = scheduleArray(data.rounds).find((item) => scheduleNumber(item.number) === roundNumber);
    return scheduleArray(round?.fixtures);
  }
  const source = surface === "round" ? scheduleArray(data.fixtures)
    : surface === "team" ? scheduleArray(data.fixtures)
      : scheduleArray(data.items);
  return source.filter((item) => {
    if (surface === "round") return true;
    return scheduleNumber(item.roundNumber) === roundNumber;
  });
}

function fixtureTeams(item: LeagueSchedulingJson, surface: LeagueSchedulingSurface) {
  if (surface === "team") {
    const side = scheduleText(item.side);
    const own = side === "HOME" ? "Mi equipo" : scheduleText(item.rivalTeam);
    const rival = side === "HOME" ? scheduleText(item.rivalTeam) : "Mi equipo";
    return { away: rival, home: own };
  }
  return {
    away: scheduleText(item.awayTeam) || scheduleText(item.rivalTeam) || "Visitante",
    home: scheduleText(item.homeTeam) || "Local",
  };
}

export function LeagueSchedulingClient(props: Props) {
  const {
    competitionId,
    embedded = false,
    entryId,
    planId,
    previewData = null,
    roundId,
    surface,
  } = props;
  const endpoint = endpointFor(props);
  const identity = identityFor(props);
  const [data, setData] = useState<LeagueSchedulingJson | null>(previewData);
  const [accessToken, setAccessToken] = useState("");
  const [userId, setUserId] = useState("");
  const [loading, setLoading] = useState(!previewData);
  const [cached, setCached] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(previewData ? "Escenario visual aislado" : "");
  const [selectedRound, setSelectedRound] = useState(0);
  const [selectedItemId, setSelectedItemId] = useState("");
  const [portraitDetailOpen, setPortraitDetailOpen] = useState(false);
  const [toolsOpen, setToolsOpen] = useState(false);
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const loadCanonical = useCallback(async (token: string, actorId: string, source: "initial" | "mutation" | "realtime") => {
    try {
      const response = await fetch(endpoint, {
        cache: "no-store",
        headers: token ? { Authorization: `Bearer ${token}` } : undefined,
      });
      const body = scheduleRecord(await response.json());
      if (!response.ok) throw new Error(scheduleText(body.message) || "No se pudo recuperar el calendario canónico.");
      setData(body);
      setCached(false);
      writeCache(cacheKey(surface, identity, actorId), body);
      if (source === "realtime") setMessage("Calendario actualizado desde el servidor");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "No se pudo recuperar el calendario canónico.");
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
        setMessage("Inicia sesión para consultar este calendario.");
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
      channel = supabase.channel(`league-scheduling:${surface}:${identity}`)
        .on("postgres_changes", {
          event: "INSERT",
          schema: "public",
          table: leagueSchedulingRealtimeTable,
        }, (payload) => {
          if (!invalidationMatches({ competitionId, entryId, planId, roundId, surface }, payload)) return;
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
  }, [competitionId, entryId, identity, loadCanonical, planId, previewData, roundId, surface]);

  const rounds = useMemo(() => data ? roundsFor(data, surface) : [], [data, surface]);
  const effectiveRound = rounds.some((round) => scheduleNumber(round.number) === selectedRound)
    ? selectedRound
    : scheduleNumber(rounds[0]?.number);
  const fixtures = useMemo(
    () => data ? fixturesFor(data, surface, effectiveRound) : [],
    [data, effectiveRound, surface],
  );
  const selectedItem = scheduleRecord(fixtures.find((item) => (
    scheduleText(item.id) || scheduleText(item.itemId) || scheduleText(item.canonicalMatchId)
  ) === selectedItemId) ?? fixtures[0]);

  const command: Command = useCallback(async (action, expectedRevision, payload = {}, aggregateOverride = "") => {
    if (previewData) {
      setMessage("Escenario visual: no se ha enviado ninguna escritura.");
      return;
    }
    const plan = scheduleRecord(data?.plan);
    const aggregateId = aggregateOverride || scheduleText(plan.id) || planId || "";
    if (!accessToken || !aggregateId) {
      setMessage("No hay una sesión y un plan válidos para esta operación.");
      return;
    }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:league-scheduling-command", "/api/competitions/scheduling/command", {
        body: JSON.stringify({
          action,
          aggregateId,
          expectedRevision,
          operationId: pending.current.id,
          payload,
        }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = scheduleRecord(await response.json());
      if (!response.ok) throw new Error(scheduleText(body.message) || "Operación no confirmada.");
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL");
      await loadCanonical(accessToken, userId, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail)
        ? "La revisión cambió. Se ha recuperado el estado oficial."
        : detail);
      if (/STALE_REVISION|revision/i.test(detail)) await loadCanonical(accessToken, userId, "mutation");
    } finally {
      setBusy(false);
    }
  }, [accessToken, data, loadCanonical, planId, previewData, userId]);

  const context = {
    detail: previewData ? "Laboratorio local" : cached ? "Copia local revalidándose" : "Estado canónico",
    eyebrow: "Competiciones",
    status: previewData ? "Solo visual" : loading ? "Sincronizando" : "Servidor",
    title: titleFor(surface),
  };
  const plan = scheduleRecord(data?.plan);
  const revision = scheduleRecord(data?.revision);
  const quality = scheduleRecord(data?.quality);
  const counts = scheduleRecord(data?.counts);
  const competition = scheduleRecord(data?.competition);
  const organizerAvailable = scheduleText(plan.status) !== "published"
    && (!Array.isArray(data?.nextValidActions) || data.nextValidActions.length > 0);

  const content = <main className={styles.page} data-mobile-tab="equipo" data-scheduling-surface={surface}>
      <GamePageHeader
        eyebrow={surface === "workbench" ? "League Scheduling R4B" : scheduleText(competition.name) || "League Scheduling"}
        title={titleFor(surface)}
      />
      {message ? <ProductFeedback tone={/confirmado|actualizado/i.test(message) ? "success" : /no |error|stale|rechaz/i.test(message) ? "warning" : "info"}>{message}</ProductFeedback> : null}
      {loading && !data ? <section className={styles.empty}><strong>Recuperando calendario oficial</strong></section> : null}
      {!loading && !data ? <section className={styles.empty}><strong>Calendario no disponible</strong></section> : null}
      {data ? <>
        {surface === "workbench" && !scheduleText(plan.id) ? <SetupPlanControls busy={busy} command={command} data={data} /> : null}
        <section className={styles.metrics} aria-label="Resumen del calendario">
          <MetricTile label="Jornadas" value={rounds.length || scheduleNumber(counts.rounds)} />
          <MetricTile label="Partidos" value={surface === "public" ? rounds.reduce((total, round) => total + scheduleArray(round.fixtures).length, 0) : scheduleNumber(counts.items) || scheduleArray(data.fixtures).length} />
          <MetricTile label="Calidad" value={quality.softScore == null ? "—" : `${scheduleNumber(quality.softScore).toFixed(0)}%`} />
          <MetricTile label="Estado" value={status(scheduleText(plan.status) || scheduleText(revision.status) || scheduleText(scheduleRecord(data.round).status) || "published")} />
        </section>

        {scheduleText(plan.id) || surface !== "workbench" ? <section className={styles.workbench}>
          <nav className={styles.roundRail} aria-label="Jornadas">
            <span>Jornadas</span>
            <div>{rounds.map((round) => {
              const number = scheduleNumber(round.number);
              return <button
                aria-current={number === effectiveRound ? "page" : undefined}
                key={scheduleText(round.id) || number}
                onClick={() => {
                  setSelectedRound(number);
                  setPortraitDetailOpen(false);
                }}
                type="button"
              ><b>{number}</b><small>{scheduleText(round.name) || `Jornada ${number}`}</small></button>;
            })}</div>
          </nav>

          <section className={styles.fixtureColumn}>
            <SectionHeader eyebrow={`Jornada ${effectiveRound || 1}`} title={scheduleText(rounds.find((round) => scheduleNumber(round.number) === effectiveRound)?.name) || `Jornada ${effectiveRound || 1}`} />
            <div className={styles.fixtureList}>{fixtures.map((item) => {
              const id = scheduleText(item.id) || scheduleText(item.itemId) || scheduleText(item.canonicalMatchId);
              const teams = fixtureTeams(item, surface);
              return <button
                aria-current={id === selectedItemId ? "true" : undefined}
                className={styles.fixture}
                key={id || `${teams.home}-${teams.away}`}
                onClick={() => {
                  setSelectedItemId(id);
                  setPortraitDetailOpen(true);
                }}
                type="button"
              >
                <span><strong>{teams.home}</strong><i>VS</i><strong>{teams.away}</strong></span>
                <small>{dateLabel(item.startsAt, scheduleText(item.timezone))}</small>
                <em>{scheduleText(item.venueLabel) || (scheduleText(item.venueStatus) === "TBD" ? "Sede pendiente" : "Sin sede")}</em>
              </button>;
            })}{!fixtures.length ? <div className={styles.empty}>No hay partidos en esta jornada.</div> : null}</div>
          </section>

          <aside className={styles.detailPanel}>
            <SectionHeader eyebrow="Detalle" title={selectedItemId ? "Partido seleccionado" : "Resumen"} />
            {Object.keys(selectedItem).length ? <FixtureDetail
              command={command}
              data={data}
              item={selectedItem}
              preview={Boolean(previewData)}
              surface={surface}
            /> : <QualityDetail quality={quality} />}
            <ConflictSummary conflicts={scheduleArray(data.conflicts)} />
          </aside>
        </section> : null}

        {Object.keys(selectedItem).length ? <>
          <button
            className={styles.portraitDetailAction}
            onClick={() => setPortraitDetailOpen(true)}
            type="button"
          >Ver detalle</button>
          <div
            className={styles.portraitDetailBackdrop}
            data-open={portraitDetailOpen ? "true" : "false"}
            onClick={() => setPortraitDetailOpen(false)}
            role="presentation"
          >
            <section
              aria-label="Detalle del partido"
              aria-modal="true"
              className={styles.portraitDetailDrawer}
              onClick={(event) => event.stopPropagation()}
              role="dialog"
            >
              <header className={styles.drawerHeader}>
                <SectionHeader eyebrow="Detalle" title="Partido seleccionado" />
                <button aria-label="Cerrar detalle" onClick={() => setPortraitDetailOpen(false)} type="button">Cerrar</button>
              </header>
              <FixtureDetail
                command={command}
                data={data}
                item={selectedItem}
                preview={Boolean(previewData)}
                surface={surface}
              />
              <ConflictSummary conflicts={scheduleArray(data.conflicts)} />
            </section>
          </div>
        </> : null}

        {surface === "workbench" && scheduleText(plan.id) && organizerAvailable ? <>
          <button
            aria-expanded={toolsOpen}
            className={styles.landscapeToolsToggle}
            onClick={() => setToolsOpen((open) => !open)}
            type="button"
          >{toolsOpen ? "Cerrar herramientas" : "Herramientas"}</button>
          <OrganizerControls
            busy={busy}
            command={command}
            data={data}
            open={toolsOpen}
            preview={Boolean(previewData)}
          />
        </> : null}
      </> : null}
    </main>;
  return embedded ? content : <OfficialProductShellV2 active="equipo" context={context}>{content}</OfficialProductShellV2>;
}

function ConflictSummary({ conflicts }: { conflicts: LeagueSchedulingJson[] }) {
  if (!conflicts.length) return <p className={styles.noConflicts}>Sin conflictos duros abiertos</p>;
  return <section className={styles.conflicts} aria-label="Conflictos del calendario">
    <strong>{conflicts.length} conflictos</strong>
    {conflicts.slice(0, 5).map((conflict, index) => <div key={scheduleText(conflict.id) || `${scheduleText(conflict.type)}-${index}`}>
      <b>{scheduleText(conflict.type).replaceAll("_", " ")}</b>
      <span>{scheduleText(conflict.message) || scheduleText(conflict.detail) || "Requiere corrección antes de publicar"}</span>
    </div>)}
  </section>;
}

function SetupPlanControls({ busy, command, data }: {
  busy: boolean;
  command: Command;
  data: LeagueSchedulingJson;
}) {
  const setup = scheduleRecord(data.setup);
  const candidates = scheduleArray(setup.candidates);
  const [candidateId, setCandidateId] = useState(scheduleText(candidates[0]?.stageId));
  const candidate = candidates.find((item) => scheduleText(item.stageId) === candidateId) ?? candidates[0];
  return <section className={styles.setupPanel}>
    <SectionHeader eyebrow="Primer paso" title="Crear plan de calendario" />
    {candidate ? <>
      <label>Fase<select value={scheduleText(candidate.stageId)} onChange={(event) => setCandidateId(event.target.value)}>
        {candidates.map((item) => <option key={scheduleText(item.stageId)} value={scheduleText(item.stageId)}>
          {scheduleText(item.editionName)} · {scheduleText(item.stageName)} · {scheduleText(item.categoryName)}
        </option>)}
      </select></label>
      <dl>
        <div><dt>Formato</dt><dd>{scheduleText(candidate.stageType).replaceAll("_", " ")}</dd></div>
        <div><dt>Vueltas</dt><dd>{scheduleNumber(candidate.legs)}</dd></div>
        <div><dt>Estado</dt><dd>{status(candidate.editionStatus)}</dd></div>
      </dl>
      <button disabled={busy} type="button" onClick={() => void command(
        "schedule_plan.create",
        scheduleNumber(candidate.stageRevision),
        {
          categoryId: scheduleText(candidate.categoryId),
          divisionId: scheduleText(candidate.divisionId),
          groupId: scheduleText(candidate.groupId),
          legs: scheduleNumber(candidate.legs),
          reason: "Creación del plan de calendario",
          ruleRevisionId: scheduleText(candidate.ruleRevisionId),
        },
        scheduleText(candidate.stageId),
      )}>Crear plan autoritativo</button>
    </> : <p>No hay una edición cerrada y compatible preparada para generar calendario.</p>}
  </section>;
}

function FixtureDetail({ command, data, item, preview, surface }: {
  command: Command;
  data: LeagueSchedulingJson;
  item: LeagueSchedulingJson;
  preview: boolean;
  surface: LeagueSchedulingSurface;
}) {
  const plan = scheduleRecord(data.plan);
  const teams = fixtureTeams(item, surface);
  const slots = scheduleArray(data.slots).filter((slot) => scheduleText(slot.status) === "available");
  const [slotId, setSlotId] = useState("");
  const canEdit = surface === "workbench" && scheduleText(plan.status) !== "published";
  const canonicalMatchId = scheduleText(item.canonicalMatchId);
  const competitionId = scheduleText(data.competitionId)
    || scheduleText(scheduleRecord(data.competition).id)
    || scheduleText(plan.competitionId);
  return <div className={styles.detailBody}>
    <div className={styles.versus}><strong>{teams.home}</strong><span>VS</span><strong>{teams.away}</strong></div>
    <dl>
      <div><dt>Inicio</dt><dd>{dateLabel(item.startsAt, scheduleText(item.timezone))}</dd></div>
      <div><dt>Sede</dt><dd>{scheduleText(item.venueLabel) || "Pendiente"}</dd></div>
      <div><dt>Estado</dt><dd>{status(item.status)}</dd></div>
      <div><dt>Zona</dt><dd>{scheduleText(item.timezone) || "Europe/Madrid"}</dd></div>
    </dl>
    {canonicalMatchId && competitionId ? <Link className={styles.openMatchLink} href={`/competiciones/${competitionId}/partidos/${canonicalMatchId}`}>Abrir operación del partido</Link> : null}
    {canEdit ? <div className={styles.inlineControls}>
      <label>Nuevo slot<select value={slotId} onChange={(event) => setSlotId(event.target.value)}>
        <option value="">Seleccionar</option>
        {slots.map((slot) => <option key={scheduleText(slot.id)} value={scheduleText(slot.id)}>{dateLabel(slot.startsAt, scheduleText(slot.timezone))}</option>)}
      </select></label>
      <button disabled={!slotId} type="button" onClick={() => void command("schedule_item.move_slot", scheduleNumber(plan.revision), {
        itemId: scheduleText(item.id), reason: "Reasignación manual de slot", slotId,
      })}>Mover</button>
      <button type="button" onClick={() => void command("schedule_item.swap_home_away", scheduleNumber(plan.revision), {
        itemId: scheduleText(item.id), reason: "Invertir localía del pairing",
      })}>Invertir localía</button>
      {preview ? <small>Acciones aisladas</small> : null}
    </div> : null}
  </div>;
}

function QualityDetail({ quality }: { quality: LeagueSchedulingJson }) {
  const explanation = scheduleRecord(quality.explanation);
  const preferences = scheduleRecord(explanation.preferences);
  return <div className={styles.quality}>
    <strong>{quality.softScore == null ? "Sin cálculo" : `${scheduleNumber(quality.softScore).toFixed(1)} / 100`}</strong>
    <span>{scheduleNumber(quality.hardViolations)} conflictos duros</span>
    <span>{scheduleNumber(preferences.satisfied)} de {scheduleNumber(preferences.total)} preferencias completas</span>
    <span>Racha local {scheduleNumber(quality.maximumHomeStreak)} · visitante {scheduleNumber(quality.maximumAwayStreak)}</span>
  </div>;
}

function OrganizerControls({ busy, command, data, open, preview }: {
  busy: boolean;
  command: Command;
  data: LeagueSchedulingJson;
  open: boolean;
  preview: boolean;
}) {
  const plan = scheduleRecord(data.plan);
  const actions = Array.isArray(data.nextValidActions)
    ? data.nextValidActions.map((value) => scheduleText(value)).filter(Boolean)
    : [];
  const available = new Set(Array.isArray(data.nextValidActions)
    ? actions
    : ["schedule.generate", "schedule.validate", "schedule.publish"]);
  const revision = scheduleNumber(plan.revision);
  const [seed, setSeed] = useState(scheduleText(scheduleRecord(data.revision).seed) || "liga-2027");

  function submitPattern(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void command("schedule_slot.bulk_create", revision, {
      durationMinutes: Number(form.get("durationMinutes")),
      endDate: String(form.get("endDate") ?? ""),
      localTime: String(form.get("localTime") ?? ""),
      reason: "Patrón semanal de slots",
      resourceKey: String(form.get("resourceKey") ?? "").trim(),
      startDate: String(form.get("startDate") ?? ""),
      timezone: "Europe/Madrid",
      venueLabel: String(form.get("venueLabel") ?? "").trim(),
      weekdays: [Number(form.get("weekday"))],
    });
  }

  return <section className={styles.organizerControls} data-open={open ? "true" : "false"}>
    <section className={styles.commandPanel}>
      <SectionHeader eyebrow="Autoridad" title="Revisión del calendario" />
      <label>Semilla<input maxLength={160} value={seed} onChange={(event) => setSeed(event.target.value)} /></label>
      <ResponsiveActionBar>
        {(["schedule.generate", "schedule.regenerate", "schedule.validate", "schedule.publish", "schedule.cancel"] as LeagueSchedulingAction[]).map((action) => available.has(action) ? <button
          data-action={action}
          disabled={busy}
          key={action}
          onClick={() => void command(action, revision, action.includes("generate") ? { reason: scheduleActionLabel(action), seed } : { reason: scheduleActionLabel(action) })}
          type="button"
        >{scheduleActionLabel(action)}</button> : null)}
      </ResponsiveActionBar>
      {preview ? <small>Los controles no escriben fuera del laboratorio.</small> : null}
    </section>

    <form className={styles.slotBuilder} onSubmit={submitPattern}>
      <SectionHeader eyebrow="Disponibilidad" title="Patrón semanal" />
      <div>
        <label>Día<select defaultValue="6" name="weekday"><option value="1">Lunes</option><option value="5">Viernes</option><option value="6">Sábado</option><option value="7">Domingo</option></select></label>
        <label>Hora<input defaultValue="18:00" name="localTime" type="time" /></label>
        <label>Desde<input defaultValue="2027-02-06" name="startDate" type="date" /></label>
        <label>Hasta<input defaultValue="2027-04-24" name="endDate" type="date" /></label>
        <label>Minutos<input defaultValue="90" min="1" name="durationMinutes" type="number" /></label>
        <label>Sede<input defaultValue="Sede pendiente" name="venueLabel" /></label>
        <label>Recurso<input defaultValue="campo-1" name="resourceKey" /></label>
      </div>
      <button disabled={busy || !available.has("schedule_slot.bulk_create")} type="submit">Crear slots</button>
    </form>
  </section>;
}

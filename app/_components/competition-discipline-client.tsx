"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  disciplineActionLabel,
  disciplineArray,
  disciplineBoolean,
  competitionDisciplineCacheVersion as disciplineCacheVersion,
  disciplineCardLabel,
  disciplineFlagsEnabled,
  disciplineNumber,
  competitionDisciplineRealtimeTable as disciplineRealtimeTable,
  disciplineRecord,
  disciplineStatusTone,
  disciplineText,
  type CompetitionDisciplineAction,
  type CompetitionDisciplineJson,
} from "../competition-discipline-contract";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import { ProductState } from "./product-state";
import { GamePageHeader, MetricTile, ProductFeedback, SectionHeader, StatusChip } from "./official-ui-v2-primitives";
import styles from "./competition-discipline-client.module.css";

export type CompetitionDisciplineSurface = "desk" | "match" | "player" | "public";

type Props = {
  competitionId: string;
  embedded?: boolean;
  matchId?: string;
  playerId?: string;
  previewData?: CompetitionDisciplineJson | null;
  surface: CompetitionDisciplineSurface;
};

type Command = (
  action: CompetitionDisciplineAction,
  aggregateId: string,
  expectedRevision: number,
  payload?: CompetitionDisciplineJson,
) => Promise<void>;

function endpointFor(surface: CompetitionDisciplineSurface, competitionId: string, matchId: string, playerId: string) {
  if (surface === "match") return `/api/competitions/discipline/match/${competitionId}/${matchId}`;
  if (surface === "player") return `/api/competitions/discipline/player/${competitionId}/${playerId}`;
  if (surface === "public") return `/api/competitions/discipline/public/${competitionId}`;
  return `/api/competitions/discipline/competition/${competitionId}`;
}

function readCache(key: string) {
  try {
    const envelope = disciplineRecord(JSON.parse(window.localStorage.getItem(key) ?? "null"));
    if (disciplineNumber(envelope.version) !== disciplineCacheVersion) return null;
    if (Date.now() > disciplineNumber(envelope.expiresAt)) return null;
    return disciplineRecord(envelope.data);
  } catch {
    return null;
  }
}

function writeCache(key: string, data: CompetitionDisciplineJson, surface: CompetitionDisciplineSurface) {
  try {
    const final = surface === "public" && disciplineArray(data.sanctions).every((item) =>
      ["cancelled", "overturned", "served"].includes(disciplineText(item.status)));
    window.localStorage.setItem(key, JSON.stringify({
      data,
      expiresAt: Date.now() + (final ? 7 * 24 * 60 * 60 * 1000 : surface === "match" ? 5 * 60 * 1000 : 2 * 60 * 1000),
      serverSequence: disciplineNumber(disciplineRecord(data.health).latestServerSequence || data.serverSequence),
      storedAt: new Date().toISOString(),
      version: disciplineCacheVersion,
    }));
  } catch {
    // Optional read cache only. PostgreSQL remains authoritative.
  }
}

function invalidationMatches(
  competitionId: string,
  matchId: string,
  playerId: string,
  payload: { new?: Record<string, unknown> },
) {
  const row = disciplineRecord(payload.new);
  if (disciplineText(row.competition_id) !== competitionId) return false;
  const entityType = disciplineText(row.entity_type);
  const entityId = disciplineText(row.entity_id);
  if (!entityType.startsWith("competition_discipline")) return false;
  if (matchId && entityType.endsWith("_match")) return entityId === matchId;
  if (playerId && entityType.endsWith("_player")) return entityId === playerId;
  return true;
}

function Status({ value }: { value: unknown }) {
  return <StatusChip tone={disciplineStatusTone(value)}>{disciplineText(value).replaceAll("_", " ") || "pendiente"}</StatusChip>;
}

function playerName(item: CompetitionDisciplineJson) {
  return disciplineText(disciplineRecord(item.playerDisplay).displayName)
    || disciplineText(disciplineRecord(item.display).displayName)
    || "Jugador";
}

function CardMark({ code, visual }: { code: unknown; visual?: unknown }) {
  const tone = disciplineText(visual) || disciplineText(code).toLowerCase();
  return <span aria-label={disciplineCardLabel(code)} className={styles.cardMark} data-card-tone={tone} title={disciplineCardLabel(code)} />;
}

function Metrics({ data }: { data: CompetitionDisciplineJson }) {
  const health = disciplineRecord(data.health);
  return <div className={styles.metrics}>
    <MetricTile label="Eventos" value={disciplineArray(data.events).length} />
    <MetricTile label="Sanciones activas" value={disciplineNumber(health.activeSanctions)} />
    <MetricTile label="Apelaciones" value={disciplineNumber(health.pendingAppeals)} />
    <MetricTile label="Secuencia" value={disciplineNumber(health.latestServerSequence || data.serverSequence)} />
  </div>;
}

function EventEditor({ command, data, disabled, editing, onDone }: {
  command: Command;
  data: CompetitionDisciplineJson;
  disabled: boolean;
  editing: CompetitionDisciplineJson | null;
  onDone: () => void;
}) {
  const context = disciplineRecord(data.matchContext);
  const players = disciplineArray(data.matchPlayers);
  const cards = disciplineArray(disciplineRecord(data.ruleCatalog).cardTypes);
  const firstPlayerId = disciplineText(players[0]?.playerProfileId);
  const cardCodes = cards.map((item) => disciplineText(item.code));
  const firstCardCode = cardCodes[0] ?? "";
  const [player, setPlayer] = useState(() => disciplineText(editing?.playerProfileId) || firstPlayerId);
  const [card, setCard] = useState(() => {
    const editingCard = disciplineText(editing?.cardTypeCode);
    if (editingCard) return editingCard;
    return cardCodes.includes("YELLOW") ? "YELLOW" : firstCardCode;
  });
  const [minute, setMinute] = useState(() => editing?.minute == null ? "1" : String(disciplineNumber(editing.minute)));
  const [eventContext, setEventContext] = useState(() => disciplineText(editing?.context) || "in_match");
  const [summary, setSummary] = useState(() => disciplineText(editing?.publicSummary));
  const [reason, setReason] = useState("");
  const selectedPlayer = players.some((item) => disciplineText(item.playerProfileId) === player)
    ? player : firstPlayerId;
  const selectedCard = cardCodes.includes(card) ? card : firstCardCode;

  if (!disciplineBoolean(disciplineRecord(data.permissions).manage) || !Object.keys(context).length) return null;
  const submit = async () => {
    const commandRevision = disciplineNumber(data.revision);
    const payload = {
      cardTypeCode: selectedCard,
      context: eventContext,
      ...(eventContext === "in_match" && minute !== "" ? { minute: Number(minute) } : {}),
      playerProfileId: selectedPlayer,
      publicSummary: summary,
    };
    if (editing) {
      await command("event.correct", disciplineText(editing.id), commandRevision, {
        ...payload,
        correctionReason: reason || "Corrección administrativa documentada",
      });
      onDone();
    } else {
      await command("event.record", disciplineText(context.canonicalMatchId), commandRevision, payload);
    }
  };
  return <section className={styles.editor}>
    <SectionHeader eyebrow="Autoridad de competición" title={editing ? "Corregir sin borrar historial" : "Registrar tarjeta"} />
    <div className={styles.formGrid}>
      <label>Jugador<select onChange={(event) => setPlayer(event.target.value)} value={selectedPlayer}>{players.map((item) => <option key={disciplineText(item.playerProfileId)} value={disciplineText(item.playerProfileId)}>{disciplineText(item.displayName)} · {disciplineText(item.side)}</option>)}</select></label>
      <label>Tipo<select onChange={(event) => setCard(event.target.value)} value={selectedCard}>{cards.map((item) => <option key={disciplineText(item.code)} value={disciplineText(item.code)}>{disciplineText(item.label) || disciplineCardLabel(item.code)}</option>)}</select></label>
      <label>Contexto<select onChange={(event) => setEventContext(event.target.value)} value={eventContext}><option value="pre_match">Prepartido</option><option value="in_match">Durante el partido</option><option value="interval">Descanso</option><option value="post_match">Pospartido</option><option value="venue">Recinto</option></select></label>
      <label>Minuto<input disabled={eventContext !== "in_match"} max={300} min={0} onChange={(event) => setMinute(event.target.value)} type="number" value={minute} /></label>
      <label className={styles.wide}>Resumen público<input maxLength={500} onChange={(event) => setSummary(event.target.value)} value={summary} /></label>
      {editing ? <label className={styles.wide}>Motivo de corrección<input maxLength={1200} onChange={(event) => setReason(event.target.value)} value={reason} /></label> : null}
    </div>
    <div className={styles.actions}>{editing ? <button onClick={onDone} type="button">Cancelar</button> : null}<button className={styles.primary} disabled={disabled || !selectedPlayer || !selectedCard || (eventContext === "in_match" && minute === "")} onClick={() => void submit()} type="button">{editing ? "Confirmar corrección" : "Registrar"}</button></div>
  </section>;
}

function EventList({ command, data, disabled, onEdit, readOnly = false }: {
  command: Command;
  data: CompetitionDisciplineJson;
  disabled: boolean;
  onEdit: (item: CompetitionDisciplineJson) => void;
  readOnly?: boolean;
}) {
  const canManage = !readOnly && disciplineBoolean(disciplineRecord(data.permissions).manage);
  const events = disciplineArray(data.events);
  const commandRevision = disciplineNumber(data.revision);
  return <section className={styles.band}>
    <SectionHeader eyebrow="Match sheet" title="Hechos disciplinarios" />
    <div className={styles.eventRows}>{events.map((item) => <article key={disciplineText(item.id)}>
      <CardMark code={item.cardTypeCode} visual={item.visualType} />
      <span><strong>{playerName(item)}</strong><small>{disciplineText(item.context).replaceAll("_", " ")} · {item.minute == null ? "sin minuto" : `${disciplineNumber(item.minute)}'`}</small></span>
      <span><Status value={item.status} /><small>{disciplineText(item.publicSummary) || disciplineText(item.publicReasonCategory)}</small></span>
      {Object.keys(disciplineRecord(item.sanction)).length ? <span><strong>{disciplineNumber(disciplineRecord(item.sanction).remainingUnits)} {disciplineText(disciplineRecord(item.sanction).unitType).toLowerCase()}</strong><small>{disciplineText(disciplineRecord(item.sanction).status)}</small></span> : <span><small>Sin sanción derivada</small></span>}
      {canManage ? <div className={styles.actions}><button disabled={disabled} onClick={() => onEdit(item)} type="button">Corregir</button><button disabled={disabled || disciplineText(item.status) === "annulled"} onClick={() => void command("event.annul", disciplineText(item.id), commandRevision, { correctionReason: "Anulación administrativa documentada" })} type="button">Anular</button></div> : null}
    </article>)}{!events.length ? <p className={styles.empty}>No hay hechos disciplinarios para este filtro.</p> : null}</div>
  </section>;
}

function SanctionDesk({ command, data, disabled, readOnly = false }: { command: Command; data: CompetitionDisciplineJson; disabled: boolean; readOnly?: boolean }) {
  const permissions = disciplineRecord(data.permissions);
  const canReview = !readOnly && disciplineBoolean(permissions.review);
  const canManage = !readOnly && disciplineBoolean(permissions.manage);
  const appealsEnabled = !readOnly && disciplineBoolean(disciplineRecord(data.flags).appealsEnabled);
  const serviceEvents = disciplineArray(data.serviceEvents);
  const commandRevision = disciplineNumber(data.revision);
  const [units, setUnits] = useState("1");
  const [reason, setReason] = useState("");
  return <section className={styles.band}>
    <SectionHeader eyebrow="Regla activa" title="Sanciones y cumplimiento" />
    {canReview || canManage ? <div className={styles.deskInputs}><label>Unidades<input min={0} onChange={(event) => setUnits(event.target.value)} type="number" value={units} /></label><label>Motivo privado<input maxLength={4000} onChange={(event) => setReason(event.target.value)} value={reason} /></label></div> : null}
    <div className={styles.sanctionGrid}>{disciplineArray(data.sanctions).map((item) => {
      const proposal = disciplineRecord(item.proposal);
      const service = serviceEvents.find((event) => disciplineText(event.sanctionId) === disciplineText(item.id) && disciplineText(event.eventType) === "SERVED");
      return <article key={disciplineText(item.id)}><header><Status value={item.status} /><small>r{disciplineNumber(item.revision)}</small></header><strong>{disciplineNumber(item.remainingUnits)} {disciplineText(item.unitType).toLowerCase()}</strong><p>{disciplineText(item.publicSummary) || disciplineText(item.publicReasonCategory) || "Resolución disciplinaria"}</p>{Object.keys(proposal).length ? <small>Comité: {disciplineNumber(proposal.minimumUnits)}–{disciplineNumber(proposal.maximumUnits)} {disciplineText(proposal.unitType).toLowerCase()}</small> : null}<div className={styles.actions}>{canReview && Object.keys(proposal).length ? <><button disabled={disabled || !reason.trim()} onClick={() => void command("sanction.decide", disciplineText(item.id), commandRevision, { decisionOutcome: "FIXED_SANCTION", privateReason: reason, publicReasonCategory: disciplineText(item.publicReasonCategory) || "dismissal", units: Number(units) })} type="button">Confirmar</button><button disabled={disabled || !reason.trim()} onClick={() => void command("sanction.decide", disciplineText(item.id), commandRevision, { decisionOutcome: "NO_SANCTION", privateReason: reason, publicReasonCategory: "administrative" })} type="button">Sin sanción</button></> : null}{canManage && ["active", "provisional"].includes(disciplineText(item.status)) ? <button disabled={disabled} onClick={() => void command("service.record", disciplineText(item.id), commandRevision)} type="button">Registrar siguiente cumplimiento</button> : null}{canReview && service ? <button disabled={disabled || !reason.trim()} onClick={() => void command("service.reverse", disciplineText(item.id), commandRevision, { privateReason: reason, serviceEventId: disciplineText(service.id) })} type="button">Revertir</button> : null}{appealsEnabled && disciplineBoolean(item.canAppeal) && ["active", "provisional"].includes(disciplineText(item.status)) ? <button disabled={disabled || !reason.trim()} onClick={() => void command("appeal.submit", disciplineText(item.id), commandRevision, { statement: reason })} type="button">Apelar</button> : null}</div></article>;
    })}{!disciplineArray(data.sanctions).length ? <p className={styles.empty}>No hay sanciones derivadas.</p> : null}</div>
  </section>;
}

function AppealDesk({ command, data, disabled }: { command: Command; data: CompetitionDisciplineJson; disabled: boolean }) {
  const canManage = disciplineBoolean(disciplineRecord(data.permissions).manageAppeals);
  const commandRevision = disciplineNumber(data.revision);
  const [reason, setReason] = useState("");
  const [modifiedUnits, setModifiedUnits] = useState("0");
  return <section className={styles.band}><SectionHeader eyebrow="Plazos de servidor" title="Apelaciones" /><div className={styles.appealRows}>{disciplineArray(data.appeals).map((item) => <article key={disciplineText(item.id)}><span><Status value={item.status} /><small>Hasta {new Date(disciplineText(item.deadlineAt)).toLocaleString("es-ES")}</small></span>{canManage ? <><input maxLength={4000} onChange={(event) => setReason(event.target.value)} placeholder="Motivo de resolución" value={reason} />{disciplineText(item.status) === "under_review" ? <input aria-label="Unidades modificadas" min={0} onChange={(event) => setModifiedUnits(event.target.value)} type="number" value={modifiedUnits} /> : null}<div className={styles.actions}>{disciplineText(item.status) === "submitted" ? <><button disabled={disabled || !reason.trim()} onClick={() => void command("appeal.transition", disciplineText(item.id), commandRevision, { privateReason: reason, status: "admissible" })} type="button">Admitir</button><button disabled={disabled || !reason.trim()} onClick={() => void command("appeal.transition", disciplineText(item.id), commandRevision, { privateReason: reason, status: "inadmissible" })} type="button">Inadmitir</button></> : null}{disciplineText(item.status) === "admissible" ? <button disabled={disabled || !reason.trim()} onClick={() => void command("appeal.transition", disciplineText(item.id), commandRevision, { privateReason: reason, status: "under_review" })} type="button">Revisar</button> : null}{disciplineText(item.status) === "under_review" ? <><button disabled={disabled || !reason.trim()} onClick={() => void command("appeal.transition", disciplineText(item.id), commandRevision, { privateReason: reason, status: "upheld" })} type="button">Confirmar</button><button disabled={disabled || !reason.trim()} onClick={() => void command("appeal.transition", disciplineText(item.id), commandRevision, { modifiedUnits: Number(modifiedUnits), privateReason: reason, status: "modified" })} type="button">Modificar</button><button disabled={disabled || !reason.trim()} onClick={() => void command("appeal.transition", disciplineText(item.id), commandRevision, { privateReason: reason, status: "overturned" })} type="button">Revocar</button></> : null}</div></> : null}{disciplineBoolean(item.canWithdraw) ? <button disabled={disabled} onClick={() => void command("appeal.withdraw", disciplineText(item.id), commandRevision)} type="button">Retirar apelación</button> : null}</article>)}{!disciplineArray(data.appeals).length ? <p className={styles.empty}>No hay apelaciones visibles.</p> : null}</div></section>;
}

function PlayerStates({ competitionId, data, preview = false }: { competitionId: string; data: CompetitionDisciplineJson; preview?: boolean }) {
  return <section className={styles.band}><SectionHeader eyebrow="Elegibilidad" title="Estado de jugadores" /><div className={styles.playerGrid}>{disciplineArray(data.playerStates).map((item) => {
    const unavailable = ["active", "blocked", "provisional", "suspended"].includes(disciplineText(item.status).toLowerCase());
    const content = <><span><strong>{playerName(item)}</strong><Status value={item.status} /></span><small>{unavailable ? "No disponible por sanción · " : ""}{disciplineNumber(item.remainingUnits)} {disciplineText(item.unitType).toLowerCase()} pendientes</small><div>{Object.entries(disciplineRecord(item.cards)).map(([card, value]) => <em key={card}><CardMark code={card} />{disciplineNumber(disciplineRecord(value).events)}</em>)}</div></>;
    return preview
      ? <div className={styles.playerState} key={disciplineText(item.id)}>{content}</div>
      : <Link href={`/competiciones/${competitionId}/jugadores/${disciplineText(item.playerProfileId)}/disciplina`} key={disciplineText(item.id)}>{content}</Link>;
  })}{!disciplineArray(data.playerStates).length ? <p className={styles.empty}>Aún no hay estados materializados.</p> : null}</div></section>;
}

export function CompetitionDisciplineClient({ competitionId, embedded = false, matchId = "", playerId = "", previewData = null, surface }: Props) {
  const endpoint = endpointFor(surface, competitionId, matchId, playerId);
  const identity = matchId || playerId || competitionId;
  const [data, setData] = useState<CompetitionDisciplineJson | null>(previewData);
  const [accessToken, setAccessToken] = useState("");
  const [actorId, setActorId] = useState("");
  const [loading, setLoading] = useState(!previewData);
  const [cached, setCached] = useState(false);
  const [online, setOnline] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(previewData ? "Escenario visual de solo lectura" : "");
  const [editing, setEditing] = useState<CompetitionDisciplineJson | null>(null);
  const pending = useRef<{ id: string; key: string } | null>(null);
  const realtimeTimer = useRef<number | null>(null);

  const loadCanonical = useCallback(async (token: string, userId: string, source: "initial" | "mutation" | "realtime") => {
    const key = `pachangas-competition-discipline-read-v1:${surface}:${competitionId}:${identity}:${userId || "public"}`;
    try {
      const response = await fetch(endpoint, { cache: "no-store", headers: token ? { Authorization: `Bearer ${token}` } : undefined });
      const body = disciplineRecord(await response.json());
      if (!response.ok) throw new Error(disciplineText(body.message) || "No se pudo recuperar la disciplina canónica.");
      setData(body);
      setCached(false);
      writeCache(key, body, surface);
      if (source === "realtime") setMessage("Disciplina actualizada desde PostgreSQL");
    } catch (error) {
      const local = readCache(key);
      if (local) { setData(local); setCached(true); setMessage("Sin conexión. Copia confirmada de solo lectura."); }
      else setMessage(error instanceof Error ? error.message : "No se pudo recuperar la disciplina canónica.");
    } finally {
      setLoading(false);
    }
  }, [competitionId, endpoint, identity, surface]);

  useEffect(() => {
    if (previewData) return;
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    let removeNetwork: (() => void) | undefined;
    const start = async () => {
      const session = await supabase?.auth.getSession();
      if (!active) return;
      const token = session?.data.session?.access_token ?? "";
      const userId = session?.data.session?.user.id ?? "";
      if (surface !== "public" && (!token || !userId)) { setLoading(false); setMessage("Inicia sesión para consultar la disciplina de la competición."); return; }
      setAccessToken(token);
      setActorId(userId);
      const local = readCache(`pachangas-competition-discipline-read-v1:${surface}:${competitionId}:${identity}:${userId || "public"}`);
      if (local) { setData(local); setCached(true); setLoading(false); }
      await loadCanonical(token, userId, "initial");
      const reconcile = () => { setOnline(navigator.onLine); if (navigator.onLine) void loadCanonical(token, userId, "realtime"); };
      window.addEventListener("online", reconcile);
      window.addEventListener("offline", reconcile);
      removeNetwork = () => { window.removeEventListener("online", reconcile); window.removeEventListener("offline", reconcile); };
      if (!supabase || !token) return;
      channel = supabase.channel(`competition-discipline:${surface}:${identity}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: disciplineRealtimeTable }, (payload) => {
          if (!invalidationMatches(competitionId, matchId, playerId, payload)) return;
          if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current);
          realtimeTimer.current = window.setTimeout(() => void loadCanonical(token, userId, "realtime"), 120);
        })
        .subscribe((state) => { if (state === "SUBSCRIBED") void loadCanonical(token, userId, "realtime"); });
    };
    void start();
    return () => { active = false; removeNetwork?.(); if (realtimeTimer.current) window.clearTimeout(realtimeTimer.current); if (channel && supabase) void supabase.removeChannel(channel); };
  }, [competitionId, identity, loadCanonical, matchId, playerId, previewData, surface]);

  const command: Command = useCallback(async (action, aggregateId, expectedRevision, payload = {}) => {
    if (previewData) { setMessage(`${disciplineActionLabel(action)} no escribió datos en la Demo.`); return; }
    if (!navigator.onLine) { setMessage("Sin conexión. La acción no se ha enviado ni confirmado."); return; }
    if (!accessToken || !aggregateId) { setMessage("No hay sesión o agregado canónico para esta acción."); return; }
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true);
    setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:competition-discipline-command", "/api/competitions/discipline/command", {
        body: JSON.stringify({ action, aggregateId, competitionId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = disciplineRecord(await response.json());
      if (!response.ok) throw new Error(disciplineText(body.message) || "Acción disciplinaria no confirmada.");
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL");
      await loadCanonical(accessToken, actorId, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Acción disciplinaria no confirmada.";
      setMessage(/STALE_REVISION|revision/i.test(detail) ? "La revisión cambió. Recuperando el estado oficial." : detail);
      if (/STALE_REVISION|revision/i.test(detail)) await loadCanonical(accessToken, actorId, "mutation");
    } finally { setBusy(false); }
  }, [accessToken, actorId, competitionId, loadCanonical, previewData]);

  const title = ({ desk: "Mesa disciplinaria", match: "Disciplina del partido", player: "Disciplina del jugador", public: "Disciplina de Liga" } as const)[surface];
  const enabled = previewData ? true : surface === "public" ? Boolean(data) : disciplineFlagsEnabled(data?.flags);
  const shellContext = { detail: previewData ? "Demo read-only" : cached ? "Copia local revalidándose" : "Snapshot canónico", eyebrow: "League Engine R5", status: previewData ? "Solo visual" : loading ? "Sincronizando" : online ? "Servidor" : "Sin conexión", title };
  const body = <>
    {!embedded ? <GamePageHeader eyebrow="Competition Discipline" title={title} /> : null}
    {message ? <ProductFeedback tone={/confirmado|actualizada/i.test(message) ? "success" : /sin conexión|no |error|rechaz|inicia|revision/i.test(message) ? "warning" : "info"}>{message}</ProductFeedback> : null}
    {loading && !data ? <ProductState busy description="Recuperando el read model confirmado." eyebrow="PostgreSQL" surface="dark" title="Sincronizando disciplina" /> : null}
    {!loading && !data ? <ProductState description="No hay una superficie disciplinaria disponible para este usuario o competición." eyebrow="Acceso" surface="dark" title="Sin estado disciplinario" /> : null}
    {data && !enabled ? <ProductState description="R5 está desplegado, pero sus flags permanecen inactivos para este entorno." eyebrow="Feature flag" surface="dark" title="Disciplina inactiva" /> : null}
    {data && enabled ? <><Metrics data={data} />{surface === "match" ? <EventEditor command={command} data={data} disabled={busy || !online} editing={editing} key={`event-editor:${disciplineText(editing?.id) || "new"}`} onDone={() => setEditing(null)} /> : null}<EventList command={command} data={data} disabled={busy || !online} onEdit={setEditing} readOnly={surface === "public"} /><SanctionDesk command={command} data={data} disabled={busy || !online} readOnly={surface === "public"} />{surface !== "public" ? <AppealDesk command={command} data={data} disabled={busy || !online} /> : null}<PlayerStates competitionId={competitionId} data={data} preview={Boolean(previewData)} />{surface === "desk" ? <section className={styles.health}><SectionHeader eyebrow="Read models reconstruibles" title="Salud del motor" /><pre>{JSON.stringify(disciplineRecord(data.health), null, 2)}</pre>{disciplineBoolean(disciplineRecord(data.permissions).review) && disciplineArray(data.cycles)[0] ? <button disabled={busy || !online} onClick={() => void command("counter.rebuild", disciplineText(disciplineArray(data.cycles)[0]?.id), disciplineNumber(data.revision))} type="button">Reconstruir contadores</button> : null}</section> : null}</> : null}
  </>;
  if (embedded) {
    return <section className={`${styles.page} ${styles.embedded}`} data-competition-discipline-surface={surface}>{body}</section>;
  }
  return <OfficialProductShellV2 active="competir" perspective="league-organizer" context={shellContext}><main className={styles.page} data-competition-discipline-surface={surface} data-mobile-tab="partido">{body}</main></OfficialProductShellV2>;
}

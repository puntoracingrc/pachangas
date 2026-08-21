"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { CLIENT_VERSION } from "../client-version-contract";
import { currentClientDisplayMode, pwaBridgeSnapshot } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import styles from "./page.module.css";

type JsonRecord = Record<string, unknown>;

const cacheVersion = 1;
const cachePrefix = "pachangas-competition-foundation-read-v1";
const ruleDocumentSkeleton = {
  discipline: {},
  format: {},
  futureCapabilities: {},
  governance: {},
  operations: {
    hardAvailabilityPolicy: {},
    schedulePreferencePolicy: {},
  },
  publication: {},
  registration: {},
  results: {
    scoringPolicy: {},
    tieBreakCriteria: [],
  },
  structure: {
    stageGraph: { edges: [], nodes: [] },
  },
};

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function array(value: unknown) {
  return Array.isArray(value) ? value.map(record) : [];
}

function text(value: unknown) {
  return typeof value === "string" ? value : "";
}

function number(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function dateLabel(value: unknown) {
  if (typeof value !== "string") return "Sin fecha";
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? "Sin fecha" : parsed.toLocaleString("es-ES", { dateStyle: "medium", timeStyle: "short" });
}

function cacheKey(userId: string) {
  return `${cachePrefix}:${userId}`;
}

function readCachedFoundation(userId: string) {
  try {
    const cached = JSON.parse(window.localStorage.getItem(cacheKey(userId)) ?? "null") as unknown;
    const envelope = record(cached);
    if (number(envelope.version) !== cacheVersion) return null;
    return record(envelope.data);
  } catch {
    return null;
  }
}

function storeCachedFoundation(userId: string, data: JsonRecord) {
  try {
    window.localStorage.setItem(cacheKey(userId), JSON.stringify({ data, storedAt: new Date().toISOString(), version: cacheVersion }));
  } catch {
    // A read cache is optional; server confirmation remains mandatory.
  }
}

function input(form: FormData, key: string) {
  return String(form.get(key) ?? "").trim();
}

function Status({ children }: { children: string }) {
  return <span className={styles.status} data-status={children.toLowerCase()}>{children}</span>;
}

function Empty({ children }: { children: string }) {
  return <p className={styles.empty}>{children}</p>;
}

export default function CompetitionFoundationLabPage() {
  const [data, setData] = useState<JsonRecord | null>(null);
  const [userId, setUserId] = useState("");
  const [selectedCompetitionId, setSelectedCompetitionId] = useState("");
  const [loading, setLoading] = useState(Boolean(supabase));
  const [busy, setBusy] = useState(false);
  const [cached, setCached] = useState(false);
  const [message, setMessage] = useState("");
  const [ruleDocument, setRuleDocument] = useState(JSON.stringify(ruleDocumentSkeleton, null, 2));
  const pendingOperation = useRef<{ id: string; key: string } | null>(null);
  const refetchTimer = useRef<number | null>(null);

  const loadCanonical = useCallback(async (actorId: string, reason: "initial" | "mutation" | "realtime" | "manual" = "manual") => {
    if (!supabase) {
      setMessage("Supabase no está configurado en este entorno.");
      setLoading(false);
      return;
    }
    const result = await supabase.rpc("get_my_pachanga_competition_foundation_v1");
    if (result.error) {
      setMessage(result.error.message.includes("Authentication") ? "Inicia sesión para abrir el laboratorio." : result.error.message);
      setLoading(false);
      return;
    }
    const canonical = record(result.data);
    setData(canonical);
    setCached(false);
    storeCachedFoundation(actorId, canonical);
    setLoading(false);
    if (reason === "realtime") setMessage("Cambio recibido. Vista canónica actualizada.");
  }, []);

  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let active = true;
    let channel: ReturnType<typeof client.channel> | null = null;
    void client.auth.getSession().then(({ data: sessionData }) => {
      if (!active) return;
      const actorId = sessionData.session?.user.id ?? "";
      if (!actorId) {
        setLoading(false);
        setMessage("Inicia sesión para abrir el laboratorio.");
        return;
      }
      setUserId(actorId);
      const local = readCachedFoundation(actorId);
      if (local) {
        setData(local);
        setCached(true);
        setLoading(false);
      }
      void loadCanonical(actorId, "initial");
      channel = client.channel(`competition-foundation:${actorId}`)
        .on("postgres_changes", {
          event: "INSERT",
          schema: "public",
          table: "pachanga_competition_invalidations",
        }, () => {
          if (refetchTimer.current) window.clearTimeout(refetchTimer.current);
          refetchTimer.current = window.setTimeout(() => void loadCanonical(actorId, "realtime"), 120);
        })
        .subscribe();
    });
    return () => {
      active = false;
      if (refetchTimer.current) window.clearTimeout(refetchTimer.current);
      if (channel) void client.removeChannel(channel);
    };
  }, [loadCanonical]);

  const flags = record(data?.flags);
  const organizers = useMemo(() => array(data?.organizers), [data]);
  const competitions = useMemo(() => array(data?.competitions), [data]);
  const selected = useMemo(() => competitions.find((item) => text(record(item.competition).id) === selectedCompetitionId) ?? competitions[0] ?? null, [competitions, selectedCompetitionId]);
  const competition = record(selected?.competition);
  const editions = array(selected?.editions);
  const ruleSets = array(selected?.ruleSets);
  const stages = array(selected?.stages);
  const staff = array(selected?.staff);
  const selectedId = text(competition.id);

  async function command(action: string, aggregateId: string, expectedRevision: number, payload: JsonRecord) {
    if (!supabase || !userId) return;
    const commandKey = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pendingOperation.current || pendingOperation.current.key !== commandKey) {
      pendingOperation.current = { id: crypto.randomUUID(), key: commandKey };
    }
    setBusy(true);
    setMessage("");
    try {
      const bridge = pwaBridgeSnapshot();
      const result = await supabase.rpc("command_pachanga_competition_foundation_v1", {
        aggregate_id: aggregateId,
        client_metadata: {
          clientVersion: CLIENT_VERSION,
          installedMode: currentClientDisplayMode(),
          serviceWorkerVersion: bridge.serviceWorkerVersion,
          surface: "competition_foundation_lab",
        },
        command_action: action,
        command_payload: payload,
        expected_revision: expectedRevision,
        operation_id: pendingOperation.current.id,
      });
      if (result.error) throw new Error(result.error.message);
      pendingOperation.current = null;
      setMessage("Operación confirmada por PostgreSQL.");
      await loadCanonical(userId, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Operación no confirmada";
      setMessage(/STALE_REVISION|PT409/i.test(detail) ? "La revisión cambió. Recarga el estado canónico antes de repetir." : detail);
    } finally {
      setBusy(false);
    }
  }

  function handleCompetitionCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pendingOperation.current = null;
    const form = new FormData(event.currentTarget);
    const organizer = organizers.find((item) => text(item.groupId) === input(form, "organizerId"));
    const entitlement = record(organizer?.entitlement);
    void command("competition.create", input(form, "organizerId"), number(entitlement.organizerRevision), {
      competitionType: input(form, "competitionType"),
      name: input(form, "name"),
      reason: "create_competition_draft",
      slug: input(form, "slug"),
      visibility: input(form, "visibility"),
    });
  }

  function handleEditionCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pendingOperation.current = null;
    const form = new FormData(event.currentTarget);
    void command("edition.create", selectedId, number(competition.revision), {
      endsAt: input(form, "endsAt"),
      name: input(form, "name"),
      reason: "create_edition",
      seasonLabel: input(form, "seasonLabel"),
      startsAt: input(form, "startsAt"),
    });
  }

  function handleRuleSetCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pendingOperation.current = null;
    const form = new FormData(event.currentTarget);
    void command("rule_set.create", selectedId, number(competition.revision), {
      name: input(form, "name"),
      reason: "create_rule_set",
    });
  }

  function handleRuleRevisionCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pendingOperation.current = null;
    const form = new FormData(event.currentTarget);
    const targetRuleSet = ruleSets.find((item) => text(item.id) === input(form, "ruleSetId"));
    try {
      const parsed = JSON.parse(ruleDocument) as unknown;
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
      void command("rule_revision.create", input(form, "ruleSetId"), number(targetRuleSet?.revision), {
        effectiveScope: "future_only",
        reason: input(form, "reason") || "create_rule_revision",
        ruleDocument: parsed,
        schemaVersion: "competition_rules.v1",
      });
    } catch {
      setMessage("El documento de reglas no contiene JSON válido.");
    }
  }

  function handleStageCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pendingOperation.current = null;
    const form = new FormData(event.currentTarget);
    const edition = editions.find((item) => text(item.id) === input(form, "editionId"));
    void command("stage.create", input(form, "editionId"), number(edition?.revision), {
      name: input(form, "name"),
      optional: form.get("optional") === "on",
      reason: "create_stage",
      stageOrder: number(input(form, "stageOrder")),
      stageType: input(form, "stageType"),
    });
  }

  function handleDivisionCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pendingOperation.current = null;
    const form = new FormData(event.currentTarget);
    const stage = stages.find((item) => text(item.id) === input(form, "stageId"));
    void command("division.create", input(form, "stageId"), number(stage?.revision), {
      levelLabel: input(form, "levelLabel"),
      name: input(form, "name"),
      order: number(input(form, "order")),
      reason: "create_division",
    });
  }

  function handleGroupCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pendingOperation.current = null;
    const form = new FormData(event.currentTarget);
    const stage = stages.find((item) => text(item.id) === input(form, "stageId"));
    void command("group.create", input(form, "stageId"), number(stage?.revision), {
      divisionId: input(form, "divisionId"),
      name: input(form, "name"),
      order: number(input(form, "order")),
      reason: "create_group",
    });
  }

  function handleStageEdgeCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pendingOperation.current = null;
    const form = new FormData(event.currentTarget);
    const edition = editions.find((item) => text(item.id) === input(form, "editionId"));
    void command("stage_edge.create", input(form, "editionId"), number(edition?.revision), {
      edgeOrder: number(input(form, "edgeOrder")),
      fromStageId: input(form, "fromStageId"),
      reason: "create_stage_edge",
      toStageId: input(form, "toStageId"),
    });
  }

  function handleStaffGrant(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    pendingOperation.current = null;
    const form = new FormData(event.currentTarget);
    void command("staff.grant", selectedId, number(competition.revision), {
      reason: "grant_competition_staff",
      staffRole: input(form, "staffRole"),
      userId: input(form, "userId"),
    });
  }

  if (!userId && !loading) {
    return <main className={styles.statePage}><div><span>Laboratorio interno</span><h1>Competition Foundation</h1><p>{message || "Necesitas una sesión autenticada."}</p><Link href="/">Volver a la app</Link></div></main>;
  }

  return (
    <main className={styles.shell}>
      <header className={styles.header}>
        <div><span>Laboratorio interno · R1</span><h1>Competition Foundation</h1><p>Identidad, estructura, permisos y auditoría. Sin calendario, clasificación ni motores deportivos.</p></div>
        <div className={styles.headerActions}><Link href="/">Volver</Link><button type="button" disabled={loading || busy} onClick={() => void loadCanonical(userId, "manual")}>Recargar</button></div>
      </header>

      <section className={styles.statusBand}>
        <div><span>Fundación</span><Status>{Boolean(flags.foundationEnabled) ? "Activa" : "Inactiva"}</Status></div>
        <div><span>Creación</span><Status>{Boolean(flags.creationEnabled) ? "Activa" : "Inactiva"}</Status></div>
        <div><span>Context binding</span><Status>{Boolean(flags.contextBindingEnabled) ? "Activo" : "Inactivo"}</Status></div>
        <div><span>Read model</span><Status>{cached ? "Caché local" : loading ? "Cargando" : "Canónico"}</Status></div>
        <small>rev {number(flags.revision)} · {dateLabel(flags.updatedAt)}</small>
      </section>

      {message ? <p className={styles.message} role="status">{message}</p> : null}

      <div className={styles.workspace}>
        <aside className={styles.navigator}>
          <section>
            <h2>Organizadores</h2>
            {organizers.length ? organizers.map((organizer) => {
              const entitlement = record(organizer.entitlement);
              return <div className={styles.organizer} key={text(organizer.groupId)}><strong>{text(organizer.name)}</strong><span>{organizer.owner ? "Owner actual" : "Staff"}</span><Status>{entitlement.canCreate ? "Puede crear" : "Sin entitlement"}</Status><small>rev {number(entitlement.organizerRevision)}</small></div>;
            }) : <Empty>No hay equipos organizadores accesibles.</Empty>}
          </section>
          <section>
            <h2>Drafts</h2>
            <div className={styles.competitionList}>{competitions.map((item) => {
              const row = record(item.competition);
              const active = text(row.id) === selectedId;
              return <button key={text(row.id)} type="button" data-active={active} onClick={() => setSelectedCompetitionId(text(row.id))}><strong>{text(row.name)}</strong><span>{text(row.type)} · rev {number(row.revision)}</span></button>;
            })}</div>
            {!competitions.length ? <Empty>Aún no hay competiciones.</Empty> : null}
          </section>
        </aside>

        <div className={styles.content}>
          <section className={styles.commandSection}>
            <header><div><span>01</span><h2>Crear draft</h2></div><p>Solo owner actual con entitlement de equipo.</p></header>
            <form className={styles.formGrid} onSubmit={handleCompetitionCreate}>
              <label>Equipo<select name="organizerId" required>{organizers.map((item) => <option key={text(item.groupId)} value={text(item.groupId)}>{text(item.name)}</option>)}</select></label>
              <label>Nombre<input name="name" minLength={3} maxLength={120} required /></label>
              <label>Slug<input name="slug" pattern="[a-z0-9-]+" required /></label>
              <label>Familia<select name="competitionType"><option value="LEAGUE">League</option><option value="TOURNAMENT">Tournament</option></select></label>
              <label>Visibilidad<select name="visibility"><option value="private">Privada</option><option value="internal">Interna</option></select></label>
              <button className={styles.primaryButton} disabled={busy || !Boolean(flags.creationEnabled)} type="submit">Crear draft</button>
            </form>
          </section>

          {selected ? <>
            <section className={styles.summary}>
              <div><span>Competición seleccionada</span><h2>{text(competition.name)}</h2><p>{text(competition.type)} · {text(competition.status)} · {text(competition.organizerName)}</p></div>
              <dl><div><dt>Revisión</dt><dd>{number(competition.revision)}</dd></div><div><dt>Secuencia</dt><dd>{number(competition.serverSequence)}</dd></div><div><dt>Ediciones</dt><dd>{editions.length}</dd></div><div><dt>Stages</dt><dd>{stages.length}</dd></div></dl>
            </section>

            <section className={styles.commandSection}>
              <header><div><span>02</span><h2>Edición y reglamento</h2></div><p>La revisión publicada puede asignarse a una edición draft.</p></header>
              <div className={styles.splitForms}>
                <form onSubmit={handleEditionCreate}>
                  <h3>Nueva edición</h3><label>Nombre<input name="name" required /></label><label>Temporada<input name="seasonLabel" placeholder="2026/27" required /></label><label>Inicio<input name="startsAt" type="date" /></label><label>Fin<input name="endsAt" type="date" /></label><button className={styles.secondaryButton} disabled={busy} type="submit">Crear edición</button>
                </form>
                <form onSubmit={handleRuleSetCreate}>
                  <h3>Nueva familia de reglas</h3><label>Nombre<input name="name" required /></label><button className={styles.secondaryButton} disabled={busy} type="submit">Crear rule set</button>
                </form>
              </div>
              <div className={styles.entityRows}>{editions.map((edition) => <article key={text(edition.id)}><span><strong>{text(edition.name)}</strong><small>{text(edition.seasonLabel)} · rev {number(edition.revision)}</small></span><Status>{text(edition.status)}</Status></article>)}</div>
            </section>

            <section className={styles.commandSection}>
              <header><div><span>03</span><h2>Revisiones inmutables</h2></div><p>Documento tipado, checksum determinista y ciclo validate → publish → freeze.</p></header>
              <form className={styles.ruleForm} onSubmit={handleRuleRevisionCreate}>
                <label>Rule set<select name="ruleSetId" required>{ruleSets.map((item) => <option value={text(item.id)} key={text(item.id)}>{text(item.name)}</option>)}</select></label>
                <label>Motivo<input name="reason" defaultValue="initial_rule_revision" /></label>
                <label className={styles.documentField}>Documento JSON<textarea value={ruleDocument} onChange={(event) => { pendingOperation.current = null; setRuleDocument(event.target.value); }} rows={13} spellCheck={false} /></label>
                <button className={styles.primaryButton} disabled={busy || !ruleSets.length} type="submit">Crear revisión</button>
              </form>
              {ruleSets.map((ruleSet) => <div className={styles.ruleSet} key={text(ruleSet.id)}><header><strong>{text(ruleSet.name)}</strong><span>rev {number(ruleSet.revision)}</span></header>{array(ruleSet.revisions).map((revision) => <article key={text(revision.id)}><span><b>v{number(revision.version)}</b><small>{text(revision.checksum).slice(0, 14)}… · rev {number(revision.revision)}</small></span><Status>{text(revision.status)}</Status><div>{text(revision.status) === "draft" ? <button type="button" disabled={busy} onClick={() => void command("rule_revision.validate", text(revision.id), number(revision.revision), { reason: "validate_rule_revision" })}>Validar</button> : null}{text(revision.status) === "validated" ? <button type="button" disabled={busy} onClick={() => void command("rule_revision.publish", text(ruleSet.id), number(ruleSet.revision), { reason: "publish_rule_revision", ruleRevisionId: text(revision.id) })}>Publicar</button> : null}{text(revision.status) === "published" ? <button type="button" disabled={busy} onClick={() => void command("rule_revision.freeze", text(revision.id), number(revision.revision), { reason: "freeze_rule_revision" })}>Congelar</button> : null}</div></article>)}</div>)}
            </section>

            <section className={styles.commandSection}>
              <header><div><span>04</span><h2>Estructura</h2></div><p>Stages, divisiones, grupos y grafo. No se generan partidos.</p></header>
              <div className={styles.splitForms}>
                <form onSubmit={handleStageCreate}><h3>Nuevo stage</h3><label>Edición<select name="editionId" required>{editions.map((item) => <option value={text(item.id)} key={text(item.id)}>{text(item.name)}</option>)}</select></label><label>Nombre<input name="name" required /></label><label>Tipo<select name="stageType"><option value="SPLIT">Split</option><option value="LEAGUE_STAGE">League stage</option><option value="GROUP_STAGE">Group stage</option><option value="KNOCKOUT">Knockout</option><option value="PLAYOFF">Playoff</option><option value="FINALS">Finals</option><option value="CUSTOM">Custom</option></select></label><label>Orden<input name="stageOrder" type="number" min="1" defaultValue="1" required /></label><label className={styles.checkbox}><input name="optional" type="checkbox" />Opcional</label><button disabled={busy || !editions.length} type="submit">Crear stage</button></form>
                <form onSubmit={handleDivisionCreate}><h3>Nueva división</h3><label>Stage<select name="stageId" required>{stages.map((item) => <option value={text(item.id)} key={text(item.id)}>{text(item.name)}</option>)}</select></label><label>Nombre<input name="name" required /></label><label>Nivel<input name="levelLabel" /></label><label>Orden<input name="order" type="number" min="1" defaultValue="1" required /></label><button disabled={busy || !stages.length} type="submit">Crear división</button></form>
                <form onSubmit={handleGroupCreate}><h3>Nuevo grupo</h3><label>Stage<select name="stageId" required>{stages.map((item) => <option value={text(item.id)} key={text(item.id)}>{text(item.name)}</option>)}</select></label><label>Nombre<input name="name" required /></label><label>Division ID<input name="divisionId" placeholder="Opcional" /></label><label>Orden<input name="order" type="number" min="1" defaultValue="1" required /></label><button disabled={busy || !stages.length} type="submit">Crear grupo</button></form>
                <form onSubmit={handleStageEdgeCreate}><h3>Nueva conexión</h3><label>Edición<select name="editionId" required>{editions.map((item) => <option value={text(item.id)} key={text(item.id)}>{text(item.name)}</option>)}</select></label><label>Origen<select name="fromStageId" required>{stages.map((item) => <option value={text(item.id)} key={text(item.id)}>{text(item.name)}</option>)}</select></label><label>Destino<select name="toStageId" required>{stages.map((item) => <option value={text(item.id)} key={text(item.id)}>{text(item.name)}</option>)}</select></label><label>Orden<input name="edgeOrder" type="number" min="1" defaultValue="1" required /></label><button disabled={busy || stages.length < 2} type="submit">Conectar</button></form>
              </div>
              <div className={styles.stageGrid}>{stages.map((stage) => <article key={text(stage.id)}><header><span><strong>{number(stage.order)} · {text(stage.name)}</strong><small>{text(stage.type)} · rev {number(stage.revision)}</small></span><Status>{text(stage.status)}</Status></header><p>{array(stage.divisions).length} divisiones · {array(stage.groups).length} grupos</p></article>)}</div>
            </section>

            <section className={styles.commandSection}>
              <header><div><span>05</span><h2>Staff</h2></div><p>Delegación limitada a esta competición; no altera roles del equipo.</p></header>
              <form className={styles.formGrid} onSubmit={handleStaffGrant}>
                <label>User ID<input name="userId" placeholder="UUID autenticado" required /></label><label>Rol<select name="staffRole"><option value="competition_director">Director</option><option value="competition_admin">Admin</option><option value="rules_manager">Reglas</option><option value="viewer">Viewer</option></select></label><button className={styles.primaryButton} disabled={busy} type="submit">Asignar staff</button>
              </form>
              <div className={styles.entityRows}>{staff.map((item) => <article key={text(item.id)}><span><strong>{text(item.role)}</strong><small>{text(item.userId)} · rev {number(item.revision)}</small></span><Status>{text(item.status)}</Status>{text(item.status) === "active" ? <button type="button" disabled={busy} onClick={() => void command("staff.revoke", selectedId, number(competition.revision), { reason: "revoke_competition_staff", staffAssignmentId: text(item.id) })}>Revocar</button> : null}</article>)}</div>
            </section>
          </> : null}
        </div>
      </div>
    </main>
  );
}

import Link from "next/link";
import {
  DataTable,
  EmptyState,
  Identifier,
  Metric,
  MetricGrid,
  PageHeader,
  Pagination,
  Panel,
  StatusBadge,
  formatAdminDate,
} from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { hasPlatformCapability } from "../_lib/platform-contract";
import { getPlatformCompetitionFoundation, getPlatformLeagueMatchOperations, getPlatformLeagueParticipation, getPlatformLeagueScheduling, paginationFromSearchParams } from "../_lib/platform-data";
import styles from "../platform-admin.module.css";
import { CompetitionAdminClient } from "./competition-admin-client";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }
function n(value: unknown) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }
function s(value: unknown) { return typeof value === "string" ? value : ""; }
function organizerId(item: Record<string, unknown>) {
  return s(item.organizerKind) === "CLUB" ? s(item.organizerClubId) : s(item.organizerGroupId);
}

export default async function PlatformCompetitionsPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("competitions.read");
  const raw = await searchParams;
  const params = new URLSearchParams();
  Object.entries(raw).forEach(([key, value]) => params.set(key, first(value)));
  const { page, pageSize } = paginationFromSearchParams(params);
  const [data, leagueParticipation, leagueScheduling, leagueMatchOperations] = await Promise.all([
    getPlatformCompetitionFoundation(session, page, pageSize),
    getPlatformLeagueParticipation(session, page, pageSize),
    getPlatformLeagueScheduling(session, page, pageSize),
    getPlatformLeagueMatchOperations(session, page, pageSize),
  ]);
  const canWrite = hasPlatformCapability(session.access, "competitions.manage");
  const canonicalHealthLabel = s(data.bindingHealth.status) === "NOT_INITIALIZED"
    ? "Pendiente de inicialización"
    : data.bindingHealth.stale
      ? "Pendiente de actualización"
      : "Canónico";

  return (
    <>
      <PageHeader
        title="Competiciones"
        subtitle="Fundación autoritativa: organizadores, reglamentos versionados y bindings de partido. No genera jornadas ni clasificaciones."
        actions={hasPlatformCapability(session.access, "labs.read") ? <Link className={styles.secondaryButton} href="/laboratorio-competition-foundation">Abrir laboratorio</Link> : null}
      />
      <MetricGrid>
        <Metric label="Competiciones" value={n(data.metrics.competitions)} hint={`${n(data.metrics.drafts)} draft`} />
        <Metric label="Ediciones" value={n(data.metrics.editions)} />
        <Metric label="Reglamentos" value={n(data.metrics.ruleRevisions)} />
        <Metric label="Entitlements" value={n(data.metrics.activeEntitlements)} tone="good" />
        <Metric label="Bindings activos" value={n(data.bindingHealth.bindingsTotal)} hint={`${n(data.bindingHealth.ambiguousBindings)} revisiones abiertas`} tone={n(data.bindingHealth.ambiguousBindings) ? "warning" : "neutral"} />
      </MetricGrid>

      <Panel title="League Participation">
        <MetricGrid>
          <Metric label="Ediciones abiertas" value={n(leagueParticipation.metrics.registrationOpenEditions)} />
          <Metric label="Inscripciones" value={n(leagueParticipation.metrics.entries)} />
          <Metric label="Plantillas" value={n(leagueParticipation.metrics.rosters)} />
          <Metric label="Delegados activos" value={n(leagueParticipation.metrics.activeDelegates)} />
          <Metric label="Alertas de elegibilidad" value={n(leagueParticipation.metrics.eligibilityWarnings)} tone={n(leagueParticipation.metrics.eligibilityWarnings) ? "warning" : "neutral"} />
          <Metric label="Conflictos duplicados" value={n(leagueParticipation.metrics.duplicateConflicts)} tone={n(leagueParticipation.metrics.duplicateConflicts) ? "warning" : "good"} />
        </MetricGrid>
      </Panel>

      <Panel title="League Scheduling R4B">
        <MetricGrid>
          <Metric label="Planes en borrador" value={n(leagueScheduling.metrics.draftPlans)} />
          <Metric label="Entradas obsoletas" value={n(leagueScheduling.metrics.stalePlans)} tone={n(leagueScheduling.metrics.stalePlans) ? "warning" : "good"} />
          <Metric label="Calendarios inválidos" value={n(leagueScheduling.metrics.invalidSchedules)} tone={n(leagueScheduling.metrics.invalidSchedules) ? "warning" : "good"} />
          <Metric label="Jornadas publicadas" value={n(leagueScheduling.metrics.publishedRounds)} />
          <Metric label="Fixtures canónicos" value={n(leagueScheduling.metrics.generatedCanonicalMatches)} />
          <Metric label="Sin slot" value={n(leagueScheduling.metrics.unassignedItems)} tone={n(leagueScheduling.metrics.unassignedItems) ? "warning" : "good"} />
          <Metric label="Conflictos duros" value={n(leagueScheduling.metrics.hardConflicts)} tone={n(leagueScheduling.metrics.hardConflicts) ? "warning" : "good"} />
          <Metric label="Calidad media" value={`${n(leagueScheduling.metrics.averageQualityScore).toFixed(1)}%`} />
        </MetricGrid>
      </Panel>

      <Panel title="League Match Operations R4C">
        <MetricGrid>
          <Metric label="Programados" value={n(leagueMatchOperations.counts.scheduled)} />
          <Metric label="Preparados" value={n(leagueMatchOperations.counts.ready)} />
          <Metric label="Jugados" value={n(leagueMatchOperations.counts.played)} />
          <Metric label="Oficiales" value={n(leagueMatchOperations.counts.official)} />
          <Metric label="Resultados pendientes" value={n(leagueMatchOperations.counts.pendingResults)} tone={n(leagueMatchOperations.counts.pendingResults) ? "warning" : "good"} />
          <Metric label="Disputas" value={n(leagueMatchOperations.counts.disputes)} tone={n(leagueMatchOperations.counts.disputes) ? "warning" : "good"} />
          <Metric label="Clasificaciones actuales" value={n(leagueMatchOperations.counts.standingsCurrent)} />
          <Metric label="Clasificaciones con error" value={n(leagueMatchOperations.counts.standingsErrors)} tone={n(leagueMatchOperations.counts.standingsErrors) ? "warning" : "good"} />
        </MetricGrid>
      </Panel>

      <Panel title="Controles de plataforma">
        <CompetitionAdminClient canWrite={canWrite} entitlements={data.entitlements} flags={data.flags} leagueFlags={leagueParticipation.flags} matchOperationsFlags={leagueMatchOperations.flags} schedulingFlags={leagueScheduling.flags} />
      </Panel>

      <Panel title="Operaciones de partido recientes">
        {leagueMatchOperations.matches.length ? <DataTable label="Partidos R4C"><thead><tr><th>Contexto</th><th>Partido</th><th>Estado</th><th>Jornada</th><th>Revisión</th><th>Secuencia</th></tr></thead><tbody>{leagueMatchOperations.matches.map((item) => <tr key={s(item.contextId)}><td><Identifier value={s(item.contextId)} /></td><td><Link href={`/competiciones/${s(item.competitionId)}/partidos/${s(item.canonicalMatchId)}`}>Abrir partido</Link><small><Identifier value={s(item.canonicalMatchId)} /></small></td><td><StatusBadge>{s(item.status)}</StatusBadge></td><td><Identifier value={s(item.roundId)} /></td><td>{n(item.revision)}</td><td>{n(item.serverSequence)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay operaciones R4C.</EmptyState>}
      </Panel>

      <Panel title="Salud de clasificaciones">
        {leagueMatchOperations.standingsHealth.length ? <DataTable label="Clasificaciones R4C"><thead><tr><th>Competición</th><th>Fase</th><th>Estado</th><th>Snapshot</th><th>Revisión</th><th>Secuencia</th></tr></thead><tbody>{leagueMatchOperations.standingsHealth.map((item) => <tr key={s(item.id)}><td><Identifier value={s(item.competitionId)} /></td><td><Identifier value={s(item.stageId)} /></td><td><StatusBadge>{s(item.health)}</StatusBadge></td><td><Identifier value={s(item.currentSnapshotId)} /></td><td>{n(item.revision)}</td><td>{n(item.serverSequence)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay clasificaciones R4C.</EmptyState>}
      </Panel>

      <Panel title="Últimas reconstrucciones de clasificación">
        {leagueMatchOperations.recentRebuilds.length ? <DataTable label="Rebuilds R4C"><thead><tr><th>Snapshot</th><th>Tipo</th><th>Revisión fuente</th><th>Duración</th><th>Checksum</th><th>Secuencia</th></tr></thead><tbody>{leagueMatchOperations.recentRebuilds.map((item) => <tr key={`${s(item.snapshotId)}-${n(item.serverSequence)}`}><td><Identifier value={s(item.snapshotId)} /></td><td><StatusBadge>{s(item.kind)}</StatusBadge></td><td>{n(item.sourceRevision)}</td><td>{n(item.durationMs).toFixed(1)} ms</td><td><Identifier value={s(item.checksum)} /></td><td>{n(item.serverSequence)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay reconstrucciones R4C.</EmptyState>}
      </Panel>

      <Panel title="Planes de calendario">
        {leagueScheduling.items.length ? <DataTable label="Planes R4B"><thead><tr><th>Competición</th><th>Fase</th><th>Plan</th><th>Equipos</th><th>Jornadas</th><th>Partidos</th><th>Calidad</th><th>Conflictos</th><th>Revisión</th></tr></thead><tbody>{leagueScheduling.items.map((item) => <tr key={s(item.id)}><td><strong>{s(item.competitionName)}</strong><small>{s(item.editionName)}</small></td><td>{s(item.stageName)}</td><td><StatusBadge>{s(item.status)}</StatusBadge><small>{n(item.legs)} vuelta(s)</small></td><td>{n(item.entryCount)}</td><td>{n(item.roundCount)}</td><td>{n(item.itemCount)}</td><td>{n(item.qualityScore).toFixed(1)}<small>{s(item.validationStatus) || "sin validar"}</small></td><td>{n(item.hardConflicts)}</td><td>{n(item.revision)}<small>{formatAdminDate(item.updatedAt)}</small></td></tr>)}</tbody></DataTable> : <EmptyState>No hay planes R4B.</EmptyState>}
      </Panel>

      <Panel title="Participaciones recientes">
        {leagueParticipation.items.length ? <DataTable label="Participaciones de Liga"><thead><tr><th>Equipo</th><th>Competición</th><th>Categoría</th><th>Entrada</th><th>Plantilla</th><th>Elegibilidad</th><th>Revisión</th></tr></thead><tbody>{leagueParticipation.items.map((item) => <tr key={s(item.id)}><td><strong>{s(item.teamName)}</strong><small><Identifier value={s(item.teamId)} /></small></td><td>{s(item.competitionName)}<small>{s(item.editionName)}</small></td><td>{s(item.categoryName)}</td><td><StatusBadge>{s(item.status)}</StatusBadge><small>{s(item.source)}</small></td><td><StatusBadge>{s(item.rosterStatus) || "sin roster"}</StatusBadge><small>{n(item.memberCount)} jugadores</small></td><td>{JSON.stringify(item.eligibilityHealth ?? {})}</td><td>{n(item.revision)}<small>{formatAdminDate(item.updatedAt)}</small></td></tr>)}</tbody></DataTable> : <EmptyState>No hay participaciones R4A.</EmptyState>}
      </Panel>

      <Panel title="Competiciones draft">
        {data.items.length ? <DataTable label="Competiciones"><thead><tr><th>Competición</th><th>Organizador</th><th>Estado</th><th>Ediciones</th><th>Reglas</th><th>Staff</th><th>Contexts</th><th>Revisión</th></tr></thead><tbody>{data.items.map((item) => <tr key={s(item.id)}><td><strong>{s(item.name)}</strong><small>{s(item.type)} · {s(item.slug)}</small><Identifier value={s(item.id)} /></td><td>{s(item.organizerName)}<small>{s(item.organizerKind)} · <Identifier value={organizerId(item)} /></small></td><td><StatusBadge>{s(item.status)}</StatusBadge><small>{s(item.visibility)}</small></td><td>{n(item.editionCount)}</td><td>{n(item.ruleRevisionCount)}<small>última v{n(item.latestRuleVersion)}</small></td><td>{n(item.staffCount)}</td><td>{n(item.contextCount)}</td><td>{n(item.revision)}<small>{formatAdminDate(item.updatedAt)}</small></td></tr>)}</tbody></DataTable> : <EmptyState>No hay competiciones creadas.</EmptyState>}
        <Pagination page={data.page} pageSize={data.pageSize} total={data.total} path="/admin/competitions" />
      </Panel>

      <Panel title="Entitlements">
        {data.entitlements.length ? <DataTable label="Entitlements de competición"><thead><tr><th>Organizador</th><th>Capacidad</th><th>Estado</th><th>Origen</th><th>Vigencia</th><th>Revisión</th></tr></thead><tbody>{data.entitlements.map((item) => <tr key={s(item.id)}><td>{s(item.organizerName)}<small>{s(item.organizerKind)} · <Identifier value={organizerId(item)} /></small></td><td>{s(item.capability)}</td><td><StatusBadge>{s(item.status)}</StatusBadge></td><td>{s(item.source)}</td><td>{formatAdminDate(item.validFrom)}<small>{item.expiresAt ? `Hasta ${formatAdminDate(item.expiresAt)}` : "Sin caducidad"}</small></td><td>{n(item.revision)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay grants de competición.</EmptyState>}
      </Panel>

      <Panel title="Salud del registro canónico">
        <div className={styles.competitionHealthGrid}>
          <div><span>Partidos canónicos</span><strong>{n(data.bindingHealth.canonicalMatches)}</strong></div>
          <div><span>Bindings activos</span><strong>{n(data.bindingHealth.bindingsTotal)}</strong></div>
          <div><span>Procedencias sin binding</span><strong>{n(data.bindingHealth.unboundSources)}</strong></div>
          <div><span>Revisiones ambiguas</span><strong>{n(data.bindingHealth.ambiguousBindings)}</strong></div>
          <div><span>Conflictos duplicados</span><strong>{n(data.bindingHealth.duplicateConflicts)}</strong></div>
          <div><span>Canónicos huérfanos</span><strong>{n(data.bindingHealth.orphanCanonicalMatches)}</strong></div>
          <div><span>Contexts vinculados</span><strong>{n(data.bindingHealth.contextsLinked)}</strong></div>
          <div><span>Snapshot</span><strong>{canonicalHealthLabel}</strong></div>
        </div>
      </Panel>

      <Panel title="Bindings pendientes de revisión">
        {data.reviews.length ? <DataTable label="Revisiones de binding"><thead><tr><th>Procedencia</th><th>Posible relación</th><th>Motivo</th><th>Estado</th><th>Secuencia</th></tr></thead><tbody>{data.reviews.map((item) => <tr key={s(item.id)}><td>{s(item.leftSourceKind)}<small>{s(item.leftSourceId)}</small></td><td>{s(item.rightSourceKind) || "Sin pareja demostrable"}<small>{s(item.rightSourceId)}</small></td><td>{s(item.reasonCode)}</td><td><StatusBadge>{s(item.status)}</StatusBadge></td><td>{n(item.serverSequence)}<small>{formatAdminDate(item.createdAt)}</small></td></tr>)}</tbody></DataTable> : <EmptyState>No hay bindings ambiguos pendientes.</EmptyState>}
      </Panel>

      <Panel title="Últimos eventos">
        {data.events.length ? <DataTable label="Eventos de competición"><thead><tr><th>Acción</th><th>Agregado</th><th>Competición</th><th>Revisión</th><th>Secuencia</th><th>Confirmado</th></tr></thead><tbody>{data.events.map((item) => <tr key={s(item.id)}><td><strong>{s(item.action)}</strong><small>{s(item.reasonCode)}</small></td><td>{s(item.aggregateType)}<small><Identifier value={s(item.aggregateId)} /></small></td><td><Identifier value={s(item.competitionId)} /></td><td>{n(item.revision)}</td><td>{n(item.serverSequence)}</td><td>{formatAdminDate(item.confirmedAt)}</td></tr>)}</tbody></DataTable> : <EmptyState>Aún no hay eventos.</EmptyState>}
      </Panel>
    </>
  );
}

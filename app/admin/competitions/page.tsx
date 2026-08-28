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
import { getPlatformCompetitionConfiguration, getPlatformCompetitionFoundation, getPlatformLeagueMatchOperations, getPlatformLeagueOperationalExceptions, getPlatformLeagueParticipation, getPlatformLeaguePrivateBeta, getPlatformLeagueScheduling, getPlatformTournamentControl, paginationFromSearchParams } from "../_lib/platform-data";
import styles from "../platform-admin.module.css";
import { CompetitionAdminClient } from "./competition-admin-client";
import { LeaguePrivateBetaAdminClient } from "./league-private-beta-admin-client";
import { TournamentPrivateBetaAdminClient } from "./tournament-private-beta-admin-client";

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
  const betaSearch = first(raw.betaSearch).trim().slice(0, 160);
  const [data, leagueParticipation, leagueScheduling, leagueMatchOperations, leagueOperationalExceptions, leaguePrivateBeta, competitionConfiguration, tournaments] = await Promise.all([
    getPlatformCompetitionFoundation(session, page, pageSize),
    getPlatformLeagueParticipation(session, page, pageSize),
    getPlatformLeagueScheduling(session, page, pageSize),
    getPlatformLeagueMatchOperations(session, page, pageSize),
    getPlatformLeagueOperationalExceptions(session, page, pageSize),
    getPlatformLeaguePrivateBeta(session, betaSearch, page, pageSize),
    getPlatformCompetitionConfiguration(session),
    getPlatformTournamentControl(session),
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

      <Panel title="League Operational Exceptions R4D">
        <MetricGrid>
          <Metric label="Cambios efectivos" value={n(leagueOperationalExceptions.counts.fixtureChanges)} />
          <Metric label="Aplazamientos" value={n(leagueOperationalExceptions.counts.postponementRequests)} />
          <Metric label="Deadlines vencidos" value={n(leagueOperationalExceptions.counts.expiredDeadlines)} tone={n(leagueOperationalExceptions.counts.expiredDeadlines) ? "warning" : "good"} />
          <Metric label="Cambios de sede" value={n(leagueOperationalExceptions.counts.venueDecisions)} />
          <Metric label="Retrasos" value={n(leagueOperationalExceptions.counts.lateArrivalIncidents)} />
          <Metric label="No-shows" value={n(leagueOperationalExceptions.counts.noShowIncidents)} />
          <Metric label="Suspensiones" value={n(leagueOperationalExceptions.counts.matchSuspensions)} />
          <Metric label="Decisiones" value={n(leagueOperationalExceptions.counts.administrativeDecisions)} />
          <Metric label="Contexts duplicados" value={n(leagueOperationalExceptions.health.duplicateActiveContexts)} tone={n(leagueOperationalExceptions.health.duplicateActiveContexts) ? "warning" : "good"} />
          <Metric label="Resultados sin fuente" value={n(leagueOperationalExceptions.health.noShowResultsWithoutSource)} tone={n(leagueOperationalExceptions.health.noShowResultsWithoutSource) ? "warning" : "good"} />
        </MetricGrid>
      </Panel>

      <Panel title="League Private Beta">
        <MetricGrid>
          <Metric label="Ligas beta" value={n(leaguePrivateBeta.metrics.competitions)} />
          <Metric label="Borradores" value={n(leaguePrivateBeta.metrics.drafts)} />
          <Metric label="Activas" value={n(leaguePrivateBeta.metrics.active)} />
          <Metric label="Bundles activos" value={n(leaguePrivateBeta.metrics.activeGrantBundles)} tone="good" />
          <Metric label="Exposición pública" value={n(leaguePrivateBeta.metrics.publicExposureViolations)} tone={n(leaguePrivateBeta.metrics.publicExposureViolations) ? "warning" : "good"} />
          <Metric label="Límite incumplido" value={n(leaguePrivateBeta.metrics.activeEditionLimitViolations)} tone={n(leaguePrivateBeta.metrics.activeEditionLimitViolations) ? "warning" : "good"} />
        </MetricGrid>
        <form className={styles.competitionSearchForm} action="/admin/competitions" method="get">
          <label className={styles.formField}>Buscar Team o Club<input name="betaSearch" defaultValue={betaSearch} placeholder="Nombre, código o slug" /></label>
          <button className={styles.secondaryButton} type="submit">Buscar organizador</button>
        </form>
        <LeaguePrivateBetaAdminClient bundles={leaguePrivateBeta.bundles} canWrite={canWrite} flags={leaguePrivateBeta.flags} organizers={leaguePrivateBeta.organizers} />
      </Panel>

      <Panel title="Competition Configuration Center V1">
        <MetricGrid>
          <Metric label="Borradores" value={n(competitionConfiguration.metrics.drafts)} />
          <Metric label="Validados" value={n(competitionConfiguration.metrics.validated)} />
          <Metric label="Revisiones publicadas" value={n(competitionConfiguration.metrics.configurationRuleRevisions)} tone="good" />
          <Metric label="Errores bloqueantes" value={n(competitionConfiguration.metrics.blockingErrors)} tone={n(competitionConfiguration.metrics.blockingErrors) ? "warning" : "good"} />
          <Metric label="Advertencias" value={n(competitionConfiguration.metrics.warnings)} tone={n(competitionConfiguration.metrics.warnings) ? "warning" : "good"} />
          <Metric label="Presets" value={n(competitionConfiguration.metrics.presets)} />
        </MetricGrid>
        <p className={styles.helpText}>Centro {competitionConfiguration.flags.configurationCenterEnabled ? "activo" : "apagado"} · Wizard V2 {competitionConfiguration.flags.wizardV2Enabled ? "activo" : "apagado"} · rollback mediante revisión nueva.</p>
        {competitionConfiguration.drafts.length ? <DataTable label="Configuraciones recientes"><thead><tr><th>Competición</th><th>Estado</th><th>Modo</th><th>Health</th><th>Revisión</th><th>Acción</th></tr></thead><tbody>{competitionConfiguration.drafts.map((item) => { const health = item.health as Record<string, unknown> ?? {}; return <tr key={s(item.id)}><td><strong>{s(item.competitionName)}</strong><small><Identifier value={s(item.competitionId)} /></small></td><td><StatusBadge>{s(item.status)}</StatusBadge><small>{s(item.presetKey)}</small></td><td>{s(item.authoringMode)}</td><td><StatusBadge>{s(health.status)}</StatusBadge></td><td>{n(item.revision)}<small>{formatAdminDate(item.updatedAt)}</small></td><td><Link href={`/competiciones/${s(item.competitionId)}/configuracion`}>Abrir</Link></td></tr>; })}</tbody></DataTable> : <EmptyState>No hay borradores de configuración.</EmptyState>}
      </Panel>

      <Panel title="Tournament Private Beta">
        <MetricGrid>
          <Metric label="Torneos" value={n(tournaments.metrics.tournaments)} />
          <Metric label="Borradores" value={n(tournaments.metrics.drafts)} />
          <Metric label="Freezes" value={n(tournaments.metrics.freezes)} />
          <Metric label="DrawPlans" value={n(tournaments.metrics.drawPlans)} />
          <Metric label="Revisiones" value={n(tournaments.metrics.revisions)} />
          <Metric label="Publicados" value={n(tournaments.metrics.published)} tone="good" />
          <Metric label="Invalid / stale" value={n(tournaments.metrics.invalidOrStale)} tone={n(tournaments.metrics.invalidOrStale) ? "warning" : "good"} />
          <Metric label="Hard conflicts" value={n(tournaments.metrics.hardConflicts)} tone={n(tournaments.metrics.hardConflicts) ? "warning" : "good"} />
          <Metric label="Quality media" value={n(tournaments.metrics.averageQuality).toFixed(1)} />
          <Metric label="Overrides" value={n(tournaments.metrics.manualOverrides)} />
          <Metric label="Tournament matches" value={n(tournaments.metrics.tournamentMatches)} tone={n(tournaments.metrics.tournamentMatches) ? "warning" : "good"} />
          <Metric label="Bracket progression" value={n(tournaments.metrics.bracketProgressions)} tone={n(tournaments.metrics.bracketProgressions) ? "warning" : "good"} />
          <Metric label="Group Stages" value={n(tournaments.groupStage.metrics.groupStages)} />
          <Metric label="Fixtures de grupo" value={n(tournaments.groupStage.metrics.publishedFixtures)} />
          <Metric label="Resultados oficiales" value={n(tournaments.groupStage.metrics.officialFixtures)} />
          <Metric label="Qualifications" value={n(tournaments.groupStage.metrics.publishedQualifications)} tone="good" />
          <Metric label="Knockout brackets" value={n(tournaments.knockout.metrics.brackets)} />
          <Metric label="Partidos knockout" value={n(tournaments.knockout.metrics.knockoutMatches)} />
          <Metric label="Avances" value={n(tournaments.knockout.metrics.advances)} />
          <Metric label="Campeones" value={n(tournaments.knockout.metrics.completionSnapshots)} tone="good" />
        </MetricGrid>
        <p className={styles.helpText}>Descubrimiento público {tournaments.knockout.health.publicDiscoveryOff ? "OFF" : "ERROR"} · ida/vuelta {tournaments.knockout.health.twoLegOff ? "OFF" : "ERROR"} · doble eliminación {tournaments.knockout.health.doubleEliminationOff ? "OFF" : "ERROR"} · grants de rewards {n(tournaments.knockout.health.rewardGrants)}.</p>
        <TournamentPrivateBetaAdminClient canWrite={canWrite} flags={tournaments.flags} grants={tournaments.grants} groupStage={tournaments.groupStage} knockout={tournaments.knockout} />
        {tournaments.recentPlans.length ? <DataTable label="Sorteos recientes"><thead><tr><th>Torneo</th><th>Modo</th><th>Estado</th><th>Revisión</th><th>Secuencia</th><th>Acción</th></tr></thead><tbody>{tournaments.recentPlans.map((item) => <tr key={s(item.id)}><td><strong>{s(item.competitionName)}</strong><small><Identifier value={s(item.competitionId)} /></small></td><td>{s(item.mode)}</td><td><StatusBadge>{s(item.status)}</StatusBadge></td><td>{n(item.revision)}</td><td>{n(item.serverSequence)}</td><td><Link href={`/competiciones/${s(item.competitionId)}/gestion/sorteo?plan=${s(item.id)}`}>Abrir</Link></td></tr>)}</tbody></DataTable> : <EmptyState>No hay DrawPlans de Tournament.</EmptyState>}
        {tournaments.groupStage.states.length ? <DataTable label="Fases de grupo"><thead><tr><th>Torneo</th><th>Estado</th><th>Grupos</th><th>Fixtures</th><th>Oficiales</th><th>Revisión</th><th>Acción</th></tr></thead><tbody>{tournaments.groupStage.states.map((item) => <tr key={s(item.groupStageStateId)}><td><strong>{s(item.competitionName)}</strong><small><Identifier value={s(item.competitionId)} /></small></td><td><StatusBadge>{s(item.status)}</StatusBadge></td><td>{n(item.groups)}</td><td>{n(item.fixtures)}</td><td>{n(item.officialFixtures)}</td><td>{n(item.revision)}<small>seq {n(item.serverSequence)}</small></td><td><Link href={`/competiciones/${s(item.competitionId)}/torneo`}>Abrir Hub</Link></td></tr>)}</tbody></DataTable> : null}
      </Panel>

      <Panel title="Ligas privadas">
        {leaguePrivateBeta.competitions.length ? <DataTable label="Ligas privadas beta"><thead><tr><th>Liga</th><th>Estado</th><th>Equipos</th><th>Partidos</th><th>Resultados</th><th>Incidencias</th><th>Clasificación</th><th>Reglas</th></tr></thead><tbody>{leaguePrivateBeta.competitions.map((item) => <tr key={s(item.id)}><td><strong>{s(item.name)}</strong><small>{s(item.organizerKind)} · <Identifier value={s(item.organizerId)} /></small></td><td><StatusBadge>{s(item.status)}</StatusBadge><small>{s(item.visibility)}</small></td><td>{n(item.teamCount)}</td><td>{n(item.matchCount)}</td><td>{n(item.pendingResults)} pendientes<small>{n(item.disputes)} disputas</small></td><td>{n(item.incidents)}</td><td><StatusBadge>{s(item.standingsHealth)}</StatusBadge></td><td><Link href={`/competiciones/${s(item.id)}/configuracion`}>Configurar</Link></td></tr>)}</tbody></DataTable> : <EmptyState>No hay Ligas privadas creadas.</EmptyState>}
      </Panel>

      <Panel title="Controles de plataforma">
        <CompetitionAdminClient canWrite={canWrite} entitlements={data.entitlements} flags={data.flags} leagueFlags={leagueParticipation.flags} matchOperationsFlags={leagueMatchOperations.flags} operationalExceptionFlags={leagueOperationalExceptions.flags} schedulingFlags={leagueScheduling.flags} />
      </Panel>

      <Panel title="Excepciones operativas recientes">
        {leagueOperationalExceptions.recent.length ? <DataTable label="Partidos R4D"><thead><tr><th>Partido</th><th>Estado</th><th>Fecha efectiva</th><th>Revisión</th><th>Secuencia</th></tr></thead><tbody>{leagueOperationalExceptions.recent.map((item) => <tr key={s(item.contextId)}><td><Link href={`/competiciones/${s(item.competitionId)}/partidos/${s(item.canonicalMatchId)}/operaciones`}>Abrir operación</Link><small><Identifier value={s(item.canonicalMatchId)} /></small></td><td><StatusBadge>{s(item.status)}</StatusBadge></td><td>{formatAdminDate(item.scheduledStart)}</td><td>{n(item.revision)}</td><td>{n(item.serverSequence)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay datos R4D.</EmptyState>}
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

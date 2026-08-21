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
import { getPlatformCompetitionFoundation, paginationFromSearchParams } from "../_lib/platform-data";
import styles from "../platform-admin.module.css";
import { CompetitionAdminClient } from "./competition-admin-client";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }
function n(value: unknown) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }
function s(value: unknown) { return typeof value === "string" ? value : ""; }

export default async function PlatformCompetitionsPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("competitions.read");
  const raw = await searchParams;
  const params = new URLSearchParams();
  Object.entries(raw).forEach(([key, value]) => params.set(key, first(value)));
  const { page, pageSize } = paginationFromSearchParams(params);
  const data = await getPlatformCompetitionFoundation(session, page, pageSize);
  const canWrite = hasPlatformCapability(session.access, "competitions.manage");

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

      <Panel title="Controles de plataforma">
        <CompetitionAdminClient canWrite={canWrite} entitlements={data.entitlements} flags={data.flags} />
      </Panel>

      <Panel title="Competiciones draft">
        {data.items.length ? <DataTable label="Competiciones"><thead><tr><th>Competición</th><th>Organizador</th><th>Estado</th><th>Ediciones</th><th>Reglas</th><th>Staff</th><th>Contexts</th><th>Revisión</th></tr></thead><tbody>{data.items.map((item) => <tr key={s(item.id)}><td><strong>{s(item.name)}</strong><small>{s(item.type)} · {s(item.slug)}</small><Identifier value={s(item.id)} /></td><td>{s(item.organizerName)}<small><Identifier value={s(item.organizerGroupId)} /></small></td><td><StatusBadge>{s(item.status)}</StatusBadge><small>{s(item.visibility)}</small></td><td>{n(item.editionCount)}</td><td>{n(item.ruleRevisionCount)}<small>última v{n(item.latestRuleVersion)}</small></td><td>{n(item.staffCount)}</td><td>{n(item.contextCount)}</td><td>{n(item.revision)}<small>{formatAdminDate(item.updatedAt)}</small></td></tr>)}</tbody></DataTable> : <EmptyState>No hay competiciones creadas.</EmptyState>}
        <Pagination page={data.page} pageSize={data.pageSize} total={data.total} path="/admin/competitions" />
      </Panel>

      <Panel title="Entitlements">
        {data.entitlements.length ? <DataTable label="Entitlements de competición"><thead><tr><th>Organizador</th><th>Capacidad</th><th>Estado</th><th>Origen</th><th>Vigencia</th><th>Revisión</th></tr></thead><tbody>{data.entitlements.map((item) => <tr key={s(item.id)}><td>{s(item.organizerName)}<small><Identifier value={s(item.organizerGroupId)} /></small></td><td>{s(item.capability)}</td><td><StatusBadge>{s(item.status)}</StatusBadge></td><td>{s(item.source)}</td><td>{formatAdminDate(item.validFrom)}<small>{item.expiresAt ? `Hasta ${formatAdminDate(item.expiresAt)}` : "Sin caducidad"}</small></td><td>{n(item.revision)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay grants de competición.</EmptyState>}
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
          <div><span>Snapshot</span><strong>{data.bindingHealth.stale ? "Pendiente de backfill" : "Canónico"}</strong></div>
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

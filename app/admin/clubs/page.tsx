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
import { getPlatformClub, getPlatformClubs, paginationFromSearchParams } from "../_lib/platform-data";
import styles from "../platform-admin.module.css";
import { ClubAdminClient } from "./club-admin-client";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }
function n(value: unknown) { const parsed = Number(value); return Number.isFinite(parsed) ? parsed : 0; }
function s(value: unknown) { return typeof value === "string" ? value : ""; }

export default async function PlatformClubsPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("clubs.read");
  const raw = await searchParams;
  const params = new URLSearchParams();
  Object.entries(raw).forEach(([key, value]) => params.set(key, first(value)));
  const { page, pageSize } = paginationFromSearchParams(params);
  const selectedClubId = first(raw.club);
  const [data, selected] = await Promise.all([
    getPlatformClubs(session, page, pageSize),
    selectedClubId ? getPlatformClub(session, selectedClubId) : Promise.resolve(null),
  ]);
  const canWrite = hasPlatformCapability(session.access, "clubs.manage");
  const selectedForClient = selected ? { ...selected.club, entitlements: selected.entitlements } : null;

  return (
    <>
      <PageHeader
        title="Clubes"
        subtitle="Autoridad de clubes, staff, equipos vinculados y capacidad explícita para organizar competiciones. Club y Equipo siguen siendo dominios distintos."
        actions={hasPlatformCapability(session.access, "labs.read") ? <Link className={styles.secondaryButton} href="/laboratorio-club-foundation">Abrir laboratorio</Link> : null}
      />

      <MetricGrid>
        <Metric label="Clubes" value={n(data.metrics.clubs)} />
        <Metric label="Activos" value={n(data.metrics.active)} tone="good" />
        <Metric label="Pendientes" value={n(data.metrics.pendingReview)} tone={n(data.metrics.pendingReview) ? "warning" : "neutral"} />
        <Metric label="Verificados" value={n(data.metrics.verified)} />
        <Metric label="Equipos vinculados" value={n(data.metrics.activeTeamRelationships)} />
      </MetricGrid>

      <Panel title="Controles de plataforma">
        <ClubAdminClient canWrite={canWrite} flags={data.flags} selected={selectedForClient} />
      </Panel>

      <Panel title="Registro de clubes">
        {data.items.length ? (
          <DataTable label="Clubes canónicos">
            <thead><tr><th>Club</th><th>Localidad</th><th>Estado</th><th>Owner</th><th>Staff</th><th>Equipos</th><th>Competiciones</th><th>Revisión</th></tr></thead>
            <tbody>{data.items.map((item) => (
              <tr key={s(item.id)}>
                <td><Link href={`/admin/clubs?club=${s(item.id)}`}><strong>{s(item.name)}</strong></Link><small>{s(item.clubType)} · {s(item.slug)}</small><Identifier value={s(item.id)} /></td>
                <td>{s(item.municipality) || "Sin municipio"}<small>{s(item.province) || s(item.countryCode)}</small></td>
                <td><StatusBadge>{s(item.operationalStatus)}</StatusBadge><small>{s(item.verificationStatus)} · {s(item.partnershipStatus)}</small></td>
                <td>{s(item.primaryOwnerName)}<small><Identifier value={s(item.primaryOwnerId)} /></small></td>
                <td>{n(item.staffCount)}<small>{n(item.pendingInvitationCount)} invitaciones</small></td>
                <td>{n(item.linkedTeamCount)}</td>
                <td>{n(item.competitionCount)}<small>{item.canCreateCompetition ? "Entitled" : "Sin entitlement"}</small></td>
                <td>{n(item.revision)}<small>{formatAdminDate(item.updatedAt)}</small></td>
              </tr>
            ))}</tbody>
          </DataTable>
        ) : <EmptyState>No hay clubes creados.</EmptyState>}
        <Pagination page={data.page} pageSize={data.pageSize} total={data.total} path="/admin/clubs" />
      </Panel>

      {selected ? (
        <>
          <Panel title={`Staff de ${s(selected.club.name)}`}>
            {selected.memberships.length ? <DataTable label="Staff del club"><thead><tr><th>Usuario</th><th>Rol</th><th>Estado</th><th>Vigencia</th><th>Revisión</th></tr></thead><tbody>{selected.memberships.map((item) => <tr key={s(item.id)}><td><Identifier value={s(item.userId)} /></td><td>{s(item.role)}</td><td><StatusBadge>{s(item.status)}</StatusBadge></td><td>{formatAdminDate(item.validFrom)}<small>{item.expiresAt ? `Hasta ${formatAdminDate(item.expiresAt)}` : "Sin caducidad"}</small></td><td>{n(item.revision)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay staff.</EmptyState>}
          </Panel>

          <Panel title="Invitaciones pendientes">
            {selected.pendingInvitations.length ? <DataTable label="Invitaciones"><thead><tr><th>ID opaco</th><th>Destino</th><th>Rol</th><th>Caduca</th><th>Revisión</th></tr></thead><tbody>{selected.pendingInvitations.map((item) => <tr key={s(item.id)}><td><Identifier value={s(item.id)} /></td><td>{s(item.targetKind)}<small>{item.targetUserId ? <Identifier value={s(item.targetUserId)} /> : "Contacto protegido"}</small></td><td>{s(item.role)}</td><td>{formatAdminDate(item.expiresAt)}</td><td>{n(item.revision)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay invitaciones pendientes.</EmptyState>}
          </Panel>

          <Panel title="Equipos vinculados">
            {selected.teamRelationships.length ? <DataTable label="Relaciones Club–Equipo"><thead><tr><th>Equipo</th><th>Relación</th><th>Estado</th><th>Origen</th><th>Revisión</th></tr></thead><tbody>{selected.teamRelationships.map((item) => <tr key={s(item.id)}><td>{s(item.teamName)}<small><Identifier value={s(item.groupId)} /></small></td><td>{s(item.relationshipType)}</td><td><StatusBadge>{s(item.status)}</StatusBadge></td><td>{s(item.initiatedBy)}</td><td>{n(item.revision)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay equipos vinculados.</EmptyState>}
          </Panel>

          <Panel title="Competiciones del club">
            {selected.competitions.length ? <DataTable label="Competiciones"><thead><tr><th>Competición</th><th>Tipo</th><th>Estado</th><th>Visibilidad</th><th>Revisión</th></tr></thead><tbody>{selected.competitions.map((item) => <tr key={s(item.id)}><td>{s(item.name)}<small>{s(item.slug)}</small></td><td>{s(item.type)}</td><td><StatusBadge>{s(item.status)}</StatusBadge></td><td>{s(item.visibility)}</td><td>{n(item.revision)}<small>{formatAdminDate(item.updatedAt)}</small></td></tr>)}</tbody></DataTable> : <EmptyState>No hay competiciones de este club.</EmptyState>}
          </Panel>

          <Panel title="Últimos eventos del club">
            {selected.recentEvents.length ? <DataTable label="Auditoría de Club"><thead><tr><th>Acción</th><th>Agregado</th><th>Revisión</th><th>Secuencia</th><th>Confirmado</th></tr></thead><tbody>{selected.recentEvents.map((item) => <tr key={s(item.id)}><td><strong>{s(item.action)}</strong><small>{s(item.reasonCode)}</small></td><td>{s(item.aggregateType)}</td><td>{n(item.revision)}</td><td>{n(item.serverSequence)}</td><td>{formatAdminDate(item.confirmedAt)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay eventos del club.</EmptyState>}
          </Panel>
        </>
      ) : null}

      <Panel title="Actividad reciente">
        {data.events.length ? <DataTable label="Eventos recientes"><thead><tr><th>Acción</th><th>Club</th><th>Agregado</th><th>Revisión</th><th>Secuencia</th><th>Confirmado</th></tr></thead><tbody>{data.events.map((item) => <tr key={s(item.id)}><td><strong>{s(item.action)}</strong><small>{s(item.reasonCode)}</small></td><td><Identifier value={s(item.clubId)} /></td><td>{s(item.aggregateType)}</td><td>{n(item.revision)}</td><td>{n(item.serverSequence)}</td><td>{formatAdminDate(item.confirmedAt)}</td></tr>)}</tbody></DataTable> : <EmptyState>Aún no hay eventos de Club R2.</EmptyState>}
      </Panel>
    </>
  );
}

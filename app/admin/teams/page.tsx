import Link from "next/link";
import { DataTable, EmptyState, Identifier, PageHeader, Pagination, Panel, StatusBadge, formatAdminDate } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { listPlatformTeamOperationalStates, listPlatformTeams, paginationFromSearchParams } from "../_lib/platform-data";
import { teamOperationalStatusLabel } from "../../team-operational-contract";
import styles from "../platform-admin.module.css";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
function operationalTone(value: unknown): "danger" | "good" | "info" | "muted" | "warning" {
  if (value === "SUSPENDED" || value === "ARCHIVED") return "danger";
  if (value === "LIMITED") return "warning";
  if (value === "UNDER_REVIEW") return "info";
  if (value === "ACTIVE") return "good";
  return "muted";
}

export default async function PlatformTeamsPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("teams.read");
  const raw = await searchParams;
  const params = new URLSearchParams();
  Object.entries(raw).forEach(([key, value]) => params.set(key, first(value)));
  const { page, pageSize } = paginationFromSearchParams(params);
  const q = first(raw.q);
  const billing = first(raw.billing) || "all";
  const createdFrom = first(raw.createdFrom);
  const createdTo = first(raw.createdTo);
  const market = first(raw.market) || "all";
  const locality = first(raw.locality);
  const owner = first(raw.owner);
  const activity = first(raw.activity) || "all";
  const social = first(raw.social) || "all";
  const minimumLevel = first(raw.minimumLevel);
  const maximumLevel = first(raw.maximumLevel);
  const sort = first(raw.sort) || "updated_desc";
  const operationalStatus = first(raw.operationalStatus).toUpperCase();
  const [data, operational] = await Promise.all([
    listPlatformTeams(session, {
      activity, billing, createdFrom, createdTo, locality, market, maximumLevel, minimumLevel, owner,
      page, pageSize, query: q, social, sort,
    }),
    listPlatformTeamOperationalStates(session, { page, pageSize, query: q, status: operationalStatus }),
  ]);
  return (
    <>
      <PageHeader title="Equipos" subtitle="Vista global de identidad, actividad, estado operativo, Mercado y Billing independiente." />
      <form className={styles.filters}>
        <label>Buscar<input name="q" defaultValue={q} placeholder="Nombre o team code" /></label>
        <label>Estado operativo<select name="operationalStatus" defaultValue={operationalStatus}><option value="">Todos</option><option value="ACTIVE">Activo</option><option value="UNDER_REVIEW">En revisión</option><option value="LIMITED">Limitado</option><option value="SUSPENDED">Suspendido</option><option value="ARCHIVED">Archivado</option><option value="EXPIRING">Caduca pronto</option><option value="APPEALED">Con apelación</option><option value="COMPETITION_AFFECTED">Competición afectada</option></select></label>
        <label>Billing<select name="billing" defaultValue={billing}><option value="all">Todos</option><option value="trial">Trial</option><option value="trialing">Trialing</option><option value="active">Active</option><option value="past_due">Past due</option><option value="unpaid">Unpaid</option><option value="incomplete">Incomplete</option><option value="canceled">Canceled</option></select></label>
        <label>Alta desde<input name="createdFrom" type="date" defaultValue={createdFrom} /></label>
        <label>Alta hasta<input name="createdTo" type="date" defaultValue={createdTo} /></label>
        <label>Mercado<select name="market" defaultValue={market}><option value="all">Todos</option><option value="enabled">Retables</option><option value="disabled">No publicados</option></select></label>
        <label>Localidad<input name="locality" defaultValue={locality} placeholder="Zona de Mercado" /></label>
        <label>Owner<input name="owner" defaultValue={owner} placeholder="UUID exacto" /></label>
        <label>Actividad<select name="activity" defaultValue={activity}><option value="all">Todos</option><option value="active">Con miembros</option><option value="inactive">Sin miembros</option></select></label>
        <label>Estado social<select name="social" defaultValue={social}><option value="all">Todos</option><option value="restricted">Con restricciones</option><option value="clean">Sin restricciones</option></select></label>
        <label>Nivel mínimo<input name="minimumLevel" defaultValue={minimumLevel} inputMode="decimal" placeholder="0" /></label>
        <label>Nivel máximo<input name="maximumLevel" defaultValue={maximumLevel} inputMode="decimal" placeholder="100" /></label>
        <label>Orden<select name="sort" defaultValue={sort}><option value="updated_desc">Actividad reciente</option><option value="created_desc">Creación reciente</option><option value="name_asc">Nombre</option><option value="level_desc">Nivel</option></select></label>
        <button className={styles.primaryButton} type="submit">Aplicar filtros</button>
      </form>
      <Panel title="Seguridad operativa de equipos">
        {operational.items.length ? <DataTable label="Estado operativo canónico de equipos">
          <thead><tr><th>Equipo</th><th>Estado</th><th>Ámbitos</th><th>Revisión</th><th>Apelación</th><th>Salud</th><th>Revisión canónica</th></tr></thead>
          <tbody>{operational.items.map((item, index) => {
            const team = record(item);
            const health = record(team.health);
            const restrictions = Array.isArray(team.restrictions) ? team.restrictions : [];
            return <tr key={`${String(team.groupId)}-${index}`}>
              <td><Link href={`/admin/teams/${String(team.groupId)}`}>{String(team.teamName ?? "Equipo")}</Link><small>{String(team.teamCode ?? "Sin team code")}</small></td>
              <td><StatusBadge tone={operationalTone(team.effectiveStatus)}>{teamOperationalStatusLabel(team.effectiveStatus)}</StatusBadge></td>
              <td>{restrictions.length}<small>{String(team.continuityPolicy ?? "Sin política")}</small></td>
              <td><StatusBadge tone={team.reviewOpen ? "warning" : "muted"}>{team.reviewOpen ? "abierta" : "sin revisión"}</StatusBadge></td>
              <td><StatusBadge tone={team.appealOpen ? "info" : "muted"}>{team.appealOpen ? "abierta" : "sin apelación"}</StatusBadge></td>
              <td><StatusBadge tone={Number(health.issueCount) ? "warning" : "good"}>{String(health.status ?? "-")}</StatusBadge><small>{Number(health.issueCount) || 0} incidencias</small></td>
              <td>{String(team.revision ?? 0)}<small>seq {String(team.serverSequence ?? 0)}</small></td>
            </tr>;
          })}</tbody>
        </DataTable> : <EmptyState>No hay equipos para este filtro operativo.</EmptyState>}
        <Pagination page={operational.page} pageSize={operational.pageSize} total={operational.total} path="/admin/teams" query={{ activity, billing, createdFrom, createdTo, locality, market, maximumLevel, minimumLevel, operationalStatus, owner, q, social, sort }} />
      </Panel>
      <Panel>
        {data.items.length ? <DataTable label="Equipos de Pachangas IQ">
          <thead><tr><th>Equipo</th><th>Owner</th><th>Miembros</th><th>Actividad</th><th>Mercado</th><th>Billing</th><th>Actualizado</th></tr></thead>
          <tbody>{data.items.map((team) => (
            <tr key={team.id}>
              <td><Link href={`/admin/teams/${team.id}`}>{team.name}</Link><small>{team.team_code || "Sin team code"}</small><Identifier value={team.id} /></td>
              <td>{team.ownerName}<small><Identifier value={team.owner_id} /></small></td>
              <td>{team.memberCount}<small>{team.activeRestrictionCount ? `${team.activeRestrictionCount} con restricción` : "Sin restricciones activas"}</small></td>
              <td><StatusBadge>{team.active ? "activo" : "sin miembros"}</StatusBadge></td>
              <td><StatusBadge>{team.market && typeof team.market === "object" && "enabled" in team.market && team.market.enabled ? "publicado" : "cerrado"}</StatusBadge></td>
              <td><StatusBadge>{team.billing_status ?? "trial"}</StatusBadge><small>{team.billing_interval ?? `${team.trialRemaining} partidos trial restantes`}</small></td>
              <td>{formatAdminDate(team.updated_at)}</td>
            </tr>
          ))}</tbody>
        </DataTable> : <EmptyState>No hay equipos para estos filtros.</EmptyState>}
        <Pagination page={data.page} pageSize={data.pageSize} total={data.total} path="/admin/teams" query={{ activity, billing, createdFrom, createdTo, locality, market, maximumLevel, minimumLevel, operationalStatus, owner, q, social, sort }} />
      </Panel>
    </>
  );
}

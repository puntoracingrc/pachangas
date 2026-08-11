import Link from "next/link";
import { DataTable, EmptyState, Identifier, PageHeader, Pagination, Panel, StatusBadge, formatAdminDate } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { listPlatformTeams, paginationFromSearchParams } from "../_lib/platform-data";
import styles from "../platform-admin.module.css";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }

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
  const data = await listPlatformTeams(session, {
    activity, billing, createdFrom, createdTo, locality, market, maximumLevel, minimumLevel, owner,
    page, pageSize, query: q, social, sort,
  });
  return (
    <>
      <PageHeader title="Equipos" subtitle="Vista global de equipos, owners, actividad, Mercado y estado de billing." />
      <form className={styles.filters}>
        <label>Buscar<input name="q" defaultValue={q} placeholder="Nombre o team code" /></label>
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
        <Pagination page={data.page} pageSize={data.pageSize} total={data.total} path="/admin/teams" query={{ activity, billing, createdFrom, createdTo, locality, market, maximumLevel, minimumLevel, owner, q, social, sort }} />
      </Panel>
    </>
  );
}

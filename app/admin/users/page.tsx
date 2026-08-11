import Link from "next/link";
import { DataTable, EmptyState, Identifier, PageHeader, Pagination, Panel, StatusBadge, formatAdminDate } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { listPlatformUsers, paginationFromSearchParams } from "../_lib/platform-data";
import styles from "../platform-admin.module.css";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }

export default async function PlatformUsersPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("users.read");
  const raw = await searchParams;
  const params = new URLSearchParams();
  Object.entries(raw).forEach(([key, value]) => params.set(key, first(value)));
  const { page, pageSize } = paginationFromSearchParams(params);
  const q = first(raw.q);
  const status = first(raw.status) || "all";
  const createdFrom = first(raw.createdFrom);
  const createdTo = first(raw.createdTo);
  const sort = first(raw.sort) || "created_desc";
  const data = await listPlatformUsers(session, { createdFrom, createdTo, page, pageSize, query: q, sort, status });
  return (
    <>
      <PageHeader title="Usuarios" subtitle="Auth se consulta por lotes en servidor; nunca se envían tokens ni secretos al navegador." />
      <form className={styles.filters}>
        <label>Buscar<input name="q" defaultValue={q} placeholder="Nombre, email o UUID" /></label>
        <label>Estado<select name="status" defaultValue={status}><option value="all">Todos</option><option value="active">Activo</option><option value="suspended">Suspendido</option><option value="banned">Baneado</option></select></label>
        <label>Alta desde<input name="createdFrom" type="date" defaultValue={createdFrom} /></label>
        <label>Alta hasta<input name="createdTo" type="date" defaultValue={createdTo} /></label>
        <label>Orden<select name="sort" defaultValue={sort}><option value="created_desc">Alta reciente</option><option value="created_asc">Alta antigua</option><option value="last_sign_in_desc">Último acceso</option><option value="name_asc">Nombre</option></select></label>
        <button className={styles.primaryButton} type="submit">Aplicar filtros</button>
      </form>
      <Panel>
        {data.items.length ? (
          <DataTable label="Usuarios de plataforma">
            <thead><tr><th>Usuario</th><th>Estado</th><th>Equipos</th><th>Rol plataforma</th><th>Último acceso</th><th>Alta</th></tr></thead>
            <tbody>{data.items.map((user) => (
              <tr key={user.id}>
                <td><Link href={`/admin/users/${user.id}`}>{user.name}</Link><small>{user.email ?? "Sin email"}</small><Identifier value={user.id} /></td>
                <td><StatusBadge>{user.status}</StatusBadge>{user.authSyncState !== "confirmed" ? <small>Auth: {user.authSyncState}</small> : null}</td>
                <td>{user.teamCount}<small>{user.ownedTeamCount} como owner</small></td>
                <td>{user.platformRole ? <StatusBadge tone="info">{user.platformRole}</StatusBadge> : <span className={styles.muted}>Sin rol</span>}</td>
                <td>{formatAdminDate(user.lastSignInAt)}</td>
                <td>{formatAdminDate(user.createdAt)}</td>
              </tr>
            ))}</tbody>
          </DataTable>
        ) : <EmptyState>No hay usuarios para estos filtros.</EmptyState>}
        <Pagination page={data.page} pageSize={data.pageSize} total={data.total} path="/admin/users" query={{ createdFrom, createdTo, q, sort, status }} />
      </Panel>
    </>
  );
}

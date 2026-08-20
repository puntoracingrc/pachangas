import Link from "next/link";
import { DataTable, EmptyState, Identifier, PageHeader, Pagination, Panel, StatusBadge, formatAdminDate } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { listPlatformChallenges, paginationFromSearchParams } from "../_lib/platform-data";
import styles from "../platform-admin.module.css";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export default async function PlatformChallengesPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("challenges.read");
  const raw = await searchParams;
  const params = new URLSearchParams(); Object.entries(raw).forEach(([key, value]) => params.set(key, first(value)));
  const { page, pageSize } = paginationFromSearchParams(params);
  const q = first(raw.q);
  const status = first(raw.status) || "all";
  const groupId = first(raw.groupId);
  const dateFrom = first(raw.dateFrom);
  const dateTo = first(raw.dateTo);
  const sort = first(raw.sort) || "updated_desc";
  const data = await listPlatformChallenges(session, { dateFrom, dateTo, groupId, page, pageSize, query: q, sort, status });
  return (
    <>
      <PageHeader title="Retos" subtitle="Seguimiento del flujo Team A → propuesta → aceptación/contrapropuesta → partido → evidencia." />
      <form className={styles.filters}><label>Buscar<input name="q" defaultValue={q} placeholder="Reto, equipo o campo" /></label><label>Group ID<input name="groupId" defaultValue={groupId} placeholder="UUID de equipo" /></label><label>Desde<input name="dateFrom" type="date" defaultValue={dateFrom} /></label><label>Hasta<input name="dateTo" type="date" defaultValue={dateTo} /></label><label>Estado<select name="status" defaultValue={status}><option value="all">Todos</option><option value="proposed">Proposed</option><option value="changes_proposed">Changes proposed</option><option value="accepted">Accepted</option><option value="rejected">Rejected</option><option value="cancelled">Cancelled</option><option value="expired">Expired</option></select></label><label>Orden<select name="sort" defaultValue={sort}><option value="updated_desc">Último cambio</option><option value="date_asc">Fecha próxima</option><option value="date_desc">Fecha reciente</option><option value="created_desc">Creación</option></select></label><button className={styles.primaryButton} type="submit">Aplicar filtros</button></form>
      <Panel>{data.items.length ? <DataTable label="Retos globales"><thead><tr><th>Reto</th><th>Emisor</th><th>Receptor</th><th>Estado</th><th>Propuesta</th><th>Fecha</th><th>Campo</th><th>Actualizado</th></tr></thead><tbody>{data.items.map((challenge) => { const sender = record(challenge.sender); const receiver = record(challenge.receiver); return <tr key={challenge.id}><td><Link href={`/admin/challenges/${challenge.id}`}><Identifier value={challenge.id} /></Link></td><td><Link href={`/admin/teams/${challenge.sender_group_id}`}>{String(sender.name ?? "Equipo")}</Link><small>{String(sender.team_code ?? "")}</small></td><td><Link href={`/admin/teams/${challenge.receiver_group_id}`}>{String(receiver.name ?? "Equipo")}</Link><small>{String(receiver.team_code ?? "")}</small></td><td><StatusBadge>{challenge.status}</StatusBadge></td><td>#{challenge.proposal_number}<small>rev {challenge.revision}</small></td><td>{formatAdminDate(challenge.scheduled_at)}</td><td>{String(challenge.field_name ?? "Por definir")}<small>{String(challenge.modality ?? "-")}</small></td><td>{formatAdminDate(challenge.updated_at)}</td></tr>; })}</tbody></DataTable> : <EmptyState>No hay Retos para estos filtros.</EmptyState>}<Pagination page={data.page} pageSize={data.pageSize} total={data.total} path="/admin/challenges" query={{ dateFrom, dateTo, groupId, q, sort, status }} /></Panel>
    </>
  );
}

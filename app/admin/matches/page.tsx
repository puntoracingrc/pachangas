import Link from "next/link";
import { DataTable, EmptyState, Identifier, PageHeader, Pagination, Panel, StatusBadge, formatAdminDate } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { listPlatformMatches, paginationFromSearchParams } from "../_lib/platform-data";
import styles from "../platform-admin.module.css";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }

export default async function PlatformMatchesPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("matches.read");
  const raw = await searchParams;
  const params = new URLSearchParams(); Object.entries(raw).forEach(([key, value]) => params.set(key, first(value)));
  const { page, pageSize } = paginationFromSearchParams(params);
  const q = first(raw.q);
  const state = first(raw.state) || "all";
  const groupId = first(raw.groupId);
  const dateFrom = first(raw.dateFrom);
  const dateTo = first(raw.dateTo);
  const type = first(raw.type) || "all";
  const scope = first(raw.scope) || "all";
  const sort = first(raw.sort) || "date_asc";
  const data = await listPlatformMatches(session, { dateFrom, dateTo, groupId, page, pageSize, query: q, scope, sort, state, type });
  return (
    <>
      <PageHeader title="Partidos" subtitle="Read model central: estado, revisión, alineación y resultado confirmado." />
      <form className={styles.filters}>
        <label>Buscar<input name="q" defaultValue={q} placeholder="Partido, equipo o Reto" /></label>
        <label>Group ID<input name="groupId" defaultValue={groupId} placeholder="UUID de equipo" /></label>
        <label>Desde<input name="dateFrom" type="date" defaultValue={dateFrom} /></label>
        <label>Hasta<input name="dateTo" type="date" defaultValue={dateTo} /></label>
        <label>Ámbito<select name="scope" defaultValue={scope}><option value="all">Todos</option><option value="internal">Interno</option><option value="challenge">Reto</option></select></label>
        <label>Modalidad<select name="type" defaultValue={type}><option value="all">Todas</option><option value="sala">Fútbol sala</option><option value="futbol7">Fútbol 7</option><option value="futbol11">Fútbol 11</option></select></label>
        <label>Estado<select name="state" defaultValue={state}><option value="all">Todos</option><option value="draft">Draft</option><option value="published">Published</option><option value="lineup_open">Lineup open</option><option value="lineup_closed">Lineup closed</option><option value="played">Played</option><option value="finalized">Finalized</option><option value="historical">Historical</option></select></label>
        <label>Orden<select name="sort" defaultValue={sort}><option value="date_asc">Fecha próxima</option><option value="date_desc">Fecha reciente</option><option value="updated_desc">Último cambio</option><option value="state_asc">Estado</option></select></label>
        <button className={styles.primaryButton} type="submit">Aplicar filtros</button>
      </form>
      <Panel>{data.items.length ? <DataTable label="Partidos globales"><thead><tr><th>Partido</th><th>Equipos</th><th>Fecha</th><th>Modalidad</th><th>Estado</th><th>Resultado</th><th>Revisión</th><th>Actualizado</th></tr></thead><tbody>{data.items.map((match) => {
        const detailHref = match.scope === "challenge" && match.challenge_id
          ? `/admin/challenges/${match.challenge_id}`
          : `/admin/matches/${match.group_id}/${encodeURIComponent(match.match_id)}`;
        return <tr key={`${match.scope}:${match.group_id}:${match.match_id}`}><td><Link href={detailHref}>{match.title}</Link><small><StatusBadge tone="info">{match.scope === "challenge" ? "Reto" : "Interno"}</StatusBadge> <Identifier value={match.match_id} /></small></td><td><Link href={`/admin/teams/${match.group_id}`}>{match.groupName}</Link>{match.secondaryGroupId ? <small>vs <Link href={`/admin/teams/${match.secondaryGroupId}`}>{match.secondaryGroupName}</Link></small> : <small>{match.teamCode}</small>}</td><td>{formatAdminDate(match.date)}</td><td>{match.modality ?? "No normalizada"}</td><td><StatusBadge>{match.match_state}</StatusBadge><small>{match.lineup_closed ? "Cerrado" : "En curso"}</small></td><td>{match.score_a == null ? "Pendiente" : `${match.score_a} - ${match.score_b}`}</td><td>{match.match_version}</td><td>{formatAdminDate(match.updated_at)}</td></tr>;
      })}</tbody></DataTable> : <EmptyState>No hay partidos para estos filtros.</EmptyState>}<Pagination page={data.page} pageSize={data.pageSize} total={data.total} path="/admin/matches" query={{ dateFrom, dateTo, groupId, q, scope, sort, state, type }} /></Panel>
    </>
  );
}

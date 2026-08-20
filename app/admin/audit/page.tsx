import { DataTable, Identifier, PageHeader, Pagination, Panel, StatusBadge, formatAdminDate } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { getPlatformSection, paginationFromSearchParams } from "../_lib/platform-data";

function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }

export default async function PlatformAuditPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("audit.read");
  const raw = await searchParams;
  const params = new URLSearchParams();
  Object.entries(raw).forEach(([key, value]) => params.set(key, first(value)));
  const { page, pageSize } = paginationFromSearchParams(params, 50);
  const data = await getPlatformSection(session, "audit", page, pageSize);
  const items = Array.isArray(data.items) ? data.items.map(record) : [];
  return <><PageHeader title="Auditoría administrativa" subtitle="Orden autoritativo por server_sequence. Los retries con el mismo operationId no duplican acciones." />
    <Panel title={`${Number(data.total) || 0} acciones registradas`}><DataTable label="Ledger de administración"><thead><tr><th>Secuencia</th><th>Acción</th><th>Actor</th><th>Objetivo</th><th>Motivo</th><th>Operation ID</th><th>Fecha</th></tr></thead><tbody>{items.map((item) => <tr key={String(item.id)}><td>{String(item.serverSequence ?? 0)}</td><td><StatusBadge tone="info">{String(item.action ?? "-")}</StatusBadge></td><td><Identifier value={typeof item.actorUserId === "string" ? item.actorUserId : null} /><small>{String(item.actorRole ?? "-")}</small></td><td>{String(item.targetType ?? "-")}<small><Identifier value={String(item.targetId ?? "")} /></small></td><td>{String(item.reason ?? "-")}</td><td><Identifier value={String(item.operationId ?? "")} /></td><td>{formatAdminDate(item.createdAt)}</td></tr>)}</tbody></DataTable><Pagination page={page} pageSize={pageSize} total={Number(data.total) || 0} path="/admin/audit" /></Panel>
  </>;
}

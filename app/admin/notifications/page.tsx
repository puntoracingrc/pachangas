import { AnnouncementComposer } from "../_components/announcement-composer";
import { DataTable, Metric, MetricGrid, PageHeader, Panel, StatusBadge, formatAdminDate } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { hasPlatformCapability } from "../_lib/platform-contract";
import { getPlatformSection } from "../_lib/platform-data";

function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export default async function PlatformNotificationsPage() {
  const session = await requirePlatformPage("notifications.read");
  const data = await getPlatformSection(session, "notifications", 1, 50);
  const metrics = record(data.metrics);
  const announcements = Array.isArray(data.announcements) ? data.announcements.map(record) : [];
  return <><PageHeader title="Notificaciones" subtitle="Volumen, entrega y anuncios administrativos con borrador, audiencia acotada y envío idempotente." />
    <MetricGrid><Metric label="Total" value={Number(metrics.total) || 0} /><Metric label="Sin leer" value={Number(metrics.unread) || 0} /><Metric label="Críticas" value={Number(metrics.critical) || 0} tone={Number(metrics.critical) ? "warning" : "neutral"} /><Metric label="Entrega pendiente" value={Number(metrics.pendingDelivery) || 0} /><Metric label="Entrega fallida" value={Number(metrics.failedDelivery) || 0} tone={Number(metrics.failedDelivery) ? "danger" : "good"} /></MetricGrid>
    {hasPlatformCapability(session.access, "notifications.send") ? <Panel title="Nuevo anuncio administrativo"><AnnouncementComposer /></Panel> : null}
    <Panel title="Anuncios"><DataTable label="Anuncios de plataforma"><thead><tr><th>Anuncio</th><th>Audiencia</th><th>Estado</th><th>Destinatarios</th><th>Creado</th><th>Enviado</th></tr></thead><tbody>{announcements.map((item) => <tr key={String(item.id)}><td>{String(item.title ?? "-")}</td><td>{String(item.audienceType ?? "-")}<small>{String(item.audienceId ?? "")}</small></td><td><StatusBadge>{String(item.state ?? "-")}</StatusBadge></td><td>{Number(item.recipientCount) || 0}</td><td>{formatAdminDate(item.createdAt)}</td><td>{formatAdminDate(item.sentAt)}</td></tr>)}</tbody></DataTable></Panel>
  </>;
}

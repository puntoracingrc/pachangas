import { DataTable, Identifier, Metric, MetricGrid, PageHeader, Panel, StatusBadge, formatAdminDate } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { getPlatformSection } from "../_lib/platform-data";

function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export default async function PlatformRewardsPage() {
  const session = await requirePlatformPage("rewards.read");
  const data = await getPlatformSection(session, "rewards", 1, 50);
  const metrics = record(data.metrics);
  const items = Array.isArray(data.items) ? data.items.map(record) : [];
  return <><PageHeader title="Rewards Center" subtitle="Trazabilidad de achievement → grant → caja → apertura → inventario. No concede premios manualmente." />
    <MetricGrid><Metric label="Achievements" value={Number(metrics.achievements) || 0} /><Metric label="Reward grants" value={Number(metrics.rewardGrants) || 0} /><Metric label="Cajas pendientes" value={Number(metrics.boxesPending) || 0} tone={Number(metrics.boxesPending) ? "warning" : "neutral"} /><Metric label="Cajas abiertas" value={Number(metrics.boxesOpened) || 0} /><Metric label="Already owned" value={Number(metrics.alreadyOwned) || 0} tone={Number(metrics.alreadyOwned) ? "warning" : "neutral"} /></MetricGrid>
    <Panel title="Grants recientes"><DataTable label="Reward grants"><thead><tr><th>Grant</th><th>Reward</th><th>Estado</th><th>Equipo</th><th>Jugador</th><th>Achievement</th><th>Fecha</th></tr></thead><tbody>{items.map((item) => <tr key={String(item.id)}><td><Identifier value={String(item.id)} /></td><td>{String(item.key ?? "-")}<small>{String(item.kind ?? "-")}</small></td><td><StatusBadge>{String(item.state ?? "-")}</StatusBadge></td><td><Identifier value={typeof item.groupId === "string" ? item.groupId : null} /></td><td><Identifier value={typeof item.playerProfileId === "string" ? item.playerProfileId : null} /></td><td><Identifier value={typeof item.achievementGrantId === "string" ? item.achievementGrantId : null} /></td><td>{formatAdminDate(item.grantedAt)}</td></tr>)}</tbody></DataTable></Panel>
  </>;
}

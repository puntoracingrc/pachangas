import Link from "next/link";
import { PageHeader, Metric, MetricGrid, Panel, StatusBadge } from "./_components/platform-ui";
import { requirePlatformPage } from "./_lib/platform-auth";
import { getPlatformOverview } from "./_lib/platform-data";
import styles from "./platform-admin.module.css";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
function count(source: Record<string, unknown>, key: string) { return Number(source[key]) || 0; }

export default async function PlatformOverviewPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("overview.read");
  const params = await searchParams;
  const period = first(params.period) || "today";
  const overview = await getPlatformOverview(session, period);
  const users = record(overview.users);
  const teams = record(overview.teams);
  const players = record(overview.players);
  const matches = record(overview.matches);
  const challenges = record(overview.challenges);
  const market = record(overview.market);
  const moderation = record(overview.moderation);
  const billing = record(overview.billing);
  const rewards = record(overview.rewards);
  const notifications = record(overview.notifications);
  const alerts = record(overview.alerts);
  const periods = [["today", "Hoy"], ["7d", "7 días"], ["30d", "30 días"], ["season", "Temporada"]] as const;

  return (
    <>
      <PageHeader
        title="Pachangas IQ, hoy"
        subtitle="Estado operativo global. Cada cifra conserva su definición y su periodo."
        actions={<div className={styles.segmented}>{periods.map(([key, label]) => <Link className={period === key ? styles.segmentedActive : ""} href={`/admin?period=${key}`} key={key}>{label}</Link>)}</div>}
      />
      <MetricGrid>
        <Metric label="Usuarios" value={count(users, "total").toLocaleString("es-ES")} hint={`${count(users, "new")} altas en el periodo`} />
        <Metric label="Equipos" value={count(teams, "total").toLocaleString("es-ES")} hint={`${count(teams, "active")} con miembros`} />
        <Metric label="Jugadores" value={count(players, "registered").toLocaleString("es-ES")} hint={`${count(market, "players")} en Mercado`} />
        <Metric label="Partidos" value={count(matches, "total").toLocaleString("es-ES")} hint={`${count(matches, "changedInPeriod")} actualizados en el periodo · ${count(matches, "finalized")} finalizados`} />
        <Metric label="Retos" value={count(challenges, "total").toLocaleString("es-ES")} hint={`${count(challenges, "createdInPeriod")} creados en el periodo · ${count(challenges, "accepted")} aceptados`} />
      </MetricGrid>

      <div className={styles.overviewColumns}>
        <Panel title="Atención operativa">
          <div className={styles.alertList}>
            <Link href="/admin/conduct"><StatusBadge tone={count(alerts, "moderationUrgent") ? "danger" : "good"}>Moderación</StatusBadge><span>{count(alerts, "moderationUrgent")} casos urgentes</span></Link>
            <Link href="/admin/billing"><StatusBadge tone={count(alerts, "billingFailures") ? "warning" : "good"}>Billing</StatusBadge><span>{count(alerts, "billingFailures")} equipos con fallo de cobro</span></Link>
            <Link href="/admin/billing"><StatusBadge tone={count(alerts, "webhookFailures") ? "danger" : "good"}>Stripe</StatusBadge><span>{count(alerts, "webhookFailures")} webhooks fallidos</span></Link>
            <Link href="/admin/system"><StatusBadge tone={count(alerts, "newClientErrors") ? "warning" : "good"}>Cliente</StatusBadge><span>{count(alerts, "newClientErrors")} errores vistos en 24 h</span></Link>
          </div>
        </Panel>
        <Panel title="Moderación y acceso social">
          <div className={styles.compactMetrics}>
            <span><strong>{count(moderation, "pending")}</strong> pendientes</span>
            <span><strong>{count(moderation, "urgent")}</strong> urgentes</span>
            <span><strong>{count(moderation, "restrictedUsers")}</strong> usuarios restringidos</span>
          </div>
        </Panel>
      </div>

      <div className={styles.overviewColumns}>
        <Panel title="Billing local">
          <div className={styles.compactMetrics}>
            <span><strong>{count(billing, "trial")}</strong> trial</span>
            <span><strong>{count(billing, "active")}</strong> activas</span>
            <span><strong>{count(billing, "pastDue")}</strong> con incidencia</span>
            <span><strong>{count(billing, "canceled")}</strong> canceladas</span>
          </div>
        </Panel>
        <Panel title="Rewards y avisos">
          <div className={styles.compactMetrics}>
            <span><strong>{count(rewards, "pendingBoxes")}</strong> cajas pendientes</span>
            <span><strong>{count(rewards, "openedBoxes")}</strong> cajas abiertas</span>
            <span><strong>{count(notifications, "unread")}</strong> avisos sin leer</span>
            <span><strong>{count(notifications, "failedDeliveries")}</strong> entregas fallidas</span>
          </div>
        </Panel>
      </div>
    </>
  );
}

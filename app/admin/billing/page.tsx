import Link from "next/link";
import { DataTable, Identifier, Metric, MetricGrid, PageHeader, Panel, StatusBadge, formatAdminDate } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { getPlatformSection, listPlatformTeams } from "../_lib/platform-data";
import { getStripeHealth } from "../_lib/platform-external";
import styles from "../platform-admin.module.css";

type SearchParams = Promise<Record<string, string | string[] | undefined>>;
function first(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] ?? "" : value ?? ""; }
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
function rows(value: unknown) { return Array.isArray(value) ? value.map(record) : []; }
function money(amount: unknown, currency: unknown) { const number = Number(amount); return Number.isFinite(number) ? new Intl.NumberFormat("es-ES", { currency: String(currency || "eur").toUpperCase(), style: "currency" }).format(number / 100) : "No disponible"; }

export default async function PlatformBillingPage({ searchParams }: { searchParams: SearchParams }) {
  const session = await requirePlatformPage("billing.read");
  const raw = await searchParams;
  const teamFilter = first(raw.team);
  const refresh = first(raw.refresh) === "1";
  const [local, stripeRaw, trialTeams] = await Promise.all([
    getPlatformSection(session, "billing", 1, 50),
    getStripeHealth(refresh),
    listPlatformTeams(session, { billing: "trial", market: "all", page: 1, pageSize: 100 }),
  ]);
  const metrics = record(local.metrics);
  const stripe = record(stripeRaw);
  const subscriptions = record(stripe.subscriptions);
  const payments = record(stripe.payments);
  const invoices = record(stripe.invoices);
  const reconciliation = record(stripe.reconciliation);
  const reconciliations = rows(reconciliation.items).filter((item) => !teamFilter || item.groupId === teamFilter);
  const webhooks = rows(local.webhooks);
  const estimatedMrr = rows(stripe.estimatedMrr);
  const estimatedArr = rows(stripe.estimatedArr);
  return <><PageHeader title="Billing y Stripe" subtitle="El estado local y el estado real de Stripe se comparan; ninguna divergencia se corrige automáticamente." actions={<Link className={styles.secondaryButton} href="/admin/billing?refresh=1">Actualizar métricas</Link>} />
    <MetricGrid>
      <Metric label="Suscripciones locales" value={Number(metrics.active) || 0} hint={`${Number(metrics.trial) || 0} equipos en trial`} />
      <Metric label="MRR estimado" value={estimatedMrr.length ? estimatedMrr.map((item) => money(item.amount, item.currency)).join(" · ") : "No disponible"} hint="Derivado de la muestra de subscriptions Stripe" />
      <Metric label="ARR estimado" value={estimatedArr.length ? estimatedArr.map((item) => money(item.amount, item.currency)).join(" · ") : "No disponible"} hint="MRR estimado × 12" />
      <Metric label="Pagos fallidos" value={Number(payments.failed) || 0} tone={Number(payments.failed) ? "danger" : "good"} hint={payments.hasMore ? "Muestra reciente truncada" : "Muestra reciente completa"} />
      <Metric label="Desajustes" value={Number(reconciliation.mismatch) || 0} tone={Number(reconciliation.mismatch) ? "danger" : "good"} hint={`${Number(reconciliation.unknown) || 0} sin diagnóstico concluyente`} />
    </MetricGrid>
    <Panel title="Estado del conector Stripe"><div className={styles.healthSummary}><StatusBadge>{String(stripe.state ?? "UNKNOWN")}</StatusBadge><span>{stripe.configured ? `Credencial: ${String(stripe.credentialMode ?? "desconocida")}` : String(stripe.reason ?? "Integración no configurada")}</span><span>Actualizado: {formatAdminDate(stripe.measuredAt)}</span>{stripe.credentialMode === "broad-key-fallback" ? <strong>Recomendación: configurar STRIPE_ADMIN_RESTRICTED_KEY de solo lectura.</strong> : null}</div></Panel>
    <div className={styles.overviewColumns}>
      <Panel title="Stripe: suscripciones e invoices"><div className={styles.compactMetrics}><span><strong>{Number(record(subscriptions.counts).active) || 0}</strong> active</span><span><strong>{Number(record(subscriptions.counts).trialing) || 0}</strong> trialing</span><span><strong>{Number(invoices.paid) || 0}</strong> invoices pagadas</span><span><strong>{Number(invoices.open) || 0}</strong> invoices abiertas</span></div></Panel>
      <Panel title="Trial local"><div className={styles.compactList}>{trialTeams.items.slice().sort((a, b) => a.trialRemaining - b.trialRemaining).slice(0, 12).map((team) => <Link href={`/admin/teams/${team.id}`} key={team.id}><strong>{team.name}</strong><span>{team.billing_trial_finalized_matches ?? 0} usados · {team.trialRemaining} restantes</span></Link>)}</div></Panel>
    </div>
    <Panel title="Reconciliación local / Stripe"><DataTable label="Reconciliación de suscripciones"><thead><tr><th>Equipo</th><th>Local</th><th>Stripe</th><th>Diagnóstico</th><th>Subscription</th></tr></thead><tbody>{reconciliations.map((item) => <tr key={String(item.groupId)}><td><Link href={`/admin/teams/${String(item.groupId)}`}>{String(item.groupName ?? "Equipo")}</Link></td><td><StatusBadge>{String(item.localStatus ?? "-")}</StatusBadge></td><td><StatusBadge>{String(item.stripeStatus ?? "UNKNOWN")}</StatusBadge></td><td><StatusBadge>{String(item.state ?? "UNKNOWN")}</StatusBadge><small>{Array.isArray(item.differences) ? item.differences.join(", ") : String(item.reason ?? "")}</small></td><td><Identifier value={typeof item.subscriptionId === "string" ? item.subscriptionId : null} /></td></tr>)}</tbody></DataTable></Panel>
    <Panel title="Webhook health"><DataTable label="Webhooks Stripe sanitizados"><thead><tr><th>Evento</th><th>Tipo</th><th>Estado</th><th>Procesado</th><th>Error sanitizado</th></tr></thead><tbody>{webhooks.map((item) => <tr key={String(item.eventId)}><td><Identifier value={String(item.eventId)} /></td><td>{String(item.eventType ?? "-")}</td><td><StatusBadge>{String(item.status ?? "-")}</StatusBadge></td><td>{formatAdminDate(item.processedAt)}</td><td>{String(item.error ?? "-")}</td></tr>)}</tbody></DataTable></Panel>
    <Panel title="Pagos recientes"><DataTable label="PaymentIntents recientes"><thead><tr><th>Pago</th><th>Estado</th><th>Importe recibido</th><th>Customer</th><th>Fecha</th></tr></thead><tbody>{rows(payments.recent).map((item) => <tr key={String(item.id)}><td><Identifier value={String(item.id)} /></td><td><StatusBadge>{String(item.status ?? "-")}</StatusBadge></td><td>{money(item.amount, item.currency)}</td><td><Identifier value={typeof item.customerId === "string" ? item.customerId : null} /></td><td>{formatAdminDate(item.createdAt)}</td></tr>)}</tbody></DataTable></Panel>
  </>;
}

"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { clientWriteFetch } from "../../pwa-client-bridge";
import {
  organizerBillingArray,
  organizerBillingBoolean,
  organizerBillingMoney,
  organizerBillingNumber,
  organizerBillingRecord,
  organizerBillingStatus,
  organizerBillingText,
  type OrganizerBillingJson,
} from "../../organizer-billing-contract";
import { DataTable, Identifier, Metric, MetricGrid, Panel, StatusBadge, formatAdminDate } from "../_components/platform-ui";
import styles from "../platform-admin.module.css";

const settingsAggregateId = "7b000000-0000-4000-8000-000000000099";
const flagControls = [
  ["foundationEnabled", "foundation_enabled", "Foundation"],
  ["planCatalogEnabled", "plan_catalog_enabled", "Catalogo"],
  ["partnerGrantsEnabled", "partner_grants_enabled", "Partnerships"],
  ["billingAccountsEnabled", "billing_accounts_enabled", "Cuentas"],
  ["organizerUiEnabled", "organizer_ui_enabled", "UI de owners"],
  ["webhookIngestEnabled", "webhook_ingest_enabled", "Webhooks"],
  ["stripeSandboxEnabled", "stripe_sandbox_enabled", "Stripe sandbox"],
  ["portalEnabled", "portal_enabled", "Portal Stripe"],
  ["reconciliationEnabled", "reconciliation_enabled", "Reconciliacion"],
  ["demoWorldV28Enabled", "demo_world_v28_enabled", "Demo World V2.8"],
  ["livePricesApproved", "live_prices_approved", "Precios live aprobados"],
  ["liveCheckoutEnabled", "live_checkout_enabled", "Checkout live"],
] as const;

type PendingOperation = { id: string; key: string };

function jsonBody(response: Response) {
  return response.json().catch(() => ({})) as Promise<OrganizerBillingJson>;
}

export function OrganizerBillingAdminClient({ canApproveLive, canWrite, canonical, stripe }: {
  canApproveLive: boolean;
  canWrite: boolean;
  canonical: OrganizerBillingJson;
  stripe: OrganizerBillingJson;
}) {
  const router = useRouter();
  const pending = useRef<PendingOperation | null>(null);
  const [busyKey, setBusyKey] = useState("");
  const [message, setMessage] = useState("");
  const [reason, setReason] = useState("");
  const [taxHealth, setTaxHealth] = useState(organizerBillingText(organizerBillingRecord(canonical.settings).taxHealth, "UNCONFIGURED"));
  const [pricePlan, setPricePlan] = useState("CLUB_ORGANIZER");
  const [priceMode, setPriceMode] = useState("test");
  const [priceInterval, setPriceInterval] = useState("month");
  const [productId, setProductId] = useState("");
  const [priceId, setPriceId] = useState("");
  const [currency, setCurrency] = useState("eur");
  const [unitAmount, setUnitAmount] = useState("");
  const [taxBehavior, setTaxBehavior] = useState("unspecified");
  const [priceApproved, setPriceApproved] = useState(false);
  const [organizerKind, setOrganizerKind] = useState("CLUB");
  const [organizerId, setOrganizerId] = useState("");
  const [manualPlan, setManualPlan] = useState("CLUB_PARTNER");
  const [grantExpiresAt, setGrantExpiresAt] = useState("");
  const [renewExpiresAt, setRenewExpiresAt] = useState("");

  const settings = organizerBillingRecord(canonical.settings);
  const metrics = organizerBillingRecord(canonical.metrics);
  const accounts = organizerBillingArray(canonical.accounts);
  const priceMappings = organizerBillingArray(canonical.priceMappings);
  const webhooks = organizerBillingArray(canonical.webhooks);
  const reconciliations = organizerBillingArray(canonical.reconciliations);
  const grants = organizerBillingArray(canonical.accessGrants);

  async function run(action: string, aggregateId: string, expectedRevision: number, payload: OrganizerBillingJson) {
    const key = JSON.stringify({ action, aggregateId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusyKey(key);
    setMessage("");
    try {
      const response = await clientWriteFetch("api:platform-admin-billing", "/api/platform-admin/billing", {
        body: JSON.stringify({ action, aggregateId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { "Content-Type": "application/json", "X-Pachangas-Platform-Admin": "1" },
        method: "POST",
      });
      const body = await jsonBody(response);
      if (!response.ok) throw new Error(organizerBillingText(body.message, organizerBillingText(body.error, "Operacion no confirmada")));
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Operacion no confirmada");
    } finally {
      setBusyKey("");
    }
  }

  const reasonReady = reason.trim().length >= 3;
  const selectedMapping = priceMappings.find((item) => organizerBillingText(item.planCode) === pricePlan
    && organizerBillingText(item.mode) === priceMode && organizerBillingText(item.interval) === priceInterval);
  const priceRevision = organizerBillingNumber(selectedMapping?.revision);
  const stripeState = organizerBillingText(stripe.state, "UNKNOWN");

  return <>
    <MetricGrid>
      <Metric label="Cuentas" value={organizerBillingNumber(metrics.accounts)} hint="Team y Club" />
      <Metric label="Suscripciones activas" value={organizerBillingNumber(metrics.activeSubscriptions)} tone="good" />
      <Metric label="Pago pendiente" value={organizerBillingNumber(metrics.pastDueSubscriptions)} tone={organizerBillingNumber(metrics.pastDueSubscriptions) ? "warning" : "neutral"} />
      <Metric label="Accesos activos" value={organizerBillingNumber(metrics.activeAccessGrants)} hint={`${organizerBillingNumber(metrics.continuityEditions)} continuidades`} />
      <Metric label="Backlog" value={organizerBillingNumber(metrics.webhookRetryBacklog) + organizerBillingNumber(metrics.reconciliationBacklog)} tone={organizerBillingNumber(metrics.webhookRetryBacklog) + organizerBillingNumber(metrics.reconciliationBacklog) ? "danger" : "good"} />
    </MetricGrid>

    <Panel title="Estado de Stripe y autoridad">
      <div className={styles.healthSummary}>
        <StatusBadge>{stripeState}</StatusBadge>
        <span>{organizerBillingBoolean(stripe.configured) ? `Credencial ${organizerBillingText(stripe.credentialMode, "configurada")}` : organizerBillingText(stripe.reason, "Stripe no configurado")}</span>
        <span>Canonico: revision {organizerBillingNumber(settings.revision)} · secuencia {organizerBillingNumber(settings.serverSequence)}</span>
        <span>Medido: {formatAdminDate(stripe.measuredAt)}</span>
        <strong>Stripe informa cobros; los grants de PostgreSQL conceden acceso.</strong>
      </div>
    </Panel>

    <Panel title="Activacion escalonada">
      <div className={styles.competitionControlGrid}>
        <section className={styles.competitionControl}>
          <h3>Motivo auditable</h3>
          <label className={styles.formField}>Motivo<textarea rows={4} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
          <p>Cada cambio usa operationId, revision esperada, actor autenticado y fecha del servidor.</p>
        </section>
        <section className={styles.competitionControl}>
          <h3>Flags Wave 7B</h3>
          {flagControls.map(([property, flagKey, label]) => {
            const liveOwnerOnly = flagKey === "live_checkout_enabled" || flagKey === "live_prices_approved";
            return <label className={styles.checkField} key={flagKey}><input
              checked={organizerBillingBoolean(settings[property])}
              disabled={!canWrite || !reasonReady || Boolean(busyKey) || (liveOwnerOnly && !canApproveLive)}
              onChange={(event) => void run("settings.flag", settingsAggregateId, organizerBillingNumber(settings.revision), { enabled: event.target.checked, flagKey, reason })}
              type="checkbox"
            />{label}{liveOwnerOnly ? " · owner" : ""}</label>;
          })}
        </section>
        <section className={styles.competitionControl}>
          <h3>Salud fiscal</h3>
          <label className={styles.formField}>Estado<select disabled={!canApproveLive || Boolean(busyKey)} value={taxHealth} onChange={(event) => setTaxHealth(event.target.value)}><option>UNCONFIGURED</option><option>SANDBOX_READY</option><option>LIVE_REVIEW_REQUIRED</option><option>LIVE_READY</option><option>BLOCKED</option></select></label>
          <button className={styles.primaryButton} disabled={!canApproveLive || !reasonReady || Boolean(busyKey)} onClick={() => void run("settings.tax_health", settingsAggregateId, organizerBillingNumber(settings.revision), { reason, taxHealth })} type="button">Guardar salud fiscal</button>
          <p>No activa Checkout ni aprueba un Price por si solo.</p>
        </section>
        {message ? <p className={styles.competitionControlMessage} role="status">{message}</p> : null}
      </div>
    </Panel>

    <Panel title="Product / Price allowlist">
      <div className={styles.competitionControlGrid}>
        <section className={styles.competitionControl}>
          <h3>Contexto</h3>
          <label className={styles.formField}>Plan<select value={pricePlan} onChange={(event) => setPricePlan(event.target.value)}><option>CLUB_ORGANIZER</option><option>TEAM_ORGANIZER_PRO</option></select></label>
          <label className={styles.formField}>Modo<select value={priceMode} onChange={(event) => { setPriceMode(event.target.value); setPriceApproved(false); }}><option value="test">Test</option><option value="live">Live</option></select></label>
          <label className={styles.formField}>Intervalo<select value={priceInterval} onChange={(event) => setPriceInterval(event.target.value)}><option value="month">Mensual</option><option value="year">Anual</option></select></label>
          <p>Revision existente: {priceRevision || "nueva asignacion"}</p>
        </section>
        <section className={styles.competitionControl}>
          <h3>Referencias Stripe</h3>
          <label className={styles.formField}>Product ID<input autoComplete="off" placeholder="prod_..." value={productId} onChange={(event) => setProductId(event.target.value)} /></label>
          <label className={styles.formField}>Price ID<input autoComplete="off" placeholder="price_..." value={priceId} onChange={(event) => setPriceId(event.target.value)} /></label>
          <label className={styles.formField}>Moneda<input maxLength={3} value={currency} onChange={(event) => setCurrency(event.target.value.toLowerCase())} /></label>
        </section>
        <section className={styles.competitionControl}>
          <h3>Importe e impuestos</h3>
          <label className={styles.formField}>Importe en centimos<input inputMode="numeric" min={0} type="number" value={unitAmount} onChange={(event) => setUnitAmount(event.target.value)} /></label>
          <label className={styles.formField}>Tax behavior<select value={taxBehavior} onChange={(event) => setTaxBehavior(event.target.value)}><option value="unspecified">Unspecified</option><option value="inclusive">Inclusive</option><option value="exclusive">Exclusive</option></select></label>
          <label className={styles.checkField}><input checked={priceApproved} disabled={priceMode === "live" && !canApproveLive} type="checkbox" onChange={(event) => setPriceApproved(event.target.checked)} />Aprobar mapping{priceMode === "live" ? " · owner" : ""}</label>
          <button className={styles.primaryButton} disabled={!canWrite || !reasonReady || Boolean(busyKey) || !/^prod_[A-Za-z0-9_]+$/.test(productId) || !/^price_[A-Za-z0-9_]+$/.test(priceId) || (priceMode === "live" && priceApproved && !canApproveLive)} onClick={() => void run("price_mapping.upsert", settingsAggregateId, priceRevision, { approved: priceApproved, billingInterval: priceInterval, currency, planCode: pricePlan, reason, stripeMode: priceMode, stripePriceId: priceId, stripeProductId: productId, taxBehavior, unitAmount })} type="button">Guardar mapping</button>
        </section>
      </div>
      <DataTable label="Mappings Stripe redactados"><thead><tr><th>Plan</th><th>Modo</th><th>Intervalo</th><th>Product / Price</th><th>Importe</th><th>Fiscal</th><th>Revision</th></tr></thead><tbody>{priceMappings.map((item) => <tr key={organizerBillingText(item.id)}><td>{organizerBillingText(item.planCode)}</td><td><StatusBadge>{organizerBillingText(item.mode)}</StatusBadge></td><td>{organizerBillingText(item.interval)}</td><td><Identifier value={organizerBillingText(item.product)} /><small><Identifier value={organizerBillingText(item.price)} /></small></td><td>{organizerBillingMoney(item.unitAmount, item.currency)}</td><td>{organizerBillingText(item.taxBehavior)}<small>{organizerBillingBoolean(item.approved) ? "Aprobado" : "No aprobado"}</small></td><td>{organizerBillingNumber(item.revision)}<small>{formatAdminDate(item.updatedAt)}</small></td></tr>)}</tbody></DataTable>
    </Panel>

    <Panel title="Accesos manuales auditados">
      <div className={styles.competitionControlGrid}>
        <section className={styles.competitionControl}><h3>Conceder</h3><label className={styles.formField}>Tipo<select value={organizerKind} onChange={(event) => { const next = event.target.value; setOrganizerKind(next); if (next === "TEAM" && manualPlan === "CLUB_PARTNER") setManualPlan("PLATFORM_GRANT"); }}><option>CLUB</option><option>TEAM</option></select></label><label className={styles.formField}>Organizador UUID<input value={organizerId} onChange={(event) => setOrganizerId(event.target.value)} /></label><label className={styles.formField}>Plan<select value={manualPlan} onChange={(event) => setManualPlan(event.target.value)}>{organizerKind === "CLUB" ? <option>CLUB_PARTNER</option> : null}<option>PROMOTION</option><option>PRIVATE_BETA</option><option>PLATFORM_GRANT</option></select></label><label className={styles.formField}>Caducidad opcional<input type="datetime-local" value={grantExpiresAt} onChange={(event) => setGrantExpiresAt(event.target.value)} /></label><button className={styles.primaryButton} disabled={!canWrite || !reasonReady || Boolean(busyKey) || !/^[0-9a-f-]{36}$/i.test(organizerId)} onClick={() => void run("manual.grant", organizerId, 0, { expiresAt: grantExpiresAt ? new Date(grantExpiresAt).toISOString() : "", organizerKind, planCode: manualPlan, reason, validFrom: "" })} type="button">Conceder acceso</button></section>
        <section className={styles.competitionControl}><h3>Renovacion</h3><label className={styles.formField}>Nueva caducidad opcional<input type="datetime-local" value={renewExpiresAt} onChange={(event) => setRenewExpiresAt(event.target.value)} /></label><p>Selecciona renovar en una fila. Dejar vacio elimina la caducidad, pero no crea un voto, pago o grant nuevo.</p></section>
      </div>
      <DataTable label="Grants de organizador"><thead><tr><th>Organizador</th><th>Plan</th><th>Origen</th><th>Estado</th><th>Vigencia</th><th>Revision</th><th>Accion</th></tr></thead><tbody>{grants.map((item) => <tr key={organizerBillingText(item.id)}><td>{organizerBillingText(item.organizerKind)}<small><Identifier value={organizerBillingText(item.organizerId)} /></small></td><td>{organizerBillingText(item.planCode)}</td><td>{organizerBillingText(item.source)}</td><td><StatusBadge>{organizerBillingStatus(item.status)}</StatusBadge></td><td>{formatAdminDate(item.validUntil)}</td><td>{organizerBillingNumber(item.revision)}</td><td><div className={styles.rankingActionRow}><button disabled={!canWrite || !reasonReady || Boolean(busyKey)} onClick={() => void run("manual.renew", organizerBillingText(item.id), organizerBillingNumber(item.revision), { expiresAt: renewExpiresAt ? new Date(renewExpiresAt).toISOString() : "", reason })} type="button">Renovar</button><button disabled={!canWrite || !reasonReady || Boolean(busyKey) || organizerBillingText(item.status) === "revoked"} onClick={() => void run("manual.revoke", organizerBillingText(item.id), organizerBillingNumber(item.revision), { reason })} type="button">Revocar</button></div></td></tr>)}</tbody></DataTable>
    </Panel>

    <Panel title="Cuentas y reconciliacion">
      <DataTable label="Cuentas de facturacion"><thead><tr><th>Organizador</th><th>Modo</th><th>Cliente</th><th>Suscripcion</th><th>Estado</th><th>Revision</th><th>Accion</th></tr></thead><tbody>{accounts.map((item) => { const subscription = organizerBillingRecord(item.subscription); return <tr key={organizerBillingText(item.id)}><td><strong>{organizerBillingText(item.organizerName)}</strong><small>{organizerBillingText(item.organizerKind)} · <Identifier value={organizerBillingText(item.organizerId)} /></small></td><td><StatusBadge>{organizerBillingText(item.mode)}</StatusBadge></td><td><Identifier value={organizerBillingText(item.customer)} /></td><td>{organizerBillingText(subscription.planCode, "Sin plan")}<small><Identifier value={organizerBillingText(subscription.reference)} /></small></td><td><StatusBadge>{organizerBillingStatus(subscription.status || item.status)}</StatusBadge><small>{formatAdminDate(subscription.currentPeriodEnd)}</small></td><td>{organizerBillingNumber(item.revision)}<small>seq {organizerBillingNumber(item.serverSequence)}</small></td><td><button className={styles.secondaryButton} disabled={!canWrite || !reasonReady || Boolean(busyKey)} onClick={() => void run("reconciliation.request", organizerBillingText(item.id), organizerBillingNumber(item.revision), { reason })} type="button">Reconciliar</button></td></tr>; })}</tbody></DataTable>
    </Panel>

    <div className={styles.overviewColumns}>
      <Panel title="Webhook ledger"><DataTable label="Webhooks Stripe"><thead><tr><th>Evento</th><th>Tipo</th><th>Estado</th><th>Intentos</th><th>Procesado</th></tr></thead><tbody>{webhooks.map((item) => <tr key={`${organizerBillingText(item.event)}-${organizerBillingNumber(item.serverSequence)}`}><td><Identifier value={organizerBillingText(item.event)} /></td><td>{organizerBillingText(item.type)}</td><td><StatusBadge>{organizerBillingText(item.status)}</StatusBadge><small>{organizerBillingText(item.safeErrorCode)}</small></td><td>{organizerBillingNumber(item.attempts)}</td><td>{formatAdminDate(item.processedAt || item.receivedAt)}</td></tr>)}</tbody></DataTable></Panel>
      <Panel title="Reconciliaciones"><DataTable label="Reconciliaciones Stripe"><thead><tr><th>Cuenta</th><th>Estado</th><th>Diferencias</th><th>Revision</th><th>Fecha</th></tr></thead><tbody>{reconciliations.map((item) => <tr key={organizerBillingText(item.id)}><td><Identifier value={organizerBillingText(item.accountId)} /></td><td><StatusBadge>{organizerBillingText(item.status)}</StatusBadge><small>{organizerBillingText(item.safeErrorCode)}</small></td><td>{Array.isArray(item.differenceCodes) ? item.differenceCodes.join(", ") : "-"}</td><td>{organizerBillingNumber(item.revision)}</td><td>{formatAdminDate(item.completedAt || item.createdAt)}</td></tr>)}</tbody></DataTable></Panel>
    </div>
  </>;
}

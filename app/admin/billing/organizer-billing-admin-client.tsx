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
const commercialFlags = [
  ["commercialDecisionWorkflowEnabled", "commercial_decision_workflow_enabled", "Flujo de decisión comercial"],
  ["organizerPricingUiEnabled", "organizer_pricing_ui_enabled", "Precios públicos aprobados"],
  ["stripeTestCheckoutEnabled", "stripe_test_checkout_enabled", "Checkout TEST"],
  ["stripeTestPortalEnabled", "stripe_test_portal_enabled", "Portal TEST"],
  ["demoWorldV29Enabled", "demo_world_v29_enabled", "Demo World V2.9"],
] as const;
const taxHealthStates = [
  "UNCONFIGURED", "COMMERCIAL_DECISION_PENDING", "TAX_REVIEW_REQUIRED",
  "TEST_READY", "LIVE_READY", "BLOCKED",
] as const;

type PendingOperation = { id: string; key: string };

function jsonBody(response: Response) {
  return response.json().catch(() => ({})) as Promise<OrganizerBillingJson>;
}

function inputDate(value: unknown) {
  const raw = organizerBillingText(value);
  const parsed = new Date(raw);
  return raw && !Number.isNaN(parsed.getTime()) ? parsed.toISOString().slice(0, 16) : "";
}

function readiness(value: unknown) {
  return organizerBillingBoolean(value) ? "Listo" : "Pendiente";
}

function RuntimeSummary({ canonical, remote }: { canonical: OrganizerBillingJson; remote: OrganizerBillingJson }) {
  const mode = organizerBillingText(canonical.mode, organizerBillingText(remote.mode)).toUpperCase();
  return <article className={styles.competitionControl}>
    <h3>{mode}</h3>
    <p><StatusBadge>{organizerBillingText(remote.state, "UNKNOWN")}</StatusBadge></p>
    <p>{organizerBillingNumber(remote.productCount)} Products · {organizerBillingNumber(remote.priceCount)} Prices</p>
    <p>Catálogo: {readiness(canonical.catalogReady)} · Checkout API: {readiness(canonical.checkoutApiReady)}</p>
    <p>Webhook: {readiness(canonical.webhookDestinationReady && canonical.webhookSigningReady)} · Portal: {readiness(canonical.portalReady)}</p>
    <small>{organizerBillingText(canonical.safeErrorCode, organizerBillingText(remote.safeErrorCode, "Sin incidencias"))}</small>
  </article>;
}

export function OrganizerBillingAdminClient({ canApproveLive, canWrite, canonical, stripe }: {
  canApproveLive: boolean;
  canWrite: boolean;
  canonical: OrganizerBillingJson;
  stripe: OrganizerBillingJson;
}) {
  const settings = organizerBillingRecord(canonical.settings);
  const metrics = organizerBillingRecord(canonical.metrics);
  const decisions = organizerBillingArray(canonical.commercialDecisions);
  const priceMappings = organizerBillingArray(canonical.priceMappings);
  const runtimeHealth = organizerBillingArray(canonical.runtimeHealth);
  const activation = organizerBillingRecord(canonical.activationChecklist);
  const accounts = organizerBillingArray(canonical.accounts);
  const webhooks = organizerBillingArray(canonical.webhooks);
  const reconciliations = organizerBillingArray(canonical.reconciliations);
  const grants = organizerBillingArray(canonical.accessGrants);
  const remoteTest = organizerBillingRecord(stripe.test);
  const remoteLive = organizerBillingRecord(stripe.live);
  const initialDecision = decisions.find((item) => organizerBillingText(item.planCode) === "CLUB_ORGANIZER")
    ?? decisions[0] ?? null;
  const router = useRouter();
  const pending = useRef<PendingOperation | null>(null);
  const [busyKey, setBusyKey] = useState("");
  const [message, setMessage] = useState("");
  const [reason, setReason] = useState("");
  const [selectedDecisionId, setSelectedDecisionId] = useState(organizerBillingText(initialDecision?.id));
  const [currency, setCurrency] = useState(organizerBillingText(initialDecision?.currency, "EUR"));
  const [monthlyAmountMinor, setMonthlyAmountMinor] = useState(String(organizerBillingNumber(initialDecision?.monthlyAmountMinor)));
  const [annualAmountMinor, setAnnualAmountMinor] = useState(String(organizerBillingNumber(initialDecision?.annualAmountMinor)));
  const [taxDisplayMode, setTaxDisplayMode] = useState(organizerBillingText(initialDecision?.taxDisplayMode, "PENDING_REVIEW"));
  const [stripeTaxBehavior, setStripeTaxBehavior] = useState(organizerBillingText(initialDecision?.stripeTaxBehavior, "unspecified"));
  const [effectiveFrom, setEffectiveFrom] = useState(inputDate(initialDecision?.effectiveFrom));
  const [trialDays, setTrialDays] = useState(String(organizerBillingNumber(initialDecision?.trialDays)));
  const [publicCopyRevision, setPublicCopyRevision] = useState(organizerBillingText(initialDecision?.publicCopyRevision, "organizer-pricing-v1"));
  const [termsRevision, setTermsRevision] = useState(organizerBillingText(settings.organizerTermsRevision, organizerBillingText(initialDecision?.termsRevision)));
  const [privacyRevision, setPrivacyRevision] = useState(organizerBillingText(settings.organizerPrivacyRevision, organizerBillingText(initialDecision?.privacyRevision)));
  const [taxHealth, setTaxHealth] = useState(organizerBillingText(settings.taxHealth, "UNCONFIGURED"));
  const [liveConfirmation, setLiveConfirmation] = useState(false);
  const [organizerKind, setOrganizerKind] = useState("CLUB");
  const [organizerId, setOrganizerId] = useState("");
  const [manualPlan, setManualPlan] = useState("CLUB_PARTNER");
  const [grantExpiresAt, setGrantExpiresAt] = useState("");
  const [renewExpiresAt, setRenewExpiresAt] = useState("");

  const selectedDecision = decisions.find((item) => organizerBillingText(item.id) === selectedDecisionId)
    ?? initialDecision;

  function selectDecision(id: string) {
    const next = decisions.find((item) => organizerBillingText(item.id) === id);
    if (!next) return;
    setSelectedDecisionId(id);
    setCurrency(organizerBillingText(next.currency, "EUR"));
    setMonthlyAmountMinor(String(organizerBillingNumber(next.monthlyAmountMinor)));
    setAnnualAmountMinor(String(organizerBillingNumber(next.annualAmountMinor)));
    setTaxDisplayMode(organizerBillingText(next.taxDisplayMode, "PENDING_REVIEW"));
    setStripeTaxBehavior(organizerBillingText(next.stripeTaxBehavior, "unspecified"));
    setEffectiveFrom(inputDate(next.effectiveFrom));
    setTrialDays(String(organizerBillingNumber(next.trialDays)));
    setPublicCopyRevision(organizerBillingText(next.publicCopyRevision, "organizer-pricing-v1"));
  }

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
      if (!response.ok) throw new Error(organizerBillingText(body.message, organizerBillingText(body.error, "Operación no confirmada")));
      pending.current = null;
      setMessage("Cambio confirmado por PostgreSQL.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Operación no confirmada");
    } finally {
      setBusyKey("");
    }
  }

  const reasonReady = reason.trim().length >= 3;
  const decisionStatus = organizerBillingText(selectedDecision?.status);
  const decisionId = organizerBillingText(selectedDecision?.id);
  const decisionRevision = organizerBillingNumber(selectedDecision?.revision);
  const decisionPlan = organizerBillingText(selectedDecision?.planCode);
  const mapped = (stripeMode: string) => priceMappings.filter((item) =>
    organizerBillingText(item.planCode) === decisionPlan
      && organizerBillingText(item.mode) === stripeMode
      && organizerBillingBoolean(item.active)
      && organizerBillingBoolean(item.approved)).length === 2;
  const decisionPayload = {
    annualAmountMinor,
    currency,
    effectiveFrom: effectiveFrom ? new Date(effectiveFrom).toISOString() : "",
    monthlyAmountMinor,
    privacyRevision,
    publicCopyRevision,
    reason,
    stripeTaxBehavior,
    taxDisplayMode,
    termsRevision,
    trialDays,
  };
  const liveGateReady = [
    activation.commercialWorkflow,
    activation.paidDecisionsPublished,
    activation.taxReady,
    activation.liveCatalogReady,
    activation.liveCheckoutReady,
    activation.livePortalReady,
  ].every(organizerBillingBoolean);

  return <>
    <MetricGrid>
      <Metric label="Cuentas" value={organizerBillingNumber(metrics.accounts)} hint="Team y Club" />
      <Metric label="Suscripciones activas" value={organizerBillingNumber(metrics.activeSubscriptions)} tone="good" />
      <Metric label="Pago pendiente" value={organizerBillingNumber(metrics.pastDueSubscriptions)} tone={organizerBillingNumber(metrics.pastDueSubscriptions) ? "warning" : "neutral"} />
      <Metric label="Decisiones aprobadas" value={decisions.filter((item) => ["approved", "published"].includes(organizerBillingText(item.status))).length} hint="Precios Organizer" />
      <Metric label="Backlog" value={organizerBillingNumber(metrics.webhookRetryBacklog) + organizerBillingNumber(metrics.reconciliationBacklog)} tone={organizerBillingNumber(metrics.webhookRetryBacklog) + organizerBillingNumber(metrics.reconciliationBacklog) ? "danger" : "good"} />
    </MetricGrid>

    <Panel title="Autoridad comercial">
      <div className={styles.competitionControlGrid}>
        <section className={styles.competitionControl}>
          <h3>Motivo auditable</h3>
          <label className={styles.formField}>Motivo<textarea rows={4} value={reason} onChange={(event) => setReason(event.target.value)} /></label>
          <p>Cada cambio usa operationId, revisión esperada, actor autenticado y fecha del servidor.</p>
        </section>
        <section className={styles.competitionControl}>
          <h3>Decisión</h3>
          <label className={styles.formField}>Plan<select value={decisionId} onChange={(event) => selectDecision(event.target.value)}>{decisions.map((item) => <option key={organizerBillingText(item.id)} value={organizerBillingText(item.id)}>{organizerBillingText(item.planCode)} · {organizerBillingText(item.status)}</option>)}</select></label>
          <p><StatusBadge>{decisionStatus || "Sin decisión"}</StatusBadge> · revisión {decisionRevision}</p>
          <p>{organizerBillingMoney(selectedDecision?.monthlyAmountMinor, selectedDecision?.currency)} / mes · {organizerBillingMoney(selectedDecision?.annualAmountMinor, selectedDecision?.currency)} / año</p>
        </section>
        <section className={styles.competitionControl}>
          <h3>Ciclo de aprobación</h3>
          <button disabled={!canApproveLive || !reasonReady || Boolean(busyKey) || decisionStatus !== "draft"} onClick={() => void run("commercial_decision.submit", decisionId, decisionRevision, { reason })} type="button">Enviar a aprobación</button>
          <button className={styles.primaryButton} disabled={!canApproveLive || !reasonReady || Boolean(busyKey) || decisionStatus !== "pending_approval" || !liveConfirmation} onClick={() => void run("commercial_decision.approve", decisionId, decisionRevision, { ...decisionPayload, billingIntervals: ["month", "year"], confirmLivePricing: "CONFIRM_STRIPE_LIVE_PRICING" })} type="button">Aprobar decisión</button>
          <button disabled={!canApproveLive || !reasonReady || Boolean(busyKey) || decisionStatus !== "approved"} onClick={() => void run("commercial_decision.withdraw", decisionId, decisionRevision, { reason })} type="button">Retirar aprobación</button>
          <label className={styles.checkField}><input checked={liveConfirmation} onChange={(event) => setLiveConfirmation(event.target.checked)} type="checkbox" />Confirmo la revisión comercial</label>
          <strong>Esta acción permitirá crear precios Stripe live.</strong>
        </section>
      </div>
    </Panel>

    <Panel title="Importes, fiscalidad y versiones">
      <div className={styles.competitionControlGrid}>
        <section className={styles.competitionControl}>
          <h3>Importes propuestos</h3>
          <label className={styles.formField}>Moneda<input maxLength={3} value={currency} onChange={(event) => setCurrency(event.target.value.toUpperCase())} /></label>
          <label className={styles.formField}>Mensual, céntimos<input inputMode="numeric" min={0} type="number" value={monthlyAmountMinor} onChange={(event) => setMonthlyAmountMinor(event.target.value)} /></label>
          <label className={styles.formField}>Anual, céntimos<input inputMode="numeric" min={0} type="number" value={annualAmountMinor} onChange={(event) => setAnnualAmountMinor(event.target.value)} /></label>
          <label className={styles.formField}>Prueba, días<input inputMode="numeric" min={0} type="number" value={trialDays} onChange={(event) => setTrialDays(event.target.value)} /></label>
        </section>
        <section className={styles.competitionControl}>
          <h3>Tratamiento fiscal</h3>
          <label className={styles.formField}>Presentación<select value={taxDisplayMode} onChange={(event) => setTaxDisplayMode(event.target.value)}><option>PENDING_REVIEW</option><option>TAX_INCLUDED</option><option>TAX_EXCLUDED</option></select></label>
          <label className={styles.formField}>Stripe Tax<select value={stripeTaxBehavior} onChange={(event) => setStripeTaxBehavior(event.target.value)}><option value="unspecified">unspecified</option><option value="inclusive">inclusive</option><option value="exclusive">exclusive</option></select></label>
          <label className={styles.formField}>Vigencia<input type="datetime-local" value={effectiveFrom} onChange={(event) => setEffectiveFrom(event.target.value)} /></label>
        </section>
        <section className={styles.competitionControl}>
          <h3>Contrato público</h3>
          <label className={styles.formField}>Copy<input value={publicCopyRevision} onChange={(event) => setPublicCopyRevision(event.target.value)} /></label>
          <label className={styles.formField}>Terms<input value={termsRevision} onChange={(event) => setTermsRevision(event.target.value)} /></label>
          <label className={styles.formField}>Privacy<input value={privacyRevision} onChange={(event) => setPrivacyRevision(event.target.value)} /></label>
          <button className={styles.primaryButton} disabled={!canApproveLive || !reasonReady || Boolean(busyKey) || decisionStatus !== "draft"} onClick={() => void run("commercial_decision.update", decisionId, decisionRevision, decisionPayload)} type="button">Guardar borrador</button>
        </section>
      </div>
    </Panel>

    <Panel title="Stripe Organizer TEST / LIVE">
      <div className={styles.competitionControlGrid}>
        <RuntimeSummary canonical={runtimeHealth.find((item) => organizerBillingText(item.mode) === "test") ?? {}} remote={remoteTest} />
        <RuntimeSummary canonical={runtimeHealth.find((item) => organizerBillingText(item.mode) === "live") ?? {}} remote={remoteLive} />
        <section className={styles.competitionControl}>
          <h3>Catálogo del plan</h3>
          <button className={styles.primaryButton} disabled={!canWrite || !reasonReady || Boolean(busyKey) || !decisionId || mapped("test")} onClick={() => void run("stripe_catalog.provision", decisionId, decisionRevision, { reason, stripeMode: "test" })} type="button">{mapped("test") ? "TEST confirmado" : "Crear y verificar TEST"}</button>
          <button disabled={!canApproveLive || !reasonReady || Boolean(busyKey) || decisionStatus !== "approved" || organizerBillingText(settings.taxHealth) !== "LIVE_READY" || mapped("live")} onClick={() => void run("stripe_catalog.provision", decisionId, decisionRevision, { reason, stripeMode: "live" })} type="button">{mapped("live") ? "LIVE confirmado" : "Crear y verificar LIVE"}</button>
          <p>El navegador no envía Product IDs ni Price IDs. El servidor crea, relee y confirma el catálogo.</p>
        </section>
      </div>
      <div className={styles.rankingActionRow}>
        {runtimeHealth.map((item) => <button disabled={!canWrite || !reasonReady || Boolean(busyKey)} key={organizerBillingText(item.mode)} onClick={() => void run("stripe_runtime.verify", settingsAggregateId, organizerBillingNumber(item.revision), { reason, stripeMode: organizerBillingText(item.mode) })} type="button">Verificar {organizerBillingText(item.mode).toUpperCase()}</button>)}
      </div>
      <DataTable label="Mappings Stripe redactados"><thead><tr><th>Plan</th><th>Modo</th><th>Intervalo</th><th>Importe</th><th>Fiscal</th><th>Autoridad</th><th>Revisión</th></tr></thead><tbody>{priceMappings.map((item) => <tr key={organizerBillingText(item.id)}><td>{organizerBillingText(item.planCode)}</td><td><StatusBadge>{organizerBillingText(item.mode)}</StatusBadge></td><td>{organizerBillingText(item.interval)}</td><td>{organizerBillingMoney(item.unitAmount, item.currency)}</td><td>{organizerBillingText(item.taxBehavior)}</td><td>{organizerBillingText(item.authorityStatus)}</td><td>{organizerBillingNumber(item.revision)}<small>{formatAdminDate(item.updatedAt)}</small></td></tr>)}</tbody></DataTable>
    </Panel>

    <Panel title="Tax Health y activación">
      <div className={styles.competitionControlGrid}>
        <section className={styles.competitionControl}>
          <h3>Salud fiscal</h3>
          <label className={styles.formField}>Estado<select disabled={!canApproveLive || Boolean(busyKey)} value={taxHealth} onChange={(event) => setTaxHealth(event.target.value)}>{taxHealthStates.map((state) => <option key={state}>{state}</option>)}</select></label>
          <button className={styles.primaryButton} disabled={!canApproveLive || !reasonReady || Boolean(busyKey)} onClick={() => void run("settings.tax_health_v2", settingsAggregateId, organizerBillingNumber(settings.revision), { confirmation: "CONFIRM_ORGANIZER_TAX_HEALTH", privacyRevision, reason, taxHealth, termsRevision })} type="button">Guardar Tax Health</button>
          <p>Codex no decide IVA, reverse charge, exenciones ni obligaciones de factura.</p>
        </section>
        <section className={styles.competitionControl}>
          <h3>Flags comerciales</h3>
          {commercialFlags.map(([property, flagKey, label]) => <label className={styles.checkField} key={flagKey}><input checked={organizerBillingBoolean(settings[property])} disabled={!canApproveLive || !reasonReady || Boolean(busyKey)} onChange={(event) => void run("settings.feature_flag_v2", settingsAggregateId, organizerBillingNumber(settings.revision), { enabled: event.target.checked, flagKey, reason })} type="checkbox" />{label}</label>)}
        </section>
        <section className={styles.competitionControl}>
          <h3>Checklist LIVE</h3>
          {Object.entries(activation).map(([key, value]) => <p key={key}>{readiness(value)} · {key}</p>)}
          <label className={styles.checkField}><input checked={liveConfirmation} onChange={(event) => setLiveConfirmation(event.target.checked)} type="checkbox" />Confirmación final explícita</label>
          <button className={styles.primaryButton} disabled={!canApproveLive || !reasonReady || Boolean(busyKey) || !liveGateReady || !liveConfirmation} onClick={() => void run("live_checkout.activate", settingsAggregateId, organizerBillingNumber(settings.revision), { confirmation: "CONFIRM_ORGANIZER_LIVE_CHECKOUT", privacyRevision, reason, termsRevision })} type="button">Activar Checkout LIVE</button>
        </section>
      </div>
      {message ? <p className={styles.competitionControlMessage} role="status">{message}</p> : null}
    </Panel>

    <Panel title="Accesos manuales auditados">
      <div className={styles.competitionControlGrid}>
        <section className={styles.competitionControl}><h3>Conceder</h3><label className={styles.formField}>Tipo<select value={organizerKind} onChange={(event) => { const next = event.target.value; setOrganizerKind(next); if (next === "TEAM" && manualPlan === "CLUB_PARTNER") setManualPlan("PLATFORM_GRANT"); }}><option>CLUB</option><option>TEAM</option></select></label><label className={styles.formField}>Organizador UUID<input value={organizerId} onChange={(event) => setOrganizerId(event.target.value)} /></label><label className={styles.formField}>Plan<select value={manualPlan} onChange={(event) => setManualPlan(event.target.value)}>{organizerKind === "CLUB" ? <option>CLUB_PARTNER</option> : null}<option>PROMOTION</option><option>PRIVATE_BETA</option><option>PLATFORM_GRANT</option></select></label><label className={styles.formField}>Caducidad opcional<input type="datetime-local" value={grantExpiresAt} onChange={(event) => setGrantExpiresAt(event.target.value)} /></label><button className={styles.primaryButton} disabled={!canWrite || !reasonReady || Boolean(busyKey) || !/^[0-9a-f-]{36}$/i.test(organizerId)} onClick={() => void run("manual.grant", organizerId, 0, { expiresAt: grantExpiresAt ? new Date(grantExpiresAt).toISOString() : "", organizerKind, planCode: manualPlan, reason, validFrom: "" })} type="button">Conceder acceso</button></section>
        <section className={styles.competitionControl}><h3>Renovación</h3><label className={styles.formField}>Nueva caducidad opcional<input type="datetime-local" value={renewExpiresAt} onChange={(event) => setRenewExpiresAt(event.target.value)} /></label><p>Selecciona renovar en una fila. Dejar vacío elimina la caducidad y no crea un grant nuevo.</p></section>
      </div>
      <DataTable label="Grants de organizador"><thead><tr><th>Organizador</th><th>Plan</th><th>Origen</th><th>Estado</th><th>Vigencia</th><th>Revisión</th><th>Acción</th></tr></thead><tbody>{grants.map((item) => <tr key={organizerBillingText(item.id)}><td>{organizerBillingText(item.organizerKind)}<small><Identifier value={organizerBillingText(item.organizerId)} /></small></td><td>{organizerBillingText(item.planCode)}</td><td>{organizerBillingText(item.source)}</td><td><StatusBadge>{organizerBillingStatus(item.status)}</StatusBadge></td><td>{formatAdminDate(item.validUntil)}</td><td>{organizerBillingNumber(item.revision)}</td><td><div className={styles.rankingActionRow}><button disabled={!canWrite || !reasonReady || Boolean(busyKey)} onClick={() => void run("manual.renew", organizerBillingText(item.id), organizerBillingNumber(item.revision), { expiresAt: renewExpiresAt ? new Date(renewExpiresAt).toISOString() : "", reason })} type="button">Renovar</button><button disabled={!canWrite || !reasonReady || Boolean(busyKey) || organizerBillingText(item.status) === "revoked"} onClick={() => void run("manual.revoke", organizerBillingText(item.id), organizerBillingNumber(item.revision), { reason })} type="button">Revocar</button></div></td></tr>)}</tbody></DataTable>
    </Panel>

    <Panel title="Cuentas y reconciliación">
      <DataTable label="Cuentas de facturación"><thead><tr><th>Organizador</th><th>Modo</th><th>Plan</th><th>Estado</th><th>Revisión</th><th>Acción</th></tr></thead><tbody>{accounts.map((item) => { const subscription = organizerBillingRecord(item.subscription); return <tr key={organizerBillingText(item.id)}><td><strong>{organizerBillingText(item.organizerName)}</strong><small>{organizerBillingText(item.organizerKind)} · <Identifier value={organizerBillingText(item.organizerId)} /></small></td><td><StatusBadge>{organizerBillingText(item.mode)}</StatusBadge></td><td>{organizerBillingText(subscription.planCode, "Sin plan")}</td><td><StatusBadge>{organizerBillingStatus(subscription.status || item.status)}</StatusBadge><small>{formatAdminDate(subscription.currentPeriodEnd)}</small></td><td>{organizerBillingNumber(item.revision)}<small>seq {organizerBillingNumber(item.serverSequence)}</small></td><td><button className={styles.secondaryButton} disabled={!canWrite || !reasonReady || Boolean(busyKey)} onClick={() => void run("reconciliation.request", organizerBillingText(item.id), organizerBillingNumber(item.revision), { reason })} type="button">Reconciliar</button></td></tr>; })}</tbody></DataTable>
    </Panel>

    <div className={styles.overviewColumns}>
      <Panel title="Webhook ledger"><DataTable label="Webhooks Stripe"><thead><tr><th>Evento</th><th>Tipo</th><th>Estado</th><th>Intentos</th><th>Procesado</th></tr></thead><tbody>{webhooks.map((item) => <tr key={`${organizerBillingText(item.event)}-${organizerBillingNumber(item.serverSequence)}`}><td><Identifier value={organizerBillingText(item.event)} /></td><td>{organizerBillingText(item.type)}</td><td><StatusBadge>{organizerBillingText(item.status)}</StatusBadge><small>{organizerBillingText(item.safeErrorCode)}</small></td><td>{organizerBillingNumber(item.attempts)}</td><td>{formatAdminDate(item.processedAt || item.receivedAt)}</td></tr>)}</tbody></DataTable></Panel>
      <Panel title="Reconciliaciones"><DataTable label="Reconciliaciones Stripe"><thead><tr><th>Cuenta</th><th>Estado</th><th>Diferencias</th><th>Revisión</th><th>Fecha</th></tr></thead><tbody>{reconciliations.map((item) => <tr key={organizerBillingText(item.id)}><td><Identifier value={organizerBillingText(item.accountId)} /></td><td><StatusBadge>{organizerBillingText(item.status)}</StatusBadge><small>{organizerBillingText(item.safeErrorCode)}</small></td><td>{Array.isArray(item.differenceCodes) ? item.differenceCodes.join(", ") : "-"}</td><td>{organizerBillingNumber(item.revision)}</td><td>{formatAdminDate(item.completedAt || item.createdAt)}</td></tr>)}</tbody></DataTable></Panel>
    </div>
  </>;
}

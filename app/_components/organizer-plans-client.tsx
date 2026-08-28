"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  organizerBillingArray,
  organizerBillingBoolean,
  organizerBillingMoney,
  organizerBillingRecord,
  organizerBillingStatus,
  organizerBillingText,
  organizerFeatureLabels,
  organizerLimitLabels,
  type OrganizerBillingJson,
} from "../organizer-billing-contract";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import styles from "./organizer-billing.module.css";

const catalogCacheKey = "pachangas-organizer-plan-catalog-v1";

function readCatalogCache() {
  try {
    return organizerBillingRecord(JSON.parse(window.localStorage.getItem(catalogCacheKey) ?? "null"));
  } catch {
    return {};
  }
}

function storeCatalogCache(canonical: OrganizerBillingJson) {
  try {
    window.localStorage.setItem(catalogCacheKey, JSON.stringify({ canonical, savedAt: new Date().toISOString() }));
  } catch {
    // A failed cache write never changes the server-confirmed catalog.
  }
}

function priceContent(plan: OrganizerBillingJson) {
  if (organizerBillingText(plan.accessModel) === "PARTNERSHIP") {
    return <><strong>Sin cobro</strong><small>Acceso concedido despues de una revision de partnership.</small></>;
  }
  const prices = organizerBillingArray(plan.prices);
  if (!prices.length) {
    return <><strong>Precio pendiente de publicacion</strong><small>No se abrira Checkout hasta que producto, precio e impuestos esten aprobados.</small></>;
  }
  const monthly = prices.find((price) => organizerBillingText(price.interval) === "month");
  const annual = prices.find((price) => organizerBillingText(price.interval) === "year");
  const annualSaving = monthly && annual
    && organizerBillingText(monthly.currency).toLowerCase() === organizerBillingText(annual.currency).toLowerCase()
    ? Math.max(0, Number(monthly.unitAmount) * 12 - Number(annual.unitAmount))
    : 0;
  return <div className={styles.priceRows}>{prices.map((price) => (
    <span key={`${organizerBillingText(price.interval)}-${organizerBillingText(price.currency)}`}>
      <b>{organizerBillingMoney(price.unitAmount, price.currency)} / {organizerBillingText(price.interval) === "year" ? "ano" : "mes"}</b>
      <small>{organizerBillingText(price.taxBehavior) === "inclusive" ? "Impuestos incluidos" : organizerBillingText(price.taxBehavior) === "exclusive" ? "Impuestos no incluidos" : "Fiscalidad pendiente"}</small>
    </span>
  ))}{annualSaving && annual ? <span><b>Ahorro anual</b><small>{organizerBillingMoney(annualSaving, annual.currency)} frente al pago mensual</small></span> : null}</div>;
}

function PlanCard({ plan }: { plan: OrganizerBillingJson }) {
  const planCode = organizerBillingText(plan.planCode);
  const features = organizerBillingArray(plan.features).filter((item) => organizerBillingBoolean(item.enabled));
  const enabledFeatureKeys = new Set(features.map((feature) => organizerBillingText(feature.key)));
  const unavailableFeatures = Object.keys(organizerFeatureLabels).filter((key) => !enabledFeatureKeys.has(key));
  const limits = organizerBillingArray(plan.limits);
  const checkoutAvailable = organizerBillingBoolean(plan.checkoutAvailable);
  const partnership = organizerBillingText(plan.accessModel) === "PARTNERSHIP";
  return (
    <article className={styles.planCard} data-plan={planCode}>
      <header className={styles.planHeader}>
        <span className={styles.kind}>{organizerBillingText(plan.organizerKind) === "CLUB" ? "Para Clubs" : "Para equipos"}</span>
        <h2>{organizerBillingText(plan.displayName, "Plan de organizacion")}</h2>
        <p>{organizerBillingText(plan.summary)}</p>
        {planCode === "TEAM_ORGANIZER_PRO" ? <span className={styles.status}>Add-on · no sustituye el plan base</span> : null}
      </header>
      <div className={styles.priceBlock}>{priceContent(plan)}</div>
      <div>
        <ul className={styles.features}>
          {features.slice(0, 7).map((feature) => <li key={organizerBillingText(feature.key)}><span>{organizerFeatureLabels[organizerBillingText(feature.key)] ?? organizerBillingText(feature.key)}</span></li>)}
        </ul>
        {features.length > 7 || limits.length || unavailableFeatures.length ? <details className={styles.details}>
          <summary>Ver capacidades y limites</summary>
          {features.length > 7 ? <ul className={styles.features}>{features.slice(7).map((feature) => <li key={organizerBillingText(feature.key)}><span>{organizerFeatureLabels[organizerBillingText(feature.key)] ?? organizerBillingText(feature.key)}</span></li>)}</ul> : null}
          {limits.length ? <ul className={styles.limits}>{limits.map((limit) => <li key={organizerBillingText(limit.key)}><span>{organizerLimitLabels[organizerBillingText(limit.key)] ?? organizerBillingText(limit.key)}</span><b>{limit.value == null ? "Pendiente" : String(limit.value)}</b></li>)}</ul> : null}
          {unavailableFeatures.length ? <div className={styles.unavailable}><strong>No incluidas</strong><p>{unavailableFeatures.map((key) => organizerFeatureLabels[key]).join(" · ")}</p></div> : null}
        </details> : null}
      </div>
      <div className={styles.actionRow}>
        {partnership || checkoutAvailable
          ? <Link className={styles.primary} href="/ajustes/facturacion">{partnership ? "Solicitar acceso" : "Gestionar plan"}</Link>
          : <span className={styles.disabledAction} aria-disabled="true">Checkout no disponible</span>}
        <span className={styles.status}>{organizerBillingStatus(plan.pricingStatus)}</span>
      </div>
    </article>
  );
}

export function OrganizerPlansClient() {
  const [catalog, setCatalog] = useState<OrganizerBillingJson | null>(null);
  const [cacheSavedAt, setCacheSavedAt] = useState("");
  const [message, setMessage] = useState("");

  useEffect(() => {
    let active = true;
    const cached = readCatalogCache();
    const cachedCanonical = organizerBillingRecord(cached.canonical);
    if (Object.keys(cachedCanonical).length) {
      queueMicrotask(() => {
        if (!active) return;
        setCatalog(cachedCanonical);
        setCacheSavedAt(organizerBillingText(cached.savedAt));
      });
    }
    void fetch("/api/billing/organizer/catalog", { cache: "no-store" })
      .then(async (response) => {
        const body = organizerBillingRecord(await response.json());
        if (!response.ok) throw new Error("No se pudo actualizar el catalogo.");
        const canonical = organizerBillingRecord(body.canonical);
        if (!active) return;
        setCatalog(canonical);
        setCacheSavedAt("");
        setMessage("");
        storeCatalogCache(canonical);
      })
      .catch(() => {
        if (active) setMessage(Object.keys(cachedCanonical).length
          ? "Sin conexion: se muestra la ultima copia guardada del catalogo."
          : "El catalogo no esta disponible en este momento.");
      });
    return () => { active = false; };
  }, []);

  const plans = organizerBillingArray(catalog?.plans);
  const enabled = organizerBillingBoolean(catalog?.enabled);
  const cached = Boolean(cacheSavedAt);
  return (
    <OfficialProductShellV2
      active="perfil"
      context={{ detail: "Acceso para organizar competiciones", eyebrow: "Organizacion", status: cached ? "Copia local" : "Servidor central", title: "Planes" }}
    >
      <main className={styles.page}>
        <header className={styles.intro}>
          <div><span className={styles.eyebrow}>Organizer plans</span><h1>Planes de organizacion</h1><p>Capacidades para Clubs y equipos que gestionan competiciones. Los permisos deportivos se conceden solo desde el estado confirmado por PostgreSQL.</p></div>
          <span className={styles.catalogState}>{catalog ? organizerBillingStatus(catalog.status) : "Cargando catalogo"}</span>
        </header>
        {message ? <p className={styles.message} data-tone={cached ? "warning" : "danger"} role="status">{message}</p> : null}
        {!catalog ? <p className={styles.empty}>Consultando el catalogo oficial...</p> : null}
        {catalog && !enabled ? <p className={styles.empty}>Los planes de organizacion aun no estan activados.</p> : null}
        {enabled && plans.length ? <section className={styles.planGrid} aria-label="Planes de organizacion disponibles">{plans.map((plan) => <PlanCard key={organizerBillingText(plan.planCode)} plan={plan} />)}</section> : null}
        {enabled && !plans.length ? <p className={styles.empty}>No hay planes publicos configurados.</p> : null}
      </main>
    </OfficialProductShellV2>
  );
}

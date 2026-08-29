"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import {
  organizerBillingArray,
  organizerBillingBoolean,
  organizerBillingCacheKey,
  organizerBillingDate,
  organizerBillingMoney,
  organizerBillingNumber,
  organizerBillingPlanForKind,
  organizerBillingRecord,
  organizerBillingSafeUrl,
  organizerBillingStatus,
  organizerBillingText,
  organizerBillingTone,
  organizerLimitLabels,
  type OrganizerBillingJson,
} from "../organizer-billing-contract";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import styles from "./organizer-billing.module.css";

type Props = {
  checkoutOperationId?: string;
  checkoutStatus?: string;
  initialOrganizerId?: string;
  initialOrganizerKind?: string;
};

type PendingOperation = { id: string; key: string };

function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}

async function readJson(response: Response) {
  const body = organizerBillingRecord(await response.json().catch(() => ({})));
  if (!response.ok) {
    const code = organizerBillingText(body.error, "BILLING_REQUEST_REJECTED");
    if (code === "CLIENT_UPDATE_REQUIRED") throw new Error("Actualiza la aplicacion antes de volver a intentarlo.");
    if (code === "BILLING_AWAITING_PRICE_APPROVAL") throw new Error("El precio todavia no esta aprobado para Checkout.");
    if (code === "BILLING_STALE_REVISION") throw new Error("La facturacion ha cambiado. Se ha recargado el estado oficial.");
    throw new Error(organizerBillingText(body.message, "La operacion no fue confirmada por el servidor."));
  }
  return body;
}

function readSnapshotCache(kind: string, id: string) {
  try {
    return organizerBillingRecord(JSON.parse(window.localStorage.getItem(organizerBillingCacheKey(kind, id)) ?? "null"));
  } catch {
    return {};
  }
}

function storeSnapshotCache(kind: string, id: string, value: OrganizerBillingJson) {
  try {
    window.localStorage.setItem(organizerBillingCacheKey(kind, id), JSON.stringify({ ...value, savedAt: new Date().toISOString() }));
  } catch {
    // The local read model is optional and never becomes billing authority.
  }
}

function operationFor(ref: React.MutableRefObject<PendingOperation | null>, key: string) {
  if (!ref.current || ref.current.key !== key) ref.current = { id: crypto.randomUUID(), key };
  return ref.current.id;
}

function AccountSummary({ account }: { account: OrganizerBillingJson }) {
  const plan = organizerBillingRecord(account.plan);
  return <article className={styles.account}>
    <div className={styles.row}><strong>{organizerBillingText(account.mode).toUpperCase()}</strong><span className={styles.status} data-tone={organizerBillingTone(plan.status || account.status)}>{organizerBillingStatus(plan.status || account.status)}</span></div>
    <div className={styles.row}><span>Plan</span><strong>{organizerBillingText(plan.name, "Sin suscripcion")}</strong></div>
    <div className={styles.row}><span>Renovacion / fin</span><strong>{organizerBillingDate(plan.currentPeriodEnd)}</strong></div>
    {organizerBillingBoolean(plan.cancelAtPeriodEnd) ? <small>La renovacion automatica esta cancelada; el acceso se mantiene hasta el final confirmado.</small> : null}
    {organizerBillingText(plan.graceEndsAt) ? <small>Gracia hasta {organizerBillingDate(plan.graceEndsAt, true)}</small> : null}
    <small>Revision {organizerBillingNumber(account.revision)} · secuencia {organizerBillingNumber(account.serverSequence)}</small>
  </article>;
}

function AccessSummary({ access }: { access: OrganizerBillingJson }) {
  return <article className={styles.access}>
    <div className={styles.row}><strong>{organizerBillingText(access.planName, organizerBillingText(access.planCode))}</strong><span className={styles.status} data-tone={organizerBillingTone(access.status)}>{organizerBillingStatus(access.status)}</span></div>
    <div className={styles.row}><span>Origen</span><strong>{organizerBillingText(access.source).replaceAll("_", " ")}</strong></div>
    <div className={styles.row}><span>Valido hasta</span><strong>{organizerBillingDate(access.validUntil)}</strong></div>
    <small>Revision {organizerBillingNumber(access.revision)} · secuencia {organizerBillingNumber(access.serverSequence)}</small>
  </article>;
}

export function OrganizerBillingClient({ checkoutOperationId = "", checkoutStatus = "", initialOrganizerId = "", initialOrganizerKind = "" }: Props) {
  const [token, setToken] = useState("");
  const [organizers, setOrganizers] = useState<OrganizerBillingJson[]>([]);
  const [selectedKey, setSelectedKey] = useState("");
  const [catalog, setCatalog] = useState<OrganizerBillingJson>({});
  const [snapshot, setSnapshot] = useState<OrganizerBillingJson>({});
  const [usage, setUsage] = useState<OrganizerBillingJson>({});
  const [write, setWrite] = useState<OrganizerBillingJson>({});
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [fromCache, setFromCache] = useState(false);
  const [online, setOnline] = useState(true);
  const [billingInterval, setBillingInterval] = useState<"month" | "year">("month");
  const [confirmation, setConfirmation] = useState<OrganizerBillingJson>({});
  const pending = useRef<PendingOperation | null>(null);
  const refreshTimer = useRef<number | null>(null);
  const realtimeStatus = useRef("");

  const selected = useMemo(() => {
    const [kind, id] = selectedKey.split(":");
    return organizers.find((item) => organizerBillingText(item.kind) === kind && organizerBillingText(item.id) === id) ?? null;
  }, [organizers, selectedKey]);

  const loadSnapshot = useCallback(async (selectedOrganizer: OrganizerBillingJson, accessToken: string, allowCache = true) => {
    const kind = organizerBillingText(selectedOrganizer.kind);
    const id = organizerBillingText(selectedOrganizer.id);
    if (allowCache) {
      const cached = readSnapshotCache(kind, id);
      const cachedCanonical = organizerBillingRecord(cached.canonical);
      if (Object.keys(cachedCanonical).length) {
        setSnapshot(cachedCanonical);
        setUsage(organizerBillingRecord(cached.usage));
        setWrite(organizerBillingRecord(cached.write));
        setFromCache(true);
      }
    }
    const query = new URLSearchParams({ organizerId: id, organizerKind: kind });
    const response = await fetch(`/api/billing/organizer/snapshot?${query.toString()}`, { cache: "no-store", headers: bearer(accessToken) });
    const body = await readJson(response);
    const canonical = organizerBillingRecord(body.canonical);
    const canonicalUsage = organizerBillingRecord(body.usage);
    const canonicalWrite = organizerBillingRecord(body.write);
    setSnapshot(canonical);
    setUsage(canonicalUsage);
    setWrite(canonicalWrite);
    setFromCache(false);
    setMessage("");
    storeSnapshotCache(kind, id, { canonical, usage: canonicalUsage, write: canonicalWrite });
  }, []);

  useEffect(() => {
    let active = true;
    queueMicrotask(() => {
      if (active) setOnline(typeof navigator === "undefined" || navigator.onLine);
    });
    if (!supabase) {
      queueMicrotask(() => {
        if (active) setMessage("La conexion segura no esta configurada.");
      });
      return () => { active = false; };
    }
    void supabase.auth.getSession().then(async ({ data }) => {
      const accessToken = data.session?.access_token ?? "";
      if (!active) return;
      if (!accessToken) {
        setMessage("Inicia sesion para consultar la facturacion de tus organizaciones.");
        return;
      }
      setToken(accessToken);
      try {
        const [organizerResponse, catalogResponse] = await Promise.all([
          fetch("/api/billing/organizer/organizers", { cache: "no-store", headers: bearer(accessToken) }),
          fetch("/api/billing/organizer/catalog", { cache: "no-store" }),
        ]);
        const organizerBody = await readJson(organizerResponse);
        const catalogBody = await readJson(catalogResponse);
        if (!active) return;
        const items = organizerBillingArray(organizerBillingRecord(organizerBody.canonical).items);
        setOrganizers(items);
        setCatalog(organizerBillingRecord(catalogBody.canonical));
        const requested = items.find((item) => organizerBillingText(item.kind) === initialOrganizerKind.toUpperCase()
          && organizerBillingText(item.id) === initialOrganizerId);
        const first = requested ?? items[0];
        if (first) setSelectedKey(`${organizerBillingText(first.kind)}:${organizerBillingText(first.id)}`);
        else setMessage("Necesitas ser owner de un equipo o Club para gestionar esta facturacion.");
      } catch (error) {
        if (active) setMessage(error instanceof Error ? error.message : "No se pudo cargar la facturacion.");
      }
    });
    return () => { active = false; };
  }, [initialOrganizerId, initialOrganizerKind]);

  useEffect(() => {
    if (!selected || !token) return;
    let active = true;
    queueMicrotask(() => {
      if (!active) return;
      void loadSnapshot(selected, token).catch((error) => {
        if (active) setMessage(error instanceof Error ? error.message : "No se pudo actualizar el estado oficial.");
      });
    });
    return () => { active = false; };
  }, [loadSnapshot, selected, token]);

  useEffect(() => {
    const onOnline = () => {
      setOnline(true);
      if (selected && token) void loadSnapshot(selected, token, false).catch(() => setMessage("No se pudo sincronizar al recuperar la conexion."));
    };
    const onOffline = () => setOnline(false);
    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);
    return () => {
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
    };
  }, [loadSnapshot, selected, token]);

  useEffect(() => {
    if (!supabase || !selected || !token) return;
    const realtimeClient = supabase;
    const kind = organizerBillingText(selected.kind);
    const id = organizerBillingText(selected.id);
    const filter = `${kind === "CLUB" ? "organizer_club_id" : "organizer_group_id"}=eq.${id}`;
    const scheduleCanonicalReload = () => {
      if (refreshTimer.current) window.clearTimeout(refreshTimer.current);
      refreshTimer.current = window.setTimeout(() => {
        void loadSnapshot(selected, token, false).catch(() => setMessage("El cambio llego por Realtime, pero no se pudo releer el snapshot."));
      }, 140);
    };
    const channel = realtimeClient.channel(`organizer-billing:${kind}:${id}`)
      .on("postgres_changes", { event: "*", filter, schema: "public", table: "pachanga_organizer_billing_invalidations_v1" }, scheduleCanonicalReload)
      .subscribe((status) => {
        if (status === "SUBSCRIBED" && realtimeStatus.current !== "SUBSCRIBED") scheduleCanonicalReload();
        realtimeStatus.current = status;
      });
    return () => {
      if (refreshTimer.current) window.clearTimeout(refreshTimer.current);
      realtimeStatus.current = "";
      void realtimeClient.removeChannel(channel);
    };
  }, [loadSnapshot, selected, token]);

  useEffect(() => {
    if (checkoutStatus !== "confirming" || !checkoutOperationId || !token || !selected) return;
    let active = true;
    let attempt = 0;
    const poll = async () => {
      attempt += 1;
      try {
        const response = await fetch(`/api/billing/organizer/status?operationId=${encodeURIComponent(checkoutOperationId)}`, { cache: "no-store", headers: bearer(token) });
        const body = await readJson(response);
        const canonical = organizerBillingRecord(body.canonical);
        if (!active) return;
        setConfirmation(canonical);
        if (organizerBillingBoolean(canonical.entitlementActive)) {
          await loadSnapshot(selected, token, false);
          return;
        }
      } catch (error) {
        if (active) setMessage(error instanceof Error ? error.message : "No se pudo confirmar la suscripcion.");
      }
      if (active && attempt < 20) window.setTimeout(() => void poll(), 1500);
    };
    void poll();
    return () => { active = false; };
  }, [checkoutOperationId, checkoutStatus, loadSnapshot, selected, token]);

  async function startHostedSession(kind: "checkout" | "portal") {
    if (!selected || !token) return;
    if (!online) {
      setMessage("Sin conexion: las operaciones de facturacion no se guardan ni se ponen en cola.");
      return;
    }
    const organizerKind = organizerBillingText(selected.kind);
    const organizerId = organizerBillingText(selected.id);
    const selectedPlan = organizerBillingPlanForKind(organizerBillingArray(catalog.plans), organizerKind);
    const key = JSON.stringify({ billingInterval, kind, organizerId, organizerKind, planCode: organizerBillingText(selectedPlan?.planCode), revision: organizerBillingNumber(write.revision) });
    const operationId = operationFor(pending, key);
    setBusy(true);
    setMessage("");
    try {
      const response = await clientWriteFetch(`api:organizer-billing-${kind}`, `/api/billing/organizer/${kind}`, {
        body: JSON.stringify(kind === "checkout" ? {
          billingInterval,
          expectedRevision: organizerBillingNumber(write.revision),
          operationId,
          organizerId,
          organizerKind,
          planCode: organizerBillingText(selectedPlan?.planCode),
        } : {
          expectedRevision: organizerBillingNumber(write.revision),
          operationId,
          organizerId,
          organizerKind,
        }),
        headers: { ...bearer(token), "Content-Type": "application/json" },
        method: "POST",
      });
      const body = await readJson(response);
      const url = organizerBillingSafeUrl(organizerBillingRecord(body.canonical).url);
      if (!url) throw new Error("El servidor no devolvio una sesion segura.");
      pending.current = null;
      window.location.assign(url);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "La operacion no fue confirmada.");
      if (/cambiado|revision/i.test(error instanceof Error ? error.message : "")) {
        await loadSnapshot(selected, token, false).catch(() => undefined);
      }
    } finally {
      setBusy(false);
    }
  }

  const accounts = organizerBillingArray(snapshot.accounts);
  const accessGrants = organizerBillingArray(snapshot.accessGrants);
  const invoices = organizerBillingArray(snapshot.invoices);
  const continuity = organizerBillingArray(snapshot.continuity);
  const availability = organizerBillingRecord(snapshot.availability);
  const usageValues = organizerBillingRecord(usage.usage);
  const limitValues = organizerBillingRecord(usage.limits);
  const mode = organizerBillingText(write.mode);
  const writeAccount = accounts.find((account) => organizerBillingText(account.mode) === mode) ?? accounts[0];
  const currentPlan = organizerBillingRecord(writeAccount?.plan);
  const selectedPlan = selected ? organizerBillingPlanForKind(organizerBillingArray(catalog.plans), organizerBillingText(selected.kind)) : null;
  const checkoutAllowed = mode === "test" ? organizerBillingBoolean(availability.sandboxCheckout) : organizerBillingBoolean(availability.liveCheckout);
  const portalAllowed = (mode === "test" ? organizerBillingBoolean(availability.sandboxPortal) : organizerBillingBoolean(availability.livePortal))
    && organizerBillingBoolean(writeAccount?.customerConfigured)
    && organizerBillingNumber(write.revision) > 0;
  const actionDisabled = busy || fromCache || !online;
  const confirmationActive = organizerBillingBoolean(confirmation.entitlementActive);

  return (
    <OfficialProductShellV2 active="perfil" context={{ detail: selected ? organizerBillingText(selected.name) : "Owner", eyebrow: "Ajustes", status: fromCache ? "Copia local" : online ? "Servidor central" : "Sin conexion", title: "Facturacion" }}>
      <main className={styles.page}>
        <div className={styles.billingLayout}>
          <header className={styles.intro}>
            <div><span className={styles.eyebrow}>Organizer billing</span><h1>Planes y facturacion</h1><p>Consulta el acceso de tus equipos y Clubs. Stripe gestiona el cobro; PostgreSQL confirma los permisos deportivos.</p></div>
            <Link className={styles.secondary} href="/planes-organizador">Ver planes</Link>
          </header>
          {message ? <p className={styles.message} data-tone="warning" role="status">{message}</p> : null}
          {checkoutStatus === "cancelled" ? <p className={styles.message} data-tone="warning" role="status">Checkout cancelado. No se ha concedido ningun acceso.</p> : null}
          {checkoutStatus === "confirming" ? <section className={styles.confirmation} aria-live="polite"><div><strong>{confirmationActive ? "Suscripcion confirmada" : "Confirmando con el servidor"}</strong><p>{confirmationActive ? "El permiso canonico ya esta activo." : "El retorno de Stripe no concede acceso. Esperamos el webhook firmado y releemos PostgreSQL."}</p></div><span className={styles.status} data-tone={confirmationActive ? "good" : "warning"}>{organizerBillingStatus(confirmation.confirmation || "PENDING")}</span></section> : null}
          {organizers.length ? <section className={styles.organizerBar}>
            <label>Organizacion<select value={selectedKey} onChange={(event) => setSelectedKey(event.target.value)}>{organizers.map((item) => <option key={`${organizerBillingText(item.kind)}:${organizerBillingText(item.id)}`} value={`${organizerBillingText(item.kind)}:${organizerBillingText(item.id)}`}>{organizerBillingText(item.kind) === "CLUB" ? "Club" : "Equipo"} · {organizerBillingText(item.name)}</option>)}</select></label>
            <p className={styles.cacheNote}>{fromCache ? "Copia guardada, solo lectura" : snapshot.updatedAt ? `Actualizado ${organizerBillingDate(snapshot.updatedAt, true)}` : "Cargando estado oficial"}</p>
          </section> : null}
          {selected && !organizerBillingBoolean(snapshot.enabled) && Object.keys(snapshot).length ? <p className={styles.empty}>La facturacion de organizadores aun no esta habilitada.</p> : null}
          {selected && organizerBillingBoolean(snapshot.enabled) ? <>
            <section className={styles.metrics} aria-label="Resumen de facturacion">
              <div className={styles.metric}><span>Organizacion</span><strong>{organizerBillingText(selected.name)}</strong></div>
              <div className={styles.metric}><span>Acceso</span><strong>{accessGrants[0] ? organizerBillingStatus(accessGrants[0].status) : "Sin acceso"}</strong></div>
              <div className={styles.metric}><span>Plan</span><strong>{organizerBillingText(currentPlan.name, organizerBillingText(accessGrants[0]?.planName, "Sin plan"))}</strong></div>
              <div className={styles.metric}><span>Impuestos</span><strong>{organizerBillingStatus(availability.taxHealth)}</strong></div>
            </section>
            <section className={styles.sectionBand}>
              <header className={styles.sectionHeader}><div><span>Acciones</span><h2>Gestion del plan</h2></div><p>Checkout y Portal se abren en Stripe. Ningun boton confirma permisos por adelantado.</p></header>
              <div className={styles.actionRow}>
                <select aria-label="Periodo de facturacion" disabled={actionDisabled} value={billingInterval} onChange={(event) => setBillingInterval(event.target.value === "year" ? "year" : "month")}><option value="month">Mensual</option><option value="year">Anual</option></select>
                <button className={styles.primary} disabled={actionDisabled || !checkoutAllowed || !selectedPlan} onClick={() => void startHostedSession("checkout")} type="button">{busy ? "Abriendo..." : `Activar ${organizerBillingText(selectedPlan?.displayName, "plan")}`}</button>
                <button className={styles.secondary} disabled={actionDisabled || !portalAllowed} onClick={() => void startHostedSession("portal")} type="button">Gestionar en Stripe</button>
                {!checkoutAllowed ? <span className={styles.status} data-tone="warning">Checkout pendiente de activacion</span> : null}
              </div>
            </section>
            <section className={styles.sectionBand}>
              <header className={styles.sectionHeader}><div><span>Estado</span><h2>Cuentas y accesos confirmados</h2></div><p>Las revisiones y secuencias proceden del servidor.</p></header>
              {accounts.length ? <div className={styles.accountGrid}>{accounts.map((account) => <AccountSummary account={account} key={organizerBillingText(account.id)} />)}</div> : <p className={styles.empty}>Todavia no existe una cuenta de facturacion para esta organizacion.</p>}
              {accessGrants.length ? <div className={styles.accessGrid}>{accessGrants.map((access) => <AccessSummary access={access} key={organizerBillingText(access.id)} />)}</div> : null}
            </section>
            <section className={styles.sectionBand}>
              <header className={styles.sectionHeader}><div><span>Uso</span><h2>Consumo y limites</h2></div><p>Un limite pendiente no se inventa ni se interpreta como una cifra comercial.</p></header>
              <div className={styles.usageGrid}>{Object.keys(organizerLimitLabels).map((key) => <div className={styles.usage} key={key}><span>{organizerLimitLabels[key]}</span><strong>{organizerBillingNumber(usageValues[key])} / {limitValues[key] == null ? "Pendiente" : String(limitValues[key])}</strong></div>)}</div>
            </section>
            {continuity.length ? <section className={styles.sectionBand}><header className={styles.sectionHeader}><div><span>Continuidad</span><h2>Ediciones protegidas</h2></div><p>Una competicion ya iniciada puede terminar sin reabrir nuevas creaciones.</p></header><div className={styles.continuityGrid}>{continuity.map((item) => <article className={styles.continuity} key={organizerBillingText(item.editionId)}><div className={styles.row}><strong>Edicion protegida</strong><span className={styles.status} data-tone={organizerBillingTone(item.status)}>{organizerBillingStatus(item.status)}</span></div><div className={styles.row}><span>Final previsto</span><strong>{organizerBillingDate(item.plannedEnd)}</strong></div><div className={styles.row}><span>Continuidad hasta</span><strong>{organizerBillingDate(item.continuityUntil)}</strong></div></article>)}</div></section> : null}
            <section className={styles.sectionBand}>
              <header className={styles.sectionHeader}><div><span>Documentos</span><h2>Facturas</h2></div><p>Los enlaces se muestran solo al owner autenticado de la organizacion.</p></header>
              {invoices.length ? <div className={styles.tableRegion} role="region" aria-label="Facturas" tabIndex={0}><table><thead><tr><th>Estado</th><th>Importe</th><th>Pagado</th><th>Vencimiento</th><th>Documento</th></tr></thead><tbody>{invoices.map((invoice) => { const hosted = organizerBillingSafeUrl(invoice.hostedInvoiceUrl); const pdf = organizerBillingSafeUrl(invoice.invoicePdfUrl); return <tr key={organizerBillingText(invoice.id)}><td><span className={styles.status} data-tone={organizerBillingTone(invoice.status)}>{organizerBillingStatus(invoice.status)}</span></td><td>{organizerBillingMoney(invoice.amountDue, invoice.currency)}</td><td>{organizerBillingMoney(invoice.amountPaid, invoice.currency)}</td><td>{organizerBillingDate(invoice.dueAt)}</td><td>{hosted ? <a href={hosted} target="_blank" rel="noreferrer">Abrir</a> : pdf ? <a href={pdf} target="_blank" rel="noreferrer">PDF</a> : "No disponible"}</td></tr>; })}</tbody></table></div> : <p className={styles.empty}>No hay facturas confirmadas para esta organizacion.</p>}
            </section>
          </> : null}
        </div>
      </main>
    </OfficialProductShellV2>
  );
}

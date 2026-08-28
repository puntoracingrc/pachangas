"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { clientWriteFetch } from "../pwa-client-bridge";
import { supabase } from "../supabaseClient";
import {
  publicCompetitionArray,
  publicCompetitionBoolean,
  publicCompetitionNumber,
  publicCompetitionRealtimeTable,
  publicCompetitionRecord,
  publicCompetitionText,
  type PublicCompetitionAction,
  type PublicCompetitionJson,
} from "../public-competition-contract";
import { ProductFeedback, SectionHeader, StatusChip } from "./official-ui-v2-primitives";
import styles from "./competition-publication-control.module.css";

const sectionKeys = ["teams", "calendar", "results", "standings", "bracket", "referees", "venueDetail"] as const;

function slugify(value: string) {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 80);
}

export function CompetitionPublicationControl({ competitionId, competitionName }: { competitionId: string; competitionName: string }) {
  const [accessToken, setAccessToken] = useState("");
  const [data, setData] = useState<PublicCompetitionJson>({});
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [slug, setSlug] = useState(slugify(competitionName));
  const [visibility, setVisibility] = useState("private");
  const [description, setDescription] = useState("");
  const [municipality, setMunicipality] = useState("");
  const [generalArea, setGeneralArea] = useState("");
  const [format, setFormat] = useState("");
  const [rulesSummary, setRulesSummary] = useState("");
  const [publicVenue, setPublicVenue] = useState("");
  const [imageUrl, setImageUrl] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [sections, setSections] = useState<Record<string, boolean>>({ bracket: true, calendar: true, referees: false, results: true, standings: true, teams: true, venueDetail: false });
  const [consents, setConsents] = useState<Record<string, boolean>>({ authorizedRepresentative: false, indexingAccepted: false, informationAccurate: false, teamAssetsAuthorized: false });
  const [registrationMode, setRegistrationMode] = useState("INVITE_ONLY");
  const [opensAt, setOpensAt] = useState("");
  const [closesAt, setClosesAt] = useState("");
  const pending = useRef<{ id: string; key: string } | null>(null);
  const timer = useRef<number | null>(null);

  const load = useCallback(async (token: string, source: "initial" | "mutation" | "realtime") => {
    try {
      const response = await fetch(`/api/competitions/public/publication/${competitionId}`, { cache: "no-store", headers: { Authorization: `Bearer ${token}` } });
      const body = publicCompetitionRecord(await response.json());
      if (!response.ok) throw new Error(publicCompetitionText(body.message) || "No se pudo cargar la publicación.");
      setData(body);
      const authority = publicCompetitionRecord(body.snapshot);
      const publication = publicCompetitionRecord(authority.publication);
      const profile = publicCompetitionRecord(publication.publicProfile);
      const publicSections = publicCompetitionRecord(publication.publicSections);
      const scope = publicCompetitionRecord(body.scope);
      const categories = publicCompetitionArray(scope.categories);
      if (publicCompetitionText(publication.id)) {
        setSlug(publicCompetitionText(publication.slug));
        setVisibility(publicCompetitionText(publication.visibility));
        setDescription(publicCompetitionText(profile.description));
        setMunicipality(publicCompetitionText(profile.municipality));
        setGeneralArea(publicCompetitionText(profile.generalArea));
        setFormat(publicCompetitionText(profile.format));
        setRulesSummary(publicCompetitionText(profile.rulesSummary));
        setPublicVenue(publicCompetitionText(profile.publicVenue));
        setImageUrl(publicCompetitionText(profile.imageUrl));
        setCategoryId(publicCompetitionText(publication.categoryId));
        setSections(Object.fromEntries(sectionKeys.map((key) => [key, publicCompetitionBoolean(publicSections[key])])));
        const readModel = publicCompetitionRecord(authority.publicReadModel);
        const registration = publicCompetitionRecord(readModel.registration);
        if (publicCompetitionText(registration.mode)) setRegistrationMode(publicCompetitionText(registration.mode));
        if (publicCompetitionText(registration.opensAt)) setOpensAt(publicCompetitionText(registration.opensAt).slice(0, 16));
        if (publicCompetitionText(registration.closesAt)) setClosesAt(publicCompetitionText(registration.closesAt).slice(0, 16));
      } else if (categories[0]) {
        setCategoryId((current) => current || publicCompetitionText(categories[0].id));
      }
      if (source === "realtime") setMessage("Publicación actualizada desde el servidor.");
    } catch (error) { setMessage(error instanceof Error ? error.message : "No se pudo cargar la publicación."); }
  }, [competitionId]);

  useEffect(() => {
    let active = true;
    let channel: ReturnType<NonNullable<typeof supabase>["channel"]> | null = null;
    const start = async () => {
      const session = (await supabase?.auth.getSession())?.data.session;
      if (!active || !session) return;
      setAccessToken(session.access_token);
      await load(session.access_token, "initial");
      if (!supabase) return;
      const reconcile = () => {
        if (timer.current) window.clearTimeout(timer.current);
        timer.current = window.setTimeout(() => void load(session.access_token, "realtime"), 120);
      };
      channel = supabase.channel(`competition-publication:${competitionId}:${session.user.id}`)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: publicCompetitionRealtimeTable }, (payload) => {
          const row = publicCompetitionRecord(payload.new);
          if (publicCompetitionText(row.competition_id) === competitionId) reconcile();
        }).subscribe((state) => { if (state === "SUBSCRIBED") reconcile(); });
    };
    void start();
    return () => { active = false; if (timer.current) window.clearTimeout(timer.current); if (channel && supabase) void supabase.removeChannel(channel); };
  }, [competitionId, load]);

  async function command(action: PublicCompetitionAction, expectedRevision: number, payload: PublicCompetitionJson) {
    if (!accessToken) return;
    if (!navigator.onLine) { setMessage("Sin conexión. El cambio no se ha enviado."); return; }
    const key = JSON.stringify({ action, competitionId, expectedRevision, payload });
    if (!pending.current || pending.current.key !== key) pending.current = { id: crypto.randomUUID(), key };
    setBusy(true); setMessage("Esperando confirmación de PostgreSQL...");
    try {
      const response = await clientWriteFetch("api:public-competition-publication", "/api/competitions/public/command", {
        body: JSON.stringify({ action, aggregateId: competitionId, expectedRevision, operationId: pending.current.id, payload }),
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        method: "POST",
      });
      const body = publicCompetitionRecord(await response.json());
      if (!response.ok) throw new Error(publicCompetitionText(body.message) || "Cambio no confirmado.");
      pending.current = null; setMessage("Cambio confirmado por el servidor.");
      await load(accessToken, "mutation");
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Cambio no confirmado.";
      setMessage(/STALE_REVISION|revision/i.test(detail) ? "La revisión cambió. Se ha recuperado el estado oficial." : detail);
      if (/STALE_REVISION|revision/i.test(detail)) await load(accessToken, "mutation");
    } finally { setBusy(false); }
  }

  const authority = publicCompetitionRecord(data.snapshot);
  const publication = publicCompetitionRecord(authority.publication);
  const flags = publicCompetitionRecord(authority.flags);
  const scope = publicCompetitionRecord(data.scope);
  const edition = publicCompetitionRecord(scope.edition);
  const categories = publicCompetitionArray(scope.categories);
  const status = publicCompetitionText(publication.status);
  const revision = publicCompetitionNumber(publication.revision);
  const exists = Boolean(publicCompetitionText(publication.id));
  const allConsented = Object.values(consents).every(Boolean);
  const profile = { description, format, generalArea, imageUrl, municipality, name: competitionName, publicVenue, rulesSummary };
  const payload = { categoryId, editionId: publicCompetitionText(edition.id), publicProfile: profile, publicSections: sections, reason: exists ? "Actualizar perfil público" : "Preparar perfil público", slug, visibility };

  return <section className={styles.surface} data-publication-status={status || "not_prepared"}>
    <SectionHeader eyebrow="Publicación y discovery" title="Perfil público de competición" />
    {message ? <ProductFeedback tone={/confirmado|actualizada/i.test(message) ? "success" : /Sin conexión/i.test(message) ? "warning" : "info"}>{message}</ProductFeedback> : null}
    <header className={styles.status}><div><StatusChip tone={status === "published" ? "success" : status === "suspended" || status === "rejected" ? "danger" : "warning"}>{status ? status.replaceAll("_", " ") : "Sin preparar"}</StatusChip>{publicCompetitionBoolean(publication.organizerVerified) ? <StatusChip tone="success">Organizador verificado</StatusChip> : null}</div>{publicCompetitionText(publication.slug) && status === "published" ? <Link href={`/competiciones/${publicCompetitionText(publication.slug)}`}>Abrir página pública</Link> : null}</header>
    <div className={styles.grid}>
      <label>Visibilidad<select value={visibility} disabled={busy || status === "suspended" || status === "archived"} onChange={(event) => setVisibility(event.target.value)}><option value="private">Privada</option><option value="unlisted">No listada</option><option value="public">Pública</option></select></label>
      <label>Slug<input value={slug} maxLength={80} pattern="[a-z0-9]+(?:-[a-z0-9]+)*" disabled={busy || status === "suspended" || status === "archived"} onChange={(event) => setSlug(slugify(event.target.value))} /></label>
      <label>Edición<input readOnly value={publicCompetitionText(edition.name)} /></label>
      <label>Categoría<select value={categoryId} disabled={busy || exists} onChange={(event) => setCategoryId(event.target.value)}>{categories.map((category) => <option key={publicCompetitionText(category.id)} value={publicCompetitionText(category.id)}>{publicCompetitionText(category.name)}</option>)}</select></label>
      <label>Municipio<input value={municipality} maxLength={120} onChange={(event) => setMunicipality(event.target.value)} /></label>
      <label>Área general<input value={generalArea} maxLength={160} onChange={(event) => setGeneralArea(event.target.value)} /></label>
      <label>Formato público<input value={format} maxLength={120} placeholder="Liga, grupos, eliminatoria..." onChange={(event) => setFormat(event.target.value)} /></label>
      <label>Sede pública<input value={publicVenue} maxLength={240} placeholder="Solo si está consentida" onChange={(event) => setPublicVenue(event.target.value)} /></label>
      <label className={styles.wide}>Imagen HTTPS<input value={imageUrl} type="url" onChange={(event) => setImageUrl(event.target.value)} /></label>
      <label className={styles.wide}>Descripción<textarea value={description} rows={3} maxLength={2400} onChange={(event) => setDescription(event.target.value)} /></label>
      <label className={styles.wide}>Resumen del reglamento<textarea value={rulesSummary} rows={3} maxLength={1000} onChange={(event) => setRulesSummary(event.target.value)} /></label>
    </div>
    <fieldset className={styles.sections}><legend>Secciones públicas</legend>{sectionKeys.map((key) => { const flagKey = key === "venueDetail" ? null : key; const globallyEnabled = flagKey == null || publicCompetitionBoolean(flags[flagKey]); return <label key={key}><input type="checkbox" checked={sections[key] ?? false} disabled={busy || !globallyEnabled} onChange={(event) => setSections((current) => ({ ...current, [key]: event.target.checked }))} />{key.replaceAll(/([A-Z])/g, " $1").replaceAll("_", " ")}{!globallyEnabled ? " · no disponible" : ""}</label>; })}<label className={styles.disabled}><input type="checkbox" disabled />Disciplina · privada en V1</label></fieldset>
    <div className={styles.actions}><button type="button" disabled={busy || !categoryId || !slug || status === "suspended" || status === "archived"} onClick={() => void command(exists ? "publication.update" : "publication.prepare", exists ? revision : 0, payload)}>{exists ? "Guardar perfil público" : "Preparar publicación"}</button>{status === "pending_review" ? <button type="button" disabled={busy} onClick={() => void command("publication.withdraw", revision, { reason: "Retirar revisión" })}>Retirar revisión</button> : null}{status === "published" ? <button type="button" disabled={busy} onClick={() => void command("publication.unpublish", revision, { reason: "Retirar publicación" })}>Despublicar</button> : null}</div>

    {exists && ["draft", "rejected", "changes_requested"].includes(status) ? <section className={styles.consent}><h3>Consentimiento de publicación</h3><div>{Object.entries({ authorizedRepresentative: "Estoy autorizado para representar la competición", informationAccurate: "La información es correcta", teamAssetsAuthorized: "Los equipos y escudos tienen autorización", indexingAccepted: "Acepto la indexación de las secciones públicas" }).map(([key, label]) => <label key={key}><input type="checkbox" checked={consents[key] ?? false} onChange={(event) => setConsents((current) => ({ ...current, [key]: event.target.checked }))} />{label}</label>)}</div><div className={styles.actions}><button type="button" disabled={busy || !allConsented} onClick={() => void command("publication.consent", revision, { purpose: "Publicar la competición y sus secciones consentidas.", reason: "Consentimiento público V1", statements: consents })}>Confirmar consentimiento</button><button type="button" disabled={busy || !publicCompetitionBoolean(publication.hasCurrentConsent) || visibility === "private"} onClick={() => void command("publication.submit", revision, { reason: "Enviar publicación a revisión" })}>Enviar a revisión</button></div></section> : null}

    {exists ? <section className={styles.registration}><h3>Modo de inscripción</h3><div><label>Modo<select value={registrationMode} onChange={(event) => setRegistrationMode(event.target.value)}><option value="INVITE_ONLY">Solo invitación</option><option value="REQUEST_APPROVAL" disabled={!publicCompetitionBoolean(flags.registrationRequests) || visibility !== "public"}>Solicitud y aprobación</option><option value="CLOSED">Cerrada</option></select></label><label>Apertura<input type="datetime-local" value={opensAt} onChange={(event) => setOpensAt(event.target.value)} /></label><label>Cierre<input type="datetime-local" value={closesAt} onChange={(event) => setClosesAt(event.target.value)} /></label><button type="button" disabled={busy} onClick={() => void command("registration.configure", revision, { closesAt, mode: registrationMode, opensAt, reason: "Configurar inscripción pública" })}>Guardar inscripción</button></div></section> : null}
  </section>;
}

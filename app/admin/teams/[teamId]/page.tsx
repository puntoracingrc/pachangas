import Link from "next/link";
import { notFound } from "next/navigation";
import { DataTable, Definition, Identifier, PageHeader, Panel, StatusBadge, formatAdminDate } from "../../_components/platform-ui";
import { requirePlatformPage } from "../../_lib/platform-auth";
import { hasPlatformCapability } from "../../_lib/platform-contract";
import { getPlatformTeamDetail } from "../../_lib/platform-data";
import {
  teamOperationalAppealLabel,
  teamOperationalContinuityLabel,
  teamOperationalScopeLabel,
  teamOperationalStatusLabel,
} from "../../../team-operational-contract";
import { TeamOperationalAdminActions } from "./team-operational-admin-actions";
import styles from "../../platform-admin.module.css";

type Params = Promise<{ teamId: string }>;
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
function list(value: unknown) { return Array.isArray(value) ? value.map(record) : []; }
function operationalTone(value: unknown): "danger" | "good" | "info" | "muted" | "warning" {
  if (value === "SUSPENDED" || value === "ARCHIVED") return "danger";
  if (value === "LIMITED") return "warning";
  if (value === "UNDER_REVIEW") return "info";
  if (value === "ACTIVE") return "good";
  return "muted";
}

export default async function PlatformTeamDetailPage({ params }: { params: Params }) {
  const session = await requirePlatformPage("teams.read");
  const { teamId } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(teamId)) notFound();
  const detail = await getPlatformTeamDetail(session, teamId);
  const group = record(detail.group);
  const market = record(detail.market);
  const operational = record(detail.operational);
  const operationalHealth = record(operational.health);
  const operationalImpact = record(operational.impact);
  const operationalAppeal = record(operational.appeal);
  const operationalRestrictions = list(operational.restrictions);
  const operationalReviews = list(operational.reviews);
  const operationalEvents = list(operational.events);
  const operationalReceipts = list(operational.receipts);
  const affectedEntries = list(operational.affectedCompetitionEntries);
  const affectedApplications = list(operational.affectedOrganizerApplications);
  const affectedRegistrations = list(operational.affectedRegistrationRequests);
  const canReadBilling = hasPlatformCapability(session.access, "billing.read");
  const canReviewOperational = hasPlatformCapability(session.access, "teams.operational.review");
  const canEnforceOperational = hasPlatformCapability(session.access, "teams.operational.enforce");
  const canResolveAppeals = hasPlatformCapability(session.access, "teams.operational.appeals");
  return (
    <>
      <PageHeader title={String(group.name ?? "Equipo")} subtitle="Detalle transversal de identidad, estado operativo, competición, plantilla, Retos, rewards y Billing independiente." actions={<><StatusBadge tone={operationalTone(operational.effectiveStatus)}>{teamOperationalStatusLabel(operational.effectiveStatus)}</StatusBadge><Link className={styles.secondaryButton} href="/admin/teams">Volver</Link>{canReadBilling ? <Link className={styles.secondaryButton} href={`/admin/billing?team=${teamId}`}>Ver billing</Link> : null}</>} />
      <div className={styles.detailGrid}>
        <section><h2>Estado operativo</h2><dl className={styles.definitionList}>
          <Definition label="Estado efectivo"><StatusBadge tone={operationalTone(operational.effectiveStatus)}>{teamOperationalStatusLabel(operational.effectiveStatus)}</StatusBadge></Definition>
          <Definition label="Lifecycle">{teamOperationalStatusLabel(operational.lifecycle)}</Definition>
          <Definition label="Enforcement">{teamOperationalStatusLabel(operational.enforcement)}</Definition>
          <Definition label="Revisión">{String(operational.revision ?? 0)} · seq {String(operational.serverSequence ?? 0)}</Definition>
          <Definition label="Vigencia">{operational.effectiveUntil ? formatAdminDate(operational.effectiveUntil) : "Sin caducidad"}</Definition>
        </dl></section>
        <section><h2>Continuidad e impacto</h2><dl className={styles.definitionList}>
          <Definition label="Política">{teamOperationalContinuityLabel(operational.continuityPolicy)}</Definition>
          <Definition label="Competiciones activas">{String(operationalImpact.activeCompetitionEntries ?? 0)}</Definition>
          <Definition label="Solicitudes bloqueadas">{String(operationalImpact.blockedOrganizerApplications ?? 0)}</Definition>
          <Definition label="Mercado / Retos">{String(operationalImpact.marketListings ?? 0)} / {String(operationalImpact.openChallenges ?? 0)}</Definition>
          <Definition label="Mensaje seguro">{String(operational.publicMessage || "Sin mensaje público")}</Definition>
        </dl></section>
        <section><h2>Salud canónica</h2><dl className={styles.definitionList}>
          <Definition label="Estado"><StatusBadge tone={Number(operationalHealth.issueCount) ? "warning" : "good"}>{String(operationalHealth.status ?? "-")}</StatusBadge></Definition>
          <Definition label="Incidencias">{String(operationalHealth.issueCount ?? 0)}</Definition>
          <Definition label="Códigos">{Array.isArray(operationalHealth.issues) && operationalHealth.issues.length ? operationalHealth.issues.join(", ") : "Ninguno"}</Definition>
          <Definition label="Siguiente acción">{String(operationalHealth.nextAction ?? "NONE")}</Definition>
        </dl></section>
      </div>

      <Panel title="Autoridad operativa de plataforma">
        <TeamOperationalAdminActions
          canAppeal={canResolveAppeals}
          canEnforce={canEnforceOperational}
          canReview={canReviewOperational}
          canonical={operational}
          teamId={teamId}
        />
      </Panel>

      <div className={styles.overviewColumns}>
        <Panel title={`Ámbitos activos (${operationalRestrictions.length})`}><div className={styles.compactList}>{operationalRestrictions.length ? operationalRestrictions.map((restriction, index) => <div key={`${String(restriction.id)}-${index}`}><strong>{teamOperationalScopeLabel(restriction.scope)}</strong><span>{String(restriction.publicMessage || "Sin mensaje público")} · {restriction.effectiveUntil ? `hasta ${formatAdminDate(restriction.effectiveUntil)}` : "sin caducidad"}</span></div>) : <p className={styles.helpText}>Sin restricciones activas.</p>}</div></Panel>
        <Panel title={`Revisiones humanas (${operationalReviews.length})`}><div className={styles.compactList}>{operationalReviews.length ? operationalReviews.map((review, index) => <div key={`${String(review.id)}-${index}`}><strong>{String(review.status)} · {String(review.reasonCode)}</strong><span>{String(review.safeMessage || "Sin mensaje seguro")} · {formatAdminDate(review.openedAt)}</span>{canReviewOperational && review.privateNote ? <small>Privado: {String(review.privateNote)}</small> : null}</div>) : <p className={styles.helpText}>Sin revisiones.</p>}</div></Panel>
      </div>

      {Object.keys(operationalAppeal).length ? <Panel title="Apelación vigente o más reciente"><dl className={styles.definitionList}>
        <Definition label="Estado">{teamOperationalAppealLabel(operationalAppeal.status)}</Definition>
        <Definition label="Petición">{String(operationalAppeal.requestedOutcome ?? "REVIEW")}</Definition>
        <Definition label="Mensaje owner">{String(operationalAppeal.ownerMessage || "Sin mensaje")}</Definition>
        <Definition label="Resolución segura">{String(operationalAppeal.safeResolutionMessage || "Pendiente")}</Definition>
      </dl></Panel> : null}

      <Panel title="Objetos afectados, sin cambios históricos"><DataTable label="Objetos afectados por el estado operativo"><thead><tr><th>Tipo</th><th>Objeto</th><th>Estado</th><th>Continuidad o bloqueo</th></tr></thead><tbody>
        {affectedEntries.map((item, index) => <tr key={`entry-${String(item.id)}-${index}`}><td>CompetitionEntry</td><td><Identifier value={String(item.competitionId)} /></td><td>{String(item.status)}</td><td>{teamOperationalContinuityLabel(item.continuityPolicy)}</td></tr>)}
        {affectedApplications.map((item, index) => <tr key={`application-${String(item.id)}-${index}`}><td>Organizer Application</td><td><Identifier value={String(item.id)} /></td><td>{String(item.status)}</td><td>{String(item.operationalBlockedCode ?? "-")}</td></tr>)}
        {affectedRegistrations.map((item, index) => <tr key={`registration-${String(item.id)}-${index}`}><td>Registration Request</td><td><Identifier value={String(item.competitionId)} /></td><td>{String(item.status)}</td><td>{String(item.operationalBlockedCode ?? "-")}</td></tr>)}
      </tbody></DataTable></Panel>

      <div className={styles.detailGrid}>
        <section><h2>Identidad</h2><dl className={styles.definitionList}>
          <Definition label="Group ID"><Identifier value={teamId} /></Definition>
          <Definition label="Team code">{String(group.team_code ?? "No disponible")}</Definition>
          <Definition label="Owner"><Link href={`/admin/users/${String(group.owner_id)}`}><Identifier value={String(group.owner_id)} /></Link></Definition>
          <Definition label="Creado">{formatAdminDate(group.created_at)}</Definition>
          <Definition label="Revisión payload">{String(group.payload_revision ?? 0)}</Definition>
        </dl></section>
        <section><h2>Competición y Mercado</h2><dl className={styles.definitionList}>
          <Definition label="Mercado"><StatusBadge>{market.enabled ? "publicado" : "cerrado"}</StatusBadge></Definition>
          <Definition label="Zona">{String(market.zone_label ?? "No normalizada")}</Definition>
          <Definition label="Modalidades">{Array.isArray(market.modalities) ? market.modalities.join(", ") : "No disponibles"}</Definition>
          <Definition label="Nivel externo">{group.externally_calibrated_level == null ? "No calibrado" : Number(group.externally_calibrated_level).toFixed(1)}</Definition>
          <Definition label="Rating activo"><StatusBadge>{group.ratings_enabled ? "activo" : "inactivo"}</StatusBadge></Definition>
        </dl></section>
        {canReadBilling ? <section><h2>Suscripción</h2><dl className={styles.definitionList}>
          <Definition label="Estado local"><StatusBadge>{String(group.billing_status ?? "trial")}</StatusBadge></Definition>
          <Definition label="Intervalo">{String(group.billing_interval ?? "trial")}</Definition>
          <Definition label="Trial">{detail.trial.used}/{detail.trial.limit} partidos</Definition>
          <Definition label="Customer"><Identifier value={String(group.stripe_customer_id ?? "")} /></Definition>
          <Definition label="Subscription"><Identifier value={String(group.stripe_subscription_id ?? "")} /></Definition>
          <Definition label="Periodo fin">{formatAdminDate(group.stripe_current_period_end)}</Definition>
        </dl></section> : <section><h2>Suscripción</h2><p className={styles.helpText}>Información disponible únicamente para roles con acceso financiero.</p></section>}
      </div>

      <Panel title={`Miembros (${detail.members.length})`}><DataTable label="Miembros del equipo"><thead><tr><th>Miembro</th><th>Rol</th><th>Alta</th><th>Cambio de rol</th></tr></thead><tbody>{detail.members.map((member, index) => { const row = record(member); return <tr key={`${String(row.user_id)}-${index}`}><td><Link href={`/admin/users/${String(row.user_id)}`}>{String(row.display_name ?? "Usuario")}</Link><small><Identifier value={String(row.user_id)} /></small></td><td><StatusBadge tone="info">{String(row.role ?? "member")}</StatusBadge></td><td>{formatAdminDate(row.created_at)}</td><td>{formatAdminDate(row.role_changed_at)}</td></tr>; })}</tbody></DataTable></Panel>
      <Panel title={`Jugadores (${detail.players.length})`}><DataTable label="Jugadores del equipo"><thead><tr><th>Jugador</th><th>Posición</th><th>GRL</th><th>Fiabilidad</th><th>Estado</th><th>Actualizado</th></tr></thead><tbody>{detail.players.map((player, index) => { const row = record(player); return <tr key={`${String(row.id)}-${index}`}><td>{row.user_id ? <Link href={`/admin/users/${String(row.user_id)}`}>{String(row.display_name ?? "Jugador")}</Link> : String(row.display_name ?? "Invitado")}</td><td>{String(row.position ?? "-")}</td><td>{row.current_overall == null ? "-" : Number(row.current_overall).toFixed(1)}</td><td>{row.rating_reliability == null ? "-" : Number(row.rating_reliability).toFixed(2)}</td><td><StatusBadge>{row.inactive ? "inactivo" : row.injured ? "lesionado" : "activo"}</StatusBadge></td><td>{formatAdminDate(row.updated_at)}</td></tr>; })}</tbody></DataTable></Panel>
      <div className={styles.overviewColumns}>
        <Panel title={`Partidos (${detail.matches.length})`}><div className={styles.compactList}>{detail.matches.slice(0, 12).map((match, index) => { const row = record(match); return <Link href={`/admin/matches/${teamId}/${encodeURIComponent(String(row.match_id))}`} key={`${String(row.match_id)}-${index}`}><strong>{String(row.match_id)}</strong><span><StatusBadge>{String(row.match_state ?? "-")}</StatusBadge> · rev {String(row.match_version ?? 0)}</span></Link>; })}</div></Panel>
        <Panel title={`Retos (${detail.challenges.length})`}><div className={styles.compactList}>{detail.challenges.slice(0, 12).map((challenge, index) => { const row = record(challenge); return <Link href={`/admin/challenges/${String(row.id)}`} key={`${String(row.id)}-${index}`}><strong>{row.direction === "sent" ? "Enviado" : "Recibido"} · {String(row.modality ?? "Reto")}</strong><span><StatusBadge>{String(row.status ?? "-")}</StatusBadge> · {formatAdminDate(row.updated_at)}</span></Link>; })}</div></Panel>
      </div>
      <Panel title={`Team Cosmetics (${detail.cosmetics.count})`}><DataTable label="Cosméticos del equipo"><thead><tr><th>Cosmético</th><th>Estado</th><th>Origen</th><th>Desbloqueado</th><th>Revisión</th></tr></thead><tbody>{detail.cosmetics.items.map((item, index) => { const row = record(item); return <tr key={`${String(row.cosmetic_key)}-${index}`}><td>{String(row.cosmetic_key)}</td><td><StatusBadge>{String(row.state)}</StatusBadge></td><td>{String(row.source_kind ?? "-")}</td><td>{formatAdminDate(row.unlocked_at)}</td><td>{String(row.revision ?? 0)}</td></tr>; })}</tbody></DataTable></Panel>
      <div className={styles.overviewColumns}>
        <Panel title={`Eventos operativos (${operationalEvents.length})`}><div className={styles.compactList}>{operationalEvents.slice(0, 20).map((event, index) => <div key={`${String(event.id)}-${index}`}><strong>{String(event.eventKind)}</strong><span>rev {String(event.aggregateRevision)} · seq {String(event.serverSequence)} · {formatAdminDate(event.confirmedAt)}</span></div>)}</div></Panel>
        <Panel title={`Recibos idempotentes (${operationalReceipts.length})`}><div className={styles.compactList}>{operationalReceipts.slice(0, 20).map((receipt, index) => <div key={`${String(receipt.operationId)}-${index}`}><strong>{String(receipt.action)}</strong><span>{String(receipt.expectedRevision)} → {String(receipt.confirmedRevision)} · seq {String(receipt.serverSequence)}</span></div>)}</div></Panel>
      </div>
    </>
  );
}

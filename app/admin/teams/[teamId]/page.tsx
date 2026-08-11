import Link from "next/link";
import { notFound } from "next/navigation";
import { DataTable, Definition, Identifier, PageHeader, Panel, StatusBadge, formatAdminDate } from "../../_components/platform-ui";
import { requirePlatformPage } from "../../_lib/platform-auth";
import { hasPlatformCapability } from "../../_lib/platform-contract";
import { getPlatformTeamDetail } from "../../_lib/platform-data";
import styles from "../../platform-admin.module.css";

type Params = Promise<{ teamId: string }>;
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export default async function PlatformTeamDetailPage({ params }: { params: Params }) {
  const session = await requirePlatformPage("teams.read");
  const { teamId } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(teamId)) notFound();
  const detail = await getPlatformTeamDetail(session, teamId);
  const group = record(detail.group);
  const market = record(detail.market);
  const canReadBilling = hasPlatformCapability(session.access, "billing.read");
  return (
    <>
      <PageHeader title={String(group.name ?? "Equipo")} subtitle="Detalle transversal de plantilla, actividad deportiva, Retos, rewards y suscripción." actions={<><Link className={styles.secondaryButton} href="/admin/teams">Volver</Link>{canReadBilling ? <Link className={styles.secondaryButton} href={`/admin/billing?team=${teamId}`}>Ver billing</Link> : null}</>} />
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
    </>
  );
}

import Link from "next/link";
import { notFound } from "next/navigation";
import { UserRoleActions, UserStateActions } from "../../_components/user-authority-actions";
import { DataTable, Definition, Identifier, PageHeader, Panel, StatusBadge, formatAdminDate } from "../../_components/platform-ui";
import { requirePlatformPage } from "../../_lib/platform-auth";
import { hasPlatformCapability } from "../../_lib/platform-contract";
import { getPlatformUserDetail } from "../../_lib/platform-data";
import styles from "../../platform-admin.module.css";

type Params = Promise<{ userId: string }>;
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export default async function PlatformUserDetailPage({ params }: { params: Params }) {
  const session = await requirePlatformPage("users.read");
  const { userId } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(userId)) notFound();
  const detail = await getPlatformUserDetail(session, userId);
  const auth = record(detail.auth);
  const profile = record(detail.profile);
  const state = record(detail.state);
  const facets = record(profile.current_facets);
  const canSuspend = hasPlatformCapability(session.access, "users.suspend");
  const canManageRoles = hasPlatformCapability(session.access, "roles.manage");
  return (
    <>
      <PageHeader title={String(profile.display_name ?? auth.email ?? "Usuario")} subtitle="Ficha operativa global, conectada con Auth, perfil universal, grupos, Rating y rewards." actions={<Link className={styles.secondaryButton} href="/admin/users">Volver</Link>} />
      <div className={styles.detailGrid}>
        <section><h2>Identidad</h2><dl className={styles.definitionList}>
          <Definition label="User ID"><Identifier value={String(auth.id ?? "")} /></Definition>
          <Definition label="Email">{String(auth.email ?? "No disponible")}</Definition>
          <Definition label="Alta">{formatAdminDate(auth.createdAt)}</Definition>
          <Definition label="Último acceso">{formatAdminDate(auth.lastSignInAt)}</Definition>
          <Definition label="Proveedores">{Array.isArray(auth.providers) ? auth.providers.join(", ") : "No disponible"}</Definition>
        </dl></section>
        <section><h2>Estado de plataforma</h2><dl className={styles.definitionList}>
          <Definition label="Estado"><StatusBadge>{String(state.status ?? "active")}</StatusBadge></Definition>
          <Definition label="Auth sync"><StatusBadge>{String(state.authSyncState ?? "confirmed")}</StatusBadge></Definition>
          <Definition label="Expira">{formatAdminDate(state.statusExpiresAt)}</Definition>
          <Definition label="Restricciones">{Number(state.activeRestrictionCount) || 0}</Definition>
          <Definition label="Rol global">{state.platformRole ? <StatusBadge tone="info">{String(state.platformRole)}</StatusBadge> : "Sin rol"}</Definition>
        </dl></section>
        <section><h2>Rating V2</h2><dl className={styles.definitionList}>
          <Definition label="GRL">{profile.current_overall == null ? "Sin carta" : Number(profile.current_overall).toFixed(1)}</Definition>
          <Definition label="Fiabilidad">{profile.rating_reliability == null ? "No disponible" : Number(profile.rating_reliability).toFixed(2)}</Definition>
          <Definition label="Evaluadores">{Number(profile.rating_evaluator_count) || 0}</Definition>
          <Definition label="Motor">{String(profile.rating_engine_version ?? "No disponible")}</Definition>
          <Definition label="Recalculado">{formatAdminDate(profile.rating_recalculated_at)}</Definition>
        </dl></section>
      </div>

      {Object.keys(facets).length ? <Panel title="Facetas canónicas"><div className={styles.facets}>{Object.entries(facets).map(([key, value]) => <span key={key}><small>{key}</small><strong>{Number(value).toFixed(1)}</strong></span>)}</div></Panel> : null}

      <div className={styles.twoColumn}>
        <div>
          <Panel title="Equipos actuales">
            <DataTable label="Membresías del usuario"><thead><tr><th>Equipo</th><th>Rol</th><th>Desde</th></tr></thead><tbody>{detail.groups.map((group, index) => {
              const row = record(group); const linked = record(row.pachanga_groups);
              return <tr key={`${String(row.group_id)}-${index}`}><td><Link href={`/admin/teams/${String(row.group_id)}`}>{String(linked.name ?? row.display_name ?? "Equipo")}</Link><small>{String(linked.team_code ?? "")}</small></td><td><StatusBadge tone="info">{String(row.role ?? "member")}</StatusBadge></td><td>{formatAdminDate(row.created_at)}</td></tr>;
            })}</tbody></DataTable>
          </Panel>
          <Panel title="Partidos con snapshot de Rating"><DataTable label="Partidos del usuario"><thead><tr><th>Partido</th><th>Equipo</th><th>Lado</th><th>Asistencia</th><th>Fecha snapshot</th></tr></thead><tbody>{detail.matches.map((match, index) => { const row = record(match); return <tr key={`${String(row.match_id)}-${index}`}><td><Link href={`/admin/matches/${String(row.group_id)}/${encodeURIComponent(String(row.match_id))}`}>{String(row.match_id)}</Link></td><td><Link href={`/admin/teams/${String(row.group_id)}`}><Identifier value={String(row.group_id)} /></Link></td><td>{String(row.team_side ?? "-")}</td><td><StatusBadge>{row.attendance_confirmed ? "confirmada" : "no confirmada"}</StatusBadge></td><td>{formatAdminDate(row.created_at)}</td></tr>; })}</tbody></DataTable></Panel>
          <Panel title="Rewards recientes"><DataTable label="Rewards del usuario"><thead><tr><th>Reward</th><th>Tipo</th><th>Estado</th><th>Fecha</th></tr></thead><tbody>{detail.rewards.grants.map((grant, index) => { const row = record(grant); return <tr key={`${String(row.id)}-${index}`}><td>{String(row.reward_key ?? "-")}</td><td>{String(row.reward_kind ?? "-")}</td><td><StatusBadge>{String(row.state ?? "-")}</StatusBadge></td><td>{formatAdminDate(row.granted_at)}</td></tr>; })}</tbody></DataTable></Panel>
        </div>
        <aside>
          {canSuspend ? <section className={styles.detailBlock}><h2>Suspensión global</h2><p className={styles.helpText}>Reversible, con motivo, revisión esperada y sincronización explícita con Supabase Auth.</p><UserStateActions currentStatus={String(state.status ?? "active")} expectedRevision={Number(state.statusRevision) || 0} userId={userId} /></section> : null}
          {canManageRoles ? <section className={styles.detailBlock}><h2>Autoridad de plataforma</h2><p className={styles.helpText}>No guarda roles en metadata editable ni confunde admins de equipo con admins globales.</p><UserRoleActions currentRole={typeof state.platformRole === "string" ? state.platformRole : null} expectedRevision={Number(state.platformRoleRevision) || 0} userId={userId} /></section> : null}
        </aside>
      </div>
    </>
  );
}

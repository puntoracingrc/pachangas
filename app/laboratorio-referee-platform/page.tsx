import Link from "next/link";
import { OfficialProductShellV2 } from "../_components/official-product-shell-v2";
import { RefereePlatformClient } from "../_components/referee-platform-client";
import { GamePageHeader, MetricTile, SectionHeader, StatusChip } from "../_components/official-ui-v2-primitives";
import { PlatformShell } from "../admin/_components/platform-shell";
import { DataTable, Metric, MetricGrid, PageHeader, Panel, StatusBadge } from "../admin/_components/platform-ui";
import { PublicRefereeProfile } from "../arbitros/[slug]/public-referee-profile";
import { RefereeMarketplacePanel } from "../mercado/referee-marketplace-panel";
import { refereeMarketFixtures, refereePrivateFixture, refereePublicFixture } from "./referee-platform-fixtures";
import styles from "./referee-platform-lab.module.css";

type LabSurface = "admin" | "confirmed" | "live" | "market" | "private" | "proposed" | "public" | "review";

const surfaces: Array<{ id: LabSurface; label: string }> = [
  { id: "review", label: "Índice" },
  { id: "live", label: "R3 en directo" },
  { id: "market", label: "Mercado" },
  { id: "private", label: "Perfil privado" },
  { id: "public", label: "Perfil público" },
  { id: "proposed", label: "Propuesta" },
  { id: "confirmed", label: "Confirmada" },
  { id: "admin", label: "Admin" },
];

function value(input: string | string[] | undefined, fallback: string) {
  return Array.isArray(input) ? input[0] ?? fallback : input ?? fallback;
}

function ReviewIndex() {
  return <OfficialProductShellV2 active="perfil" context={{ detail: "Fixtures visuales aislados · sin escrituras", eyebrow: "Laboratorio R3", status: "Solo visual", title: "Árbitros · Official UI V2" }}>
    <main className={styles.reviewPage} data-mobile-tab="perfil">
      <GamePageHeader eyebrow="Integration Gate" summary="Cada enlace utiliza componentes reales con datos sintéticos aislados. El modo en directo conserva Supabase, RPC, RLS y Realtime." title="Revisión visual arbitral" />
      <section className={styles.reviewGrid}>{surfaces.filter((item) => item.id !== "review").map((item) => <Link href={`?surface=${item.id}`} key={item.id}><span>{item.label}</span><small>Desktop · portrait · mobile game landscape</small></Link>)}</section>
      <section className={styles.reviewMetrics}><MetricTile label="Autoridad" value="R3 intacta" /><MetricTile label="Presentación" value="Official UI V2" /><MetricTile label="Disciplina" value="NOT_AVAILABLE" /></section>
    </main>
  </OfficialProductShellV2>;
}

function MarketReview() {
  return <OfficialProductShellV2 active="mercado" context={{ detail: "Barcelona · Fútbol 7 · disponibilidad", eyebrow: "Mercado", status: "Solo visual", title: "Árbitros" }}>
    <main className={styles.surfacePage} data-mobile-tab="mercado">
      <nav className={styles.labNav} aria-label="Superficies del laboratorio"><Link href="?surface=review">Índice</Link><strong>Mercado de árbitros</strong></nav>
      <RefereeMarketplacePanel assignmentsEnabled canPropose context={{ groupId: "00000000-0000-0000-0000-00000000e301", matchId: "00000000-0000-0000-0000-00000000c301", title: "Atlètic Nord vs Raval United" }} marketplaceEnabled previewItems={refereeMarketFixtures} />
    </main>
  </OfficialProductShellV2>;
}

function AdminReview() {
  return <PlatformShell access={{ capabilities: ["overview.read", "referees.read", "referees.manage"], revision: 1, role: "platform_admin", userId: "00000000-0000-0000-0000-00000000ad31" }} environment="PREVIEW">
    <PageHeader eyebrow="Control Center · fixture visual" title="Árbitros" subtitle="Perfiles, relaciones con Clubs, asignaciones canónicas y salud operativa." />
    <MetricGrid><Metric label="Perfiles" value="3" /><Metric label="Activos" value="3" tone="good" /><Metric label="En Mercado" value="2" /><Metric label="Asignaciones activas" value="1" tone="warning" /></MetricGrid>
    <Panel title="Controles de plataforma"><div className={styles.adminControls}><section><SectionHeader eyebrow="Flags R3" title="Activación aislada" /><StatusChip tone="warning">Solo staging</StatusChip><p>Los seis flags nacen y terminan apagados.</p><button type="button">Guardar flags</button></section><section><SectionHeader eyebrow="Perfil" title="Laura Martínez" /><StatusChip tone="success">active</StatusChip><p>Verificación y reconstrucción de estadísticas desde asignaciones canónicas.</p><button type="button">Rebuild estadísticas</button></section></div></Panel>
    <Panel title="Registro arbitral"><DataTable label="Árbitros canónicos"><thead><tr><th>Árbitro</th><th>Estado</th><th>Modalidades</th><th>Zonas</th><th>Partidos</th></tr></thead><tbody>{refereeMarketFixtures.map((profile) => <tr key={String(profile.refereeProfileId)}><td><strong>{String(profile.displayName)}</strong><small>@{String(profile.slug)}</small></td><td><StatusBadge>{String(profile.operationalStatus)}</StatusBadge></td><td>{Array.isArray(profile.modalities) ? profile.modalities.length : 0}</td><td>{Array.isArray(profile.areas) ? profile.areas.length : 0}</td><td>{String((profile.statistics as { matchesCompleted?: unknown })?.matchesCompleted ?? 0)}</td></tr>)}</tbody></DataTable></Panel>
  </PlatformShell>;
}

export default async function RefereeLabPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const query = await searchParams;
  const requested = value(query.surface, "review") as LabSurface;
  const surface = surfaces.some((item) => item.id === requested) ? requested : "review";

  if (surface === "live") return <RefereePlatformClient laboratory />;
  if (surface === "market") return <MarketReview />;
  if (surface === "public") return <PublicRefereeProfile previewProfile={refereePublicFixture} slug="laura-martinez" />;
  if (surface === "admin") return <AdminReview />;
  if (surface === "private") return <RefereePlatformClient previewData={refereePrivateFixture("confirmed")} />;
  if (surface === "proposed") return <RefereePlatformClient focusSection="assignments" previewData={refereePrivateFixture("proposed")} />;
  if (surface === "confirmed") return <RefereePlatformClient focusSection="assignments" previewData={refereePrivateFixture("confirmed")} />;
  return <ReviewIndex />;
}

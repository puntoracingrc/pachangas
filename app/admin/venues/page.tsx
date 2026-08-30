import {
  DataTable,
  EmptyState,
  Metric,
  MetricGrid,
  PageHeader,
  Panel,
  StatusBadge,
} from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { getPlatformVenueOperations } from "../_lib/platform-data";

type Json = Record<string, unknown>;
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Json : {}; }
function array(value: unknown) { return Array.isArray(value) ? value.map(record) : []; }
function number(value: unknown) { const result = Number(value); return Number.isFinite(result) ? result : 0; }
function text(value: unknown) { return typeof value === "string" ? value : ""; }

export default async function PlatformVenueOperationsPage() {
  const session = await requirePlatformPage("clubs.read");
  const data = await getPlatformVenueOperations(session);
  const counts = record(data.counts);
  const health = record(data.health);
  const indexes = record(data.indexes);
  const realtime = record(data.realtime);
  const errors = record(data.errors);
  const candidates = array(data.partnerCandidates);
  const healthEntries = Object.entries(health).filter(([key]) => key !== "checkedAt");
  const issueCount = healthEntries.reduce((total, [, value]) => total + number(value), 0);

  return <>
    <PageHeader title="Venue Operations" subtitle="Read model global de instalaciones, disponibilidad, reservas, conflictos, privacidad y convergencia Realtime. Sin datos de pago ni contactos privados." />
    <MetricGrid>
      <Metric label="Venues" value={number(counts.venues)} />
      <Metric label="Pitches" value={number(counts.pitches)} />
      <Metric label="Solicitudes" value={number(counts.requests)} />
      <Metric label="Reservas confirmadas" value={number(counts.confirmedReservations)} tone="good" />
      <Metric label="Holds activos" value={number(counts.activeHolds)} tone={number(counts.activeHolds) ? "warning" : "neutral"} />
      <Metric label="Conflictos health" value={issueCount} tone={issueCount ? "warning" : "good"} />
    </MetricGrid>

    <Panel title="Salud operativa">
      {healthEntries.length ? <DataTable label="Health de Venue Operations"><thead><tr><th>Control</th><th>Resultado</th><th>Estado</th></tr></thead><tbody>{healthEntries.map(([key, value]) => <tr key={key}><td>{key}</td><td>{number(value)}</td><td><StatusBadge>{number(value) ? "REVIEW" : "CLEAR"}</StatusBadge></td></tr>)}</tbody></DataTable> : <EmptyState>Sin controles de salud disponibles.</EmptyState>}
    </Panel>

    <MetricGrid>
      <Metric label="Índices protegidos" value={number(indexes.protectedIndexCount)} />
      <Metric label="Invalidaciones" value={number(counts.invalidations)} />
      <Metric label="Secuencia Realtime" value={number(realtime.latestInvalidationSequence)} />
      <Metric label="Eventos" value={number(counts.events)} />
      <Metric label="Bindings" value={number(counts.bindings)} />
      <Metric label="Cancelaciones" value={number(counts.cancellations)} />
    </MetricGrid>

    <Panel title="Infraestructura y errores">
      <DataTable label="Estado técnico"><thead><tr><th>Área</th><th>Estado</th><th>Detalle</th></tr></thead><tbody>
        <tr><td>Índices</td><td><StatusBadge>{text(indexes.status)}</StatusBadge></td><td>{number(indexes.protectedIndexCount)} índices gestionados por migración</td></tr>
        <tr><td>Realtime</td><td><StatusBadge>CANONICAL_REFETCH</StatusBadge></td><td>{text(realtime.transport)} · {text(realtime.publication)}</td></tr>
        <tr><td>Errores de comando</td><td><StatusBadge>{text(errors.status)}</StatusBadge></td><td>No se presenta un cero ficticio; los fallos se observan mediante health y logs operativos.</td></tr>
      </tbody></DataTable>
    </Panel>

    <Panel title="Clubs candidatos a partnership">
      {candidates.length ? <DataTable label="Candidatos"><thead><tr><th>Club</th><th>Municipio</th><th>Venues públicos</th><th>Reservas confirmadas</th></tr></thead><tbody>{candidates.map((item) => <tr key={text(item.clubId)}><td>{text(item.clubName)}</td><td>{text(item.municipality) || "Sin municipio"}</td><td>{number(item.publicVenues)}</td><td>{number(item.confirmedReservations)}</td></tr>)}</tbody></DataTable> : <EmptyState>No hay candidatos derivados del uso canónico actual.</EmptyState>}
    </Panel>
  </>;
}

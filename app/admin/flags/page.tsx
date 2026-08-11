import { FlagChangeControl } from "../_components/flag-change-control";
import { DataTable, PageHeader, Panel, StatusBadge } from "../_components/platform-ui";
import { requirePlatformPage } from "../_lib/platform-auth";
import { hasPlatformCapability } from "../_lib/platform-contract";
import { getPlatformFlags } from "../_lib/platform-data";
import styles from "../platform-admin.module.css";

export default async function PlatformFlagsPage() {
  const session = await requirePlatformPage("flags.read");
  const flags = await getPlatformFlags(session);
  const canWrite = hasPlatformCapability(session.access, "flags.write");
  return <><PageHeader title="Feature flags" subtitle="Producto, laboratorio y funciones apagadas se muestran como estados distintos. Los secrets no aparecen aquí." />
    <Panel><DataTable label="Feature flags"><thead><tr><th>Función</th><th>Estado</th><th>Valor</th><th>Fuente</th><th>Revisión</th><th>Acción</th></tr></thead><tbody>{flags.map((flag) => <tr key={String(flag.key)}><td><strong>{String(flag.label ?? flag.key)}</strong><small>{String(flag.key)}</small></td><td><StatusBadge tone={flag.state === "PRODUCT" ? "good" : flag.state === "LAB" ? "info" : "muted"}>{String(flag.state)}</StatusBadge></td><td>{flag.enabled ? "Activo" : "Inactivo"}</td><td><code className={styles.identifier}>{String(flag.source ?? "-")}</code></td><td>{String(flag.revision ?? 0)}</td><td>{canWrite && flag.mutable ? <FlagChangeControl enabled={Boolean(flag.enabled)} flagKey={String(flag.key)} revision={Number(flag.revision) || 0} /> : <span className={styles.muted}>Solo lectura</span>}</td></tr>)}</tbody></DataTable></Panel>
  </>;
}

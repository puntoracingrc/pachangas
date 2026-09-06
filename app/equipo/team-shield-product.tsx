"use client";

import { useEffect, useRef, useState } from "react";
import { supabase } from "../supabaseClient";
import { teamShieldDesignEquals, type TeamShieldConfig, type TeamShieldCosmeticSlot } from "../team-shield-contract";
import { normalizeTeamShieldSnapshot, type TeamShieldSnapshot } from "../team-identity-contract";
import { userFacingError } from "../user-facing-error";
import styles from "./team-shield-product.module.css";
import { TeamShieldCosmeticsEditor } from "./team-shield-editor";

type EditorState = { snapshot: TeamShieldSnapshot; draft: TeamShieldConfig };

export function TeamShieldProduct({ groupId }: { groupId: string }) {
  const [state, setState] = useState<EditorState | null>(null);
  const [category, setCategory] = useState<TeamShieldCosmeticSlot>("shape");
  const [error, setError] = useState(false);
  const [retry, setRetry] = useState(0);
  const [busy, setBusy] = useState(false);
  const [online, setOnline] = useState(true);
  const [message, setMessage] = useState("");
  const generation = useRef(0);
  const saving = useRef(false);
  const operations = useRef(new Map<string, string>());

  useEffect(() => {
    const client = supabase;
    let disposed = false;
    const invalidateRequests = () => { generation.current++; };
    async function load() {
      if (disposed || saving.current) return;
      const request = ++generation.current;
      try {
        if (!client) throw new Error("Unavailable");
        const result = await client.rpc("get_pachanga_team_shield_snapshot_v1", { target_group_id: groupId });
        if (disposed || request !== generation.current) return;
        const snapshot = normalizeTeamShieldSnapshot(result.data);
        if (result.error || !snapshot || snapshot.group.groupId !== groupId) throw new Error("Unavailable");
        setState(current => ({ snapshot, draft: current && current.snapshot.group.groupId === groupId
          && !teamShieldDesignEquals(current.draft, current.snapshot.config) ? current.draft : snapshot.config }));
        setError(false);
      } catch {
        if (!disposed && request === generation.current) { setState(null); setError(true); }
      }
    }
    const connection = () => { setOnline(navigator.onLine); if (navigator.onLine) void load(); };
    connection();
    const channel = client?.channel(`shield-editor-${groupId}`).on("postgres_changes", {
      event: "*", schema: "public", table: "pachanga_team_shield_state", filter: `group_id=eq.${groupId}`,
    }, load).subscribe();
    const auth = client?.auth.onAuthStateChange(() => queueMicrotask(() => { if (!disposed) void load(); }));
    window.addEventListener("focus", load);
    window.addEventListener("online", connection);
    window.addEventListener("offline", connection);
    return () => {
      disposed = true; invalidateRequests();
      if (channel) void client?.removeChannel(channel);
      auth?.data.subscription.unsubscribe();
      window.removeEventListener("focus", load); window.removeEventListener("online", connection); window.removeEventListener("offline", connection);
    };
  }, [groupId, retry]);

  async function save() {
    const client = supabase;
    if (!client || !state || state.snapshot.group.groupId !== groupId || !state.snapshot.canManage
      || !state.snapshot.teamCosmeticsEnabled || saving.current || !navigator.onLine) return;
    const fingerprint = `${groupId}:${state.snapshot.revision}:${JSON.stringify(state.draft)}`;
    const operationId = operations.current.get(fingerprint) ?? crypto.randomUUID();
    operations.current.set(fingerprint, operationId);
    saving.current = true; setBusy(true); setMessage("");
    const request = ++generation.current;
    try {
      const result = await client.rpc("save_pachanga_team_shield_loadout_v1", {
        target_group_id: groupId, target_config: state.draft, expected_revision: state.snapshot.revision,
        operation_id: operationId, client_metadata: { surface: "team-shield-editor" },
      });
      if (request !== generation.current) return;
      if (result.error) {
        setMessage(result.error.code === "PT409" ? "Otro administrador ha actualizado el escudo. Revisa los cambios antes de volver a guardar." : userFacingError(result.error));
        setRetry(value => value + 1);
        return;
      }
      const snapshot = normalizeTeamShieldSnapshot(result.data);
      if (!snapshot || snapshot.group.groupId !== groupId) {
        setMessage("No hemos podido confirmar el guardado. Comprueba el escudo antes de volver a intentarlo.");
        setRetry(value => value + 1);
        return;
      }
      operations.current.delete(fingerprint);
      setState({ snapshot, draft: snapshot.config });
      setMessage("Escudo del equipo guardado.");
    } catch {
      if (request === generation.current) setMessage("No hemos podido confirmar el guardado. Puedes volver a intentarlo.");
    } finally { saving.current = false; if (request === generation.current) setBusy(false); }
  }

  if (error) return <section aria-label="Editor del escudo"><p role="status">No hemos podido cargar el escudo del equipo.</p><button type="button" onClick={() => setRetry(value => value + 1)}>Reintentar</button></section>;
  if (!state || state.snapshot.group.groupId !== groupId) return <p role="status">Cargando el escudo del equipo…</p>;
  const { snapshot, draft } = state;
  return <section className={styles.editor} aria-label="Editor del escudo del equipo">
    <header className={styles.heading}><span>Identidad del equipo</span><h1>Escudo del equipo</h1>
    <p>{snapshot.canManage ? "Prueba formas, colores y complementos. Guarda cuando quieras publicar el diseño para todo el equipo." : "Puedes probar formas, colores y complementos. Tu vista previa es personal; solo los administradores pueden guardar el escudo del equipo."}</p></header>
    {!snapshot.teamCosmeticsEnabled ? <p role="status">El guardado de escudos todavía no está disponible.</p> : null}
    {message ? <p role="status">{message}</p> : null}
    <TeamShieldCosmeticsEditor activeCategory={category} busy={busy} canSave={snapshot.canManage && snapshot.teamCosmeticsEnabled}
      catalog={snapshot.catalog} config={draft} dirty={!teamShieldDesignEquals(draft, snapshot.config)} isOnline={online}
      onCategoryChange={setCategory} onChange={config => { if (!saving.current) setState({ snapshot, draft: config }); }}
      onReset={() => setState({ snapshot, draft: snapshot.config })} onSave={() => void save()} revision={snapshot.revision} />
  </section>;
}

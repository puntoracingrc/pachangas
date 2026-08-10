"use client";

import { useState } from "react";
import { conductCategoryLabels, conductClientMetadata } from "./conduct-contract";
import styles from "./conduct.module.css";
import { supabase } from "./supabaseClient";

type ConductReportContext = {
  contextId: string;
  contextKind: string;
  expectedRevision: number;
  reporterGroupId: string;
  targetGroupId: string;
  targetProfileId: string;
};

const categories = Object.entries(conductCategoryLabels);

export function ConductReportForm({ context }: { context: ConductReportContext }) {
  const [category, setCategory] = useState(categories[0][0]);
  const [description, setDescription] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const complete = Boolean(
    context.targetProfileId && context.reporterGroupId && context.targetGroupId
    && context.contextId && context.expectedRevision > 0,
  );

  async function submit() {
    if (!supabase || !complete || busy) return;
    setBusy(true);
    setMessage("");
    const result = await supabase.rpc("submit_pachanga_conduct_report_v1", {
      category,
      client_metadata: conductClientMetadata("contextual-conduct-report"),
      context_id: context.contextId,
      context_kind: context.contextKind,
      description: description.trim(),
      expected_revision: context.expectedRevision,
      operation_id: crypto.randomUUID(),
      reporter_group_id: context.reporterGroupId,
      target_group_id: context.targetGroupId,
      target_profile_id: context.targetProfileId,
    });
    setMessage(result.error ? result.error.message : "Reporte recibido para revisión privada.");
    if (!result.error) setDescription("");
    setBusy(false);
  }

  if (!complete) {
    return <p className={styles.message}>El reporte necesita abrirse desde un partido o reto válido.</p>;
  }

  return (
    <section className={styles.panel}>
      <h2>Reporte privado</h2>
      <form className={styles.form} onSubmit={(event) => { event.preventDefault(); void submit(); }}>
        <label>
          Categoría
          <select value={category} onChange={(event) => setCategory(event.target.value)}>
            {categories.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
        <label>
          Contexto adicional (opcional)
          <textarea maxLength={500} value={description} onChange={(event) => setDescription(event.target.value)} />
        </label>
        <button type="submit" disabled={busy}>{busy ? "Enviando..." : "Enviar a moderación"}</button>
      </form>
      {message ? <p className={styles.message} role="status">{message}</p> : null}
    </section>
  );
}

"use client";

import { useEffect, useState } from "react";

import { RATING_COMPARISON_OPTIONS, type RatingComparison } from "../rating-system-v2";
import { supabase } from "../supabaseClient";

type GuestRatingContext = {
  confirmedRevision: number | string;
  expiresAt: string;
  groupName: string;
  matchDate?: string | null;
  matchTitle: string;
};

function guestClientMetadata() {
  const key = "pachanga-rating-session-v2";
  let sessionId = sessionStorage.getItem(key);
  if (!sessionId) {
    sessionId = crypto.randomUUID();
    sessionStorage.setItem(key, sessionId);
  }
  return { sessionId, surface: "guest-team-rating" };
}

export default function GuestTeamRatingPage() {
  const [token, setToken] = useState("");
  const [selected, setSelected] = useState<RatingComparison>("PARECIDO");
  const [saving, setSaving] = useState(false);
  const [complete, setComplete] = useState(false);
  const [message, setMessage] = useState("");
  const [context, setContext] = useState<GuestRatingContext | null>(null);
  const [contextLoading, setContextLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    const nextToken = new URLSearchParams(window.location.search).get("t")?.trim() ?? "";
    async function loadContext() {
      await Promise.resolve();
      if (cancelled) return;
      setToken(nextToken);
      if (!supabase || !nextToken) {
        setContextLoading(false);
        return;
      }
      const result = await supabase.rpc("get_pachanga_guest_rating_token_context_v2", { claim_token: nextToken });
      if (cancelled) return;
      setContextLoading(false);
      if (result.error) {
        setMessage("El enlace no es válido, ha caducado o ya fue utilizado.");
        return;
      }
      setContext(result.data as GuestRatingContext);
    }
    void loadContext();
    return () => {
      cancelled = true;
    };
  }, []);

  async function reloadContext() {
    if (!supabase || !token) return null;
    const result = await supabase.rpc("get_pachanga_guest_rating_token_context_v2", { claim_token: token });
    if (result.error) return null;
    const nextContext = result.data as GuestRatingContext;
    setContext(nextContext);
    return nextContext;
  }

  async function submit() {
    if (!supabase || !token || !context || saving || complete) return;
    setSaving(true);
    setMessage("");
    const operationStorageKey = `pachanga-guest-rating-operation:${token.slice(-16)}`;
    let operationId = sessionStorage.getItem(operationStorageKey);
    if (!operationId) {
      operationId = crypto.randomUUID();
      sessionStorage.setItem(operationStorageKey, operationId);
    }
    const result = await supabase.rpc("record_pachanga_guest_team_rating_token_v2", {
      claim_token: token,
      client_metadata: guestClientMetadata(),
      comparison: selected,
      expected_revision: Number(context.confirmedRevision),
      operation_id: operationId,
    });
    setSaving(false);
    if (result.error) {
      if (result.error.message.toLowerCase().includes("revision")) {
        const refreshed = await reloadContext();
        if (refreshed) {
          setMessage("El partido cambió en otro dispositivo. Ya hemos recargado el estado; vuelve a guardar.");
          return;
        }
      }
      setMessage("El enlace no es válido, ha caducado o ya fue utilizado.");
      return;
    }
    sessionStorage.removeItem(operationStorageKey);
    setComplete(true);
    setMessage("Valoración guardada. Gracias por responder con sinceridad.");
  }

  return (
    <main className="guest-team-rating-page">
      <section>
        <header>
          <span>Pachangas IQ</span>
          <h1>Valora globalmente al equipo</h1>
          <p>
            {context ? `${context.groupName} · ${context.matchTitle}. ` : ""}
            Compara su nivel con el que tuvo tu participación en este partido. No estás valorando a jugadores concretos.
          </p>
        </header>
        {!complete ? (
          <>
            <div className="guest-team-rating-options">
              {RATING_COMPARISON_OPTIONS.map((option) => (
                <button
                  aria-pressed={selected === option.id}
                  className={selected === option.id ? "selected" : ""}
                  key={option.id}
                  onClick={() => setSelected(option.id)}
                  type="button"
                >
                  {option.label}
                </button>
              ))}
            </div>
            <button className="guest-team-rating-submit" disabled={!token || !context || contextLoading || saving} onClick={() => void submit()} type="button">
              {saving ? "Guardando..." : "Guardar valoración"}
            </button>
          </>
        ) : null}
        {!token ? <p role="alert">Falta el enlace seguro de valoración.</p> : null}
        {token && contextLoading ? <p>Comprobando enlace...</p> : null}
        {message ? <p role="status">{message}</p> : null}
      </section>
    </main>
  );
}

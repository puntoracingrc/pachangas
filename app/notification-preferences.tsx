"use client";

import { useCallback, useEffect, useState } from "react";
import { supabase } from "./supabaseClient";

type NotificationPreference = {
  category: string;
  containsMandatory: boolean;
  description: string;
  emailAvailable: boolean;
  emailEnabled: boolean;
  inAppEnabled: boolean;
  label: string;
  pushAvailable: boolean;
  pushEnabled: boolean;
  revision: number;
  serverSequence: number;
};

function normalizePreferences(value: unknown): NotificationPreference[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const row = item as Record<string, unknown>;
    if (typeof row.category !== "string" || typeof row.label !== "string") return [];
    return [{
      category: row.category,
      containsMandatory: Boolean(row.containsMandatory),
      description: typeof row.description === "string" ? row.description : "",
      emailAvailable: Boolean(row.emailAvailable),
      emailEnabled: Boolean(row.emailEnabled),
      inAppEnabled: row.inAppEnabled !== false,
      label: row.label,
      pushAvailable: Boolean(row.pushAvailable),
      pushEnabled: Boolean(row.pushEnabled),
      revision: Math.max(0, Math.floor(Number(row.revision) || 0)),
      serverSequence: Math.max(0, Math.floor(Number(row.serverSequence) || 0)),
    }];
  });
}

export function NotificationPreferences() {
  const [preferences, setPreferences] = useState<NotificationPreference[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyCategory, setBusyCategory] = useState<string | null>(null);
  const [message, setMessage] = useState("");

  const loadPreferences = useCallback(async () => {
    if (!supabase) {
      setLoading(false);
      return;
    }
    const session = await supabase.auth.getSession();
    if (!session.data.session?.user) {
      setPreferences([]);
      setMessage("Inicia sesión para configurar tus avisos.");
      setLoading(false);
      return;
    }
    const result = await supabase.rpc("get_pachanga_notification_preferences_v1");
    setLoading(false);
    if (result.error) {
      setMessage(result.error.message);
      return;
    }
    setMessage("");
    setPreferences(normalizePreferences(result.data));
  }, []);

  useEffect(() => {
    const client = supabase;
    const initialLoad = window.setTimeout(() => void loadPreferences(), 0);
    if (!client) return () => window.clearTimeout(initialLoad);
    const { data } = client.auth.onAuthStateChange(() => {
      window.setTimeout(() => void loadPreferences(), 0);
    });
    return () => {
      window.clearTimeout(initialLoad);
      data.subscription.unsubscribe();
    };
  }, [loadPreferences]);

  async function savePreference(
    preference: NotificationPreference,
    changes: Partial<Pick<NotificationPreference, "emailEnabled" | "inAppEnabled" | "pushEnabled">>,
  ) {
    if (!supabase || busyCategory) return;
    if (!navigator.onLine) {
      setMessage("Sin conexión. No se ha cambiado ninguna preferencia.");
      return;
    }
    setBusyCategory(preference.category);
    setMessage("");
    const result = await supabase.rpc("update_pachanga_notification_preferences_v1", {
      expected_revision: preference.revision,
      next_email_enabled: changes.emailEnabled ?? preference.emailEnabled,
      next_in_app_enabled: changes.inAppEnabled ?? preference.inAppEnabled,
      next_push_enabled: changes.pushEnabled ?? preference.pushEnabled,
      operation_id: crypto.randomUUID(),
      target_category: preference.category,
    });
    if (result.error) setMessage(result.error.message);
    await loadPreferences();
    setBusyCategory(null);
  }

  return (
    <section className="notification-preferences" aria-labelledby="notification-preferences-title">
      <header>
        <div>
          <span>Perfil</span>
          <h1 id="notification-preferences-title">Avisos y notificaciones</h1>
        </div>
        <p>Elige qué avisos no críticos quieres ver. Las acciones necesarias para partidos, seguridad y administración siempre permanecen en la app.</p>
      </header>

      {message ? <p className="notification-preferences-message" role="status">{message}</p> : null}
      {loading ? <p className="notification-preferences-message">Cargando preferencias...</p> : null}

      <div className="notification-preference-list">
        {preferences.map((preference) => {
          const busy = busyCategory === preference.category;
          return (
            <article key={preference.category}>
              <div className="notification-preference-copy">
                <strong>{preference.label}</strong>
                <p>{preference.description}</p>
                {preference.containsMandatory ? <small>Incluye avisos críticos que no se pueden ocultar.</small> : null}
              </div>
              <div className="notification-channel-toggles" aria-label={`Canales para ${preference.label}`}>
                <label>
                  <input
                    type="checkbox"
                    checked={preference.inAppEnabled}
                    disabled={busy}
                    onChange={(event) => void savePreference(preference, { inAppEnabled: event.target.checked })}
                  />
                  <span>En la app</span>
                </label>
                <label title={preference.pushAvailable ? "Notificaciones push" : "Disponible en una fase posterior"}>
                  <input
                    type="checkbox"
                    checked={preference.pushEnabled}
                    disabled={busy || !preference.pushAvailable}
                    onChange={(event) => void savePreference(preference, { pushEnabled: event.target.checked })}
                  />
                  <span>Push</span><small>{preference.pushAvailable ? "" : "Próximamente"}</small>
                </label>
                <label title={preference.emailAvailable ? "Avisos por correo" : "Disponible en una fase posterior"}>
                  <input
                    type="checkbox"
                    checked={preference.emailEnabled}
                    disabled={busy || !preference.emailAvailable}
                    onChange={(event) => void savePreference(preference, { emailEnabled: event.target.checked })}
                  />
                  <span>Correo</span><small>{preference.emailAvailable ? "" : "Próximamente"}</small>
                </label>
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
}

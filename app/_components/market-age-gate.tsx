"use client";

import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";
import { supabase } from "../supabaseClient";
import { OfficialProductShellV2 } from "./official-product-shell-v2";
import type { MarketAgeAccess } from "../market-age-contract";
import styles from "../perfil/profile.module.css";

export function MarketAgeGate({ children }: { children: ReactNode }) {
  const [access, setAccess] = useState<MarketAgeAccess | "loading" | "error" | "signed-out">("loading");
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    const client = supabase;
    if (!client) return;
    let active = true;
    let request = 0;
    let actor = "";
    async function check() {
      const currentRequest = ++request;
      try {
        const { data } = await client!.auth.getSession();
        if (!active || currentRequest !== request) return;
        const id = data.session?.user.id ?? "";
        if (id !== actor) { actor = id; setAccess("loading"); }
        if (!id) { setAccess("signed-out"); return; }
        const response = await client!.rpc("get_my_pachanga_market_age_access_v1");
        if (!active || currentRequest !== request) return;
        const value = response.data?.access;
        setAccess(!response.error && ["adult", "minor", "missing"].includes(value) ? value : "error");
      } catch {
        if (active && currentRequest === request) setAccess("error");
      }
    }
    void check();
    const { data } = client.auth.onAuthStateChange(() => { queueMicrotask(() => { if (active) void check(); }); });
    const refresh = () => void check();
    window.addEventListener("focus", refresh);
    window.addEventListener("online", refresh);
    return () => { active = false; data.subscription.unsubscribe(); window.removeEventListener("focus", refresh); window.removeEventListener("online", refresh); };
  }, [attempt]);

  if (access === "adult") return children;
  return <OfficialProductShellV2 active="perfil" context={{ title: "Tu espacio", type: "profile", role: "Jugador" }}>
    <section className={styles.state} aria-live="polite">
      <h1>{access === "minor" ? "Mercado y retos, a partir de los 18 años" : access === "missing" ? "Completa tu fecha de nacimiento" : access === "signed-out" ? "Inicia sesión para continuar" : access === "error" || !supabase ? "No pudimos comprobar el acceso" : "Comprobando acceso…"}</h1>
      {access === "minor" ? <p>Puedes crear un equipo y jugar con sus miembros. Un administrador adulto puede organizar encuentros con otros equipos y tú puedes participar con el tuyo. Tu perfil no aparece en el mercado.</p> : access === "missing" ? <p>Necesitamos este dato privado para saber si puedes acceder al mercado y a los retos.</p> : null}
      {access === "missing" ? <Link href="/?social=profile">Completar mi perfil</Link> : <Link href="/">Volver a Inicio</Link>}
      {access === "error" || !supabase ? <button type="button" onClick={() => setAttempt(value => value + 1)}>Reintentar</button> : null}
    </section>
  </OfficialProductShellV2>;
}

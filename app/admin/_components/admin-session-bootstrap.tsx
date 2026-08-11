"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { supabase } from "../../supabaseClient";
import styles from "../platform-admin.module.css";

type BootstrapState = "checking" | "missing-session" | "not-authorized" | "unavailable";

export function AdminSessionBootstrap() {
  const [state, setState] = useState<BootstrapState>("checking");

  useEffect(() => {
    let active = true;
    async function exchangeSession() {
      if (!supabase) {
        if (active) setState("unavailable");
        return;
      }
      const sessionResult = await supabase.auth.getSession();
      const token = sessionResult.data.session?.access_token;
      if (!token) {
        if (active) setState("missing-session");
        return;
      }
      try {
        const response = await fetch("/api/platform-admin/session", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "X-Pachangas-Platform-Admin": "1",
          },
        });
        if (!active) return;
        if (!response.ok) {
          setState(response.status === 403 ? "not-authorized" : "unavailable");
          return;
        }
        window.location.replace(`${window.location.pathname}${window.location.search}`);
      } catch {
        if (active) setState("unavailable");
      }
    }
    void exchangeSession();
    return () => { active = false; };
  }, []);

  const content = {
    checking: ["Comprobando acceso", "Validando la sesión de plataforma..."],
    "missing-session": ["Sesión necesaria", "Inicia sesión en Pachangas IQ y vuelve al Control Center."],
    "not-authorized": ["Acceso no disponible", "Esta cuenta no tiene un rol de administración de plataforma."],
    unavailable: ["Control Center no disponible", "No se ha podido validar el acceso. Inténtalo de nuevo en unos instantes."],
  }[state];

  return (
    <main className={styles.accessPage}>
      <section className={styles.accessPanel} aria-live="polite">
        <Image src="/icon-monochrome.svg" alt="" width={44} height={44} priority />
        <p className={styles.eyebrow}>Pachangas IQ</p>
        <h1>{content[0]}</h1>
        <p>{content[1]}</p>
        {state !== "checking" ? <Link className={styles.primaryAction} href="/">Volver a Pachangas IQ</Link> : null}
      </section>
    </main>
  );
}

"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../supabaseClient";

const googleAuthNonceKey = "pachanga-google-auth-nonce";
const googleAuthReturnKey = "pachanga-google-auth-return";

export default function GoogleAuthPage() {
  const [status, setStatus] = useState("Conectando con Google...");

  useEffect(() => {
    async function finishGoogleLogin() {
      if (!supabase) {
        setStatus("Supabase no está configurado.");
        return;
      }

      const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
      const error = hash.get("error_description") || hash.get("error");
      if (error) {
        setStatus(error);
        return;
      }

      const token = hash.get("id_token");
      const nonce = localStorage.getItem(googleAuthNonceKey) ?? undefined;
      if (!token || !nonce) {
        setStatus("No se pudo completar el login con Google.");
        return;
      }

      const result = await supabase.auth.signInWithIdToken({
        provider: "google",
        token,
        nonce,
      });

      if (result.error) {
        setStatus(result.error.message);
        return;
      }

      localStorage.removeItem(googleAuthNonceKey);
      const returnTo = localStorage.getItem(googleAuthReturnKey) || "/";
      localStorage.removeItem(googleAuthReturnKey);
      window.location.replace(returnTo);
    }

    void finishGoogleLogin();
  }, []);

  return (
    <main className="auth-callback-page">
      <section>
        <p className="eyebrow">Pachangas IQ</p>
        <h1>{status}</h1>
      </section>
    </main>
  );
}

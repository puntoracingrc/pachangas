"use client";

import { useEffect, useState } from "react";
import { supabase } from "../supabaseClient";

type PlatformAccessResponse = {
  access?: {
    role?: string;
  };
};

export function useCanonicalPlatformOwner() {
  const [confirmedOwner, setConfirmedOwner] = useState(false);

  useEffect(() => {
    let active = true;

    async function readCanonicalAccess() {
      if (!supabase) {
        if (active) setConfirmedOwner(false);
        return;
      }

      const sessionResult = await supabase.auth.getSession();
      const token = sessionResult.data.session?.access_token;
      if (!token) {
        if (active) setConfirmedOwner(false);
        return;
      }

      try {
        const response = await fetch("/api/platform-admin/session", {
          cache: "no-store",
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "X-Pachangas-Platform-Admin": "1",
          },
        });
        const body = response.ok ? await response.json() as PlatformAccessResponse : null;
        if (active) setConfirmedOwner(body?.access?.role === "platform_owner");
      } catch {
        if (active) setConfirmedOwner(false);
      }
    }

    void readCanonicalAccess();
    const subscription = supabase?.auth.onAuthStateChange(() => {
      window.setTimeout(() => void readCanonicalAccess(), 0);
    });

    return () => {
      active = false;
      subscription?.data.subscription.unsubscribe();
    };
  }, []);

  return confirmedOwner;
}

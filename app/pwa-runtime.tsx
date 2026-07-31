"use client";

import { useEffect } from "react";

type NavigatorWithStandalone = Navigator & {
  standalone?: boolean;
};

function canRegisterServiceWorker() {
  if (!("serviceWorker" in navigator)) return false;

  const { hostname, protocol } = window.location;
  const isLocalhost = hostname === "localhost" || hostname === "127.0.0.1";
  const isSecureOrigin = protocol === "https:" || isLocalhost;

  if (!isSecureOrigin) return false;
  if (process.env.NODE_ENV !== "production" && isLocalhost) return false;

  return true;
}

function isInstalledDisplayMode() {
  const navigatorWithStandalone = navigator as NavigatorWithStandalone;

  return (
    window.matchMedia("(display-mode: standalone)").matches ||
    window.matchMedia("(display-mode: fullscreen)").matches ||
    window.matchMedia("(display-mode: minimal-ui)").matches ||
    Boolean(navigatorWithStandalone.standalone)
  );
}

export function PwaRuntime() {
  useEffect(() => {
    const updateDisplayMode = () => {
      document.documentElement.dataset.displayMode = isInstalledDisplayMode() ? "standalone" : "browser";
    };
    const displayModeQueries = [
      window.matchMedia("(display-mode: standalone)"),
      window.matchMedia("(display-mode: fullscreen)"),
      window.matchMedia("(display-mode: minimal-ui)"),
    ];

    updateDisplayMode();
    displayModeQueries.forEach((query) => query.addEventListener("change", updateDisplayMode));
    window.addEventListener("appinstalled", updateDisplayMode);

    return () => {
      displayModeQueries.forEach((query) => query.removeEventListener("change", updateDisplayMode));
      window.removeEventListener("appinstalled", updateDisplayMode);
    };
  }, []);

  useEffect(() => {
    if (!canRegisterServiceWorker()) return;

    const registerServiceWorker = () => {
      void navigator.serviceWorker.register("/sw.js", { scope: "/" }).catch(() => undefined);
    };

    if (document.readyState === "complete") {
      registerServiceWorker();
      return;
    }

    window.addEventListener("load", registerServiceWorker, { once: true });
    return () => window.removeEventListener("load", registerServiceWorker);
  }, []);

  return null;
}

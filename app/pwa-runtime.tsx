"use client";

import { useEffect } from "react";
import { adaptiveWindowClass } from "./adaptive-window";

type NavigatorWithStandalone = Navigator & {
  standalone?: boolean;
};

type StorageManagerWithEstimate = StorageManager & {
  estimate?: () => Promise<StorageEstimate>;
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

function setDatasetFlag(name: string, value: boolean) {
  document.documentElement.dataset[name] = value ? "yes" : "no";
}

function setViewportVariables() {
  const viewport = window.visualViewport;
  const height = Math.round(viewport?.height ?? window.innerHeight);
  const width = Math.round(viewport?.width ?? window.innerWidth);
  const sizeClass = adaptiveWindowClass(width, height);

  if (height > 0) {
    document.documentElement.style.setProperty("--app-viewport-height", `${height}px`);
  }

  if (width > 0) {
    document.documentElement.style.setProperty("--app-viewport-width", `${width}px`);
  }

  document.documentElement.dataset.windowWidthClass = sizeClass.width;
  document.documentElement.dataset.windowHeightClass = sizeClass.height;
  document.documentElement.dataset.windowSizeClass = `${sizeClass.width}-${sizeClass.height}`;
}

function updateOrientationDataset() {
  document.documentElement.dataset.appOrientation = window.matchMedia("(orientation: landscape)").matches ? "landscape" : "portrait";
}

export function PwaRuntime() {
  useEffect(() => {
    let frame = 0;
    const updateViewport = () => {
      window.cancelAnimationFrame(frame);
      frame = window.requestAnimationFrame(() => {
        setViewportVariables();
        updateOrientationDataset();
      });
    };

    updateViewport();
    window.addEventListener("resize", updateViewport);
    window.addEventListener("orientationchange", updateViewport);
    window.visualViewport?.addEventListener("resize", updateViewport);
    window.visualViewport?.addEventListener("scroll", updateViewport);

    return () => {
      window.cancelAnimationFrame(frame);
      window.removeEventListener("resize", updateViewport);
      window.removeEventListener("orientationchange", updateViewport);
      window.visualViewport?.removeEventListener("resize", updateViewport);
      window.visualViewport?.removeEventListener("scroll", updateViewport);
    };
  }, []);

  useEffect(() => {
    setDatasetFlag("supportsServiceWorker", "serviceWorker" in navigator);
    setDatasetFlag("supportsShare", typeof navigator.share === "function");
    setDatasetFlag("supportsClipboard", Boolean(navigator.clipboard?.writeText));
    setDatasetFlag("supportsCamera", Boolean(navigator.mediaDevices?.getUserMedia));
    setDatasetFlag("supportsStorageEstimate", Boolean((navigator.storage as StorageManagerWithEstimate | undefined)?.estimate));

    const storage = navigator.storage as StorageManagerWithEstimate | undefined;
    void storage?.estimate?.().then((estimate) => {
      const quota = estimate.quota ?? 0;
      const usage = estimate.usage ?? 0;
      if (quota <= 0) return;

      const ratio = usage / quota;
      document.documentElement.dataset.storagePressure = ratio > 0.85 ? "high" : ratio > 0.65 ? "medium" : "low";
    }).catch(() => undefined);
  }, []);

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

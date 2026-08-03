"use client";

import { useEffect, useRef, useState } from "react";
import { adaptiveWindowClass } from "./adaptive-window";
import {
  flushQueuedClientTelemetry,
  pausePwaWrites,
  pwaBridgeSnapshot,
  refreshPwaClientPolicy,
  setPwaOnlineState,
  setPwaServiceWorkerVersion,
  subscribePwaBridge,
  waitForPwaWrites,
} from "./pwa-client-bridge";
import {
  activateWaitingServiceWorker,
  reloadOnceAfterControllerChange,
  serviceWorkerVersion,
} from "./pwa-service-worker-update";

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

function setDatasetFlag(name: string, value: boolean) {
  document.documentElement.dataset[name] = value ? "yes" : "no";
}

function setViewportVariables() {
  const viewport = window.visualViewport;
  const height = Math.round(viewport?.height ?? window.innerHeight);
  const width = Math.round(viewport?.width ?? window.innerWidth);
  const sizeClass = adaptiveWindowClass(width, height);

  if (height > 0) document.documentElement.style.setProperty("--app-viewport-height", `${height}px`);
  if (width > 0) document.documentElement.style.setProperty("--app-viewport-width", `${width}px`);

  document.documentElement.dataset.windowWidthClass = sizeClass.width;
  document.documentElement.dataset.windowHeightClass = sizeClass.height;
  document.documentElement.dataset.windowSizeClass = `${sizeClass.width}-${sizeClass.height}`;
}

function updateOrientationDataset() {
  document.documentElement.dataset.appOrientation = window.matchMedia("(orientation: landscape)").matches ? "landscape" : "portrait";
}

export function PwaRuntime() {
  const [bridgeState, setBridgeState] = useState(pwaBridgeSnapshot);
  const [updateMessage, setUpdateMessage] = useState("");
  const registrationRef = useRef<ServiceWorkerRegistration | null>(null);
  const expectedWorkerVersionRef = useRef(bridgeState.serviceWorkerVersion);
  const reloadAfterControllerChangeRef = useRef(false);

  useEffect(() => subscribePwaBridge(() => setBridgeState(pwaBridgeSnapshot())), []);

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
      const displayMode = window.matchMedia("(display-mode: fullscreen)").matches
        ? "fullscreen"
        : window.matchMedia("(display-mode: standalone)").matches ||
            window.matchMedia("(display-mode: minimal-ui)").matches ||
            Boolean((navigator as Navigator & { standalone?: boolean }).standalone)
          ? "standalone"
          : "browser";
      document.documentElement.dataset.displayMode = displayMode;
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
    const refreshPolicy = () => {
      setPwaOnlineState(navigator.onLine);
      if (!navigator.onLine) return;
      void flushQueuedClientTelemetry();
      void refreshPwaClientPolicy().catch(() => undefined);
    };
    const onOffline = () => setPwaOnlineState(false);
    const onVisibilityChange = () => {
      if (document.visibilityState === "visible") refreshPolicy();
    };

    refreshPolicy();
    window.addEventListener("online", refreshPolicy);
    window.addEventListener("offline", onOffline);
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => {
      window.removeEventListener("online", refreshPolicy);
      window.removeEventListener("offline", onOffline);
      document.removeEventListener("visibilitychange", onVisibilityChange);
    };
  }, []);

  useEffect(() => {
    if (!canRegisterServiceWorker()) return;
    let disposed = false;

    const activateWaiting = async (registration: ServiceWorkerRegistration) => {
      if (!registration.waiting || !navigator.serviceWorker.controller) return;
      setUpdateMessage("Aplicando actualización...");
      const activated = await activateWaitingServiceWorker({
        pauseWrites: pausePwaWrites,
        registration,
        setExpectedVersion: (version) => {
          expectedWorkerVersionRef.current = version;
          reloadAfterControllerChangeRef.current = true;
          setPwaServiceWorkerVersion(version);
        },
        waitForWrites: () => waitForPwaWrites(30_000),
      });
      if (!activated && !disposed) setUpdateMessage("Actualización pendiente. Termina la operación en curso y vuelve a intentarlo.");
    };

    const watchInstallingWorker = (registration: ServiceWorkerRegistration) => {
      const installing = registration.installing;
      if (!installing) return;
      const onStateChange = () => {
        if (installing.state === "installed" && navigator.serviceWorker.controller) void activateWaiting(registration);
      };
      installing.addEventListener("statechange", onStateChange);
    };

    const registerServiceWorker = async () => {
      try {
        const registration = await navigator.serviceWorker.register("/sw.js", {
          scope: "/",
          updateViaCache: "none",
        });
        if (disposed) return;
        registrationRef.current = registration;
        registration.addEventListener("updatefound", () => watchInstallingWorker(registration));

        const activeVersion = await serviceWorkerVersion(registration.active);
        if (!disposed) setPwaServiceWorkerVersion(activeVersion);
        if (registration.waiting) await activateWaiting(registration);
        await registration.update();
        if (registration.waiting) await activateWaiting(registration);
      } catch {
        if (!disposed) setUpdateMessage("No se pudo comprobar la actualización automática.");
      }
    };

    const onControllerChange = () => {
      if (!reloadAfterControllerChangeRef.current) {
        void serviceWorkerVersion(navigator.serviceWorker.controller).then(setPwaServiceWorkerVersion);
        return;
      }
      reloadAfterControllerChangeRef.current = false;
      const version = expectedWorkerVersionRef.current;
      reloadOnceAfterControllerChange({
        reload: () => window.location.reload(),
        serviceWorkerVersion: version,
        storage: window.sessionStorage,
      });
    };

    navigator.serviceWorker.addEventListener("controllerchange", onControllerChange);
    if (document.readyState === "complete") void registerServiceWorker();
    else window.addEventListener("load", registerServiceWorker, { once: true });

    return () => {
      disposed = true;
      navigator.serviceWorker.removeEventListener("controllerchange", onControllerChange);
      window.removeEventListener("load", registerServiceWorker);
    };
  }, []);

  async function requestUpdate() {
    const registration = registrationRef.current;
    if (!registration) {
      window.location.reload();
      return;
    }

    setUpdateMessage("Buscando actualización...");
    try {
      await registration.update();
      if (!registration.waiting) {
        setUpdateMessage("La actualización se instalará en cuanto esté disponible.");
        return;
      }
      await activateWaitingServiceWorker({
        pauseWrites: pausePwaWrites,
        registration,
        setExpectedVersion: (version) => {
          expectedWorkerVersionRef.current = version;
          reloadAfterControllerChangeRef.current = true;
          setPwaServiceWorkerVersion(version);
        },
        waitForWrites: () => waitForPwaWrites(30_000),
      });
    } catch {
      setUpdateMessage("No se pudo descargar la actualización. Comprueba la conexión.");
    }
  }

  const showUpdateRequired = bridgeState.updateRequired;
  const showConnectionWarning = !showUpdateRequired && bridgeState.offline;
  const showUpdating = !showUpdateRequired && !showConnectionWarning && bridgeState.writesPaused;
  if (!showUpdateRequired && !showConnectionWarning && !showUpdating && !updateMessage) return null;

  return (
    <aside className={`pwa-bridge-notice ${showUpdateRequired ? "update-required" : ""}`} role={showUpdateRequired ? "alert" : "status"}>
      <div>
        <strong>{showUpdateRequired ? "Actualización obligatoria" : showConnectionWarning ? "Sin conexión" : "Actualizando Pachangas IQ"}</strong>
        <span>
          {showUpdateRequired
            ? "Puedes seguir consultando datos, pero necesitas actualizar para guardar cambios."
            : showConnectionWarning
              ? "Los cambios no se mostrarán como confirmados hasta recibir respuesta del servidor."
              : updateMessage || "Esperando a que terminen las operaciones pendientes."}
        </span>
      </div>
      {showUpdateRequired ? <button type="button" onClick={() => void requestUpdate()}>Actualizar ahora</button> : null}
    </aside>
  );
}

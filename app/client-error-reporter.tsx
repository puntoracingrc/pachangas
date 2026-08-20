"use client";

import { useEffect } from "react";
import { sanitizeClientErrorRoute } from "./api/client-error-telemetry/_contract";
import { CLIENT_VERSION } from "./client-version-contract";

const sentAt = new Map<string, number>();

function browserFamily() {
  const agent = navigator.userAgent;
  if (/Edg\//.test(agent)) return "Edge";
  if (/Firefox\//.test(agent)) return "Firefox";
  if (/CriOS|Chrome\//.test(agent)) return "Chrome";
  if (/Safari\//.test(agent)) return "Safari";
  return "Other";
}

function platformFamily() {
  const agent = navigator.userAgent;
  if (/Android/.test(agent)) return "Android";
  if (/iPhone|iPad|iPod/.test(agent)) return "iOS";
  if (/Macintosh/.test(agent)) return "macOS";
  if (/Windows/.test(agent)) return "Windows";
  if (/Linux/.test(agent)) return "Linux";
  return "Other";
}

async function fingerprint(value: string) {
  const bytes = new TextEncoder().encode(value.slice(0, 4000));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((item) => item.toString(16).padStart(2, "0")).join("");
}

async function report(category: "network" | "promise" | "render" | "resource" | "unknown", material: string) {
  if (!navigator.onLine) return;
  const route = sanitizeClientErrorRoute(window.location.pathname);
  if (!route) return;
  const errorFingerprint = await fingerprint(`${category}|${material}`);
  const now = Date.now();
  if (now - (sentAt.get(errorFingerprint) ?? 0) < 60_000) return;
  sentAt.set(errorFingerprint, now);
  void fetch("/api/client-error-telemetry", {
    body: JSON.stringify({
      appVersion: CLIENT_VERSION,
      browserFamily: browserFamily(),
      category,
      fingerprint: errorFingerprint,
      operationId: crypto.randomUUID(),
      platform: platformFamily(),
      route,
    }),
    headers: { "Content-Type": "application/json" },
    keepalive: true,
    method: "POST",
  }).catch(() => undefined);
}

export function ClientErrorReporter() {
  useEffect(() => {
    function onError(event: ErrorEvent) {
      const source = event.error instanceof Error
        ? `${event.error.name}|${event.error.stack ?? "no-stack"}`
        : `${event.filename || "resource"}|${event.lineno}|${event.colno}`;
      void report(event.error ? "render" : "resource", source);
    }
    function onRejection(event: PromiseRejectionEvent) {
      const reason = event.reason instanceof Error ? `${event.reason.name}|${event.reason.stack ?? "no-stack"}` : typeof event.reason;
      void report("promise", reason);
    }
    window.addEventListener("error", onError);
    window.addEventListener("unhandledrejection", onRejection);
    return () => {
      window.removeEventListener("error", onError);
      window.removeEventListener("unhandledrejection", onRejection);
    };
  }, []);
  return null;
}

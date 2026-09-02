export type MarketDataSource = "CACHED" | "IDLE" | "LIVE" | "LOADING" | "UNAVAILABLE";

export type MarketQueryPhase =
  | "CACHED"
  | "IDLE"
  | "LOADING"
  | "OFFLINE_NO_CACHE"
  | "READY_EMPTY"
  | "READY_WITH_RESULTS"
  | "UNAVAILABLE";

export function marketQueryPhase(source: MarketDataSource, resultCount: number, online: boolean): MarketQueryPhase {
  if (source === "CACHED") return "CACHED";
  if (source === "IDLE") return "IDLE";
  if (source === "LOADING") return "LOADING";
  if (source === "UNAVAILABLE") return online ? "UNAVAILABLE" : "OFFLINE_NO_CACHE";
  return resultCount > 0 ? "READY_WITH_RESULTS" : "READY_EMPTY";
}

export function visibleMarketResultCount(phase: MarketQueryPhase, resultCount: number) {
  return phase === "CACHED" || phase === "READY_EMPTY" || phase === "READY_WITH_RESULTS"
    ? resultCount
    : null;
}

export type MarketRequestVisualStatus = "accepted" | "cancelled" | "idle" | "pending" | "rejected" | "sending";

export function marketRequestPresentation(status: MarketRequestVisualStatus) {
  if (status === "sending") return { actionLabel: "Enviando...", detail: "Procesando la simulación local. Remote writes = 0.", statusLabel: "Enviando solicitud", tone: "neutral" as const };
  if (status === "pending") return { actionLabel: "Solicitud enviada", detail: "Registrada en esta sesión Demo. Remote writes = 0.", statusLabel: "Solicitud enviada", tone: "neutral" as const };
  if (status === "accepted") return { actionLabel: "Ver partido", detail: "Confirmada en esta sesión Demo. Remote writes = 0.", statusLabel: "Plaza confirmada", tone: "success" as const };
  if (status === "rejected") return { actionLabel: "Solicitar de nuevo", detail: "No aceptada en esta sesión Demo. Remote writes = 0.", statusLabel: "Solicitud no aceptada", tone: "danger" as const };
  if (status === "cancelled") return { actionLabel: "Solicitar de nuevo", detail: "Cancelada en esta sesión Demo. Remote writes = 0.", statusLabel: "Solicitud cancelada", tone: "neutral" as const };
  return { actionLabel: "Solicitar plaza", detail: null, statusLabel: null, tone: "neutral" as const };
}

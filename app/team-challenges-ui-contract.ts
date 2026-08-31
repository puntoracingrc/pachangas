import type { TeamChallenge } from "./team-social-contract";

export type ChallengeMainView = "active" | "history";
export type ChallengeActiveFilter = "all" | "received" | "sent";

export type ChallengeRouteState = {
  challengeId: string;
  creating: boolean;
  filter: ChallengeActiveFilter;
  legacy: boolean;
  matchChallengeId: string;
  rivalCode: string;
  view: ChallengeMainView;
};

export type ChallengeNotice = {
  body: string;
  stale: boolean;
  title: string;
  tone: "error" | "info" | "success";
};

export type TeamChallengeGroups = {
  agreed: TeamChallenge[];
  history: TeamChallenge[];
  needsResponse: TeamChallenge[];
  waiting: TeamChallenge[];
};

const terminalStatuses = new Set<TeamChallenge["status"]>(["cancelled", "expired", "rejected"]);

export function parseChallengeRoute(search: string): ChallengeRouteState {
  const params = new URLSearchParams(search);
  const legacyView = params.get("vista");
  const requestedView = params.get("view");
  const requestedFilter = params.get("filter");
  const view: ChallengeMainView = requestedView === "history" || legacyView === "history" ? "history" : "active";
  const filter: ChallengeActiveFilter = requestedFilter === "received" || requestedFilter === "sent"
    ? requestedFilter
    : legacyView === "received" || legacyView === "sent"
      ? legacyView
      : "all";
  const rivalCode = params.get("rival")?.trim().toUpperCase() ?? "";

  return {
    challengeId: params.get("reto") ?? "",
    creating: params.get("crear") === "1" || legacyView === "search" || Boolean(rivalCode),
    filter,
    legacy: params.has("vista"),
    matchChallengeId: params.get("retoPartido") ?? "",
    rivalCode,
    view,
  };
}

export function challengeRouteSearch(state: ChallengeRouteState) {
  const params = new URLSearchParams();
  params.set("view", state.view);
  if (state.view === "active" && state.filter !== "all") params.set("filter", state.filter);
  if (state.challengeId) params.set("reto", state.challengeId);
  if (state.matchChallengeId) params.set("retoPartido", state.matchChallengeId);
  if (state.creating) params.set("crear", "1");
  if (state.rivalCode) params.set("rival", state.rivalCode);
  return params.toString();
}

function includedByFilter(challenge: TeamChallenge, filter: ChallengeActiveFilter) {
  return filter === "all"
    || (filter === "received" && challenge.direction === "incoming")
    || (filter === "sent" && challenge.direction === "outgoing");
}

export function groupTeamChallenges(
  challenges: TeamChallenge[],
  filter: ChallengeActiveFilter = "all",
): TeamChallengeGroups {
  const visible = challenges.filter((challenge) => includedByFilter(challenge, filter));
  const pending = visible.filter((challenge) => challenge.status === "proposed" || challenge.status === "changes_proposed");
  return {
    agreed: visible.filter((challenge) => challenge.status === "accepted"),
    history: challenges.filter((challenge) => terminalStatuses.has(challenge.status)),
    needsResponse: pending.filter((challenge) => challenge.lastProposedBy === "opponent"),
    waiting: pending.filter((challenge) => challenge.lastProposedBy === "own"),
  };
}

export function challengeDirectionLabel(challenge: TeamChallenge) {
  if (challenge.status === "accepted") return "Partido acordado";
  if (challenge.lastProposedBy === "own") return "Esperando respuesta";
  if (challenge.status === "changes_proposed") return "Cambios propuestos";
  return challenge.direction === "incoming" ? "Te ha retado" : "Propuesta recibida";
}

export function challengePrimaryLabel(challenge: TeamChallenge, canManage: boolean) {
  if (challenge.status === "accepted") return "Ver partido";
  if (terminalStatuses.has(challenge.status)) return "Ver detalle";
  if (canManage && challenge.lastProposedBy === "opponent") {
    return challenge.status === "changes_proposed" ? "Aceptar cambios" : "Aceptar";
  }
  return challenge.lastProposedBy === "own" ? "Ver propuesta" : "Ver reto";
}

export function safeChallengeError(error: { code?: string | null; message?: string | null } | null | undefined): ChallengeNotice {
  const code = error?.code?.toUpperCase() ?? "";
  const message = error?.message?.toLocaleLowerCase("es") ?? "";
  if (code === "PT409" || /revision|stale|changed|conflict/.test(message)) {
    return { body: "Este reto ha cambiado. Hemos cargado la última propuesta.", stale: true, title: "Propuesta actualizada", tone: "info" };
  }
  if (/not found|no encontrado|team code|código/.test(message)) {
    return { body: "Comprueba el código o busca otro rival.", stale: false, title: "Equipo no encontrado", tone: "error" };
  }
  if (/same group|same team|mismo equipo|itself/.test(message)) {
    return { body: "Elige un equipo distinto al tuyo.", stale: false, title: "Ese rival no es válido", tone: "error" };
  }
  if (/not challengeable|unavailable|no disponible/.test(message)) {
    return { body: "Ese equipo no acepta retos ahora mismo.", stale: false, title: "Rival no disponible", tone: "error" };
  }
  if (/field|venue|campo/.test(message)) {
    return { body: "Añade un campo y su dirección para continuar.", stale: false, title: "Falta el campo", tone: "error" };
  }
  if (/scheduled|date|fecha|future/.test(message)) {
    return { body: "Elige una fecha futura válida.", stale: false, title: "Revisa la fecha", tone: "error" };
  }
  if (/permission|forbidden|admin|owner|not allowed|unauthorized/.test(message)) {
    return { body: "Solo un admin u owner del equipo puede hacer ese cambio.", stale: false, title: "No tienes permiso", tone: "error" };
  }
  if (/terminal|already accepted|already rejected|already cancelled|estado/.test(message)) {
    return { body: "El reto ya tiene un estado definitivo. Hemos actualizado la vista.", stale: true, title: "El reto ya cambió", tone: "info" };
  }
  if (/network|fetch|offline|connection/.test(message)) {
    return { body: "Necesitas conexión para confirmar esta acción.", stale: false, title: "Sin conexión", tone: "error" };
  }
  return { body: "No se ha confirmado ningún cambio. Inténtalo de nuevo.", stale: false, title: "Servicio no disponible", tone: "error" };
}

export function challengeSuccess(body: string): ChallengeNotice {
  return { body, stale: false, title: "Listo", tone: "success" };
}

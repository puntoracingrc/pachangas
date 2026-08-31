export type ProductPrimaryTab = "inicio" | "partido" | "retos" | "mercado" | "competir" | "equipo" | "perfil";

export type SocialCorePrimaryTab = "inicio" | "partido" | "retos" | "mercado";

export type ProductActorPerspective =
  | "player"
  | "team-admin"
  | "team-owner"
  | "club-organizer"
  | "league-organizer"
  | "tournament-organizer"
  | "referee"
  | "free-agent"
  | "platform-reviewer"
  | "platform-admin";

export type ProductNavigationDestination = {
  href: string;
  id: SocialCorePrimaryTab;
  label: string;
  short: string;
};

export type ProductContextualDestination = {
  href: string;
  id: string;
  label: string;
  short: string;
};

export const PRODUCT_PRIMARY_DESTINATIONS: ProductNavigationDestination[] = [
  { href: "/?mobile=inicio", id: "inicio", label: "Inicio", short: "IN" },
  { href: "/?mobile=partido", id: "partido", label: "Partidos", short: "PA" },
  { href: "/retos", id: "retos", label: "Retos", short: "RE" },
  { href: "/mercado", id: "mercado", label: "Mercado", short: "ME" },
];

export const PRODUCT_PORTRAIT_DESTINATIONS = PRODUCT_PRIMARY_DESTINATIONS;

const commonPlayerTools: ProductContextualDestination[] = [
  { href: "/?mobile=equipo", id: "team", label: "Equipo", short: "EQ" },
  { href: "/reservas", id: "reservations", label: "Reservas", short: "RS" },
  { href: "/ranking", id: "ranking", label: "Ranking", short: "RK" },
  { href: "/perfil/avisos", id: "notifications", label: "Avisos", short: "AV" },
];

const organizerTools: ProductContextualDestination[] = [
  { href: "/organizacion/solicitudes", id: "organize", label: "Organizar", short: "OR" },
  { href: "/clubes/gestionar", id: "clubs", label: "Club", short: "CL" },
  { href: "/clubes/gestionar/campos", id: "venues", label: "Campos", short: "CP" },
  { href: "/clubes/gestionar/campos/bloques", id: "season-venues", label: "Temporada", short: "TE" },
  { href: "/clubes/gestionar/reservas", id: "bookings", label: "Reservas", short: "RS" },
  { href: "/ligas", id: "leagues", label: "Ligas", short: "LG" },
  { href: "/torneos", id: "tournaments", label: "Torneos", short: "TR" },
  { href: "/perfil/avisos", id: "notifications", label: "Avisos", short: "AV" },
];

export function contextualDestinationsForPerspective(
  perspective: ProductActorPerspective,
): ProductContextualDestination[] {
  if (perspective === "referee") {
    return [
      { href: "/perfil/arbitro", id: "referee-profile", label: "Ficha arbitral", short: "FA" },
      { href: "/mis-asignaciones-arbitrales", id: "assignments", label: "Asignaciones", short: "AS" },
      { href: "/perfil/avisos", id: "notifications", label: "Avisos", short: "AV" },
    ];
  }
  if (perspective === "platform-admin" || perspective === "platform-reviewer") {
    return [
      { href: "/admin", id: "control-center", label: "Control Center", short: "CC" },
      { href: "/perfil/avisos", id: "notifications", label: "Avisos", short: "AV" },
    ];
  }
  if (
    perspective === "club-organizer"
    || perspective === "league-organizer"
    || perspective === "tournament-organizer"
  ) return organizerTools;
  if (perspective === "team-admin" || perspective === "team-owner") {
    return [
      ...commonPlayerTools,
      { href: "/campos", id: "venues", label: "Campos", short: "CP" },
      { href: "/organizacion/solicitudes", id: "organize", label: "Organizar", short: "OR" },
      { href: "/equipo/estado", id: "team-state", label: "Estado", short: "ES" },
    ];
  }
  if (perspective === "free-agent") {
    return [
      { href: "/mercado", id: "market", label: "Buscar equipo", short: "ME" },
      { href: "/competiciones", id: "competitions", label: "Competiciones", short: "CO" },
      { href: "/perfil/avisos", id: "notifications", label: "Avisos", short: "AV" },
    ];
  }
  return commonPlayerTools;
}

export function productNavigationForViewport(viewport: "desktop" | "landscape" | "portrait") {
  return viewport === "portrait" ? PRODUCT_PORTRAIT_DESTINATIONS : PRODUCT_PRIMARY_DESTINATIONS;
}

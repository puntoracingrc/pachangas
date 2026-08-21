export const platformRoles = [
  "platform_owner",
  "platform_admin",
  "moderator",
  "support",
  "finance",
  "ops",
] as const;

export type PlatformRole = (typeof platformRoles)[number];

export type PlatformAccess = {
  capabilities: string[];
  revision: number;
  role: PlatformRole;
  userId: string;
};

export type PlatformEnvironment = "LOCAL" | "PREVIEW" | "PRODUCTION" | "STAGING";

export const platformRoleLabels: Record<PlatformRole, string> = {
  finance: "Finanzas",
  moderator: "Moderación",
  ops: "Operaciones",
  platform_admin: "Administrador de plataforma",
  platform_owner: "Propietario de plataforma",
  support: "Soporte",
};

export const platformNavigation = [
  { capability: "overview.read", href: "/admin", label: "Resumen" },
  { capability: "users.read", href: "/admin/users", label: "Usuarios" },
  { capability: "teams.read", href: "/admin/teams", label: "Equipos" },
  { capability: "matches.read", href: "/admin/matches", label: "Partidos" },
  { capability: "competitions.read", href: "/admin/competitions", label: "Competiciones" },
  { capability: "challenges.read", href: "/admin/challenges", label: "Retos" },
  { capability: "moderation.read", href: "/admin/conduct", label: "Moderación" },
  { capability: "rankings.read", href: "/admin/rankings", label: "Rankings" },
  { capability: "rewards.read", href: "/admin/rewards", label: "Rewards" },
  { capability: "notifications.read", href: "/admin/notifications", label: "Notificaciones" },
  { capability: "billing.read", href: "/admin/billing", label: "Billing" },
  { capability: "system.read", href: "/admin/system", label: "Sistema" },
  { capability: "flags.read", href: "/admin/flags", label: "Flags" },
  { capability: "audit.read", href: "/admin/audit", label: "Auditoría" },
] as const;

export function isPlatformRole(value: unknown): value is PlatformRole {
  return typeof value === "string" && (platformRoles as readonly string[]).includes(value);
}

export function hasPlatformCapability(access: PlatformAccess, capability: string) {
  return access.capabilities.includes(capability);
}

export function currentPlatformEnvironment(): PlatformEnvironment {
  if (process.env.VERCEL_ENV === "production") return "PRODUCTION";
  if (process.env.VERCEL_ENV === "preview") return "PREVIEW";
  if (process.env.PACHANGAS_ENVIRONMENT?.toLowerCase() === "staging") return "STAGING";
  return "LOCAL";
}

export const TEAM_SHIELD_PREMIUM_BORDER_TEXTURES = {
  copper: "/team-shield-premium-v1/border-copper.9b756acb.webp",
  gold: "/team-shield-premium-v1/border-gold.96413f0c.webp",
  silver: "/team-shield-premium-v1/border-silver.dde0edf8.webp",
} as const;

export type TeamShieldPremiumBorderMaterial = keyof typeof TEAM_SHIELD_PREMIUM_BORDER_TEXTURES;

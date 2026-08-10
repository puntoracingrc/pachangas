export const TEAM_SHIELD_PREMIUM_BALL_KEY = "team.shield.symbol.ball_premium";

export const TEAM_SHIELD_PREMIUM_BALL_FRAMES = [
  "/team-shield-premium-v1/ball-frame-0.c3565074.webp",
  "/team-shield-premium-v1/ball-frame-1.a056b70d.webp",
  "/team-shield-premium-v1/ball-frame-2.1e63053b.webp",
  "/team-shield-premium-v1/ball-frame-3.c29b00c7.webp",
  "/team-shield-premium-v1/ball-frame-4.2571172b.webp",
  "/team-shield-premium-v1/ball-frame-5.7a0354ad.webp",
  "/team-shield-premium-v1/ball-frame-6.dbf823ca.webp",
  "/team-shield-premium-v1/ball-frame-7.21039a34.webp",
] as const;

export const TEAM_SHIELD_PREMIUM_BORDER_TEXTURES = {
  copper: "/team-shield-premium-v1/border-copper.9b756acb.webp",
  gold: "/team-shield-premium-v1/border-gold.96413f0c.webp",
  silver: "/team-shield-premium-v1/border-silver.dde0edf8.webp",
} as const;

export type TeamShieldPremiumBallFrame = (typeof TEAM_SHIELD_PREMIUM_BALL_FRAMES)[number];

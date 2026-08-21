export const OFFICIAL_UI_V2_VERSION = "2.0.0-preview" as const;

export type OfficialLayoutMode = "DESKTOP" | "MOBILE_GAME_LANDSCAPE" | "MOBILE_PORTRAIT";
export type OfficialShellVariant = "PLATFORM_ADMIN" | "PRODUCT";

export type OfficialViewport = {
  coarsePointer: boolean;
  height: number;
  landscape: boolean;
  width: number;
};

export const OFFICIAL_UI_V2_TOKENS = {
  color: {
    accent: "#c8ef5d",
    accentCool: "#51cfdf",
    background: "#07110f",
    border: "rgba(217, 234, 225, 0.16)",
    danger: "#d6535c",
    info: "#4d82d8",
    surfaceElevated: "rgba(18, 29, 26, 0.94)",
    surfaceInteractive: "rgba(32, 48, 42, 0.78)",
    surfacePrimary: "rgba(18, 29, 26, 0.88)",
    textMuted: "#a9bbb2",
    textPrimary: "#f1f6f2",
    warning: "#efbd64",
  },
  content: {
    max: "1440px",
    readable: "720px",
  },
  motion: {
    fast: "140ms",
    standard: "220ms",
  },
  navigation: {
    desktopHeight: "64px",
    landscapeRail: "88px",
    portraitHeight: "68px",
  },
  radius: {
    control: "6px",
    panel: "8px",
    small: "5px",
  },
  space: {
    1: "4px",
    2: "8px",
    3: "12px",
    4: "16px",
    5: "24px",
    6: "32px",
  },
  zIndex: {
    navigation: 80,
    overlay: 140,
    toast: 180,
  },
} as const;

export function resolveOfficialLayoutMode(viewport: OfficialViewport): OfficialLayoutMode {
  const landscapePhone = viewport.landscape
    && viewport.width >= 568
    && viewport.width <= 932
    && viewport.height <= 600;
  const landscapeTouchTablet = viewport.landscape
    && viewport.coarsePointer
    && viewport.width >= 768
    && viewport.width <= 1368
    && viewport.height <= 1024;

  if (landscapePhone || landscapeTouchTablet) return "MOBILE_GAME_LANDSCAPE";
  if (viewport.width <= 760 || (viewport.coarsePointer && viewport.width < 1024)) return "MOBILE_PORTRAIT";
  return "DESKTOP";
}

import {
  DEFAULT_DEMO_WORLD_SESSION,
  assertDemoWorldSnapshot,
  type DemoWorldActivityChunk,
  type DemoWorldCoreChunk,
  type DemoWorldManifest,
  type DemoWorldMatchesChunk,
  type DemoWorldPlayersChunk,
  type DemoWorldPrimaryTab,
  type DemoWorldSessionState,
  type DemoWorldSnapshot,
} from "./demo-world-contract";

const DEMO_WORLD_SESSION_KEY = "pachangas-demo-world-v1-session";
const DEMO_WORLD_PRIMARY_TABS: DemoWorldPrimaryTab[] = ["inicio", "partido", "mercado", "equipo", "perfil"];

async function loadChunk<T>(path: string): Promise<T> {
  const response = await fetch(path, {
    cache: "force-cache",
    credentials: "same-origin",
    method: "GET",
  });
  if (!response.ok) throw new Error(`No se pudo cargar el mundo demo (${response.status}).`);
  return response.json() as Promise<T>;
}

export function loadDemoWorldCore(manifest: DemoWorldManifest): Promise<DemoWorldCoreChunk> {
  return loadChunk<DemoWorldCoreChunk>(manifest.chunks.core);
}

export async function loadDemoWorldSnapshot(manifest: DemoWorldManifest, loadedCore?: DemoWorldCoreChunk): Promise<DemoWorldSnapshot> {
  const [activity, core, matches, players] = await Promise.all([
    loadChunk<DemoWorldActivityChunk>(manifest.chunks.activity),
    loadedCore ? Promise.resolve(loadedCore) : loadDemoWorldCore(manifest),
    loadChunk<DemoWorldMatchesChunk>(manifest.chunks.matches),
    loadChunk<DemoWorldPlayersChunk>(manifest.chunks.players),
  ]);
  return assertDemoWorldSnapshot({ activity, core, manifest, matches, players });
}

function normalizedStringArray(value: unknown) {
  return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string") : [];
}

export function readDemoWorldSession(storage: Pick<Storage, "getItem">): DemoWorldSessionState {
  try {
    const value = JSON.parse(storage.getItem(DEMO_WORLD_SESSION_KEY) ?? "null") as Partial<DemoWorldSessionState> | null;
    if (!value || typeof value !== "object") return structuredClone(DEFAULT_DEMO_WORLD_SESSION);
    const perspectiveId = value.perspectiveId === "admin" || value.perspectiveId === "free-agent" ? value.perspectiveId : "player";
    const attendanceByMatch = value.attendanceByMatch && typeof value.attendanceByMatch === "object"
      ? Object.entries(value.attendanceByMatch).reduce<DemoWorldSessionState["attendanceByMatch"]>((result, [matchId, status]) => {
        if (status === "voy" || status === "duda" || status === "no") result[matchId] = status;
        return result;
      }, {})
      : {};
    return {
      attendanceByMatch,
      equippedCosmeticKeys: normalizedStringArray(value.equippedCosmeticKeys),
      inventoryCosmeticKeys: normalizedStringArray(value.inventoryCosmeticKeys),
      newCosmeticKeys: normalizedStringArray(value.newCosmeticKeys),
      openedBoxIds: normalizedStringArray(value.openedBoxIds),
      perspectiveId,
      readNotificationIds: normalizedStringArray(value.readNotificationIds),
    };
  } catch {
    return structuredClone(DEFAULT_DEMO_WORLD_SESSION);
  }
}

export function demoWorldTabFromSearch(search: string): DemoWorldPrimaryTab {
  const requestedTab = new URLSearchParams(search).get("tab");
  return DEMO_WORLD_PRIMARY_TABS.includes(requestedTab as DemoWorldPrimaryTab)
    ? requestedTab as DemoWorldPrimaryTab
    : "inicio";
}

export function readInitialDemoWorldSession(
  search: string,
  storage?: Pick<Storage, "getItem">,
): DemoWorldSessionState {
  const state = storage ? readDemoWorldSession(storage) : structuredClone(DEFAULT_DEMO_WORLD_SESSION);
  const requestedPerspective = new URLSearchParams(search).get("perspective");
  if (requestedPerspective === "admin" || requestedPerspective === "player" || requestedPerspective === "free-agent") {
    state.perspectiveId = requestedPerspective;
  }
  return state;
}

export function writeDemoWorldSession(storage: Pick<Storage, "setItem">, state: DemoWorldSessionState) {
  storage.setItem(DEMO_WORLD_SESSION_KEY, JSON.stringify(state));
}

export function resetDemoWorldSession(storage: Pick<Storage, "removeItem">) {
  storage.removeItem(DEMO_WORLD_SESSION_KEY);
  return structuredClone(DEFAULT_DEMO_WORLD_SESSION);
}

export function demoAvatarDataUri(name: string, hue: number) {
  const initials = name.split(/\s+/).slice(0, 2).map((part) => part[0]?.toUpperCase() ?? "").join("");
  const safeInitials = initials.replace(/[^A-ZÁÉÍÓÚÜÑ]/g, "").slice(0, 2) || "IQ";
  const normalizedHue = Math.round(((hue % 360) + 360) % 360);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 300"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop stop-color="hsl(${normalizedHue} 58% 42%)"/><stop offset="1" stop-color="hsl(${(normalizedHue + 42) % 360} 52% 18%)"/></linearGradient></defs><rect width="240" height="300" fill="url(#g)"/><circle cx="120" cy="104" r="52" fill="rgba(255,255,255,.24)"/><path d="M34 300c8-79 56-119 86-119s78 40 86 119" fill="rgba(255,255,255,.2)"/><text x="120" y="123" text-anchor="middle" font-family="Arial,sans-serif" font-size="44" font-weight="800" fill="white">${safeInitials}</text></svg>`;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}

export function demoWorldSessionKey() {
  return DEMO_WORLD_SESSION_KEY;
}

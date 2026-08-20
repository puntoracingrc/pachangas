export const clientErrorCategories = ["network", "promise", "render", "resource", "unknown"] as const;
export type ClientErrorCategory = (typeof clientErrorCategories)[number];

export type ClientErrorTelemetry = {
  appVersion: string;
  browserFamily: string;
  category: ClientErrorCategory;
  fingerprint: string;
  operationId: string;
  platform: string;
  route: string;
};

const keys = new Set<keyof ClientErrorTelemetry>(["appVersion", "browserFamily", "category", "fingerprint", "operationId", "platform", "route"]);
const categories = new Set<string>(clientErrorCategories);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const fingerprintPattern = /^[0-9a-f]{16,128}$/i;
const dynamicRoutePatterns: Array<[RegExp, string]> = [
  [/^\/admin\/users\/[^/]+\/?$/, "/admin/users/:userId"],
  [/^\/admin\/teams\/[^/]+\/?$/, "/admin/teams/:teamId"],
  [/^\/admin\/challenges\/[^/]+\/?$/, "/admin/challenges/:challengeId"],
  [/^\/admin\/matches\/[^/]+\/[^/]+\/?$/, "/admin/matches/:groupId/:matchId"],
  [/^\/invitacion\/(admin|grupo|partido)\/[^/]+\/?$/, "/invitacion/$1/:token"],
  [/^\/partido\/[^/]+\/[^/]+\/?$/, "/partido/:teamCode/:matchId"],
];

function shortText(value: unknown, maximum: number) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum ? value : null;
}

export function sanitizeClientErrorRoute(value: unknown) {
  const route = shortText(value, 240);
  if (!route || !route.startsWith("/") || route.includes("?") || route.includes("#")) return null;
  for (const [pattern, replacement] of dynamicRoutePatterns) {
    if (pattern.test(route)) return route.replace(pattern, replacement);
  }
  return route
    .split("/")
    .map((segment) => {
      if (!segment) return segment;
      if (uuidPattern.test(segment) || /@|%40/i.test(segment) || /^[A-Za-z0-9_-]{24,}$/.test(segment)) return ":segment";
      return segment;
    })
    .join("/");
}

export function sanitizeClientErrorTelemetry(value: unknown): ClientErrorTelemetry | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !keys.has(key as keyof ClientErrorTelemetry))) return null;
  const appVersion = shortText(record.appVersion, 80);
  const browserFamily = shortText(record.browserFamily, 40);
  const fingerprint = shortText(record.fingerprint, 128);
  const operationId = shortText(record.operationId, 36);
  const platform = shortText(record.platform, 40);
  const route = sanitizeClientErrorRoute(record.route);
  if (!appVersion || !browserFamily || !fingerprint || !operationId || !platform || !route) return null;
  if (!categories.has(String(record.category)) || !uuidPattern.test(operationId) || !fingerprintPattern.test(fingerprint)) return null;
  return { appVersion, browserFamily, category: record.category as ClientErrorCategory, fingerprint, operationId, platform, route };
}

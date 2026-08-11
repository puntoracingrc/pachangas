import "server-only";

import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";
import { notFound } from "next/navigation";
import { cookies } from "next/headers";
import { cache } from "react";
import { noStoreHeaders } from "../../api/client-policy/_contract";
import {
  hasPlatformCapability,
  isPlatformRole,
  type PlatformAccess,
} from "./platform-contract";

export const PLATFORM_ADMIN_COOKIE = "pachangas-platform-admin";
export const PLATFORM_ADMIN_REQUEST_HEADER = "x-pachangas-platform-admin";

export class PlatformAccessError extends Error {
  constructor(
    message: string,
    public readonly status: 401 | 403 = 403,
  ) {
    super(message);
    this.name = "PlatformAccessError";
  }
}

function requiredEnvironment(name: string) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

export function platformServiceClient() {
  return createClient(
    requiredEnvironment("NEXT_PUBLIC_SUPABASE_URL"),
    requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

export function platformUserClient(token: string) {
  return createClient(
    requiredEnvironment("NEXT_PUBLIC_SUPABASE_URL"),
    requiredEnvironment("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"),
    {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    },
  );
}

function normalizeAccess(value: unknown): PlatformAccess | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (typeof record.userId !== "string" || !isPlatformRole(record.role)) return null;
  if (!Array.isArray(record.capabilities) || record.capabilities.some((item) => typeof item !== "string")) return null;
  return {
    capabilities: record.capabilities as string[],
    revision: Number(record.revision) || 1,
    role: record.role,
    userId: record.userId,
  };
}

export type VerifiedPlatformSession = {
  access: PlatformAccess;
  client: SupabaseClient;
  token: string;
  user: User;
};

export async function verifyPlatformToken(token: string, capability?: string): Promise<VerifiedPlatformSession> {
  if (!token) throw new PlatformAccessError("Authentication required", 401);
  const client = platformUserClient(token);
  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new PlatformAccessError("Invalid session", 401);

  const accessResult = await client.rpc("get_my_pachanga_platform_access_v1");
  const access = accessResult.error ? null : normalizeAccess(accessResult.data);
  if (!access || access.userId !== userResult.data.user.id) {
    throw new PlatformAccessError("Platform access required", 403);
  }
  if (capability && !hasPlatformCapability(access, capability)) {
    throw new PlatformAccessError("Platform capability required", 403);
  }
  return { access, client, token, user: userResult.data.user };
}

function cookieToken(cookieHeader: string | null) {
  if (!cookieHeader) return "";
  const encoded = cookieHeader
    .split(";")
    .map((item) => item.trim())
    .find((item) => item.startsWith(`${PLATFORM_ADMIN_COOKIE}=`))
    ?.slice(PLATFORM_ADMIN_COOKIE.length + 1);
  if (!encoded) return "";
  try {
    return decodeURIComponent(encoded);
  } catch {
    return "";
  }
}

export function tokenFromPlatformRequest(request: Request) {
  const authorization = request.headers.get("authorization") ?? "";
  const bearer = authorization.replace(/^Bearer\s+/i, "").trim();
  return bearer || cookieToken(request.headers.get("cookie"));
}

export async function requirePlatformRequest(request: Request, capability?: string) {
  return verifyPlatformToken(tokenFromPlatformRequest(request), capability);
}

export const platformAccessFromCookies = cache(async () => {
  const store = await cookies();
  const token = store.get(PLATFORM_ADMIN_COOKIE)?.value ?? "";
  if (!token) return null;
  try {
    return await verifyPlatformToken(token);
  } catch {
    return null;
  }
});

export async function requirePlatformPage(capability?: string) {
  const session = await platformAccessFromCookies();
  if (!session || (capability && !hasPlatformCapability(session.access, capability))) notFound();
  return session;
}

export function requireSameOriginMutation(request: Request) {
  if (request.method === "GET" || request.method === "HEAD") return;
  const origin = request.headers.get("origin");
  const expectedOrigin = new URL(request.url).origin;
  if (!origin || origin !== expectedOrigin) throw new PlatformAccessError("Invalid request origin", 403);
  if (request.headers.get(PLATFORM_ADMIN_REQUEST_HEADER) !== "1") {
    throw new PlatformAccessError("Admin request confirmation required", 403);
  }
}

export function platformJson(data: unknown, init?: ResponseInit) {
  const headers = new Headers(init?.headers);
  Object.entries(noStoreHeaders).forEach(([key, value]) => headers.set(key, value));
  headers.set("X-Robots-Tag", "noindex, nofollow");
  return Response.json(data, { ...init, headers });
}

export function platformErrorResponse(error: unknown) {
  if (error instanceof PlatformAccessError) {
    return platformJson({ error: "ADMIN_ACCESS_DENIED" }, { status: error.status });
  }
  const message = error instanceof Error ? error.message : "Unexpected admin error";
  if (/changed before saving|stale revision|revision mismatch/i.test(message)) {
    return platformJson({ error: "ADMIN_STALE_REVISION", message: "El estado ha cambiado. Recarga los datos antes de repetir la acción." }, { status: 409 });
  }
  if (/not found/i.test(message)) {
    return platformJson({ error: "ADMIN_NOT_FOUND", message: "El recurso solicitado no existe." }, { status: 404 });
  }
  if (/authentication required|platform access required|platform capability required|permission denied/i.test(message)) {
    return platformJson({ error: "ADMIN_ACCESS_DENIED" }, { status: 403 });
  }
  if (/^invalid\b/i.test(message)) {
    return platformJson({ error: "ADMIN_INVALID_REQUEST", message: "La solicitud no es válida." }, { status: 400 });
  }
  const safeMessage = /Missing [A-Z0-9_]+/.test(message)
    ? "Admin integration is not configured"
    : "La operacion administrativa no pudo completarse.";
  return platformJson({ error: "ADMIN_REQUEST_FAILED", message: safeMessage }, { status: 500 });
}

const loopbackHosts = new Set(["127.0.0.1", "localhost", "::1", "[::1]"]);

export class SyntheticWorldEnvironmentError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SyntheticWorldEnvironmentError";
  }
}

function loopbackUrl(value: string | undefined, label: string) {
  if (!value) throw new SyntheticWorldEnvironmentError(`${label} is required`);
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new SyntheticWorldEnvironmentError(`${label} must be an absolute URL`);
  }
  if (!loopbackHosts.has(parsed.hostname)) {
    throw new SyntheticWorldEnvironmentError(`${label} must use a loopback host`);
  }
  return parsed;
}

export function assertSyntheticWorldEnvironment(
  env: NodeJS.ProcessEnv = process.env,
  requestUrl?: string,
) {
  if (env.PACHANGAS_SYNTHETIC_WORLD !== "1") {
    throw new SyntheticWorldEnvironmentError("PACHANGAS_SYNTHETIC_WORLD=1 is required");
  }
  if (env.VERCEL_ENV || env.CF_PAGES || env.NODE_ENV === "production") {
    throw new SyntheticWorldEnvironmentError("Synthetic World is disabled in hosted or production environments");
  }

  const supabase = loopbackUrl(env.NEXT_PUBLIC_SUPABASE_URL, "NEXT_PUBLIC_SUPABASE_URL");
  const app = loopbackUrl(env.NEXT_PUBLIC_APP_URL ?? "http://127.0.0.1:3090", "NEXT_PUBLIC_APP_URL");
  if (requestUrl) loopbackUrl(requestUrl, "request URL");
  if (!env.SUPABASE_SERVICE_ROLE_KEY?.trim()) {
    throw new SyntheticWorldEnvironmentError("SUPABASE_SERVICE_ROLE_KEY is required locally");
  }
  if (env.STRIPE_SECRET_KEY || env.GOOGLE_WEATHER_API_KEY || env.RESEND_API_KEY) {
    throw new SyntheticWorldEnvironmentError("External production integrations must be absent in Synthetic World");
  }

  return {
    appUrl: app.origin,
    isolated: true as const,
    supabaseUrl: supabase.origin,
  };
}

export function syntheticWorldPageEnabled(env: NodeJS.ProcessEnv = process.env) {
  try {
    assertSyntheticWorldEnvironment(env);
    return true;
  } catch {
    return false;
  }
}

export function syntheticWorldAdminEnabled(env: NodeJS.ProcessEnv = process.env) {
  return env.PACHANGAS_SYNTHETIC_ADMIN === "1" && syntheticWorldPageEnabled(env);
}

import { SYNTHETIC_SEASON_SEED } from "../../app/demo-world/demo-world-v3-2-contract";

export const SYNTHETIC_SEASON_CONFIRMATION = "SYNTHETIC_SEASON_EPHEMERAL_ONLY" as const;
export const PACHANGAS_PRODUCTION_PROJECT_REF = "qonbngfrnrqgmxbdfbea" as const;

function firstValue(environment: NodeJS.ProcessEnv, keys: string[]) {
  return keys.map((key) => environment[key]?.trim()).find(Boolean) ?? "";
}

function isLoopbackUrl(raw: string) {
  try {
    const url = new URL(raw);
    return ["127.0.0.1", "::1", "localhost"].includes(url.hostname);
  } catch {
    return false;
  }
}

export function syntheticSeasonEnvironmentErrors(environment: NodeJS.ProcessEnv) {
  const errors: string[] = [];
  const confirmation = environment.SYNTHETIC_SEASON_CONFIRM?.trim();
  const seed = environment.SYNTHETIC_SEASON_SEED?.trim() || SYNTHETIC_SEASON_SEED;
  const namespace = environment.SYNTHETIC_SEASON_NAMESPACE?.trim() || "";
  const targetUrl = firstValue(environment, ["SYNTHETIC_SEASON_DATABASE_URL", "PACHANGAS_SYNTHETIC_DB_URL", "SUPABASE_DB_URL"]);
  const projectRef = firstValue(environment, ["SYNTHETIC_SEASON_EPHEMERAL_REF", "SUPABASE_PROJECT_REF"]);
  const nonSyntheticUsers = Number(environment.SYNTHETIC_SEASON_NON_SYNTHETIC_USERS ?? "0");
  const ledger = Number(environment.SYNTHETIC_SEASON_MIGRATION_LEDGER ?? "212");

  if (confirmation !== SYNTHETIC_SEASON_CONFIRMATION) errors.push("SYNTHETIC_SEASON_CONFIRMATION_REQUIRED");
  if (seed !== SYNTHETIC_SEASON_SEED) errors.push("SYNTHETIC_SEASON_SEED_MISMATCH");
  if (!namespace.startsWith("synthetic-season-v1")) errors.push("SYNTHETIC_SEASON_NAMESPACE_NOT_ALLOWLISTED");
  if (ledger !== 212) errors.push("SYNTHETIC_SEASON_LEDGER_MISMATCH");
  if (!Number.isFinite(nonSyntheticUsers) || nonSyntheticUsers !== 0) errors.push("SYNTHETIC_SEASON_NON_SYNTHETIC_USERS_PRESENT");
  if (projectRef === PACHANGAS_PRODUCTION_PROJECT_REF || targetUrl.includes(PACHANGAS_PRODUCTION_PROJECT_REF)) errors.push("SYNTHETIC_SEASON_PRODUCTION_TARGET_BLOCKED");
  if (targetUrl && !isLoopbackUrl(targetUrl) && (!projectRef || !targetUrl.includes(projectRef))) errors.push("SYNTHETIC_SEASON_TARGET_NOT_EPHEMERAL");
  if (!targetUrl && !projectRef) errors.push("SYNTHETIC_SEASON_EPHEMERAL_TARGET_REQUIRED");

  const publicSecretKeys = Object.keys(environment).filter((key) => (
    /^(?:NEXT_PUBLIC|PUBLIC)_/.test(key)
    && /SERVICE_ROLE|STRIPE_SECRET|DATABASE_URL|SUPABASE_DB/i.test(key)
    && Boolean(environment[key])
  ));
  if (publicSecretKeys.length) errors.push("SYNTHETIC_SEASON_PUBLIC_SECRET_DETECTED");
  if (firstValue(environment, ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET", "STRIPE_RESTRICTED_KEY"])) errors.push("SYNTHETIC_SEASON_STRIPE_ENV_BLOCKED");
  return errors;
}

export function assertSyntheticSeasonEnvironment(environment: NodeJS.ProcessEnv) {
  const errors = syntheticSeasonEnvironmentErrors(environment);
  if (errors.length) throw new Error(errors.join("\n"));
  return {
    ledger: 212 as const,
    namespace: environment.SYNTHETIC_SEASON_NAMESPACE!,
    productionBlocked: true,
    seed: SYNTHETIC_SEASON_SEED,
  };
}

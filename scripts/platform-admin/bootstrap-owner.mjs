import { randomUUID } from "node:crypto";
import process from "node:process";
import { createClient } from "@supabase/supabase-js";

function argument(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1]?.trim() ?? "" : "";
}

function requiredEnvironment(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

const environment = (process.env.PACHANGAS_ENVIRONMENT ?? "local").trim().toLowerCase();
const isProduction = environment === "production" || process.env.VERCEL_ENV === "production";
const requestedUserId = argument("user-id");
const requestedEmail = argument("email");
const requiredProvider = argument("required-provider").toLowerCase();
const expectedProjectRef = argument("expected-project-ref");
const productionConfirmation = argument("confirm-production-bootstrap");
const reason = argument("reason");
const requestedOperationId = argument("operation-id");
const operationId = requestedOperationId || randomUUID();
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

if (isProduction) {
  if (productionConfirmation !== "I_UNDERSTAND_PRODUCTION") {
    throw new Error("Production owner bootstrap requires explicit confirmation");
  }
  if (!emailPattern.test(requestedEmail)) throw new Error("Pass a valid --email for production resolution");
  if (!requiredProvider) throw new Error("Pass --required-provider for production resolution");
  if (!expectedProjectRef) throw new Error("Pass --expected-project-ref for production verification");
  if (!uuidPattern.test(requestedOperationId)) {
    throw new Error("Production bootstrap requires an explicit --operation-id UUID");
  }
  if (requestedUserId) throw new Error("Production bootstrap resolves the user server-side; do not pass --user-id");
} else if (!uuidPattern.test(requestedUserId)) {
  throw new Error("Pass a valid --user-id UUID");
}

if (!uuidPattern.test(operationId)) throw new Error("Pass a valid --operation-id UUID or omit it");
if (reason.length < 3 || reason.length > 1200) throw new Error("Pass --reason with 3 to 1200 characters");

const supabaseUrl = requiredEnvironment("NEXT_PUBLIC_SUPABASE_URL");
if (isProduction) {
  const hostname = new URL(supabaseUrl).hostname;
  if (hostname !== `${expectedProjectRef}.supabase.co`) {
    throw new Error("Supabase project does not match --expected-project-ref");
  }
}

const client = createClient(
  supabaseUrl,
  requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);

async function resolveProductionUser(email, provider) {
  const matches = [];
  const perPage = 1000;
  for (let page = 1; page <= 10000; page += 1) {
    const listed = await client.auth.admin.listUsers({ page, perPage });
    if (listed.error) throw new Error("Unable to resolve the production Auth user");
    const users = listed.data.users ?? [];
    matches.push(...users.filter((user) => user.email === email));
    if (users.length < perPage) break;
    if (page === 10000) throw new Error("Production Auth user scan exceeded the safety limit");
  }
  if (matches.length !== 1) {
    throw new Error(`Production Auth resolution returned ${matches.length} exact matches`);
  }

  const [user] = matches;
  if (!user.email_confirmed_at && !user.confirmed_at) throw new Error("Production Auth email is not confirmed");
  if (!user.identities?.some((identity) => identity.provider?.toLowerCase() === provider)) {
    throw new Error("Production Auth required provider is missing");
  }
  if (user.aud && user.aud !== "authenticated") throw new Error("Production Auth user is not active");
  if (user.deleted_at) throw new Error("Production Auth user is deleted");
  if (user.banned_until && new Date(user.banned_until).getTime() > Date.now()) {
    throw new Error("Production Auth user is banned");
  }
  return user;
}

const resolvedUser = isProduction
  ? await resolveProductionUser(requestedEmail, requiredProvider)
  : { id: requestedUserId };

const parameters = {
  operation_id: operationId,
  reason,
  target_user_id: resolvedUser.id,
};
const first = await client.rpc("bootstrap_pachanga_platform_owner_v1", parameters);
if (first.error) throw new Error(`Bootstrap rejected: ${first.error.message}`);
const replay = await client.rpc("bootstrap_pachanga_platform_owner_v1", parameters);
if (replay.error) throw new Error(`Bootstrap replay rejected: ${replay.error.message}`);
if (JSON.stringify(first.data) !== JSON.stringify(replay.data)) {
  throw new Error("Bootstrap replay did not converge to the original response");
}

const access = await client.rpc("get_pachanga_platform_access_service_v1", {
  target_user_id: resolvedUser.id,
});
if (access.error || access.data?.role !== "platform_owner" || access.data?.userId !== resolvedUser.id) {
  throw new Error("Platform owner authority could not be verified after bootstrap");
}

process.stdout.write(`${JSON.stringify({
  environment: isProduction ? "production" : environment,
  operationId,
  targetUserId: resolvedUser.id,
  emailVerified: isProduction,
  providerVerified: isProduction ? requiredProvider : null,
  replayVerified: true,
  result: first.data,
  access: access.data,
}, null, 2)}\n`);

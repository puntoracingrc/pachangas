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
if (environment === "production" || process.env.VERCEL_ENV === "production") {
  throw new Error("Owner bootstrap is disabled for production in Platform Control Center V1");
}

const userId = argument("user-id");
const reason = argument("reason");
const operationId = argument("operation-id") || randomUUID();
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

if (!uuidPattern.test(userId)) throw new Error("Pass a valid --user-id UUID");
if (!uuidPattern.test(operationId)) throw new Error("Pass a valid --operation-id UUID or omit it");
if (reason.length < 3 || reason.length > 1200) throw new Error("Pass --reason with 3 to 1200 characters");

const client = createClient(
  requiredEnvironment("NEXT_PUBLIC_SUPABASE_URL"),
  requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { autoRefreshToken: false, persistSession: false } },
);
const result = await client.rpc("bootstrap_pachanga_platform_owner_v1", {
  operation_id: operationId,
  reason,
  target_user_id: userId,
});
if (result.error) throw new Error(`Bootstrap rejected: ${result.error.message}`);

process.stdout.write(`${JSON.stringify({ environment, operationId, result: result.data }, null, 2)}\n`);
